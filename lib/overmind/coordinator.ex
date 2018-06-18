defmodule Overmind.Coordinator do
  require Logger
  import Overmind.Utils
  alias Overmind.ZnodeStat
  alias Overmind.Coordinator.Cluster
  alias Overmind.Coordinator.Data

  # use GenStateMachine, callback_mode: :state_functions
  # NOTE state_enter functions aren't allowed to set next_event actions
  # use GenStateMachine, callback_mode: [:handle_event_function, :state_enter]
  use GenStateMachine, callback_mode: [:handle_event_function]

  @moduledoc """
  What `#{__MODULE__}` does:
  - holds the pid of ZK client for other modules to use (I don't think you can
    register a monitor for it retrospectively)
  - tracks ZK connection status
  - registers the current node as available
  - watches the current cluster members and the pending cluster members to
    announce it to the node's workers
  - tries to become a leader, is a follower otherwise
  - if the leader, tracks the nodes' readiness to follow the pending_cluster
    structure and switches it out as the current_cluster once everyone's ready

  All coordination is done through Zookeeper.

  Here's an example situation showing which zookeeper paths we're using.
  (All are under chroot):

      /available_nodes # normal znode, generated as part of setup
      /available_nodes/foo@somewhere # ephemeral znode created by the node when it connects to the
                       # ZK cluster
        - data: 2 # the data means the latest (pending_)cluster version it's ready for
      /available_nodes/bar@somewhere
        - data: 3
      /available_nodes/baz@somewhere
        - data: 3
      /leaders # normal znode, generated as setup, used for leader election
      /leaders/bar@somewhere-0000000002 # ephemeral_sequential, the lowest index is the leader
      /leaders/foo@somewhere-0000000003
      /leaders/baz@somewhere-0000000004
      /current_cluster # persistent, generated as part of setup, but overwritten by leaders
        - data: 2:foo@somewhere,bar@somewhere # the 2 at the beginning means the zk version of pending_cluster it was based off of
      /pending_cluster # persistent, generated as part of setup, empty data
                       # means no cluster structure is pending. Leaders set
                       # this to the pending cluster structure
        - data: foo@somewhere,bar@somewhere,baz@somewhere
        - version: 3

  So in this situation `bar@somewhere` is the current leader, the current
  cluster is `foo` and `bar`, and the leader is in the process of changing it
  to `foo`, `bar` and `baz`. `bar` and `baz` are ready for the change (version 3)
  but `foo` isn't yet.

  **NOTE**: It is possible that the leader is not ready for the pending cluster
  they themselves have proposed. That's because it's the rest of the node's
  system that gets ready, not the coordinator themself and it is an asynchronous
  operation.

  ![Coordinator state machine diagram](assets/coordinator.png)
  """

  # TODO maybe add :uninitialized for before the client has connected at all?
  # that would save us fro blowing up in init() if the zk cluster is unreachable
  @type state :: :disconnected | :leading | :following
  @opts [:notification_targets, :zk_servers, :chroot_path, :self_node, :subscribers]

  @zk_host {'localhost', 2181}
  @default_chroot_path "/overmind"

  # typo protection
  @available_nodes "/available_nodes"
  @leaders "/leaders"
  @leaders_charlist String.to_charlist(@leaders)
  @current_cluster "/current_cluster"
  @pending_cluster "/pending_cluster"

  # ==========================================================================
  # Public API
  # ==========================================================================

  def get_state_and_data(coordinator) do
    GenStateMachine.call(coordinator, :get_state_and_data)
  end

  def node_ready(coordinator, cluster_version) do
    GenStateMachine.cast(coordinator, {:node_ready, cluster_version})
  end

  # ==========================================================================
  # Callbacks
  # ==========================================================================

  def start_link(opts) do
    {coordinator_opts, gsm_opts} = Keyword.split(opts, @opts)
    GenStateMachine.start_link(__MODULE__, coordinator_opts, gsm_opts)
  end

  def start(opts) do
    {coordinator_opts, gsm_opts} = Keyword.split(opts, @opts)
    GenStateMachine.start(__MODULE__, coordinator_opts, gsm_opts)
  end

  @impl true
  def init(opts) do
    Logger.info("Overmind.Coordinator initializing")
    zk_servers = Keyword.fetch!(opts, :zk_servers)
    chroot_path = Keyword.get(opts, :chroot_path, @default_chroot_path)
    # for tests mainly
    self_node = Keyword.get(opts, :self_node, Node.self())
    subscribers = Keyword.get(opts, :subscribers, [])

    # chroot path needs to be created in advance
    {:ok, root_client_pid} = :erlzk.connect(zk_servers, 30000, [])
    ensure_znode(root_client_pid, chroot_path)
    :ok = :erlzk.close(root_client_pid)

    # the actual erlzk client
    {:ok, client_pid} = :erlzk.connect([@zk_host], 30000, chroot: chroot_path, monitor: self())
    suicide_pact(client_pid)
    Logger.info("Overmind.Coordinator connected")

    ensure_znode(client_pid, @available_nodes)
    ensure_znode(client_pid, @leaders)
    ensure_znode(client_pid, @current_cluster, "-1:")
    ensure_znode(client_pid, @pending_cluster)
    Logger.info("Overmind.Coordinator created prerequisite paths")

    data = %Data{
      Data.new()
      | self_node: self_node,
        client_pid: client_pid,
        subscribers: subscribers
    }

    {:ok, :disconnected, data, []}
  end

  # --------------------------------------------------------------------------
  # Disconnected state
  # --------------------------------------------------------------------------

  @impl true
  def handle_event(:info, {:connected, _ip, _port}, :disconnected, data) do
    Logger.info("Overmind.Coordinator registering itself")
    my_available_path = Path.join(@available_nodes, Atom.to_string(data.self_node))

    # NOTE if the previous instance of this node has disconnected recently, the
    # node might still be there, consider retries maybe
    {:ok, _path} = :erlzk.create(data.client_pid, my_available_path, "-1", :ephemeral)

    my_leaders_path = "#{@leaders}/#{data.self_node}-"

    {:ok, @leaders_charlist ++ '/' ++ my_leader_node} =
      :erlzk.create(data.client_pid, my_leaders_path, :ephemeral_sequential)

    {:ok, leaders} = :erlzk.get_children(data.client_pid, @leaders)
    true = my_leader_node in leaders
    data = Data.set_leader_node(data, List.to_string(my_leader_node))

    if get_leader(leaders) == my_leader_node do
      Logger.info("I'm going to be a leader!")
      {:ok, {current_cluster_data, _stat}} = :erlzk.get_data(data.client_pid, @current_cluster)

      current_cluster = Cluster.from_current_cluster_data(current_cluster_data)

      {data, true} = Data.current_cluster_changed(data, current_cluster)
      # pretending available nodes changed to bootstrap the leading state
      {:next_state, :leading, data, [info({:node_children_changed, @available_nodes})]}
    else
      Logger.info("I'm going to be a follower!")
      # TODO fetch&subscribe current and pending nodes
      # TODO broadcast

      {:next_state, :following, data}
    end
  end

  # --------------------------------------------------------------------------
  # Leading state
  # --------------------------------------------------------------------------

  def handle_event(:info, {:node_children_changed, @available_nodes}, :leading, data) do
    Logger.info("available nodes changed watcher triggered")
    # immediately re-setting the watcher
    {:ok, available_nodes} = :erlzk.get_children(data.client_pid, @available_nodes, self())
    available_nodes = Enum.map(available_nodes, &List.to_string/1)
    # forwarding the info to the actual handler
    {:next_state, :leading, data, [internal({:available_nodes_changed, available_nodes})]}
  end

  def handle_event(:internal, {:available_nodes_changed, available_nodes}, :leading, data) do
    Logger.info("available nodes changed")
    pending_cluster = Cluster.new(available_nodes, -13)

    pending_cluster_data = Cluster.to_pending_cluster_data(pending_cluster)
    {:ok, _} = :erlzk.set_data(data.client_pid, @pending_cluster, pending_cluster_data)
    {:ok, {^pending_cluster_data, stat}} = :erlzk.get_data(data.client_pid, @pending_cluster)
    stat = ZnodeStat.new(stat)

    pending_cluster = Cluster.from_pending_cluster_data(stat.version, pending_cluster_data)

    {data, true} = Data.pending_cluster_changed(data, pending_cluster)
    broadcast_cluster(data)

    available_node_changed_actions =
      data.pending_cluster.nodes
      |> Enum.map(fn available_node ->
        node_path = Path.join(@available_nodes, Atom.to_string(available_node))
        # :erlzk is awesome and deduplicates duplicate watchches with same path and pid
        # it's ok to set the watch blindly even if there is one set already
        {:ok, {data, _stat}} = :erlzk.get_data(data.client_pid, node_path, self())
        internal({:available_node_changed, available_node, String.to_integer(data)})
      end)

    {:next_state, :leading, data, available_node_changed_actions}
  end

  def handle_event(
        :info,
        {:node_data_changed, node_path = @available_nodes <> "/" <> node_name},
        :leading,
        data
      ) do
    {:ok, {version_string, _stat}} = :erlzk.get_data(data.client_pid, node_path, self())

    actions = [
      internal(
        {:available_node_changed, String.to_atom(node_name), String.to_integer(version_string)}
      )
    ]

    {:next_state, :leading, data, actions}
  end

  def handle_event(:internal, {:available_node_changed, node_atom, version}, :leading, data) do
    Logger.info("handling available node changed #{node_atom} went to #{version}")
    {data, changed} = Data.available_node_changed(data, node_atom, version)

    if changed do
      broadcast_cluster(data)
    end

    {:next_state, :leading, data}
  end

  def handle_event(:cast, {:node_ready, cluster_version}, state, data)
      when state in [:leading, :following] do
    my_available_path = Path.join(@available_nodes, Atom.to_string(data.self_node))
    version_string = Integer.to_string(cluster_version)
    {:ok, _path} = :erlzk.set_data(data.client_pid, my_available_path, version_string)
    :keep_state_and_data
  end

  # --------------------------------------------------------------------------
  # Other / generic
  # --------------------------------------------------------------------------

  def handle_event({:call, from}, :get_state_and_data, state, data) do
    GenStateMachine.reply(from, {state, data})
    :keep_state_and_data
  end

  def handle_event(event_type, event_content, state, _data) do
    Logger.warn(
      "Coordinator OTHER_EVENT at #{inspect(state)}: #{inspect({event_type, event_content})}"
    )

    :keep_state_and_data
  end

  def child_spec(:child_spec_arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [:start_link_arg]}
    }
  end

  # ==========================================================================
  # Helper functions
  # ==========================================================================

  def broadcast_cluster(%Data{subscribers: subscribers} = data) do
    Logger.warn(
      "broadcasting to #{Enum.count(subscribers)} subscribers, stable: #{Data.stable?(data)}"
    )

    Enum.each(subscribers, fn s ->
      msg = {:clusters_changed, data.current_cluster, data.pending_cluster}
      send(s, msg)
    end)
  end

  defp internal(event) do
    {:next_event, :internal, event}
  end

  defp info(event) do
    {:next_event, :info, event}
  end

  defp suicide_pact(client_pid) do
    originating_process = self()

    pact = fn ->
      ref = Process.monitor(originating_process)

      receive do
        {:DOWN, ^ref, :process, _, _} ->
          :erlzk.close(client_pid)
      end
    end

    spawn(pact)
    :ok
  end
end

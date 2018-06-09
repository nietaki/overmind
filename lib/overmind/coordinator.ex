defmodule Overmind.Coordinator do
  require Logger

  use GenStateMachine

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

  @type state :: :disconnected | :leading | :following

  defstruct [
    :client_pid
  ]

  @zk_host {'localhost', 2181}
  @chroot_path '/chroot_path'

  def start_link(:start_link_arg) do
    GenStateMachine.start_link(__MODULE__, :init_arg, name: __MODULE__)
  end

  @impl true
  def init(:init_arg) do
    Logger.info("Overmind.Coordinator initializing")
    # chroot path needs to be created in advance
    {:ok, client_pid} = :erlzk.connect([@zk_host], 30000, [])
    res = :erlzk.create(client_pid, @chroot_path)
    true = res in [{:ok, @chroot_path}, {:error, :node_exists}]
    # TODO other important paths
    :ok = :erlzk.close(client_pid)

    # the actual erlzk client
    {:ok, client_pid} = :erlzk.connect([@zk_host], 30000, chroot: @chroot_path, monitor: self())
    Logger.info("Overmind.Coordinator connected")

    data = %__MODULE__{client_pid: client_pid}
    {:ok, :connected, data, [{:next_event, :internal, :register_yourself}]}
  end

  @impl true
  def handle_event(:internal, :register_yourself, :connected, data) do
    Logger.info("Overmind.Coordinator registering itself")
    IO.inspect(:erlzk.create(data.client_pid, '/foo'))
    # TODO add your node under connected nodes, transition to participating
    {:next_state, :connected, data}
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
end

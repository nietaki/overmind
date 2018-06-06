defmodule Overmind.Coordinator do
  require Logger

  use GenStateMachine

  @type state :: :disconnected | :connected | :participating

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

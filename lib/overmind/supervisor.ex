defmodule Overmind.Supervisor do
  use Supervisor

  def start_link() do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = [
      # {Overmind.Coordinator, :child_spec_arg}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end

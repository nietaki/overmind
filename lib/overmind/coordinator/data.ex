defmodule Overmind.Coordinator.Data do
  alias Overmind.Coordinator.Cluster

  @type t :: %__MODULE__{}

  defstruct [
    # atom
    :self_node,
    # pid
    :client_pid,
    # [pid | atom]
    :subscribers,
    # String.t
    :leader_node,
    # %Cluster{}
    :current_cluster,
    # %Cluster{}
    :pending_cluster,
    # node :: atom() => version :: integer
    :available_nodes
  ]

  def new() do
    %__MODULE__{
      subscribers: []
    }
  end

  def set_leader_node(data, leader_node) when is_binary(leader_node) do
    %__MODULE__{data | leader_node: leader_node}
  end

  def current_cluster_changed(%__MODULE__{} = data, %Cluster{} = cluster) do
    %__MODULE__{
      data
      | current_cluster: cluster,
        pending_cluster: nil,
        available_nodes: nil
    }
    |> changed(true)
  end

  def pending_cluster_changed(%__MODULE__{} = data, %Cluster{} = cluster) do
    readiness =
      cluster.nodes
      |> Enum.map(&{&1, -1})
      |> Map.new()

    %__MODULE__{
      data
      | pending_cluster: cluster,
        available_nodes: readiness
    }
    |> changed(true)
  end

  def available_node_changed(%__MODULE__{} = data, node, node_readiness_version) do
    false = data.pending_cluster == nil

    new_available =
      data.available_nodes
      |> Map.update!(node, &max(&1, node_readiness_version))

    if Enum.all?(new_available, fn {_n, version} -> version >= data.pending_cluster.version end) do
      %__MODULE__{
        data
        | current_cluster: data.pending_cluster,
          pending_cluster: nil,
          available_nodes: nil
      }
      |> changed(true)
    else
      %__MODULE__{
        data
        | available_nodes: new_available
      }
      |> changed(false)
    end
  end

  def stable?(%__MODULE__{pending_cluster: pending_cluster}) do
    pending_cluster == nil
  end

  defp changed(data, is_changed) when is_boolean(is_changed) do
    {data, is_changed}
  end
end

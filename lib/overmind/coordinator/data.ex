defmodule Overmind.Coordinator.Data do
  alias Overmind.Coordinator.Cluster
  alias __MODULE__, as: This

  require Logger

  @type t :: %This{}

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
    %This{
      subscribers: []
    }
  end

  def set_leader_node(data, leader_node) when is_binary(leader_node) do
    %This{data | leader_node: leader_node}
  end

  def current_cluster_changed(%This{} = data, %Cluster{} = cluster) do
    %This{
      data
      | current_cluster: cluster,
        pending_cluster: nil,
        available_nodes: nil
    }
    |> changed(true)
  end

  def pending_cluster_changed(%This{} = data, %Cluster{} = cluster) do
    readiness =
      cluster.nodes
      |> Enum.map(&{&1, -1})
      |> Map.new()

    %This{
      data
      | pending_cluster: cluster,
        available_nodes: readiness
    }
    |> changed(true)
  end

  # def available_node_changed(
  #       data = %This{current_cluster: %Cluster{version: cur_version}},
  #       _node,
  #       ready_version
  #     )
  #     when ready_version >= cur_version do
  #   changed(data, false)
  # end
  #
  # def available_node_changed(data = %This{pending_cluster: nil}, node, version) do
  #   Logger.error("unexpected available node changed event #{inspect {node, version}} at #{inspect data}")
  #   changed(data, false)
  # end

  def available_node_changed(%This{} = data, node, node_readiness_version) do
    if data.pending_cluster == nil do
      changed(data, false)
    else
      new_available =
        data.available_nodes
        |> Map.update!(node, &max(&1, node_readiness_version))

      data = %This{data | available_nodes: new_available}

      if Enum.all?(new_available, fn {_n, version} -> version >= data.pending_cluster.version end) do
        %This{
          data
          | current_cluster: data.pending_cluster,
            pending_cluster: nil,
            available_nodes: nil
        }
        |> changed(true)
      else
        changed(data, false)
      end
    end
  end

  def stable?(%This{pending_cluster: pending_cluster}) do
    pending_cluster == nil
  end

  defp changed(data, is_changed) when is_boolean(is_changed) do
    {data, is_changed}
  end
end

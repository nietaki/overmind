defmodule Overmind.Coordinator.Cluster do
  @enforce_keys [
    # integer
    :version,
    # atom list
    :nodes
  ]

  defstruct @enforce_keys

  def new(nodes, version) when is_integer(version) do
    nodes =
      Enum.map(nodes, fn
        node when is_atom(node) ->
          node

        node when is_list(node) ->
          List.to_atom(node)

        node when is_binary(node) ->
          String.to_atom(node)
      end)

    %__MODULE__{version: version, nodes: nodes}
  end

  def from_current_cluster_data(data) when is_binary(data) do
    [version, nodes] = String.split(data, ":", parts: 2)
    version = String.to_integer(version)
    nodes = String.split(nodes, ",", trim: true)
    new(nodes, version)
  end

  def to_current_cluster_data(%__MODULE__{version: version, nodes: nodes}) do
    nodes =
      nodes
      |> Enum.map(&Atom.to_string/1)
      |> Enum.join(",")

    "#{version}:#{nodes}"
  end

  def to_pending_cluster_data(%__MODULE__{nodes: nodes}) do
    nodes
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join(",")
  end

  def from_pending_cluster_data(version, data) do
    nodes = String.split(data, ",", trim: true)
    new(nodes, version)
  end
end

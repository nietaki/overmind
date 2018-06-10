defmodule Overmind.Utils do
  def ensure_znode(client_pid, path, data \\ "") when is_list(path) do
    res = :erlzk.create(client_pid, path, data)
    true = res in [{:ok, path}, {:error, :node_exists}]
    :ok
  end

  # TODO znodestat to a nice struct

  def node_to_charlist(node \\ Node.self()) when is_atom(node) do
    node |> to_charlist()
  end

  def node_from_charlist(charlist) when is_list(charlist) do
    charlist |> :erlang.list_to_atom()
  end

  # ==========================================================================
  # ZK - related utils
  # ==========================================================================

  @spec split_sequential_name(charlist()) :: {integer(), charlist()}
  def split_sequential_name(sequential_name) do
    {basename, integer_charlist} = Enum.split(sequential_name, -10)
    seq_no = List.to_integer(integer_charlist)
    true = seq_no >= 0
    {seq_no, basename}
  end

  def get_leader(leaders) do
    actual_leader =
      leaders
      |> Enum.map(fn name ->
        {split_sequential_name(name), name}
      end)
      |> Enum.sort()
      |> Enum.take(1)

    case actual_leader do
      [] ->
        nil

      [{{_, _}, full_name}] ->
        full_name
    end
  end
end

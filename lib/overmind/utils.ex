defmodule Overmind.Utils do
  def ensure_znode(client_pid, path, data \\ "") do
    res = :erlzk.create(client_pid, path, data)

    case res do
      {:ok, _path} ->
        res

      {:error, :node_exists} ->
        res

      other ->
        raise "unexpected result in ensure_znode: #{inspect(other)}"
    end
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

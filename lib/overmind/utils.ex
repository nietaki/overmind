defmodule Overmind.Utils do
  def ensure_znode(client_pid, path) when is_list(path) do
    res = :erlzk.create(client_pid, path)
    true = res in [{:ok, path}, {:error, :node_exists}]
    :ok
  end

  # TODO znodestat to a nice struct
end

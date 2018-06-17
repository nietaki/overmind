defmodule Tools do
  @doc """
  Run the passed function until it returns without raising an exception or remaining_retries are exhausted
  """
  def wait_until_pass(fun, remaining_retries \\ 10, delay_ms \\ 10)

  def wait_until_pass(fun, 0, _delay_ms) do
    fun.()
  end

  def wait_until_pass(fun, remaining_retries, delay_ms) do
    try do
      fun.()
    rescue
      _e in ExUnit.AssertionError ->
        Process.sleep(delay_ms)
        wait_until_pass(fun, remaining_retries - 1, delay_ms)
    end
  end
end

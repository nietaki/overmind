defmodule OvermindTest do
  use ExUnit.Case
  doctest Overmind

  test "greets the world" do
    assert Overmind.hello() == :world
  end
end

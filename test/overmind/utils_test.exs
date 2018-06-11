defmodule Overmind.UtilsTest do
  use ExUnit.Case

  import Overmind.Utils

  test "split_sequential_name" do
    assert {15, 'foo-bar-'} == split_sequential_name('foo-bar-0000000015')
    assert {14, 'foo-bar'} == split_sequential_name('foo-bar0000000014')
  end

  test "get_leader" do
    assert nil == get_leader([])
    leaders = ['foo0000000014', 'bar0000000030', 'baz-0000000004']
    assert 'baz-0000000004' == get_leader(leaders)
  end
end

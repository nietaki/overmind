defmodule Overmind.CoordinatorTest do
  use ExUnit.Case

  alias Overmind.Coordinator.Cluster
  alias Overmind.Coordinator.Data

  describe "Cluster" do
    test "constructs from current cluster data correctly" do
      test_case = fn data, nodes ->
        cluster = Cluster.from_current_cluster_data(data)
        assert %Cluster{version: -1, nodes: nodes} == cluster
        assert data == Cluster.to_current_cluster_data(cluster)
      end

      test_case.("-1:", [])
      test_case.("-1:foo@bar", [:foo@bar])
      test_case.("-1:foo@bar,baz@ban", [:foo@bar, :baz@ban])
    end
  end

  describe "Data" do
    setup do
      empty = %Data{}

      {:ok, %{empty: empty}}
    end

    test "changing current cluster broadcasts and re-sets available nodes", %{empty: empty} do
      cluster = Cluster.new([:foo, :bar], 4)
      assert {new_data, true} = Data.current_cluster_changed(empty, cluster)
      assert new_data.current_cluster == cluster

      assert new_data.available_nodes == nil
    end

    test "changing pending cluster", %{empty: empty} do
      current = Cluster.new([:foo, :bar], 4)
      {data, true} = Data.current_cluster_changed(empty, current)
      pending = Cluster.new([:bar, :baz], 5)

      assert {new_data, true} = Data.pending_cluster_changed(data, pending)
      assert new_data.pending_cluster == pending

      assert new_data.available_nodes == %{
               bar: -1,
               baz: -1
             }
    end

    test "updating available nodes, one by one", %{empty: empty} do
      current = Cluster.new([:foo, :bar], 4)
      pending = Cluster.new([:bar, :baz], 5)
      {data, true} = Data.current_cluster_changed(empty, current)
      {data, true} = Data.pending_cluster_changed(data, pending)

      assert {new_data, false} = Data.available_node_changed(data, :bar, 4)

      assert new_data.available_nodes == %{
               bar: 4,
               baz: -1
             }

      assert {new_data, false} = Data.available_node_changed(new_data, :baz, 5)

      assert new_data.current_cluster == data.current_cluster

      assert new_data.available_nodes == %{
               bar: 4,
               baz: 5
             }

      # this will trigger the transition
      assert {new_data, true} = Data.available_node_changed(new_data, :bar, 5)

      assert new_data.current_cluster == pending
      assert new_data.pending_cluster == nil
      assert new_data.available_nodes == nil
    end
  end
end

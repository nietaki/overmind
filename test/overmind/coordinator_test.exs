defmodule Overmind.CoordinatorTest do
  use ExUnit.Case

  alias Overmind.Coordinator.Cluster

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
end

defmodule Overmind.CoordinatorTest do
  use ExUnit.Case
  import Tools

  alias Overmind.Coordinator
  alias Overmind.Coordinator.Cluster
  alias Overmind.Coordinator.Data

  @a :a@a
  @b :b@b

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

  describe "Coordinator integration tests" do
    setup do
      zk_servers = [{'localhost', 2181}]

      {:ok, root_client_pid} = :erlzk.connect(zk_servers, 30000, [])
      Overmind.Utils.ensure_znode(root_client_pid, "/test_chroot")
      test_dir = UUID.uuid4()
      :ok = :erlzk.close(root_client_pid)

      opts = [
        chroot_path: "/test_chroot/#{test_dir}",
        zk_servers: zk_servers
      ]

      {:ok, %{opts: opts}}
    end

    test "a clean start", %{opts: opts} do
      {:ok, pid} = Coordinator.start_link(opts ++ [self_node: :a@foo])
      assert is_pid(pid)

      assert {:leading, data} = Coordinator.get_state_and_data(pid)
      assert data.self_node == :a@foo
      assert data.available_nodes == %{a@foo: -1}
      assert is_pid(data.client_pid)
      assert data.current_cluster == %Cluster{nodes: [], version: -1}
      assert data.pending_cluster == %Cluster{nodes: [:a@foo], version: 1}
      assert data.leader_node =~ "a@foo"
    end

    test "Just one server scenario", %{opts: opts} do
      {:ok, pid} = Coordinator.start_link(opts ++ [self_node: :a@foo, subscribers: [self()]])
      assert is_pid(pid)

      assert {:leading, data} = Coordinator.get_state_and_data(pid)
      assert data.current_cluster == %Cluster{nodes: [], version: -1}
      assert data.pending_cluster == %Cluster{nodes: [:a@foo], version: 1}

      assert_receive {:clusters_changed, current, pending}
      assert current == Cluster.new([], -1)
      assert pending == nil

      assert_receive {:clusters_changed, current, pending}
      assert current == Cluster.new([], -1)
      assert pending == Cluster.new([:a@foo], 1)

      refute_receive {:clusters_changed, _, _}

      Coordinator.node_ready(pid, 1)

      wait_until_pass(fn ->
        assert {:leading, data} = Coordinator.get_state_and_data(pid)
        assert data.current_cluster == %Cluster{nodes: [:a@foo], version: 1}
      end)

      assert {:leading, data} = Coordinator.get_state_and_data(pid)
      assert data.pending_cluster == nil

      assert_receive {:clusters_changed, current_cluster, nil}
      assert current_cluster == Cluster.new([:a@foo], 1)
      refute_receive {:clusters_changed, _, _}
    end

    test "basic 2 server scenario", %{opts: opts} do
      _ = start_link_coordinator(opts, @a)
      assert_receive {@a, {:clusters_changed, _, _}}
      assert_receive {@a, {:clusters_changed, _, _}}
      refute_receive {@a, _}

      _ = start_link_coordinator(opts, @b)
      refute_receive {@b, _}
      # TODO continue here
    end

    test "killing the coordinator kills its zk client too", %{opts: opts} do
      {:ok, pid} = Coordinator.start(opts)
      {_, data} = Coordinator.get_state_and_data(pid)
      client_pid = data.client_pid
      assert Process.alive?(pid)
      assert Process.alive?(client_pid)

      Process.exit(pid, :kill)
      refute Process.alive?(pid)

      wait_until_pass(fn ->
        refute Process.alive?(client_pid)
      end)
    end
  end

  def start_link_coordinator(opts, name) do
    test_process = self()
    forwarder_pid = spawn_link(fn -> named_message_forwarder(test_process, name) end)
    custom_opts = [self_node: name, subscribers: [forwarder_pid]]
    {:ok, pid} = Coordinator.start_link(opts ++ custom_opts)
    pid
  end

  defp named_message_forwarder(target, name) do
    receive do
      anything -> send(target, {name, anything})
    end

    named_message_forwarder(target, name)
  end
end

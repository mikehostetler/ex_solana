defmodule JidoFlame.RegistryTest do
  use ExUnit.Case, async: false

  alias JidoFlame.{AgentRegistry, ChildRegistry}

  describe "AgentRegistry" do
    setup do
      name = :"agent_reg_#{:erlang.unique_integer([:positive])}"
      {:ok, _pid} = AgentRegistry.start_link(name: name)
      {:ok, registry: name}
    end

    test "registers and looks up agents", %{registry: name} do
      assert :ok = AgentRegistry.register("agent-1", self(), name)
      assert {:ok, pid} = AgentRegistry.lookup("agent-1", name)
      assert pid == self()
    end

    test "returns error for unknown agent", %{registry: name} do
      assert :error = AgentRegistry.lookup("unknown", name)
    end

    test "allows duplicate registration from same pid", %{registry: name} do
      assert :ok = AgentRegistry.register("agent-1", self(), name)
      assert :ok = AgentRegistry.register("agent-1", self(), name)
    end

    test "prevents duplicate registration from different pid", %{registry: name} do
      assert :ok = AgentRegistry.register("agent-1", self(), name)

      task =
        Task.async(fn ->
          AgentRegistry.register("agent-1", self(), name)
        end)

      assert {:error, :already_registered} = Task.await(task)
    end

    test "unregisters agents", %{registry: name} do
      assert :ok = AgentRegistry.register("agent-1", self(), name)
      assert :ok = AgentRegistry.unregister("agent-1", name)
      assert :error = AgentRegistry.lookup("agent-1", name)
    end

    test "unregister is idempotent", %{registry: name} do
      assert :ok = AgentRegistry.unregister("nonexistent", name)
    end

    test "lists all registered agents", %{registry: name} do
      AgentRegistry.register("agent-1", self(), name)
      AgentRegistry.register("agent-2", self(), name)

      entries = AgentRegistry.list_all(name)
      assert length(entries) == 2
      ids = Enum.map(entries, fn {id, _pid} -> id end) |> Enum.sort()
      assert ids == ["agent-1", "agent-2"]
    end

    test "auto-unregisters on process exit", %{registry: name} do
      test_pid = self()

      pid =
        spawn(fn ->
          AgentRegistry.register("agent-temp", self(), name)
          send(test_pid, :registered)

          receive do
            :stop -> :ok
          end
        end)

      assert_receive :registered, 500
      assert {:ok, ^pid} = AgentRegistry.lookup("agent-temp", name)

      Process.exit(pid, :kill)
      :timer.sleep(100)

      assert :error = AgentRegistry.lookup("agent-temp", name)
    end
  end

  describe "ChildRegistry" do
    setup do
      name = :"child_reg_#{:erlang.unique_integer([:positive])}"
      {:ok, _pid} = ChildRegistry.start_link(name: name)
      {:ok, registry: name}
    end

    test "registers and looks up children", %{registry: name} do
      assert :ok = ChildRegistry.register_child("agent-1", :worker, self(), name)
      assert {:ok, pid} = ChildRegistry.lookup_child("agent-1", :worker, name)
      assert pid == self()
    end

    test "returns error for unknown child", %{registry: name} do
      assert :error = ChildRegistry.lookup_child("agent-1", :unknown, name)
    end

    test "allows duplicate registration from same pid", %{registry: name} do
      assert :ok = ChildRegistry.register_child("agent-1", :worker, self(), name)
      assert :ok = ChildRegistry.register_child("agent-1", :worker, self(), name)
    end

    test "prevents duplicate registration from different pid", %{registry: name} do
      assert :ok = ChildRegistry.register_child("agent-1", :worker, self(), name)

      task =
        Task.async(fn ->
          ChildRegistry.register_child("agent-1", :worker, self(), name)
        end)

      assert {:error, :already_registered} = Task.await(task)
    end

    test "lists children for an agent", %{registry: name} do
      ChildRegistry.register_child("agent-1", :worker_1, self(), name)
      ChildRegistry.register_child("agent-1", :worker_2, self(), name)

      children = ChildRegistry.children("agent-1", name)
      assert length(children) == 2
    end

    test "lists children with tags", %{registry: name} do
      ChildRegistry.register_child("agent-1", :worker_1, self(), name)
      ChildRegistry.register_child("agent-1", :worker_2, self(), name)

      children = ChildRegistry.children_with_tags("agent-1", name)
      tags = Enum.map(children, fn {tag, _pid} -> tag end) |> Enum.sort()
      assert tags == [:worker_1, :worker_2]
    end

    test "does not mix children from different agents", %{registry: name} do
      ChildRegistry.register_child("agent-1", :worker, self(), name)
      ChildRegistry.register_child("agent-2", :worker, self(), name)

      children_1 = ChildRegistry.children("agent-1", name)
      children_2 = ChildRegistry.children("agent-2", name)

      assert length(children_1) == 1
      assert length(children_2) == 1
    end

    test "unregisters individual children", %{registry: name} do
      ChildRegistry.register_child("agent-1", :worker, self(), name)
      assert :ok = ChildRegistry.unregister_child("agent-1", :worker, name)
      assert :error = ChildRegistry.lookup_child("agent-1", :worker, name)
    end

    test "unregister_child is idempotent", %{registry: name} do
      assert :ok = ChildRegistry.unregister_child("agent-1", :nonexistent, name)
    end

    test "unregisters all children for an agent", %{registry: name} do
      ChildRegistry.register_child("agent-1", :worker_1, self(), name)
      ChildRegistry.register_child("agent-1", :worker_2, self(), name)
      ChildRegistry.register_child("agent-2", :worker_1, self(), name)

      assert :ok = ChildRegistry.unregister_all("agent-1", name)
      assert ChildRegistry.children("agent-1", name) == []
      assert length(ChildRegistry.children("agent-2", name)) == 1
    end

    test "auto-unregisters on process exit", %{registry: name} do
      test_pid = self()

      pid =
        spawn(fn ->
          ChildRegistry.register_child("agent-1", :worker, self(), name)
          send(test_pid, :registered)

          receive do
            :stop -> :ok
          end
        end)

      assert_receive :registered, 500
      assert {:ok, ^pid} = ChildRegistry.lookup_child("agent-1", :worker, name)

      Process.exit(pid, :kill)
      :timer.sleep(100)

      assert :error = ChildRegistry.lookup_child("agent-1", :worker, name)
    end
  end
end

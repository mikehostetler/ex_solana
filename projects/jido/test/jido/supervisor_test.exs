defmodule JidoTest.SupervisorTest do
  use ExUnit.Case, async: true

  describe "Jido supervisor" do
    test "starts a Jido instance supervisor" do
      name = :"test_jido_#{System.unique_integer([:positive])}"
      {:ok, pid} = Jido.start_link(name: name)
      assert is_pid(pid)
      assert Process.alive?(pid)
      Supervisor.stop(pid)
    end

    test "requires :name option" do
      assert_raise KeyError, ~r/:name/, fn ->
        Jido.start_link([])
      end
    end

    test "can be used as a child spec" do
      name = :"test_jido_#{System.unique_integer([:positive])}"
      spec = Jido.child_spec(name: name)
      assert spec.id == name
      assert spec.type == :supervisor
    end

    test "starts TaskSupervisor as child" do
      name = :"test_jido_#{System.unique_integer([:positive])}"
      {:ok, pid} = Jido.start_link(name: name)

      task_sup = Jido.task_supervisor(name)
      assert Process.whereis(task_sup) != nil

      # Verify we can start tasks on it
      {:ok, task} = Task.Supervisor.start_child(task_sup, fn -> :ok end)
      assert is_pid(task)

      Supervisor.stop(pid)
    end

    test "starts Registry as child" do
      name = :"test_jido_#{System.unique_integer([:positive])}"
      {:ok, sup_pid} = Jido.start_link(name: name)

      reg = Jido.registry(name)
      assert Process.whereis(reg) != nil

      # Verify we can register processes
      {:ok, _} = Registry.register(reg, "test_key", :test_value)
      assert [{registered_pid, :test_value}] = Registry.lookup(reg, "test_key")
      assert registered_pid == self()

      # Unregister before stopping to avoid EXIT signal to test process
      Registry.unregister(reg, "test_key")
      Supervisor.stop(sup_pid)
    end

    test "starts AgentSupervisor (DynamicSupervisor) as child" do
      name = :"test_jido_#{System.unique_integer([:positive])}"
      {:ok, pid} = Jido.start_link(name: name)

      agent_sup = Jido.agent_supervisor(name)
      assert Process.whereis(agent_sup) != nil

      # Verify it's a DynamicSupervisor by checking we can count children
      assert DynamicSupervisor.count_children(agent_sup) == %{
               active: 0,
               specs: 0,
               supervisors: 0,
               workers: 0
             }

      Supervisor.stop(pid)
    end
  end
end

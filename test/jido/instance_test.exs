defmodule JidoTest.InstanceTest do
  use ExUnit.Case, async: false

  alias JidoTest.TestAgents.Minimal

  defmodule TestInstance do
    use Jido, otp_app: :jido_test_instance
  end

  setup do
    Application.put_env(:jido_test_instance, TestInstance, max_tasks: 500)

    on_exit(fn ->
      Application.delete_env(:jido_test_instance, TestInstance)

      if pid = Process.whereis(TestInstance) do
        try do
          Supervisor.stop(pid, :normal, 5000)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    :ok
  end

  describe "instance module definition" do
    test "generates child_spec/1" do
      spec = TestInstance.child_spec([])

      assert spec.id == TestInstance
      assert spec.type == :supervisor
      assert {Jido, :start_link, [opts]} = spec.start
      assert Keyword.get(opts, :name) == TestInstance
    end

    test "generates config/1 that reads from application env" do
      config = TestInstance.config()

      assert Keyword.get(config, :max_tasks) == 500
    end

    test "config/1 merges runtime overrides" do
      config = TestInstance.config(max_tasks: 1000, extra: :value)

      assert Keyword.get(config, :max_tasks) == 1000
      assert Keyword.get(config, :extra) == :value
    end

    test "child_spec/1 accepts runtime overrides" do
      spec = TestInstance.child_spec(max_tasks: 2000)

      assert {Jido, :start_link, [opts]} = spec.start
      assert Keyword.get(opts, :max_tasks) == 2000
    end
  end

  describe "instance lifecycle" do
    test "start_link/1 starts the supervisor" do
      {:ok, pid} = TestInstance.start_link()

      assert is_pid(pid)
      assert Process.alive?(pid)
      assert Process.whereis(TestInstance) == pid
    end

    test "starts TaskSupervisor as child" do
      {:ok, _pid} = TestInstance.start_link()

      task_sup = TestInstance.task_supervisor_name()
      assert Process.whereis(task_sup) != nil
    end

    test "starts Registry as child" do
      {:ok, _pid} = TestInstance.start_link()

      reg = TestInstance.registry_name()
      assert Process.whereis(reg) != nil
    end

    test "starts AgentSupervisor as child" do
      {:ok, _pid} = TestInstance.start_link()

      agent_sup = TestInstance.agent_supervisor_name()
      assert Process.whereis(agent_sup) != nil
    end
  end

  describe "instance agent API" do
    test "start_agent/2 starts an agent" do
      {:ok, _sup_pid} = TestInstance.start_link()

      {:ok, agent_pid} = TestInstance.start_agent(Minimal, id: "test-1")

      assert is_pid(agent_pid)
      assert Process.alive?(agent_pid)
    end

    test "whereis/1 looks up an agent by ID" do
      {:ok, _sup_pid} = TestInstance.start_link()

      {:ok, agent_pid} = TestInstance.start_agent(Minimal, id: "lookup-test")

      found_pid = TestInstance.whereis("lookup-test")
      assert found_pid == agent_pid
    end

    test "whereis/1 returns nil for unknown ID" do
      {:ok, _sup_pid} = TestInstance.start_link()

      assert TestInstance.whereis("nonexistent") == nil
    end

    test "list_agents/0 lists all agents" do
      {:ok, _sup_pid} = TestInstance.start_link()

      {:ok, _} = TestInstance.start_agent(Minimal, id: "list-1")
      {:ok, _} = TestInstance.start_agent(Minimal, id: "list-2")

      agents = TestInstance.list_agents()
      ids = Enum.map(agents, fn {id, _pid} -> id end)

      assert "list-1" in ids
      assert "list-2" in ids
    end

    test "agent_count/0 returns count of running agents" do
      {:ok, _sup_pid} = TestInstance.start_link()

      assert TestInstance.agent_count() == 0

      {:ok, _} = TestInstance.start_agent(Minimal, id: "count-1")
      assert TestInstance.agent_count() == 1

      {:ok, _} = TestInstance.start_agent(Minimal, id: "count-2")
      assert TestInstance.agent_count() == 2
    end

    test "stop_agent/1 stops an agent by ID" do
      {:ok, _sup_pid} = TestInstance.start_link()

      {:ok, _} = TestInstance.start_agent(Minimal, id: "stop-test")

      assert TestInstance.whereis("stop-test") != nil
      assert :ok = TestInstance.stop_agent("stop-test")
      assert TestInstance.whereis("stop-test") == nil
    end

    test "stop_agent/1 stops an agent by pid" do
      {:ok, _sup_pid} = TestInstance.start_link()

      {:ok, pid} = TestInstance.start_agent(Minimal, id: "stop-pid-test")

      assert Process.alive?(pid)
      assert :ok = TestInstance.stop_agent(pid)
      refute Process.alive?(pid)
    end
  end

  describe "supervision tree integration" do
    test "can be used in Supervisor.start_link/2" do
      children = [TestInstance]

      {:ok, sup_pid} = Supervisor.start_link(children, strategy: :one_for_one)

      assert Process.alive?(sup_pid)
      assert Process.whereis(TestInstance) != nil

      Supervisor.stop(sup_pid, :normal, 5000)
    end

    test "can be used with runtime options in supervision tree" do
      children = [{TestInstance, max_tasks: 3000}]

      {:ok, sup_pid} = Supervisor.start_link(children, strategy: :one_for_one)

      assert Process.alive?(sup_pid)
      assert Process.whereis(TestInstance) != nil

      Supervisor.stop(sup_pid, :normal, 5000)
    end
  end
end

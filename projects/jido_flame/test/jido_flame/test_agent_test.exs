defmodule JidoFlame.TestAgentTest do
  use ExUnit.Case, async: false

  alias JidoFlame.TestAgent

  describe "TestAgent" do
    test "starts and responds to ping" do
      {:ok, pid} = TestAgent.start_link(%{})
      assert TestAgent.ping(pid) == :pong
      GenServer.stop(pid)
    end

    test "starts with map options" do
      {:ok, pid} = TestAgent.start_link(%{initial_data: %{key: :value}})
      assert TestAgent.get_data(pid, :key) == :value
      GenServer.stop(pid)
    end

    test "starts with keyword list options" do
      {:ok, pid} = TestAgent.start_link(initial_data: %{key: :value})
      assert TestAgent.get_data(pid, :key) == :value
      GenServer.stop(pid)
    end

    test "stores and retrieves data" do
      {:ok, pid} = TestAgent.start_link(%{})

      assert :ok = TestAgent.put_data(pid, :key, :value)
      assert TestAgent.get_data(pid, :key) == :value

      GenServer.stop(pid)
    end

    test "returns nil for unknown data key" do
      {:ok, pid} = TestAgent.start_link(%{})

      assert TestAgent.get_data(pid, :unknown) == nil

      GenServer.stop(pid)
    end

    test "returns node info" do
      {:ok, pid} = TestAgent.start_link(%{})

      info = TestAgent.node_info(pid)
      assert info.node == node()
      assert info.pid == pid
      assert is_integer(info.uptime_ms)
      assert info.uptime_ms >= 0

      GenServer.stop(pid)
    end

    test "executes functions" do
      {:ok, pid} = TestAgent.start_link(%{})

      result = TestAgent.execute(pid, fn -> 1 + 1 end)
      assert result == 2

      GenServer.stop(pid)
    end

    test "executes functions that return computed values" do
      {:ok, pid} = TestAgent.start_link(%{})

      result =
        TestAgent.execute(pid, fn ->
          3 * 5
        end)

      assert result == 15

      GenServer.stop(pid)
    end

    test "tracks parent_ref" do
      parent_ref = %{
        logical_agent_id: "test-parent",
        owner_pid: self(),
        meta: %{test: true}
      }

      {:ok, pid} = TestAgent.start_link(%{parent_ref: parent_ref})

      state = TestAgent.get_state(pid)
      assert state.parent_ref == parent_ref

      GenServer.stop(pid)
    end

    test "get_state returns full state struct" do
      {:ok, pid} = TestAgent.start_link(%{initial_data: %{foo: :bar}})

      state = TestAgent.get_state(pid)
      assert %TestAgent{} = state
      assert state.data == %{foo: :bar}
      assert %DateTime{} = state.started_at

      GenServer.stop(pid)
    end

    test "emits started signal to parent on init" do
      parent_ref = %{
        logical_agent_id: "test-parent",
        owner_pid: self()
      }

      {:ok, pid} = TestAgent.start_link(%{parent_ref: parent_ref})

      assert_receive {:remote_child_signal, signal}, 500
      assert signal.type == "jido.flame.test_agent.started"
      assert signal.data.node == node()
      assert signal.data.pid == pid

      GenServer.stop(pid)
    end

    test "emits custom signal to parent via emit_to_parent" do
      parent_ref = %{
        logical_agent_id: "test-parent",
        owner_pid: self()
      }

      {:ok, pid} = TestAgent.start_link(%{parent_ref: parent_ref})

      assert_receive {:remote_child_signal, _started_signal}, 500

      TestAgent.emit_to_parent(pid, "test.signal", %{data: 123})

      assert_receive {:remote_child_signal, signal}, 500
      assert signal.type == "test.signal"
      assert signal.data.data == 123

      GenServer.stop(pid)
    end

    test "emits stopped signal to parent on terminate" do
      parent_ref = %{
        logical_agent_id: "test-parent",
        owner_pid: self()
      }

      {:ok, pid} = TestAgent.start_link(%{parent_ref: parent_ref})

      assert_receive {:remote_child_signal, _started_signal}, 500

      GenServer.stop(pid, :normal)

      assert_receive {:remote_child_signal, signal}, 500
      assert signal.type == "jido.flame.test_agent.stopped"
      assert signal.data.reason == :normal
    end

    test "does not emit signals when no parent_ref" do
      {:ok, pid} = TestAgent.start_link(%{})

      refute_receive {:remote_child_signal, _}, 100

      GenServer.stop(pid)
    end

    test "stop/2 stops the agent" do
      {:ok, pid} = TestAgent.start_link(%{})

      assert :ok = TestAgent.stop(pid)
      refute Process.alive?(pid)
    end

    test "stop/2 with custom reason emits stopped signal" do
      parent_ref = %{
        logical_agent_id: "test-parent",
        owner_pid: self()
      }

      {:ok, pid} = TestAgent.start_link(%{parent_ref: parent_ref})

      assert_receive {:remote_child_signal, _started_signal}, 500

      Process.flag(:trap_exit, true)
      TestAgent.stop(pid, :custom_reason)

      assert_receive {:remote_child_signal, signal}, 500
      assert signal.type == "jido.flame.test_agent.stopped"
      assert signal.data.reason == :custom_reason
    end

    test "child_spec/1 returns proper child spec" do
      opts = %{initial_data: %{}}

      spec = TestAgent.child_spec(opts)

      assert spec.id == TestAgent
      assert spec.start == {TestAgent, :start_link, [opts]}
      assert spec.type == :worker
      assert spec.restart == :temporary
    end
  end
end

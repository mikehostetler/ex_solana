defmodule JidoTest.AgentServerTest do
  use ExUnit.Case, async: true

  alias Jido.AgentServer
  alias Jido.Agent.Directive
  alias Jido.Signal

  defmodule TestAgent do
    @moduledoc false
    use Jido.Agent,
      name: "test_agent",
      schema: [
        counter: [type: :integer, default: 0],
        messages: [type: {:list, :any}, default: []]
      ]

    def handle_signal(agent, %Signal{type: "increment"} = _signal) do
      count = Map.get(agent.state, :counter, 0)
      agent = %{agent | state: Map.put(agent.state, :counter, count + 1)}
      {agent, []}
    end

    def handle_signal(agent, %Signal{type: "decrement"} = _signal) do
      count = Map.get(agent.state, :counter, 0)
      agent = %{agent | state: Map.put(agent.state, :counter, count - 1)}
      {agent, []}
    end

    def handle_signal(agent, %Signal{type: "record", data: data} = _signal) do
      messages = Map.get(agent.state, :messages, [])
      agent = %{agent | state: Map.put(agent.state, :messages, messages ++ [data])}
      {agent, []}
    end

    def handle_signal(agent, %Signal{type: "emit_test"} = _signal) do
      signal = Signal.new!("test.emitted", %{from: "agent"}, source: "/test")
      {agent, [%Directive.Emit{signal: signal}]}
    end

    def handle_signal(agent, %Signal{type: "schedule_test"} = _signal) do
      scheduled_signal = Signal.new!("scheduled.ping", %{}, source: "/test")
      {agent, [%Directive.Schedule{delay_ms: 50, message: scheduled_signal}]}
    end

    def handle_signal(agent, %Signal{type: "stop_test"} = _signal) do
      {agent, [%Directive.Stop{reason: :normal}]}
    end

    def handle_signal(agent, %Signal{type: "error_test"} = _signal) do
      error = Jido.Error.validation_error("Test error", %{field: :test})
      {agent, [%Directive.Error{error: error, context: :test}]}
    end

    def handle_signal(agent, _signal) do
      {agent, []}
    end
  end

  describe "start_link/2" do
    test "starts with agent module" do
      {:ok, pid} = AgentServer.start_link(TestAgent)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with name registration" do
      {:ok, pid} = AgentServer.start_link(TestAgent, name: :test_agent_named)
      assert Process.alive?(pid)
      assert GenServer.whereis(:test_agent_named) == pid
      GenServer.stop(pid)
    end

    test "starts with custom agent_opts" do
      {:ok, pid} = AgentServer.start_link(TestAgent, agent_opts: [id: "custom-123"])
      agent = AgentServer.get_agent(pid)
      assert agent.id == "custom-123"
      GenServer.stop(pid)
    end

    test "starts with pre-built agent" do
      agent = TestAgent.new(id: "prebuilt-456")
      agent = %{agent | state: Map.put(agent.state, :counter, 99)}

      {:ok, pid} = AgentServer.start_link(TestAgent, agent: agent)
      result = AgentServer.get_agent(pid)
      assert result.id == "prebuilt-456"
      assert result.state.counter == 99
      GenServer.stop(pid)
    end
  end

  describe "handle_signal/2 (async)" do
    test "processes signal asynchronously" do
      {:ok, pid} = AgentServer.start_link(TestAgent)

      signal = Signal.new!("increment", %{}, source: "/test")
      assert :ok = AgentServer.handle_signal(pid, signal)

      Process.sleep(10)
      agent = AgentServer.get_agent(pid)
      assert agent.state.counter == 1

      GenServer.stop(pid)
    end

    test "processes multiple signals" do
      {:ok, pid} = AgentServer.start_link(TestAgent)

      for _ <- 1..5 do
        signal = Signal.new!("increment", %{}, source: "/test")
        AgentServer.handle_signal(pid, signal)
      end

      Process.sleep(50)
      agent = AgentServer.get_agent(pid)
      assert agent.state.counter == 5

      GenServer.stop(pid)
    end
  end

  describe "handle_signal_sync/3" do
    test "processes signal synchronously and returns agent" do
      {:ok, pid} = AgentServer.start_link(TestAgent)

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, agent} = AgentServer.handle_signal_sync(pid, signal)

      assert agent.state.counter == 1
      GenServer.stop(pid)
    end

    test "records data from signal" do
      {:ok, pid} = AgentServer.start_link(TestAgent)

      signal = Signal.new!("record", %{message: "hello"}, source: "/test")
      {:ok, agent} = AgentServer.handle_signal_sync(pid, signal)

      assert agent.state.messages == [%{message: "hello"}]
      GenServer.stop(pid)
    end
  end

  describe "get_agent/1" do
    test "returns current agent state" do
      {:ok, pid} = AgentServer.start_link(TestAgent)
      agent = AgentServer.get_agent(pid)

      assert agent.state.counter == 0
      assert agent.state.messages == []
      GenServer.stop(pid)
    end
  end

  describe "alive?/1" do
    test "returns true for alive process" do
      {:ok, pid} = AgentServer.start_link(TestAgent)
      assert AgentServer.alive?(pid)
      GenServer.stop(pid)
    end

    test "returns false for dead process" do
      {:ok, pid} = AgentServer.start_link(TestAgent)
      GenServer.stop(pid)
      refute AgentServer.alive?(pid)
    end

    test "works with named processes" do
      {:ok, _pid} = AgentServer.start_link(TestAgent, name: :alive_test)
      assert AgentServer.alive?(:alive_test)
      GenServer.stop(:alive_test)
    end
  end

  describe "directive execution" do
    test "Emit directive logs when no dispatch configured" do
      {:ok, pid} = AgentServer.start_link(TestAgent)

      signal = Signal.new!("emit_test", %{}, source: "/test")
      {:ok, _agent} = AgentServer.handle_signal_sync(pid, signal)

      GenServer.stop(pid)
    end

    test "Error directive logs the error" do
      {:ok, pid} = AgentServer.start_link(TestAgent)

      signal = Signal.new!("error_test", %{}, source: "/test")
      {:ok, _agent} = AgentServer.handle_signal_sync(pid, signal)

      GenServer.stop(pid)
    end

    test "Schedule directive schedules a delayed signal" do
      {:ok, pid} = AgentServer.start_link(TestAgent)

      signal = Signal.new!("schedule_test", %{}, source: "/test")
      {:ok, _agent} = AgentServer.handle_signal_sync(pid, signal)

      assert Process.alive?(pid)
      Process.sleep(100)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "Stop directive stops the server" do
      {:ok, pid} = AgentServer.start_link(TestAgent)
      ref = Process.monitor(pid)

      signal = Signal.new!("stop_test", %{}, source: "/test")
      AgentServer.handle_signal(pid, signal)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end
  end

  describe "unknown signals" do
    test "handles unknown signal types gracefully" do
      {:ok, pid} = AgentServer.start_link(TestAgent)

      signal = Signal.new!("unknown.signal.type", %{}, source: "/test")
      {:ok, agent} = AgentServer.handle_signal_sync(pid, signal)

      assert agent.state.counter == 0
      GenServer.stop(pid)
    end
  end
end

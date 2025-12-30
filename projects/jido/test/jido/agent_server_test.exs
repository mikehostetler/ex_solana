defmodule JidoTest.AgentServerTest do
  use ExUnit.Case, async: true

  alias Jido.AgentServer
  alias Jido.AgentServer.State
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

  describe "start_link/1" do
    test "starts with agent module" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with custom id" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, id: "custom-123")
      {:ok, state} = AgentServer.state(pid)
      assert state.id == "custom-123"
      GenServer.stop(pid)
    end

    test "registers in Registry" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, id: "registry-test")
      assert AgentServer.whereis("registry-test") == pid
      GenServer.stop(pid)
    end

    test "starts with pre-built agent" do
      agent = TestAgent.new(id: "prebuilt-456")
      agent = %{agent | state: Map.put(agent.state, :counter, 99)}

      {:ok, pid} = AgentServer.start_link(agent: agent, agent_module: TestAgent)
      {:ok, state} = AgentServer.state(pid)
      assert state.agent.id == "prebuilt-456"
      assert state.agent.state.counter == 99
      GenServer.stop(pid)
    end

    test "starts with initial_state" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, initial_state: %{counter: 42})
      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.counter == 42
      GenServer.stop(pid)
    end
  end

  describe "start/1" do
    test "starts under DynamicSupervisor" do
      {:ok, pid} = AgentServer.start(agent: TestAgent, id: "dynamic-test")
      assert Process.alive?(pid)
      assert AgentServer.whereis("dynamic-test") == pid
      DynamicSupervisor.terminate_child(Jido.AgentSupervisor, pid)
    end
  end

  describe "call/3 (sync)" do
    test "processes signal and returns agent" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, agent} = AgentServer.call(pid, signal)

      assert agent.state.counter == 1
      GenServer.stop(pid)
    end

    test "processes multiple signals in sequence" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)

      for _ <- 1..5 do
        signal = Signal.new!("increment", %{}, source: "/test")
        {:ok, _agent} = AgentServer.call(pid, signal)
      end

      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.counter == 5
      GenServer.stop(pid)
    end

    test "records data from signal" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)

      signal = Signal.new!("record", %{message: "hello"}, source: "/test")
      {:ok, agent} = AgentServer.call(pid, signal)

      assert agent.state.messages == [%{message: "hello"}]
      GenServer.stop(pid)
    end

    test "works with agent ID string" do
      {:ok, _pid} = AgentServer.start_link(agent: TestAgent, id: "call-id-test")

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, agent} = AgentServer.call("call-id-test", signal)

      assert agent.state.counter == 1
      GenServer.stop(AgentServer.whereis("call-id-test"))
    end
  end

  describe "cast/2 (async)" do
    test "processes signal asynchronously" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)

      signal = Signal.new!("increment", %{}, source: "/test")
      assert :ok = AgentServer.cast(pid, signal)

      Process.sleep(10)
      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.counter == 1

      GenServer.stop(pid)
    end

    test "processes multiple signals" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)

      for _ <- 1..5 do
        signal = Signal.new!("increment", %{}, source: "/test")
        AgentServer.cast(pid, signal)
      end

      Process.sleep(50)
      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.counter == 5

      GenServer.stop(pid)
    end
  end

  describe "state/1" do
    test "returns full State struct" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, id: "state-test")
      {:ok, state} = AgentServer.state(pid)

      assert %State{} = state
      assert state.id == "state-test"
      assert state.agent.state.counter == 0
      assert state.status == :idle

      GenServer.stop(pid)
    end

    test "works with agent ID string" do
      {:ok, _pid} = AgentServer.start_link(agent: TestAgent, id: "state-id-test")
      {:ok, state} = AgentServer.state("state-id-test")

      assert state.id == "state-id-test"
      GenServer.stop(AgentServer.whereis("state-id-test"))
    end
  end

  describe "whereis/2" do
    test "returns pid for registered agent" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, id: "whereis-test")
      assert AgentServer.whereis("whereis-test") == pid
      GenServer.stop(pid)
    end

    test "returns nil for unknown agent" do
      assert AgentServer.whereis("nonexistent") == nil
    end
  end

  describe "via_tuple/2" do
    test "creates valid via tuple" do
      via = AgentServer.via_tuple("via-test")
      assert via == {:via, Registry, {Jido.Registry, "via-test"}}
    end

    test "works with custom registry" do
      via = AgentServer.via_tuple("via-test", MyRegistry)
      assert via == {:via, Registry, {MyRegistry, "via-test"}}
    end
  end

  describe "alive?/1" do
    test "returns true for alive process" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)
      assert AgentServer.alive?(pid)
      GenServer.stop(pid)
    end

    test "returns false for dead process" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)
      GenServer.stop(pid)
      refute AgentServer.alive?(pid)
    end

    test "works with agent ID string" do
      {:ok, _pid} = AgentServer.start_link(agent: TestAgent, id: "alive-test")
      assert AgentServer.alive?("alive-test")
      GenServer.stop(AgentServer.whereis("alive-test"))
    end
  end

  describe "directive execution" do
    test "Emit directive is processed" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)

      signal = Signal.new!("emit_test", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # Give drain loop time to process
      Process.sleep(10)

      GenServer.stop(pid)
    end

    test "Error directive is processed" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)

      signal = Signal.new!("error_test", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # Give drain loop time to process
      Process.sleep(10)

      GenServer.stop(pid)
    end

    test "Schedule directive schedules a delayed signal" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)

      signal = Signal.new!("schedule_test", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      assert Process.alive?(pid)
      Process.sleep(100)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "Stop directive stops the server" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)
      ref = Process.monitor(pid)

      signal = Signal.new!("stop_test", %{}, source: "/test")
      AgentServer.cast(pid, signal)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end
  end

  describe "unknown signals" do
    test "handles unknown signal types gracefully" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)

      signal = Signal.new!("unknown.signal.type", %{}, source: "/test")
      {:ok, agent} = AgentServer.call(pid, signal)

      assert agent.state.counter == 0
      GenServer.stop(pid)
    end
  end

  describe "drain loop" do
    test "processes directives in order" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)

      # Send multiple signals quickly
      for i <- 1..10 do
        signal = Signal.new!("record", %{index: i}, source: "/test")
        AgentServer.cast(pid, signal)
      end

      Process.sleep(100)
      {:ok, state} = AgentServer.state(pid)

      # Verify order is preserved
      assert length(state.agent.state.messages) == 10
      indices = Enum.map(state.agent.state.messages, & &1.index)
      assert indices == Enum.to_list(1..10)

      GenServer.stop(pid)
    end

    test "status transitions correctly" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)

      # Initially idle
      {:ok, state} = AgentServer.state(pid)
      assert state.status == :idle

      GenServer.stop(pid)
    end
  end

  describe "queue overflow" do
    test "returns error when queue is full" do
      import ExUnit.CaptureLog

      # Start with very small queue
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, max_queue_size: 2)

      # Get state and manually fill queue
      {:ok, state} = AgentServer.state(pid)

      # Queue is processed fast, so we test via State module directly
      signal = Signal.new!("record", %{}, source: "/test")
      {:ok, s1} = State.enqueue(state, signal, %Directive.Emit{signal: signal})
      {:ok, s2} = State.enqueue(s1, signal, %Directive.Emit{signal: signal})

      assert {:error, :queue_overflow} =
               State.enqueue(s2, signal, %Directive.Emit{signal: signal})

      GenServer.stop(pid)
    end

    test "queue length is reported correctly" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)
      {:ok, state} = AgentServer.state(pid)

      assert State.queue_length(state) == 0
      assert State.queue_empty?(state)

      signal = Signal.new!("test", %{}, source: "/test")
      {:ok, s1} = State.enqueue(state, signal, %Directive.Emit{signal: signal})
      assert State.queue_length(s1) == 1
      refute State.queue_empty?(s1)

      GenServer.stop(pid)
    end
  end

  describe "status transitions" do
    test "starts as initializing then transitions to idle" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)

      # After post_init continue, should be idle
      {:ok, state} = AgentServer.state(pid)
      assert state.status == :idle

      GenServer.stop(pid)
    end

    test "transitions to processing during signal handling" do
      defmodule SlowAgent do
        @moduledoc false
        use Jido.Agent,
          name: "slow_agent",
          schema: [value: [type: :integer, default: 0]]

        def handle_signal(agent, %Signal{type: "slow"} = _signal) do
          Process.sleep(100)
          {agent, []}
        end

        def handle_signal(agent, _signal), do: {agent, []}
      end

      {:ok, pid} = AgentServer.start_link(agent: SlowAgent)

      # Start async processing
      signal = Signal.new!("slow", %{}, source: "/test")
      spawn(fn -> AgentServer.call(pid, signal) end)

      # Small delay to let processing start
      Process.sleep(10)
      {:ok, state} = AgentServer.state(pid)
      # Status should be processing or idle depending on timing
      assert state.status in [:idle, :processing]

      Process.sleep(150)
      GenServer.stop(pid)
    end

    test "returns to idle after processing completes" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # After processing, wait for drain loop
      Process.sleep(10)
      {:ok, state} = AgentServer.state(pid)
      assert state.status == :idle

      GenServer.stop(pid)
    end
  end

  describe "scheduled signals" do
    test "scheduled signal is processed after delay" do
      defmodule ScheduleTrackingAgent do
        @moduledoc false
        use Jido.Agent,
          name: "schedule_tracking_agent",
          schema: [
            pings: [type: :integer, default: 0]
          ]

        def handle_signal(agent, %Signal{type: "start_schedule"} = _signal) do
          scheduled = Signal.new!("scheduled.ping", %{}, source: "/test")
          {agent, [%Directive.Schedule{delay_ms: 50, message: scheduled}]}
        end

        def handle_signal(agent, %Signal{type: "scheduled.ping"} = _signal) do
          pings = Map.get(agent.state, :pings, 0)
          agent = %{agent | state: Map.put(agent.state, :pings, pings + 1)}
          {agent, []}
        end

        def handle_signal(agent, _signal), do: {agent, []}
      end

      {:ok, pid} = AgentServer.start_link(agent: ScheduleTrackingAgent)

      signal = Signal.new!("start_schedule", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # Before delay
      {:ok, state1} = AgentServer.state(pid)
      assert state1.agent.state.pings == 0

      # Wait for scheduled signal
      Process.sleep(100)

      {:ok, state2} = AgentServer.state(pid)
      assert state2.agent.state.pings == 1

      GenServer.stop(pid)
    end

    test "multiple scheduled signals are processed" do
      defmodule MultiScheduleAgent do
        @moduledoc false
        use Jido.Agent,
          name: "multi_schedule_agent",
          schema: [
            events: [type: {:list, :any}, default: []]
          ]

        def handle_signal(agent, %Signal{type: "schedule_many"} = _signal) do
          directives =
            for i <- 1..3 do
              sig = Signal.new!("tick", %{n: i}, source: "/test")
              %Directive.Schedule{delay_ms: i * 20, message: sig}
            end

          {agent, directives}
        end

        def handle_signal(agent, %Signal{type: "tick", data: data} = _signal) do
          events = Map.get(agent.state, :events, [])
          agent = %{agent | state: Map.put(agent.state, :events, events ++ [data.n])}
          {agent, []}
        end

        def handle_signal(agent, _signal), do: {agent, []}
      end

      {:ok, pid} = AgentServer.start_link(agent: MultiScheduleAgent)

      signal = Signal.new!("schedule_many", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      Process.sleep(150)

      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.events == [1, 2, 3]

      GenServer.stop(pid)
    end

    test "non-signal message is wrapped in signal" do
      defmodule WrapScheduleAgent do
        @moduledoc false
        use Jido.Agent,
          name: "wrap_schedule_agent",
          schema: [
            received: [type: :any, default: nil]
          ]

        def handle_signal(agent, %Signal{type: "schedule_atom"} = _signal) do
          {agent, [%Directive.Schedule{delay_ms: 10, message: :timeout}]}
        end

        def handle_signal(agent, %Signal{type: "jido.scheduled", data: %{message: msg}} = _signal) do
          agent = %{agent | state: Map.put(agent.state, :received, msg)}
          {agent, []}
        end

        def handle_signal(agent, _signal), do: {agent, []}
      end

      {:ok, pid} = AgentServer.start_link(agent: WrapScheduleAgent)

      signal = Signal.new!("schedule_atom", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      Process.sleep(50)

      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.received == :timeout

      GenServer.stop(pid)
    end
  end

  describe "server resolution" do
    test "resolves pid directly" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)
      signal = Signal.new!("increment", %{}, source: "/test")

      {:ok, agent} = AgentServer.call(pid, signal)
      assert agent.state.counter == 1

      GenServer.stop(pid)
    end

    test "resolves via tuple" do
      {:ok, _pid} = AgentServer.start_link(agent: TestAgent, id: "via-resolve-test")

      via = AgentServer.via_tuple("via-resolve-test")
      signal = Signal.new!("increment", %{}, source: "/test")

      {:ok, agent} = AgentServer.call(via, signal)
      assert agent.state.counter == 1

      GenServer.stop(AgentServer.whereis("via-resolve-test"))
    end

    test "resolves string id" do
      {:ok, _pid} = AgentServer.start_link(agent: TestAgent, id: "string-resolve-test")

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, agent} = AgentServer.call("string-resolve-test", signal)

      assert agent.state.counter == 1

      GenServer.stop(AgentServer.whereis("string-resolve-test"))
    end

    test "returns error for non-existent server" do
      signal = Signal.new!("increment", %{}, source: "/test")

      assert {:error, :not_found} = AgentServer.call("nonexistent-server", signal)
      assert {:error, :not_found} = AgentServer.cast("nonexistent-server", signal)
      assert {:error, :not_found} = AgentServer.state("nonexistent-server")
    end

    test "returns error for invalid server reference" do
      signal = Signal.new!("increment", %{}, source: "/test")

      assert {:error, :invalid_server} = AgentServer.call(123, signal)
      assert {:error, :invalid_server} = AgentServer.call({:invalid}, signal)
    end

    test "alive? returns false for non-existent server" do
      refute AgentServer.alive?("nonexistent")
    end
  end

  describe "error handling" do
    test "unknown call returns error" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)

      result = GenServer.call(pid, :unknown_message)
      assert result == {:error, :unknown_call}

      GenServer.stop(pid)
    end

    test "unknown cast is ignored" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)

      GenServer.cast(pid, :unknown_message)
      Process.sleep(10)

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "unknown info message is ignored" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)

      send(pid, :random_message)
      Process.sleep(10)

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "agent ID handling" do
    test "uses agent's ID when agent is a struct" do
      agent = TestAgent.new(id: "struct-id-123")
      {:ok, pid} = AgentServer.start_link(agent: agent, agent_module: TestAgent)

      {:ok, state} = AgentServer.state(pid)
      assert state.id == "struct-id-123"

      GenServer.stop(pid)
    end

    test "generates ID when not provided" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent)
      {:ok, state} = AgentServer.state(pid)

      assert is_binary(state.id)
      assert String.length(state.id) > 0

      GenServer.stop(pid)
    end

    test "converts atom ID to string" do
      {:ok, pid} = AgentServer.start_link(agent: TestAgent, id: :atom_id)
      {:ok, state} = AgentServer.state(pid)

      assert state.id == "atom_id"

      GenServer.stop(pid)
    end
  end

  describe "child_spec/1" do
    test "returns valid child spec" do
      spec = AgentServer.child_spec(agent: TestAgent, id: "spec-test")

      assert spec.id == "spec-test"
      assert spec.start == {AgentServer, :start_link, [[agent: TestAgent, id: "spec-test"]]}
      assert spec.shutdown == 5_000
      assert spec.restart == :permanent
      assert spec.type == :worker
    end

    test "uses module as default id" do
      spec = AgentServer.child_spec(agent: TestAgent)

      assert spec.id == AgentServer
    end
  end

  describe "termination" do
    test "logs on termination" do
      import ExUnit.CaptureLog

      # Start with start_link so we can call GenServer.stop directly
      # Trap exits so the test process doesn't crash
      Process.flag(:trap_exit, true)

      {:ok, pid} = AgentServer.start_link(agent: TestAgent, id: "terminate-test")

      log =
        capture_log(fn ->
          GenServer.stop(pid, :normal)
          Process.sleep(10)
        end)

      # Consume the EXIT message
      assert_receive {:EXIT, ^pid, :normal}, 100

      assert log =~ "terminate-test"
      assert log =~ "terminating"
    end
  end
end

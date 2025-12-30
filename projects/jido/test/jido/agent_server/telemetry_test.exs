defmodule JidoTest.AgentServer.TelemetryTest do
  use ExUnit.Case, async: false

  alias Jido.AgentServer
  alias Jido.Agent.Directive
  alias Jido.Signal

  defmodule TelemetryAgent do
    @moduledoc false
    use Jido.Agent,
      name: "telemetry_agent",
      schema: [
        counter: [type: :integer, default: 0]
      ]

    def handle_signal(agent, %Signal{type: "increment"} = _signal) do
      count = Map.get(agent.state, :counter, 0)
      agent = %{agent | state: Map.put(agent.state, :counter, count + 1)}
      {agent, []}
    end

    def handle_signal(agent, %Signal{type: "emit_directive"} = _signal) do
      signal = Signal.new!("test.emitted", %{}, source: "/test")
      {agent, [%Directive.Emit{signal: signal}]}
    end

    def handle_signal(agent, %Signal{type: "schedule_directive"} = _signal) do
      {agent, [%Directive.Schedule{delay_ms: 100, message: :tick}]}
    end

    def handle_signal(agent, _signal) do
      {agent, []}
    end
  end

  setup do
    test_pid = self()

    handler_id = "test-telemetry-handler-#{:erlang.unique_integer()}"

    :telemetry.attach_many(
      handler_id,
      [
        [:jido, :agent_server, :signal, :start],
        [:jido, :agent_server, :signal, :stop],
        [:jido, :agent_server, :signal, :exception],
        [:jido, :agent_server, :directive, :start],
        [:jido, :agent_server, :directive, :stop],
        [:jido, :agent_server, :directive, :exception],
        [:jido, :agent_server, :queue, :overflow]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach(handler_id)
    end)

    :ok
  end

  describe "signal telemetry" do
    test "emits start and stop events for signal processing" do
      {:ok, pid} = AgentServer.start_link(agent: TelemetryAgent, id: "telemetry-signal-test")

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :start], measurements,
                      metadata}

      assert is_integer(measurements.system_time)
      assert metadata.agent_id == "telemetry-signal-test"
      assert metadata.signal_type == "increment"

      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :stop], measurements,
                      metadata}

      assert is_integer(measurements.duration)
      assert measurements.duration >= 0
      assert metadata.directive_count == 0

      GenServer.stop(pid)
    end

    test "includes directive count in stop event" do
      {:ok, pid} = AgentServer.start_link(agent: TelemetryAgent, id: "telemetry-directive-count")

      signal = Signal.new!("emit_directive", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :start], _, _}

      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :stop], _, metadata}

      assert metadata.directive_count == 1

      GenServer.stop(pid)
    end
  end

  describe "directive telemetry" do
    test "emits start and stop events for directive execution" do
      {:ok, pid} = AgentServer.start_link(agent: TelemetryAgent, id: "telemetry-directive-test")

      signal = Signal.new!("emit_directive", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # Signal events
      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :start], _, _}
      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :stop], _, _}

      # Wait for directive to be processed in drain loop
      await_telemetry_event([:jido, :agent_server, :directive, :start])

      assert_receive {:telemetry_event, [:jido, :agent_server, :directive, :start], measurements,
                      metadata}

      assert is_integer(measurements.system_time)
      assert metadata.agent_id == "telemetry-directive-test"
      assert metadata.directive_type == "Emit"

      assert_receive {:telemetry_event, [:jido, :agent_server, :directive, :stop], measurements,
                      metadata}

      assert is_integer(measurements.duration)
      assert metadata.result == :async

      GenServer.stop(pid)
    end

    test "reports correct directive type" do
      {:ok, pid} = AgentServer.start_link(agent: TelemetryAgent, id: "telemetry-type-test")

      signal = Signal.new!("schedule_directive", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # Skip signal events
      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :start], _, _}
      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :stop], _, _}

      await_telemetry_event([:jido, :agent_server, :directive, :start])

      assert_receive {:telemetry_event, [:jido, :agent_server, :directive, :start], _, metadata}

      assert metadata.directive_type == "Schedule"

      assert_receive {:telemetry_event, [:jido, :agent_server, :directive, :stop], _, metadata}

      assert metadata.result == :ok

      GenServer.stop(pid)
    end
  end

  describe "metadata correctness" do
    test "includes agent_id and agent_module in signal events" do
      {:ok, pid} =
        AgentServer.start_link(agent: TelemetryAgent, id: "telemetry-metadata-test")

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :start], _, metadata}

      assert metadata.agent_id == "telemetry-metadata-test"
      assert metadata.agent_module == TelemetryAgent
      assert metadata.signal_type == "increment"

      GenServer.stop(pid)
    end

    test "includes signal_type in directive events" do
      {:ok, pid} =
        AgentServer.start_link(agent: TelemetryAgent, id: "telemetry-signal-type-test")

      signal = Signal.new!("emit_directive", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # Skip signal events
      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :start], _, _}
      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :stop], _, _}

      await_telemetry_event([:jido, :agent_server, :directive, :start])

      assert_receive {:telemetry_event, [:jido, :agent_server, :directive, :start], _, metadata}

      assert metadata.signal_type == "emit_directive"

      GenServer.stop(pid)
    end
  end

  describe "timing measurements" do
    test "duration is positive for signal processing" do
      {:ok, pid} = AgentServer.start_link(agent: TelemetryAgent, id: "telemetry-timing-test")

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :stop], measurements, _}

      assert measurements.duration >= 0

      GenServer.stop(pid)
    end

    test "duration is positive for directive execution" do
      {:ok, pid} =
        AgentServer.start_link(agent: TelemetryAgent, id: "telemetry-directive-timing")

      signal = Signal.new!("emit_directive", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # Skip signal events
      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :start], _, _}
      assert_receive {:telemetry_event, [:jido, :agent_server, :signal, :stop], _, _}

      await_telemetry_event([:jido, :agent_server, :directive, :stop])

      assert_receive {:telemetry_event, [:jido, :agent_server, :directive, :stop], measurements,
                      _}

      assert measurements.duration >= 0

      GenServer.stop(pid)
    end
  end

  # Helper to wait for async telemetry events
  defp await_telemetry_event(event, timeout \\ 500) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_telemetry_event(event, deadline)
  end

  defp do_await_telemetry_event(event, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      flunk("Timed out waiting for telemetry event #{inspect(event)}")
    end

    receive do
      {:telemetry_event, ^event, _, _} = msg ->
        send(self(), msg)
        :ok
    after
      10 ->
        do_await_telemetry_event(event, deadline)
    end
  end
end

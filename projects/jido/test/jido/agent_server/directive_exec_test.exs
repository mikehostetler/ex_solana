defmodule JidoTest.AgentServer.DirectiveExecTest do
  use JidoTest.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.AgentServer.{DirectiveExec, State, Options}
  alias Jido.Signal

  defmodule TestAgent do
    @moduledoc false
    use Jido.Agent,
      name: "directive_exec_test_agent",
      schema: [
        counter: [type: :integer, default: 0]
      ]
  end

  defmodule CustomDirective do
    @moduledoc false
    defstruct [:value]
  end

  setup %{jido: jido} do
    agent = TestAgent.new()

    {:ok, opts} = Options.new(%{agent: agent, id: "test-agent-123", jido: jido})
    {:ok, state} = State.from_options(opts, agent.__struct__, agent)

    input_signal = Signal.new!(%{type: "test.signal", source: "/test", data: %{}})

    %{state: state, input_signal: input_signal, agent: agent}
  end

  describe "Emit directive" do
    test "returns async tuple with nil ref when no dispatch config", %{
      state: state,
      input_signal: input_signal
    } do
      signal = Signal.new!(%{type: "test.emitted", source: "/test", data: %{}})
      directive = %Directive.Emit{signal: signal, dispatch: nil}

      assert {:async, nil, ^state} = DirectiveExec.exec(directive, input_signal, state)
    end

    test "returns async tuple when dispatch config provided", %{
      state: state,
      input_signal: input_signal
    } do
      signal = Signal.new!(%{type: "test.emitted", source: "/test", data: %{}})
      directive = %Directive.Emit{signal: signal, dispatch: {:logger, level: :info}}

      assert {:async, nil, ^state} = DirectiveExec.exec(directive, input_signal, state)
    end

    test "uses default_dispatch from state when directive dispatch is nil", %{
      input_signal: input_signal,
      agent: agent,
      jido: jido
    } do
      {:ok, opts} =
        Options.new(%{
          agent: agent,
          id: "test-agent-dispatch",
          default_dispatch: {:logger, level: :debug},
          jido: jido
        })

      {:ok, state} = State.from_options(opts, agent.__struct__, agent)

      signal = Signal.new!(%{type: "test.emitted", source: "/test", data: %{}})
      directive = %Directive.Emit{signal: signal, dispatch: nil}

      assert {:async, nil, ^state} = DirectiveExec.exec(directive, input_signal, state)
    end
  end

  describe "Error directive" do
    test "returns ok with log_only policy", %{state: state, input_signal: input_signal} do
      error = Jido.Error.validation_error("Test error")
      directive = %Directive.Error{error: error, context: :test}

      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
    end

    test "returns stop with stop_on_error policy", %{
      input_signal: input_signal,
      agent: agent,
      jido: jido
    } do
      {:ok, opts} =
        Options.new(%{
          agent: agent,
          id: "test-agent-stop",
          error_policy: :stop_on_error,
          jido: jido
        })

      {:ok, state} = State.from_options(opts, agent.__struct__, agent)

      error = Jido.Error.validation_error("Test error")
      directive = %Directive.Error{error: error, context: :test}

      assert {:stop, {:agent_error, ^error}, ^state} =
               DirectiveExec.exec(directive, input_signal, state)
    end

    test "increments error_count with max_errors policy", %{
      input_signal: input_signal,
      agent: agent,
      jido: jido
    } do
      {:ok, opts} =
        Options.new(%{
          agent: agent,
          id: "test-agent-max",
          error_policy: {:max_errors, 3},
          jido: jido
        })

      {:ok, state} = State.from_options(opts, agent.__struct__, agent)
      assert state.error_count == 0

      error = Jido.Error.validation_error("Test error")
      directive = %Directive.Error{error: error, context: :test}

      {:ok, state} = DirectiveExec.exec(directive, input_signal, state)
      assert state.error_count == 1

      {:ok, state} = DirectiveExec.exec(directive, input_signal, state)
      assert state.error_count == 2

      {:stop, {:max_errors_exceeded, 3}, state} =
        DirectiveExec.exec(directive, input_signal, state)

      assert state.error_count == 3
    end
  end

  describe "Spawn directive" do
    test "spawns child using custom spawn_fun", %{
      input_signal: input_signal,
      agent: agent,
      jido: jido
    } do
      test_pid = self()

      spawn_fun = fn child_spec ->
        send(test_pid, {:spawn_called, child_spec})
        {:ok, spawn(fn -> :ok end)}
      end

      {:ok, opts} =
        Options.new(%{
          agent: agent,
          id: "test-agent-spawn",
          spawn_fun: spawn_fun,
          jido: jido
        })

      {:ok, state} = State.from_options(opts, agent.__struct__, agent)

      child_spec = {Task, fn -> :ok end}
      directive = %Directive.Spawn{child_spec: child_spec, tag: :worker}

      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
      assert_receive {:spawn_called, ^child_spec}
    end

    test "handles spawn failure gracefully", %{
      input_signal: input_signal,
      agent: agent,
      jido: jido
    } do
      spawn_fun = fn _child_spec ->
        {:error, :spawn_failed}
      end

      {:ok, opts} =
        Options.new(%{
          agent: agent,
          id: "test-agent-spawn-fail",
          spawn_fun: spawn_fun,
          jido: jido
        })

      {:ok, state} = State.from_options(opts, agent.__struct__, agent)

      child_spec = {Task, fn -> :ok end}
      directive = %Directive.Spawn{child_spec: child_spec, tag: :worker}

      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
    end
  end

  describe "Schedule directive" do
    test "sends scheduled signal after delay", %{state: state, input_signal: input_signal} do
      signal = Signal.new!(%{type: "scheduled.ping", source: "/test", data: %{}})
      directive = %Directive.Schedule{delay_ms: 10, message: signal}

      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
      assert_receive {:scheduled_signal, received_signal}, 100
      assert received_signal.type == "scheduled.ping"
    end

    test "wraps non-signal message in signal", %{state: state, input_signal: input_signal} do
      directive = %Directive.Schedule{delay_ms: 10, message: :timeout}

      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
      assert_receive {:scheduled_signal, received_signal}, 100
      assert received_signal.type == "jido.scheduled"
      assert received_signal.data.message == :timeout
    end
  end

  describe "Stop directive" do
    test "returns stop tuple with reason", %{state: state, input_signal: input_signal} do
      directive = %Directive.Stop{reason: :normal}

      assert {:stop, :normal, ^state} = DirectiveExec.exec(directive, input_signal, state)
    end

    test "returns stop tuple with custom reason", %{state: state, input_signal: input_signal} do
      directive = %Directive.Stop{reason: {:shutdown, :user_requested}}

      assert {:stop, {:shutdown, :user_requested}, ^state} =
               DirectiveExec.exec(directive, input_signal, state)
    end
  end

  describe "Any (fallback) directive" do
    test "returns ok for unknown directive types", %{state: state, input_signal: input_signal} do
      directive = %CustomDirective{value: 42}

      assert {:ok, ^state} = DirectiveExec.exec(directive, input_signal, state)
    end
  end
end

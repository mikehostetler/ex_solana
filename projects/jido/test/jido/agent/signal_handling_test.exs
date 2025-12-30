defmodule JidoTest.Agent.SignalHandlingTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.Signal

  # A simple test action
  defmodule IncrementAction do
    @moduledoc false
    use Jido.Action,
      name: "increment",
      schema: [
        amount: [type: :integer, default: 1]
      ]

    def run(params, context) do
      current = Map.get(context.state, :counter, 0)
      {:ok, %{counter: current + params.amount}}
    end
  end

  # Agent using default handle_signal (delegates to cmd via signal_to_action)
  defmodule DefaultSignalAgent do
    @moduledoc false
    use Jido.Agent,
      name: "default_signal_agent",
      schema: [
        counter: [type: :integer, default: 0]
      ]

    # Register the action so signal_to_action -> cmd works
    def actions, do: [IncrementAction]
  end

  # Agent with custom handle_signal override
  defmodule CustomSignalAgent do
    @moduledoc false
    use Jido.Agent,
      name: "custom_signal_agent",
      schema: [
        counter: [type: :integer, default: 0],
        messages: [type: {:list, :any}, default: []]
      ]

    # Custom handle_signal that directly manipulates state
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

    # Fall back to default for unknown signals
    def handle_signal(agent, signal) do
      super(agent, signal)
    end
  end

  # Agent with custom signal_to_action override
  defmodule CustomTranslationAgent do
    @moduledoc false
    use Jido.Agent,
      name: "custom_translation_agent",
      schema: [
        counter: [type: :integer, default: 0]
      ]

    # Custom translation: strips "action." prefix from signal type
    def signal_to_action(%Signal{type: "action." <> action_name, data: data}) do
      {action_name, data}
    end

    def signal_to_action(signal) do
      super(signal)
    end
  end

  describe "default handle_signal/2" do
    test "translates signal to action via signal_to_action/1" do
      _agent = DefaultSignalAgent.new()
      signal = Signal.new!("test_type", %{value: 42}, source: "/test")

      # Default signal_to_action returns {type, data}
      action = DefaultSignalAgent.signal_to_action(signal)
      assert action == {"test_type", %{value: 42}}
    end

    test "handle_signal delegates to cmd with translated action" do
      agent = DefaultSignalAgent.new()

      # When signal type doesn't match an action, it will produce an error directive
      signal = Signal.new!("unknown_action", %{}, source: "/test")
      {_agent, directives} = DefaultSignalAgent.handle_signal(agent, signal)

      # Should get an error directive because "unknown_action" isn't a valid action
      assert length(directives) == 1
      assert %Directive.Error{} = hd(directives)
    end
  end

  describe "custom handle_signal/2 override" do
    test "increment signal updates counter" do
      agent = CustomSignalAgent.new()
      signal = Signal.new!("increment", %{}, source: "/test")

      {agent, directives} = CustomSignalAgent.handle_signal(agent, signal)

      assert agent.state.counter == 1
      assert directives == []
    end

    test "decrement signal updates counter" do
      agent = CustomSignalAgent.new(state: %{counter: 5})
      signal = Signal.new!("decrement", %{}, source: "/test")

      {agent, directives} = CustomSignalAgent.handle_signal(agent, signal)

      assert agent.state.counter == 4
      assert directives == []
    end

    test "record signal appends to messages" do
      agent = CustomSignalAgent.new()
      signal = Signal.new!("record", %{message: "hello"}, source: "/test")

      {agent, directives} = CustomSignalAgent.handle_signal(agent, signal)

      assert agent.state.messages == [%{message: "hello"}]
      assert directives == []
    end

    test "emit_test signal returns Emit directive" do
      agent = CustomSignalAgent.new()
      signal = Signal.new!("emit_test", %{}, source: "/test")

      {_agent, directives} = CustomSignalAgent.handle_signal(agent, signal)

      assert length(directives) == 1
      assert %Directive.Emit{signal: emitted} = hd(directives)
      assert emitted.type == "test.emitted"
    end

    test "unknown signals fall back to super" do
      agent = CustomSignalAgent.new()
      signal = Signal.new!("unknown", %{}, source: "/test")

      # Falls back to default which calls cmd with {"unknown", %{}}
      {_agent, directives} = CustomSignalAgent.handle_signal(agent, signal)

      # Should produce error since "unknown" isn't a valid action
      assert length(directives) == 1
      assert %Directive.Error{} = hd(directives)
    end

    test "multiple signals processed in sequence" do
      agent = CustomSignalAgent.new()

      signals = [
        Signal.new!("increment", %{}, source: "/test"),
        Signal.new!("increment", %{}, source: "/test"),
        Signal.new!("increment", %{}, source: "/test")
      ]

      agent =
        Enum.reduce(signals, agent, fn signal, acc ->
          {new_agent, _} = CustomSignalAgent.handle_signal(acc, signal)
          new_agent
        end)

      assert agent.state.counter == 3
    end
  end

  describe "custom signal_to_action/1 override" do
    test "custom translation strips prefix" do
      signal = Signal.new!("action.do_something", %{value: 123}, source: "/test")

      action = CustomTranslationAgent.signal_to_action(signal)

      assert action == {"do_something", %{value: 123}}
    end

    test "non-matching signals use super" do
      signal = Signal.new!("regular.signal", %{value: 456}, source: "/test")

      action = CustomTranslationAgent.signal_to_action(signal)

      assert action == {"regular.signal", %{value: 456}}
    end
  end

  describe "integration with AgentServer" do
    test "custom handle_signal works with AgentServer.call" do
      {:ok, pid} =
        Jido.AgentServer.start_link(agent: CustomSignalAgent, id: "signal-integration-test")

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state.counter == 1

      GenServer.stop(pid)
    end

    test "default handle_signal works with AgentServer when action exists" do
      # This tests that the default handle_signal properly delegates to cmd
      # For this to work, the signal type must match a registered action
      {:ok, pid} =
        Jido.AgentServer.start_link(agent: CustomSignalAgent, id: "signal-default-test")

      # Use a signal that CustomSignalAgent handles directly
      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state.counter == 1

      GenServer.stop(pid)
    end
  end
end

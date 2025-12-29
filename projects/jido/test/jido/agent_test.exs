defmodule JidoTest.AgentTest do
  use ExUnit.Case, async: true

  alias Jido.Agent

  # Test agent modules
  defmodule MinimalAgent do
    use Jido.Agent,
      name: "minimal_agent"
  end

  defmodule BasicAgent do
    use Jido.Agent,
      name: "basic_agent",
      description: "A basic test agent",
      category: "test",
      tags: ["test", "basic"],
      vsn: "1.0.0",
      schema: [
        counter: [type: :integer, default: 0],
        status: [type: :atom, default: :idle]
      ]
  end

  defmodule HookAgent do
    use Jido.Agent,
      name: "hook_agent",
      schema: [
        counter: [type: :integer, default: 0]
      ]

    def on_after_cmd(agent, _action, directives) do
      {:ok, %{agent | state: Map.put(agent.state, :hook_called, true)}, directives}
    end
  end

  # Custom strategy that tracks execution count
  defmodule CountingStrategy do
    @behaviour Jido.Agent.Strategy

    @impl true
    def cmd(agent, action, ctx) do
      # Track how many times strategy was called
      count = Map.get(agent.state, :strategy_count, 0)
      agent = %{agent | state: Map.put(agent.state, :strategy_count, count + 1)}

      # Delegate to Direct strategy for actual execution
      Jido.Agent.Strategy.Direct.cmd(agent, action, ctx)
    end
  end

  defmodule CustomStrategyAgent do
    use Jido.Agent,
      name: "custom_strategy_agent",
      strategy: JidoTest.AgentTest.CountingStrategy
  end

  defmodule StrategyWithOptsAgent do
    use Jido.Agent,
      name: "strategy_opts_agent",
      strategy: {JidoTest.AgentTest.CountingStrategy, max_depth: 5}
  end

  describe "module definition" do
    test "defines metadata accessors" do
      assert BasicAgent.name() == "basic_agent"
      assert BasicAgent.description() == "A basic test agent"
      assert BasicAgent.category() == "test"
      assert BasicAgent.tags() == ["test", "basic"]
      assert BasicAgent.vsn() == "1.0.0"
    end

    test "minimal agent has default values" do
      assert MinimalAgent.name() == "minimal_agent"
      assert MinimalAgent.description() == nil
      assert MinimalAgent.schema() == []
    end
  end

  describe "new/1" do
    test "creates agent with auto-generated id" do
      agent = MinimalAgent.new()
      assert is_binary(agent.id)
      assert String.length(agent.id) > 0
    end

    test "creates agent with custom id" do
      agent = MinimalAgent.new(id: "custom-123")
      assert agent.id == "custom-123"
    end

    test "creates agent with initial state" do
      agent = BasicAgent.new(state: %{counter: 10})
      assert agent.state.counter == 10
      assert agent.state.status == :idle
    end

    test "applies schema defaults to state" do
      agent = BasicAgent.new()
      assert agent.state.counter == 0
      assert agent.state.status == :idle
    end

    test "merges initial state with defaults" do
      agent = BasicAgent.new(state: %{counter: 5})
      assert agent.state.counter == 5
      assert agent.state.status == :idle
    end

    test "populates agent metadata" do
      agent = BasicAgent.new()
      assert agent.name == "basic_agent"
      assert agent.description == "A basic test agent"
      assert agent.category == "test"
      assert agent.tags == ["test", "basic"]
      assert agent.vsn == "1.0.0"
    end

    test "uses default strategy" do
      assert BasicAgent.strategy() == Jido.Agent.Strategy.Direct
      assert BasicAgent.strategy_opts() == []
    end
  end

  describe "set/2" do
    test "updates state with map" do
      agent = BasicAgent.new()
      {:ok, updated} = BasicAgent.set(agent, %{counter: 42})
      assert updated.state.counter == 42
    end

    test "updates state with keyword list" do
      agent = BasicAgent.new()
      {:ok, updated} = BasicAgent.set(agent, counter: 42, status: :running)
      assert updated.state.counter == 42
      assert updated.state.status == :running
    end

    test "deep merges nested maps" do
      agent = BasicAgent.new(state: %{config: %{a: 1, b: 2}})
      {:ok, updated} = BasicAgent.set(agent, %{config: %{b: 3, c: 4}})
      assert updated.state.config == %{a: 1, b: 3, c: 4}
    end
  end

  describe "validate/2" do
    test "validates state against schema" do
      agent = BasicAgent.new()
      {:ok, validated} = BasicAgent.validate(agent)
      assert validated.state.counter == 0
      assert validated.state.status == :idle
    end

    test "preserves extra fields in non-strict mode" do
      agent = BasicAgent.new(state: %{counter: 0, extra_field: "hello"})
      {:ok, validated} = BasicAgent.validate(agent)
      assert validated.state.extra_field == "hello"
    end

    test "strict mode only keeps schema fields" do
      agent = BasicAgent.new(state: %{counter: 0, status: :idle, extra_field: "hello"})
      {:ok, validated} = BasicAgent.validate(agent, strict: true)
      refute Map.has_key?(validated.state, :extra_field)
    end
  end

  describe "cmd/2" do
    test "executes action module" do
      agent = BasicAgent.new()
      {updated, _directives} = BasicAgent.cmd(agent, JidoTest.TestActions.NoSchema)
      assert updated.state.result == "No params"
    end

    test "executes action tuple" do
      agent = BasicAgent.new()

      {updated, _directives} =
        BasicAgent.cmd(agent, {JidoTest.TestActions.BasicAction, %{value: 42}})

      assert updated.state.value == 42
    end

    test "executes list of actions" do
      agent = BasicAgent.new()

      {updated, directives} =
        BasicAgent.cmd(agent, [
          {JidoTest.TestActions.Add, %{value: 5, amount: 3}},
          JidoTest.TestActions.NoSchema
        ])

      assert updated.state.value == 8
      assert updated.state.result == "No params"
      assert directives == []
    end

    test "handles %Instruction{} struct directly" do
      agent = BasicAgent.new()

      {:ok, instruction} =
        Jido.Instruction.new(%{action: JidoTest.TestActions.BasicAction, params: %{value: 99}})

      {updated, _directives} = BasicAgent.cmd(agent, instruction)
      assert updated.state.value == 99
    end

    test "emits error directive for invalid action params" do
      agent = BasicAgent.new()
      {_agent, directives} = BasicAgent.cmd(agent, {JidoTest.TestActions.BasicAction, %{}})

      assert [%Jido.Agent.Directive.Error{context: :instruction, error: error}] = directives
      assert error.message == "Instruction failed"
    end

    test "invalid input format returns error directive" do
      agent = BasicAgent.new()
      {updated, directives} = BasicAgent.cmd(agent, {:unknown, "whatever"})

      # Agent state unchanged
      assert updated.state == agent.state
      # Error directive emitted for normalization failure
      assert [%Jido.Agent.Directive.Error{context: :normalize}] = directives
    end
  end

  describe "lifecycle hooks" do
    test "on_after_cmd is called after processing" do
      agent = HookAgent.new()
      refute Map.has_key?(agent.state, :hook_called)

      {updated, _} = HookAgent.cmd(agent, JidoTest.TestActions.NoSchema)
      assert updated.state.hook_called == true
    end
  end

  describe "strategy" do
    test "default strategy is Direct" do
      assert BasicAgent.strategy() == Jido.Agent.Strategy.Direct
      assert BasicAgent.strategy_opts() == []
    end

    test "custom strategy module is used" do
      assert CustomStrategyAgent.strategy() == JidoTest.AgentTest.CountingStrategy
      assert CustomStrategyAgent.strategy_opts() == []
    end

    test "strategy with options extracts module and opts" do
      assert StrategyWithOptsAgent.strategy() == JidoTest.AgentTest.CountingStrategy
      assert StrategyWithOptsAgent.strategy_opts() == [max_depth: 5]
    end

    test "custom strategy is invoked during cmd/2" do
      agent = CustomStrategyAgent.new()
      refute Map.has_key?(agent.state, :strategy_count)

      {updated, _} = CustomStrategyAgent.cmd(agent, JidoTest.TestActions.NoSchema)
      assert updated.state.strategy_count == 1

      {updated2, _} = CustomStrategyAgent.cmd(updated, JidoTest.TestActions.NoSchema)
      assert updated2.state.strategy_count == 2
    end
  end

  describe "base module functions" do
    test "Agent.new/1 creates agent from attrs" do
      {:ok, agent} = Agent.new(%{name: "test_agent", id: "test-123"})
      assert agent.id == "test-123"
      assert agent.name == "test_agent"
    end

    test "Agent.set/2 updates state" do
      {:ok, agent} = Agent.new(%{id: "test"})
      {:ok, updated} = Agent.set(agent, %{key: "value"})
      assert updated.state.key == "value"
    end

    test "Agent.new/1 returns error for invalid id type" do
      # Base new/1 uses Zoi struct schema which validates types
      {:error, error} = Agent.new(%{id: 12345})
      assert error.message == "Agent validation failed"
    end
  end

  describe "directives" do
    alias Jido.Agent.Directive

    test "Directive.emit/1 creates Emit directive" do
      signal = %{type: "test.event", data: %{}}
      directive = Directive.emit(signal)

      assert %Directive.Emit{signal: ^signal, dispatch: nil} = directive
    end

    test "Directive.emit/2 creates Emit with dispatch config" do
      signal = %{type: "test.event"}
      dispatch = {:pubsub, topic: "events"}
      directive = Directive.emit(signal, dispatch)

      assert %Directive.Emit{signal: ^signal, dispatch: ^dispatch} = directive
    end

    test "Directive.error/1 creates Error directive" do
      error = Jido.Error.validation_error("Test error")
      directive = Directive.error(error)

      assert %Directive.Error{error: ^error, context: nil} = directive
    end

    test "Directive.error/2 creates Error with context" do
      error = Jido.Error.execution_error("Failed")
      directive = Directive.error(error, :instruction)

      assert %Directive.Error{error: ^error, context: :instruction} = directive
    end

    test "Directive.spawn/1 creates Spawn directive" do
      child_spec = {Task, fn -> :ok end}
      directive = Directive.spawn(child_spec)

      assert %Directive.Spawn{child_spec: ^child_spec, tag: nil} = directive
    end

    test "Directive.spawn/2 creates Spawn with tag" do
      child_spec = {Task, fn -> :ok end}
      directive = Directive.spawn(child_spec, :worker_1)

      assert %Directive.Spawn{child_spec: ^child_spec, tag: :worker_1} = directive
    end

    test "Directive.schedule/2 creates Schedule directive" do
      directive = Directive.schedule(5000, :timeout)

      assert %Directive.Schedule{delay_ms: 5000, message: :timeout} = directive
    end

    test "Directive.stop/0 creates Stop with default reason" do
      directive = Directive.stop()

      assert %Directive.Stop{reason: :normal} = directive
    end

    test "Directive.stop/1 creates Stop with custom reason" do
      directive = Directive.stop(:shutdown)

      assert %Directive.Stop{reason: :shutdown} = directive
    end
  end

  describe "actions returning effects" do
    defmodule EmitAction do
      use Jido.Action,
        name: "emit_action",
        description: "Action that returns an emit effect"

      alias Jido.Agent.Directive

      def run(_params, _context) do
        signal = %{type: "test.emitted", data: %{value: 42}}
        {:ok, %{emitted: true}, Directive.emit(signal)}
      end
    end

    defmodule MultiEffectAction do
      use Jido.Action,
        name: "multi_effect_action",
        description: "Action that returns multiple effects"

      alias Jido.Agent.Directive

      def run(_params, _context) do
        effects = [
          Directive.emit(%{type: "event.1"}),
          Directive.schedule(1000, :check)
        ]

        {:ok, %{triggered: true}, effects}
      end
    end

    defmodule SetStateAction do
      use Jido.Action,
        name: "set_state_action",
        description: "Action that uses Internal.SetState"

      alias Jido.Agent.Internal

      def run(_params, _context) do
        {:ok, %{primary: "result"}, %Internal.SetState{attrs: %{extra: "state"}}}
      end
    end

    test "action can emit signal via directive" do
      agent = BasicAgent.new()
      {updated, directives} = BasicAgent.cmd(agent, EmitAction)

      assert updated.state.emitted == true
      assert [%Jido.Agent.Directive.Emit{signal: signal}] = directives
      assert signal.type == "test.emitted"
    end

    test "action can return multiple directives" do
      agent = BasicAgent.new()
      {updated, directives} = BasicAgent.cmd(agent, MultiEffectAction)

      assert updated.state.triggered == true
      assert length(directives) == 2
      assert [%Jido.Agent.Directive.Emit{}, %Jido.Agent.Directive.Schedule{}] = directives
    end

    test "Internal.SetState modifies agent state but is not returned as directive" do
      agent = BasicAgent.new()
      {updated, directives} = BasicAgent.cmd(agent, SetStateAction)

      # Result merged into state
      assert updated.state.primary == "result"
      # SetState effect also merged into state
      assert updated.state.extra == "state"
      # No directives returned (SetState is internal)
      assert directives == []
    end
  end

  describe "Zoi schema support" do
    defmodule ZoiSchemaAgent do
      use Jido.Agent,
        name: "zoi_schema_agent",
        schema:
          Zoi.object(%{
            status: Zoi.atom() |> Zoi.default(:idle),
            count: Zoi.integer() |> Zoi.default(0)
          })
    end

    test "agent works with Zoi schema" do
      agent = ZoiSchemaAgent.new()
      # Note: Zoi defaults aren't extracted the same way as NimbleOptions
      # The schema is used for validation, not for providing defaults to new/1
      assert agent.name == "zoi_schema_agent"
    end

    test "validate works with Zoi schema" do
      agent = ZoiSchemaAgent.new(state: %{status: :running, count: 5})
      {:ok, validated} = ZoiSchemaAgent.validate(agent)
      assert validated.state.status == :running
      assert validated.state.count == 5
    end
  end
end

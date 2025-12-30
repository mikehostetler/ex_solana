defmodule JidoTest.AgentSkillIntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Skill.Spec

  # =============================================================================
  # Test Fixtures - Actions
  # =============================================================================

  defmodule IncrementAction do
    @moduledoc false
    use Jido.Action,
      name: "increment",
      schema: Zoi.object(%{amount: Zoi.integer() |> Zoi.default(1)})

    alias Jido.Agent.Internal

    def run(%{amount: amount}, %{state: state}) do
      current = get_in(state, [:counter_skill, :count]) || 0
      {:ok, %{}, %Internal.SetPath{path: [:counter_skill, :count], value: current + amount}}
    end
  end

  defmodule DecrementAction do
    @moduledoc false
    use Jido.Action,
      name: "decrement",
      schema: Zoi.object(%{amount: Zoi.integer() |> Zoi.default(1)})

    alias Jido.Agent.Internal

    def run(%{amount: amount}, %{state: state}) do
      current = get_in(state, [:counter_skill, :count]) || 0
      {:ok, %{}, %Internal.SetPath{path: [:counter_skill, :count], value: current - amount}}
    end
  end

  defmodule GreetAction do
    @moduledoc false
    use Jido.Action,
      name: "greet",
      schema: Zoi.object(%{name: Zoi.string() |> Zoi.default("World")})

    alias Jido.Agent.Internal

    def run(%{name: name}, _context) do
      {:ok, %{},
       %Internal.SetPath{path: [:greeter_skill, :last_greeting], value: "Hello, #{name}!"}}
    end
  end

  defmodule SetModeAction do
    @moduledoc false
    use Jido.Action,
      name: "set_mode",
      schema: Zoi.object(%{mode: Zoi.atom()})

    alias Jido.Agent.Internal

    def run(%{mode: mode}, _context) do
      {:ok, %{}, %Internal.SetPath{path: [:mode_skill, :current_mode], value: mode}}
    end
  end

  defmodule SimpleAction do
    @moduledoc false
    use Jido.Action,
      name: "simple_action",
      schema: []

    def run(_params, _context), do: {:ok, %{executed: true}}
  end

  # =============================================================================
  # Test Fixtures - Skills
  # =============================================================================

  defmodule CounterSkill do
    @moduledoc false
    use Jido.Skill,
      name: "counter_skill",
      state_key: :counter_skill,
      actions: [
        JidoTest.AgentSkillIntegrationTest.IncrementAction,
        JidoTest.AgentSkillIntegrationTest.DecrementAction
      ],
      description: "A skill for counting",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
  end

  defmodule GreeterSkill do
    @moduledoc false
    use Jido.Skill,
      name: "greeter_skill",
      state_key: :greeter_skill,
      actions: [JidoTest.AgentSkillIntegrationTest.GreetAction],
      description: "A skill for greeting",
      schema: Zoi.object(%{last_greeting: Zoi.string() |> Zoi.optional()})
  end

  defmodule ConfigurableSkill do
    @moduledoc false
    use Jido.Skill,
      name: "configurable_skill",
      state_key: :configurable,
      actions: [JidoTest.AgentSkillIntegrationTest.SimpleAction],
      description: "A skill with config",
      config_schema:
        Zoi.object(%{
          enabled: Zoi.boolean() |> Zoi.default(true),
          max_retries: Zoi.integer() |> Zoi.default(3)
        }),
      schema: Zoi.object(%{status: Zoi.atom() |> Zoi.default(:ready)})
  end

  defmodule ModeSkill do
    @moduledoc false
    use Jido.Skill,
      name: "mode_skill",
      state_key: :mode_skill,
      actions: [JidoTest.AgentSkillIntegrationTest.SetModeAction],
      schema: Zoi.object(%{current_mode: Zoi.atom() |> Zoi.default(:normal)})
  end

  defmodule MinimalSkill do
    @moduledoc false
    use Jido.Skill,
      name: "minimal_skill",
      state_key: :minimal,
      actions: [JidoTest.AgentSkillIntegrationTest.SimpleAction]
  end

  # =============================================================================
  # Test Fixtures - Agents
  # =============================================================================

  defmodule SingleSkillAgent do
    @moduledoc false
    use Jido.Agent,
      name: "single_skill_agent",
      skills: [JidoTest.AgentSkillIntegrationTest.CounterSkill]
  end

  defmodule MultiSkillAgent do
    @moduledoc false
    use Jido.Agent,
      name: "multi_skill_agent",
      skills: [
        JidoTest.AgentSkillIntegrationTest.CounterSkill,
        JidoTest.AgentSkillIntegrationTest.GreeterSkill
      ]
  end

  defmodule ConfiguredSkillAgent do
    @moduledoc false
    use Jido.Agent,
      name: "configured_skill_agent",
      skills: [
        {JidoTest.AgentSkillIntegrationTest.ConfigurableSkill, %{enabled: false, max_retries: 5}}
      ]
  end

  defmodule MixedSchemaAgent do
    @moduledoc false
    use Jido.Agent,
      name: "mixed_schema_agent",
      schema: [
        base_counter: [type: :integer, default: 100],
        base_mode: [type: :atom, default: :initial]
      ],
      skills: [JidoTest.AgentSkillIntegrationTest.CounterSkill]
  end

  defmodule ThreeSkillAgent do
    @moduledoc false
    use Jido.Agent,
      name: "three_skill_agent",
      skills: [
        JidoTest.AgentSkillIntegrationTest.CounterSkill,
        JidoTest.AgentSkillIntegrationTest.GreeterSkill,
        JidoTest.AgentSkillIntegrationTest.ModeSkill
      ]
  end

  defmodule MinimalSkillAgent do
    @moduledoc false
    use Jido.Agent,
      name: "minimal_skill_agent",
      skills: [JidoTest.AgentSkillIntegrationTest.MinimalSkill]
  end

  # =============================================================================
  # Tests: Agent with Single Skill
  # =============================================================================

  describe "agent with single skill" do
    test "skills/0 returns the skill spec" do
      specs = SingleSkillAgent.skills()

      assert length(specs) == 1
      [spec] = specs
      assert %Spec{} = spec
      assert spec.module == CounterSkill
      assert spec.name == "counter_skill"
      assert spec.state_key == :counter_skill
    end

    test "actions/0 includes skill actions" do
      actions = SingleSkillAgent.actions()

      assert IncrementAction in actions
      assert DecrementAction in actions
      assert length(actions) == 2
    end

    test "schema/0 returns merged schema with skill nested under state_key" do
      schema = SingleSkillAgent.schema()

      assert schema != nil
      keys = Jido.Agent.Schema.known_keys(schema)
      assert :counter_skill in keys
    end

    test "new/0 initializes skill state with defaults under state_key" do
      agent = SingleSkillAgent.new()

      assert agent.state[:counter_skill] != nil
      assert agent.state[:counter_skill][:count] == 0
    end

    test "new/1 with custom state merges correctly" do
      agent = SingleSkillAgent.new(state: %{counter_skill: %{count: 10}})

      assert agent.state[:counter_skill][:count] == 10
    end
  end

  # =============================================================================
  # Tests: Agent with Multiple Skills
  # =============================================================================

  describe "agent with multiple skills" do
    test "skills/0 returns both skill specs" do
      specs = MultiSkillAgent.skills()

      assert length(specs) == 2
      modules = Enum.map(specs, & &1.module)
      assert CounterSkill in modules
      assert GreeterSkill in modules
    end

    test "actions/0 aggregates actions from both skills" do
      actions = MultiSkillAgent.actions()

      assert IncrementAction in actions
      assert DecrementAction in actions
      assert GreetAction in actions
      assert length(actions) == 3
    end

    test "new/0 initializes state for both skills" do
      agent = MultiSkillAgent.new()

      assert agent.state[:counter_skill] != nil
      assert agent.state[:counter_skill][:count] == 0

      assert agent.state[:greeter_skill] != nil
      assert agent.state[:greeter_skill][:last_greeting] == nil
    end

    test "skill states are isolated under their state_keys" do
      agent = MultiSkillAgent.new()

      counter_state = agent.state[:counter_skill]
      greeter_state = agent.state[:greeter_skill]

      assert is_map(counter_state)
      assert is_map(greeter_state)
      assert Map.keys(counter_state) != Map.keys(greeter_state)
    end
  end

  describe "agent with three skills" do
    test "all skill specs are returned" do
      specs = ThreeSkillAgent.skills()

      assert length(specs) == 3
      modules = Enum.map(specs, & &1.module)
      assert CounterSkill in modules
      assert GreeterSkill in modules
      assert ModeSkill in modules
    end

    test "actions from all skills are aggregated" do
      actions = ThreeSkillAgent.actions()

      assert IncrementAction in actions
      assert DecrementAction in actions
      assert GreetAction in actions
      assert SetModeAction in actions
    end

    test "all skill states are initialized" do
      agent = ThreeSkillAgent.new()

      assert agent.state[:counter_skill][:count] == 0
      assert agent.state[:greeter_skill][:last_greeting] == nil
      assert agent.state[:mode_skill][:current_mode] == :normal
    end
  end

  # =============================================================================
  # Tests: Skill with Config
  # =============================================================================

  describe "skill with config" do
    test "skill_config/1 returns the config" do
      config = ConfiguredSkillAgent.skill_config(ConfigurableSkill)

      assert config != nil
      assert config[:enabled] == false
      assert config[:max_retries] == 5
    end

    test "skill_config/1 returns nil for unknown skill module" do
      config = ConfiguredSkillAgent.skill_config(CounterSkill)

      assert config == nil
    end

    test "skill_spec contains the config" do
      [spec] = ConfiguredSkillAgent.skills()

      assert spec.config[:enabled] == false
      assert spec.config[:max_retries] == 5
    end

    test "config_schema is available on skill" do
      config_schema = ConfigurableSkill.config_schema()

      assert config_schema != nil
    end

    test "skill state is initialized with defaults" do
      agent = ConfiguredSkillAgent.new()

      assert agent.state[:configurable][:status] == :ready
    end
  end

  # =============================================================================
  # Tests: State Isolation
  # =============================================================================

  describe "state isolation" do
    test "skill_state/2 returns only the skill's state" do
      agent = MultiSkillAgent.new()

      counter_state = MultiSkillAgent.skill_state(agent, CounterSkill)
      greeter_state = MultiSkillAgent.skill_state(agent, GreeterSkill)

      assert counter_state == %{count: 0}
      assert greeter_state == %{}
    end

    test "skill_state/2 returns nil for unknown skill" do
      agent = MultiSkillAgent.new()

      result = MultiSkillAgent.skill_state(agent, ConfigurableSkill)

      assert result == nil
    end

    test "executing an action modifies only its skill's namespace" do
      agent = MultiSkillAgent.new()

      {updated, _directives} = MultiSkillAgent.cmd(agent, {IncrementAction, %{amount: 5}})

      assert updated.state[:counter_skill][:count] == 5
      assert updated.state[:greeter_skill][:last_greeting] == nil
    end

    test "executing multiple actions maintains isolation" do
      agent = MultiSkillAgent.new()

      {agent2, _} = MultiSkillAgent.cmd(agent, {IncrementAction, %{amount: 3}})
      {agent3, _} = MultiSkillAgent.cmd(agent2, {GreetAction, %{name: "Alice"}})
      {agent4, _} = MultiSkillAgent.cmd(agent3, {IncrementAction, %{amount: 2}})

      assert agent4.state[:counter_skill][:count] == 5
      assert agent4.state[:greeter_skill][:last_greeting] == "Hello, Alice!"
    end
  end

  # =============================================================================
  # Tests: Introspection APIs
  # =============================================================================

  describe "introspection APIs" do
    test "skills/0 returns list of skill specs" do
      specs = MultiSkillAgent.skills()

      assert is_list(specs)
      assert Enum.all?(specs, &match?(%Spec{}, &1))
    end

    test "skill_specs/0 is alias for skills/0" do
      assert MultiSkillAgent.skills() == MultiSkillAgent.skill_specs()
    end

    test "actions/0 returns list of action modules" do
      actions = MultiSkillAgent.actions()

      assert is_list(actions)
      assert Enum.all?(actions, &is_atom/1)
    end

    test "actions/0 returns empty list for agent without skills" do
      defmodule NoSkillAgent do
        use Jido.Agent,
          name: "no_skill_agent"
      end

      assert NoSkillAgent.actions() == []
    end

    test "skill_config/1 with valid skill returns config map" do
      config = ConfiguredSkillAgent.skill_config(ConfigurableSkill)

      assert is_map(config)
    end

    test "skill_config/1 with invalid skill returns nil" do
      config = ConfiguredSkillAgent.skill_config(NonExistentModule)

      assert config == nil
    end

    test "skill_state/2 with valid skill returns state map" do
      agent = SingleSkillAgent.new()
      state = SingleSkillAgent.skill_state(agent, CounterSkill)

      assert is_map(state)
      assert state[:count] == 0
    end

    test "skill_state/2 with invalid skill returns nil" do
      agent = SingleSkillAgent.new()
      state = SingleSkillAgent.skill_state(agent, NonExistentModule)

      assert state == nil
    end
  end

  # =============================================================================
  # Tests: Schema Merging
  # =============================================================================

  describe "schema merging" do
    test "merged schema contains skill state_keys" do
      schema = MixedSchemaAgent.schema()
      keys = Jido.Agent.Schema.known_keys(schema)

      assert :counter_skill in keys
    end

    test "defaults from both base and skill are applied in new/0" do
      agent = MixedSchemaAgent.new()

      assert agent.state[:base_counter] == 100
      assert agent.state[:base_mode] == :initial
      assert agent.state[:counter_skill][:count] == 0
    end

    test "base schema fields and skill schema fields coexist" do
      agent = MixedSchemaAgent.new(state: %{base_counter: 50})

      assert agent.state[:base_counter] == 50
      assert agent.state[:base_mode] == :initial
      assert agent.state[:counter_skill][:count] == 0
    end

    test "skill without schema works" do
      agent = MinimalSkillAgent.new()

      assert agent.state[:minimal] == %{}
    end

    test "agent schema/0 returns the merged schema" do
      schema = SingleSkillAgent.schema()

      assert schema != nil
    end
  end

  # =============================================================================
  # Tests: cmd/2 with Skill Actions
  # =============================================================================

  describe "cmd/2 with skill actions" do
    test "executes skill action module" do
      agent = SingleSkillAgent.new()

      {updated, directives} = SingleSkillAgent.cmd(agent, IncrementAction)

      assert updated.state[:counter_skill][:count] == 1
      assert directives == []
    end

    test "executes skill action with params" do
      agent = SingleSkillAgent.new()

      {updated, directives} = SingleSkillAgent.cmd(agent, {IncrementAction, %{amount: 10}})

      assert updated.state[:counter_skill][:count] == 10
      assert directives == []
    end

    test "executes list of skill actions" do
      agent = SingleSkillAgent.new()

      {updated, directives} =
        SingleSkillAgent.cmd(agent, [
          {IncrementAction, %{amount: 5}},
          {IncrementAction, %{amount: 3}},
          DecrementAction
        ])

      assert updated.state[:counter_skill][:count] == 7
      assert directives == []
    end

    test "works with actions from multiple skills" do
      agent = MultiSkillAgent.new()

      {updated, _} =
        MultiSkillAgent.cmd(agent, [
          {IncrementAction, %{amount: 10}},
          {GreetAction, %{name: "Test"}}
        ])

      assert updated.state[:counter_skill][:count] == 10
      assert updated.state[:greeter_skill][:last_greeting] == "Hello, Test!"
    end

    test "state updates persist across multiple cmd calls" do
      agent = SingleSkillAgent.new()

      {agent2, _} = SingleSkillAgent.cmd(agent, {IncrementAction, %{amount: 5}})
      {agent3, _} = SingleSkillAgent.cmd(agent2, {IncrementAction, %{amount: 3}})
      {agent4, _} = SingleSkillAgent.cmd(agent3, {DecrementAction, %{amount: 2}})

      assert agent4.state[:counter_skill][:count] == 6
    end

    test "cmd/2 with Instruction struct works" do
      agent = SingleSkillAgent.new()

      {:ok, instruction} =
        Jido.Instruction.new(%{action: IncrementAction, params: %{amount: 7}})

      {updated, _directives} = SingleSkillAgent.cmd(agent, instruction)

      assert updated.state[:counter_skill][:count] == 7
    end
  end

  # =============================================================================
  # Tests: Edge Cases
  # =============================================================================

  describe "edge cases" do
    test "agent with skill that has no schema initializes with empty map" do
      agent = MinimalSkillAgent.new()

      assert agent.state[:minimal] == %{}
    end

    test "accessing skill state for skill without schema returns empty map" do
      agent = MinimalSkillAgent.new()
      state = MinimalSkillAgent.skill_state(agent, MinimalSkill)

      assert state == %{}
    end

    test "skill actions list is deduplicated" do
      defmodule DuplicateActionSkill do
        use Jido.Skill,
          name: "dup_skill",
          state_key: :dup,
          actions: [
            JidoTest.AgentSkillIntegrationTest.SimpleAction,
            JidoTest.AgentSkillIntegrationTest.SimpleAction
          ]
      end

      defmodule DupAgent do
        use Jido.Agent,
          name: "dup_agent",
          skills: [JidoTest.AgentSkillIntegrationTest.DuplicateActionSkill]
      end

      actions = DupAgent.actions()
      assert length(actions) == 1
      assert SimpleAction in actions
    end

    test "multiple skills with same action module works" do
      defmodule SharedActionSkillA do
        use Jido.Skill,
          name: "shared_a",
          state_key: :shared_a,
          actions: [JidoTest.AgentSkillIntegrationTest.SimpleAction]
      end

      defmodule SharedActionSkillB do
        use Jido.Skill,
          name: "shared_b",
          state_key: :shared_b,
          actions: [JidoTest.AgentSkillIntegrationTest.SimpleAction]
      end

      defmodule SharedActionAgent do
        use Jido.Agent,
          name: "shared_action_agent",
          skills: [
            JidoTest.AgentSkillIntegrationTest.SharedActionSkillA,
            JidoTest.AgentSkillIntegrationTest.SharedActionSkillB
          ]
      end

      actions = SharedActionAgent.actions()
      assert length(actions) == 1
      assert SimpleAction in actions
    end

    test "agent metadata is preserved with skills" do
      agent = MultiSkillAgent.new()

      assert agent.name == "multi_skill_agent"
      assert is_binary(agent.id)
    end
  end
end

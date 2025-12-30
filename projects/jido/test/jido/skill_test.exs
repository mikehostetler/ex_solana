defmodule JidoTest.SkillTest do
  use ExUnit.Case, async: true

  alias Jido.Skill.Spec

  # Skill fixtures - these reference action modules from test/support/test_actions.ex
  # which are compiled before test files

  defmodule BasicSkill do
    @moduledoc false
    use Jido.Skill,
      name: "basic_skill",
      state_key: :basic,
      actions: [JidoTest.SkillTestAction]
  end

  defmodule FullSkill do
    @moduledoc false
    use Jido.Skill,
      name: "full_skill",
      state_key: :full,
      actions: [JidoTest.SkillTestAction, JidoTest.SkillTestAnotherAction],
      description: "A fully configured skill",
      category: "test",
      vsn: "1.0.0",
      schema: Zoi.object(%{counter: Zoi.integer() |> Zoi.default(0)}),
      config_schema: Zoi.object(%{enabled: Zoi.boolean() |> Zoi.default(true)}),
      signal_patterns: ["skill.**", "test.*"],
      tags: ["test", "full"]
  end

  defmodule CustomCallbackSkill do
    @moduledoc false
    use Jido.Skill,
      name: "custom_callback_skill",
      state_key: :custom,
      actions: [JidoTest.SkillTestAction]

    @impl Jido.Skill
    def mount(_agent, config) do
      {:ok, %{mounted: true, config: config}}
    end

    @impl Jido.Skill
    def router(_config), do: [:custom_router]

    @impl Jido.Skill
    def handle_signal(signal, context) do
      {:ok, %{signal: signal, context: context, handled: true}}
    end

    @impl Jido.Skill
    def transform_result(action, result, _context) do
      {:ok, %{action: action, result: result, transformed: true}}
    end

    @impl Jido.Skill
    def child_spec(config) do
      %{id: __MODULE__, start: {Agent, :start_link, [fn -> config end]}}
    end
  end

  defmodule MountErrorSkill do
    @moduledoc false
    use Jido.Skill,
      name: "mount_error_skill",
      state_key: :mount_error,
      actions: [JidoTest.SkillTestAction]

    @impl Jido.Skill
    def mount(_agent, _config) do
      {:error, :mount_failed}
    end
  end

  describe "skill definition with required fields" do
    test "defines a basic skill with required fields" do
      assert BasicSkill.name() == "basic_skill"
      assert BasicSkill.state_key() == :basic
      assert BasicSkill.actions() == [JidoTest.SkillTestAction]
    end

    test "optional fields default to nil or empty" do
      assert BasicSkill.description() == nil
      assert BasicSkill.category() == nil
      assert BasicSkill.vsn() == nil
      assert BasicSkill.schema() == nil
      assert BasicSkill.config_schema() == nil
      assert BasicSkill.signal_patterns() == []
      assert BasicSkill.tags() == []
    end
  end

  describe "skill definition with all optional fields" do
    test "defines a skill with all optional fields" do
      assert FullSkill.name() == "full_skill"
      assert FullSkill.state_key() == :full
      assert FullSkill.actions() == [JidoTest.SkillTestAction, JidoTest.SkillTestAnotherAction]
      assert FullSkill.description() == "A fully configured skill"
      assert FullSkill.category() == "test"
      assert FullSkill.vsn() == "1.0.0"
      assert FullSkill.schema() != nil
      assert FullSkill.config_schema() != nil
      assert FullSkill.signal_patterns() == ["skill.**", "test.*"]
      assert FullSkill.tags() == ["test", "full"]
    end
  end

  describe "skill_spec/0 and skill_spec/1" do
    test "skill_spec/0 returns correct Spec struct with defaults" do
      spec = BasicSkill.skill_spec()

      assert %Spec{} = spec
      assert spec.module == BasicSkill
      assert spec.name == "basic_skill"
      assert spec.state_key == :basic
      assert spec.actions == [JidoTest.SkillTestAction]
      assert spec.config == %{}
      assert spec.description == nil
      assert spec.category == nil
      assert spec.vsn == nil
      assert spec.schema == nil
      assert spec.config_schema == nil
      assert spec.signal_patterns == []
      assert spec.tags == []
    end

    test "skill_spec/0 returns correct Spec struct with all fields" do
      spec = FullSkill.skill_spec()

      assert %Spec{} = spec
      assert spec.module == FullSkill
      assert spec.name == "full_skill"
      assert spec.state_key == :full
      assert spec.actions == [JidoTest.SkillTestAction, JidoTest.SkillTestAnotherAction]
      assert spec.description == "A fully configured skill"
      assert spec.category == "test"
      assert spec.vsn == "1.0.0"
      assert spec.schema != nil
      assert spec.config_schema != nil
      assert spec.signal_patterns == ["skill.**", "test.*"]
      assert spec.tags == ["test", "full"]
    end

    test "skill_spec/1 accepts config overrides" do
      spec = BasicSkill.skill_spec(%{custom_option: true, setting: "value"})

      assert spec.config == %{custom_option: true, setting: "value"}
    end

    test "skill_spec/1 with empty config returns empty map" do
      spec = BasicSkill.skill_spec(%{})
      assert spec.config == %{}
    end
  end

  describe "metadata accessors" do
    test "name/0 returns skill name" do
      assert BasicSkill.name() == "basic_skill"
      assert FullSkill.name() == "full_skill"
    end

    test "state_key/0 returns skill state key" do
      assert BasicSkill.state_key() == :basic
      assert FullSkill.state_key() == :full
    end

    test "description/0 returns skill description" do
      assert BasicSkill.description() == nil
      assert FullSkill.description() == "A fully configured skill"
    end

    test "category/0 returns skill category" do
      assert BasicSkill.category() == nil
      assert FullSkill.category() == "test"
    end

    test "vsn/0 returns skill version" do
      assert BasicSkill.vsn() == nil
      assert FullSkill.vsn() == "1.0.0"
    end

    test "schema/0 returns skill state schema" do
      assert BasicSkill.schema() == nil
      assert FullSkill.schema() != nil
    end

    test "config_schema/0 returns skill config schema" do
      assert BasicSkill.config_schema() == nil
      assert FullSkill.config_schema() != nil
    end

    test "signal_patterns/0 returns skill signal patterns" do
      assert BasicSkill.signal_patterns() == []
      assert FullSkill.signal_patterns() == ["skill.**", "test.*"]
    end

    test "tags/0 returns skill tags" do
      assert BasicSkill.tags() == []
      assert FullSkill.tags() == ["test", "full"]
    end

    test "actions/0 returns skill actions" do
      assert BasicSkill.actions() == [JidoTest.SkillTestAction]
      assert FullSkill.actions() == [JidoTest.SkillTestAction, JidoTest.SkillTestAnotherAction]
    end
  end

  describe "compile-time validation" do
    test "missing required field raises CompileError" do
      assert_raise CompileError, fn ->
        defmodule MissingNameSkill do
          use Jido.Skill,
            state_key: :missing,
            actions: [JidoTest.SkillTestAction]
        end
      end
    end

    test "missing state_key raises CompileError" do
      assert_raise CompileError, fn ->
        defmodule MissingStateKeySkill do
          use Jido.Skill,
            name: "missing_state_key",
            actions: [JidoTest.SkillTestAction]
        end
      end
    end

    test "missing actions raises CompileError" do
      assert_raise CompileError, fn ->
        defmodule MissingActionsSkill do
          use Jido.Skill,
            name: "missing_actions",
            state_key: :missing
        end
      end
    end

    test "invalid action module raises CompileError" do
      assert_raise CompileError, fn ->
        defmodule InvalidActionSkill do
          use Jido.Skill,
            name: "invalid_action",
            state_key: :invalid,
            actions: [NonExistentModule]
        end
      end
    end

    test "module that doesn't implement Action behavior raises CompileError" do
      assert_raise CompileError, fn ->
        defmodule NotActionSkill do
          use Jido.Skill,
            name: "not_action",
            state_key: :not_action,
            actions: [JidoTest.NotAnActionModule]
        end
      end
    end

    test "invalid name format raises CompileError" do
      assert_raise CompileError, fn ->
        defmodule InvalidNameSkill do
          use Jido.Skill,
            name: "invalid-name-with-dashes",
            state_key: :invalid,
            actions: [JidoTest.SkillTestAction]
        end
      end
    end
  end

  describe "default callback implementations" do
    test "default mount/2 returns {:ok, empty map}" do
      result = BasicSkill.mount(%{}, %{})
      assert result == {:ok, %{}}
    end

    test "default mount/2 ignores agent and config" do
      result = BasicSkill.mount(:any_agent, %{any: :config})
      assert result == {:ok, %{}}
    end

    test "default router/1 returns nil" do
      result = BasicSkill.router(%{})
      assert result == nil
    end

    test "default handle_signal/2 returns {:ok, nil}" do
      result = BasicSkill.handle_signal(:some_signal, %{})
      assert result == {:ok, nil}
    end

    test "default transform_result/3 returns result unchanged" do
      result = BasicSkill.transform_result(JidoTest.SkillTestAction, %{value: 42}, %{})
      assert result == %{value: 42}
    end

    test "default child_spec/1 returns nil" do
      result = BasicSkill.child_spec(%{})
      assert result == nil
    end
  end

  describe "custom callback implementations" do
    test "custom mount/2 is called with agent and config" do
      agent = %{id: "test-agent"}
      config = %{setting: "value"}

      result = CustomCallbackSkill.mount(agent, config)

      assert result == {:ok, %{mounted: true, config: config}}
    end

    test "mount/2 can return error" do
      result = MountErrorSkill.mount(%{}, %{})
      assert result == {:error, :mount_failed}
    end

    test "custom router/1 returns custom router" do
      result = CustomCallbackSkill.router(%{some: :config})
      assert result == [:custom_router]
    end

    test "custom handle_signal/2 receives signal and context" do
      signal = %{type: "test.signal", data: %{}}
      context = %{agent_id: "test"}

      {:ok, result} = CustomCallbackSkill.handle_signal(signal, context)

      assert result.signal == signal
      assert result.context == context
      assert result.handled == true
    end

    test "custom transform_result/3 transforms result" do
      action = JidoTest.SkillTestAction
      result = %{original: "result"}
      context = %{agent_id: "test"}

      {:ok, transformed} = CustomCallbackSkill.transform_result(action, result, context)

      assert transformed.action == action
      assert transformed.result == result
      assert transformed.transformed == true
    end

    test "custom child_spec/1 returns supervisor child spec" do
      config = %{initial: "state"}

      spec = CustomCallbackSkill.child_spec(config)

      assert spec.id == CustomCallbackSkill
      assert {Agent, :start_link, [_fun]} = spec.start
    end
  end

  describe "Skill.config_schema/0" do
    test "returns the Zoi schema for skill configuration" do
      schema = Jido.Skill.config_schema()
      assert is_struct(schema)
    end
  end
end

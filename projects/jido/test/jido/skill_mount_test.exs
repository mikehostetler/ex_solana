defmodule JidoTest.SkillMountTest do
  use ExUnit.Case, async: true

  # Test action for skills
  defmodule TestAction do
    @moduledoc false
    use Jido.Action,
      name: "test_action",
      schema: []

    def run(_params, _context), do: {:ok, %{}}
  end

  # Skill with custom mount that adds state
  defmodule MountingSkill do
    @moduledoc false
    use Jido.Skill,
      name: "mounting_skill",
      state_key: :mounting,
      actions: [JidoTest.SkillMountTest.TestAction],
      schema: Zoi.object(%{default_value: Zoi.integer() |> Zoi.default(0)})

    @impl Jido.Skill
    def mount(_agent, config) do
      {:ok, %{mounted: true, initialized_at: DateTime.utc_now(), config_value: config[:setting]}}
    end
  end

  # Skill with default mount (no override)
  defmodule DefaultMountSkill do
    @moduledoc false
    use Jido.Skill,
      name: "default_mount_skill",
      state_key: :default_mount,
      actions: [JidoTest.SkillMountTest.TestAction],
      schema: Zoi.object(%{counter: Zoi.integer() |> Zoi.default(42)})
  end

  # Skill that reads from previously mounted skill state
  defmodule DependentSkill do
    @moduledoc false
    use Jido.Skill,
      name: "dependent_skill",
      state_key: :dependent,
      actions: [JidoTest.SkillMountTest.TestAction]

    @impl Jido.Skill
    def mount(agent, _config) do
      # Read from :mounting skill state if available
      mounting_state = Map.get(agent.state, :mounting, %{})
      was_mounted = Map.get(mounting_state, :mounted, false)
      {:ok, %{saw_mounting: was_mounted}}
    end
  end

  # Skill that returns error from mount
  defmodule ErrorMountSkill do
    @moduledoc false
    use Jido.Skill,
      name: "error_mount_skill",
      state_key: :error_mount,
      actions: [JidoTest.SkillMountTest.TestAction]

    @impl Jido.Skill
    def mount(_agent, _config) do
      {:error, :mount_failed_intentionally}
    end
  end

  # Agent with mounting skill
  defmodule MountingAgent do
    @moduledoc false
    use Jido.Agent,
      name: "mounting_agent",
      skills: [JidoTest.SkillMountTest.MountingSkill]
  end

  # Agent with configured mounting skill
  defmodule ConfiguredMountingAgent do
    @moduledoc false
    use Jido.Agent,
      name: "configured_mounting_agent",
      skills: [{JidoTest.SkillMountTest.MountingSkill, %{setting: "custom_value"}}]
  end

  # Agent with default mount skill
  defmodule DefaultMountAgent do
    @moduledoc false
    use Jido.Agent,
      name: "default_mount_agent",
      skills: [JidoTest.SkillMountTest.DefaultMountSkill]
  end

  # Agent with two skills where second depends on first
  defmodule DependentSkillsAgent do
    @moduledoc false
    use Jido.Agent,
      name: "dependent_skills_agent",
      skills: [
        JidoTest.SkillMountTest.MountingSkill,
        JidoTest.SkillMountTest.DependentSkill
      ]
  end

  # Agent with error mounting skill
  defmodule ErrorMountAgent do
    @moduledoc false
    use Jido.Agent,
      name: "error_mount_agent",
      skills: [JidoTest.SkillMountTest.ErrorMountSkill]
  end

  describe "mount/2 in Agent.new/1" do
    test "skill with custom mount populates its state slice" do
      agent = MountingAgent.new()

      assert agent.state[:mounting][:mounted] == true
      assert agent.state[:mounting][:initialized_at] != nil
      # from schema
      assert agent.state[:mounting][:default_value] == 0
    end

    test "skill mount receives config and can use it" do
      agent = ConfiguredMountingAgent.new()

      assert agent.state[:mounting][:config_value] == "custom_value"
    end

    test "skill with default mount/2 still gets schema defaults" do
      agent = DefaultMountAgent.new()

      assert agent.state[:default_mount][:counter] == 42
      # Default mount returns empty map, so no additional fields
    end

    test "skill mount can see previously mounted skill state" do
      agent = DependentSkillsAgent.new()

      # First skill should be mounted
      assert agent.state[:mounting][:mounted] == true

      # Second skill should have seen the first skill's state
      assert agent.state[:dependent][:saw_mounting] == true
    end

    test "skill mount error raises with clear message" do
      assert_raise Jido.Error.InternalError, ~r/Skill mount failed/, fn ->
        ErrorMountAgent.new()
      end
    end

    test "mount state merges with schema defaults, not replaces" do
      agent = MountingAgent.new()

      # Schema default should be preserved
      assert agent.state[:mounting][:default_value] == 0
      # Mount additions should be present
      assert agent.state[:mounting][:mounted] == true
    end

    test "custom initial state overrides both schema and mount" do
      agent = MountingAgent.new(state: %{mounting: %{default_value: 999, custom: :field}})

      # Custom value should override schema default
      assert agent.state[:mounting][:default_value] == 999
      # Mount values should still merge in
      assert agent.state[:mounting][:mounted] == true
      # Custom field preserved
      assert agent.state[:mounting][:custom] == :field
    end
  end
end

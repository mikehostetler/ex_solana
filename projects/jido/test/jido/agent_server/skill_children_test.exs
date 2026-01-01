defmodule JidoTest.AgentServer.SkillChildrenTest do
  use JidoTest.Case, async: true

  # Test action
  defmodule SimpleAction do
    @moduledoc false
    use Jido.Action,
      name: "simple_action",
      schema: []

    def run(_params, _context), do: {:ok, %{}}
  end

  # Skill with no child_spec (default returns nil)
  defmodule NoChildSkill do
    @moduledoc false
    use Jido.Skill,
      name: "no_child_skill",
      state_key: :no_child,
      actions: [JidoTest.AgentServer.SkillChildrenTest.SimpleAction]
  end

  # Skill that starts a single Agent as a child
  defmodule SingleChildSkill do
    @moduledoc false
    use Jido.Skill,
      name: "single_child_skill",
      state_key: :single_child,
      actions: [JidoTest.AgentServer.SkillChildrenTest.SimpleAction]

    @impl Jido.Skill
    def child_spec(config) do
      initial_value = config[:initial_value] || :default

      %{
        id: __MODULE__,
        start: {Agent, :start_link, [fn -> initial_value end]}
      }
    end
  end

  # Skill that starts multiple children
  defmodule MultiChildSkill do
    @moduledoc false
    use Jido.Skill,
      name: "multi_child_skill",
      state_key: :multi_child,
      actions: [JidoTest.AgentServer.SkillChildrenTest.SimpleAction]

    @impl Jido.Skill
    def child_spec(config) do
      count = config[:count] || 2

      Enum.map(1..count, fn i ->
        %{
          id: {__MODULE__, i},
          start: {Agent, :start_link, [fn -> {:worker, i} end]}
        }
      end)
    end
  end

  # Skill with invalid child_spec (for error handling test)
  defmodule InvalidChildSpecSkill do
    @moduledoc false
    use Jido.Skill,
      name: "invalid_child_spec_skill",
      state_key: :invalid_child,
      actions: [JidoTest.AgentServer.SkillChildrenTest.SimpleAction]

    @impl Jido.Skill
    def child_spec(_config) do
      :not_a_valid_child_spec
    end
  end

  # Agent with no child skill
  defmodule NoChildAgent do
    @moduledoc false
    use Jido.Agent,
      name: "no_child_agent",
      skills: [JidoTest.AgentServer.SkillChildrenTest.NoChildSkill]
  end

  # Agent with single child skill
  defmodule SingleChildAgent do
    @moduledoc false
    use Jido.Agent,
      name: "single_child_agent",
      skills: [JidoTest.AgentServer.SkillChildrenTest.SingleChildSkill]
  end

  # Agent with configured child skill
  defmodule ConfiguredChildAgent do
    @moduledoc false
    use Jido.Agent,
      name: "configured_child_agent",
      skills: [
        {JidoTest.AgentServer.SkillChildrenTest.SingleChildSkill, %{initial_value: :custom}}
      ]
  end

  # Agent with multi child skill
  defmodule MultiChildAgent do
    @moduledoc false
    use Jido.Agent,
      name: "multi_child_agent",
      skills: [{JidoTest.AgentServer.SkillChildrenTest.MultiChildSkill, %{count: 3}}]
  end

  # Agent with invalid child spec skill
  defmodule InvalidChildAgent do
    @moduledoc false
    use Jido.Agent,
      name: "invalid_child_agent",
      skills: [JidoTest.AgentServer.SkillChildrenTest.InvalidChildSpecSkill]
  end

  describe "child_spec/1 with no children" do
    test "skill returning nil starts no children", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: NoChildAgent, jido: jido)

      {:ok, state} = Jido.AgentServer.state(pid)
      assert state.children == %{}

      GenServer.stop(pid)
    end
  end

  describe "child_spec/1 with single child" do
    test "skill starts child process on AgentServer init", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: SingleChildAgent, jido: jido)

      {:ok, state} = Jido.AgentServer.state(pid)

      # Should have one child
      assert map_size(state.children) == 1

      # Get the child info
      [{tag, child_info}] = Map.to_list(state.children)

      # Tag should be {:skill, SkillModule, ChildId}
      assert {:skill, JidoTest.AgentServer.SkillChildrenTest.SingleChildSkill, _} = tag

      # Child should be alive
      assert Process.alive?(child_info.pid)

      # Child should have the default value
      assert Agent.get(child_info.pid, & &1) == :default

      GenServer.stop(pid)
    end

    test "child receives config from skill config", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: ConfiguredChildAgent, jido: jido)

      {:ok, state} = Jido.AgentServer.state(pid)

      [{_tag, child_info}] = Map.to_list(state.children)
      assert Agent.get(child_info.pid, & &1) == :custom

      GenServer.stop(pid)
    end

    test "child is monitored by AgentServer", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: SingleChildAgent, jido: jido)

      {:ok, state} = Jido.AgentServer.state(pid)
      [{_tag, child_info}] = Map.to_list(state.children)

      # Child has a monitor ref
      assert child_info.ref != nil

      # Manually stop the child
      Agent.stop(child_info.pid)

      # Give time for DOWN message to be processed
      Process.sleep(50)

      # Child should be removed from state
      {:ok, new_state} = Jido.AgentServer.state(pid)
      assert map_size(new_state.children) == 0

      GenServer.stop(pid)
    end
  end

  describe "child_spec/1 with multiple children" do
    test "skill can start multiple child processes", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: MultiChildAgent, jido: jido)

      {:ok, state} = Jido.AgentServer.state(pid)

      # Should have 3 children
      assert map_size(state.children) == 3

      # All children should be alive
      Enum.each(state.children, fn {_tag, child_info} ->
        assert Process.alive?(child_info.pid)
      end)

      GenServer.stop(pid)
    end
  end

  describe "child_spec/1 error handling" do
    test "invalid child_spec is logged but doesn't crash server", %{jido: jido} do
      # This should start successfully but log a warning
      {:ok, pid} = Jido.AgentServer.start_link(agent: InvalidChildAgent, jido: jido)

      {:ok, state} = Jido.AgentServer.state(pid)
      # No children should be started due to invalid spec
      assert state.children == %{}

      GenServer.stop(pid)
    end
  end

  describe "child cleanup on AgentServer stop" do
    test "children are cleaned up when AgentServer stops", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: SingleChildAgent, jido: jido)

      {:ok, state} = Jido.AgentServer.state(pid)
      [{_tag, child_info}] = Map.to_list(state.children)
      child_pid = child_info.pid

      assert Process.alive?(child_pid)

      # Stop the AgentServer
      GenServer.stop(pid)

      # Give time for cleanup
      Process.sleep(50)

      refute Process.alive?(pid)
    end
  end
end

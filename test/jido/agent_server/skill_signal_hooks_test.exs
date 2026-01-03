defmodule JidoTest.AgentServer.SkillSignalHooksTest do
  use JidoTest.Case, async: true

  alias Jido.Signal

  # Test action that increments a counter
  defmodule IncrementAction do
    @moduledoc false
    use Jido.Action,
      name: "increment",
      schema: Zoi.object(%{amount: Zoi.integer() |> Zoi.default(1)})

    alias Jido.Agent.Internal

    def run(%{amount: amount}, %{state: state}) do
      current = get_in(state, [:counter]) || 0
      {:ok, %{}, %Internal.SetPath{path: [:counter], value: current + amount}}
    end
  end

  # Override action
  defmodule OverrideAction do
    @moduledoc false
    use Jido.Action,
      name: "override_action",
      schema: []

    alias Jido.Agent.Internal

    def run(_params, _context) do
      {:ok, %{}, %Internal.SetPath{path: [:overridden], value: true}}
    end
  end

  # Skill with default handle_signal (continues to router)
  defmodule DefaultHandleSignalSkill do
    @moduledoc false
    use Jido.Skill,
      name: "default_handle_signal",
      state_key: :default_hs,
      actions: [JidoTest.AgentServer.SkillSignalHooksTest.IncrementAction]
  end

  # Skill that overrides routing for specific signals
  defmodule OverrideSkill do
    @moduledoc false
    use Jido.Skill,
      name: "override_skill",
      state_key: :override,
      actions: [
        JidoTest.AgentServer.SkillSignalHooksTest.IncrementAction,
        JidoTest.AgentServer.SkillSignalHooksTest.OverrideAction
      ]

    @impl Jido.Skill
    def handle_signal(signal, _context) do
      if signal.type == "counter.override" do
        {:ok, {:override, JidoTest.AgentServer.SkillSignalHooksTest.OverrideAction}}
      else
        {:ok, :continue}
      end
    end
  end

  # Skill that returns error for specific signals
  defmodule ErrorSkill do
    @moduledoc false
    use Jido.Skill,
      name: "error_skill",
      state_key: :error_skill,
      actions: [JidoTest.AgentServer.SkillSignalHooksTest.IncrementAction]

    @impl Jido.Skill
    def handle_signal(signal, _context) do
      if signal.type == "counter.error" do
        {:error, :skill_rejected_signal}
      else
        {:ok, :continue}
      end
    end
  end

  # Agent with default handle_signal skill
  defmodule DefaultHandleSignalAgent do
    @moduledoc false
    use Jido.Agent,
      name: "default_handle_signal_agent",
      schema: [counter: [type: :integer, default: 0]],
      skills: [JidoTest.AgentServer.SkillSignalHooksTest.DefaultHandleSignalSkill]

    def signal_routes do
      [{"counter.increment", JidoTest.AgentServer.SkillSignalHooksTest.IncrementAction}]
    end
  end

  # Agent with override skill
  defmodule OverrideAgent do
    @moduledoc false
    use Jido.Agent,
      name: "override_agent",
      schema: [
        counter: [type: :integer, default: 0],
        overridden: [type: :boolean, default: false]
      ],
      skills: [JidoTest.AgentServer.SkillSignalHooksTest.OverrideSkill]

    def signal_routes do
      [
        {"counter.increment", JidoTest.AgentServer.SkillSignalHooksTest.IncrementAction},
        {"counter.override", JidoTest.AgentServer.SkillSignalHooksTest.IncrementAction}
      ]
    end
  end

  # Agent with error skill
  defmodule ErrorAgent do
    @moduledoc false
    use Jido.Agent,
      name: "error_agent",
      schema: [counter: [type: :integer, default: 0]],
      skills: [JidoTest.AgentServer.SkillSignalHooksTest.ErrorSkill]

    def signal_routes do
      [
        {"counter.increment", JidoTest.AgentServer.SkillSignalHooksTest.IncrementAction},
        {"counter.error", JidoTest.AgentServer.SkillSignalHooksTest.IncrementAction}
      ]
    end
  end

  describe "handle_signal/2 with default implementation" do
    test "signals route normally when skill uses default handle_signal", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: DefaultHandleSignalAgent, jido: jido)

      signal = Signal.new!("counter.increment", %{amount: 5}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:counter] == 5
    end
  end

  describe "handle_signal/2 with override" do
    test "skill can override routing by returning {:ok, {:override, action}}", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: OverrideAgent, jido: jido)

      # This would normally route to IncrementAction, but skill overrides it
      signal = Signal.new!("counter.override", %{}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      # Override action sets :overridden to true instead of incrementing
      assert agent.state[:overridden] == true
      # Not incremented
      assert agent.state[:counter] == 0
    end

    test "skill continues to normal routing when not overriding", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: OverrideAgent, jido: jido)

      signal = Signal.new!("counter.increment", %{amount: 10}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:counter] == 10
      assert agent.state[:overridden] == false
    end
  end

  describe "handle_signal/2 with error" do
    test "skill can abort signal processing by returning error", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: ErrorAgent, jido: jido)

      signal = Signal.new!("counter.error", %{}, source: "/test")
      result = Jido.AgentServer.call(pid, signal)

      # Should return error
      assert {:error, error} = result
      assert error.message == "Skill handle_signal failed"

      # Agent state should be unchanged
      {:ok, state} = Jido.AgentServer.state(pid)
      assert state.agent.state[:counter] == 0
    end

    test "non-error signals still process normally", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: ErrorAgent, jido: jido)

      signal = Signal.new!("counter.increment", %{amount: 3}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:counter] == 3
    end
  end
end

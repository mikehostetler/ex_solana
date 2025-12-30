defmodule JidoTest.AgentServer.StrategyInitTest do
  use ExUnit.Case, async: true

  alias Jido.AgentServer
  alias Jido.Agent.Directive
  alias Jido.Signal

  defmodule TrackingStrategy do
    @moduledoc false
    use Jido.Agent.Strategy

    @impl true
    def init(agent, ctx) do
      new_state =
        Map.put(agent.state, :__strategy__, %{
          initialized: true,
          opts: ctx[:strategy_opts] || []
        })

      {%{agent | state: new_state}, []}
    end

    @impl true
    def cmd(agent, _instructions, _ctx) do
      {agent, []}
    end
  end

  defmodule InitDirectiveStrategy do
    @moduledoc false
    use Jido.Agent.Strategy

    @impl true
    def init(agent, _ctx) do
      new_state = Map.put(agent.state, :__strategy__, %{initialized: true})
      agent = %{agent | state: new_state}

      signal = Signal.new!("strategy.initialized", %{agent_id: agent.id}, source: "/strategy")
      {agent, [%Directive.Emit{signal: signal}]}
    end

    @impl true
    def cmd(agent, _instructions, _ctx) do
      {agent, []}
    end
  end

  defmodule TrackingAgent do
    @moduledoc false
    use Jido.Agent,
      name: "tracking_agent",
      strategy: {JidoTest.AgentServer.StrategyInitTest.TrackingStrategy, max_iterations: 5},
      schema: [
        counter: [type: :integer, default: 0]
      ]
  end

  defmodule DirectiveAgent do
    @moduledoc false
    use Jido.Agent,
      name: "directive_agent",
      strategy: JidoTest.AgentServer.StrategyInitTest.InitDirectiveStrategy,
      schema: [
        value: [type: :integer, default: 0]
      ]
  end

  defmodule DefaultStrategyAgent do
    @moduledoc false
    use Jido.Agent,
      name: "default_strategy_agent",
      schema: [
        status: [type: :atom, default: :idle]
      ]
  end

  describe "strategy.init/2 lifecycle" do
    test "strategy.init/2 is called on AgentServer startup" do
      {:ok, pid} = AgentServer.start_link(agent: TrackingAgent)
      {:ok, state} = AgentServer.state(pid)

      assert state.agent.state.__strategy__.initialized == true

      GenServer.stop(pid)
    end

    test "strategy_opts are passed to init/2" do
      {:ok, pid} = AgentServer.start_link(agent: TrackingAgent)
      {:ok, state} = AgentServer.state(pid)

      assert state.agent.state.__strategy__.opts == [max_iterations: 5]

      GenServer.stop(pid)
    end

    test "strategy state is initialized before first signal" do
      {:ok, pid} = AgentServer.start_link(agent: TrackingAgent)

      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.__strategy__.initialized == true

      signal = Signal.new!("test", %{}, source: "/test")
      {:ok, agent} = AgentServer.call(pid, signal)

      assert agent.state.__strategy__.initialized == true

      GenServer.stop(pid)
    end

    test "directives from init/2 are processed" do
      {:ok, pid} = AgentServer.start_link(agent: DirectiveAgent)

      Process.sleep(20)

      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.__strategy__.initialized == true

      GenServer.stop(pid)
    end

    test "default Direct strategy works (no-op init)" do
      {:ok, pid} = AgentServer.start_link(agent: DefaultStrategyAgent)
      {:ok, state} = AgentServer.state(pid)

      assert state.status == :idle
      assert state.agent.state.status == :idle

      GenServer.stop(pid)
    end

    test "strategy init works with pre-built agent" do
      agent = TrackingAgent.new(id: "prebuilt")
      {:ok, pid} = AgentServer.start_link(agent: agent, agent_module: TrackingAgent)
      {:ok, state} = AgentServer.state(pid)

      assert state.agent.state.__strategy__.initialized == true

      GenServer.stop(pid)
    end

    test "strategy init works with initial_state" do
      {:ok, pid} =
        AgentServer.start_link(
          agent: TrackingAgent,
          initial_state: %{counter: 42}
        )

      {:ok, state} = AgentServer.state(pid)

      assert state.agent.state.counter == 42
      assert state.agent.state.__strategy__.initialized == true

      GenServer.stop(pid)
    end
  end
end

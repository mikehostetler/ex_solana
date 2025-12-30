defmodule JidoTest.TestAgents do
  @moduledoc false

  defmodule Minimal do
    @moduledoc false
    use Jido.Agent,
      name: "minimal_agent"
  end

  defmodule Basic do
    @moduledoc false
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

  defmodule Hook do
    @moduledoc false
    use Jido.Agent,
      name: "hook_agent",
      schema: [
        counter: [type: :integer, default: 0]
      ]

    def on_after_cmd(agent, _action, directives) do
      {:ok, %{agent | state: Map.put(agent.state, :hook_called, true)}, directives}
    end
  end

  defmodule CountingStrategy do
    @moduledoc false
    @behaviour Jido.Agent.Strategy

    @impl true
    def init(agent, _ctx), do: {agent, []}

    @impl true
    def tick(agent, _ctx), do: {agent, []}

    @impl true
    def cmd(agent, action, ctx) do
      count = Map.get(agent.state, :strategy_count, 0)
      agent = %{agent | state: Map.put(agent.state, :strategy_count, count + 1)}
      Jido.Agent.Strategy.Direct.cmd(agent, action, ctx)
    end
  end

  defmodule InitDirectiveStrategy do
    @moduledoc "Strategy that emits directives from init/2 for testing"
    use Jido.Agent.Strategy

    @impl true
    def init(agent, _ctx) do
      new_state = Map.put(agent.state, :__strategy__, %{initialized: true})
      agent = %{agent | state: new_state}

      signal = Jido.Signal.new!("strategy.initialized", %{}, source: "/strategy")
      {agent, [%Jido.Agent.Directive.Emit{signal: signal}]}
    end

    @impl true
    def cmd(agent, _instructions, _ctx) do
      {agent, []}
    end
  end

  defmodule CustomStrategy do
    @moduledoc false
    use Jido.Agent,
      name: "custom_strategy_agent",
      strategy: JidoTest.TestAgents.CountingStrategy
  end

  defmodule StrategyWithOpts do
    @moduledoc false
    use Jido.Agent,
      name: "strategy_opts_agent",
      strategy: {JidoTest.TestAgents.CountingStrategy, max_depth: 5}
  end

  defmodule ZoiSchema do
    @moduledoc false
    use Jido.Agent,
      name: "zoi_schema_agent",
      schema:
        Zoi.object(%{
          status: Zoi.atom() |> Zoi.default(:idle),
          count: Zoi.integer() |> Zoi.default(0)
        })
  end

  defmodule WithCustomStrategy do
    @moduledoc "Agent with a strategy that emits directives from init/2"
    use Jido.Agent,
      name: "with_custom_strategy_agent",
      strategy: JidoTest.TestAgents.InitDirectiveStrategy,
      schema: [
        value: [type: :integer, default: 0]
      ]
  end
end

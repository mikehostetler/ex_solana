defmodule Jido.AgentServer.SignalRouter do
  @moduledoc """
  Builds a unified Jido.Signal.Router from strategy, agent, and skill routes.

  This module is responsible for:
  1. Collecting routes from all sources (strategy, agent, skills)
  2. Normalizing route specs with appropriate priorities
  3. Building the trie-based router for efficient signal routing

  ## Priority Levels

  | Source   | Default Priority | Range    |
  |----------|------------------|----------|
  | Strategy | 50               | 50-100   |
  | Agent    | 0                | -25 to 25|
  | Skill    | -10              | -50 to -10|

  ## Route Spec Formats

  Routes can be specified in several formats:
  - `{path, target}` - Simple route with default priority
  - `{path, target, priority}` - Route with explicit priority
  - `{path, match_fn, target}` - Route with match function
  - `{path, match_fn, target, priority}` - Route with match function and priority

  ## Target Types

  - `module()` - Action module, params = signal.data
  - `{module(), map()}` - Action module with static params
  - `{:strategy_cmd, atom()}` - Strategy command
  """

  alias Jido.AgentServer.State
  alias Jido.Signal.Router, as: SignalRouter

  @strategy_default_priority 50
  @agent_default_priority 0
  @skill_default_priority -10

  @doc """
  Builds a unified router from all route sources in the agent state.

  Collects routes from:
  - Strategy routes (priority 50+) via `strategy.signal_routes/1`
  - Agent routes (priority 0) via `agent_module.signal_routes/0`
  - Skill routes (priority -10) via skill `signal_patterns` and `router/1`

  Returns an empty router if no routes are found or if building fails.
  """
  @spec build(State.t()) :: SignalRouter.Router.t()
  def build(%State{} = state) do
    routes =
      []
      |> add_strategy_routes(state)
      |> add_agent_routes(state)
      |> add_skill_routes(state)

    case SignalRouter.new(routes) do
      {:ok, router} -> router
      {:error, _} -> SignalRouter.new!([])
    end
  end

  # Collects routes from strategy.signal_routes/1
  defp add_strategy_routes(routes, %State{agent_module: agent_module}) do
    strat = agent_module.strategy()
    ctx = %{agent_module: agent_module, strategy_opts: agent_module.strategy_opts()}

    if function_exported?(strat, :signal_routes, 1) do
      strategy_routes = strat.signal_routes(ctx)
      normalized = normalize_routes(strategy_routes, @strategy_default_priority)
      routes ++ normalized
    else
      routes
    end
  end

  # Collects routes from agent_module.signal_routes/0
  defp add_agent_routes(routes, %State{agent_module: agent_module}) do
    if function_exported?(agent_module, :signal_routes, 0) do
      agent_routes = agent_module.signal_routes()
      normalized = normalize_routes(agent_routes, @agent_default_priority)
      routes ++ normalized
    else
      routes
    end
  end

  # Collects routes from skills via signal_patterns and router/1
  defp add_skill_routes(routes, %State{agent_module: agent_module}) do
    skill_specs =
      if function_exported?(agent_module, :skill_specs, 0) do
        agent_module.skill_specs()
      else
        []
      end

    skill_routes =
      Enum.flat_map(skill_specs, fn spec ->
        custom_routes = get_skill_custom_routes(spec)

        pattern_routes =
          if custom_routes == [] do
            generate_pattern_routes(spec)
          else
            []
          end

        custom_routes ++ pattern_routes
      end)

    normalized = normalize_routes(skill_routes, @skill_default_priority)
    routes ++ normalized
  end

  defp get_skill_custom_routes(spec) do
    skill_module = spec.module

    if function_exported?(skill_module, :router, 1) do
      case skill_module.router(spec.config) do
        nil -> []
        routes when is_list(routes) -> routes
        _other -> []
      end
    else
      []
    end
  end

  defp generate_pattern_routes(spec) do
    patterns = spec.signal_patterns || []
    actions = spec.actions || []

    for pattern <- patterns, action <- actions do
      {pattern, action}
    end
  end

  defp normalize_routes(routes, default_priority) do
    Enum.map(routes, fn
      {path, target, priority} when is_integer(priority) ->
        {path, target, priority}

      {path, match_fn, target, priority} when is_function(match_fn, 1) and is_integer(priority) ->
        {path, match_fn, target, priority}

      {path, match_fn, target} when is_function(match_fn, 1) ->
        {path, match_fn, target, default_priority}

      {path, target} ->
        {path, target, default_priority}
    end)
  end
end

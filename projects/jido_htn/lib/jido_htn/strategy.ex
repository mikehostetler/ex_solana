defmodule Jido.Agent.Strategy.HTN do
  @moduledoc """
  HTN-based execution strategy for Jido Agents.

  This strategy integrates Hierarchical Task Network (HTN) planning with the 
  Jido Agent framework. When `:htn_run` instructions are received, it:

  1. Calls `Jido.HTN.plan/3` with the configured domain and provided world_state
  2. Executes the resulting plan `[{ActionModule, params}]` sequentially
  3. Tracks plan execution state in `agent.state.__strategy__`

  ## Configuration

      defmodule MyHTNAgent do
        use Jido.Agent,
          name: "my_htn_agent",
          strategy: {Jido.Agent.Strategy.HTN, domain: MyDomain.domain()}
      end

  ## Strategy Options

  - `:domain` - (required) A `%Jido.HTN.Domain{}` struct defining tasks
  - `:debug` - When true, stores MTR and debug tree in strategy state

  ## Usage

      # Create an :htn_run instruction
      {agent, directives} = MyAgent.cmd(agent, {:htn_run, %{
        world_state: %{location: :home},
        root_tasks: ["deliver_package"]
      }})

  ## State Tracking

  Strategy state is stored in `agent.state.__strategy__`:

  - `status` - `:idle`, `:running`, `:success`, or `:failure`
  - `plan` - List of `{ActionModule, params}` tuples
  - `current_step` - Index of current/last executed step
  - `world_state` - World state used for planning
  - `planner_metadata` - Debug info (MTR, tree) if enabled
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.Agent.Effects
  alias Jido.Error
  alias Jido.Instruction
  alias Jido.HTN

  @impl true
  def init(%Agent{} = agent, _ctx) do
    strategy_state =
      agent.state
      |> Map.get(:__strategy__, %{})
      |> Map.merge(%{
        module: __MODULE__,
        status: :idle,
        plan: [],
        current_step: 0,
        world_state: %{},
        planner_metadata: nil,
        result: nil
      })

    agent = put_in(agent.state[:__strategy__], strategy_state)
    {agent, []}
  end

  @impl true
  def cmd(%Agent{} = agent, instructions, ctx) when is_list(instructions) do
    {htn_instrs, passthrough_instrs} =
      Enum.split_with(instructions, fn
        %Instruction{action: :htn_run} -> true
        _ -> false
      end)

    {agent, directives1} =
      if passthrough_instrs == [] do
        {agent, []}
      else
        Jido.Agent.Strategy.Direct.cmd(agent, passthrough_instrs, ctx)
      end

    Enum.reduce(htn_instrs, {agent, directives1}, fn instr, {ag, dirs} ->
      {ag2, new_dirs} = run_htn_instruction(ag, instr, ctx)
      {ag2, dirs ++ new_dirs}
    end)
  end

  @impl true
  def snapshot(%Agent{} = agent, _ctx) do
    state = agent.state |> Map.get(:__strategy__, %{})

    status = Map.get(state, :status, :idle)
    done? = status in [:success, :failure]

    %Jido.Agent.Strategy.Snapshot{
      status: status,
      done?: done?,
      result: Map.get(state, :result),
      details:
        state
        |> Map.drop([:module, :status, :result])
    }
  end

  @impl true
  def action_spec(:htn_run) do
    %{
      doc: "Run an HTN plan for the configured domain",
      schema: [
        world_state: [type: :map, required: false, default: %{}],
        root_tasks: [type: {:list, :string}, required: false]
      ]
    }
  end

  def action_spec(_), do: nil

  # ---------------------------------------------------------------------------
  # Private Implementation
  # ---------------------------------------------------------------------------

  defp run_htn_instruction(%Agent{} = agent, %Instruction{} = instr, ctx) do
    domain =
      ctx.strategy_opts[:domain] ||
        raise ArgumentError, "HTN strategy requires :domain in strategy_opts"

    params = instr.params || %{}
    world_state = Map.get(params, :world_state, agent.state)
    root_tasks = Map.get(params, :root_tasks, nil)

    plan_opts =
      []
      |> maybe_put(:root_tasks, root_tasks)
      |> maybe_put(:debug, ctx.strategy_opts[:debug])

    case HTN.plan(domain, world_state, plan_opts) do
      {:ok, plan} ->
        execute_plan(agent, plan, world_state, nil, ctx)

      {:ok, plan, mtr} ->
        execute_plan(agent, plan, world_state, %{mtr: mtr}, ctx)

      {:ok, plan, mtr, tree} ->
        execute_plan(agent, plan, world_state, %{mtr: mtr, tree: tree}, ctx)

      {:error, reason} ->
        agent =
          update_strategy_state(agent, %{
            status: :failure,
            plan: [],
            current_step: 0,
            world_state: world_state,
            planner_metadata: %{error: reason}
          })

        error = Error.execution_error("HTN planning failed", %{reason: reason})
        {agent, [%Directive.Error{error: error, context: :htn_planning}]}

      {:error, reason, tree} ->
        agent =
          update_strategy_state(agent, %{
            status: :failure,
            plan: [],
            current_step: 0,
            world_state: world_state,
            planner_metadata: %{error: reason, tree: tree}
          })

        error = Error.execution_error("HTN planning failed", %{reason: reason})
        {agent, [%Directive.Error{error: error, context: :htn_planning}]}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp execute_plan(%Agent{} = agent, plan, world_state, planner_meta, ctx) do
    agent =
      update_strategy_state(agent, %{
        status: :running,
        plan: plan,
        current_step: 0,
        world_state: world_state,
        planner_metadata: planner_meta
      })

    {agent, directives} =
      plan
      |> Enum.with_index(0)
      |> Enum.reduce({agent, []}, fn {{action_mod, params_kw}, step_idx}, {ag, dirs} ->
        ag = update_strategy_state(ag, %{current_step: step_idx})

        {ag2, new_dirs} = run_primitive_action(ag, {action_mod, params_kw}, ctx)
        {ag2, dirs ++ new_dirs}
      end)

    agent =
      update_strategy_state(agent, %{
        status: :success,
        current_step: length(plan)
      })

    {agent, directives}
  end

  defp run_primitive_action(%Agent{} = agent, {action_mod, params_kw}, _ctx) do
    params_map = Enum.into(params_kw || [], %{})

    instruction = %Instruction{
      action: action_mod,
      params: params_map,
      context: %{
        source: :htn,
        state: agent.state
      }
    }

    case Jido.Exec.run(instruction) do
      {:ok, result} when is_map(result) ->
        {Effects.apply_result(agent, result), []}

      {:ok, result, effects} when is_map(result) ->
        agent = Effects.apply_result(agent, result)
        Effects.apply_effects(agent, List.wrap(effects))

      {:error, reason} ->
        error =
          Error.execution_error("HTN primitive instruction failed", %{
            reason: reason,
            action: action_mod
          })

        {agent, [%Directive.Error{error: error, context: :htn_primitive}]}
    end
  end

  defp update_strategy_state(%Agent{} = agent, updates) do
    base =
      agent.state
      |> Map.get(:__strategy__, %{})
      |> Map.put(:module, __MODULE__)

    new_state = Map.merge(base, updates)
    put_in(agent.state[:__strategy__], new_state)
  end
end

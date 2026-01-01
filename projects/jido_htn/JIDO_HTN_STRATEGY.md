# Jido HTN Strategy Integration Report

## Executive Summary

This document outlines the architectural changes required to integrate `jido_htn` with the Jido ecosystem's **Signals**, **Effects**, **Directives**, and **Actions** patterns for agent coordination.

**Key Insight**: Use the existing `Jido.HTN` planner purely for *planning* (world-state simulation) and add a new `Jido.Agent.Strategy.HTN` that *executes* plans using Jido primitives.

**Estimated Effort**: L (1-2 days) for solid first integration; more for advanced async and multi-agent patterns.

---

## 1. Current State Assessment

### 1.1 What jido_htn Already Provides (Keep for Planning)

| Component | Purpose | Status |
|-----------|---------|--------|
| `Jido.HTN.plan/3` | Decomposes HTN domain into action plans | ✅ Working |
| `Jido.HTN.PrimitiveTask` | Encodes Jido Action + preconditions/effects | ✅ Structure ready |
| `Jido.HTN.Domain` | Domain builder with tasks, methods, callbacks | ✅ Working |
| `TaskDecomposer` | Priority-based method selection, MTR tracking | ✅ Working |
| `EffectHandler` | Planning-time world_state simulation | ✅ Working |
| `ConditionEvaluator` | Precondition/method condition evaluation | ✅ Working |

**PrimitiveTask already supports Jido Actions**:
```elixir
%PrimitiveTask{
  name: "execute_trade",
  task: {MyApp.TradeAction, [symbol: "BTC", amount: 100]},  # Jido Action!
  preconditions: [...],
  effects: [...],
  expected_effects: [...],
  background: false
}
```

### 1.2 What's Missing for Jido Integration

| Missing Piece | Description | Priority |
|---------------|-------------|----------|
| **Strategy Module** | No `Jido.Agent.Strategy.HTN` implementation | P0 |
| **Runtime Execution** | `PrimitiveTask.execute/2` raises "not implemented" | P0 |
| **Directive Accumulation** | No HTN equivalent of BT `Tick` structure | P0 |
| **Signal Routing** | No `signal_routes/1` for inbound signals | P1 |
| **Jido.Exec Integration** | Not using `Jido.Exec.run/1` or `Jido.Agent.Effects` | P0 |
| **Multi-Agent Patterns** | No SpawnAgent/StopChild integration | P2 |

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Jido Agent                                   │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                  agent.state.__strategy__                     │  │
│  │  ┌─────────────────────────────────────────────────────────┐  │  │
│  │  │              Strategy.HTN.State                         │  │  │
│  │  │  • status: :idle | :running | :success | :failure       │  │  │
│  │  │  • domain: Jido.HTN.Domain.t()                          │  │  │
│  │  │  • world_state: map() (planner simulation)              │  │  │
│  │  │  • plan: [{module, params}] (from planner)              │  │  │
│  │  │  • cursor: integer (current plan position)              │  │  │
│  │  │  • background_tasks: MapSet.t()                         │  │  │
│  │  └─────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   Jido.Agent.Strategy.HTN                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌────────────┐  │
│  │  init/2     │  │   cmd/3     │  │   tick/2    │  │ snapshot/2 │  │
│  │             │  │             │  │             │  │            │  │
│  │ Load domain │  │ Handle:     │  │ Resume      │  │ Map state  │  │
│  │ Init state  │  │ :htn_start  │  │ execution   │  │ to public  │  │
│  │             │  │ :htn_cancel │  │ from cursor │  │ Snapshot   │  │
│  │             │  │ :htn_event  │  │             │  │            │  │
│  └─────────────┘  └─────────────┘  └─────────────┘  └────────────┘  │
│                              │                                       │
│                              ▼                                       │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    HTN Runtime.Tick                           │  │
│  │  Carries execution state across plan steps:                   │  │
│  │  • agent, world_state, plan, cursor, status                   │  │
│  │  • directives: [] (accumulated during execution)              │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│  Jido.HTN.plan  │ │ PrimitiveTask   │ │ Jido.Agent      │
│  (Planning)     │ │ .execute/2      │ │ .Effects        │
│                 │ │ (Runtime)       │ │                 │
│ Decomposes HTN  │ │ Uses Jido.Exec  │ │ apply_result/2  │
│ Returns plan    │ │ Returns result  │ │ apply_effects/2 │
│ + world_state   │ │ + directives    │ │                 │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

---

## 3. Signal Integration

### 3.1 Signal Routes Configuration

```elixir
defmodule Jido.Agent.Strategy.HTN do
  use Jido.Agent.Strategy

  @impl true
  def signal_routes(_ctx) do
    [
      # Start HTN planning and execution
      {"htn.start", {:strategy_cmd, :htn_start}},
      
      # Cancel current plan
      {"htn.cancel", {:strategy_cmd, :htn_cancel}},
      
      # External task completion/failure events
      {"htn.task.event", {:strategy_cmd, :htn_task_event}},
      
      # Request replanning with new world state
      {"htn.replan", {:strategy_cmd, :htn_replan}},
      
      # Background worker results (from child agents)
      {"worker.result", {:strategy_cmd, :htn_task_event}},
      
      # Child agent exit signals
      {"jido.agent.child.exit", {:strategy_cmd, :htn_child_exit}}
    ]
  end
end
```

### 3.2 HTN Lifecycle Signals (Emitted)

| Signal Type | When Emitted | Data |
|-------------|--------------|------|
| `htn.plan.started` | After successful `plan/3` | `%{plan_id, task_count}` |
| `htn.plan.completed` | All tasks executed successfully | `%{plan_id, result}` |
| `htn.plan.failed` | Plan execution failed | `%{plan_id, reason}` |
| `htn.task.started` | Before executing primitive | `%{plan_id, task_name}` |
| `htn.task.completed` | After successful primitive | `%{plan_id, task_name, result}` |
| `htn.task.failed` | Primitive execution failed | `%{plan_id, task_name, reason}` |

### 3.3 Background Task Signal Flow

```
┌──────────────────┐                    ┌──────────────────┐
│   Parent Agent   │                    │   Child Agent    │
│ (HTN Strategy)   │                    │   (Worker)       │
└────────┬─────────┘                    └────────┬─────────┘
         │                                       │
         │  1. PrimitiveTask emits               │
         │     %SpawnAgent{agent: Worker}        │
         │──────────────────────────────────────>│
         │                                       │
         │  2. Child performs work               │
         │                                       │
         │  3. Child emits to parent:            │
         │     Signal: "worker.result"           │
         │<──────────────────────────────────────│
         │                                       │
         │  4. signal_routes maps to             │
         │     :htn_task_event                   │
         │                                       │
         │  5. HTN Strategy advances             │
         │     plan cursor                       │
         ▼                                       ▼
```

---

## 4. Effect & Directive Accumulation

### 4.1 HTN Runtime Tick Structure

```elixir
defmodule Jido.HTN.Runtime.Tick do
  @moduledoc """
  Execution state carrier for HTN plan execution.
  Mirrors the BehaviorTree Tick pattern for consistency.
  """
  
  @enforce_keys [:agent, :domain]
  defstruct [
    :agent,            # Current Jido.Agent struct
    :domain,           # Jido.HTN.Domain.t()
    :world_state,      # Planner's simulated world state
    :plan,             # [{module, keyword}] from planner
    :cursor,           # Current plan index
    :plan_id,          # Correlation ID
    :status,           # :idle | :running | :waiting | :success | :failure
    :last_result,      # Last action result
    :last_error,       # Last error if any
    directives: [],    # Accumulated directives
    meta: %{}          # Debug info, timestamps, etc.
  ]

  # Helpers for immutable updates
  def update_agent(%__MODULE__{} = tick, agent) do
    %{tick | agent: agent}
  end

  def update_world_state(%__MODULE__{} = tick, world_state) do
    %{tick | world_state: world_state}
  end

  def append_directives(%__MODULE__{directives: dirs} = tick, new_dirs) do
    %{tick | directives: dirs ++ List.wrap(new_dirs)}
  end

  def advance_cursor(%__MODULE__{cursor: c} = tick) do
    %{tick | cursor: c + 1}
  end

  def put(%__MODULE__{meta: meta} = tick, key, value) do
    %{tick | meta: Map.put(meta, key, value)}
  end
end
```

### 4.2 Primitive Task Execution with Effects

```elixir
defmodule Jido.HTN.PrimitiveTask do
  # ... existing struct definition ...

  @spec execute(t(), %{agent: Jido.Agent.t(), ctx: map()}) ::
          {:ok, Jido.Agent.t(), map(), [Jido.Agent.Directive.t()]}
          | {:error, any(), Jido.Agent.t(), [Jido.Agent.Directive.t()]}
  def execute(%__MODULE__{task: {action_mod, params}} = _task,
              %{agent: agent, ctx: ctx}) do
    
    exec_input = %{
      action: action_mod,
      params: Map.new(params),
      context: ctx
    }

    case Jido.Exec.run(exec_input) do
      {:ok, result, effects} ->
        # 1. Apply result to agent state
        agent1 = Jido.Agent.Effects.apply_result(agent, result)
        
        # 2. Apply effects and collect directives
        {agent2, directives} = Jido.Agent.Effects.apply_effects(agent1, List.wrap(effects))
        
        {:ok, agent2, result, directives}

      {:error, reason, effects} ->
        {agent1, directives} = Jido.Agent.Effects.apply_effects(agent, List.wrap(effects))
        {:error, reason, agent1, directives}
    end
  end

  def execute(%__MODULE__{task: action_mod}, exec_ctx) when is_atom(action_mod) do
    execute(%__MODULE__{task: {action_mod, []}}, exec_ctx)
  end
end
```

### 4.3 Effect Flow Through Execution

```elixir
def execute_primitive_in_tick(tick, primitive_task, ctx) do
  alias Jido.HTN.Planner.EffectHandler
  
  case PrimitiveTask.execute(primitive_task, %{agent: tick.agent, ctx: ctx}) do
    {:ok, agent, result, new_directives} ->
      # 1. Update agent in tick
      tick = Tick.update_agent(tick, agent)
      
      # 2. Update HTN world_state for planner consistency
      world_state =
        EffectHandler.apply_all_effects_for_simulation(
          tick.domain,
          primitive_task,
          result,
          tick.world_state
        )
      tick = Tick.update_world_state(tick, world_state)
      
      # 3. Handle background task tracking
      tick =
        if primitive_task.background do
          world_state = Map.update!(tick.world_state, :background_tasks, 
            &MapSet.put(&1, primitive_task.name))
          Tick.update_world_state(tick, world_state)
        else
          tick
        end
      
      # 4. Accumulate directives
      tick = Tick.append_directives(tick, new_directives)
      
      # 5. Store result and advance cursor
      tick = tick
        |> Tick.put(:last_result, result)
        |> Tick.advance_cursor()
      
      {:ok, tick}

    {:error, reason, agent, directives} ->
      tick = tick
        |> Tick.update_agent(agent)
        |> Tick.append_directives(directives)
        |> Map.put(:status, :failure)
        |> Map.put(:last_error, reason)
      
      {:error, reason, tick}
  end
end
```

---

## 5. Strategy Module Implementation

### 5.1 Strategy State Structure

```elixir
defmodule Jido.Agent.Strategy.HTN.State do
  @moduledoc """
  HTN Strategy state stored in agent.state.__strategy__
  """
  
  @enforce_keys [:status]
  defstruct [
    :status,            # :idle | :planning | :running | :waiting | :success | :failure
    :domain,            # Jido.HTN.Domain.t() or domain module
    :world_state,       # Planner-simulated world state
    :plan,              # [{module(), keyword()}] from planner
    :plan_id,           # Correlation ID for this plan
    :cursor,            # Current position in plan
    :mtr,               # Method Traversal Record (optional)
    :background_tasks,  # MapSet of pending background task names
    :last_result,       # Last successful result
    :last_error,        # Last error
    config: %{}         # Domain-specific configuration
  ]
end
```

### 5.2 Strategy Callbacks

```elixir
defmodule Jido.Agent.Strategy.HTN do
  @moduledoc """
  HTN-based execution strategy for Jido Agents.
  
  Uses Hierarchical Task Network planning to decompose high-level goals
  into executable Jido Actions, then executes the resulting plan while
  accumulating directives.
  """
  
  use Jido.Agent.Strategy
  
  alias Jido.Agent.Strategy.State, as: StratState
  alias __MODULE__.State, as: HTNState
  alias Jido.HTN.Runtime.Tick
  
  # ============================================================================
  # signal_routes/1
  # ============================================================================
  
  @impl true
  def signal_routes(_ctx) do
    [
      {"htn.start",            {:strategy_cmd, :htn_start}},
      {"htn.cancel",           {:strategy_cmd, :htn_cancel}},
      {"htn.task.event",       {:strategy_cmd, :htn_task_event}},
      {"htn.replan",           {:strategy_cmd, :htn_replan}},
      {"worker.result",        {:strategy_cmd, :htn_task_event}},
      {"jido.agent.child.exit", {:strategy_cmd, :htn_child_exit}}
    ]
  end
  
  # ============================================================================
  # init/2
  # ============================================================================
  
  @impl true
  def init(agent, %{strategy_opts: opts} = _ctx) do
    domain = resolve_domain(opts)
    
    init_state = %HTNState{
      status: :idle,
      domain: domain,
      world_state: %{background_tasks: MapSet.new()},
      plan: [],
      cursor: 0,
      background_tasks: MapSet.new(),
      config: Map.new(opts)
    }

    agent = StratState.put(agent, init_state)
    {agent, []}
  end
  
  defp resolve_domain(opts) do
    case Keyword.fetch!(opts, :domain) do
      mod when is_atom(mod) -> 
        if function_exported?(mod, :domain, 0), do: mod.domain(), else: mod.build()
      %Jido.HTN.Domain{} = d -> d
    end
  end
  
  # ============================================================================
  # cmd/3
  # ============================================================================
  
  @impl true
  def cmd(agent, instructions, ctx) do
    case instructions do
      [%{action: :htn_start, params: params} | _] ->
        handle_start(agent, params, ctx)
        
      [%{action: :htn_cancel, params: params} | _] ->
        handle_cancel(agent, params, ctx)
        
      [%{action: :htn_task_event, params: params} | _] ->
        handle_task_event(agent, params, ctx)
        
      [%{action: :htn_replan, params: params} | _] ->
        handle_replan(agent, params, ctx)
        
      [%{action: :htn_child_exit, params: params} | _] ->
        handle_child_exit(agent, params, ctx)
        
      [%{action: action} | _] ->
        # Unknown action - could delegate to default or error
        {:error, {:unknown_htn_action, action}, agent, []}
    end
  end
  
  # ============================================================================
  # tick/2
  # ============================================================================
  
  @impl true
  def tick(agent, ctx) do
    state = StratState.get(agent, %HTNState{status: :idle})
    
    case state.status do
      :running ->
        tick = build_tick_from_state(agent, state)
        {status, tick} = run_until_block_or_done(tick, ctx)
        agent = write_tick_to_agent(tick, status)
        {agent, tick.directives}
        
      _other ->
        # Nothing to do when not running
        {agent, []}
    end
  end
  
  # ============================================================================
  # snapshot/2
  # ============================================================================
  
  @impl true
  def snapshot(agent, _ctx) do
    state = StratState.get(agent, %HTNState{status: :idle})
    
    %Jido.Agent.Strategy.Snapshot{
      status: state.status,
      done?: state.status in [:success, :failure],
      result: state.last_result,
      details: %{
        plan_id: state.plan_id,
        cursor: state.cursor,
        plan_length: length(state.plan || []),
        background_tasks: MapSet.to_list(state.background_tasks || MapSet.new()),
        last_error: state.last_error
      }
    }
  end
  
  # ============================================================================
  # Private Handlers
  # ============================================================================
  
  defp handle_start(agent, params, ctx) do
    state = StratState.get(agent, %HTNState{status: :idle})
    
    # 1. Build initial world_state from params and agent state
    world_state = build_world_state(agent, params, state)
    
    # 2. Plan
    plan_opts = [
      root_tasks: Map.get(params, :root_tasks),
      timeout: Map.get(params, :timeout, 5000),
      debug: Map.get(params, :debug, false)
    ] |> Enum.reject(fn {_, v} -> is_nil(v) end)
    
    case Jido.HTN.plan(state.domain, world_state, plan_opts) do
      {:ok, plan, mtr} ->
        plan_id = generate_plan_id()
        
        # 3. Initialize execution state
        new_state = %{state |
          status: :running,
          world_state: world_state,
          plan: plan,
          plan_id: plan_id,
          cursor: 0,
          mtr: mtr,
          last_error: nil
        }
        
        # 4. Build tick and execute
        agent = StratState.put(agent, new_state)
        tick = build_tick_from_state(agent, new_state)
        
        # Emit plan started signal
        start_signal = build_signal("htn.plan.started", %{
          plan_id: plan_id,
          task_count: length(plan)
        })
        tick = Tick.append_directives(tick, [Jido.Agent.Directive.emit(start_signal)])
        
        # 5. Execute synchronously until blocked or done
        {status, tick} = run_until_block_or_done(tick, ctx)
        agent = write_tick_to_agent(tick, status)
        
        {agent, tick.directives}
        
      {:ok, plan, mtr, _debug_tree} ->
        # Same as above, with debug tree
        handle_plan_success(agent, state, plan, mtr, params, ctx)
        
      {:error, reason} ->
        error_directive = %Jido.Agent.Directive.Error{
          reason: {:planning_failed, reason}
        }
        new_state = %{state | status: :failure, last_error: reason}
        agent = StratState.put(agent, new_state)
        {agent, [error_directive]}
    end
  end
  
  defp handle_cancel(agent, _params, _ctx) do
    state = StratState.get(agent, %HTNState{status: :idle})
    
    new_state = %{state |
      status: :idle,
      plan: [],
      cursor: 0,
      last_error: :cancelled
    }
    
    agent = StratState.put(agent, new_state)
    {agent, []}
  end
  
  defp handle_task_event(agent, params, ctx) do
    state = StratState.get(agent, %HTNState{status: :idle})
    
    # Update world_state based on event
    task_name = Map.get(params, :task_name)
    task_status = Map.get(params, :status, :completed)
    
    case task_status do
      :completed ->
        # Remove from background_tasks if present
        background_tasks = MapSet.delete(state.background_tasks, task_name)
        new_state = %{state | background_tasks: background_tasks}
        
        # Potentially update world_state with result
        world_state = if result = Map.get(params, :result) do
          Map.merge(state.world_state, result)
        else
          state.world_state
        end
        new_state = %{new_state | world_state: world_state}
        
        agent = StratState.put(agent, new_state)
        
        # Continue execution if we were waiting
        if state.status == :waiting do
          tick(agent, ctx)
        else
          {agent, []}
        end
        
      :failed ->
        error_signal = build_signal("htn.task.failed", %{
          task_name: task_name,
          reason: Map.get(params, :reason)
        })
        new_state = %{state | status: :failure, last_error: Map.get(params, :reason)}
        agent = StratState.put(agent, new_state)
        {agent, [Jido.Agent.Directive.emit(error_signal)]}
    end
  end
  
  defp handle_replan(agent, params, ctx) do
    # Cancel current and start fresh
    {agent, _} = handle_cancel(agent, %{}, ctx)
    handle_start(agent, params, ctx)
  end
  
  defp handle_child_exit(agent, params, _ctx) do
    state = StratState.get(agent, %HTNState{status: :idle})
    
    # Map child exit to task event
    tag = Map.get(params, :tag)
    reason = Map.get(params, :reason, :normal)
    
    if reason == :normal do
      # Mark as completed
      background_tasks = MapSet.delete(state.background_tasks, tag)
      new_state = %{state | background_tasks: background_tasks}
      agent = StratState.put(agent, new_state)
      {agent, []}
    else
      # Mark as failed
      new_state = %{state | status: :failure, last_error: {:child_exit, tag, reason}}
      agent = StratState.put(agent, new_state)
      {agent, []}
    end
  end
  
  # ============================================================================
  # Execution Helpers
  # ============================================================================
  
  defp run_until_block_or_done(tick, ctx) do
    plan = tick.plan || []
    cursor = tick.cursor || 0
    
    if cursor >= length(plan) do
      # Plan complete
      complete_signal = build_signal("htn.plan.completed", %{
        plan_id: tick.plan_id,
        result: tick.last_result
      })
      tick = Tick.append_directives(tick, [Jido.Agent.Directive.emit(complete_signal)])
      {:success, tick}
    else
      # Get current task
      {action_mod, params} = Enum.at(plan, cursor)
      
      # Find primitive task from domain for metadata
      primitive_task = find_primitive_by_action(tick.domain, action_mod, params)
      
      case execute_primitive_in_tick(tick, primitive_task, action_mod, params, ctx) do
        {:ok, tick} ->
          # Continue to next task
          run_until_block_or_done(tick, ctx)
          
        {:waiting, tick} ->
          # Background task started, continue but mark waiting
          run_until_block_or_done(tick, ctx)
          
        {:error, _reason, tick} ->
          {:failure, tick}
      end
    end
  end
  
  defp execute_primitive_in_tick(tick, primitive_task, action_mod, params, ctx) do
    alias Jido.HTN.Planner.EffectHandler
    
    exec_input = %{
      action: action_mod,
      params: Map.new(params),
      context: ctx
    }
    
    case Jido.Exec.run(exec_input) do
      {:ok, result, effects} ->
        # 1. Apply result to agent
        agent = Jido.Agent.Effects.apply_result(tick.agent, result)
        
        # 2. Apply effects and collect directives
        {agent, new_directives} = Jido.Agent.Effects.apply_effects(agent, List.wrap(effects))
        
        # 3. Update tick with agent
        tick = Tick.update_agent(tick, agent)
        
        # 4. Update HTN world_state
        world_state = if primitive_task do
          EffectHandler.apply_all_effects_for_simulation(
            tick.domain,
            primitive_task,
            result,
            tick.world_state
          )
        else
          tick.world_state
        end
        tick = Tick.update_world_state(tick, world_state)
        
        # 5. Handle background tracking
        tick = if primitive_task && primitive_task.background do
          ws = Map.update!(tick.world_state, :background_tasks, 
            &MapSet.put(&1, primitive_task.name))
          Tick.update_world_state(tick, ws)
        else
          tick
        end
        
        # 6. Accumulate directives
        tick = Tick.append_directives(tick, new_directives)
        
        # 7. Emit task completed signal
        complete_signal = build_signal("htn.task.completed", %{
          plan_id: tick.plan_id,
          task_name: if(primitive_task, do: primitive_task.name, else: "#{action_mod}"),
          result: result
        })
        tick = Tick.append_directives(tick, [Jido.Agent.Directive.emit(complete_signal)])
        
        # 8. Store result and advance cursor
        tick = tick
          |> Tick.put(:last_result, result)
          |> Tick.advance_cursor()
        
        if primitive_task && primitive_task.background do
          {:waiting, tick}
        else
          {:ok, tick}
        end

      {:error, reason, effects} ->
        {agent, directives} = Jido.Agent.Effects.apply_effects(tick.agent, List.wrap(effects))
        tick = tick
          |> Tick.update_agent(agent)
          |> Tick.append_directives(directives)
          |> Map.put(:last_error, reason)
        
        {:error, reason, tick}
    end
  end
  
  defp find_primitive_by_action(domain, action_mod, _params) do
    # Search domain tasks for matching action
    Enum.find_value(domain.tasks, fn {_name, task} ->
      case task do
        %Jido.HTN.PrimitiveTask{task: {^action_mod, _}} -> task
        %Jido.HTN.PrimitiveTask{task: ^action_mod} -> task
        _ -> nil
      end
    end)
  end
  
  # ============================================================================
  # State Management Helpers
  # ============================================================================
  
  defp build_tick_from_state(agent, state) do
    %Tick{
      agent: agent,
      domain: state.domain,
      world_state: state.world_state,
      plan: state.plan,
      cursor: state.cursor,
      plan_id: state.plan_id,
      status: state.status,
      directives: [],
      meta: %{}
    }
  end
  
  defp write_tick_to_agent(tick, status) do
    state = StratState.get(tick.agent, %HTNState{status: :idle})
    
    new_state = %{state |
      status: status,
      world_state: tick.world_state,
      cursor: tick.cursor,
      last_result: tick.meta[:last_result],
      last_error: tick.last_error
    }
    
    StratState.put(tick.agent, new_state)
  end
  
  defp build_world_state(agent, params, _state) do
    # Merge agent state with params, add background tracking
    base = Map.get(params, :world_state, %{})
    
    base
    |> Map.merge(Map.get(agent.state, :world, %{}))
    |> Map.put_new(:background_tasks, MapSet.new())
  end
  
  defp build_signal(type, data) do
    Jido.Signal.new!(type, data, source: "/htn")
  end
  
  defp generate_plan_id do
    "plan_#{System.unique_integer([:positive])}"
  end
  
  defp handle_plan_success(agent, state, plan, mtr, _params, ctx) do
    plan_id = generate_plan_id()
    
    new_state = %{state |
      status: :running,
      plan: plan,
      plan_id: plan_id,
      cursor: 0,
      mtr: mtr,
      last_error: nil
    }
    
    agent = StratState.put(agent, new_state)
    tick = build_tick_from_state(agent, new_state)
    
    start_signal = build_signal("htn.plan.started", %{
      plan_id: plan_id,
      task_count: length(plan)
    })
    tick = Tick.append_directives(tick, [Jido.Agent.Directive.emit(start_signal)])
    
    {status, tick} = run_until_block_or_done(tick, ctx)
    agent = write_tick_to_agent(tick, status)
    
    {agent, tick.directives}
  end
end
```

---

## 6. Multi-Agent Coordination

### 6.1 SpawnAgent from HTN Tasks

**Action that spawns child agents:**

```elixir
defmodule MyApp.Actions.SpawnWorker do
  use Jido.Action,
    name: "spawn_worker",
    description: "Spawn a child worker agent",
    schema: [
      worker_module: [type: :atom, required: true],
      tag: [type: :atom, required: true],
      initial_state: [type: :map, default: %{}]
    ]

  @impl true
  def run(params, _ctx) do
    directive = %Jido.Agent.Directive.SpawnAgent{
      agent: params.worker_module,
      tag: params.tag,
      opts: %{initial_state: params.initial_state}
    }
    
    {:ok, %{spawned: params.tag}, [directive]}
  end
end
```

**HTN Domain using spawn action:**

```elixir
Domain.new("coordinator")
|> Domain.primitive("spawn_processor", 
    {MyApp.Actions.SpawnWorker, [worker_module: ProcessorAgent, tag: :processor]},
    preconditions: [&needs_processor?/1],
    effects: [fn _ -> %{processor_spawned: true} end],
    background: true
  )
|> Domain.primitive("spawn_validator",
    {MyApp.Actions.SpawnWorker, [worker_module: ValidatorAgent, tag: :validator]},
    preconditions: [&needs_validator?/1],
    effects: [fn _ -> %{validator_spawned: true} end],
    background: true
  )
|> Domain.compound("coordinate_work",
    methods: [
      %{
        name: "parallel_workers",
        preconditions: [],
        subtasks: ["spawn_processor", "spawn_validator", "wait_for_results"]
      }
    ]
  )
```

### 6.2 Child Agent Emitting to Parent

```elixir
defmodule MyApp.Actions.ReportResult do
  use Jido.Action,
    name: "report_result",
    description: "Report result back to parent agent"

  @impl true
  def run(params, ctx) do
    result_signal = Jido.Signal.new!("worker.result", %{
      task_id: params.task_id,
      result: params.result
    })
    
    # Emit to parent using context
    directive = Jido.Agent.Directive.emit_to_parent(ctx.agent, result_signal)
    
    {:ok, %{reported: true}, [directive]}
  end
end
```

### 6.3 Coordination Pattern Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Coordinator Agent (HTN Strategy)                │
│                                                                     │
│  Domain: coordinate_work                                            │
│    └── Method: parallel_workers                                     │
│          ├── spawn_processor  ──┐                                   │
│          ├── spawn_validator  ──┼── All emit %SpawnAgent{}          │
│          └── wait_for_results ──┘                                   │
│                                                                     │
│  signal_routes:                                                     │
│    "worker.result" → :htn_task_event                                │
│    "jido.agent.child.exit" → :htn_child_exit                        │
└────────────────────────┬────────────────────────────────────────────┘
                         │
         ┌───────────────┼───────────────┐
         ▼               ▼               ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ Processor Agent │ │ Validator Agent │ │  Other Child    │
│                 │ │                 │ │                 │
│ On completion:  │ │ On completion:  │ │                 │
│ emit_to_parent  │ │ emit_to_parent  │ │                 │
│ "worker.result" │ │ "worker.result" │ │                 │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

---

## 7. Implementation Priority

### Phase 1: Core Integration (P0) - 1 Day

| Task | Description | Files |
|------|-------------|-------|
| **7.1** | Implement `PrimitiveTask.execute/2` with `Jido.Exec` | `primitive_task.ex` |
| **7.2** | Create `Jido.HTN.Runtime.Tick` module | `lib/jido_htn/runtime/tick.ex` |
| **7.3** | Create `Jido.Agent.Strategy.HTN` basic structure | `lib/jido_htn/strategy/htn.ex` |
| **7.4** | Implement `init/2`, `cmd/3` (`:htn_start`, `:htn_cancel`) | `strategy/htn.ex` |
| **7.5** | Implement `tick/2` for plan execution | `strategy/htn.ex` |
| **7.6** | Implement `snapshot/2` | `strategy/htn.ex` |

### Phase 2: Planner Integration (P1) - 0.5 Day

| Task | Description | Files |
|------|-------------|-------|
| **7.7** | Wire `Jido.HTN.plan/3` to strategy | `strategy/htn.ex` |
| **7.8** | Sync `world_state` updates via `EffectHandler` | `strategy/htn.ex` |
| **7.9** | Add basic `signal_routes/1` | `strategy/htn.ex` |
| **7.10** | Implement `:htn_task_event` handler | `strategy/htn.ex` |

### Phase 3: Background & Signals (P2) - 0.5 Day

| Task | Description | Files |
|------|-------------|-------|
| **7.11** | Track `background_tasks` in strategy state | `strategy/htn.ex` |
| **7.12** | Implement `:htn_replan` handler | `strategy/htn.ex` |
| **7.13** | Emit lifecycle signals (`htn.plan.*`, `htn.task.*`) | `strategy/htn.ex` |
| **7.14** | Handle child exit signals | `strategy/htn.ex` |

### Phase 4: Multi-Agent Patterns (P3) - Optional

| Task | Description | Files |
|------|-------------|-------|
| **7.15** | Create example SpawnAgent action | `examples/` |
| **7.16** | Create example emit_to_parent pattern | `examples/` |
| **7.17** | Document multi-agent coordination patterns | `guides/` |

---

## 8. File Structure After Implementation

```
projects/jido_htn/
├── lib/
│   ├── jido_htn.ex                    # Main module (existing)
│   ├── jido_htn/
│   │   ├── domain.ex                  # Domain builder (existing)
│   │   ├── domain/                    # Domain helpers (existing)
│   │   ├── planner.ex                 # HTN planner (existing)
│   │   ├── planner/                   # Planner modules (existing)
│   │   ├── primitive_task.ex          # UPDATED: Add execute/2
│   │   ├── compound_task.ex           # (existing)
│   │   ├── method.ex                  # (existing)
│   │   ├── runtime/                   # NEW DIRECTORY
│   │   │   └── tick.ex                # NEW: Execution state carrier
│   │   └── strategy/                  # NEW DIRECTORY
│   │       ├── htn.ex                 # NEW: Strategy.HTN module
│   │       └── state.ex               # NEW: HTN strategy state struct
│   └── examples/
│       ├── multi_agent_coordination.ex # NEW: Example patterns
│       └── simple_htn_agent.ex         # NEW: Basic usage example
├── test/
│   ├── jido_htn/
│   │   ├── runtime/
│   │   │   └── tick_test.exs          # NEW
│   │   └── strategy/
│   │       └── htn_test.exs           # NEW
│   └── integration/
│       └── htn_strategy_test.exs      # NEW: Full integration test
└── guides/
    ├── getting_started.md             # NEW
    ├── signals_and_coordination.md    # NEW
    └── multi_agent_patterns.md        # NEW
```

---

## 9. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Diverging world_state vs agent.state** | State inconsistency during execution | Clear contract: derive world_state from agent.state at plan start; update both during execution |
| **Async race conditions** | Incorrect plan progression | Start synchronous; add explicit state machine for pending tasks before async |
| **Signal overload** | Brittle routing | Define small canonical signal set; domain actions wrap domain-specific events |
| **Strategy state bloat** | Heavy snapshots, hard debugging | Keep only: domain ref, plan, cursor, world_state, background_tasks, status |

---

## 10. Success Criteria

1. **Basic HTN Agent Works**
   - `use Jido.Agent, strategy: {Jido.Agent.Strategy.HTN, domain: MyDomain}`
   - `MyAgent.cmd(agent, :htn_start)` plans and executes

2. **Directives Flow Correctly**
   - Actions returning `%SpawnAgent{}` spawn child agents
   - Actions returning `%Emit{}` emit signals

3. **Signals Route Properly**
   - External `"htn.start"` signal triggers planning
   - Child `"worker.result"` signals update parent HTN

4. **Background Tasks Work**
   - `background: true` tasks don't block plan progression
   - Completion signals update world_state

5. **Tests Pass**
   - Unit tests for Tick, Strategy.HTN
   - Integration test with real domain + actions

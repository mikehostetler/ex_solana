# Research: Define Effects for HTN Planning/Execution

**Item ID:** 012-define-effects-for-htn-planningexecution
**Date:** 2026-01-07
**Status:** Researched

## Executive Summary

This research analyzes the current HTN (Hierarchical Task Network) implementation to define a comprehensive effects system for planning and execution operations. The goal is to make the HTN engine's behavior explicit, observable, and composable through a well-structured effect vocabulary, similar to how Jido agents use internal effects and external directives.

**Key Finding:** The HTN planner already has a basic effect system for state simulation, but lacks:
1. **Explicit effect structs** - Current effects are anonymous functions
2. **Observability** - No telemetry/events for planning operations
3. **Separation of concerns** - Planning effects mixed with execution effects
4. **Type safety** - No validation or schema for effect payloads

## 1. Project Dependencies Discovered

### Core Dependencies (from mix.exs)

**jido_htn** (projects/jido_htn/mix.exs):
- `zoi ~> 0.14` - Schema validation and struct generation
- `jido` (path: "../jido") - Core agent system (~> 1.3.0)
- `jido_action` (path: "../jido_action") - Action system (~> 1.3.0)
- `ex_dbug ~> 2.0` - Debugging utilities
- `proper_case ~> 1.3` - Case conversion
- `private ~> 0.1.2` - Private macro
- `deep_merge ~> 1.0` - Deep map merging
- Testing: `mimic ~> 2.0`, `excoveralls ~> 0.18.3`, `stream_data ~> 1.0`

**jido** (projects/jido/mix.exs):
- `jido_signal` (path: "../jido_signal") - Signal/event system
- `phoenix_pubsub ~> 2.1` - Pub/sub for distributed communication
- `telemetry ~> 1.3` - Telemetry events
- `telemetry_metrics ~> 1.1` - Telemetry metrics
- `fsmx ~> 0.5` - Finite state machine
- `msgpax ~> 2.3` - MessagePack serialization
- `nimble_options ~> 1.1` - Options validation

### Architectural Patterns Discovered

1. **Zoi Schemas** - All structs use Zoi for validation and type specs
2. **Internal Effects Pattern** - Jido.Agent.Internal defines effect structs (SetState, ReplaceState, etc.)
3. **Telemetry Integration** - Jido.Telemetry emits events for agent operations
4. **Signal System** - jido_signal provides event dispatching
5. **Effect Application** - Jido.Agent.Effects separates internal from external effects

## 2. Current HTN Effects Implementation

### Existing Effect System

**File:** `projects/jido_htn/lib/jido_htn/planner/effect_handler.ex`

```elixir
defmodule Jido.HTN.Planner.EffectHandler do
  @moduledoc """
  Handles the application of effects in the HTN planner.
  """

  @spec apply_effects(map(), list(), map(), map()) :: map()
  def apply_effects(domain, effects, result, world_state) do
    Enum.reduce(effects, world_state, fn effect, acc ->
      case effect do
        effect when is_function(effect, 1) ->
          Map.merge(acc, effect.(result))

        effect when is_binary(effect) ->
          case Map.get(domain.callbacks, effect) do
            nil -> acc
            callback -> Map.merge(acc, callback.(result))
          end
      end
    end)
  end

  @spec apply_all_effects_for_simulation(map(), struct(), map(), map()) :: map()
  def apply_all_effects_for_simulation(
        domain,
        %Jido.HTN.PrimitiveTask{effects: regular_effects, expected_effects: expected_effects},
        result,
        world_state
      ) do
    # Apply expected effects first for planning simulation
    simulated_state_after_expected =
      Enum.reduce(expected_effects, world_state, fn effect_fun, acc_state ->
        Map.merge(acc_state, effect_fun.(acc_state))
      end)

    # Then apply regular effects
    apply_effects(domain, regular_effects, result, simulated_state_after_expected)
  end
end
```

**Current Issues:**
- Effects are anonymous functions or string callback names
- No type safety or validation
- No observability or telemetry
- Mixes planning-time simulation with execution-time effects
- No structured metadata (plan ID, task IDs, timestamps, etc.)

### PrimitiveTask Effects Schema

**File:** `projects/jido_htn/lib/jido_htn/primitive_task.ex:41-52`

```elixir
effects:
  Zoi.list(
    Zoi.function(),
    description: "Functions that transform world state"
  )
  |> Zoi.default([]),
expected_effects:
  Zoi.list(
    Zoi.function(),
    description: "Expected world state transformations"
  )
  |> Zoi.default([]),
```

## 3. Jido Effects Patterns to Follow

### Internal Effects Pattern

**File:** `projects/jido/lib/jido/agent/internal.ex`

```elixir
defmodule Jido.Agent.Internal do
  @moduledoc """
  Internal effects that strategies handle to update agent state.

  Separated from directives to maintain a clean boundary:
  - Internal effects → modify agent state within the strategy
  - Directives → external effects for the runtime to execute

  Available Effects:
  - SetState - Deep merge attributes into state
  - ReplaceState - Replace state wholesale
  - DeleteKeys - Remove top-level keys
  - SetPath - Set value at nested path
  - DeletePath - Delete value at nested path
  """
end
```

**Key Pattern:** Each effect is a Zoi struct with:
- Clear module documentation
- Schema with type-safe fields
- Descriptive field names with descriptions
- Helper constructor functions

### Effect Application Pattern

**File:** `projects/jido/lib/jido/agent/effects.ex:41-66`

```elixir
@spec apply_effects(Agent.t(), [struct()]) :: {Agent.t(), [struct()]}
def apply_effects(%Agent{} = agent, effects) do
  Enum.reduce(effects, {agent, []}, fn
    %Internal.SetState{attrs: attrs}, {a, directives} ->
      new_state = Jido.Agent.State.merge(a.state, attrs)
      {%{a | state: new_state}, directives}

    %Internal.ReplaceState{state: new_state}, {a, directives} ->
      {%{a | state: new_state}, directives}

    # ... other internal effects

    %_{} = directive, {a, directives} ->
      {a, directives ++ [directive]}
  end)
end
```

**Key Pattern:** Pattern matching on effect structs, separating internal state changes from external directives.

### Telemetry Pattern

**File:** `projects/jido/lib/jido/telemetry.ex:9-34`

```elixir
@moduledoc """
Telemetry events for Jido Agent and Strategy operations.

Events:
- [:jido, :agent, :cmd, :start] - Agent command execution started
- [:jido, :agent, :cmd, :stop] - Agent command execution completed
- [:jido, :agent, :strategy, :init, :start] - Strategy initialization started
- [:jido, :agent_server, :signal, :start] - Signal processing started
...
"""
```

**Key Pattern:** Well-documented telemetry events with:
- Clear event names (nested list of atoms)
- Metadata structure documented
- Measurements documented
- Consistent naming: `[:jido, :subsystem, :operation, :lifecycle]`

## 4. Files Requiring Changes

### New Files to Create

#### 1. `projects/jido_htn/lib/jido_htn/effects.ex`
**Purpose:** Define HTN-specific effect structs

**Required Effect Types:**

**Planning Effects (planning-time operations):**
- `MethodSelected` - A method was chosen for task decomposition
- `TaskDecomposed` - A compound task was decomposed into subtasks
- `PrimitiveTaskScheduled` - A primitive task was added to the plan
- `PlanningFailed` - Planning failed with error details
- `PlanPruned` - A planning branch was pruned due to priority/cost

**State Effects (world state changes):**
- `WorldStateUpdated` - State changed during planning simulation
- `StateSnapshot` - Snapshot of world state at a point in planning

**Execution Effects (runtime execution):**
- `TaskStarted` - A primitive task began execution
- `TaskCompleted` - A primitive task completed successfully
- `TaskFailed` - A primitive task failed
- `ActionExecuted` - A Jido.Action was executed

**Metadata Fields:**
- `plan_id` - Unique identifier for the planning attempt
- `task_id` - Task identifier
- `method_id` - Method identifier
- `timestamp` - When the effect occurred
- `depth` - Planning depth
- `correlation_id` - For tracking related effects

#### 2. `projects/jido_htn/lib/jido_htn/planner/effects.ex`
**Purpose:** Effect application and emission logic

**Functions:**
- `emit_effects/2` - Emit effects to telemetry/signal system
- `apply_state_effects/3` - Apply state mutation effects
- `filter_observable_effects/1` - Separate observable from internal effects

#### 3. `projects/jido_htn/lib/jido_htn/telemetry.ex`
**Purpose:** HTN-specific telemetry event definitions

**Events:**
- `[:jido, :htn, :planning, :start]`
- `[:jido, :htn, :planning, :stop]`
- `[:jido, :htn, :planning, :failed]`
- `[:jido, :htn, :task, :decomposed]`
- `[:jido, :htn, :method, :selected]`
- `[:jido, :htn, :execution, :task_start]`
- `[:jido, :htn, :execution, :task_complete]`
- `[:jido, :htn, :execution, :task_failed]`

### Files to Modify

#### 1. `projects/jido_htn/lib/jido_htn/planner.ex`
**Changes:**
- Add plan ID generation
- Emit planning start/stop effects
- Track effects during planning
- Return effects alongside plan

**Line references:**
- `:17` - `plan/3` function: Add effect emission
- `:34` - `do_plan/5`: Wrap with telemetry span
- `:61` - `decompose/8`: Return effects
- `:116` - `do_plan/5`: Emit completion effects

#### 2. `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex`
**Changes:**
- Emit effect when method is selected (line ~219)
- Emit effect when task is decomposed
- Add effect metadata to MTR
- Track state changes as effects

**Line references:**
- `:28` - `decompose_task/8`: Emit decomposition effects
- `:60` - `decompose_primitive/5`: Emit primitive task effects
- `:96` - `decompose_compound/8`: Emit compound task effects
- `:219` - Method selection: Emit MethodSelected effect

#### 3. `projects/jido_htn/lib/jido_htn/planner/effect_handler.ex`
**Changes:**
- Accept structured effects in addition to functions
- Return observable effects alongside state
- Add effect validation
- Track effect application order

**Line references:**
- `:12` - `apply_effects/4`: Return emitted effects
- `:31` - `apply_all_effects_for_simulation/4`: Track expected vs actual effects

#### 4. `projects/jido_htn/lib/jido_htn/primitive_task.ex`
**Changes:**
- Update `effects` field schema to accept structs or functions
- Add `observable_effects` field for effects to emit externally
- Keep backward compatibility with function-based effects

**Line references:**
- `:41` - Update `effects` schema
- Add new field after `:52`

#### 5. `projects/jido_htn/lib/jido_htn/domain.ex`
**Changes:**
- Add `effect_handlers` callback map for effect routing
- Add `emit_effects?` boolean flag
- Add effect middleware configuration

**Line references:**
- `:24` - Add `effect_handlers` field
- `:28` - Add configuration fields

## 5. Existing Patterns to Follow

### Zoi Struct Pattern

**Example from Jido.Agent.Internal.SetState:**

```elixir
@schema Zoi.struct(
  __MODULE__,
  %{
    attrs: Zoi.map(description: "Attributes to merge into agent state")
  },
  coerce: true
)

@type t :: unquote(Zoi.type_spec(@schema))
@enforce_keys Zoi.Struct.enforce_keys(@schema)
defstruct Zoi.Struct.struct_fields(@schema)

def schema, do: @schema
```

### Helper Constructor Pattern

```elixir
@doc "Creates a SetState effect."
@spec set_state(map()) :: SetState.t()
def set_state(attrs) when is_map(attrs), do: %SetState{attrs: attrs}
```

### Telemetry Span Pattern

**From Jido.Telemetry:**

```elixir
@spec span_agent_cmd(Jido.Agent.t(), term(), (-> result)) :: result
def span_agent_cmd(agent, action, func) when is_function(func, 0) do
  start_time = System.monotonic_time()

  metadata = %{
    agent_id: agent.id,
    agent_module: agent.name,
    action: action
  }

  :telemetry.execute(
    [:jido, :agent, :cmd, :start],
    %{system_time: System.system_time()},
    metadata
  )

  try do
    result = func.()
    # ... emit stop event
    result
  catch
    kind, reason ->
      # ... emit exception event
      :erlang.raise(kind, reason, __STACKTRACE__)
  end
end
```

## 6. Integration Points

### Jido Signal System

**File:** `projects/jido_signal/lib/jido_signal/`

HTN effects should integrate with `jido_signal` for:
- Cross-process effect broadcasting
- Multi-agent coordination
- External observability

**Integration approach:**
```elixir
# In HTN planner
defp emit_effect(effect) do
  :telemetry.execute([:jido, :htn, :effect, :kind], measurements, metadata)
  JidoSignal.Bus.broadcast("htn:effects", effect)
end
```

### Jido Telemetry

**File:** `projects/jido/lib/jido/telemetry.ex`

Add HTN telemetry handlers following the existing pattern:
- Event definitions in module documentation
- Measurement and metadata schemas
- Handler functions for each event type
- Span helpers for planning operations

### Jido Actions Integration

**From:** `projects/jido_action/lib/jido_action/`

HTN primitive tasks execute Jido actions. Effects should:
- Wrap action execution with task started/completed effects
- Capture action results in effect metadata
- Map action errors to task failed effects

## 7. Proposed Effect Type System

### Planning Effects

```elixir
defmodule Jido.HTN.Effects.MethodSelected do
  @schema Zoi.struct(
    __MODULE__,
    %{
      plan_id: Zoi.string(description: "Planning attempt identifier"),
      task_name: Zoi.string(description: "Task being decomposed"),
      method_name: Zoi.string(description: "Method selected"),
      priority: Zoi.integer(description: "Method priority") |> Zoi.optional(),
      depth: Zoi.integer(description: "Decomposition depth"),
      timestamp: Zoi.integer(description: "Unix timestamp in microseconds")
    }
  )
end

defmodule Jido.HTN.Effects.TaskDecomposed do
  @schema Zoi.struct(
    __MODULE__,
    %{
      plan_id: Zoi.string(),
      task_name: Zoi.string(),
      subtask_count: Zoi.integer(),
      subtasks: Zoi.list(Zoi.string()),
      depth: Zoi.integer(),
      timestamp: Zoi.integer()
    }
  )
end

defmodule Jido.HTN.Effects.PlanningFailed do
  @schema Zoi.struct(
    __MODULE__,
    %{
      plan_id: Zoi.string(),
      reason: Zoi.string(),
      failed_at_task: Zoi.string() |> Zoi.optional(),
      partial_plan: Zoi.list(Zoi.any()) |> Zoi.optional(),
      timestamp: Zoi.integer()
    }
  )
end
```

### Execution Effects

```elixir
defmodule Jido.HTN.Effects.TaskStarted do
  @schema Zoi.struct(
    __MODULE__,
    %{
      plan_id: Zoi.string(),
      task_name: Zoi.string(),
      action_module: Zoi.atom(),
      action_params: Zoi.list(Zoi.any()),
      timestamp: Zoi.integer()
    }
  )
end

defmodule Jido.HTN.Effects.TaskCompleted do
  @schema Zoi.struct(
    __MODULE__,
    %{
      plan_id: Zoi.string(),
      task_name: Zoi.string(),
      duration_ms: Zoi.integer(),
      result: Zoi.map(),
      timestamp: Zoi.integer()
    }
  )
end
```

## 8. Backward Compatibility Strategy

### Phase 1: Add Structured Effects (Non-Breaking)
- Add new effect structs alongside existing function effects
- Update `PrimitiveTask` to accept both functions and structs
- `EffectHandler` detects type and applies appropriately
- Existing domains continue to work without changes

### Phase 2: Emit Effects (Non-Breaking)
- Add telemetry emission hooks in planner
- Effects emitted but not consumed by default
- Opt-in via Domain configuration flag

### Phase 3: Require Structured Effects (Breaking)
- Update documentation to use structured effects
- Provide migration guide
- Deprecate function-based effects
- Remove in next major version

## 9. Testing Considerations

### Test Files to Update

1. **`test/jido_htn/planner_test.exs`**
   - Add assertions for emitted effects
   - Test effect metadata structure
   - Verify telemetry events

2. **`test/jido_htn/planner/state_simulation_test.exs`**
   - Test that state effects work with new struct system
   - Verify expected_effects vs actual effects

3. **`test/jido_htn/effects_test.exs`** (new file)
   - Test each effect type's schema
   - Test effect application
   - Test effect emission
   - Test backward compatibility

4. **`test/jido_htn/telemetry_test.exs`** (new file)
   - Test telemetry event emission
   - Test event metadata
   - Test span helpers

### Mock Strategy

Use existing `mimic` dependency (already in mix.exs):
```elixir
# Mock effect emission
Mimic.stub(Jido.HTN.Telemetry, :emit_effect, fn effect -> :ok end)
```

## 10. Documentation Requirements

### New Documentation Files

1. **`guides/effects.md`**
   - Effect system overview
   - Effect type reference
   - Creating custom effects
   - Effect handling patterns

2. **`guides/telemetry.md`**
   - Telemetry event reference
   - Metrics definitions
   - Observability patterns

3. **`guides/migration_guide.md`**
   - Migrating from function effects to structured effects
   - Breaking changes
   - Code examples

### Updated Documentation

1. **`guides/getting-started.md`**
   - Add effects section
   - Show telemetry setup

2. **`lib/jido_htn/planner/effect_handler.ex`**
   - Expand module documentation
   - Add effect type examples
   - Document migration path

## 11. Performance Considerations

### Effect Emission Overhead

**Current telemetry pattern (from Jido.Telemetry):**
- Events emitted synchronously
- Minimal overhead (~microseconds per event)
- Use `:telemetry.attach_many` for batch handlers

**Recommendations:**
- Make effect emission optional via config
- Use sampling for high-frequency effects
- Consider async emission for non-critical effects
- Add rate limiting for PlanPruned effects (can be spammy during backtracking)

### Memory Considerations

**Effect accumulation during planning:**
- Planning can generate thousands of effects
- Store effects in ETS table for large plans
- Limit effect history size (configurable)
- Provide effect streaming API

## 12. Risk Assessment

### Breaking Changes

**High Risk:**
- Changing `PrimitiveTask.effects` schema could break existing domains
- Changing `EffectHandler.apply_effects/4` signature

**Mitigation:**
- Support both function and struct effects during transition
- Use `Zoi.union()` for polymorphic fields
- Provide deprecation warnings
- Clear version bump documentation

### Performance Risks

**Medium Risk:**
- Effect emission overhead during planning
- Memory growth from effect accumulation
- Telemetry handler blocking

**Mitigation:**
- Make effects opt-in
- Use async telemetry handlers
- Implement effect sampling
- Add performance benchmarks

### Integration Risks

**Low Risk:**
- jido_signal integration complexity
- Telemetry event naming conflicts

**Mitigation:**
- Use namespaced event names
- Provide noop dispatcher fallback
- Test integration with existing Jido agents

## 13. Implementation Recommendations

### Phase 1: Foundation (1-2 days)
1. Create `Jido.HTN.Effects` module with effect structs
2. Create `Jido.HTN.Telemetry` module with event definitions
3. Add telemetry span helpers
4. Write unit tests for all effect types

### Phase 2: Integration (2-3 days)
1. Update `TaskDecomposer` to emit effects
2. Update `Planner` to track and return effects
3. Update `EffectHandler` to work with structured effects
4. Add integration tests

### Phase 3: Execution (1-2 days)
1. Add execution effect hooks
2. Integrate with jido_signal
3. Add telemetry handlers
4. Write end-to-end tests

### Phase 4: Documentation (1 day)
1. Write effect system guide
2. Write telemetry guide
3. Update existing documentation
4. Create migration examples

**Total Estimate:** 5-8 days

## 14. Open Questions

1. **Effect Persistence:** Should effects be persisted for replay/debugging?
   - Option A: In-memory only (current proposal)
   - Option B: Optional persistence to database/ETS
   - Option C: External effect log service

2. **Effect Filtering:** How should users control which effects are emitted?
   - Option A: Global enable/disable flags
   - Option B: Per-effect-type filters
   - Option C: Predicate functions

3. **Cross-Agent Coordination:** How do effects work with multiple agents using HTN?
   - Need effect correlation IDs
   - Should effects include agent_id?
   - Should effects be broadcast to other agents?

4. **Error Effects:** Should errors be represented as effects or separate error types?
   - Current: PlanningFailed effect
   - Alternative: Separate error notification system

5. **Behavior Tree Alignment:** Item 005 defines behavior tree effects. How should HTN effects align?
   - Share effect types?
   - Separate but parallel systems?
   - Common base effect module?

## 15. Related Items

### Prerequisites
- **009-convert-to-zoi-error-handling** - Effects should use Zoi error patterns
- **010-implement-explode-errors** - Effects should include error details

### Related Work
- **005-define-effects-for-behavior-tree-executi** - Defines BT effects, should align
- **013-define-signals-for-multi-agent-coordinat** - Effects should integrate with signals
- **011-modernize-to-current-jido-patterns-actio** - Ensure effect patterns match Jido conventions

## 16. Success Criteria

Implementation is complete when:

1. ✅ All HTN planning operations emit structured effects
2. ✅ All HTN execution operations emit structured effects
3. ✅ Effects include full metadata (plan_id, timestamps, depth, etc.)
4. ✅ Telemetry events emitted for all effect types
5. ✅ Effects integrate with jido_signal for cross-process communication
6. ✅ Backward compatibility maintained for function-based effects
7. ✅ Comprehensive test coverage (>90%)
8. ✅ Documentation complete with examples
9. ✅ Performance impact <10% overhead
10. ✅ Integration tests with existing Jido agents pass

## 17. References

### Code References
- `projects/jido/lib/jido/agent/internal.ex` - Internal effects pattern
- `projects/jido/lib/jido/agent/effects.ex` - Effect application pattern
- `projects/jido/lib/jido/telemetry.ex` - Telemetry pattern
- `projects/jido_htn/lib/jido_htn/planner/effect_handler.ex` - Current HTN effects
- `projects/jido_htn/lib/jido_htn/primitive_task.ex:41` - Effects schema

### Documentation References
- Zoi Documentation: https://hexdocs.pm/zoi (for effect schemas)
- Jido Agent Guides: `projects/jido/guides/agents.md`
- Telemetry Docs: https://hexdocs.pm/telemetry

### External Resources
- HTN Planning Research: Nau et al. "HTN Planning: An Overview"
- Effect Systems in Functional Programming: https://wiki.haskell.org/Effect_system
- Telemetry Best Practices: https://github.com/beam-telemetry/telemetry

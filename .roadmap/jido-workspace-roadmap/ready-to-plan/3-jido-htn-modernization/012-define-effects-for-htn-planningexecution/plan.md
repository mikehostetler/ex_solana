# Implementation Plan: Define Effects for HTN Planning/Execution

**Item ID:** 012-define-effects-for-htn-planningexecution
**Date:** 2026-01-07
**Status:** Planned
**Estimated Effort:** 5-8 days

## 1. Executive Summary

This implementation defines a comprehensive effects system for Jido's HTN (Hierarchical Task Network) planner that makes planning and execution operations explicit, observable, and composable. The effects system follows Jido's established patterns (internal effects, external directives, telemetry events) while maintaining backward compatibility with existing function-based effects.

**Key Architectural Decisions:**
- Effects are modeled as Zoi structs with type-safe fields and metadata
- Planning effects are separate from execution effects for clear separation of concerns
- Effects are emitted via telemetry for observability and jido_signal for coordination
- Backward compatibility maintained through polymorphic effect fields (functions OR structs)
- Effect emission is opt-in via Domain configuration to minimize overhead

**Expected Timeline:** 5-8 days total (4 implementation phases)

## 2. Impact Analysis Summary

### Key Findings from Research

The HTN planner currently uses anonymous functions for effects, which lacks:
1. **Type safety** - No validation or schema for effect payloads
2. **Observability** - No telemetry/events for planning operations
3. **Separation** - Planning effects mixed with execution effects
4. **Metadata** - No plan IDs, timestamps, depth tracking, or correlation IDs

### Files Requiring Changes

**New Files (3):**
1. `projects/jido_htn/lib/jido_htn/effects.ex` - Effect struct definitions
2. `projects/jido_htn/lib/jido_htn/planner/effects.ex` - Effect application logic
3. `projects/jido_htn/lib/jido_htn/telemetry.ex` - Telemetry event definitions

**Modified Files (5):**
1. `projects/jido_htn/lib/jido_htn/planner.ex` - Add plan ID tracking and effect emission
2. `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex` - Emit decomposition effects
3. `projects/jido_htn/lib/jido_htn/planner/effect_handler.ex` - Support structured effects
4. `projects/jido_htn/lib/jido_htn/primitive_task.ex` - Update effects schema
5. `projects/jido_htn/lib/jido_htn/domain.ex` - Add effect configuration fields

**Test Files (2 new, 2 updated):**
1. `test/jido_htn/effects_test.exs` (new) - Effect schema and application tests
2. `test/jido_htn/telemetry_test.exs` (new) - Telemetry event tests
3. `test/jido_htn/planner_test.exs` (update) - Assert emitted effects
4. `test/jido_htn/planner/state_simulation_test.exs` (update) - Test state effects

### Existing Patterns to Follow

**Jido.Agent.Internal Pattern** (`projects/jido/lib/jido/agent/internal.ex`):
- Each effect is a Zoi struct with schema validation
- Clear module documentation with effect list
- Helper constructor functions (e.g., `set_state/1`)

**Jido.Agent.Effects Pattern** (`projects/jido/lib/jido/agent/effects.ex`):
- Pattern match on effect structs
- Separate internal state changes from external directives
- Return tuple of `{agent_state, external_directives}`

**Jido.Telemetry Pattern** (`projects/jido/lib/jido/telemetry.ex`):
- Well-documented event names: `[:jido, :subsystem, :operation, :lifecycle]`
- Span helpers for operations with start/stop/exception events
- Metadata structure documented in module docs

### Integration Points Identified

1. **jido_signal** - Cross-process effect broadcasting for multi-agent coordination
2. **jido_telemetry** - Existing telemetry infrastructure for metrics
3. **jido_action** - HTN primitive tasks execute Jido actions, need effect wrapping
4. **Zoi 0.14** - Schema validation already in use for HTN structs

## 3. Feature Specification

### User Stories

**As a developer**, I want to observe HTN planning operations so I can debug complex planning failures.

*Acceptance Criteria:*
- Planning operations emit telemetry events with structured metadata
- Events include plan_id, task names, depth, timestamps
- Can attach telemetry handlers to inspect planning decisions
- Events correlate to planning operations via plan_id

**As a system operator**, I want to monitor HTN task execution so I can detect performance issues.

*Acceptance Criteria:*
- Task execution emits start/complete/failed events
- Events include duration, task name, action module
- Can track task execution through telemetry dashboards
- Failed tasks include error details

**As a multi-agent system architect**, I want HTN effects to integrate with jido_signal so agents can coordinate.

*Acceptance Criteria:*
- Effects broadcast to signal bus via jido_signal
- Effects include correlation IDs for tracking
- Can subscribe to effect streams from other agents
- Effect emission is opt-in to avoid performance overhead

**As a domain author**, I want backward compatibility so my existing domains continue to work.

*Acceptance Criteria:*
- Function-based effects still work
- No breaking changes to PrimitiveTask schema
- Can migrate to structured effects incrementally
- Clear deprecation warnings for old patterns

### API Contracts

#### Effect Structs

All effects follow this pattern:
```elixir
defmodule Jido.HTN.Effects.MethodSelected do
  @moduledoc "Emitted when a method is chosen for task decomposition."

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

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema

  @doc "Creates a MethodSelected effect."
  def new(attrs) when is_map(attrs) do
    Zoi.new!(__MODULE__, attrs)
  end
end
```

#### Planner API Changes

**Before:**
```elixir
{:ok, plan} = Jido.HTN.Planner.plan(domain, initial_task, world_state)
```

**After (backward compatible):**
```elixir
# Returns {:ok, plan, effects} tuple if effects enabled
{:ok, plan, effects} = Jido.HTN.Planner.plan(domain, initial_task, world_state)

# Returns {:ok, plan} if effects disabled (backward compatible)
{:ok, plan} = Jido.HTN.Planner.plan(domain, initial_task, world_state)
```

#### Domain Configuration

```elixir
defmodule MyDomain do
  use Jido.HTN.Domain

  domain do
    # Existing fields
    name "my_domain"
    version "1.0.0"

    # New effect configuration
    emit_effects? true
    effect_handlers %{
      "WorldStateUpdated" => &handle_state_update/2
    }
  end
end
```

### Data Flow

```
1. Planning starts
   ↓
2. Planner generates plan_id
   ↓
3. Telemetry span starts [:jido, :htn, :planning, :start]
   ↓
4. TaskDecomposer decomposes tasks
   ↓
5. Effects emitted at each step:
   - MethodSelected (when method chosen)
   - TaskDecomposed (when task decomposed)
   - PrimitiveTaskScheduled (when primitive added)
   ↓
6. EffectHandler applies state effects
   ↓
7. Planner collects all effects
   ↓
8. Telemetry span stops [:jido, :htn, :planning, :stop]
   ↓
9. Returns {:ok, plan, effects}
```

### State Management Requirements

**Effect Accumulation:**
- Effects collected in list during planning
- ETS table for large plans (>1000 effects)
- Configurable max effect history size

**Effect Metadata:**
- `plan_id` - UUID v4 generated at planning start
- `correlation_id` - Optional parent ID for nested planning
- `timestamp` - System.monotonic_time(:microsecond)
- `depth` - Current decomposition depth (for planning effects)

### Error Handling Approach

**Planning Failures:**
- Emit `PlanningFailed` effect with error details
- Include `failed_at_task`, `reason`, `partial_plan`
- Telemetry event: `[:jido, :htn, :planning, :failed]`

**Task Execution Failures:**
- Emit `TaskFailed` effect with error details
- Include `task_name`, `error`, `stacktrace`
- Telemetry event: `[:jido, :htn, :execution, :task_failed]`

**Effect Application Failures:**
- Use Splode for error reporting (consistent with Jido)
- Return `{:error, Splode.Error}` tuples
- Log errors but don't fail planning (best-effort application)

## 4. Technical Design

### Data Model Changes

#### Effect Type Hierarchy

```
Jido.HTN.Effects (module)
├── Planning Effects
│   ├── MethodSelected
│   ├── TaskDecomposed
│   ├── PrimitiveTaskScheduled
│   ├── PlanningFailed
│   └── PlanPruned
├── State Effects
│   ├── WorldStateUpdated
│   └── StateSnapshot
└── Execution Effects
    ├── TaskStarted
    ├── TaskCompleted
    ├── TaskFailed
    └── ActionExecuted
```

#### Effect Struct Schema

All effect structs share common metadata fields:
```elixir
%{
  plan_id: String.t(),           # UUID v4
  timestamp: integer(),           # Unix microseconds
  correlation_id: String.t() | nil  # Optional parent ID
}
```

Planning effects add:
```elixir
%{
  task_name: String.t(),
  depth: non_neg_integer()
}
```

Execution effects add:
```elixir
%{
  task_name: String.t(),
  action_module: atom() | nil,
  duration_ms: non_neg_integer() | nil
}
```

### Module Organization

```
projects/jido_htn/lib/jido_htn/
├── effects.ex                    # NEW: Effect struct definitions
│   ├── MethodSelected
│   ├── TaskDecomposed
│   ├── PrimitiveTaskScheduled
│   ├── PlanningFailed
│   ├── PlanPruned
│   ├── WorldStateUpdated
│   ├── StateSnapshot
│   ├── TaskStarted
│   ├── TaskCompleted
│   ├── TaskFailed
│   └── ActionExecuted
├── telemetry.ex                  # NEW: Telemetry event definitions
│   ├── event definitions
│   ├── span helpers
│   └── handler attachments
├── planner/
│   ├── effects.ex                # NEW: Effect application logic
│   │   ├── emit_effect/2
│   │   ├── apply_state_effects/3
│   │   └── filter_observable_effects/1
│   ├── effect_handler.ex         # MODIFY: Support structured effects
│   ├── task_decomposer.ex        # MODIFY: Emit effects
│   └── planner.ex                # MODIFY: Track and return effects
├── primitive_task.ex             # MODIFY: Update effects schema
└── domain.ex                     # MODIFY: Add effect configuration
```

### Third-Party Integration

#### Telemetry (existing dependency)

```elixir
# Emit effect
:telemetry.execute(
  [:jido, :htn, :method, :selected],
  %{duration: duration_ms},
  %{
    plan_id: plan_id,
    task_name: task_name,
    method_name: method_name,
    depth: depth
  }
)
```

#### jido_signal (existing via jido dependency)

```elixir
# Broadcast effect
JidoSignal.Bus.broadcast("htn:effects", %{
  type: "method_selected",
  plan_id: plan_id,
  data: effect
})
```

#### Zoi 0.14 (existing dependency)

All effects use Zoi for schema validation and type specs.

### Configuration/Environment Changes

#### Application Configuration

Add to `config/config.exs`:
```elixir
config :jido_htn,
  # Enable/disable effect emission globally
  emit_effects: true,
  # Effect history size (ETS table)
  max_effect_history: 10_000,
  # Effect sampling (1.0 = all, 0.1 = 10%)
  effect_sample_rate: 1.0
```

#### Domain Configuration

Add to Domain schema:
```elixir
emit_effects?: Zoi.boolean()
  |> Zoi.default(false)
  |> Zoi.description("Emit structured effects during planning"),

effect_handlers: Zoi.map()
  |> Zoi.default(%{})
  |> Zoi.description("Map of effect type names to handler functions")
```

## 5. Implementation Phases

### Phase 1: Foundation

**Objective:** Create effect struct definitions and telemetry infrastructure without modifying existing planner behavior.

**Success Criteria:**
- All effect structs defined with Zoi schemas
- Telemetry module with event definitions
- Unit tests for all effect types
- No changes to existing planner code

**Files to Create:**
1. `projects/jido_htn/lib/jido_htn/effects.ex`
2. `projects/jido_htn/lib/jido_htn/telemetry.ex`
3. `test/jido_htn/effects_test.exs`
4. `test/jido_htn/telemetry_test.exs`

**Files to Modify:**
1. `projects/jido_htn/mix.exs` - Ensure dependencies are up to date

**Tests to Add:**
- Test each effect struct's schema validation
- Test helper constructors
- Test optional fields
- Test timestamp auto-generation

**Dependencies:**
- None (foundational phase)

**Implementation Steps:**
1. Create `Jido.HTN.Effects` module with all 10 effect structs
2. Add `new/1` helper for each effect type
3. Create `Jido.HTN.Telemetry` with event documentation
4. Add `span_planning/4` helper for telemetry spans
5. Write unit tests for all effects
6. Write unit tests for telemetry helpers

### Phase 2: Core Integration

**Objective:** Update planner and task decomposer to emit effects during planning.

**Success Criteria:**
- Planner generates plan_id and tracks effects
- TaskDecomposer emits effects at key points
- EffectHandler supports both function and struct effects
- Integration tests pass

**Files to Modify:**
1. `projects/jido_htn/lib/jido_htn/planner.ex`
2. `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex`
3. `projects/jido_htn/lib/jido_htn/planner/effect_handler.ex`
4. `test/jido_htn/planner_test.exs`

**Tests to Add:**
- Test planner returns effects when enabled
- Test planner emits MethodSelected effects
- Test planner emits TaskDecomposed effects
- Test effect metadata is correct (plan_id, depth, timestamps)
- Test backward compatibility (effects disabled returns old format)

**Dependencies:**
- Phase 1 must be complete

**Implementation Steps:**
1. Update `Planner.plan/3` to generate plan_id
2. Wrap planning with telemetry span
3. Add effect accumulator to planning state
4. Update `TaskDecomposer` to emit effects:
   - Emit `MethodSelected` when method chosen
   - Emit `TaskDecomposed` after decomposition
   - Emit `PrimitiveTaskScheduled` for primitives
5. Update `EffectHandler` to detect effect type (function vs struct)
6. Return effects alongside plan
7. Add integration tests

**Line References:**
- `projects/jido_htn/lib/jido_htn/planner.ex:17` - `plan/3` function
- `projects/jido_htn/lib/jido_htn/planner.ex:34` - `do_plan/5` function
- `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex:28` - `decompose_task/8`
- `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex:219` - Method selection
- `projects/jido_htn/lib/jido_htn/planner/effect_handler.ex:12` - `apply_effects/4`

### Phase 3: Execution & Observability

**Objective:** Add execution-time effects and integrate with telemetry/jido_signal.

**Success Criteria:**
- Task execution emits start/complete/failed effects
- Effects broadcast via jido_signal
- Telemetry handlers attach to events
- End-to-end tests with real domains

**Files to Create:**
1. `projects/jido_htn/lib/jido_htn/planner/effects.ex` - Effect application logic

**Files to Modify:**
1. `projects/jido_htn/lib/jido_htn/primitive_task.ex`
2. `projects/jido_htn/lib/jido_htn/domain.ex`
3. `test/jido_htn/planner/state_simulation_test.exs`

**Tests to Add:**
- Test execution effects are emitted
- Test effects broadcast via jido_signal
- Test telemetry events are fired
- Test effect handlers are called
- Test state simulation with structured effects

**Dependencies:**
- Phase 2 must be complete

**Implementation Steps:**
1. Create `Jido.HTN.Planner.Effects` module
2. Add `emit_effect/2` function for telemetry+jido_signal
3. Add `apply_state_effects/3` for state mutation
4. Update `PrimitiveTask` schema to accept structs OR functions
5. Add `emit_effects?` and `effect_handlers` to Domain
6. Add execution effect hooks:
   - `TaskStarted` before action execution
   - `TaskCompleted` after success
   - `TaskFailed` on error
7. Attach telemetry handlers
8. Write end-to-end tests

**Line References:**
- `projects/jido_htn/lib/jido_htn/primitive_task.ex:41` - Effects schema
- `projects/jido_htn/lib/jido_htn/domain.ex:24` - Domain fields

### Phase 4: Polish & Documentation

**Objective:** Complete documentation, performance optimization, and migration guide.

**Success Criteria:**
- Effect system guide complete
- Telemetry event reference complete
- Migration guide for existing domains
- Performance benchmarks show <10% overhead
- All documentation reviewed

**Files to Create:**
1. `projects/jido_htn/guides/effects.md`
2. `projects/jido_htn/guides/telemetry.md`
3. `projects/jido_htn/guides/migration_guide.md`

**Files to Modify:**
1. `projects/jido_htn/guides/getting-started.md`
2. `projects/jido_htn/lib/jido_htn/planner/effect_handler.ex` - Expand docs

**Tests to Add:**
- Performance benchmarks (planning with/without effects)
- Memory usage tests (effect accumulation)
- Stress tests (large plans with many effects)

**Dependencies:**
- Phase 3 must be complete

**Implementation Steps:**
1. Write effect system guide
2. Write telemetry event reference
3. Write migration guide with before/after examples
4. Update getting-started guide
5. Add performance benchmarks
6. Optimize effect emission (sampling, async emission)
7. Review all documentation
8. Final QA pass

## 6. Quality & Testing Strategy

### Test Categories

**Unit Tests (70% target coverage):**
- Each effect struct's schema validation
- Helper constructor functions
- Telemetry event emission
- Effect application logic
- Metadata field validation

**Integration Tests (20% target coverage):**
- Planner returns effects
- Effects are emitted during planning
- Effect handlers are called
- jido_signal integration
- Telemetry handler attachment

**Property-Based Tests (10% target coverage):**
- Effect metadata validity (plan_id format, timestamp range)
- Effect list ordering
- State effect application idempotence

### Coverage Targets

- **New code:** >95% coverage
- **Modified code:** >90% coverage
- **Overall jido_htn:** Maintain >85% coverage

### Quality Gates

Before marking this item complete:
1. All tests pass (unit, integration, property-based)
2. Coverage thresholds met
3. Performance benchmarks show <10% overhead
4. Documentation complete and reviewed
5. Migration guide tested with sample domain
6. Integration tests with existing Jido agents pass
7. No deprecation warnings in tests
8. Code review approved

## 7. Risk Assessment

### Technical Risks

**Risk:** Effect emission overhead slows down planning
- **Probability:** Medium
- **Impact:** High (planning performance critical)
- **Mitigation:**
  - Make effects opt-in via Domain configuration
  - Use sampling for high-frequency effects
  - Add performance benchmarks to CI
  - Use async emission for non-critical effects

**Risk:** Memory growth from effect accumulation
- **Probability:** Medium
- **Impact:** Medium
- **Mitigation:**
  - Limit effect history size (configurable)
  - Use ETS table for large plans
  - Provide effect streaming API
  - Document memory considerations

**Risk:** Breaking existing domains with function effects
- **Probability:** Low
- **Impact:** High (backward compatibility critical)
- **Mitigation:**
  - Support both functions and structs via Zoi.union()
  - Comprehensive backward compatibility tests
  - Add deprecation warnings, not errors
  - Document migration path clearly

### Dependency Risks

**Risk:** Item 009 (Zoi error handling) not complete
- **Probability:** Medium
- **Impact:** Medium
- **Mitigation:**
  - Use existing Splode patterns for now
  - Can refactor to Zoi errors later
  - Keep error handling consistent with Jido

**Risk:** Item 010 (explode errors) not complete
- **Probability:** Medium
- **Impact:** Low
- **Mitigation:**
  - Use simple error structs for now
  - Can add explode errors later
  - Focus on effect structure, not error details

### Timeline Risks

**Risk:** Integration with jido_signal more complex than expected
- **Probability:** Low
- **Impact:** Medium
- **Mitigation:**
  - Use existing Jido signal patterns
  - Fallback to telemetry-only if needed
  - Phase 3 can be deferred if needed

## 8. Success Criteria

Implementation is complete when:

1. All 10 effect types defined with Zoi schemas
2. Planner emits effects during planning (MethodSelected, TaskDecomposed, etc.)
3. Execution emits effects (TaskStarted, TaskCompleted, TaskFailed)
4. Effects include full metadata (plan_id, timestamps, depth, correlation_id)
5. Telemetry events emitted for all effect types
6. Effects integrate with jido_signal for cross-process communication
7. Backward compatibility maintained (function effects still work)
8. Comprehensive test coverage (>90% for new code)
9. Documentation complete:
   - Effect system guide
   - Telemetry event reference
   - Migration guide
10. Performance impact <10% overhead when effects enabled
11. Integration tests with existing Jido agents pass
12. No breaking changes to existing domains

### Definition of "Done"

This item is done when:
- All 4 implementation phases complete
- All tests passing with >90% coverage
- Documentation reviewed and approved
- Performance benchmarks pass
- Migration guide tested with sample domain
- Code review approved
- Item state updated to "complete"

### Acceptance Testing Approach

1. Create sample domain with function effects (backward compatibility test)
2. Create sample domain with structured effects (new pattern test)
3. Run both domains through same planning scenarios
4. Verify both produce equivalent results
5. Verify new domain emits effects
6. Verify effects appear in telemetry
7. Verify effects broadcast via jido_signal
8. Measure performance overhead
9. Review and approve documentation

## 9. References

### Code References
- `projects/jido/lib/jido/agent/internal.ex` - Internal effects pattern
- `projects/jido/lib/jido/agent/effects.ex` - Effect application pattern
- `projects/jido/lib/jido/telemetry.ex` - Telemetry pattern
- `projects/jido_htn/lib/jido_htn/planner/effect_handler.ex` - Current HTN effects
- `projects/jido_htn/lib/jido_htn/primitive_task.ex:41` - Effects schema

### Documentation References
- Zoi Documentation: https://hexdocs.pm/zoi
- Jido Agent Guides: `projects/jido/guides/agents.md`
- Telemetry Docs: https://hexdocs.pm/telemetry
- Research document: `.roadmap/.../012/research.md`

### Related Items
- **009-convert-to-zoi-error-handling** - Prerequisite for error patterns
- **010-implement-explode-errors** - Related for error details
- **005-define-effects-for-behavior-tree-executi** - Align with BT effects
- **013-define-signals-for-multi-agent-coordinat** - Signal system integration

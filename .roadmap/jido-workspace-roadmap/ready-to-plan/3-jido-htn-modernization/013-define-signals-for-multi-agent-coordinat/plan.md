# Implementation Plan: Define Signals for Multi-Agent Coordination

**Item ID:** 013-define-signals-for-multi-agent-coordinat
**Date:** 2026-01-07
**Status:** Planned
**Estimated Effort:** 6-9 days

## 1. Executive Summary

This implementation introduces a comprehensive signal system for Jido's HTN (Hierarchical Task Network) planner to enable multi-agent coordination and higher-level orchestration. The signal system exposes meaningful planning events (plan lifecycle, task processing, method selection, error conditions, and coordination primitives) so that other agents, supervisors, and orchestrators can observe, coordinate, and adjust behavior in real-time.

**Key Architectural Decisions:**
- Signals follow CloudEvents v1.0.2 specification (consistent with Jido ecosystem)
- Signal emission is opt-in via Domain configuration to avoid performance overhead
- Signals are named using the convention `<domain>.<entity>.<action>[.<qualifier>]`
- Signals are emitted asynchronously to avoid blocking planner execution
- Signals include structured payloads with plan_id for correlation
- Signal priorities align with Jido's routing system (50-100 for coordination, -50 to -10 for task-level)
- Backward compatibility maintained - existing HTN domains work without changes

**Expected Timeline:** 6-9 days total (4 implementation phases)

## 2. Impact Analysis Summary

### Key Findings from Research

The HTN planner currently **operates silently** - no signal/event infrastructure exists. This means:
1. **No observability** - External systems cannot monitor planning operations
2. **No coordination** - Agents cannot coordinate based on planning state
3. **No debugging** - No external debugging or monitoring capabilities
4. **No collaboration** - Multi-agent scenarios cannot synchronize on HTN events

However, the **Jido ecosystem has robust signal infrastructure** ready to use:
- `Jido.Signal` - CloudEvents v1.0.2 compliant signals
- `JidoSignal.Bus` - Message bus with pub/sub, persistence, and middleware
- `JidoSignal.Router` - Pattern-based signal routing with priorities
- `AgentServer.SignalRouter` - Multi-agent signal coordination

### Files Requiring Changes

**New Files (4):**
1. `projects/jido_htn/lib/jido_htn/signals.ex` - Signal type definitions and constructors
2. `projects/jido_htn/lib/jido_htn/signals/emitter.ex` - Signal emission logic
3. `projects/jido_htn/lib/jido_htn/planner/signals.ex` - Signal hooks for planner integration
4. `projects/jido_htn/lib/jido_htn/signals/priority.ex` - Signal priority constants

**Modified Files (6):**
1. `projects/jido_htn/lib/jido_htn/planner.ex:37` - Emit `htn.plan.starting` at do_plan/5 entry
2. `projects/jido_htn/lib/jido_htn/planner.ex:131-141` - Emit `htn.plan.created` on success
3. `projects/jido_htn/lib/jido_htn/planner.ex:143-150` - Emit `htn.plan.failed` on error
4. `projects/jido_htn/lib/jido_htn/planner.ex:181` - Emit `htn.recursion.limit` on max depth
5. `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex:55` - Emit `htn.task.failed` for unknown tasks
6. `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex:90-163` - Emit method selection/decomposition signals

**Test Files (3 new, 2 updated):**
1. `test/jido_htn/signals_test.exs` (new) - Signal schema validation tests
2. `test/jido_htn/signals/emitter_test.exs` (new) - Emission logic tests
3. `test/jido_htn/signals/integration_test.exs` (new) - End-to-end signal tests
4. `test/jido_htn/planner_test.exs` (update) - Assert signals are emitted
5. `test/jido_htn/planner/decomposition_test.exs` (update) - Verify decomposition signals

**Configuration Files (2):**
1. `projects/jido_htn/mix.exs` - Add `jido_signal` dependency
2. `projects/jido_htn/lib/jido_htn/domain.ex` - Add signal configuration to Domain schema

### Existing Patterns to Follow

**Jido.Signal Pattern** (`projects/jido/lib/jido/signal.ex`):
- CloudEvents v1.0.2 compliance
- Standardized data attribute structure
- Type field naming convention: `<domain>.<entity>.<action>[.<qualifier>]`

**JidoSignal.Bus Pattern** (`projects/jido_signal/lib/jido_signal/bus.ex`):
- Pub/sub broadcasting with topics
- Async signal dispatch
- Middleware for cross-cutting concerns

**JidoSignal.Router Pattern** (`projects/jido_signal/lib/jido_signal/router.ex`):
- Pattern-based signal routing with priorities
- Support for wildcard subscriptions
- Priority-based signal ordering

**AgentServer.SignalRouter Pattern** (`projects/jido/lib/jido/agent_server/signal_router.ex`):
- Multi-agent signal coordination
- Parent-child signal delegation
- Cross-process signal routing

### Integration Points Identified

1. **jido_signal** - Primary signal bus infrastructure (add as dependency)
2. **Jido.Signal** - Base signal schemas and CloudEvents compliance
3. **JidoSignal.Bus** - Broadcasting signals to subscribers
4. **AgentServer** - Multi-agent coordination scenarios
5. **Telemetry** - Optional telemetry integration for metrics

## 3. Feature Specification

### User Stories

**As a multi-agent system architect**, I want HTN signals to integrate with jido_signal so agents can coordinate on planning events.

*Acceptance Criteria:*
- Planning lifecycle signals (plan.created, plan.failed) broadcast to signal bus
- Signals include plan_id for correlation
- Can subscribe to HTN signals from other agents
- Signals follow CloudEvents v1.0.2 specification
- Signal emission is opt-in to avoid performance overhead

**As a supervisor agent**, I want to observe HTN task execution so I can detect and respond to failures.

*Acceptance Criteria:*
- Task lifecycle signals (task.started, task.completed, task.failed) are emitted
- Signals include task_name, result/error details
- Can set up signal handlers to respond to failures
- Signals include timestamps for performance tracking

**As a resource manager**, I want to receive HTN resource signals so I can coordinate shared resource allocation.

*Acceptance Criteria:*
- Resource signals (resource.requested, resource.acquired, resource.released) emitted
- Signals include resource_type, requesting_agent, purpose
- Can implement resource allocation policies based on signals
- Resource constraint violations broadcast as signals

**As a domain author**, I want backward compatibility so my existing domains continue to work without modification.

*Acceptance Criteria:*
- Signal emission disabled by default
- Existing domains work without changes
- Can enable signals via Domain configuration
- Clear documentation on opt-in process

### API Contracts

#### Signal Constructor Pattern

All signals follow this constructor pattern:
```elixir
defmodule Jido.HTN.Signals.PlanCreated do
  @moduledoc "Emitted when an HTN plan is successfully generated."

  @type t :: %__MODULE__{
    type: String.t(),
    source: String.t(),
    id: String.t(),
    data: map(),
    time: integer()
  }

  defstruct [
    :type,
    :source,
    :id,
    :data,
    :time
  ]

  @doc "Creates a PlanCreated signal."
  def new(plan_id, domain, plan, final_state, mtr) do
    %__MODULE__{
      type: "htn.plan.created",
      source: "jido_htn",
      id: plan_id,
      data: %{
        plan_id: plan_id,
        domain: domain,
        plan: plan,
        final_state: final_state,
        mtr: mtr,
        timestamp: System.system_time(:microsecond)
      },
      time: System.system_time(:microsecond)
    }
  end
end
```

#### Planner API Changes

**Before (no changes - backward compatible):**
```elixir
{:ok, plan} = Jido.HTN.Planner.plan(domain, initial_task, world_state)
```

**After (signals enabled via Domain config):**
```elixir
# Same API, but signals are emitted if configured
{:ok, plan} = Jido.HTN.Planner.plan(domain, initial_task, world_state)
# Signals emitted asynchronously during planning
```

#### Domain Configuration

```elixir
defmodule MyDomain do
  use Jido.HTN.Domain

  domain do
    # Existing fields
    name "my_domain"
    version "1.0.0"

    # New signal configuration
    emit_signals? true
    signal_bus JidoSignal.Bus
    signal_priority %{
      "htn.plan.**" => 75,
      "htn.resource.**" => 50,
      "htn.task.**" => -25
    }
  end
end
```

#### Signal Subscription Example

```elixir
# Subscribe to all HTN planning signals
JidoSignal.Bus.subscribe("htn.plan.**")

# Subscribe to resource signals for coordination
JidoSignal.Bus.subscribe("htn.resource.**")

# Handle signals in a process
handle_info({:signal, %Jido.HTN.Signals.PlanCreated{} = signal}, state) do
  # Respond to plan creation
  {:noreply, state}
end
```

### Data Flow

```
1. Planning starts
   ↓
2. Planner checks Domain for emit_signals? flag
   ↓
3. If enabled, generate plan_id (UUID v4)
   ↓
4. Emit htn.plan.starting signal
   ↓
5. TaskDecomposer processes tasks
   ↓
6. Emit signals at each step:
   - htn.task.starting (when task processing begins)
   - htn.method.evaluating (evaluating method conditions)
   - htn.method.selected (method chosen)
   - htn.task.decomposed (compound task decomposed)
   - htn.task.completed (task completed successfully)
   ↓
7. On planning success, emit htn.plan.created
   ↓
8. On planning failure, emit htn.plan.failed
   ↓
9. Return {:ok, plan} or {:error, reason}
```

### State Management Requirements

**Signal Metadata:**
- `plan_id` - UUID v4 generated at planning start (for correlation)
- `timestamp` - System.system_time(:microsecond)
- `source` - "jido_htn" (identifies signal source)
- `type` - Signal type (e.g., "htn.plan.created")

**Signal Bus State:**
- Signals broadcast asynchronously (no blocking)
- Subscribers receive signals in their mailbox
- Signal history optional (via jido_signal persistence)

### Error Handling Approach

**Signal Emission Failures:**
- Signal emission failures should NOT crash the planner
- Log errors but continue planning
- Use try/rescue around emission calls
- Provide telemetry for emission failures

**Invalid Signal Payloads:**
- Validate signal data before emission
- Use Zoi schemas for validation
- Skip emission if validation fails (log error)
- Provide clear error messages for debugging

**Bus Unavailable:**
- Gracefully degrade if signal bus not started
- Log warning but continue planning
- Provide configuration option to fail fast if desired

## 4. Technical Design

### Data Model Changes

#### Signal Type Hierarchy

```
Jido.HTN.Signals (module)
├── Planning Lifecycle
│   ├── PlanStarting
│   ├── PlanCreated
│   ├── PlanFailed
│   └── PlanTimeout
├── Task Processing
│   ├── TaskStarting
│   ├── TaskCompleted
│   ├── TaskFailed
│   └── TaskDecomposed
├── Method Selection
│   ├── MethodEvaluating
│   ├── MethodSelected
│   ├── MethodPreconditionFailed
│   └── MethodFailed
├── Error and Dead-ends
│   ├── DeadEndReached
│   ├── ReplanRequired
│   └── RecursionLimit
└── Multi-Agent Coordination
    ├── AgentDelegating
    ├── AgentAssigned
    ├── ResourceRequested
    ├── ResourceAcquired
    ├── ResourceReleased
    └── ConstraintViolation
```

#### Signal Data Payloads

All signals include:
```elixir
%{
  plan_id: String.t(),           # UUID v4 for correlation
  timestamp: integer(),           # Unix microseconds
  domain: String.t() | nil        # Optional domain name
}
```

Planning signals add:
```elixir
%{
  root_tasks: list(),             # Initial tasks
  world_state: map(),             # Initial state
  final_state: map() | nil,       # Final state (created)
  reason: term() | nil,           # Failure reason (failed)
  mtr: list() | nil               # Method traversal record
}
```

Task signals add:
```elixir
%{
  task_name: String.t(),
  result: term() | nil,           # Task result (completed)
  error: term() | nil,            # Error details (failed)
  new_state: map() | nil          # Updated state
}
```

Method signals add:
```elixir
%{
  task_name: String.t(),
  method_name: String.t(),
  priority: integer() | nil,      # Method priority
  condition: term() | nil         # Precondition that failed
}
```

Coordination signals add:
```elixir
%{
  target_agent: String.t() | nil,     # For delegation
  assigned_by: String.t() | nil,       # For assignment
  resource_type: String.t() | nil,     # For resource signals
  requested_by: String.t() | nil,      # For resource signals
  purpose: String.t() | nil,           # For resource requests
  constraint: String.t() | nil,        # For constraint violations
  violated_by: String.t() | nil,       # For constraint violations
  severity: atom() | nil               # For constraint violations
}
```

### Module Organization

```
projects/jido_htn/lib/jido_htn/
├── signals.ex                       # NEW: Signal type definitions
│   ├── PlanStarting
│   ├── PlanCreated
│   ├── PlanFailed
│   ├── PlanTimeout
│   ├── TaskStarting
│   ├── TaskCompleted
│   ├── TaskFailed
│   ├── TaskDecomposed
│   ├── MethodEvaluating
│   ├── MethodSelected
│   ├── MethodPreconditionFailed
│   ├── MethodFailed
│   ├── DeadEndReached
│   ├── ReplanRequired
│   ├── RecursionLimit
│   ├── AgentDelegating
│   ├── AgentAssigned
│   ├── ResourceRequested
│   ├── ResourceAcquired
│   ├── ResourceReleased
│   └── ConstraintViolation
├── signals/
│   ├── emitter.ex                   # NEW: Signal emission logic
│   │   ├── emit_signal/2
│   │   ├── emit_async/2
│   │   └── should_emit?/1
│   ├── priority.ex                  # NEW: Signal priority constants
│   │   ├── coordination_priority/0
│   │   ├── agent_priority/0
│   │   └── task_priority/0
│   └── coordinator.ex               # NEW: Multi-agent coordination helpers
│       ├── delegate_task/3
│       ├── request_resource/3
│       └── notify_constraint_violation/3
├── planner/
│   ├── signals.ex                   # NEW: Signal hooks for planner
│   │   ├── emit_plan_starting/1
│   │   ├── emit_plan_created/2
│   │   ├── emit_plan_failed/2
│   │   └── emit_recursion_limit/2
│   ├── planner.ex                   # MODIFY: Add signal emission
│   └── task_decomposer.ex           # MODIFY: Add task/method signals
└── domain.ex                         # MODIFY: Add signal configuration
```

### Third-Party Integration

#### jido_signal (add as dependency)

```elixir
# mix.exs
defp deps do
  [
    {:jido_signal, "~> 0.1"}
  ]
end
```

Signal emission:
```elixir
# Emit signal to bus
JidoSignal.Bus.broadcast(
  "htn.plan.created",
  Jido.HTN.Signals.PlanCreated.new(plan_id, domain, plan, final_state, mtr)
)
```

Subscription:
```elixir
# Subscribe to signals
JidoSignal.Bus.subscribe("htn.plan.**")

# Handle in process
def handle_info({:signal, signal}, state) do
  # Process signal
  {:noreply, state}
end
```

#### Jido.Signal (existing via jido dependency)

Use CloudEvents-compliant signal schemas:
```elixir
%Jido.Signal{
  type: "htn.plan.created",
  source: "jido_htn",
  id: plan_id,
  data: %{...},
  time: timestamp
}
```

#### Telemetry (optional integration)

```elixir
# Emit telemetry event alongside signal
:telemetry.execute(
  [:jido, :htn, :signal, :emitted],
  %{count: 1},
  %{
    signal_type: "htn.plan.created",
    plan_id: plan_id
  }
)
```

### Configuration/Environment Changes

#### Application Configuration

Add to `config/config.exs`:
```elixir
config :jido_htn,
  # Enable/disable signal emission globally
  emit_signals: false,
  # Signal bus to use
  signal_bus: JidoSignal.Bus,
  # Default signal priorities
  signal_priorities: %{
    "htn.plan.**" => 75,
    "htn.resource.**" => 50,
    "htn.agent.**" => 25,
    "htn.task.**" => -25
  },
  # Async emission settings
  signal_emission_timeout: 5000,
  # Sampling for high-frequency signals (1.0 = all, 0.1 = 10%)
  signal_sample_rate: 1.0
```

#### Domain Configuration

Add to Domain schema:
```elixir
emit_signals?: Zoi.boolean()
  |> Zoi.default(false)
  |> Zoi.description("Emit signals during planning for multi-agent coordination"),

signal_bus: Zoi.module()
  |> Zoi.default(JidoSignal.Bus)
  |> Zoi.description("Signal bus to use for broadcasting signals"),

signal_priorities: Zoi.map()
  |> Zoi.default(%{})
  |> Zoi.description("Override default signal priorities")
```

## 5. Implementation Phases

### Phase 1: Foundation

**Objective:** Create signal type definitions and emitter infrastructure without modifying existing planner behavior.

**Success Criteria:**
- All 18 signal types defined with CloudEvents-compliant schemas
- Signal emitter module with async emission logic
- Signal priority constants defined
- Unit tests for all signal types
- No changes to existing planner code

**Files to Create:**
1. `projects/jido_htn/lib/jido_htn/signals.ex`
2. `projects/jido_htn/lib/jido_htn/signals/emitter.ex`
3. `projects/jido_htn/lib/jido_htn/signals/priority.ex`
4. `test/jido_htn/signals_test.exs`
5. `test/jido_htn/signals/emitter_test.exs`

**Files to Modify:**
1. `projects/jido_htn/mix.exs` - Add jido_signal dependency

**Tests to Add:**
- Test each signal type's constructor
- Test CloudEvents compliance (type, source, id, data, time fields)
- Test signal data payload validation
- Test emitter with mock bus
- Test async emission doesn't block
- Test emission failures are handled gracefully

**Dependencies:**
- None (foundational phase)

**Implementation Steps:**
1. Add `jido_signal ~> 0.1` to mix.exs deps
2. Run `mix deps.get`
3. Create `Jido.HTN.Signals` module with all 18 signal types
4. Each signal type has a `new/` constructor
5. Create `Jido.HTN.Signals.Priority` with priority constants
6. Create `Jido.HTN.Signals.Emitter` with emission logic
7. Implement `emit_signal/2` (synchronous)
8. Implement `emit_async/2` (async with GenServer)
9. Implement `should_emit?/1` (check Domain config)
10. Write unit tests for all signal types
11. Write unit tests for emitter
12. Ensure all tests pass

### Phase 2: Planner Integration

**Objective:** Update planner to emit lifecycle signals at key planning points.

**Success Criteria:**
- Planner emits plan.starting at planning start
- Planner emits plan.created on success
- Planner emits plan.failed on failure
- Planner emits recursion.limit on max depth
- Signals include correct metadata (plan_id, timestamps, etc.)
- Integration tests pass

**Files to Modify:**
1. `projects/jido_htn/lib/jido_htn/planner.ex`
2. `projects/jido_htn/lib/jido_htn/domain.ex`
3. `test/jido_htn/planner_test.exs`

**Files to Create:**
1. `projects/jido_htn/lib/jido_htn/planner/signals.ex`

**Tests to Add:**
- Test planner emits plan.starting signal
- Test planner emits plan.created signal with correct data
- Test planner emits plan.failed signal with error details
- Test planner emits recursion.limit signal
- Test signals include plan_id for correlation
- Test signals NOT emitted when emit_signals? is false
- Test backward compatibility (existing domains work)

**Dependencies:**
- Phase 1 must be complete

**Implementation Steps:**
1. Add `emit_signals?`, `signal_bus`, `signal_priorities` to Domain schema
2. Create `Jido.HTN.Planner.Signals` module with hook functions
3. Implement `emit_plan_starting/1` hook
4. Implement `emit_plan_created/2` hook
5. Implement `emit_plan_failed/2` hook
6. Implement `emit_recursion_limit/2` hook
7. Update `Planner.plan/3` to generate plan_id if signals enabled
8. Add signal emission to `do_plan/5` at line 37 (plan.starting)
9. Add signal emission at line 131-141 (plan.created)
10. Add signal emission at line 143-150 (plan.failed)
11. Add signal emission at line 181 (recursion.limit)
12. Add integration tests
13. Ensure all tests pass

**Line References:**
- `projects/jido_htn/lib/jido_htn/planner.ex:17` - `plan/3` function
- `projects/jido_htn/lib/jido_htn/planner.ex:37` - `do_plan/5` function
- `projects/jido_htn/lib/jido_htn/planner.ex:131-141` - Success path
- `projects/jido_htn/lib/jido_htn/planner.ex:143-150` - Failure path
- `projects/jido_htn/lib/jido_htn/planner.ex:181` - Recursion limit check
- `projects/jido_htn/lib/jido_htn/domain.ex:24` - Domain fields

### Phase 3: Task Decomposition Signals

**Objective:** Add task and method signals to task decomposer for detailed planning visibility.

**Success Criteria:**
- TaskDecomposer emits task.starting/completed/failed signals
- TaskDecomposer emits method.evaluating/selected/failed signals
- TaskDecomposer emits task.decomposed signal
- Signals include correct task_name, method_name, etc.
- Integration tests pass

**Files to Modify:**
1. `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex`
2. `test/jido_htn/planner/decomposition_test.exs`

**Tests to Add:**
- Test task.starting signal emitted
- Test task.completed signal emitted with result
- Test task.failed signal emitted with error
- Test method.evaluating signal emitted
- Test method.selected signal emitted
- Test method.precondition_failed signal emitted
- Test method.failed signal emitted
- Test task.decomposed signal emitted
- Test signals include correct task/method names
- Test signals NOT emitted when emit_signals? is false

**Dependencies:**
- Phase 2 must be complete

**Implementation Steps:**
1. Add signal emission to `decompose_task/8` at line 55 (task.failed for unknown)
2. Add signal emission at line 90-93 (method.precondition_failed)
3. Add signal emission at line 106-165 (method.evaluating for each candidate)
4. Add signal emission at line 141-147 (task.completed on success)
5. Add signal emission at line 157-163 (method.failed on failure)
6. Add signal emission for task.decomposed after decomposition
7. Add integration tests for all signals
8. Ensure all tests pass

**Line References:**
- `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex:28` - `decompose_task/8`
- `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex:55` - Unknown task
- `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex:90-93` - Precondition check
- `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex:106-165` - Method selection
- `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex:141-147` - Success path
- `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex:157-163` - Failure path

### Phase 4: Coordination & Documentation

**Objective:** Add multi-agent coordination signals and complete documentation.

**Success Criteria:**
- Coordination signals (delegation, resources, constraints) defined
- Coordination helper module created
- Multi-agent examples documented
- Signal system guide complete
- Signal reference documentation complete
- All documentation reviewed

**Files to Create:**
1. `projects/jido_htn/lib/jido_htn/signals/coordinator.ex`
2. `projects/jido_htn/guides/signals.md`
3. `projects/jido_htn/guides/multi_agent_coordination.md`
4. `projects/jido_htn/examples/multi_agent_example.exs`

**Files to Modify:**
1. `projects/jido_htn/lib/jido_htn/signals.ex` - Add coordination signals
2. `projects/jido_htn/guides/getting-started.md` - Mention signals
3. `projects/jido_htn/README.md` - Add signals section

**Tests to Add:**
- Test coordinator helper functions
- Test multi-agent example scenarios
- Test resource coordination signals
- Test delegation signals
- Test constraint violation signals

**Dependencies:**
- Phase 3 must be complete

**Implementation Steps:**
1. Add coordination signals to signals.ex (agent.*, resource.*, constraint.*)
2. Create `Jido.HTN.Signals.Coordinator` module
3. Implement `delegate_task/3` helper
4. Implement `request_resource/3` helper
5. Implement `notify_constraint_violation/3` helper
6. Create multi-agent example showing coordination
7. Write signal system guide
8. Write multi-agent coordination guide
9. Write signal reference documentation
10. Update getting-started guide
11. Update README with signals section
12. Review all documentation
13. Final QA pass

## 6. Quality & Testing Strategy

### Test Categories

**Unit Tests (70% target coverage):**
- Each signal type's constructor
- Signal data payload validation
- CloudEvents compliance
- Emitter logic (sync and async)
- Priority constants
- Coordinator helper functions

**Integration Tests (20% target coverage):**
- Planner emits lifecycle signals
- TaskDecomposer emits task/method signals
- Signals broadcast via jido_signal
- Signal subscription and handling
- Domain configuration (emit_signals? flag)
- Backward compatibility

**Property-Based Tests (10% target coverage):**
- Signal ID format (valid UUID)
- Timestamp monotonicity
- Signal data validity
- Priority range constraints

### Coverage Targets

- **New code:** >95% coverage
- **Modified code:** >90% coverage
- **Overall jido_htn:** Maintain >85% coverage

### Quality Gates

Before marking this item complete:
1. All tests pass (unit, integration, property-based)
2. Coverage thresholds met
3. Performance overhead <5% when signals enabled
4. Signal emission failures don't crash planner
5. Documentation complete and reviewed
6. Multi-agent examples tested
7. Backward compatibility verified
8. Code review approved

## 7. Risk Assessment

### Technical Risks

**Risk:** Signal emission overhead slows down planning
- **Probability:** Medium
- **Impact:** High (planning performance critical)
- **Mitigation:**
  - Make signals opt-in via Domain configuration
  - Use async emission to avoid blocking
  - Add sampling for high-frequency signals
  - Add performance benchmarks to CI
  - Document performance considerations

**Risk:** Signal bus unavailable causes failures
- **Probability:** Medium
- **Impact:** Medium
- **Mitigation:**
  - Gracefully degrade if bus not started
  - Log warning but continue planning
  - Provide configuration to fail fast if desired
  - Add health checks for signal bus
  - Document deployment requirements

**Risk:** Signal flood overwhelms subscribers
- **Probability:** Medium
- **Impact:** Medium
- **Mitigation:**
  - Implement sampling for high-frequency signals
  - Batch similar events
  - Provide filtering options
  - Document best practices
  - Create examples of proper subscription patterns

### Dependency Risks

**Risk:** Item 009 (Zoi error handling) not complete
- **Probability:** Low
- **Impact:** Low
- **Mitigation:**
  - Use existing error patterns for now
  - Can refactor to Zoi errors later
  - Keep error handling consistent with Jido

**Risk:** Item 012 (HTN effects) not complete
- **Probability:** Low
- **Impact:** Low
- **Mitigation:**
  - Signals are independent of effects
  - Can work in parallel
  - No hard dependency

### Timeline Risks

**Risk:** Multi-agent coordination scenarios more complex than expected
- **Probability:** Low
- **Impact:** Medium
- **Mitigation:**
  - Start with basic signals first
  - Add coordination helpers in Phase 4
  - Defer complex scenarios if needed
  - Focus on foundation first

## 8. Success Criteria

Implementation is complete when:

1. All 18 signal types defined with CloudEvents-compliant schemas
2. Planner emits lifecycle signals (plan.starting, plan.created, plan.failed)
3. TaskDecomposer emits task signals (task.starting, task.completed, task.failed)
4. TaskDecomposer emits method signals (method.evaluating, method.selected, method.failed)
5. Planner emits error signals (recursion.limit, dead_end.reached)
6. Coordination signals available (agent.*, resource.*, constraint.*)
7. Signals include full metadata (plan_id, timestamps, domain)
8. Signals broadcast via jido_signal
9. Signal emission is opt-in via Domain configuration
10. Backward compatibility maintained (existing domains work)
11. Comprehensive test coverage (>90% for new code)
12. Documentation complete:
    - Signal system guide
    - Multi-agent coordination guide
    - Signal reference
    - Multi-agent examples
13. Performance overhead <5% when signals enabled
14. Integration tests with jido_signal pass
15. No breaking changes to existing domains

### Definition of "Done"

This item is done when:
- All 4 implementation phases complete
- All tests passing with >90% coverage
- Documentation reviewed and approved
- Multi-agent examples tested
- Performance benchmarks pass
- Code review approved
- Item state updated to "complete"

### Acceptance Testing Approach

1. Create domain without signals (backward compatibility test)
2. Create domain with signals enabled
3. Run both domains through same planning scenarios
4. Verify both produce equivalent results
5. Verify signal-enabled domain emits signals
6. Verify signals appear in jido_signal bus
7. Subscribe to signals from test process
8. Verify signal data payloads are correct
9. Verify signal metadata (plan_id, timestamps)
10. Test multi-agent coordination scenario
11. Measure performance overhead
12. Review and approve documentation

## 9. References

### Code References
- `projects/jido/lib/jido/signal.ex` - CloudEvents signal pattern
- `projects/jido_signal/lib/jido_signal/bus.ex` - Signal bus infrastructure
- `projects/jido_signal/lib/jido_signal/router.ex` - Signal routing
- `projects/jido/lib/jido/agent_server/signal_router.ex` - Multi-agent coordination
- `projects/jido_htn/lib/jido_htn/planner.ex:37` - Planning entry point
- `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex:28` - Task decomposition

### Documentation References
- CloudEvents Spec: https://github.com/cloudevents/spec
- Jido Signal Guide: `projects/jido_ai/guides/developer/05_signals.md`
- jido_signal Docs: https://hexdocs.pm/jido_signal
- Research document: `.roadmap/.../013/research.md`

### Related Items
- **012-define-effects-for-htn-planningexecution** - Complementary effects system
- **005-define-effects-for-behavior-tree-executi** - Align with BT signals
- **006-define-signals-for-state-transitionseven** - Align with BT signals

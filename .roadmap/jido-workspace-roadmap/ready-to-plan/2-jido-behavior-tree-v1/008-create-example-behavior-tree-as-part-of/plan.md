# Plan: Behavior Tree as Part of Larger Strategy

## Executive Summary

This implementation creates a comprehensive example demonstrating how behavior trees integrate as components within larger Jido strategy orchestration. The approach builds a meta-strategy framework that coordinates between behavior trees (reactive decisions), HTN planners (complex multi-step sequences), and rule-based validation (constraints). This showcases Jido's composability, signal-based coordination, and blackboard state sharing patterns.

**Key Architectural Decisions:**
- Meta-strategy pattern using phase-based delegation to different planning components
- Signal-based coordination using CloudEvents v1.0.2 specification for state transitions
- Shared blackboard schema for cross-component state management
- Unified error handling via Splode with directive-based error propagation

**Effort Estimate:** Medium complexity (3-4 phases, ~15-20 files)

## Impact Analysis Summary

### Key Research Findings (from research.md)

**Existing Behavior Tree Implementation:**
- Location: `projects/jido_behaviortree/`
- Strategy interface: `Jido.Agent.Strategy.BehaviorTree` implements standard `init/2`, `cmd/3`, `snapshot/2` protocol
- State management: Zoi schemas with `agent.state.__strategy__` namespacing
- Execution model: One tick per `cmd/3` call, bounded and predictable
- Available nodes: Sequence, Selector, Parallel (composites); Inverter, Succeeder, Failer, Repeat (decorators); Action, Wait, Condition, SetBlackboard (leaf)

**Integration Points:**
- **Signals System** (`projects/jido_signal/`): CloudEvents v1.0.2 compliant, used for strategy transitions and error handling
- **Blackboard Pattern**: Shared state storage with type-safe access via Zoi schemas, persistent across ticks
- **HTN** (`projects/jido_htn/`): Hierarchical Task Network planner (currently needs modernization per items 009-014)

### Files Requiring Changes

**New Files to Create:**
```
projects/jido_behaviortree/examples/composite_strategy/
├── README.md
├── example_agent.ex
├── meta_strategy.ex                    # Phase-based coordination layer
├── components/
│   ├── reactive_tree.ex                # Behavior tree for reactive decisions
│   ├── planning_engine.ex              # HTN integration (stub for now)
│   └── rule_validator.ex               # Rule-based constraint checking
├── signals/
│   ├── phase_transition.ex             # Signal for phase changes
│   └── composite_events.ex             # Other composite-specific signals
├── blackboard/
│   └── composite_schema.ex             # Zoi schema for shared state
└── test/
    ├── composite_strategy_test.exs     # Integration tests
    ├── signal_coordination_test.exs    # Signal flow tests
    └── blackboard_test.exs             # State sharing tests
```

**Existing Patterns to Follow:**
- Strategy protocol: `Jido.Agent.Strategy.BehaviorTree` behavior (projects/jido_behaviortree/lib/jido_behaviortree/strategy/behavior_tree.ex:1-238)
- Signal creation: `Jido.Signal.new/3` positional constructor (projects/jido_signal/lib/jido_signal.ex:556-568)
- State schema: Zoi struct patterns with `@schema` module attribute
- Error handling: Splode `ok!/1` pattern for Result types
- Directive composition: Returning lists of directives from `cmd/3`

### Integration Points Identified

1. **Delegation Boundaries**: Meta-strategy's `cmd/3` delegates to component strategies based on `agent.state.phase`
2. **State Sharing**: Blackboard accessible via `Blackboard.get/2` and `Blackboard.put/3` with typed schemas
3. **Signal Coordination**: Signal bus subscriptions for phase transition events
4. **Error Propagation**: Error directives route to meta-strategy error handler

## Feature Specification

### User Stories

**Story 1: Reactive Decision Integration**
As a developer building an autonomous agent, I want the behavior tree to handle reactive decisions (obstacle avoidance, threat response) so that my agent can respond quickly to environmental changes without replanning.

**Acceptance Criteria:**
- Behavior tree component executes one tick per meta-strategy `cmd/3` call when phase is `:reactive`
- Tree nodes can read/write to shared blackboard
- Tree emits signals on state changes (success, failure, running)
- Meta-strategy transitions phase based on tree outcomes

**Story 2: Planning Component Coordination**
As a developer, I want the meta-strategy to delegate to an HTN planner for complex multi-step tasks so that reactive and deliberative reasoning can be coordinated.

**Acceptance Criteria:**
- When phase is `:planning`, meta-strategy delegates to HTN component
- HTN results are written to blackboard for other components
- Planning completion triggers signal for phase transition
- If HTN modernization (items 009-014) is incomplete, use stub/mock

**Story 3: Rule-Based Validation**
As a developer, I want rule-based constraints to be checked before executing actions so that my agent respects safety limits and resource constraints.

**Acceptance Criteria:**
- Rule validator component checks blackboard state against constraints
- Returns error directives if constraints violated
- Can be invoked as separate phase or integrated into other components

**Story 4: Signal-Based Phase Transitions**
As a developer, I want phase transitions to be triggered by signals so that coordination is decoupled and event-driven.

**Acceptance Criteria:**
- Phase transition signals conform to CloudEvents v1.0.2
- Signals carry correlation IDs for tracking
- Meta-strategy subscribes to relevant signal types
- Signal handlers update `agent.state.phase` and emit telemetry

### API Contracts

**Meta-Strategy cmd/3:**
```elixir
@spec cmd(Agent.t(), [Instruction.t()], Context.t()) :: {Agent.t(), [Directive.t()]}
```
- Delegates to component based on `agent.state.phase`
- Returns updated agent with accumulated directives
- Handles errors by returning error directives

**Component Delegation Pattern:**
```elixir
# Each component implements
@spec delegate(Agent.t(), Context.t()) :: {Agent.t(), [Directive.t()], Signal.t() | nil}
```

**Blackboard Schema (CompositeSchema):**
```elixir
@schema %{
  phase: Zoi.atom() |> Zoi.default(:reactive),
  target: Zoi.map() |> Zoi.optional(),
  obstacles: Zoi.list(Zoi.map()) |> Zoi.default([]),
  resources: Zoi.map() |> Zoi.default(%{}),
  plan: Zoi.list(Zoi.map()) |> Zoi.optional(),
  last_error: Zoi.any() |> Zoi.optional()
}
```

### Data Flow

```
User Instructions
       ↓
Meta-Strategy.cmd/3
       ↓
┌──────────────────────────────────────┐
│  Check agent.state.phase             │
│  - :reactive → Behavior Tree        │
│  - :planning → HTN Component        │
│  - :validation → Rule Validator     │
└──────────────────────────────────────┘
       ↓
Component Execution
       ↓
┌──────────────────────────────────────┐
│  Update Blackboard                   │
│  Emit Signals (if needed)            │
│  Accumulate Directives               │
└──────────────────────────────────────┘
       ↓
Return {Agent, Directives}
```

### State Management Requirements

**Agent State Structure:**
```elixir
%Agent{
  state: %{
    __strategy__: %{
      phase: :reactive | :planning | :validation | :done,
      blackboard: CompositeSchema.t(),
      component_states: %{
        reactive_tree: BTState.t(),
        planning_engine: PlanningState.t(),
        rule_validator: ValidatorState.t()
      },
      tick_count: non_neg_integer(),
      correlation_id: String.t()
    }
  }
}
```

**State Transitions:**
- `:reactive` → `:planning` when tree acquires target
- `:planning` → `:reactive` when plan complete
- `:planning` → `:validation` before execution
- Any → `:done` on success/failure completion

### Error Handling Approach

**Error Sources:**
1. Component execution failures (Splode errors)
2. Blackboard validation failures (Zoi errors)
3. Phase transition errors (Signal errors)
4. Timeout/deadline errors

**Error Handling Strategy:**
- Wrap component calls in try/rescue
- Return error directives instead of raising
- Log errors with correlation IDs
- Emit error signals for monitoring
- Provide recovery path via meta-strategy

**Error Directive Pattern:**
```elixir
%Directive.Error{
  error: Error.execution_error("Component failed", %{component: :reactive_tree}),
  context: :composite_strategy
}
```

## Technical Design

### Data Model Changes

**New Zoi Schema - Composite Blackboard:**
```elixir
defmodule Jido.BehaviorTree.Examples.Composite.Blackboard.Schema do
  @moduledoc """
  Shared state schema for composite strategy components.
  """

  @schema Zoi.struct(
    __MODULE__,
    %{
      # Phase management
      phase: Zoi.atom(description: "Current execution phase")
             |> Zoi.default(:reactive)
             |> Zoi.in([:reactive, :planning, :validation, :done]),
      phase_history: Zoi.list(Zoi.atom())
                    |> Zoi.default([])
                    |> Zoi.description("History of phases visited"),

      # Reactive component state
      obstacles: Zoi.list(Zoi.map())
               |> Zoi.default([])
               |> Zoi.description("Detected obstacles to avoid"),
      target_acquired: Zoi.boolean()
                      |> Zoi.default(false)
                      |> Zoi.description("Whether target has been acquired"),
      current_position: Zoi.map(%{x: 0, y: 0})
                      |> Zoi.default(%{x: 0, y: 0})
                      |> Zoi.description("Agent's current position"),

      # Planning component state
      plan: Zoi.list(Zoi.map())
          |> Zoi.optional()
          |> Zoi.description("Generated plan steps"),
      planning_goal: Zoi.map()
                   |> Zoi.optional()
                   |> Zoi.description("Current planning goal"),

      # Validation component state
      constraints: Zoi.list(Zoi.map())
                 |> Zoi.default([])
                 |> Zoi.description("Active constraints"),
      validation_errors: Zoi.list(Zoi.string())
                      |> Zoi.default([])
                      |> Zoi.description("Validation errors"),

      # Metadata
      tick_count: Zoi.integer()
                |> Zoi.default(0)
                |> Zoi.min(0),
      correlation_id: Zoi.string()
                     |> Zoi.description("Correlation ID for tracking"),
      last_error: Zoi.any()
                |> Zoi.optional()
                |> Zoi.description("Last error if any")
    },
    coerce: true
  )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema
end
```

**New Signal Types:**
```elixir
defmodule Jido.BehaviorTree.Examples.Composite.Signals.PhaseTransition do
  use Jido.Signal,
    type: "composite.phase.transition",
    default_source: "/composite/strategy",
    schema: [
      from_phase: [type: :atom, required: true],
      to_phase: [type: :atom, required: true],
      reason: [type: :string, required: false],
      correlation_id: [type: :string, required: true]
    ]
end

defmodule Jido.BehaviorTree.Examples.Composite.Signals.ComponentCompleted do
  use Jido.Signal,
    type: "composite.component.completed",
    default_source: "/composite/strategy",
    schema: [
      component: [type: :atom, required: true],
      status: [type: :atom, required: true],
      result: [type: :map, required: false]
    ]
end
```

### Module Organization

**Meta-Strategy:**
```elixir
defmodule Jido.BehaviorTree.Examples.Composite.MetaStrategy do
  @moduledoc """
  Meta-strategy that coordinates between behavior tree, HTN, and rule-based components.

  ## Phase-Based Delegation

  The meta-strategy delegates to different planning components based on the current phase:

  - `:reactive` - Behavior tree handles real-time decisions
  - `:planning` - HTN generates multi-step plans
  - `:validation` - Rules validate constraints
  - `:done` - Strategy complete

  ## Signal-Based Coordination

  Components emit signals which trigger phase transitions:
  - PhaseTransition signals for explicit phase changes
  - ComponentCompleted signals for component outcomes
  - Error signals for failures

  ## Blackboard Sharing

  All components share state through the blackboard:
  - Obstacle detection (reactive → planning)
  - Plan results (planning → validation)
  - Constraint violations (validation → reactive)
  """
  use Jido.Agent.Strategy

  alias Jido.BehaviorTree.Examples.Composite.{
    Blackboard.Schema,
    Components.{ReactiveTree, PlanningEngine, RuleValidator},
    Signals.{PhaseTransition, ComponentCompleted}
  }

  # Standard strategy callbacks: init/2, cmd/3, snapshot/2
end
```

**Component Interface:**
```elixir
defmodule Jido.BehaviorTree.Examples.Composite.Components.ReactiveTree do
  @moduledoc """
  Behavior tree component for reactive decision-making.

  Handles obstacle avoidance, threat response, and target acquisition.
  Emits signals when phase should transition to planning.
  """
  use Jido.Agent.Strategy

  # Implements standard strategy protocol
  # Delegates to Jido.Agent.Strategy.BehaviorTree internally
end
```

### Third-Party Integration Details

**Dependencies:**
- `jido_behaviortree` (existing) - Core behavior tree execution
- `jido_signal` (existing) - Signal-based coordination
- `jido` (existing) - Agent and strategy abstractions
- `jido_htn` (existing, may need stub) - Hierarchical planning
- `zoi` (existing) - Schema validation
- `splode` (existing) - Error handling

**HTN Integration Strategy:**
Since items 009-014 (HTN modernization) may not be complete, create a stub component:
```elixir
defmodule Jido.BehaviorTree.Examples.Composite.Components.PlanningEngineStub do
  @moduledoc """
  Stub HTN component for demonstration until HTN modernization is complete.

  TODO: Replace with jido_htn integration after items 009-014
  """
  # Implements simple mock planning behavior
end
```

### Configuration/Environment Changes

**Example Agent Configuration:**
```elixir
defmodule Jido.BehaviorTree.Examples.Composite.ExampleAgent do
  use Jido.Agent,
    name: "composite_agent",
    strategy: {Jido.BehaviorTree.Examples.Composite.MetaStrategy,
      initial_phase: :reactive,
      blackboard: %{
        obstacles: [],
        constraints: [
          %{type: :resource_limit, resource: :energy, limit: 100}
        ]
      },
      signal_bus: :composite_signals
    }
end
```

No runtime configuration changes required. Uses existing Jido agent configuration patterns.

## Implementation Phases

### Phase 1: Foundation

**Objective:** Set up project structure, schemas, and signal definitions

**Success Criteria:**
- All module files created with correct structure
- Zoi schemas compile without errors
- Signal types are registered and usable
- Basic agent starts without errors

**Files to Create:**
- `projects/jido_behaviortree/examples/composite_strategy/README.md`
- `projects/jido_behaviortree/examples/composite_strategy/blackboard/composite_schema.ex`
- `projects/jido_behaviortree/examples/composite_strategy/signals/phase_transition.ex`
- `projects/jido_behaviortree/examples/composite_strategy/signals/composite_events.ex`
- `projects/jido_behaviortree/examples/composite_strategy/test/blackboard_test.exs`

**Tests to Add:**
- Schema validation tests (Zoi coercion, defaults)
- Signal creation and serialization tests
- Basic agent startup tests

**Dependencies:** None

**Acceptance Criteria:**
```elixir
# Can create valid blackboard
{:ok, bb} = CompositeSchema.new(%{phase: :reactive})

# Can create signals
{:ok, signal} = PhaseTransition.new(%{
  from_phase: :reactive,
  to_phase: :planning,
  correlation_id: "test-123"
})

# Agent starts without errors
{:ok, agent} = ExampleAgent.new()
```

### Phase 2: Component Implementation

**Objective:** Implement individual strategy components

**Success Criteria:**
- Reactive tree component executes behavior tree
- Planning stub component returns mock plans
- Rule validator component checks constraints
- Each component emits appropriate signals

**Files to Create:**
- `projects/jido_behaviortree/examples/composite_strategy/components/reactive_tree.ex`
- `projects/jido_behaviortree/examples/composite_strategy/components/planning_engine_stub.ex`
- `projects/jido_behaviortree/examples/composite_strategy/components/rule_validator.ex`
- `projects/jido_behaviortree/examples/composite_strategy/test/components_test.exs`

**Tests to Add:**
- Reactive tree tick execution
- Blackboard read/write operations
- Signal emission on state changes
- Rule validation logic

**Dependencies:** Phase 1 complete

**Acceptance Criteria:**
```elixir
# Reactive tree executes
{agent, directives} = ReactiveTree.cmd(agent, [], ctx)
# Returns directives and updates blackboard

# Planning stub generates plan
{agent, directives} = PlanningEngineStub.cmd(agent, [], ctx)
# Plan written to blackboard.plan

# Rule validator checks constraints
{agent, directives} = RuleValidator.cmd(agent, [], ctx)
# Returns error directives if constraints violated
```

### Phase 3: Meta-Strategy Integration

**Objective:** Implement meta-strategy coordination layer

**Success Criteria:**
- Meta-strategy delegates to correct component based on phase
- Phase transitions triggered by signals work correctly
- Blackboard state is consistent across components
- Error handling recovers gracefully

**Files to Create:**
- `projects/jido_behaviortree/examples/composite_strategy/meta_strategy.ex`
- `projects/jido_behaviortree/examples/composite_strategy/example_agent.ex`
- `projects/jido_behaviortree/examples/composite_strategy/test/composite_strategy_test.exs`

**Tests to Add:**
- Full workflow execution (reactive → planning → validation)
- Signal-based phase transitions
- Error propagation and recovery
- Blackboard state consistency

**Dependencies:** Phase 2 complete

**Acceptance Criteria:**
```elixir
# Full workflow executes
agent = ExampleAgent.new()
agent = ExampleAgent.cmd(agent, [:acquire_target])
# Phase transitions: :reactive → :planning → :validation

# Signals are emitted
assert_received %PhaseTransition{from_phase: :reactive, to_phase: :planning}

# Errors handled gracefully
{agent, [%Directive.Error{}]} = ExampleAgent.cmd(agent, [:invalid_command])
```

### Phase 4: Documentation & Polish

**Objective:** Complete documentation and example scenarios

**Success Criteria:**
- README with architecture overview
- Inline documentation complete
- Example scenarios documented
- All tests passing with >90% coverage

**Files to Modify:**
- `projects/jido_behaviortree/examples/composite_strategy/README.md` (complete)
- All module files (ensure @moduledoc complete)
- `projects/jido_behaviortree/README.md` (add example link)

**Tests to Add:**
- Integration tests for real-world scenarios
- Property-based tests for state transitions
- Performance benchmarks (optional)

**Dependencies:** Phase 3 complete

**Acceptance Criteria:**
```bash
# All tests pass
mix test

# Coverage report
mix test.coverage
# >90% coverage for new modules

# Documentation builds
mix docs
```

## Quality & Testing Strategy

### Test Categories

**1. Unit Tests**
- Schema validation (Zoi coercion, defaults, constraints)
- Signal creation and serialization
- Individual component execution
- Blackboard operations

**2. Integration Tests**
- Component coordination through meta-strategy
- Signal-based phase transitions
- State sharing across components
- Error propagation flow

**3. Property-Based Tests**
- State transition consistency
- Blackboard schema invariants
- Signal ordering guarantees

**4. Documentation Tests**
- Doctests for all public APIs
- Example scenarios in README
- Interactive examples (IEx session)

### Coverage Targets

- **New modules:** >90% line coverage
- **Critical paths:** 100% coverage (phase transitions, error handling)
- **Documentation:** 100% public function documentation

### Quality Gates

**Before Phase Completion:**
1. All tests pass
2. Coverage threshold met
3. No compiler warnings
4. Documentation complete
5. Code review approved

**Before Full Completion:**
1. All phases complete
2. Integration tests pass
3. Documentation reviewed
4. Example scenarios validated
5. Performance acceptable (if applicable)

## Risk Assessment

### Technical Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| HTN modernization incomplete | High | High | Create stub component; document TODO |
| Signal ordering issues | Medium | Medium | Use correlation IDs; idempotent handlers |
| Blackboard schema conflicts | Medium | Low | Strict Zoi validation; clear documentation |
| Component deadlock | Low | Low | Timeout per phase; max tick limits |
| Performance degradation | Low | Low | Profile early; optimize hot paths |

### Dependency Risks

| Dependency | Risk | Mitigation |
|------------|------|------------|
| Items 005-006 (effects/signals) | May not be complete | Use existing signal patterns; adapt if needed |
| Item 007 (single BT example) | Should be reference | Review implementation patterns |
| Items 009-014 (HTN) | Likely incomplete | Stub implementation planned |
| Zoi schema changes | API may evolve | Pin version; follow changelog |

### Timeline Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope creep | Medium | Phase-based approach with clear boundaries |
| Integration complexity | Medium | Incremental integration per phase |
| Documentation burden | Low | Document as we go; doctest-driven |

## Success Criteria

### Measurable Outcomes

**Functional Requirements:**
- [ ] Meta-strategy executes composite workflows (reactive → planning → validation)
- [ ] Components share state via blackboard without conflicts
- [ ] Signals trigger phase transitions reliably
- [ ] Errors propagate and are handled gracefully
- [ ] Example agent demonstrates full workflow

**Quality Requirements:**
- [ ] >90% test coverage for new code
- [ ] 100% public API documentation
- [ ] Zero compiler warnings
- [ ] All tests passing in CI

**Documentation Requirements:**
- [ ] README with architecture overview
- [ ] Inline module documentation
- [ ] Example scenarios with code
- [ ] Integration guide for adding components

### Definition of "Done"

1. All implementation phases complete
2. All tests passing (unit, integration, doctests)
3. Coverage threshold met (>90%)
4. Documentation complete and reviewed
5. Example agent runnable in IEx
6. Code reviewed and approved
7. Roadmap item marked "planned"

### Acceptance Testing Approach

**Scenario 1: Obstacle Avoidance Workflow**
```elixir
# Setup
agent = ExampleAgent.new()

# Reactive phase: Detect obstacle
agent = ExampleAgent.cmd(agent, [:detect_obstacle, %{position: {10, 10}}])
assert agent.state.__strategy__.blackboard.obstacles == [%{position: {10, 10}}]

# Transition to planning
assert_received %PhaseTransition{from_phase: :reactive, to_phase: :planning}

# Planning phase: Generate avoidance plan
agent = ExampleAgent.cmd(agent, [:plan_avoidance])
assert agent.state.__strategy__.blackboard.plan != nil

# Validation phase: Check constraints
agent = ExampleAgent.cmd(agent, [:validate_plan])
assert agent.state.__strategy__.phase == :reactive  # Back to reactive
```

**Scenario 2: Error Recovery**
```elixir
# Setup
agent = ExampleAgent.new()

# Trigger error
{agent, [%Directive.Error{}]} = ExampleAgent.cmd(agent, [:invalid_command])

# Verify recovery
assert agent.state.__strategy__.blackboard.last_error != nil
# Meta-strategy should recover and continue
```

**Scenario 3: Signal-Based Coordination**
```elixir
# Subscribe to signals
Jido.Signal.Bus.subscribe(:composite_signals, "composite.*")

# Execute workflow
agent = ExampleAgent.new() |> ExampleAgent.cmd([:run_full_workflow])

# Verify signals
assert_received %PhaseTransition{from_phase: :reactive, to_phase: :planning}
assert_received %ComponentCompleted{component: :planning_engine, status: :success}
assert_received %PhaseTransition{from_phase: :planning, to_phase: :validation}
```

## Next Steps

1. **Complete Prerequisites:** Ensure items 005, 006, 007 are implemented
2. **Begin Phase 1:** Create project structure and schemas
3. **Iterate:** Complete phases 2-3 incrementally
4. **Document:** Update documentation throughout implementation
5. **Validate:** Run acceptance tests before marking complete

## References

- Behavior Tree Strategy: `projects/jido_behaviortree/lib/jido_behaviortree/strategy/behavior_tree.ex`
- Signal System: `projects/jido_signal/lib/jido_signal.ex`
- HTN (for reference): `projects/jido_htn/`
- Jido Agent: `projects/jido/lib/jido/agent.ex`
- Research findings: `.roadmap/.../008-create-example-behavior-tree-as-part-of/research.md`

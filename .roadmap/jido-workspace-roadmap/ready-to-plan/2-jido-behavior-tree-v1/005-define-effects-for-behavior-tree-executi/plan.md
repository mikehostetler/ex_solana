# Implementation Plan: Define Effects for Behavior Tree Execution

**Item ID**: 005
**State**: Planned
**Date**: 2025-01-07

---

## 1. Executive Summary

This implementation defines a first-class set of Jido effects for behavior tree execution, following the established pattern of **Internal Effects** (state mutations within strategies) and **Directives** (external effects for the runtime). The design introduces behavior-tree-specific effects that cleanly separate pure decision logic from IO, making behavior tree execution observable, testable, and composable.

**Key Architectural Decisions:**
- Follow the existing Internal/Directive separation pattern from `Jido.Agent`
- Create behavior-tree-specific Internal effects for strategy state updates
- Leverage existing `Directive.Emit` for signal dispatch
- Integrate with existing telemetry infrastructure at `projects/jido/lib/jido/telemetry.ex`

**Effort Estimate:** Medium complexity - involves creating new effect modules and updating integration points

---

## 2. Impact Analysis Summary

### Key Findings from Research

The research identified that:

1. **Jido already has a well-established effect system** with Internal effects and Directives
2. **The behavior tree strategy exists** at `projects/jido_behaviortree/lib/jido_behaviortree/strategy/behavior_tree.ex`
3. **The Tick struct already has directive accumulation** - we need to use it
4. **Action nodes already handle effects** - we need to extend the pattern
5. **Telemetry infrastructure exists** - we should emit consistent events

### Files Requiring Changes

**New Files to Create:**
- `projects/jido_behaviortree/lib/jido_behaviortree/internal.ex` - BT-specific Internal effects
- `projects/jido_behaviortree/lib/jido_behaviortree/signals.ex` - Signal type definitions
- `projects/jido_behaviortree/lib/jido_behaviortree/effects.ex` - Effect application helpers

**Files to Modify:**
- `projects/jido_behaviortree/lib/jido_behaviortree/strategy/behavior_tree.ex` - Integrate effect handling
- `projects/jido_behaviortree/lib/jido_behaviortree/tick.ex` - Add effect emission helpers
- `projects/jido_behaviortree/lib/jido_behaviortree/nodes/action.ex` - Ensure effect consistency
- `projects/jido_behaviortree/lib/jido_behaviortree/telemetry.ex` - Add new telemetry events

### Existing Patterns to Follow

1. **Zoi Schema Pattern** - All effects use `Zoi.struct()` for type-safe schemas
2. **Directive Pattern** - Bare structs with `@schema` module attribute
3. **Signal Naming** - Use `jido.bt.*` prefix for behavior tree signals
4. **Telemetry Events** - Follow `[:jido, :bt, ...]` event naming

### Integration Points Identified

1. **Strategy State Storage** - `agent.state.__strategy__.bt` for BT-specific state
2. **Tick Directive Accumulation** - Use `tick.directives` for accumulated directives
3. **Action Node Effects** - Ensure consistency with existing action effect handling
4. **Jido.Agent.Effects** - Central effect application at `projects/jido/lib/jido/agent/effects.ex`

---

## 3. Feature Specification

### User Stories

**US1: Node Tick Observability**
As a developer debugging behavior tree execution, I want signals emitted for each node tick, so that I can trace execution flow and identify bottlenecks.

**Acceptance Criteria:**
- `NodeTickEffect` signal emitted on node tick start
- `NodeTickEffect` signal emitted on node tick completion with status
- Signals include node ID, tree ID, tick ID, and status

**US2: Blackboard Operation Tracking**
As a developer testing behavior trees, I want blackboard read/write operations tracked via effects, so that I can verify state mutations.

**Acceptance Criteria:**
- `BlackboardReadEffect` emitted for blackboard reads
- `BlackboardWriteEffect` emitted for blackboard writes
- Effects include key path, value, and node context

**US3: Tree Lifecycle Events**
As a system operator, I want to receive signals when behavior trees complete or fail, so that I can trigger downstream workflows.

**Acceptance Criteria:**
- `TreeCompletedEffect` signal emitted on tree completion
- Signal includes final status, tick count, and duration
- Signal dispatched via configured adapters

**US4: Error Handling**
As a developer, I want node errors to be surfaced as effects, so that error handling is consistent across the Jido ecosystem.

**Acceptance Criteria:**
- `NodeErrorEffect` Internal effect on node errors
- Error includes node ID, error reason, and stack trace
- Error can be caught and handled by parent nodes

### API Contracts

```elixir
# Internal Effects (Strategy State Mutations)
%Jido.BehaviorTree.Internal.SetNodeStatus{
  node_id: "selector_001",
  status: :success
}

%Jido.BehaviorTree.Internal.UpdateBlackboard{
  path: [:user, :location],
  value: "home"
}

%Jido.BehaviorTree.Internal.SetTreeStatus{
  status: :running
}

# Signal Types (for Directive.Emit)
%Jido.BehaviorTree.Signal.NodeTickStarted{
  tree_id: "bt_001",
  node_id: "selector_001",
  tick_id: "tick_123",
  timestamp: ~U[2025-01-07 12:00:00Z]
}

%Jido.BehaviorTree.Signal.NodeTickCompleted{
  tree_id: "bt_001",
  node_id: "selector_001",
  tick_id: "tick_123",
  status: :success,
  duration_ms: 5
}

%Jido.BehaviorTree.Signal.TreeCompleted{
  tree_id: "bt_001",
  status: :success,
  tick_count: 10,
  duration_ms: 150
}
```

### Data Flow

```
Node Tick
  ↓
Emit telemetry event (existing)
  ↓
Emit Internal.SetNodeStatus (new)
  ↓
Update agent.state.__strategy__.bt
  ↓
Emit Directive.Emit with Signal (new)
  ↓
Accumulate to tick.directives
  ↓
Runtime dispatches signal via adapters
```

### State Management Requirements

**Strategy State Structure:**
```elixir
agent.state.__strategy__.bt = %{
  tree_id: "bt_001",
  status: :running,
  tick_count: 10,
  current_node: "selector_001",
  node_status: %{
    "selector_001" => :running,
    "action_001" => :success
  },
  last_tick_id: "tick_123"
}
```

### Error Handling Approach

1. **Node Errors** - Wrap in `Jido.Error`, emit `NodeErrorEffect` Internal effect
2. **Signal Dispatch Failures** - Log and continue (non-blocking)
3. **Blackboard Access Errors** - Raise and let node handle
4. **Telemetry Attachment Failures** - Log warning, continue execution

---

## 4. Technical Design

### Data Model Changes

**New Internal Effects (Zoi Schemas):**

```elixir
# In projects/jido_behaviortree/lib/jido_behaviortree/internal.ex

defmodule Jido.BehaviorTree.Internal.SetNodeStatus do
  @schema Zoi.struct(
    __MODULE__,
    %{
      node_id: Zoi.string(description: "Node identifier"),
      status: Zoi.atom(description: "Node status (:success, :failure, :running)")
        |> Zoi.in([:success, :failure, :running])
    },
    coerce: true
  )
end

defmodule Jido.BehaviorTree.Internal.UpdateBlackboard do
  @schema Zoi.struct(
    __MODULE__,
    %{
      path: Zoi.list(Zoi.atom(), description: "Path to update"),
      value: Zoi.any(description: "Value to set")
    },
    coerce: true
  )
end

defmodule Jido.BehaviorTree.Internal.SetTreeStatus do
  @schema Zoi.struct(
    __MODULE__,
    %{
      status: Zoi.atom(description: "Tree status")
        |> Zoi.in([:idle, :running, :success, :failure])
    },
    coerce: true
  )
end

defmodule Jido.BehaviorTree.Internal.NodeError do
  @schema Zoi.struct(
    __MODULE__,
    %{
      node_id: Zoi.string(description: "Node identifier"),
      error: Zoi.any(description: "Error term"),
      stacktrace: Zoi.list(Zoi.any()) |> Zoi.optional()
    },
    coerce: true
  )
end
```

**New Signal Types:**

```elixir
# In projects/jido_behaviortree/lib/jido_behaviortree/signals.ex

defmodule Jido.BehaviorTree.Signals do
  # All signals follow CloudEvents v1.0.2
  # Type format: "jido.bt.<entity>.<action>[.<qualifier>]"

  @signals %{
    node_tick_started: "jido.bt.node.tick.started",
    node_tick_completed: "jido.bt.node.tick.completed",
    node_error: "jido.bt.node.error",
    tree_tick_started: "jido.bt.tree.tick.started",
    tree_tick_completed: "jido.bt.tree.tick.completed",
    tree_completed: "jido.bt.tree.completed",
    blackboard_updated: "jido.bt.blackboard.updated"
  }
end
```

### Module Organization

```
projects/jido_behaviortree/lib/jido_behaviortree/
├── internal.ex              # NEW: BT-specific Internal effects
├── signals.ex               # NEW: Signal type definitions
├── effects.ex               # NEW: Effect helpers and constructors
├── strategy/
│   └── behavior_tree.ex     # MODIFY: Integrate effect handling
├── tick.ex                  # MODIFY: Add effect emission helpers
├── nodes/
│   ├── action.ex            # MODIFY: Ensure effect consistency
│   ├── selector.ex          # MODIFY: Emit node tick effects
│   ├── sequence.ex          # MODIFY: Emit node tick effects
│   └── ...
└── telemetry.ex             # MODIFY: Add new telemetry events
```

### Third-Party Integration

**No new dependencies required.**

This implementation leverages:
- **Zoi** - Already in use for schemas
- **Jido.Signal** - Existing signal infrastructure
- **Jido.Agent.Directive** - Existing directive types
- **Telemetry** - Standard BEAM telemetry

### Configuration Changes

Add to `projects/jido_behaviortree/config/config.exs`:

```elixir
config :jido_behaviortree, :effects,
  # Enable/disable effect emission
  enabled: true,
  # Emit signals for node ticks
  emit_node_tick_signals: true,
  # Track blackboard operations
  track_blackboard_ops: false,  # Disabled by default (performance)
  # Log level for effect failures
  log_level: :warning
```

---

## 5. Implementation Phases

### Phase 1: Foundation

**Objective:** Establish the core effect modules and type definitions.

**Success Criteria:**
- All Internal effect modules compile
- All signal type modules compile
- Typespecs are valid
- Basic schema validation works

**Files to Create:**
1. `projects/jido_behaviortree/lib/jido_behaviortree/internal.ex`
2. `projects/jido_behaviortree/lib/jido_behaviortree/signals.ex`
3. `projects/jido_behaviortree/lib/jido_behaviortree/effects.ex`

**Tests to Add:**
1. `test/jido_behaviortree/internal_test.exs`
2. `test/jido_behaviortree/signals_test.exs`

**Dependencies:** None

**Tasks:**
1. Create Internal effect modules with Zoi schemas
2. Define signal type constants following CloudEvents naming
3. Create helper constructor functions for common effects
4. Add typespecs and @moduledoc documentation
5. Write unit tests for schema validation

---

### Phase 2: Core Implementation

**Objective:** Integrate effects into behavior tree execution flow.

**Success Criteria:**
- Node ticks emit Internal effects
- Tick directive accumulation works
- Strategy state updates correctly
- Basic integration tests pass

**Files to Modify:**
1. `projects/jido_behaviortree/lib/jido_behaviortree/tick.ex`
2. `projects/jido_behaviortree/lib/jido_behaviortree/strategy/behavior_tree.ex`
3. `projects/jido_behaviortree/lib/jido_behaviortree/nodes/selector.ex`
4. `projects/jido_behaviortree/lib/jido_behaviortree/nodes/sequence.ex`

**Tests to Add:**
1. `test/jido_behaviortree/strategy/behavior_tree_effects_test.exs`
2. `test/jido_behaviortree/tick_effects_test.exs`

**Dependencies:** Phase 1 must be complete

**Tasks:**
1. Add `emit_node_tick_effect/4` helper to Tick module
2. Add `apply_internal_effects/2` to BehaviorTree strategy
3. Update selector/sequence nodes to emit effects
4. Add strategy state tracking for node statuses
5. Write integration tests for effect flow

**Implementation Detail - Tick Helper:**
```elixir
# In tick.ex
def emit_node_tick_effect(%Tick{} = tick, node_id, event, metadata \\ %{}) do
  signal = %Jido.BehaviorTree.Signal.NodeTick{
    tree_id: get_tree_id(tick),
    node_id: node_id,
    tick_id: get_tick_id(tick),
    event: event,
    metadata: metadata
  }

  directive = %Jido.Agent.Directive.Emit{signal: signal}
  append_directives(tick, [directive])
end
```

---

### Phase 3: Integration & Testing

**Objective:** Complete signal integration and add comprehensive telemetry.

**Success Criteria:**
- All node types emit effects consistently
- Telemetry events match existing patterns
- Signal dispatch works via adapters
- Full test coverage achieved

**Files to Modify:**
1. `projects/jido_behaviortree/lib/jido_behaviortree/nodes/action.ex`
2. `projects/jido_behaviortree/lib/jido_behaviortree/nodes/decorator.ex`
3. `projects/jido_behaviortree/lib/jido_behaviortree/telemetry.ex`
4. `projects/jido_behaviortree/lib/jido_behaviortree/blackboard.ex`

**Tests to Add:**
1. `test/jido_behaviortree/effects_integration_test.exs`
2. `test/jido_behaviortree/telemetry_effects_test.exs`

**Dependencies:** Phase 2 must be complete

**Tasks:**
1. Update Action node to track blackboard operations (optional)
2. Add tree lifecycle signals (completed, failed)
3. Add telemetry events for effect emissions
4. Write end-to-end integration tests
5. Add configuration for enabling/disabling effects

**Implementation Detail - Tree Completion Signal:**
```elixir
# In strategy/behavior_tree.ex
defp handle_tree_completion(%Tick{} = tick, final_status) do
  signal = %Jido.BehaviorTree.Signal.TreeCompleted{
    tree_id: tick.context.tree_id,
    status: final_status,
    tick_count: tick.sequence + 1,
    duration_ms: DateTime.diff(DateTime.utc_now(), tick.context.start_time, :millisecond)
  }

  directives = [
    %Jido.Agent.Directive.Emit{signal: signal},
    %Jido.BehaviorTree.Internal.SetTreeStatus{status: final_status}
  ]

  %{tick | directives: tick.directives ++ directives}
end
```

---

### Phase 4: Polish & Documentation

**Objective:** Complete documentation, examples, and quality checks.

**Success Criteria:**
- All public modules have complete @moduledoc
- Usage examples provided
- Migration guide documented
- Code review approved

**Files to Create:**
1. `projects/jido_behaviortree/guides/effects.md`
2. `projects/jido_behaviortree/guides/signals.md`

**Files to Modify:**
1. `projects/jido_behaviortree/README.md`
2. `projects/jido_behaviortree/CHANGELOG.md`
3. `projects/jido_behaviortree/mix.exs` (version bump)

**Dependencies:** Phase 3 must be complete

**Tasks:**
1. Write comprehensive effect system documentation
2. Add usage examples to docs
3. Create migration guide for existing BT users
4. Run full test suite and fix any issues
5. Update CHANGELOG with new features
6. Prepare PR description

---

## 6. Quality & Testing Strategy

### Test Categories

**Unit Tests:**
- Schema validation for all Internal effects
- Signal struct creation and validation
- Helper function behavior
- Edge cases (nil values, invalid types)

**Integration Tests:**
- Effect emission from node ticks
- Directive accumulation on Tick
- Strategy state updates
- Signal dispatch via Emit directive

**Property-Based Tests:**
- Schema coercion properties
- Effect composition properties
- Signal metadata validity

### Coverage Targets

- **Internal effects:** 100% (critical path)
- **Signal types:** 100% (data contracts)
- **Effect helpers:** 90%+
- **Integration:** 80%+
- **Overall target:** 90%+ coverage

### Quality Gates

1. **All tests pass** - `mix test`
2. **Coverage threshold met** - `mix test.coverage`
3. **Typespecs valid** - `mix dialyzer`
4. **Code formatted** - `mix format`
5. **Linter clean** - `mix credo`
6. **Documentation compiles** - `mix docs`

---

## 7. Risk Assessment

### Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Performance regression from effect emission | Medium | Medium | Make effects configurable, optimize hot paths |
| Breaking changes to existing BT usage | Low | High | Maintain backward compatibility, add migration guide |
| Signal dispatch failures affecting execution | Low | Medium | Signal emission should be non-blocking, log failures |
| Zoi schema validation errors | Low | Low | Comprehensive schema testing, clear error messages |

### Dependency Risks

| Risk | Mitigation |
|------|------------|
| Changes to `Jido.Agent.Directive` | Follow existing patterns, no new directive types needed |
| Changes to `Jido.Signal` | Use existing signal infrastructure, follow CloudEvents spec |
| Zoi version conflicts | Pin to compatible Zoi version in mix.exs |

### Timeline Risks

| Risk | Mitigation |
|------|------------|
| Scope creep from additional effect types | Start with minimal set, iterate in future PRs |
| Integration complexity underestimation | Phase 2 focused on core flow only, defer advanced features |

---

## 8. Success Criteria

### Measurable Outcomes

1. **Effect Coverage:** All node types emit appropriate effects
2. **Signal Consistency:** All signals follow CloudEvents v1.0.2 spec
3. **Test Coverage:** 90%+ coverage for new modules
4. **Performance:** <5% overhead for effect emission (configurable)
5. **Documentation:** Complete docs for all public APIs

### Definition of "Done"

- [ ] All Internal effects implemented with Zoi schemas
- [ ] All signal types defined and documented
- [ ] Node tick effects emitted consistently
- [ ] Tree lifecycle effects emitted
- [ ] Directive accumulation working
- [ ] Strategy state updates correct
- [ ] Telemetry events added
- [ ] Unit tests passing (90%+ coverage)
- [ ] Integration tests passing
- [ ] Documentation complete
- [ ] Examples provided
- [ ] Code review approved
- [ ] CHANGELOG updated

### Acceptance Testing

```elixir
# Acceptance Test 1: Node Tick Effects
test "node tick emits status and signal effects" do
  # Setup behavior tree
  # Execute tick
  # Assert Internal.SetNodeStatus emitted
  # Assert Directive.Emit with NodeTickCompleted signal
end

# Acceptance Test 2: Tree Completion Effects
test "tree completion emits lifecycle effects" do
  # Setup tree that completes
  # Execute to completion
  # Assert TreeCompleted signal emitted
  # Assert strategy state updated
end

# Acceptance Test 3: Effect Accumulation
test "effects accumulate correctly across tree traversal" do
  # Setup tree with multiple nodes
  # Execute tick
  # Assert all directives accumulated
  # Assert strategy state reflects all node statuses
end
```

---

## Dependencies on Other Work

### Pre-requisites
- None (standalone feature)

### Blocked By
- None

### Enables
- Item 006: Define signals for state transitions (can build on these signal types)
- Item 007: Create example behavior tree (can demonstrate effect usage)
- Item 008: Create example BT as part of Jido (can showcase integration)

---

## Open Questions

1. **Should blackboard operations be tracked by default?**
   - Recommendation: No, add as opt-in feature due to performance concerns

2. **Should we add a new `Directive.BTEffect` directive type?**
   - Recommendation: No, use existing `Directive.Emit` with BT-specific signal types

3. **How to handle effect failures without breaking tree execution?**
   - Recommendation: Log and continue, make effects non-blocking

---

## Additional Notes

- This implementation aligns with the existing Jido effect system patterns
- No breaking changes to existing behavior tree API
- Effects are designed to be optional and configurable
- Signal naming follows established `jido.bt.*` convention
- Telemetry integration is additive to existing events

# Implementation Plan: Modernize Jido HTN to Current Jido Patterns

**Item ID:** `011-modernize-to-current-jido-patterns-actio`
**Section:** 3. Jido HTN Modernization
**Planning Date:** 2026-01-07
**Estimated Effort:** 3-5 days

---

## Executive Summary

This implementation modernizes `jido_htn` to align with current Jido ecosystem conventions, transforming legacy patterns (string-based errors, `{module, params}` action tuples, function-based effects) into modern Jido patterns (Splode-based structured errors, direct `Jido.Action` integration, `Jido.Agent.Directive` for side effects, and signal-based coordination).

**Key Architectural Decisions:**
1. **Error Handling:** Migrate from string errors to `Jido.HTN.Error` using Splode for structured, composable error handling
2. **Action Execution:** Replace `{module, params}` tuples with direct `Jido.Action` module references executed via `Jido.Exec.run/3`
3. **Effects to Directives:** Transform state mutation functions into `Jido.Agent.Directive` returns from actions
4. **Signal Integration:** Add CloudEvents v1.0.2 compliant signal emission for plan lifecycle events

**Impact:** Medium breaking changes requiring migration guide, but significant improvement in consistency with Jido ecosystem, better error messages, and native agent coordination support.

---

## Impact Analysis Summary

### Key Findings from Research

**What's Already Modern (No Changes Needed):**
- Zoi schemas for all structs (Method, CompoundTask, PrimitiveTask, Domain)
- Builder pattern for domain construction
- Path dependencies on jido and jido_action
- Testing infrastructure (Mimic, StreamData)

**Critical Areas Requiring Modernization:**
1. **Action Integration** - 50+ sites using `{module, params}` tuples instead of direct action calls
2. **Error Handling** - ~50 error sites returning strings instead of structured errors
3. **Effects System** - State mutation functions instead of directives
4. **Signal Emission** - No signals emitted for plan lifecycle events

### Files Requiring Changes (by Priority)

**High Priority (Core Functionality):**
- `lib/jido_htn/planner.ex` - Error returns (lines 47, 51)
- `lib/jido_htn/planner/task_decomposer.ex` - Action execution (lines 55, 91-92, 269)
- `lib/jido_htn/primitive_task.ex` - Remove placeholder, implement execution (lines 19-25, 127-140)
- `lib/jido_htn/domain/domain_builder.ex` - Error handling (lines 133, 139)

**Medium Priority (Integration):**
- `lib/jido_htn/planner/effect_handler.ex` - Replace with directive pattern (lines 11-45)
- `lib/jido_htn/domain/domain_validation.ex` - Structured error returns (lines 60-68, 97-474)

**Low Priority (Cleanup):**
- `lib/jido_htn/method.ex` - Validation error returns (lines 71-111)
- `lib/jido_htn/planner/condition_evaluator.ex` - Error handling (lines 12-20)

### Integration Points Discovered

**Jido.Exec Integration:**
- Location: `projects/jido_action/lib/jido_action/exec.ex`
- Replace `Jido.Workflow.run/3` placeholder with `Jido.Exec.run/3`

**Signal Routing Integration:**
- Pattern from `projects/jido/lib/jido/skill.ex:182-184`
- Define router for HTN signals in consuming applications

**Error Aggregation:**
- Pattern from `projects/jido/lib/jido/error.ex:46-100`
- Create `Jido.HTN.Error` using Splode with error classes

---

## Feature Specification

### User Stories with Acceptance Criteria

**Story 1: Structured Error Handling**
- As a developer using HTN planning, I want descriptive, structured errors so that I can programmatically handle planning failures
- Acceptance: All planning errors return `{:error, Jido.HTN.Error.PlanningError.t()}` with field-level details
- Acceptance: Error messages include context (task name, method, precondition details)

**Story 2: Direct Action Integration**
- As a domain builder, I want to reference Jido.Action modules directly so that HTN tasks integrate seamlessly with my agent actions
- Acceptance: `PrimitiveTask` stores `task: MyAction` instead of `task: {MyAction, [params]}`
- Acceptance: Execution uses `Jido.Exec.run/3` with proper directive handling
- Acceptance: Actions receive full Jido context including agent state

**Story 3: Signal-Based Coordination**
- As an agent developer, I want HTN to emit signals so that I can react to plan lifecycle events
- Acceptance: Planning emits `htn.plan.started`, `htn.plan.completed`, `htn.plan.failed` signals
- Acceptance: Signals follow CloudEvents v1.0.2 format via Jido.Signal
- Acceptance: Signal emission is configurable (can be disabled for high-frequency scenarios)

**Story 4: Directive-Based Side Effects**
- As an agent operator, I want HTN actions to return directives so that effects are applied via the AgentServer
- Acceptance: Actions can return `{:ok, result, [directive]}` for side effects
- Acceptance: Directives support emit, spawn, schedule, stop operations
- Acceptance: Legacy effect functions are migrated to directive pattern

### API Contracts and Data Flow

**Planning API:**
```elixir
# Before
{:ok, [{module(), keyword()}]} | {:error, String.t()}

# After
{:ok, Jido.HTN.Plan.t(), [Jido.Agent.Directive.t()]} | {:error, Jido.HTN.Error.PlanningError.t()}
```

**Execution API:**
```elixir
# Before (placeholder)
Jido.Workflow.run(action, params, world_state)

# After
{:ok, result, agent} = Jido.Exec.run(agent, action, params)
```

**Error API:**
```elixir
# Before
{:error, "Unknown task: #{name}"}

# After
{:error, Jido.HTN.Error.planning_error("Unknown task", task_name: name)}
```

### State Management Requirements

**No State Changes Required:**
- HTN planner remains stateless (pure function planning)
- Domain definitions remain compile-time DSL
- World state continues to be passed through context

**Context Structure:**
- HTN planning receives `Jido.Context` with agent state
- Actions receive full context including `agent_id`, `dispatch`, `signals`

### Error Handling Approach

**Error Classes (Splode):**
```elixir
Jido.HTN.Error.PlanningError      # No valid method found
Jido.HTN.Error.ValidationError    # Domain validation failed
Jido.HTN.Error.DecompositionError # Task decomposition failed
Jido.HTN.Error.ExecutionError     # Action execution failed
```

**Error Composition:**
- Multiple validation errors compose into single error with list
- Precondition failures include task context
- Planning failures include attempted methods

---

## Technical Design

### Data Model Changes

**1. PrimitiveTask Schema Update:**
```elixir
# Before (primitive_task.ex:19-25)
field :task, {:custom, {__MODULE__, :validate_task_tuple, []}}

# After
field :task, {:custom, {__MODULE__, :validate_action_module, []}}
```

**2. Planner Return Type:**
```elixir
# Before
@type plan_result :: {:ok, [{module(), keyword()}]} | {:error, String.t()}

# After
@type plan_result :: {:ok, Jido.HTN.Plan.t(), [Jido.Agent.Directive.t()]} | {:error, Jido.HTN.Error.t()}
```

**3. New Plan Struct:**
```elixir
defmodule Jido.HTN.Plan do
  @schema Zoi.struct(
    __MODULE__,
    %{
      tasks: Zoi.list(Zoi.atom()),
      methods: Zoi.list(Zoi.string()),
      world_state: Zoi.map()
    },
    coerce: true
  )
end
```

### Module Organization

**New Modules to Create:**
```
lib/jido_htn/
  error.ex                    # Jido.HTN.Error using Splode
  plan.ex                     # Jido.HTN.Plan struct
  planner/
    exec.ex                   # HTN execution via Jido.Exec
  signals.ex                  # HTN signal definitions
```

**Modified Modules:**
```
lib/jido_htn/
  planner.ex                  # Error returns, directive returns
  planner/
    task_decomposer.ex        # Action execution
    effect_handler.ex         # Replace with directive pattern
    condition_evaluator.ex    # Error handling
  domain/
    domain_builder.ex         # Error handling
    domain_validation.ex      # Structured errors
  primitive_task.ex           # Task field, execution
```

### Third-Party Integration Details

**Jido.Exec Integration:**
```elixir
# Execution wrapper for HTN tasks
defmodule Jido.HTN.Planner.Exec do
  def run(agent, action, params, opts \\ []) do
    context = build_context(agent, params, opts)
    Jido.Exec.run(agent, action, params, context)
  end
end
```

**Jido.Signal Integration:**
```elixir
defmodule Jido.HTN.Signals do
  def plan_started(plan_id, tasks), do: Signal.new!("htn.plan.started", %{plan_id: plan_id, tasks: tasks})
  def plan_completed(plan_id, result), do: Signal.new!("htn.plan.completed", %{plan_id: plan_id, result: result})
  def plan_failed(plan_id, error), do: Signal.new!("htn.plan.failed", %{plan_id: plan_id, error: error})
end
```

**Splode Integration:**
```elixir
defmodule Jido.HTN.Error do
  use Splode,
    error_classes: [
      planning: PlanningError,
      validation: ValidationError,
      decomposition: DecompositionError,
      execution: ExecutionError
    ],
    unknown_error: PlanningError
end
```

### Configuration/Environment Changes

**No Config Changes Required:**
- jido_htn is a library with no runtime configuration
- Domain building remains compile-time DSL
- No environment variables needed

**Optional Configuration (Future):**
```elixir
# Application environment (optional)
config :jido_htn,
  emit_signals: true,  # Enable/disable signal emission
  log_planning: false  # Enable planning debug logs
```

---

## Implementation Phases

### Phase 1: Foundation - Error Handling Infrastructure

**Objective:** Establish structured error handling using Splode across HTN modules

**Success Criteria:**
- `Jido.HTN.Error` module defined with 4 error classes
- Core planning files return structured errors
- All error tests pass with new error assertions

**Files to Create:**
- `lib/jido_htn/error.ex` - Splode-based error aggregator

**Files to Modify:**
- `lib/jido_htn/planner.ex` - Update error returns (lines 47, 51)
- `lib/jido_htn/planner/task_decomposer.ex` - Update error returns (lines 55, 91-92, 269)
- `lib/jido_htn/domain/domain_builder.ex` - Replace raise with errors (lines 133, 139)

**Tests to Add:**
- `test/jido_htn/error_test.exs` - Error creation and composition tests
- Update existing planner tests to assert on `Jido.HTN.Error` types

**Dependencies:**
- Requires: `splode` (already available via jido dependency)

**Acceptance Criteria:**
- All error returns use `Jido.HTN.Error.*` helpers
- Error messages include contextual information
- Multiple errors compose correctly
- Test coverage >90% for error module

---

### Phase 2: Core Implementation - Action Integration

**Objective:** Replace `{module, params}` tuples with direct `Jido.Action` integration

**Success Criteria:**
- `PrimitiveTask` stores action module references
- Execution uses `Jido.Exec.run/3` with proper directive handling
- Actions receive full Jido context

**Files to Create:**
- `lib/jido_htn/plan.ex` - Plan struct definition
- `lib/jido_htn/planner/exec.ex` - Execution wrapper

**Files to Modify:**
- `lib/jido_htn/primitive_task.ex` - Update task field, remove placeholder (lines 19-25, 127-140)
- `lib/jido_htn/planner.ex` - Return Plan struct with directives
- `lib/jido_htn/planner/task_decomposer.ex` - Return actions not tuples (line 269)
- Test files in `test/jido_htn/` - Update action execution assertions

**Tests to Add:**
- `test/jido_htn/planner/exec_test.exs` - Execution wrapper tests
- `test/jido_htn/plan_test.exs` - Plan struct tests
- Integration test with real Jido.Action

**Dependencies:**
- Requires: Phase 1 complete (error handling)
- Requires: `jido_action` (already in dependencies)
- Requires: `Jido.Exec` (available via jido)

**Acceptance Criteria:**
- `PrimitiveTask.new!/2` accepts action module directly
- `PrimitiveTask.execute/2` calls action via `Jido.Exec.run/3`
- Actions can return directives for side effects
- Test coverage >85% for execution flow

---

### Phase 3: Integration & Testing - Signals and Directives

**Objective:** Add signal emission for plan lifecycle and migrate effects to directives

**Success Criteria:**
- HTN emits CloudEvents-compliant signals for planning events
- Legacy effect functions replaced with directive pattern
- Signal routing example documented

**Files to Create:**
- `lib/jido_htn/signals.ex` - Signal definitions
- `examples/signal_routing.exs` - Example signal router setup

**Files to Modify:**
- `lib/jido_htn/planner.ex` - Emit signals during planning
- `lib/jido_htn/planner/effect_handler.ex` - Replace with directive pattern (lines 11-45)
- `lib/jido_htn/primitive_task.ex` - Update to handle directives from actions

**Tests to Add:**
- `test/jido_htn/signals_test.exs` - Signal emission tests
- Update integration tests to verify directive handling
- Property-based tests for signal format (StreamData)

**Dependencies:**
- Requires: Phase 2 complete (action integration)
- Requires: `jido_signal` (available via jido)

**Acceptance Criteria:**
- Planning emits `htn.plan.started`, `htn.plan.completed`, `htn.plan.failed`
- Signals include plan context (tasks, methods, result)
- Signal emission can be disabled via options
- Actions can return directives processed by AgentServer
- Example signal router provided in documentation

---

### Phase 4: Polish & Documentation - Validation and Migration

**Objective:** Update validation error returns and provide migration guide

**Success Criteria:**
- All validation errors are structured
- Migration guide documents breaking changes
- Example domain definitions updated
- Full test coverage maintained

**Files to Modify:**
- `lib/jido_htn/domain/domain_validation.ex` - Structured error returns (lines 60-68, 97-474)
- `lib/jido_htn/domain/domain_reader.ex` - Update error returns (lines 12-96)
- `lib/jido_htn/method.ex` - Consider validation error returns (lines 71-111)
- `lib/jido_htn/planner/condition_evaluator.ex` - Add error handling (lines 12-20)
- Test files - Update all error assertions

**Documentation to Create:**
- `MIGRATION_GUIDE.md` - Breaking changes and upgrade path
- Update README.md with new action integration examples
- Update examples/ to use modern patterns
- Add signal routing guide

**Tests to Update:**
- All test files with string error assertions
- Domain validation tests
- Condition evaluator tests
- Integration tests

**Dependencies:**
- Requires: Phase 3 complete (signals and directives)

**Acceptance Criteria:**
- All validation errors use `Jido.HTN.Error.ValidationError`
- Migration guide covers all breaking changes
- Examples use modern action integration
- Test coverage remains >90%
- All quality checks pass (`mix quality`)

---

## Quality & Testing Strategy

### Test Categories

**Unit Tests (Target: >90% coverage):**
- Error creation and composition (error_test.exs)
- Plan struct validation (plan_test.exs)
- Signal format compliance (signals_test.exs)
- Action execution wrapper (exec_test.exs)
- Individual function behavior updates

**Integration Tests:**
- Full planning flow with real actions
- Directive handling from actions
- Signal emission and routing
- Error propagation through planning pipeline
- Context passing to actions

**Property-Based Tests (StreamData):**
- Plan struct generation and validation
- Error composition properties
- Signal CloudEvents compliance
- Action execution properties

**Existing Test Infrastructure:**
- Mimic for mocking (already in mix.exs)
- StreamData for property tests (already in mix.exs)
- ExCoveralls for coverage (already in mix.exs)

### Coverage Targets

| Module | Target Coverage | Priority |
|--------|----------------|----------|
| `Jido.HTN.Error` | 100% | High |
| `Jido.HTN.Plan` | 100% | High |
| `Jido.HTN.Planner.Exec` | 95% | High |
| `Jido.HTN.Signals` | 90% | Medium |
| `Jido.HTN.Planner` | 90% | High |
| `Jido.HTN.PrimitiveTask` | 90% | High |
| `Jido.HTN.Domain.Builder` | 85% | Medium |
| `Jido.HTN.Domain.Validation` | 85% | Low |

**Overall Target:** 90%+ coverage (exceeds current 82%)

### Quality Gates Before Completion

**Pre-merge Checklist:**
- [ ] All tests pass (`mix test`)
- [ ] Coverage >90% (`mix coveralls`)
- [ ] No compiler warnings (`mix compile --warnings-as-errors`)
- [ ] Code formatted (`mix format`)
- [ ] Quality checks pass (`mix quality`)
- [ ] Migration guide complete
- [ ] Examples updated and tested
- [ ] Documentation generated (`mix docs`)
- [ ] No breaking changes without migration path
- [ ] Signal routing example works

**Definition of Done:**
- All 4 phases complete
- All quality gates pass
- Migration guide published
- Examples updated
- No regressions in existing functionality
- Documentation covers new patterns

---

## Risk Assessment

### Technical Risks

**Risk 1: Breaking Change Impact**
- **Severity:** Medium
- **Description:** Error format changes and action execution changes break existing code
- **Mitigation:**
  - Provide comprehensive migration guide
  - Support both error formats during transition period
  - Add deprecation warnings for old patterns
  - Release as major version bump (jido_htn 2.0)

**Risk 2: Action Execution Coupling**
- **Severity:** Low
- **Description:** Tighter coupling to Jido.Exec may reduce flexibility
- **Mitigation:**
  - Keep execution wrapper separate (Jido.HTN.Planner.Exec)
  - Allow custom execution strategies via options
  - Document extension points for custom executors

**Risk 3: Signal Performance**
- **Severity:** Low
- **Description:** Signal emission overhead in high-frequency planning
- **Mitigation:**
  - Make signal emission configurable (default: on)
  - Allow disabling signal emission via options
  - Benchmark signal emission cost
  - Document performance characteristics

**Risk 4: Error Composition Complexity**
- **Severity:** Low
- **Description:** Splode error composition may be complex for validation errors
- **Mitigation:**
  - Follow existing Jido.Error patterns
  - Provide helper functions for common error cases
  - Document error composition patterns
  - Add comprehensive error tests

### Dependency Risks

**Risk 5: Jido.Exec API Changes**
- **Severity:** Low
- **Description:** Jido.Exec API may change before HTN 2.0 release
- **Mitigation:**
  - Jido is stable (v1.3.0)
  - Exec is core API with backward compatibility commitment
  - Pin jido version in dependencies

**Risk 6: Splode Learning Curve**
- **Severity:** Low
- **Description:** Team unfamiliar with Splode patterns
- **Mitigation:**
  - Follow existing Jido.Error patterns exactly
  - Link to Splode documentation in code
  - Provide error helper functions
  - Document common error patterns

### Timeline Risks

**Risk 7: Underestimated Complexity**
- **Severity:** Medium
- **Description:** 3-5 day estimate may be insufficient
- **Mitigation:**
  - Phase 1 is foundation - can ship independently if needed
  - Each phase is independently valuable
  - Can defer Phase 4 to follow-up work
  - Progress tracking via todo list

**Risk 8: Test Update Burden**
- **Severity:** Low
- **Description:** Updating all test assertions may be time-consuming
- **Mitigation:**
  - Update tests incrementally per phase
  - Use search-and-replace for common patterns
  - Leverage existing test infrastructure
  - Focus on integration tests over unit tests for updates

---

## Success Criteria

### Measurable Outcomes

**Code Quality Metrics:**
- 90%+ test coverage (up from 82%)
- Zero compiler warnings
- Zero quality check failures
- All tests passing (218 tests expected)

**Functional Requirements:**
- HTN planning uses Jido.Exec for action execution
- All errors are structured (Jido.HTN.Error)
- Actions can return directives for side effects
- Planning emits CloudEvents-compliant signals
- Migration guide documents all breaking changes

**Integration Requirements:**
- HTN plans integrate with Jido.AgentServer
- HTN signals route via Jido.Skill
- HTN actions work with Jido.Exec
- Error handling matches Jido patterns

### Definition of Done

**Phase Completion Criteria:**
- **Phase 1 (Foundation):** Error module created, core files updated, tests passing
- **Phase 2 (Core):** Action integration working, execution via Jido.Exec, tests passing
- **Phase 3 (Integration):** Signals emitted, directives working, examples provided
- **Phase 4 (Polish):** Validation updated, migration guide complete, all quality gates pass

**Final Acceptance:**
- All 4 phases complete
- Migration guide published
- Examples updated and tested
- Full test coverage (>90%)
- All quality checks pass
- No regressions
- Documentation complete

### Acceptance Testing Approach

**Manual Testing Scenarios:**
1. Define a domain with modern action integration
2. Plan a complex task with multiple methods
3. Execute the plan and verify directives are processed
4. Verify signals are emitted and can be routed
5. Trigger planning errors and verify structured errors
6. Migrate an existing domain definition using migration guide
7. Run all examples in examples/

**Automated Testing:**
- Full test suite passes (`mix test`)
- Coverage report generated (`mix coveralls`)
- Property tests run (`mix test --property`)
- Integration tests run (`mix test --integration`)

**Documentation Verification:**
- Migration guide steps are reproducible
- Examples compile and run without errors
- Signal routing example works end-to-end
- API documentation generated successfully

---

## Implementation Notes

### Key Decisions Made

**1. Action Storage Format (Decision from Research Item 10.1)**
- **Decision:** Use direct module reference (`task: MyAction`)
- **Rationale:** Aligns with Jido.Action patterns, cleaner API
- **Transition:** Support both formats during deprecation period

**2. Planning vs Execution Separation (Decision from Research Item 10.2)**
- **Decision:** Integrate with Jido.Exec for consistency
- **Rationale:** Native Jido ecosystem integration, directive support
- **Trade-off:** Tighter coupling to Jido runtime for better coordination

**3. Signal Granularity (Decision from Research Item 10.3)**
- **Decision:** Start with plan-level signals only, add task-level as opt-in
- **Rationale:** Avoid signal spam in high-frequency scenarios
- **Future:** Task-level signals can be enabled via options

### Backward Compatibility Strategy

**Supported During Transition:**
- Old error format returns with deprecation warning
- Old `{module, params}` tuple format with warning
- Old effect function pattern (delegates to directives)

**Removed in 2.0:**
- String-based errors
- `{module, params}` action tuples
- Direct state mutation effects
- `Jido.Workflow.run/3` placeholder

### Dependencies and Versions

**Required Dependencies (Already Present):**
- `{:jido, "~> 1.3"}` - Core agent system
- `{:jido_action, "~> 1.3"}` - Action behavior and Exec
- `{:zoi, "~> 0.14"}` - Schema validation
- `{:splode, "~> 0.2"}` - Error handling (via jido)

**No New Dependencies Required**

---

## References

### Documentation Sources

**Zoi Documentation:**
- [Zoi v0.14.0 - Quickstart Guide](https://hexdocs.pm/zoi/quickstart_guide.html)
- [Zoi v0.14.0 - Main Module](https://hexdocs.pm/zoi/Zoi.html)
- [Zoi on Hex.pm](https://hex.pm/packages/zoi)

**Splode Documentation:**
- [Get Started with Splode](https://hexdocs.pm/splode/get-started-with-splode.html)
- [Splode.Error Documentation](https://hexdocs.pm/splode/Splode.Error.html)
- [Splode Main Module](https://hexdocs.pm/splode/Splode.html)

**Jido Documentation:**
- Jido.Action behavior (`projects/jido_action/lib/jido_action.ex:1-150`)
- Jido.Error module (`projects/jido/lib/jido/error.ex:90-100`)
- Jido.Agent.Directive (`projects/jido/lib/jido/agent/directive.ex:381-515`)
- Jido.Exec (`projects/jido_action/lib/jido_action/exec.ex`)
- Jido.Signal (`projects/jido_signal/lib/jido_signal.ex:150-153`)

### Research Dependencies

This plan is based on comprehensive research documented in:
- `research.md` - Full codebase impact analysis
- `item.json` - Original task requirements

### Related Roadmap Items

**Prerequisites:**
- Item 009: Convert to Zoi error handling (COMPLETED)
- Item 010: Implement explode errors (COMPLETED)

**Dependent Items:**
- Item 012: Define effects for HTN planning/execution (uses directives from this work)
- Item 013: Define signals for multi-agent coordination (builds on signals from this work)
- Item 014: Documentation pass (documents changes from this work)

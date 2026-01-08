# Implementation Plan: Maximize Test Coverage - Target >90% on Core Modules

**Item ID:** `002-maximize-test-coverage-target-90-coverag`
**Planning Date:** 2025-01-07
**Target Release:** Jido Core 2.0

---

## Executive Summary

This implementation plan addresses raising Jido Core's test coverage from **29.32% to >90%** across 47 core modules. The approach focuses on behaviorally meaningful tests that validate core agent lifecycle, supervision trees, message passing, configuration, error handling, and integration points. The implementation is structured in 4 phases: (1) Coverage Baseline & Tooling, (2) Critical Infrastructure Tests, (3) Feature Area Tests, and (4) CI/CD Integration & Quality Gates.

**Key Architectural Decisions:**
- Focus on documented modules in `mix.exs` groups, excluding example modules
- Use existing test infrastructure (`JidoTest.Case`, async testing patterns)
- Prioritize 0% coverage modules before improving partially covered modules
- Set incremental coverage thresholds (50% → 70% → 90%) to maintain momentum

**Estimated Effort:** 40-60 hours across 4 phases, assuming ~1-2 hours per module for new tests

---

## Impact Analysis Summary

### Key Findings from Research

**Critical Coverage Gaps (0% coverage - 33 modules):**
- **Actions (13 modules):** Control, Lifecycle, Scheduling, Status actions completely untested
- **Agent Infrastructure (8 modules):** AgentPool, FSM strategy, Scheduler, Cron directives
- **Observability (4 modules):** Observe façade, log adapters, span context management
- **Core Utilities (3 modules):** Await, Discovery (7.69%), Telemetry (13.56%)
- **AgentServer Components (5 modules):** Signal router, status, child/patient tracking

**Medium Coverage Gaps (20-50% - 10 modules):**
- AgentServer (26.44%), State (44.07%), Schema (46.15%)
- Directive execution modules need test completion

**Files Requiring Changes:**
- **New test files:** ~25 test files to create in `test/jido/`
- **Configuration updates:** `mix.exs` (coverage threshold), `.github/workflows/test.yml`
- **Documentation:** Update testing guides with new patterns

### Existing Patterns to Follow

**Test Infrastructure (from `test/support/jido_case.ex`):**
- `JidoTest.Case` provides isolated Jido instances per test
- Helper functions: `start_test_agent/2`, `test_registry/1`, `test_task_supervisor/1`
- Automatic setup/teardown of Jido supervisor

**Testing Patterns (from `test/jido/agent_server_test.exs`):**
```elixir
use JidoTest.Case, async: true
@moduletag :capture_log

# Define test actions inline
defmodule TestAction do
  use Jido.Action, name: "test", schema: []
  def run(_params, context), do: {:ok, %{}}
end

# Define test agents inline
defmodule TestAgent do
  use Jido.Agent, name: "test", schema: [...]
  def signal_routes, do: [...]
end
```

### Integration Points Identified

**Telemetry Events:**
- `[:jido, :agent, :action, :run, :start/:stop/:exception]`
- Test with `:telemetry` test attachments

**Phoenix.PubSub:**
- Signal broadcasting tests
- Registry pattern for agent discovery

**Poolboy:**
- Agent pool checkout/checkin tests
- Pool configuration validation

---

## Feature Specification

### User Stories

**As a maintainer,** I want comprehensive test coverage so that refactoring doesn't introduce regressions.
- **Acceptance Criteria:** >90% coverage on all core modules, tests verify public API behavior

**As a contributor,** I want clear test patterns so that I can write tests for new features consistently.
- **Acceptance Criteria:** Test examples in documentation, existing test files follow consistent patterns

**As a CI system,** I want automated coverage enforcement so that PRs cannot decrease coverage below threshold.
- **Acceptance Criteria:** CI fails on coverage drops, coverage metrics visible in PR comments

**As a developer,** I want fast test execution so that I can run tests frequently during development.
- **Acceptance Criteria:** Full test suite runs in <10 minutes, most tests use `async: true`

### API Contracts & Data Flow

**Test Execution Flow:**
```
mix test.coverage
  → ExUnit runs test suite
  → ExCoveralls instruments code
  → Coverage report generated (HTML, JSON)
  → CI checks threshold (90%)
  → PR comment with coverage diff
```

**Test File Structure:**
```
test/jido/
  ├── actions/
  │   ├── control_test.exs
  │   ├── lifecycle_test.exs
  │   ├── scheduling_test.exs
  │   └── status_test.exs
  ├── agent/
  │   ├── strategy/
  │   │   └── fsm_test.exs
  │   └── directive/
  │       └── cron_test.exs
  ├── agent_pool_test.exs
  ├── observe_test.exs
  ├── await_test.exs
  └── scheduler_test.exs
```

### State Management Requirements

**Test Isolation:**
- Each test gets unique Jido instance (via `JidoTest.Case`)
- Agents started with unique names per test
- Registry cleanup automatic on test teardown

**Async Safety:**
- Most tests use `async: true` for parallel execution
- Integration tests that share state use `async: false`
- `@moduletag :capture_log` for log-heavy tests

### Error Handling Approach

**Test Error Scenarios:**
- Invalid params to actions (schema validation)
- Agent startup failures (missing dependencies)
- Signal routing errors (unknown recipients)
- Timeout scenarios (await, scheduling)

**Error Assertions:**
```elixir
assert {:error, reason} = Action.run(params, context)
assert reason =~ "expected"
assert_raise RuntimeError, ~r/message/, fn -> ... end
```

---

## Technical Design

### Data Model Changes

**No data model changes** - this is pure test addition.

**Coverage Tracking Model:**
- Track per-module coverage in spreadsheet or GitHub Project
- Columns: Module, Current %, Target %, Test File, Status, Notes

### Module Organization

**Test File Organization (mirrors lib/):**
```
test/jido/                     # Core tests
  ├── actions/                 # Action tests (4 files)
  ├── agent/                   # Agent submodules
  │   ├── strategy/           # Strategy tests
  │   └── directive/          # Directive tests
  ├── agent_server/           # Server component tests
  ├── observe/                # Observability tests
  └── support/                # Test helpers (existing)
```

**Test Module Naming:**
- `JidoTest.Actions.Control` → tests `Jido.Actions.Control`
- `JidoTest.AgentPool` → tests `Jido.AgentPool`
- Use `ExUnit.Case` macros for shared test logic

### Third-Party Integration Details

**ExCoveralls Configuration (mix.exs):**
```elixir
test_coverage: [
  tool: ExCoveralls,
  summary: [threshold: 90],  # Updated from 80
  export: "cov",
  ignore_modules: [~r/^JidoTest\./]
]
```

**CI/CD Integration (.github/workflows/test.yml):**
```yaml
test_command: mix test.coverage
```

**Optional: ExCoveralls GitHub Actions:**
- Coverage comments on PRs
- Coverage badge generation
- LCOV export for tooling integration

### Configuration & Environment Changes

**Files to Update:**
1. `mix.exs:31` - Update coverage threshold to 90
2. `.github/workflows/test.yml` - Change `test_command` to `mix test.coverage`
3. `test/test_helper.exs` - No changes (already configured correctly)

**Environment Variables:**
- None required for coverage tracking

---

## Implementation Phases

### Phase 1: Coverage Baseline & Tooling

**Objective:** Establish baseline coverage, update CI/CD, create tracking infrastructure

**Success Criteria:**
- Detailed coverage report generated
- CI/CD updated to run coverage tests
- Coverage tracking spreadsheet/Project created
- Module prioritization document completed

**Files to Create/Modify:**
- `mix.exs:31` - Update `threshold: 80` to `threshold: 90`
- `.github/workflows/test.yml` - Update `test_command: mix test.coverage`
- `docs/coverage-tracking.md` - Create tracking document

**Tests to Add:**
- None (baseline phase)

**Tasks:**
1. Generate detailed coverage report: `cd projects/jido && mix test.coverage`
2. Open HTML report: `open cover/excoveralls.html`
3. Document current coverage per module in tracking document
4. Categorize modules by priority:
   - **P0 (Critical):** 0% coverage in core infrastructure (AgentPool, Observe, Await, Scheduler)
   - **P1 (High):** 0% coverage in Actions (Control, Lifecycle, Scheduling, Status)
   - **P2 (Medium):** 20-50% coverage (AgentServer, State, Schema)
   - **P3 (Low):** 50-80% coverage (Error, Directive, Util)
5. Create GitHub Project or spreadsheet for tracking progress
6. Update CI/CD workflow to run `mix test.coverage`
7. Verify CI fails on coverage drops

**Dependencies:**
- None (foundation phase)

**Acceptance Tests:**
- [ ] Coverage report exists in `cover/excoveralls.html`
- [ ] CI runs `mix test.coverage` and reports metrics
- [ ] Tracking document lists all 47 modules with current coverage
- [ ] Modules prioritized into P0-P3 tiers

---

### Phase 2: Critical Infrastructure Tests (P0 Modules)

**Objective:** Write tests for 0% coverage modules in core infrastructure

**Success Criteria:**
- AgentPool, Observe, Await, Scheduler, Discovery, Telemetry modules have >90% coverage
- All tests follow existing patterns (`JidoTest.Case`, `async: true`)
- Test suite runtime < 10 minutes

**Files to Create:**
- `test/jido/agent_pool_test.exs`
- `test/jido/observe_test.exs`
- `test/jido/observe/log_test.exs`
- `test/jido/observe/span_ctx_test.exs`
- `test/jido/await_test.exs`
- `test/jido/scheduler_test.exs`
- `test/jido/discovery_test.exs`
- `test/jido/telemetry_test.exs`

**Tests to Add (8 test files, ~120 tests total):**

**1. AgentPool Tests (`test/jido/agent_pool_test.exs`):**
```elixir
defmodule JidoTest.AgentPool do
  use JidoTest.Case, async: true

  describe "pool lifecycle" do
    test "starts pool with default configuration"
    test "starts pool with custom size and max_overflow"
    test "stops pool cleanly"
  end

  describe "checkout/checkin" do
    test "checks out agent from pool"
    test "blocks when pool is empty"
    test "checks in agent back to pool"
    test "handles timeout when waiting for agent"
  end

  describe "with_agent" do
    test "executes function with checked out agent"
    test "returns agent to pool after function"
    test "propagates errors from function"
  end

  describe "call" do
    test "sends message to pooled agent"
    test "retries on failure"
    test "times out on unresponsive agent"
  end
end
```

**2. Observe Tests (`test/jido/observe_test.exs`):**
```elixir
defmodule JidoTest.Observe do
  use JidoTest.Case, async: true
  @moduletag :capture_log

  describe "with_span" do
    test "wraps function in span context"
    test "emits telemetry events on start/stop"
    test "captures errors and emits exception event"
    test "nests spans correctly"
  end

  describe "start_span/finish_span" do
    test "manually manages span lifecycle"
    test "attaches span context to process"
    test "finishes span and records metrics"
  end

  describe "finish_span_error" do
    test "records error in span"
    test "emits exception telemetry event"
  end
end
```

**3. Await Tests (`test/jido/await_test.exs`):**
```elixir
defmodule JidoTest.Await do
  use JidoTest.Case, async: true

  describe "await" do
    test "waits for condition to become true"
    test "returns result when condition met"
    test "times out when condition not met"
    test "checks condition at specified interval"
  end

  describe "await!" do
    test "raises on timeout"
    test "returns result when condition met"
  end
end
```

**4. Scheduler Tests (`test/jido/scheduler_test.exs`):**
```elixir
defmodule JidoTest.Scheduler do
  use JidoTest.Case, async: false  # Scheduler is global

  describe "schedule/3" do
    test "schedules function to run at delay"
    test "executes scheduled function"
    test "cancels scheduled job"
    test "handles invalid delay values"
  end

  describe "cron_schedule" do
    test "schedules recurring job with cron expression"
    test "executes job on cron schedule"
    test "cancels cron job"
  end
end
```

**5. Telemetry Tests (`test/jido/telemetry_test.exs`):**
```elixir
defmodule JidoTest.Telemetry do
  use JidoTest.Case, async: true

  describe "attach_event_handler" do
    test "attaches handler to telemetry event"
    test "executes handler when event emitted"
    test "detaches handler when done"
  end

  describe "event emission" do
    test "emits action execution events"
    test "includes correct measurements and metadata"
  end
end
```

**6-8. Discovery, Log, SpanCtx Tests:**
- Similar pattern for remaining observability modules

**Dependencies:**
- Phase 1 must be complete (baseline established)

**Acceptance Tests:**
- [ ] All 8 test files created
- [ ] Coverage for P0 modules >90%
- [ ] All tests pass: `mix test`
- [ ] Test coverage report shows improvement
- [ ] No `@tag :flaky` tests without justification

---

### Phase 3: Feature Area Tests (P1 & P2 Modules)

**Objective:** Write tests for Actions and partial coverage modules

**Success Criteria:**
- All Actions modules have >90% coverage
- AgentServer, State, Schema modules improved to >90%
- FSM strategy and directives tested
- Total coverage >90%

**Files to Create:**
- `test/jido/actions/control_test.exs`
- `test/jido/actions/lifecycle_test.exs`
- `test/jido/actions/scheduling_test.exs`
- `test/jido/actions/status_test.exs`
- `test/jido/agent/strategy/fsm_test.exs`
- `test/jido/agent/strategy/snapshot_test.exs`
- `test/jido/agent/directive/cron_test.exs`
- `test/jido/agent/directive/cron_cancel_test.exs`
- `test/jido/agent/directive/spawn_agent_test.exs`
- `test/jido/agent_server/signal_router_test.exs`
- `test/jido/agent_server/status_test.exs`
- `test/jido/agent_server/child_info_test.exs`

**Tests to Add (12 test files, ~180 tests total):**

**1. Control Actions Tests (`test/jido/actions/control_test.exs`):**
```elixir
defmodule JidoTest.Actions.Control do
  use JidoTest.Case, async: true

  describe "Broadcast action" do
    test "broadcasts signal to all subscribers"
    test "includes payload in broadcast"
  end

  describe "Cancel action" do
    test "cancels pending directive"
    test "returns error for non-existent directive"
  end

  describe "Forward action" do
    test "forwards signal to target agent"
    test "preserves signal metadata"
  end

  describe "Reply action" do
    test "replies to signal sender"
    test "handles missing reply_to context"
  end

  describe "Noop action" do
    test "returns success without side effects"
  end
end
```

**2. Lifecycle Actions Tests (`test/jido/actions/lifecycle_test.exs`):**
```elixir
defmodule JidoTest.Actions.Lifecycle do
  use JidoTest.Case, async: true

  describe "NotifyParent action" do
    test "sends signal to parent agent"
    test "handles missing parent gracefully"
  end

  describe "NotifyPid action" do
    test "sends signal to specified pid"
    test "handles invalid pid"
  end

  describe "SpawnChild action" do
    test "spawns child agent with specified module"
    test "links child to parent"
    test "returns child pid"
  end

  describe "StopChild action" do
    test "stops child agent by pid"
    test "handles stopping non-existent child"
  end

  describe "StopSelf action" do
    test "stops current agent"
    test "executes cleanup before stop"
  end
end
```

**3. Scheduling Actions Tests (`test/jido/actions/scheduling_test.exs`):**
```elixir
defmodule JidoTest.Actions.Scheduling do
  use JidoTest.Case, async: false  # Scheduler is global

  describe "ScheduleCron action" do
    test "schedules cron job for agent"
    test "executes action on cron schedule"
    test "persists across agent restarts"
  end

  describe "CancelCron action" do
    test "crons cron job by id"
    test "handles non-existent job id"
  end

  describe "ScheduleSignal action" do
    test "schedules signal to be sent at delay"
    test "includes target and payload"
  end

  describe "ScheduleTimeout action" do
    test "schedules timeout signal"
    test "cancels on agent stop"
  end
end
```

**4. Status Actions Tests (`test/jido/actions/status_test.exs`):**
```elixir
defmodule JidoTest.Actions.Status do
  use JidoTest.Case, async: true

  describe "MarkCompleted action" do
    test "sets agent status to :completed"
    test "emits status transition signal"
  end

  describe "MarkFailed action" do
    test "sets agent status to :failed"
    test "includes error reason"
  end

  describe "MarkIdle action" do
    test "sets agent status to :idle"
  end

  describe "MarkWorking action" do
    test "sets agent status to :working"
  end

  describe "SetStatus action" do
    test "sets arbitrary status"
    test "validates status values"
  end
end
```

**5-8. AgentServer Component Tests:**
- Signal router tests (routing logic, unknown recipients)
- Status management tests (status transitions, queries)
- Child info tests (child tracking, shutdown handling)

**9-12. Strategy & Directive Tests:**
- FSM strategy tests (state transitions, event handling)
- Snapshot tests (state capture/restore)
- Cron directive tests (scheduling, cancellation)
- Spawn agent directive tests (agent spawning, linking)

**Dependencies:**
- Phase 2 must be complete (critical infrastructure tested)

**Acceptance Tests:**
- [ ] All 12 test files created
- [ ] Coverage for Action modules >90%
- [ ] Coverage for AgentServer components >90%
- [ ] Coverage for FSM/directives >90%
- [ ] Total coverage >90%
- [ ] All tests pass: `mix test`

---

### Phase 4: CI/CD Integration & Quality Gates

**Objective:** Finalize CI/CD integration, add coverage reporting, ensure test quality

**Success Criteria:**
- CI runs coverage tests on every PR
- Coverage metrics visible in PR comments
- Coverage threshold enforced (90%)
- Test suite runtime < 10 minutes
- All tests verified for behavioral value (not just coverage)

**Files to Create/Modify:**
- `.github/workflows/test.yml` - Update with coverage reporting
- `mix.exs:31` - Final threshold set to 90
- `docs/testing-guide.md` - Update with new test patterns
- `docs/coverage-report.md` - Generate final coverage report

**Tests to Add:**
- None (integration phase)

**Tasks:**

**1. CI/CD Updates:**
```yaml
# .github/workflows/test.yml
name: Test

on: push
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
      - run: mix test.coverage
      - uses: codecov/codecov-action@v3  # Optional
        with:
          files: cover/excoveralls.json
```

**2. Optional: ExCoveralls GitHub Actions:**
```elixir
# mix.exs - Add if PR comments desired
def project do
  [
    test_coverage: [
      tool: ExCoveralls,
      summary: [threshold: 90],
      export: "cov",
      ignore_modules: [~r/^JidoTest\./]
    ],
    preferred_cli_env: [
      coveralls: :test,
      "coveralls.html": :test,
      "coveralls.github": :test
    ]
  ]
end

# Add to dependencies:
{:excoveralls, "~> 0.18", only: :test}
```

**3. Test Quality Audit:**
- Review all tests for behavioral value
- Reject tests without assertions
- Remove brittle/overly specific tests
- Consolidate redundant test cases

**4. Performance Check:**
- Time test suite: `time mix test`
- Identify slow tests (>1 second)
- Optimize or add `@tag timeout:` for long tests

**5. Documentation Updates:**
- Add test patterns to testing guide
- Document coverage targets
- Add examples for new test files

**6. Final Coverage Report:**
```bash
cd projects/jido
mix test.coverage
open cover/excoveralls.html
# Document final coverage per module
```

**Dependencies:**
- Phase 3 must be complete (all tests written)

**Acceptance Tests:**
- [ ] CI runs `mix test.coverage` on every push
- [ ] Coverage fails PR if <90%
- [ ] Coverage metrics visible in PR (comment or badge)
- [ ] Test suite runtime < 10 minutes
- [ ] All tests verified for behavioral value
- [ ] Testing guide updated with new patterns
- [ ] Final coverage report generated

---

## Quality & Testing Strategy

### Test Categories

**1. Unit Tests (70% of tests):**
- Test individual functions in isolation
- Mock external dependencies (rarely needed)
- Fast execution (<100ms per test)

**2. Integration Tests (20% of tests):**
- Test component interactions (agent + actions + signals)
- Use real JidoTest.Case infrastructure
- Slower execution (100ms-1s per test)

**3. Property-Based Tests (5% of tests):**
- Use `stream_data` for state machine invariants
- Example: "For any signal sequence, agent state remains valid"
- Catch edge cases unit tests miss

**4. Edge Case Tests (5% of tests):**
- Nil values, empty inputs, timeouts
- Error scenarios, failure modes
- Boundary conditions

### Coverage Targets

**Per-Module Targets:**
- **Core modules (AgentServer, Agent, State):** >95%
- **Action modules:** >90%
- **Infrastructure (Observe, Scheduler, Pool):** >90%
- **Utilities:** >85%

**Overall Target:**
- **Line coverage:** >90%
- **Branch coverage:** >85%

### Quality Gates

**Before Marking Complete:**
- [ ] All tests pass: `mix test`
- [ ] Coverage report shows >90% overall
- [ ] No modules <85% coverage (with documented rationale)
- [ ] Test suite runtime < 10 minutes
- [ ] Code review: all tests verify behavior (not just coverage)
- [ ] No `@tag :flaky` tests without justification
- [ ] CI/CD enforces coverage threshold

**Code Review Checklist:**
- Test has descriptive name explaining what it verifies
- Test has assertions (not just execution)
- Test follows existing patterns (JidoTest.Case, async: true)
- Test is deterministic (no race conditions)
- Error tests verify error content (not just that error occurred)

---

## Risk Assessment

### Technical Risks

**Risk: Test suite runtime exceeds 10 minutes**
- **Probability:** Medium
- **Impact:** High (slows development)
- **Mitigation:**
  - Keep tests async where possible
  - Use `@tag timeout:` for long tests
  - Consider test splitting for CI/CD
  - Profile and optimize slow tests

**Risk: Brittle tests that break on refactoring**
- **Probability:** High
- **Impact:** Medium (test maintenance burden)
- **Mitigation:**
  - Test public APIs, not private functions
  - Use property-based tests for invariants
  - Regular test review to eliminate brittle tests
  - Focus on integration tests over implementation details

**Risk: Coverage gaming (tests without assertions)**
- **Probability:** Medium
- **Impact:** High (false sense of security)
- **Mitigation:**
  - Code review practice: reject tests without assertions
  - Test review checklist: "What bug does this catch?"
  - Focus on behaviorally meaningful tests
  - Regular test audits

### Dependency Risks

**Risk: Flaky tests due to async timing**
- **Probability:** Medium
- **Impact:** Medium (unreliable CI)
- **Mitigation:**
  - Use `@moduletag :capture_log` for log-heavy tests
  - Add explicit waits/await for async operations
  - Avoid sleep() in tests (use await patterns)
  - Tag truly flaky tests with `@tag :flaky` and document

**Risk: Hard-to-test code requiring refactors**
- **Probability:** Low
- **Impact:** Medium (scope creep)
- **Mitigation:**
  - Focus testing on public APIs
  - Accept <90% for truly untestable code (document rationale)
  - Consider minimal refactoring if critical path uncovered

### Timeline Risks

**Risk: Underestimated effort for 25+ test files**
- **Probability:** Medium
- **Impact:** High (timeline slip)
- **Mitigation:**
  - Start with P0 modules, validate time estimates
  - Adjust scope if running behind
  - Consider accepting 85-90% coverage for less critical modules
  - Parallelize test writing across team members

---

## Success Criteria

### Measurable Outcomes

**Coverage Metrics:**
- [ ] Overall coverage >90% (from 29.32%)
- [ ] No core modules <85% coverage
- [ ] All P0 modules >95% coverage
- [ ] Line coverage >90%, branch coverage >85%

**Test Metrics:**
- [ ] 25+ new test files created
- [ ] 300+ new tests added
- [ ] Test suite runtime < 10 minutes
- [ ] Zero `@tag :flaky` tests without justification
- [ ] All tests follow JidoTest.Case pattern

**CI/CD Metrics:**
- [ ] CI runs `mix test.coverage` on every PR
- [ ] Coverage threshold enforced (90%)
- [ ] Coverage metrics visible in PR

**Quality Metrics:**
- [ ] Code review approved: all tests verify behavior
- [ ] Zero tests without assertions
- [ ] Documentation updated (testing guide)

### Definition of "Done"

Task is complete when:
1. **Coverage:** All core modules >90% coverage
2. **Tests:** All tests pass, runtime < 10 minutes
3. **CI:** Coverage enforced in CI/CD
4. **Quality:** Code review approved, behavioral tests verified
5. **Documentation:** Testing guide updated with new patterns
6. **Reporting:** Final coverage report generated and documented

### Acceptance Testing Approach

**Pre-Release Validation:**
1. Run full test suite: `mix test`
2. Run coverage: `mix test.coverage`
3. Open HTML report: `open cover/excoveralls.html`
4. Verify all core modules >90%
5. Check test runtime: `time mix test`
6. Review PR with test coverage diff
7. Code review for test quality
8. Update testing documentation

**Post-Release Monitoring:**
1. Track coverage in CI/CD
2. Review coverage trends (prevent drift)
3. Address flaky tests promptly
4. Quarterly test audit (remove brittle tests)

---

## Next Steps

**Immediate Actions (to start implementation):**
1. Clarify scope questions from research (Section 10):
   - Which modules are "core"? → **Decision:** Use `groups_for_modules` in mix.exs, exclude examples
   - Should coverage include integration tests? → **Decision:** Focus on unit tests, add integration tests where critical
   - Should we use stream_data? → **Decision:** Use for AgentServer state machine only
   - What is acceptable test runtime? → **Decision:** Target < 10 minutes
   - Coverage export format? → **Decision:** HTML for local, JSON for CI
   - PR coverage comments? → **Decision:** Optional, add if time permits

2. Create coverage tracking spreadsheet/Project board

3. Begin Phase 1: Generate baseline coverage report

4. Schedule implementation phases across team members

**Tools & Resources:**
- ExCoveralls: https://hexdocs.pm/excoveralls/
- ExUnit: https://hexdocs.pm/ex_unit/
- StreamData: https://hexdocs.pm/stream_data/
- Elixir testing best practices: https://elixirschool.com/en/lessons/basics/testing/

**Questions for Team:**
1. Are we accepting 85-90% for some modules, or is 90% a hard floor?
2. Who will code review tests for behavioral value?
3. Should we add ExCoveralls GitHub Actions integration (PR comments)?
4. What is our maximum acceptable test suite runtime?

---

## Appendix: Test File Templates

**Action Test Template:**
```elixir
defmodule JidoTest.Actions.{ActionName} do
  use JidoTest.Case, async: true

  describe "{action_name} action" do
    test "executes successfully with valid params"
    test "returns error with invalid params"
    test "emits expected telemetry events"
  end
end
```

**AgentServer Test Template:**
```elixir
defmodule JidoTest.AgentServer.{Component} do
  use JidoTest.Case, async: true
  @moduletag :capture_log

  defmodule TestAgent do
    use Jido.Agent, name: "test", schema: []
    def signal_routes, do: []
  end

  describe "component behavior" do
    test "handles expected case"
    test "handles error case"
  end
end
```

**Coverage Tracking Template:**
| Module | Current % | Target % | Test File | Status | Notes |
|--------|-----------|----------|-----------|---------|-------|
| Jido.AgentPool | 0% | 90% | agent_pool_test.exs | Todo | Critical path |
| Jido.Observe | 0% | 90% | observe_test.exs | Todo | Telemetry events |
| ... | ... | ... | ... | ... | ... |

# Research: Maximize Test Coverage - Target >90% Coverage on Core Modules

**Item ID:** `002-maximize-test-coverage-target-90-coverag`
**Research Date:** 2025-01-07
**Current State:** Ready for planning

---

## Executive Summary

Jido currently has **29.32% test coverage** across 47 modules, with a threshold configured at 80%. This task requires identifying coverage gaps, writing behaviorally meaningful tests for core agent lifecycle, supervision trees, message passing, configuration, error handling, and integration points, and bringing coverage above 90%.

**Key Finding:** The project has excellent testing infrastructure (ExCoveralls, ExUnit, custom test case modules) but many core modules have 0% coverage, particularly Actions, Observability, AgentPool, and Scheduler modules.

---

## 1. Project Dependencies Discovered

### Testing Framework & Tools (from `mix.exs`)

**Core Testing:**
- `excoveralls ~> 0.18.3` - Coverage tracking with HTML export
- `ex_unit` - Built-in Elixir testing framework
- `stream_data ~> 1.0` - Property-based testing (available but unused)

**Mocking & Testing Utilities:**
- `mimic ~> 2.0` - Mocking library for tests
- `mock ~> 0.3.0` - Alternative mocking (legacy)

**Code Quality:**
- `credo ~> 1.7` - Code quality linting
- `dialyxir ~> 1.4` - Dialyzer for type checking
- `doctor ~> 0.21` - Health checks for codebase

**Current Coverage Configuration (mix.exs:29-34):**
```elixir
test_coverage: [
  tool: ExCoveralls,
  summary: [threshold: 80],
  export: "cov",
  ignore_modules: [~r/^JidoTest\./]
]
```

### Jido Ecosystem Dependencies

- `jido_action` (github: agentjido/jido_action, branch: main)
- `jido_signal` (path dependency)
- `fsmx ~> 0.5` - State machine support for agent strategies
- `phoenix_pubsub ~> 2.1` - Message passing infrastructure
- `telemetry ~> 1.3` - Observability events
- `poolboy ~> 1.5` - Agent pooling

---

## 2. Files Requiring Changes

### Modules with 0% Coverage (Critical Priority)

**Action Modules (13 modules):**
- `lib/jido/actions/control.ex:1-120` - Broadcast, Cancel, Forward, Noop, Reply actions
- `lib/jido/actions/lifecycle.ex:1-150` - NotifyParent, NotifyPid, SpawnChild, StopChild, StopSelf
- `lib/jido/actions/scheduling.ex:1-200` - CancelCron, ScheduleCron, ScheduleSignal, ScheduleTimeout
- `lib/jido/actions/status.ex:1-100` - MarkCompleted, MarkFailed, MarkIdle, MarkWorking, SetStatus

**Agent & Strategy Modules (8 modules):**
- `lib/jido/agent_pool.ex:1-200` - Pooled agent management
- `lib/jido/agent/strategy/fsm.ex:1-300` - FSM strategy implementation
- `lib/jido/agent/strategy/fsm/machine.ex:1-150` - FSM machine state management
- `lib/jido/agent/strategy/snapshot.ex:1-100` - Strategy snapshot/restore
- `lib/jido/agent/effects.ex:1-100` - Effect handling
- `lib/jido/agent/directive/cron.ex:1-150` - Cron directive implementation
- `lib/jido/agent/directive/cron_cancel.ex:1-80` - Cron cancellation
- `lib/jido/agent/directive/spawn_agent.ex:1-100` - Agent spawning directive

**Observability Modules (6 modules):**
- `lib/jido/observe.ex:1-389` - Main observability façade
- `lib/jido/observe/log.ex:1-100` - Threshold-based logging
- `lib/jido/observe/noop_tracer.ex:1-50` - No-op tracer implementation
- `lib/jido/observe/span_ctx.ex:1-60` - Span context management

**Core Infrastructure Modules (6 modules):**
- `lib/jido/await.ex:1-150` - Async await functionality
- `lib/jido/scheduler.ex:1-200` - Scheduling system
- `lib/jido/discovery.ex:1-100` - Service discovery (7.69% covered)
- `lib/jido/telemetry.ex:1-100` - Telemetry handlers (13.56% covered)

**AgentServer Modules (4 modules):**
- `lib/jido/agent_server/signal_router.ex:1-150` - Signal routing logic
- `lib/jido/agent_server/status.ex:1-100` - Status management
- `lib/jido/agent_server/child_info.ex:1-80` - Child process info (25.00% covered)
- `lib/jido/agent_server/parent_ref.ex:1-80` - Parent reference tracking (33.33% covered)

**Error Modules (9 modules with 50% coverage):**
- `lib/jido/error.ex:1-300` - Error constructors (64.81% covered)
- Individual error exception modules need coverage for exception struct definitions

### Low Coverage Modules (20-50% - Priority 2)

- `lib/jido/agent_server.ex:1-500` - Main agent server (26.44%)
- `lib/jido/agent_server/state.ex:1-300` - Server state management (44.07%)
- `lib/jido/agent/schema.ex:1-200` - Agent schema validation (46.15%)
- `lib/jido/agent_server/options.ex:1-150` - Server options (52.17%)
- `lib/jido/agent_server/directive_exec.ex:1-400` - Directive execution (66.67%)
- `lib/jido/agent_server/directive_executors.ex:1-200` - Executor routing (partial)

### Test Files to Create

**Missing Test Files (estimated 25+ files):**
- `test/jido/actions/control_test.exs` - Control action tests
- `test/jido/actions/lifecycle_test.exs` - Lifecycle action tests
- `test/jido/actions/scheduling_test.exs` - Scheduling action tests
- `test/jido/actions/status_test.exs` - Status action tests
- `test/jido/agent_pool_test.exs` - Pool management tests
- `test/jido/observe_test.exs` - Observability façade tests
- `test/jido/await_test.exs` - Async await tests
- `test/jido/scheduler_test.exs` - Scheduler tests
- `test/jido/agent/strategy/fsm_test.exs` - FSM strategy tests
- `test/jido/agent/directive/cron_test.exs` - Cron directive tests
- Plus ~15 more for remaining uncovered modules

---

## 3. Existing Patterns Found

### Test Infrastructure

**Custom Test Case Module:**
- `test/support/jido_case.ex` - `JidoTest.Case` provides isolated Jido instances
  - Automatic Jido supervisor setup/teardown per test
  - Provides `start_test_agent/2`, `test_registry/1`, `test_task_supervisor/1` helpers
  - Each test gets unique Jido instance (`:"jido_test_#{test_id}"`)

**Test Helper (test/test_helper.exs):**
- Excludes `:skip` and `:flaky` tags by default
- Simple configuration: `ExUnit.start()`

**Existing Test Pattern (from test/jido/agent_server_test.exs):**
```elixir
defmodule JidoTest.AgentServerTest do
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

  test "agent executes action", context do
    {:ok, pid} = start_test_agent(context, TestAgent)
    # Test assertions
  end
end
```

### Testing Patterns Used

**Async Testing:**
- Most tests use `async: true` for parallel execution
- `@moduletag :capture_log` for log-heavy tests

**Action Testing:**
- Inline action modules defined in test files
- Test params, context, state, and directive returns
- Example: `test/jido/actions/control_test.exs` (100% covered Actions.Control)

**Agent Lifecycle Testing:**
- Start/stop agent cycles
- State transitions
- Signal routing
- Error handling

**Mocking:**
- `mimic` available but rarely used in current tests
- Prefer explicit test doubles over mocks

---

## 4. Integration Points

### Telemetry Integration

**Current Usage:**
- `lib/jido/telemetry.ex` - Event handler attachment (13.56% covered)
- `lib/jido/observe.ex` - Span wrapping with telemetry emission (0% covered)

**Telemetry Events Emitted (from moduledocs):**
- `[:jido, :agent, :action, :run, :start]` - Action execution starts
- `[:jido, :agent, :action, :run, :stop]` - Action execution completes
- `[:jido, :agent, :action, :run, :exception]` - Action execution fails
- Events include measurements: `system_time`, `duration`
- Events include metadata: `agent_id`, `action`, etc.

📖 [Telemetry docs](https://hexdocs.pm/telemetry/)
📖 [Telemetry event best practices](https://hexdocs.pm/telemetry/telemetry.html#content)

### External Service Mocking

**Pattern:**
- No actual external services in core Jido
- Integration points abstracted through actions
- Test actions mock behavior (e.g., `RecordAction`, `EmitTestAction`)

### Poolboy Integration

**Current:**
- `lib/jido/agent_pool.ex` wraps `:poolboy` for agent pooling
- Pool configuration: `:size`, `:max_overflow`, `:strategy`

📖 [Poolboy docs](https://github.com/devinus/poolboy)

### Phoenix.PubSub Integration

**Current:**
- Used for signal broadcasting
- Registry pattern for agent discovery

📖 [Phoenix.PubSub docs](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html)

---

## 5. Test Impact & Patterns

### Tests Requiring Updates

**No existing tests need updates** - we're adding new test files.

**New Test Files Required:**

1. **Action Tests (4 files):**
   - `test/jido/actions/control_test.exs` - Test Broadcast, Cancel, Forward, Noop, Reply
   - `test/jido/actions/lifecycle_test.exs` - Test NotifyParent, NotifyPid, SpawnChild, StopChild, StopSelf
   - `test/jido/actions/scheduling_test.exs` - Test CancelCron, ScheduleCron, ScheduleSignal, ScheduleTimeout
   - `test/jido/actions/status_test.exs` - Test MarkCompleted, MarkFailed, MarkIdle, MarkWorking, SetStatus

2. **Observability Tests (4 files):**
   - `test/jido/observe_test.exs` - Test with_span, start_span, finish_span, finish_span_error
   - `test/jido/observe/log_test.exs` - Test threshold-based logging
   - `test/jido/observe/span_ctx_test.exs` - Test span context lifecycle
   - `test/jido/telemetry_test.exs` - Test telemetry event handlers

3. **Agent Infrastructure Tests (6 files):**
   - `test/jido/agent_pool_test.exs` - Test checkout/checkin, with_agent, call
   - `test/jido/await_test.exs` - Test async await patterns
   - `test/jido/scheduler_test.exs` - Test scheduling system
   - `test/jido/discovery_test.exs` - Test service discovery
   - `test/jido/agent/strategy/fsm_test.exs` - Test FSM strategy
   - `test/jido/agent/directive/cron_test.exs` - Test cron directives

4. **Error Module Tests (1-2 files):**
   - `test/jido/error_test.exs` (exists, 64.81% - needs completion)
   - Test exception raising for all error types

5. **AgentServer Tests (3 files):**
   - `test/jido/agent_server/signal_router_test.exs` - Test signal routing
   - `test/jido/agent_server/status_test.exs` - Test status management
   - `test/jido/agent_server/child_info_test.exs` - Test child process tracking

### Current Testing Patterns

**Test Organization:**
- `test/jido/` - Mirrors `lib/jido/` structure
- `test/support/` - Test helpers and case modules
- `test/jido/bus/support/` - Bus-specific support (in elixirc_paths)

**Test Execution:**
- `mix test` - Run all tests (excludes :skip and :flaky)
- `mix test.coverage` - Run with ExCoveralls
- `mix test --only focus` - Run focused tests

**Test Tags:**
- `@moduletag :capture_log` - Suppress logs for module
- `@tag :skip` - Skip test
- `@tag :flaky` - Skip flaky test by default
- `@tag focus: true` - Focus specific test

---

## 6. Configuration & Environment

### Config Files to Update

**1. Update coverage threshold in `mix.exs:31`:**
```elixir
test_coverage: [
  tool: ExCoveralls,
  summary: [threshold: 90],  # Change from 80 to 90
  export: "cov",
  ignore_modules: [~r/^JidoTest\./]
]
```

**2. CI/CD workflow (`.github/workflows/test.yml`):**
Currently uses: `test_command: mix test`

**Update to:**
```yaml
test_command: mix test.coverage
```

This will surface coverage metrics in CI and fail PRs that drop below threshold.

**3. Consider adding coverage reporting to CI:**
- ExCoveralls can post coverage comments to PRs
- HTML reports exported to `cover/` directory
- GitHub Actions integration available

### Environment Variables

No new environment variables required. Coverage is compile-time configuration.

---

## 7. Required New Dependencies/Patterns

**None required.** The project has:

✅ ExCoveralls for coverage reporting
✅ ExUnit for testing framework
✅ Mimic for mocking (if needed)
✅ StreamData for property-based testing (available)
✅ Custom test case module for isolation

**Optional Enhancements:**

1. **Property-Based Testing:**
   - Consider using `stream_data` for AgentServer state machine properties
   - Example: "For any sequence of signals, agent state remains valid"

2. **Coverage Visualization:**
   - ExCoveralls HTML reports generated in `cover/excoveralls.html`
   - Consider adding to CI for PR comments

---

## 8. Risk Assessment

### Breaking Changes
**Risk: LOW**
- Adding tests does not change behavior
- No code modifications required
- Coverage threshold change only affects CI

### Performance Implications
**Risk: LOW**
- More tests = longer test runs
- Current test suite runs quickly (async: true)
- Consider test partitioning if runtime exceeds 5-10 minutes

**Mitigation:**
- Keep tests async where possible
- Use `@tag timeout: 5000` for long-running tests
- Consider `:skip` tags for integration tests

### Security Touchpoints
**Risk: NONE**
- Tests don't affect production security
- Ensure test actions don't expose real credentials
- Mock external dependencies

### Test Maintenance Burden
**Risk: MEDIUM**
- 90% coverage requires ongoing maintenance
- Refactoring will require test updates
- Risk of "testing for coverage" vs "testing for behavior"

**Mitigation:**
- Focus on behaviorally meaningful tests (as stated in requirements)
- Test public APIs, not private functions
- Use property-based tests for invariants
- Regular test review to eliminate brittle tests

### Coverage Gaming
**Risk: MEDIUM**
- Temptation to write "coverage tests" that assert nothing
- Tests that hit lines but don't verify behavior

**Mitigation:**
- Code review practices: reject tests without assertions
- Focus on integration tests that verify real workflows
- Test review checklist: "What bug does this test catch?"

---

## 9. Third-Party Integrations & External Services

**None** - Jido Core is self-contained. All integrations are through:
- Telemetry events (in-process)
- Phoenix.PubSub (in-process)
- Poolboy (in-process)

No external API calls, databases, or third-party services in scope for this task.

---

## 10. Unclear Areas Requiring Clarification

### 1. Coverage Scope - "Core Modules"

**Question:** Which modules are considered "core" for the 90% target?

**Options:**
- A. All modules in `projects/jido/lib/jido/` (47 modules)
- B. Only modules listed in `groups_for_modules` in mix.exs (Core, Skills, Utilities)
- C. Exclude Example modules (Actions.Arithmetic, Tools.Basic, etc.)

**Recommendation:** Option B - Focus on documented modules, exclude examples.

### 2. Integration Test Scope

**Question:** Should coverage include integration tests with:
- `jido_action` dependency?
- `jido_signal` dependency?
- Multi-agent coordination scenarios?

**Clarification Needed:** Requirements mention "integration points with external services (through mocks or adapters)" - but Jido Core has no external services. Does this mean integration with Jido ecosystem libraries?

### 3. Property-Based Testing

**Question:** Should we use `stream_data` for property-based tests?

**Context:**
- `stream_data` is in dependencies
- Ideal for state machine testing (AgentServer)
- Adds test complexity and runtime

**Decision Point:** Use for critical state machines only (AgentServer, FSM.Strategy)?

### 4. Flaky Test Handling

**Question:** How should we handle async race condition tests?

**Context:**
- Current tests have `@tag :flaky` for unreliable tests
- Excluded by default in test_helper
- Some agent timing tests may be inherently flaky

**Clarification:** Accept some flaky tests with tags, or require all tests to be deterministic?

### 5. Coverage Export Format

**Question:** Which coverage formats should CI generate?

**Current:** `export: "cov"` in mix.exs

**Options:**
- HTML reports for local development
- LCOV for CI integration
- JSON for tooling
- Terminal summary

**Clarification Needed:** Should we set up coverage reporting in GitHub Actions (PR comments, badges)?

### 6. Test Runtime Budget

**Question:** What is the acceptable test suite runtime?

**Current:** Unknown (not measured yet)
**Impact:** Determines how thorough tests can be
- < 2 minutes: Unit tests only, minimal integration
- 2-5 minutes: Unit + some integration tests
- 5-10 minutes: Comprehensive integration tests
- > 10 minutes: Consider test splitting or parallelization

**Clarification Needed:** Maximum acceptable test runtime for CI?

---

## 11. Implementation Guidance

### Phase 1: Coverage Baseline & Prioritization

1. **Generate detailed coverage report:**
   ```bash
   cd projects/jido
   mix test.coverage
   open cover/excoveralls.html
   ```

2. **Categorize modules by priority:**
   - **P0 (Critical):** 0% coverage in agent lifecycle (AgentPool, Observe, Await, Scheduler)
   - **P1 (High):** 0% coverage in Actions (Control, Lifecycle, Scheduling, Status)
   - **P2 (Medium):** 20-50% coverage (AgentServer, State, Schema)
   - **P3 (Low):** 50-80% coverage (Error, Directive, Util)

3. **Track progress:**
   - Create spreadsheet or use GitHub projects
   - Columns: Module, Current %, Target %, Test File, Status

### Phase 2: Test Writing Strategy

**For each module:**

1. **Read the source code** to understand behavior
2. **Identify public API functions** (not private helpers)
3. **Write tests for:**
   - Happy path (normal operation)
   - Error cases (invalid input, failures)
   - Edge cases (empty input, nil values)
   - Integration scenarios (with other Jido components)

4. **Follow existing patterns:**
   ```elixir
   # Use JidoTest.Case for agent tests
   use JidoTest.Case, async: true
   @moduletag :capture_log

   # Define test actions inline
   defmodule TestAction do
     use Jido.Action, name: "test", schema: []
     def run(_params, _context), do: {:ok, %{}}
   end

   # Write descriptive test names
   test "executes action and returns result", context do
     {:ok, pid} = start_test_agent(context, TestAgent)
     # Act and Assert
   end
   ```

5. **Run tests frequently:**
   ```bash
   # Test single file
   mix test test/jido/observe_test.exs

   # Test with focus
   mix test --only focus

   # Test with coverage for specific file
   mix test.coverage test/jido/observe_test.exs
   ```

### Phase 3: CI Integration

1. **Update test workflow:**
   ```yaml
   # .github/workflows/test.yml
   test_command: mix test.coverage
   ```

2. **Add coverage reporting (optional):**
   - ExCoveralls GitHub Actions integration
   - Coverage badges in README
   - PR comments with coverage diff

3. **Update threshold:**
   ```elixir
   # mix.exs
   summary: [threshold: 90]  # Incrementally: 50 → 70 → 90
   ```

### Phase 4: Test Maintenance

1. **Weekly coverage audits:**
   - Check for dropped coverage
   - Remove obsolete tests
   - Refactor brittle tests

2. **Test quality metrics:**
   - Assertion density (assertions per test)
   - Test runtime (identify slow tests)
   - Flaky test tracking

---

## 12. Success Criteria

Task is complete when:

- [ ] Coverage report shows >90% for core modules
- [ ] All new tests follow existing patterns (JidoTest.Case, async: true)
- [ ] Tests verify behavior, not just coverage (code review required)
- [ ] CI workflow updated to run `mix test.coverage`
- [ ] Coverage threshold in mix.exs updated to 90%
- [ ] Test suite runtime < 10 minutes (to be determined)
- [ ] No tests marked `:flaky` without justification
- [ ] Coverage gaps documented with rationale (if any modules remain <90%)

---

## 13. Next Steps for Planning Phase

1. **Clarify scope questions** (Section 10 above)
2. **Define test writing guidelines** for the team
3. **Set up tracking** for coverage progress
4. **Prioritize module order** based on criticality
5. **Allocate time estimates** per module (based on complexity)
6. **Plan CI/CD updates** for coverage enforcement
7. **Define "done" criteria** for test quality

---

## 14. Documentation References

**Testing Framework:**
- 📖 [ExUnit docs](https://hexdocs.pm/ex_unit/ExUnit.html)
- 📖 [ExUnit.Case docs](https://hexdocs.pm/ex_unit/ExUnit.Case.html)
- 📖 [ExUnit.Callbacks docs](https://hexdocs.pm/ex_unit/ExUnit.Callbacks.html)

**Coverage Tools:**
- 📖 [ExCoveralls docs](https://hexdocs.pm/excoveralls/)
- 📖 [ExCoveralls GitHub Actions](https://github.com/paradoxical/excoveralls#github-actions-continuous-integration)

**Property-Based Testing:**
- 📖 [StreamData docs](https://hexdocs.pm/stream_data/)
- 📖 [Property-Based Testing guide](https://hexdocs.pm/stream_data/introduction_to_property_based_testing.html)

**Mocking:**
- 📖 [Mimic docs](https://hexdocs.pm/mimic/Mimic.html)
- 📖 [Testing with Mimic](https://github.com/edgurgel/mimic#testing)

**Jido Testing Guide:**
- 📖 [projects/jido/guides/testing.md](https://github.com/agentjido/jido/blob/main/guides/testing.md)

**Elixir Testing Best Practices:**
- 📖 [Elixir School - Testing](https://elixirschool.com/en/lessons/basics/testing/)
- 📖 [Testing Anti-Patterns](https://blog.drewolson.org/elixir-testing-anti-patterns/)

# Feature: WS-1.6 Phase 1 Integration Tests

## Problem Statement

Phase 1 (Session Foundation) has comprehensive unit tests for each component, but lacks integration tests that verify all components work together correctly. Before proceeding to Phase 2, we need confidence that:

- Session lifecycle works end-to-end
- Multiple sessions can coexist without interference
- The 10-session limit is enforced correctly
- SessionRegistry and SessionSupervisor stay synchronized
- Child processes are accessible through Session.Supervisor

## Solution Overview

Create a comprehensive integration test suite in `test/jido_code/integration/session_phase1_test.exs` that tests all Phase 1 components working together.

## Implementation Plan

### Task 1.6.1: Session Lifecycle Integration
- [ ] Create test file with proper setup/teardown
- [ ] Test: Create session → verify in Registry → verify processes running → stop → verify cleanup
- [ ] Test: Create session with custom config → verify config propagated
- [ ] Test: Update session in Registry → verify updated_at changes
- [ ] Test: Rename session → verify Registry updated
- [ ] Test: Session process crash → verify restart → verify Registry intact

### Task 1.6.2: Multi-Session Integration
- [ ] Test: Create 3 sessions → verify all in Registry → verify all processes running
- [ ] Test: Create sessions for different paths → verify isolation
- [ ] Test: Stop one session → verify others unaffected
- [ ] Test: Lookup by ID, path, and name all work correctly
- [ ] Test: list_all/0 returns all sessions sorted by created_at

### Task 1.6.3: Session Limit Integration
- [ ] Test: Create exactly 10 sessions → all succeed
- [ ] Test: Create 11th session → fails with :session_limit_reached
- [ ] Test: At limit → stop one → create new → succeeds
- [ ] Test: Duplicate path rejected even when under limit
- [ ] Test: Duplicate ID rejected (edge case)

### Task 1.6.4: Registry-Supervisor Coordination
- [ ] Test: Session registered in Registry before processes start
- [ ] Test: Session unregistered from Registry after processes stop
- [ ] Test: Registry count matches DynamicSupervisor child count
- [ ] Test: find_session_pid/1 returns correct pid
- [ ] Test: session_running?/1 matches Registry state
- [ ] Test: Cleanup on partial failure

### Task 1.6.5: Child Process Access Integration
- [ ] Test: get_manager/1 returns live Manager pid
- [ ] Test: get_state/1 returns live State pid
- [ ] Test: Child pids are different for different sessions
- [ ] Test: Child pids change after supervisor restart
- [ ] Test: get_manager/1 returns error for stopped session

## Technical Details

### Test Setup

```elixir
setup do
  # Use application's infrastructure (already running)
  # Clear any existing test sessions
  SessionRegistry.clear()

  # Create temp directories for test sessions
  tmp_base = Path.join(System.tmp_dir!(), "integration_test_#{:rand.uniform(100_000)}")
  File.mkdir_p!(tmp_base)

  on_exit(fn ->
    # Stop all test sessions
    for session <- SessionRegistry.list_all() do
      SessionSupervisor.stop_session(session.id)
    end
    SessionRegistry.clear()
    File.rm_rf!(tmp_base)
  end)

  {:ok, tmp_base: tmp_base}
end
```

### Helper Functions

```elixir
defp create_test_dir(base, name) do
  path = Path.join(base, name)
  File.mkdir_p!(path)
  path
end

defp wait_for_process_death(pid, timeout \\ 1000) do
  ref = Process.monitor(pid)
  receive do
    {:DOWN, ^ref, :process, ^pid, _} -> :ok
  after
    timeout -> {:error, :timeout}
  end
end
```

## Success Criteria

- [x] All 5 tasks (1.6.1-1.6.5) complete
- [x] All integration tests pass (26 tests, 0 failures)
- [x] Tests are deterministic (no flakiness)
- [x] Tests run in < 10 seconds total (0.9 seconds)
- [x] No regressions in existing tests

## Current Status

**Status**: Complete

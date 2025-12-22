# Feature Plan: Multi-Session Persistence Integration Tests (Task 6.7.5)

**Task:** 6.7.5 - Multi-Session Persistence Integration Tests
**Phase:** Phase 6 - Session Persistence
**Date:** 2025-12-10
**Status:** Planning Complete, Ready for Implementation

---

## Problem Statement

### What Problem Are We Solving?

The persistence system needs to handle multiple concurrent saved sessions correctly. However, we need **integration tests** that verify:

1. **Multiple Sessions Listed**: Close 3 sessions → all appear in resumable list
2. **Selective Resume**: Resume one session → remaining sessions still resumable
3. **Sorting**: Sessions sorted by closed_at (most recent first)
4. **Filtering**: Active sessions excluded from resumable list
5. **Multi-Session Workflows**: Complete workflows with multiple sessions

**Current Test Coverage:**
- ✅ `list_persisted` with 3 sessions (line 360-385)
- ✅ Multiple save-resume cycles for ONE session (line 260-289)
- ✅ Active session filtering (session_phase6_test.exs)
- ❌ **Missing**: `/resume` command behavior with multiple sessions
- ❌ **Missing**: Sorting verification
- ❌ **Missing**: Selective resume with remaining sessions

**Impact:**
- Without these tests, multi-session scenarios could have bugs
- Sorting might not work correctly
- Resume might not properly filter/update lists
- No guarantee system handles concurrent sessions well

---

## Solution Overview

### High-Level Approach

Add comprehensive integration tests to verify the persistence system handles multiple sessions correctly. These tests will focus on **realistic multi-session workflows** at the Commands level, not just the Persistence layer.

### Key Design Decisions

**Decision 1: Test at Commands Module Level**
- **Choice:** Test `Commands.execute_resume` with multiple sessions
- **Rationale:**
  - Task 6.7.3 established pattern of testing Commands level
  - Commands.execute_resume calls Persistence.list_resumable
  - Verifies end-to-end flow users actually experience
  - Consistent with existing test organization

**Decision 2: Add to commands_test.exs**
- **Choice:** Add tests to commands_test.exs where Task 6.7.3 tests are
- **Rationale:**
  - All `/resume` command tests in one place
  - Reuses session creation helpers from Task 6.7.3
  - Consistent organization
  - NOT in session_phase6_test.exs (which tests Persistence layer directly)

**Decision 3: Focus on Multi-Session Scenarios**
- **Choice:** Test realistic workflows with 3+ sessions
- **Rationale:**
  - Single session already tested
  - Need to verify system scales to multiple sessions
  - Common user scenario: multiple project sessions saved
  - Edge cases around sorting/filtering

**Decision 4: Verify Sorting Explicitly**
- **Choice:** Create sessions with controlled timestamps, verify order
- **Rationale:**
  - Sorting by closed_at is user-facing requirement
  - Most recent first is expected behavior
  - Need to verify implementation matches spec

---

## Technical Details

### Commands Module Integration

**Location:** `lib/jido_code/commands.ex`

**Function Tested:** `execute_resume(:list, _model)` (lines 585-591)
```elixir
def execute_resume(:list, _model) do
  alias JidoCode.Session.Persistence

  sessions = Persistence.list_resumable()
  message = format_resumable_list(sessions)
  {:ok, message}
end
```

**What list_resumable Does:**
- Gets all persisted sessions via `list_persisted()`
- Filters out sessions for active projects
- Returns list of session metadata maps
- Sorting happens in `format_resumable_list`

### Sorting Implementation

**Location:** `lib/jido_code/commands.ex` lines 659-691

```elixir
defp format_resumable_list(sessions) do
  # ... sorting and formatting
end
```

Need to verify this sorts by `closed_at` descending (most recent first).

### Test Infrastructure

**From Task 6.7.3** (commands_test.exs):
- `create_and_close_session/2` - Creates, populates, closes session
- `wait_for_persisted_file/2` - Polls for file creation
- Setup with API key, temp directories, cleanup

**Additional Need:**
- Way to control `closed_at` timestamps for sorting tests
- Helper to create sessions with specific close times

---

## Implementation Plan

### Step 1: Test Multiple Sessions in List

**Test Goal:** Verify 3 closed sessions all appear in `/resume` list

**Implementation:**
```elixir
describe "/resume command - multiple sessions" do
  setup do
    # Same setup as Task 6.7.3
    System.put_env("ANTHROPIC_API_KEY", "test-key-multi-session")
    {:ok, _} = Application.ensure_all_started(:jido_code)

    tmp_base = Path.join(System.tmp_dir!(), "multi_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_base)

    on_exit(fn ->
      # Cleanup
      for session <- SessionRegistry.list_all() do
        SessionSupervisor.stop_session(session.id)
      end
      File.rm_rf!(tmp_base)
      if File.exists?(Persistence.sessions_dir()), do: File.rm_rf!(Persistence.sessions_dir())
    end)

    {:ok, tmp_base: tmp_base}
  end

  test "lists all closed sessions", %{tmp_base: tmp_base} do
    # Create 3 projects
    projects = for i <- 1..3 do
      project = Path.join(tmp_base, "project#{i}")
      File.mkdir_p!(project)
      project
    end

    # Create and close 3 sessions
    _sessions = for {project, i} <- Enum.with_index(projects, 1) do
      create_and_close_session("Session #{i}", project)
    end

    # List resumable sessions
    result = Commands.execute_resume(:list, %{})

    # Verify all 3 appear
    assert {:ok, message} = result
    assert message =~ "Session 1"
    assert message =~ "Session 2"
    assert message =~ "Session 3"
  end
end
```

**Assertions:**
- All 3 session names in message
- Message format correct
- No crashes/errors

---

### Step 2: Test Selective Resume

**Test Goal:** Resume one session → other 2 still in list

**Implementation:**
```elixir
test "resuming one session leaves others in list", %{tmp_base: tmp_base} do
  # Create 3 projects
  projects = for i <- 1..3 do
    project = Path.join(tmp_base, "project#{i}")
    File.mkdir_p!(project)
    project
  end

  # Create and close 3 sessions
  sessions = for {project, i} <- Enum.with_index(projects, 1) do
    create_and_close_session("Session #{i}", project)
  end

  # Resume first session
  result = Commands.execute_resume({:restore, "1"}, %{})
  assert {:session_action, {:add_session, _resumed}} = result

  # List remaining resumable sessions
  list_result = Commands.execute_resume(:list, %{})
  assert {:ok, message} = list_result

  # Verify 2 remaining (not the resumed one)
  assert message =~ "Session 2"
  assert message =~ "Session 3"
  # Session 1 should NOT be in list (it's now active)
  refute message =~ "Session 1"
end
```

**Assertions:**
- Resume successful
- Remaining sessions still listed
- Resumed session NOT in list

---

### Step 3: Test Sorting by closed_at

**Test Goal:** Verify sessions sorted most recent first

**Implementation:**
```elixir
test "sessions sorted by closed_at (most recent first)", %{tmp_base: tmp_base} do
  # Create 3 projects
  projects = for i <- 1..3 do
    project = Path.join(tmp_base, "project#{i}")
    File.mkdir_p!(project)
    project
  end

  # Create and close sessions with delays
  for {project, i} <- Enum.with_index(projects, 1) do
    create_and_close_session("Session #{i}", project)
    # Small delay to ensure different closed_at times
    Process.sleep(100)
  end

  # List sessions
  result = Commands.execute_resume(:list, %{})
  assert {:ok, message} = result

  # Verify order - Session 3 should appear before Session 1
  # (most recent closed appears first)
  session3_pos = :binary.match(message, "Session 3") |> elem(0)
  session2_pos = :binary.match(message, "Session 2") |> elem(0)
  session1_pos = :binary.match(message, "Session 1") |> elem(0)

  assert session3_pos < session2_pos
  assert session2_pos < session1_pos
end
```

**Assertions:**
- Most recent (Session 3) appears first
- Oldest (Session 1) appears last
- Middle session in middle position

---

### Step 4: Test Active Session Filtering

**Test Goal:** Active sessions excluded from resumable list

**Implementation:**
```elixir
test "active sessions excluded from resumable list", %{tmp_base: tmp_base} do
  # Create 3 projects
  projects = for i <- 1..3 do
    project = Path.join(tmp_base, "project#{i}")
    File.mkdir_p!(project)
    project
  end

  # Create and close 3 sessions
  for {project, i} <- Enum.with_index(projects, 1) do
    create_and_close_session("Session #{i}", project)
  end

  # Resume session 2 (making it active)
  result = Commands.execute_resume({:restore, "2"}, %{})
  assert {:session_action, {:add_session, _}} = result

  # List resumable
  list_result = Commands.execute_resume(:list, %{})
  assert {:ok, message} = list_result

  # Should show 1 and 3, but NOT 2 (active)
  assert message =~ "Session 1"
  assert message =~ "Session 3"
  refute message =~ "Session 2"
end
```

**Assertions:**
- Closed sessions appear
- Active session does NOT appear
- Count correct (2 resumable, not 3)

---

## Success Criteria

### Tests Implemented ✅

- [ ] Test 1: Lists all closed sessions (3 sessions)
- [ ] Test 2: Resuming one leaves others in list
- [ ] Test 3: Sessions sorted by closed_at (most recent first)
- [ ] Test 4: Active sessions excluded from list

**Total:** 4 comprehensive multi-session integration tests

### Test Results ✅

- [ ] All new tests passing (4/4)
- [ ] All existing tests still passing (145 commands, 21 phase6)
- [ ] No compilation warnings
- [ ] Execution time reasonable

### Documentation ✅

- [ ] Feature plan written (this document)
- [ ] Implementation summary written
- [ ] Phase plan updated (Task 6.7.5 marked complete)

---

## Testing Approach

### Test Categories

**1. Coverage Tests (1 test):**
- Lists all closed sessions (Test 1)

**2. State Management Tests (1 test):**
- Selective resume (Test 2)

**3. Sorting Tests (1 test):**
- closed_at ordering (Test 3)

**4. Filtering Tests (1 test):**
- Active exclusion (Test 4)

### Assertion Strategy

**Listing:**
- Execute `Commands.execute_resume(:list, %{})`
- Verify `{:ok, message}` returned
- Check message contains expected session names
- Use string matching for presence/absence

**Ordering:**
- Use `:binary.match` to find positions in message
- Compare positions to verify order
- Most recent should have lowest position

**State Changes:**
- Resume session
- Re-list to verify changes
- Check counts and names

---

## Notes and Considerations

### Scope Clarification

**What is Tested:**
- `/resume` command with multiple sessions
- Listing behavior
- Sorting by closed_at
- Filtering of active sessions
- Selective resume impact on list

**What is NOT Tested (Already Covered):**
- Persistence.list_persisted with multiple sessions (Task 6.7.1)
- Single session workflows (Task 6.7.3)
- File format (Task 6.7.4)

**Rationale:** Focus on multi-session WORKFLOWS, not single-session or unit-level behavior.

### Dependencies

**Requires (Already Complete):**
- Task 6.7.3: `/resume` command tests and helpers

**Provides:**
- Multi-session workflow verification
- Sorting validation
- Filtering correctness proof

### Timing Considerations

**Sorting Test Challenge:**
- Need different closed_at timestamps
- Use `Process.sleep(100)` between closes
- 100ms should be sufficient for distinct timestamps
- Alternative: Manually set timestamps (more complex)

---

## Implementation Status

**Phase:** Planning Complete ✅
**Next Step:** Implement Test 1 (list all closed sessions)
**Current Branch:** feature/ws-6.7.5-multi-session-persistence

---

**End of Feature Plan**

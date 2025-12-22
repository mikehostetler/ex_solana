# Feature Plan: Cleanup Integration Tests (Task 6.7.6)

**Task:** 6.7.6 - Cleanup Integration Tests
**Phase:** Phase 6 - Session Persistence
**Date:** 2025-12-10
**Status:** Planning Complete, Ready for Implementation

---

## Problem Statement

### What Problem Are We Solving?

The persistence system has cleanup functionality (`/resume delete`, `/resume clear`, `Persistence.cleanup/1`) but lacks **integration tests** that verify cleanup works correctly in real-world scenarios with active sessions.

**Current Test Coverage:**
- ✅ `/resume delete` command tests (commands_test.exs:1432-1570) - 12 tests
- ✅ `/resume clear` command tests (commands_test.exs:1603-1678) - 4 tests
- ✅ `Persistence.cleanup/1` unit test (session_phase6_test.exs:329-358) - 1 test
- ❌ **Missing**: Integration tests verifying cleanup doesn't affect active sessions
- ❌ **Missing**: Integration test for `/resume delete` with active sessions
- ❌ **Missing**: Integration test for `/resume clear` with active sessions
- ❌ **Missing**: Integration test for automatic cleanup preserving active session data

**Impact:**
- Without integration tests, cleanup could accidentally affect active sessions
- No guarantee that deleting persisted session doesn't corrupt active session state
- Clearing all sessions might interfere with running sessions
- Automatic cleanup might delete sessions that are currently active

---

## Solution Overview

### High-Level Approach

Add integration tests that verify cleanup operations (delete, clear, automatic cleanup) work correctly when active sessions exist. Tests will create both active and persisted sessions, perform cleanup, then verify:
1. Persisted files are deleted as expected
2. Active sessions continue to function normally
3. Active session state is not corrupted

### Key Design Decisions

**Decision 1: Add to `/resume command integration` describe block**
- **Choice:** Add tests to existing integration test section in commands_test.exs
- **Rationale:**
  - Existing `/resume command integration` block (lines 1684-1960) tests resume workflows
  - Cleanup is part of resume command family
  - Reuses existing helpers (create_and_close_session, wait_for_supervisor)
  - Consistent organization

**Decision 2: Test Active Session Isolation**
- **Choice:** Focus on verifying cleanup doesn't affect active sessions
- **Rationale:**
  - This is the critical integration gap
  - Unit tests already cover basic deletion
  - Integration value is in multi-session scenarios
  - Prevents regression bugs

**Decision 3: Reuse Existing Unit Tests for Coverage**
- **Choice:** Don't duplicate existing `/resume delete` and `/resume clear` tests
- **Rationale:**
  - 16 existing tests already cover command parsing, error cases, idempotency
  - Integration tests should focus on **interaction** between active and persisted sessions
  - Avoid test bloat and maintenance burden

---

## Technical Details

### Commands Module Functions

**Location:** `lib/jido_code/commands.ex`

#### `/resume delete` (lines 632-652)
```elixir
def execute_resume({:delete, target}, _model) do
  sessions = Persistence.list_resumable()

  case resolve_resume_target(target, sessions) do
    {:ok, session_id} ->
      case Persistence.delete_persisted(session_id) do
        :ok -> {:ok, "Deleted saved session."}
        {:error, reason} -> {:error, "Failed to delete: #{inspect(reason)}"}
      end
    {:error, reason} -> {:error, reason}
  end
end
```

**Key Behavior:**
- Lists resumable sessions (excludes active)
- Resolves target (index or UUID)
- Deletes persisted file
- Does NOT touch active sessions

#### `/resume clear` (lines 653-670)
```elixir
def execute_resume(:clear, _model) do
  sessions = Persistence.list_persisted()
  count = length(sessions)

  if count > 0 do
    Enum.each(sessions, fn session ->
      Persistence.delete_persisted(session.id)
    end)
    {:ok, "Cleared #{count} saved session(s)."}
  else
    {:ok, "No saved sessions to clear."}
  end
end
```

**Key Behavior:**
- Lists ALL persisted sessions (includes active)
- Deletes all persisted files
- Does NOT stop active sessions

### Persistence Module Function

**Location:** `lib/jido_code/session/persistence.ex`

#### `cleanup/1` (lines 671-732)
```elixir
def cleanup(max_age_days \\ 30) do
  cutoff = DateTime.add(DateTime.utc_now(), -max_age_days * 86400, :second)
  sessions = list_persisted()

  # Deletes sessions with closed_at older than cutoff
  # Returns %{deleted: n, skipped: n, failed: n, errors: [...]}
end
```

**Key Behavior:**
- Filters by `closed_at` timestamp
- Deletes old persisted files
- Returns statistics map

### Critical Integration Point

**Active sessions have persisted files:**
- When session created, no file exists
- When session closed, auto-save creates file
- If session resumed, file deleted
- **BUT**: If session closed, file created, then session resumed AGAIN via create_session (not resume), file remains!

**Test Scenario:**
1. Create session A, close it → file A created
2. Create session B (different project), leave active → no file B
3. `/resume clear` → deletes file A
4. Session B should still work → verify state intact

---

## Implementation Plan

### Step 1: Test `/resume delete` doesn't affect active sessions

**Test Goal:** Delete persisted session while active session exists, verify active unaffected

**Implementation:**
```elixir
test "delete command doesn't affect active sessions", %{tmp_base: tmp_base} do
  # Create and close session 1 (persisted)
  project1 = Path.join(tmp_base, "project1")
  File.mkdir_p!(project1)
  _closed_session = create_and_close_session("Closed Session", project1)

  # Create session 2 and keep active
  project2 = Path.join(tmp_base, "project2")
  File.mkdir_p!(project2)
  {:ok, active_session} = SessionSupervisor.create_session(
    project_path: project2,
    name: "Active Session",
    config: test_config()
  )

  # Add state to active session
  test_message = %{
    id: "msg-1",
    role: :user,
    content: "Test message",
    timestamp: DateTime.utc_now()
  }
  Session.State.append_message(active_session.id, test_message)

  # Delete closed session
  result = Commands.execute_resume({:delete, "1"}, %{})
  assert {:ok, "Deleted saved session."} = result

  # Verify active session still works
  assert {:ok, session} = SessionRegistry.lookup(active_session.id)
  assert session.name == "Active Session"

  # Verify active session state intact
  {:ok, messages} = Session.State.get_messages(active_session.id)
  assert Enum.any?(messages, fn m -> m["content"] == "Test message" end)
end
```

**Assertions:**
- Delete succeeds
- Active session still in registry
- Active session state (messages) intact

---

### Step 2: Test `/resume clear` doesn't affect active sessions

**Test Goal:** Clear all persisted files while active sessions exist

**Implementation:**
```elixir
test "clear command doesn't affect active sessions", %{tmp_base: tmp_base} do
  # Create and close 2 sessions (persisted)
  project1 = Path.join(tmp_base, "project1")
  project2 = Path.join(tmp_base, "project2")
  File.mkdir_p!(project1)
  File.mkdir_p!(project2)

  _closed1 = create_and_close_session("Closed 1", project1)
  _closed2 = create_and_close_session("Closed 2", project2)

  # Create active session
  project3 = Path.join(tmp_base, "project3")
  File.mkdir_p!(project3)
  {:ok, active} = SessionSupervisor.create_session(
    project_path: project3,
    name: "Active",
    config: test_config()
  )

  # Add todos to active session
  todos = [
    %{content: "Task 1", status: :pending, active_form: "Working on task 1"}
  ]
  Session.State.update_todos(active.id, todos)

  # Clear all persisted sessions
  result = Commands.execute_resume(:clear, %{})
  assert {:ok, message} = result
  assert message =~ "Cleared 2"

  # Verify active session still works
  assert {:ok, _} = SessionRegistry.lookup(active.id)

  # Verify active session state intact
  {:ok, active_todos} = Session.State.get_todos(active.id)
  assert length(active_todos) == 1
  assert Enum.at(active_todos, 0)["content"] == "Task 1"
end
```

**Assertions:**
- Clear reports correct count (2)
- Active session still in registry
- Active session todos intact

---

### Step 3: Test automatic cleanup doesn't affect active sessions

**Test Goal:** Run `Persistence.cleanup/1` with active sessions, verify no corruption

**Implementation:**
```elixir
test "automatic cleanup doesn't affect active sessions", %{tmp_base: tmp_base} do
  # Create and close old session (>30 days)
  project1 = Path.join(tmp_base, "project1")
  File.mkdir_p!(project1)
  old_session = create_and_close_session("Old Session", project1)

  # Modify file timestamp to be 31 days old
  old_file = Path.join(Persistence.sessions_dir(), "#{old_session.id}.json")
  wait_for_persisted_file(old_file)

  {:ok, data} = File.read(old_file)
  {:ok, json} = Jason.decode(data)
  old_time = DateTime.add(DateTime.utc_now(), -31 * 86400, :second)
  modified_json = Map.put(json, "closed_at", DateTime.to_iso8601(old_time))
  File.write!(old_file, Jason.encode!(modified_json))

  # Create active session
  project2 = Path.join(tmp_base, "project2")
  File.mkdir_p!(project2)
  {:ok, active} = SessionSupervisor.create_session(
    project_path: project2,
    name: "Active",
    config: test_config()
  )

  # Add both messages and todos to active
  Session.State.append_message(active.id, %{
    id: "msg-1",
    role: :user,
    content: "Active message",
    timestamp: DateTime.utc_now()
  })
  Session.State.update_todos(active.id, [
    %{content: "Active task", status: :pending, active_form: "Working"}
  ])

  # Run cleanup (30 days)
  result = Persistence.cleanup(30)

  # Verify old session deleted
  assert result.deleted == 1
  refute File.exists?(old_file)

  # Verify active session unaffected
  assert {:ok, _} = SessionRegistry.lookup(active.id)
  {:ok, messages} = Session.State.get_messages(active.id)
  {:ok, todos} = Session.State.get_todos(active.id)

  assert Enum.any?(messages, fn m -> m["content"] == "Active message" end)
  assert length(todos) == 1
end
```

**Assertions:**
- Cleanup deletes old session (deleted == 1)
- Old file removed
- Active session in registry
- Active messages intact
- Active todos intact

---

### Step 4: Test cleanup with active session that has persisted file

**Test Goal:** Edge case - active session exists AND has persisted file (closed then recreated)

**Implementation:**
```elixir
test "cleanup with active session having persisted file", %{tmp_base: tmp_base} do
  project = Path.join(tmp_base, "project1")
  File.mkdir_p!(project)

  # Create, add data, and close session (creates file)
  {:ok, session} = SessionSupervisor.create_session(
    project_path: project,
    name: "Test Session",
    config: test_config()
  )
  session_id = session.id

  Session.State.append_message(session_id, %{
    id: "msg-1",
    role: :user,
    content: "Original message",
    timestamp: DateTime.utc_now()
  })

  :ok = SessionSupervisor.stop_session(session_id)

  # Wait for file
  file = Path.join(Persistence.sessions_dir(), "#{session_id}.json")
  wait_for_persisted_file(file)

  # Modify file to be 31 days old
  {:ok, data} = File.read(file)
  {:ok, json} = Jason.decode(data)
  old_time = DateTime.add(DateTime.utc_now(), -31 * 86400, :second)
  modified_json = Map.put(json, "closed_at", DateTime.to_iso8601(old_time))
  File.write!(file, Jason.encode!(modified_json))

  # Recreate session at same path (simulates user returning to project)
  {:ok, new_session} = SessionSupervisor.create_session(
    project_path: project,
    name: "Test Session",
    config: test_config()
  )
  new_id = new_session.id

  # Add NEW data to active session
  Session.State.append_message(new_id, %{
    id: "msg-2",
    role: :user,
    content: "New message",
    timestamp: DateTime.utc_now()
  })

  # Run cleanup - should delete OLD file
  result = Persistence.cleanup(30)

  # Old file should be deleted (it's >30 days old)
  assert result.deleted == 1
  refute File.exists?(file)

  # New active session should be unaffected
  assert {:ok, _} = SessionRegistry.lookup(new_id)
  {:ok, messages} = Session.State.get_messages(new_id)
  assert Enum.any?(messages, fn m -> m["content"] == "New message" end)
end
```

**Assertions:**
- Cleanup deletes old persisted file
- New active session unaffected
- New session state intact

---

## Success Criteria

### Tests Implemented ✅

- [ ] Test 1: `/resume delete` doesn't affect active sessions
- [ ] Test 2: `/resume clear` doesn't affect active sessions
- [ ] Test 3: Automatic cleanup doesn't affect active sessions
- [ ] Test 4: Cleanup with active session having persisted file (edge case)

**Total:** 4 comprehensive cleanup integration tests

### Test Results ✅

- [ ] All new tests passing (4/4)
- [ ] All existing tests still passing (149 commands, 21 phase6)
- [ ] No compilation warnings
- [ ] Execution time reasonable

### Documentation ✅

- [ ] Feature plan written (this document)
- [ ] Implementation summary written
- [ ] Phase plan updated (Task 6.7.6 marked complete)

---

## Testing Approach

### Test Categories

**1. Command Isolation Tests (2 tests):**
- Delete doesn't affect active (Test 1)
- Clear doesn't affect active (Test 2)

**2. Automatic Cleanup Tests (2 tests):**
- Cleanup doesn't affect active (Test 3)
- Cleanup with persisted file collision (Test 4)

### Assertion Strategy

**Active Session Verification:**
- Check SessionRegistry.lookup succeeds
- Verify session name matches
- Read state (messages, todos) and verify content

**Cleanup Verification:**
- Check file deletion (File.exists?)
- Verify return values (deleted count, messages)
- Confirm persisted sessions removed from list

**State Integrity:**
- Read messages via Session.State.get_messages
- Read todos via Session.State.get_todos
- Use pattern matching to find expected data

---

## Test Infrastructure

### Setup (Reuse from `/resume command integration`)

From commands_test.exs lines 1685-1718:
- Set ANTHROPIC_API_KEY
- Start application
- Wait for SessionSupervisor
- Clear SessionRegistry
- Create temp directories
- Cleanup on_exit

### Helper Functions (Reuse)

From commands_test.exs lines 1910-1959:
- `create_and_close_session/2` - Create, populate, close, wait for file
- `wait_for_persisted_file/2` - Poll for file creation
- `wait_for_supervisor/1` - Wait for supervisor availability

### Additional Helpers Needed

```elixir
defp test_config do
  %{
    provider: "anthropic",
    model: "claude-3-5-haiku-20241022",
    temperature: 0.7,
    max_tokens: 4096
  }
end
```

---

## Notes and Considerations

### Scope Clarification

**What is Tested:**
- Cleanup commands (`/resume delete`, `/resume clear`) with active sessions
- Automatic cleanup (`Persistence.cleanup/1`) with active sessions
- State integrity after cleanup operations
- Edge case: persisted file exists for active session

**What is NOT Tested (Already Covered):**
- Command parsing (existing unit tests)
- Error cases (existing unit tests)
- Basic deletion logic (existing unit tests)
- Single-session cleanup (existing unit test)

**Rationale:** Focus on **integration** - interaction between active and persisted sessions.

### Dependencies

**Requires (Already Complete):**
- Task 6.7.3: `/resume` command helpers
- Task 6.7.5: Multi-session test patterns

**Provides:**
- Cleanup integration verification
- Active session isolation proof
- Complete integration test coverage for Section 6.7

### Edge Cases

**Edge Case 1: Active session with stale persisted file**
- Scenario: Session closed (file created), then session recreated at same path
- Test 4 covers this
- File should be deletable without affecting active session

**Edge Case 2: Session closed, cleaned up, then resumed**
- Not an integration concern (resume will fail gracefully)
- Already covered by existing resume error tests

**Edge Case 3: Cleanup during session close**
- Race condition: session closing (writing file) while cleanup runs
- Not critical: cleanup will skip or delete based on timestamp
- File write is atomic (File.write!)

---

## Implementation Status

**Phase:** Planning Complete ✅
**Next Step:** Implement Test 1 (delete doesn't affect active)
**Current Branch:** feature/ws-6.7.6-cleanup-integration

---

**End of Feature Plan**

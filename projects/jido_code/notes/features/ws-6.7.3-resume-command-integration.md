# Feature Plan: Resume Command Integration Tests (Task 6.7.3)

**Task:** 6.7.3 - Resume Command Integration Tests
**Phase:** Phase 6 - Session Persistence
**Date:** 2025-12-10
**Status:** Planning Complete, Ready for Implementation

---

## Problem Statement

### What Problem Are We Solving?

The `/resume` command was implemented in earlier Phase 6 tasks to allow users to list and restore closed sessions. However, we currently lack **integration tests** that verify:

1. `/resume` (no args) correctly lists resumable sessions
2. `/resume <target>` (index or UUID) correctly resumes the selected session
3. Error handling for edge cases (session limit, deleted paths, already open)
4. Command parsing and execution work end-to-end
5. Integration between Commands module and Persistence module

**Current Test Coverage:**
- ✅ Task 6.7.1: Persistence.resume/1 and list_resumable/0 tested (unit level)
- ✅ Task 6.7.2: Auto-save on close tested (SessionSupervisor level)
- ❌ **Missing**: `/resume` command parsing and execution (Commands module level)
- ❌ **Missing**: Error handling for edge cases (session limit, project deleted, already open)

**Impact:**
- Without these tests, `/resume` command regressions could go unnoticed
- Edge cases might not be handled correctly
- Integration between Commands and Persistence not verified
- TUI behavior depends on correct command return values

---

## Solution Overview

### High-Level Approach

Add comprehensive integration tests to verify the `/resume` command works correctly end-to-end at the **Commands module level**. These tests will:

1. **Test Command Parsing**
   - `/resume` → list resumable sessions
   - `/resume 1` → resume by index
   - `/resume <uuid>` → resume by UUID
   - `/resume list` → explicit list command

2. **Test Command Execution**
   - Verify Commands.execute_resume/2 returns correct values
   - Verify integration with Persistence.list_resumable/0
   - Verify integration with Persistence.resume/1
   - Verify error handling for edge cases

3. **Test Error Scenarios**
   - Session limit reached (10 session max)
   - Project path deleted
   - Project already open (duplicate detection)
   - Invalid targets (non-existent index/UUID)

4. **Verify Return Values**
   - List returns {:ok, formatted_message} with session details
   - Resume returns {:resume, session_id} for TUI to handle
   - Errors return {:error, reason} with user-friendly messages

### Key Design Decisions

**Decision 1: Test at Commands Module Level, Not TUI Level**
- **Choice:** Test Commands.execute_resume/2 directly
- **Rationale:**
  - TUI integration tests would require TermUI runtime and complex setup
  - Commands module is the integration point between TUI and Persistence
  - Can verify command behavior without full TUI stack
  - Matches pattern from existing commands_test.exs tests
- **Scope:** Test command parsing, execution, and return values (not TUI rendering)

**Decision 2: Add Tests to Existing commands_test.exs**
- **Choice:** Add new describe block to commands_test.exs
- **Rationale:**
  - File already has `/resume delete` and `/resume clear` tests
  - Keeps all `/resume` command tests together
  - Reuses existing test infrastructure (helpers, setup)
  - Consistent with existing command test patterns

**Decision 3: Create Test Sessions via SessionSupervisor**
- **Choice:** Use SessionSupervisor.create_session and stop_session to set up test data
- **Rationale:**
  - Need real closed sessions for list_resumable to find
  - Matches integration test approach from session_phase6_test.exs
  - Tests real workflow: create → close → list → resume

**Decision 4: Test Error Cases Explicitly**
- **Choice:** Create separate tests for each error scenario
- **Rationale:**
  - Clear test names describe expected behavior
  - Easy to debug when specific error case fails
  - Documents all edge cases that must be handled

---

## Technical Details

### Resume Command Flow (Code Locations)

#### 1. Command Parsing
**Location:** `lib/jido_code/commands.ex` lines 198-202

```elixir
# /resume with optional target (index, UUID, or "list")
defp parse_and_execute("/resume" <> rest, config) do
  target = String.trim(rest)
  {:resume, if(target == "", do: :list, else: target)}
end
```

**Flow:**
- `/resume` → `{:resume, :list}`
- `/resume 1` → `{:resume, "1"}`
- `/resume <uuid>` → `{:resume, "<uuid>"}`
- `/resume list` → `{:resume, "list"}`

#### 2. Command Execution
**Location:** `lib/jido_code/commands.ex` lines 574-652

```elixir
def execute_resume(:list, _model) do
  # List resumable sessions with formatting
end

def execute_resume(target, _model) when is_binary(target) do
  # Resume specific session by index or UUID
end
```

**Return Values:**
- **List:** `{:ok, formatted_message}` - String with session list
- **Resume:** `{:resume, session_id}` - Tuple for TUI to handle
- **Error:** `{:error, reason}` - Error tuple with reason atom or string

#### 3. Persistence Integration
**Functions Used:**
- `Persistence.list_resumable/0` - Get list of closed sessions (filters out active)
- `Persistence.resume/1` - Resume session by ID
- `SessionRegistry.list_all/0` - Check active sessions for limits

#### 4. Error Scenarios

**Session Limit (10 max):**
```elixir
active_count = length(SessionRegistry.list_all())
if active_count >= 10 do
  {:error, "Session limit reached (10 maximum)"}
end
```

**Project Path Deleted:**
```elixir
# Persistence.resume/1 returns:
{:error, :project_path_not_found}
```

**Project Already Open:**
```elixir
# Check if project_path already in active sessions
{:error, :project_already_open}
```

### Test Infrastructure Available

#### From commands_test.exs

**Existing Helpers:**
- `create_test_session/1` - Creates session with temp project path
- `days_ago/1` - Helper for creating old timestamps
- Setup/teardown for clean test environment

**Patterns to Follow:**
- Use describe blocks for grouping related tests
- Test both parsing and execution separately
- Use meaningful test names describing behavior

#### From session_phase6_test.exs

**Reusable Patterns:**
- Create sessions with SessionSupervisor.create_session
- Close sessions with SessionSupervisor.stop_session
- Wait for files with wait_for_file helper
- Verify persistence with Persistence.list_resumable

---

## Implementation Plan

### Overview

Since the `/resume` command tests should be in `commands_test.exs` (consistent with `/resume delete` and `/resume clear`), but we need to create and close sessions (like integration tests), we'll:

1. Add necessary setup to commands_test.exs for session creation/closing
2. Add comprehensive tests for `/resume` command variations
3. Test error scenarios explicitly

### Step 1: Add Test Setup for Session Creation

**File:** `test/jido_code/commands_test.exs`

**Action:** Add helper functions for creating and closing test sessions

```elixir
# Add to module-level helpers (around line 30-50)

defp create_and_close_test_session(name, project_path) do
  # Create session
  config = %{
    provider: "anthropic",
    model: "claude-3-5-haiku-20241022",
    temperature: 0.7,
    max_tokens: 4096
  }

  {:ok, session} = SessionSupervisor.create_session(
    project_path: project_path,
    name: name,
    config: config
  )

  # Add a message so session has content
  message = %{
    id: "test-msg-#{System.unique_integer([:positive])}",
    role: :user,
    content: "Test message",
    timestamp: DateTime.utc_now()
  }
  Session.State.append_message(session.id, message)

  # Close session (triggers auto-save)
  :ok = SessionSupervisor.stop_session(session.id)

  # Wait for file creation
  session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
  wait_for_file(session_file)

  session
end

defp wait_for_file(file_path, retries \\ 50) do
  if File.exists?(file_path) do
    :ok
  else
    if retries > 0 do
      Process.sleep(10)
      wait_for_file(file_path, retries - 1)
    else
      {:error, :timeout}
    end
  end
end
```

**Verification:** Helpers compile and can be called from tests

---

### Step 2: Test `/resume` Lists Resumable Sessions (Subtask 6.7.3.1)

**Test Goal:** Verify `/resume` (no args) lists all resumable sessions

**Implementation:**
```elixir
describe "/resume command - listing" do
  setup do
    # Set API key for test sessions
    System.put_env("ANTHROPIC_API_KEY", "test-key-for-resume-tests")

    # Ensure app started and supervisor available
    {:ok, _} = Application.ensure_all_started(:jido_code)

    # Create temp directory for test projects
    tmp_base = Path.join(System.tmp_dir!(), "resume_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_base)

    on_exit(fn ->
      # Stop all test sessions
      for session <- SessionRegistry.list_all() do
        SessionSupervisor.stop_session(session.id)
      end

      # Clean up temp dirs and session files
      File.rm_rf!(tmp_base)
      File.rm_rf!(Persistence.sessions_dir())
    end)

    {:ok, tmp_base: tmp_base}
  end

  test "lists resumable sessions when closed sessions exist", %{tmp_base: tmp_base} do
    # Create and close 2 test sessions
    project1 = Path.join(tmp_base, "project1")
    project2 = Path.join(tmp_base, "project2")
    File.mkdir_p!(project1)
    File.mkdir_p!(project2)

    _session1 = create_and_close_test_session("Project 1", project1)
    _session2 = create_and_close_test_session("Project 2", project2)

    # Execute /resume (list)
    result = Commands.execute_resume(:list, %{})

    # Verify returns {:ok, message} with session details
    assert {:ok, message} = result
    assert is_binary(message)
    assert message =~ "Project 1"
    assert message =~ "Project 2"
    assert message =~ project1
    assert message =~ project2
  end

  test "returns message when no resumable sessions", %{tmp_base: _tmp_base} do
    # No sessions created

    # Execute /resume (list)
    result = Commands.execute_resume(:list, %{})

    # Verify returns {:ok, message} indicating no sessions
    assert {:ok, message} = result
    assert message =~ "No saved sessions"
  end
end
```

**Assertions:**
- Returns `{:ok, message}` tuple
- Message contains session names and paths
- Message indicates "no sessions" when list is empty

---

### Step 3: Test `/resume <index>` Resumes by Index (Subtask 6.7.3.2)

**Test Goal:** Verify `/resume 1` resumes the first session in the list

**Implementation:**
```elixir
describe "/resume command - resuming by index" do
  # Same setup as above

  test "resumes session by index", %{tmp_base: tmp_base} do
    # Create and close 2 test sessions
    project1 = Path.join(tmp_base, "project1")
    project2 = Path.join(tmp_base, "project2")
    File.mkdir_p!(project1)
    File.mkdir_p!(project2)

    session1 = create_and_close_test_session("Project 1", project1)
    _session2 = create_and_close_test_session("Project 2", project2)

    # Execute /resume 1 (first session)
    result = Commands.execute_resume("1", %{})

    # Verify returns {:resume, session_id}
    assert {:resume, resumed_id} = result

    # Verify resumed session is now active
    assert {:ok, resumed_session} = SessionRegistry.lookup(resumed_id)
    assert resumed_session.name == "Project 1"

    # Verify persisted file deleted (consumed by resume)
    session_file = Path.join(Persistence.sessions_dir(), "#{session1.id}.json")
    refute File.exists?(session_file)
  end

  test "returns error for invalid index", %{tmp_base: tmp_base} do
    # Create one session
    project1 = Path.join(tmp_base, "project1")
    File.mkdir_p!(project1)
    _session1 = create_and_close_test_session("Project 1", project1)

    # Try to resume index 2 (doesn't exist)
    result = Commands.execute_resume("2", %{})

    # Verify returns error
    assert {:error, _reason} = result
  end
end
```

**Assertions:**
- Returns `{:resume, session_id}` for valid index
- Session becomes active in registry
- Persisted file deleted after resume
- Returns error for invalid index

---

### Step 4: Test Session Limit Error (Subtask 6.7.3.3)

**Test Goal:** Verify resume fails when 10 sessions already active

**Implementation:**
```elixir
describe "/resume command - error handling" do
  test "returns error when session limit reached", %{tmp_base: tmp_base} do
    # Create 10 active sessions (at limit)
    Enum.each(1..10, fn i ->
      project = Path.join(tmp_base, "project#{i}")
      File.mkdir_p!(project)

      {:ok, _session} = SessionSupervisor.create_session(
        project_path: project,
        name: "Session #{i}",
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      )
    end)

    # Create one closed session to resume
    project11 = Path.join(tmp_base, "project11")
    File.mkdir_p!(project11)
    _session11 = create_and_close_test_session("Session 11", project11)

    # Try to resume (should fail - at limit)
    result = Commands.execute_resume("1", %{})

    # Verify returns error about session limit
    assert {:error, reason} = result
    assert reason =~ "limit"
  end
end
```

**Assertions:**
- Returns `{:error, reason}` when at 10 session limit
- Error message mentions "limit"

---

### Step 5: Test Project Path Deleted Error (Subtask 6.7.3.4)

**Test Goal:** Verify resume fails gracefully when project directory deleted

**Implementation:**
```elixir
test "returns error when project path deleted", %{tmp_base: tmp_base} do
  # Create and close session
  project = Path.join(tmp_base, "project_to_delete")
  File.mkdir_p!(project)
  session = create_and_close_test_session("Deleted Project", project)

  # Delete project directory
  File.rm_rf!(project)

  # Try to resume
  result = Commands.execute_resume("1", %{})

  # Verify returns error about missing project
  assert {:error, reason} = result
  assert reason =~ "not found" or reason == :project_path_not_found
end
```

**Assertions:**
- Returns `{:error, reason}` when project path doesn't exist
- Error indicates path not found

---

### Step 6: Test Project Already Open Error (Subtask 6.7.3.5)

**Test Goal:** Verify resume fails when project already has an active session

**Implementation:**
```elixir
test "returns error when project already open", %{tmp_base: tmp_base} do
  # Create project
  project = Path.join(tmp_base, "shared_project")
  File.mkdir_p!(project)

  # Create active session for this project
  {:ok, _active_session} = SessionSupervisor.create_session(
    project_path: project,
    name: "Active Session",
    config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
  )

  # Create and close another session for same project
  _closed_session = create_and_close_test_session("Closed Session", project)

  # Try to resume (should fail - project already open)
  result = Commands.execute_resume("1", %{})

  # Verify returns error about project already open
  assert {:error, reason} = result
  assert reason =~ "already open" or reason == :project_already_open
end
```

**Assertions:**
- Returns `{:error, reason}` when project already has active session
- Error indicates project already open

---

### Step 7: Test Resume by UUID

**Test Goal:** Verify `/resume <uuid>` works in addition to index

**Implementation:**
```elixir
test "resumes session by UUID", %{tmp_base: tmp_base} do
  # Create and close session
  project = Path.join(tmp_base, "project_uuid")
  File.mkdir_p!(project)
  session = create_and_close_test_session("UUID Project", project)

  # Execute /resume <uuid>
  result = Commands.execute_resume(session.id, %{})

  # Verify returns {:resume, session_id}
  assert {:resume, resumed_id} = result
  assert resumed_id == session.id

  # Verify session active
  assert {:ok, _} = SessionRegistry.lookup(resumed_id)
end
```

**Assertions:**
- UUID targeting works same as index targeting
- Returns `{:resume, session_id}`
- Session becomes active

---

## Success Criteria

### Tests Implemented ✅

- [ ] Test 1: Lists resumable sessions (2 sessions) (6.7.3.1)
- [ ] Test 2: Lists message when no sessions (6.7.3.1)
- [ ] Test 3: Resumes session by index (6.7.3.2)
- [ ] Test 4: Returns error for invalid index (6.7.3.2)
- [ ] Test 5: Returns error when session limit reached (6.7.3.3)
- [ ] Test 6: Returns error when project path deleted (6.7.3.4)
- [ ] Test 7: Returns error when project already open (6.7.3.5)
- [ ] Test 8: Resumes session by UUID (additional coverage)

**Total:** 8 comprehensive `/resume` command integration tests

### Test Results ✅

- [ ] All new tests passing (8/8)
- [ ] All existing tests still passing (137+ existing in commands_test.exs)
- [ ] No compilation warnings
- [ ] Execution time reasonable (< 5 seconds for new tests)

### Documentation ✅

- [ ] Feature plan written (this document)
- [ ] Implementation summary written
- [ ] Phase plan updated (Task 6.7.3 marked complete)
- [ ] Test descriptions clear and comprehensive

### Code Quality ✅

- [ ] Tests follow existing patterns from commands_test.exs
- [ ] Helper functions added for session creation/closing
- [ ] Clear, descriptive test names
- [ ] Proper setup/teardown for clean test environment

---

## Testing Approach

### Test Categories

**1. Happy Path Tests (3 tests):**
- Lists resumable sessions (Test 1)
- Resumes by index (Test 3)
- Resumes by UUID (Test 8)

**2. Empty State Test (1 test):**
- Lists message when no sessions (Test 2)

**3. Error Handling Tests (4 tests):**
- Invalid index (Test 4)
- Session limit reached (Test 5)
- Project path deleted (Test 6)
- Project already open (Test 7)

### Assertion Strategy

**Command Execution:**
- Call Commands.execute_resume/2 directly
- Verify return value tuple type (`{:ok, _}`, `{:resume, _}`, `{:error, _}`)
- Verify message content for list results

**Session State:**
- Use SessionRegistry.lookup to verify active state
- Use Persistence.list_resumable to verify closed state
- Use File.exists? to verify persisted file state

**Error Messages:**
- Match on error tuple
- Verify error message contains expected keywords

---

## Notes and Considerations

### Scope Clarification

**What is Tested:**
- Command parsing (`/resume` → `{:resume, :list}`)
- Command execution (Commands.execute_resume/2)
- Integration with Persistence module
- Error handling for edge cases
- Return values for TUI consumption

**What is NOT Tested (Out of Scope):**
- TUI rendering of session list
- TUI tab management
- TUI session switching
- Keyboard shortcuts
- Visual formatting

**Rationale:** Task 6.7.3 is part of Phase 6 (Persistence), not TUI testing. The TUI will consume the return values from execute_resume/2, but testing the TUI itself is separate.

### Dependencies

**Requires (Already Complete):**
- Task 6.4: Persistence.resume/1 and list_resumable/0 implemented
- Task 6.5: Commands.execute_resume/2 implemented
- Task 6.7.1: Basic integration test infrastructure

**Provides:**
- Comprehensive test coverage for `/resume` command
- Documentation of expected behavior
- Safety net for refactoring

---

## Implementation Status

**Phase:** Planning Complete ✅
**Next Step:** Implement Test 1 (lists resumable sessions)
**Current Branch:** feature/ws-6.7.3-resume-command-integration

---

**End of Feature Plan**

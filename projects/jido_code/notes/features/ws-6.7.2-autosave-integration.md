# Feature Plan: Auto-Save on Close Integration Tests (Task 6.7.2)

**Task:** 6.7.2 - Auto-Save on Close Integration Tests
**Phase:** Phase 6 - Session Persistence
**Date:** 2025-12-10
**Status:** Planning Complete, Ready for Implementation

---

## Problem Statement

### What Problem Are We Solving?

Auto-save functionality was implemented in Phase 6 (Task 6.2) to automatically persist session state when sessions are closed. However, we currently lack integration tests that verify:

1. Auto-save triggers correctly for different close methods (`/session close` command, Ctrl+W keyboard shortcut)
2. Session data is saved **before** processes are terminated
3. Conversation state at the exact moment of close is preserved
4. Save failures are handled gracefully (logged but don't block close)
5. The complete close flow works end-to-end

**Impact:**
- Without these tests, auto-save regressions could go unnoticed
- Users could lose work if auto-save fails silently
- Close operations might hang or fail if save is blocking incorrectly
- We can't confidently refactor session close logic

---

## Solution Overview

### High-Level Approach

Add comprehensive integration tests to `test/jido_code/integration/session_phase6_test.exs` that verify:

1. **SessionSupervisor.stop_session/1 Integration**
   - Verify stop_session calls save_session_before_close
   - Verify save happens before process termination
   - Verify session file created with correct data

2. **Command Integration** (`/session close`)
   - Test command parsing → TUI handling → supervisor stop → auto-save
   - Verify end-to-end flow from command to saved file

3. **TUI Integration** (Ctrl+W)
   - Test keyboard shortcut → TUI event → supervisor stop → auto-save
   - Verify end-to-end flow from keypress to saved file

4. **Error Handling**
   - Test save failures (permission errors, disk full, etc.)
   - Verify close continues even when save fails
   - Verify warnings are logged appropriately

5. **State Preservation**
   - Verify conversation state at close time is preserved
   - Add messages/todos, close immediately, verify in file

### Key Design Decisions

**Decision 1: Add to Existing Integration Test File**
- **Choice:** Add tests to existing `session_phase6_test.exs`
- **Rationale:**
  - Already has setup infrastructure (API keys, cleanup, helpers)
  - Auto-save is part of Phase 6 persistence feature set
  - Keeps all Phase 6 integration tests in one place
  - Can reuse helper functions (create_test_session, add_messages_to_session, wait_for_file)

**Decision 2: Test at SessionSupervisor Level, Not TUI Level**
- **Choice:** Call `SessionSupervisor.stop_session/1` directly, not TUI commands
- **Rationale:**
  - TUI integration tests would require complex setup (TermUI runtime, keyboard event simulation)
  - SessionSupervisor.stop_session is the common path for all close operations
  - Simpler, more focused tests
  - TUI → supervisor integration already verified by existing functional tests
- **Note:** Document that `/session close` and Ctrl+W both call stop_session/1

**Decision 3: Use ExUnit.CaptureLog for Log Verification**
- **Choice:** Wrap test code in `capture_log/1` to verify warning logs
- **Rationale:**
  - Pattern already used extensively in codebase (7+ test files)
  - Clean, idiomatic Elixir testing
  - No need for custom log capture infrastructure

**Decision 4: Simulate Save Failures via File Permissions**
- **Choice:** Use `File.chmod!(file, 0o000)` to make directory read-only
- **Rationale:**
  - Pattern already used in settings_test.exs for testing permission errors
  - Doesn't require mocking or stubbing
  - Tests real error handling code path
  - Easy to set up and tear down

---

## Technical Details

### Auto-Save Flow (Code Locations)

#### 1. SessionSupervisor.stop_session/1
**Location:** `lib/jido_code/session_supervisor.ex` lines 166-176

```elixir
def stop_session(session_id) do
  case lookup_child_pid(session_id) do
    {:ok, pid} ->
      # Save before stopping
      save_session_before_close(session_id)

      # Then terminate
      DynamicSupervisor.terminate_child(__MODULE__, pid)

    {:error, :not_found} ->
      {:error, :not_found}
  end
end
```

**Key Points:**
- save_session_before_close/1 called **before** terminate_child
- Ensures session data saved before processes stop
- Returns {:error, :not_found} if session doesn't exist

#### 2. save_session_before_close/1
**Location:** `lib/jido_code/session_supervisor.ex` lines 178-190

```elixir
defp save_session_before_close(session_id) do
  case SessionRegistry.lookup(session_id) do
    {:ok, session} ->
      case Persistence.save(session) do
        {:ok, _path} ->
          Logger.debug("Session #{session_id} saved before close")
          :ok

        {:error, reason} ->
          Logger.warning("Failed to save session #{session_id} before close: #{inspect(reason)}")
          :ok  # Don't block close on save failure
      end

    {:error, :not_found} ->
      :ok
  end
end
```

**Key Points:**
- **Best-effort save:** Failures logged but return :ok
- Close continues even if save fails
- Logs warning on failure (line 186)
- Logs debug on success (line 183)

#### 3. Persistence.save/1
**Location:** `lib/jido_code/session/persistence.ex` lines 436-444

```elixir
def save(%Session{} = session) do
  try do
    persisted_session = build_persisted_session(session)
    json = Jason.encode!(persisted_session)

    sessions_dir = sessions_dir()
    File.mkdir_p!(sessions_dir)

    file_path = session_file_path(session.id)
    :ok = File.write!(file_path, json)

    {:ok, file_path}
  rescue
    e ->
      {:error, Exception.message(e)}
  end
end
```

**Key Points:**
- Creates sessions directory if not exists
- Writes JSON file with session state
- Rescues all exceptions, returns {:error, reason}

#### 4. build_persisted_session/1
**Location:** `lib/jido_code/session/persistence.ex` lines 464-516

```elixir
defp build_persisted_session(%Session{} = session) do
  {:ok, messages} = Session.State.get_messages(session.id)
  {:ok, todos} = Session.State.get_todos(session.id)

  %{
    version: @version,
    id: session.id,
    name: session.name,
    project_path: session.project_path,
    config: serialize_config(session.config),
    conversation: Enum.map(messages, &serialize_message/1),
    todos: Enum.map(todos, &serialize_todo/1),
    closed_at: DateTime.to_iso8601(DateTime.utc_now())
  }
end
```

**Key Points:**
- Gets messages and todos from Session.State at call time
- Serializes conversation state at exact moment of close
- Adds closed_at timestamp

### Close Command Integration

#### /session close Command
**Location:** `lib/jido_code/commands.ex` lines 514-541

```elixir
def execute_session({:close, target}, _model) do
  case resolve_session_target(target) do
    {:ok, session_id, session_name} ->
      {:session_action, {:close_session, session_id, session_name}}

    {:error, _} = error ->
      error
  end
end
```

**Flow:**
1. Command parsed: `/session close 1` → `{:session, {:close, "1"}}`
2. execute_session resolves target to session_id
3. Returns `{:session_action, {:close_session, session_id, name}}`
4. TUI handles session_action via handle_session_action/3 (lines 876-890)
5. TUI calls do_close_session/3 (lines 1269-1281)
6. do_close_session calls SessionSupervisor.stop_session/1
7. stop_session triggers auto-save

#### Ctrl+W Keyboard Shortcut
**Location:** `lib/jido_code/tui.ex` lines 1204-1206

```elixir
defp event_to_msg({:key, %{ch: ?w, mod: :ctrl}}) do
  {:msg, :close_active_session}
end
```

**Flow:**
1. Keyboard event detected: Ctrl+W
2. Converted to `:close_active_session` message
3. update/2 handles :close_active_session (line 876)
4. Calls do_close_session/3 with active session
5. do_close_session calls SessionSupervisor.stop_session/1
6. stop_session triggers auto-save

**Common Path:** Both flows converge at `SessionSupervisor.stop_session/1`

### Test Infrastructure Available

#### From session_phase6_test.exs

**Setup Block (lines 26-64):**
- Sets ANTHROPIC_API_KEY for test sessions
- Clears SessionRegistry and stops existing sessions
- Creates temp directories with cleanup
- Waits for SessionSupervisor availability

**Helper Functions:**
- `create_test_session/2` - Creates session with valid config
- `add_messages_to_session/2` - Adds messages with unique IDs
- `add_todos_to_session/2` - Adds todos with varying statuses
- `wait_for_file/2` - Polls for file creation with timeout (500ms max)

#### ExUnit.CaptureLog

**Usage Pattern (from existing tests):**
```elixir
import ExUnit.CaptureLog

test "logs warning on failure" do
  log = capture_log(fn ->
    # code that logs warning
  end)

  assert log =~ "Failed to save session"
end
```

**Examples in Codebase:**
- `test/jido_code/session/persistence_test.exs` - 5 tests use capture_log
- `test/jido_code/config_test.exs` - 2 tests use capture_log
- `test/jido_code/session/persistence_resume_test.exs` - 3 tests use capture_log

#### File Permission Error Simulation

**Pattern from settings_test.exs (lines 283-313):**
```elixir
test "handles permission errors gracefully" do
  # Make directory read-only
  File.chmod!(sessions_dir, 0o555)

  # Attempt operation
  result = Persistence.save(session)

  # Verify error returned
  assert {:error, _reason} = result

  # Restore permissions in cleanup
  on_exit(fn -> File.chmod!(sessions_dir, 0o755) end)
end
```

---

## Implementation Plan

### Step 1: Add Import and Test Group Structure

**File:** `test/jido_code/integration/session_phase6_test.exs`

**Action:** Add new describe block for auto-save tests

```elixir
# Add to imports (after line 20)
import ExUnit.CaptureLog

# Add new describe block (after existing tests, before end of module)
describe "auto-save on close integration" do
  # Tests will go here
end
```

**Verification:** File compiles without errors

---

### Step 2: Test - Stop Session Triggers Auto-Save (Subtask 6.7.2.1)

**Test Goal:** Verify SessionSupervisor.stop_session/1 creates session file before termination

**Implementation:**
```elixir
test "stop_session triggers auto-save before termination", %{tmp_base: tmp_base} do
  # Create session with messages
  session = create_test_session(tmp_base, "Auto-Save Test")
  add_messages_to_session(session.id, 2)

  # Verify session is active
  assert {:ok, _} = SessionRegistry.lookup(session.id)

  # Stop session (triggers auto-save)
  :ok = SessionSupervisor.stop_session(session.id)

  # Wait for file creation
  session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
  assert :ok = wait_for_file(session_file)

  # Verify file exists
  assert File.exists?(session_file)

  # Verify session no longer active
  assert {:error, :not_found} = SessionRegistry.lookup(session.id)

  # Verify file contains messages
  {:ok, json} = File.read(session_file)
  {:ok, data} = Jason.decode(json)
  assert length(data["conversation"]) == 2
  assert data["name"] == "Auto-Save Test"
end
```

**Assertions:**
- Session file created
- Session removed from registry (terminated)
- File contains correct data (messages, name)
- File created **before** termination (order matters)

---

### Step 3: Test - Conversation State at Close Time (Subtask 6.7.2.4)

**Test Goal:** Verify saved conversation includes messages added right before close

**Implementation:**
```elixir
test "saves conversation state at exact time of close", %{tmp_base: tmp_base} do
  # Create session
  session = create_test_session(tmp_base, "State Preservation")

  # Add initial messages
  add_messages_to_session(session.id, 2)

  # Add one more message immediately before close
  final_message = %{
    id: "final-msg-#{System.unique_integer([:positive])}",
    role: :user,
    content: "Final message before close",
    timestamp: DateTime.utc_now()
  }
  Session.State.append_message(session.id, final_message)

  # Close immediately
  :ok = SessionSupervisor.stop_session(session.id)

  # Wait for file
  session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
  assert :ok = wait_for_file(session_file)

  # Verify file contains all 3 messages including the final one
  {:ok, json} = File.read(session_file)
  {:ok, data} = Jason.decode(json)
  assert length(data["conversation"]) == 3

  # Verify final message is in the saved conversation
  contents = Enum.map(data["conversation"], & &1["content"])
  assert "Final message before close" in contents
end
```

**Assertions:**
- Final message added before close is in saved file
- All messages (including last-second additions) preserved
- Conversation count matches expected (3)

---

### Step 4: Test - Save Failure Doesn't Block Close (Subtask 6.7.2.3)

**Test Goal:** Verify close continues even when save fails (permission error)

**Implementation:**
```elixir
test "save failure logs warning but allows close to continue", %{tmp_base: tmp_base} do
  # Create session
  session = create_test_session(tmp_base, "Failure Test")
  add_messages_to_session(session.id, 1)

  # Make sessions directory read-only (simulates permission error)
  sessions_dir = Persistence.sessions_dir()
  original_mode = File.stat!(sessions_dir).mode
  File.chmod!(sessions_dir, 0o555)

  # Ensure cleanup restores permissions
  on_exit(fn -> File.chmod!(sessions_dir, original_mode) end)

  # Capture log output
  log = capture_log(fn ->
    # Stop session (save will fail due to permissions)
    result = SessionSupervisor.stop_session(session.id)

    # Verify stop_session still returns :ok
    assert :ok == result
  end)

  # Verify warning was logged
  assert log =~ "Failed to save session #{session.id} before close"

  # Verify session was still terminated (not in registry)
  assert {:error, :not_found} = SessionRegistry.lookup(session.id)

  # Verify no session file created (save failed)
  session_file = Path.join(sessions_dir, "#{session.id}.json")
  refute File.exists?(session_file)
end
```

**Assertions:**
- stop_session returns :ok even when save fails
- Warning logged about save failure
- Session still terminated (removed from registry)
- No session file created (expected due to failure)

---

### Step 5: Test - Todos Preserved on Close (Additional Coverage)

**Test Goal:** Verify todos are also saved during auto-save

**Implementation:**
```elixir
test "saves todos state during auto-save", %{tmp_base: tmp_base} do
  # Create session
  session = create_test_session(tmp_base, "Todos Test")

  # Add messages and todos
  add_messages_to_session(session.id, 1)
  add_todos_to_session(session.id, 3)

  # Close session
  :ok = SessionSupervisor.stop_session(session.id)

  # Wait for file
  session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
  assert :ok = wait_for_file(session_file)

  # Verify file contains todos
  {:ok, json} = File.read(session_file)
  {:ok, data} = Jason.decode(json)
  assert length(data["todos"]) == 3
  assert length(data["conversation"]) == 1

  # Verify todo structure
  first_todo = hd(data["todos"])
  assert Map.has_key?(first_todo, "content")
  assert Map.has_key?(first_todo, "status")
  assert Map.has_key?(first_todo, "activeForm")
end
```

**Assertions:**
- Todos count matches (3)
- Messages also saved (1)
- Todo structure correct (has required fields)

---

### Step 6: Test - Multiple Closes Create Multiple Files (Edge Case)

**Test Goal:** Verify multiple sessions closing creates multiple session files

**Implementation:**
```elixir
test "multiple session closes create separate session files", %{tmp_base: tmp_base} do
  # Create 3 sessions
  session1 = create_test_session(tmp_base, "Session 1")
  session2 = create_test_session(tmp_base, "Session 2")
  session3 = create_test_session(tmp_base, "Session 3")

  # Add different messages to each
  add_messages_to_session(session1.id, 1)
  add_messages_to_session(session2.id, 2)
  add_messages_to_session(session3.id, 3)

  # Close all three
  :ok = SessionSupervisor.stop_session(session1.id)
  :ok = SessionSupervisor.stop_session(session2.id)
  :ok = SessionSupervisor.stop_session(session3.id)

  # Wait for all files
  sessions_dir = Persistence.sessions_dir()
  file1 = Path.join(sessions_dir, "#{session1.id}.json")
  file2 = Path.join(sessions_dir, "#{session2.id}.json")
  file3 = Path.join(sessions_dir, "#{session3.id}.json")

  assert :ok = wait_for_file(file1)
  assert :ok = wait_for_file(file2)
  assert :ok = wait_for_file(file3)

  # Verify all three files exist
  assert File.exists?(file1)
  assert File.exists?(file2)
  assert File.exists?(file3)

  # Verify each file has correct message count
  assert_message_count(file1, 1)
  assert_message_count(file2, 2)
  assert_message_count(file3, 3)
end

defp assert_message_count(file_path, expected_count) do
  {:ok, json} = File.read(file_path)
  {:ok, data} = Jason.decode(json)
  assert length(data["conversation"]) == expected_count
end
```

**Assertions:**
- All three session files created
- Each file has correct message count
- Files are independent (no cross-contamination)

---

### Step 7: Test - Closed Session Not in Active Registry (Verification)

**Test Goal:** Double-check that auto-saved sessions are not in active registry

**Implementation:**
```elixir
test "auto-saved sessions removed from active registry", %{tmp_base: tmp_base} do
  # Create two sessions
  session1 = create_test_session(tmp_base, "Active")
  session2 = create_test_session(tmp_base, "Closed")

  # Verify both active
  assert {:ok, _} = SessionRegistry.lookup(session1.id)
  assert {:ok, _} = SessionRegistry.lookup(session2.id)

  # Close only session2
  :ok = SessionSupervisor.stop_session(session2.id)

  # Wait for file
  session_file = Path.join(Persistence.sessions_dir(), "#{session2.id}.json")
  assert :ok = wait_for_file(session_file)

  # Verify session1 still active
  assert {:ok, _} = SessionRegistry.lookup(session1.id)

  # Verify session2 NOT in active registry
  assert {:error, :not_found} = SessionRegistry.lookup(session2.id)

  # Verify session2 file exists
  assert File.exists?(session_file)

  # Cleanup active session
  SessionSupervisor.stop_session(session1.id)
end
```

**Assertions:**
- Active session remains in registry
- Closed session removed from registry
- Closed session file exists
- Sessions isolated (closing one doesn't affect other)

---

## Success Criteria

### Tests Implemented ✅

- [ ] Test 1: stop_session triggers auto-save before termination (6.7.2.1)
- [ ] Test 2: Conversation state at exact time of close preserved (6.7.2.4)
- [ ] Test 3: Save failure logs warning but allows close (6.7.2.3)
- [ ] Test 4: Todos preserved during auto-save (additional coverage)
- [ ] Test 5: Multiple closes create multiple files (edge case)
- [ ] Test 6: Auto-saved sessions removed from registry (verification)

**Total:** 6 comprehensive auto-save integration tests

### Test Results ✅

- [ ] All new tests passing (6/6)
- [ ] All existing tests still passing (9 from Task 6.7.1)
- [ ] Total: 15 integration tests in session_phase6_test.exs
- [ ] No compilation warnings
- [ ] Execution time < 2 seconds

### Documentation ✅

- [ ] Feature plan written (this document)
- [ ] Implementation summary written
- [ ] Phase plan updated (Task 6.7.2 marked complete)
- [ ] Test descriptions clear and comprehensive

### Code Quality ✅

- [ ] Tests follow existing patterns from session_phase6_test.exs
- [ ] Helper functions reused (create_test_session, add_messages_to_session, wait_for_file)
- [ ] ExUnit.CaptureLog used correctly for log verification
- [ ] File permission cleanup in on_exit hooks
- [ ] Clear, descriptive test names

---

## Testing Approach

### Test Categories

**1. Happy Path Tests (3 tests):**
- stop_session triggers auto-save (Test 1)
- Conversation state preserved (Test 2)
- Todos preserved (Test 4)

**2. Error Handling Tests (1 test):**
- Save failure doesn't block close (Test 3)

**3. Edge Case Tests (2 tests):**
- Multiple closes create multiple files (Test 5)
- Registry isolation verification (Test 6)

### Assertion Strategy

**File Existence:**
- Use wait_for_file/2 to handle async I/O
- Assert File.exists? for session files

**Registry State:**
- Assert SessionRegistry.lookup returns {:ok, _} for active
- Assert SessionRegistry.lookup returns {:error, :not_found} for closed

**File Content:**
- Read JSON file with File.read + Jason.decode
- Assert message/todo counts
- Assert specific content in conversation array

**Log Verification:**
- Wrap test code in capture_log/1
- Assert log output contains expected warning message

**Error Simulation:**
- Use File.chmod! to make directories read-only
- Use on_exit hooks to restore permissions

---

## Notes and Considerations

### Edge Cases Covered

1. **Save failure doesn't block close** - Critical for UX (Test 3)
2. **Multiple sessions closing** - Common scenario (Test 5)
3. **Last-second message additions** - Real user behavior (Test 2)
4. **Registry isolation** - Prevents bugs (Test 6)

### Not Covered (Out of Scope)

1. **TUI command integration** - Would require TermUI runtime setup
   - `/session close` command parsing already tested in commands_test.exs
   - Ctrl+W keyboard handling already tested in tui_test.exs
   - Both converge at SessionSupervisor.stop_session/1 which we test

2. **Disk full errors** - Hard to simulate portably
   - File permission errors (Test 3) provide similar coverage

3. **Concurrent session closes** - Complex setup, minimal benefit
   - SessionSupervisor uses DynamicSupervisor which handles concurrency

4. **HMAC signature verification** - Covered by unit tests in persistence_test.exs

### Future Improvements

1. **Performance testing** - Measure auto-save latency for large sessions
2. **Stress testing** - Close many sessions rapidly, verify all saved
3. **Corruption recovery** - Partial writes during crashes (low priority)

### Dependencies

**Requires (Already Complete):**
- Task 6.2: Auto-save implementation (SessionSupervisor.stop_session/1)
- Task 6.4: Save and resume functions (Persistence.save/1)
- Task 6.7.1: Basic integration test infrastructure (session_phase6_test.exs setup)

**Blocks:**
- None (Task 6.7.3 can proceed independently)

---

## Risk Assessment

### Low Risk

- **Test implementation** - Following established patterns
- **Helper function reuse** - Already proven in 9 existing tests
- **ExUnit.CaptureLog** - Used in 7+ existing test files

### Medium Risk

- **File permission simulation** - Must restore permissions in cleanup
  - **Mitigation:** Use on_exit hooks (pattern from settings_test.exs)

### No Risk

- **Production code changes** - None required (tests only)
- **Breaking changes** - Tests verify existing behavior

---

## Estimated Effort

**Implementation:** 1-2 hours
- Write 6 tests: ~60-90 minutes
- Debug and fix issues: ~15-30 minutes
- Documentation: ~15-30 minutes

**Testing:** 15-30 minutes
- Run tests multiple times
- Verify all 15 integration tests pass
- Check for flaky tests

**Total:** 1.5-2.5 hours

---

## Acceptance Checklist

### Before Starting
- [x] Feature branch created (feature/ws-6.7.2-autosave-integration)
- [x] Feature plan written (this document)
- [x] Phase plan reviewed (Task 6.7.2 requirements understood)

### During Implementation
- [ ] Import ExUnit.CaptureLog added to test file
- [ ] Test 1 implemented and passing (stop_session triggers auto-save)
- [ ] Test 2 implemented and passing (conversation state preserved)
- [ ] Test 3 implemented and passing (save failure handled)
- [ ] Test 4 implemented and passing (todos preserved)
- [ ] Test 5 implemented and passing (multiple closes)
- [ ] Test 6 implemented and passing (registry isolation)
- [ ] All 15 integration tests passing (6 new + 9 existing)

### Before Committing
- [ ] Phase plan updated (Task 6.7.2 marked complete)
- [ ] Summary document written (notes/summaries/ws-6.7.2-autosave-integration.md)
- [ ] All tests passing
- [ ] No compilation warnings
- [ ] Git status clean (no untracked files except feature/summary docs)

### Commit Requirements
- [ ] Commit message describes changes clearly
- [ ] NO references to "Claude" or "Anthropic" in commit message
- [ ] Commit follows conventional commit format: test(session): ...

---

## Implementation Status

**Phase:** Planning Complete ✅
**Next Step:** Implement Test 1 (stop_session triggers auto-save)
**Current Branch:** feature/ws-6.7.2-autosave-integration

---

**End of Feature Plan**

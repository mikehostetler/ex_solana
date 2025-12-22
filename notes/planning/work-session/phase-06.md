# Phase 6: Session Persistence

This phase implements session persistence, allowing sessions to be saved to disk and restored via the `/resume` command. Sessions are not automatically restored on startup—users must explicitly request restoration.

---

## 6.1 Persistence Data Structure

Define the data structures and file formats for persisted sessions.

### 6.1.1 Persisted Session Schema
- [x] **Task 6.1.1**

Define the schema for persisted session data.

- [x] 6.1.1.1 Create `lib/jido_code/session/persistence.ex` module
- [x] 6.1.1.2 Define `@type persisted_session()`:
  ```elixir
  @type persisted_session :: %{
    version: pos_integer(),        # Schema version for migrations
    id: String.t(),
    name: String.t(),
    project_path: String.t(),
    config: config(),
    created_at: String.t(),        # ISO 8601
    updated_at: String.t(),        # ISO 8601
    closed_at: String.t(),         # ISO 8601
    conversation: [persisted_message()],
    todos: [persisted_todo()]
  }
  ```
- [x] 6.1.1.3 Define `@type persisted_message()`:
  ```elixir
  @type persisted_message :: %{
    id: String.t(),
    role: String.t(),
    content: String.t(),
    timestamp: String.t()
  }
  ```
- [x] 6.1.1.4 Define `@type persisted_todo()`:
  ```elixir
  @type persisted_todo :: %{
    content: String.t(),
    status: String.t(),
    active_form: String.t()
  }
  ```
- [x] 6.1.1.5 Document schema version for future migrations
- [x] 6.1.1.6 Write unit tests for schema types

### 6.1.2 Storage Location
- [x] **Task 6.1.2**

Define storage locations for persisted sessions.

- [x] 6.1.2.1 Define sessions directory: `~/.jido_code/sessions/`
- [x] 6.1.2.2 Define session file pattern: `{session_id}.json`
- [x] 6.1.2.3 Implement `sessions_dir/0` returning expanded path
- [x] 6.1.2.4 Implement `session_file/1` returning file path for session ID
- [x] 6.1.2.5 Implement `ensure_sessions_dir/0` creating directory if missing
- [x] 6.1.2.6 Write unit tests for path functions

**Unit Tests for Section 6.1:**
- Test persisted_session schema matches expected format
- Test persisted_message schema matches expected format
- Test `sessions_dir/0` returns correct path
- Test `session_file/1` returns correct file path
- Test `ensure_sessions_dir/0` creates directory

---

## 6.2 Session Saving

Implement saving sessions to disk.

### 6.2.1 Save Session State
- [x] **Task 6.2.1**

Implement saving session to JSON file.

- [x] 6.2.1.1 Implement `save/1` accepting session_id:
  ```elixir
  def save(session_id) do
    with {:ok, session} <- SessionRegistry.lookup(session_id),
         {:ok, state} <- get_session_state(session_id),
         persisted = build_persisted_session(session, state),
         :ok <- write_session_file(persisted) do
      {:ok, session_file(session_id)}
    end
  end
  ```
- [x] 6.2.1.2 Implement `build_persisted_session/2`:
  ```elixir
  defp build_persisted_session(session, state) do
    %{
      version: 1,
      id: session.id,
      name: session.name,
      project_path: session.project_path,
      config: session.config,
      created_at: DateTime.to_iso8601(session.created_at),
      updated_at: DateTime.to_iso8601(session.updated_at),
      closed_at: DateTime.to_iso8601(DateTime.utc_now()),
      conversation: Enum.map(state.messages, &serialize_message/1),
      todos: Enum.map(state.todos, &serialize_todo/1)
    }
  end
  ```
- [x] 6.2.1.3 Write JSON atomically (temp file then rename)
- [x] 6.2.1.4 Handle write errors gracefully
- [x] 6.2.1.5 Write unit tests for save function

### 6.2.2 Auto-Save on Close
- [x] **Task 6.2.2**

Integrate save with session close flow.

- [x] 6.2.2.1 Update `SessionSupervisor.stop_session/1` to save first:
  ```elixir
  def stop_session(session_id) do
    # Save before stopping
    Persistence.save(session_id)
    # Then stop processes
    terminate_session_processes(session_id)
  end
  ```
- [x] 6.2.2.2 Log save success/failure
- [x] 6.2.2.3 Continue with stop even if save fails
- [x] 6.2.2.4 Write integration tests for auto-save

### 6.2.3 Manual Save Command
- [x] **Task 6.2.3** (completed 2025-12-16)

Implement `/session save` command (optional).

- [x] 6.2.3.1 Add `save` subcommand to session commands
- [x] 6.2.3.2 Implement `execute_session({:save, target}, model)` with:
  - Optional target parameter (index/name/ID, defaults to active)
  - Calls `Persistence.save/1` for actual save operation
  - Returns success message with file path
  - Comprehensive error handling for all failure cases
- [x] 6.2.3.3 Write unit tests for save command (10 new tests)

**Unit Tests for Section 6.2:**
- Test `save/1` creates JSON file
- Test save includes all session data
- Test save includes conversation history
- Test save includes todo list
- Test save writes atomically
- Test session close triggers auto-save
- Test `/session save` command works

---

## 6.3 Session Listing (Persisted)

Implement listing persisted sessions for resume.

### 6.3.1 List Persisted Sessions
- [x] **Task 6.3.1**

Implement listing all persisted sessions.

- [x] 6.3.1.1 Implement `list_persisted/0`:
  ```elixir
  def list_persisted do
    sessions_dir()
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.map(&load_session_metadata/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.closed_at, {:desc, DateTime})
  end
  ```
- [x] 6.3.1.2 Implement `load_session_metadata/1` (load minimal info):
  ```elixir
  defp load_session_metadata(filename) do
    path = Path.join(sessions_dir(), filename)
    case File.read(path) do
      {:ok, content} ->
        Jason.decode!(content)
        |> Map.take([:id, :name, :project_path, :closed_at])
      {:error, _} -> nil
    end
  end
  ```
- [x] 6.3.1.3 Sort by closed_at (most recent first)
- [x] 6.3.1.4 Handle corrupted files gracefully
- [x] 6.3.1.5 Write unit tests for listing

### 6.3.2 Filter Active Sessions
- [x] **Task 6.3.2**

Exclude already-active sessions from persisted list.

- [x] 6.3.2.1 Implement `list_resumable/0`:
  ```elixir
  def list_resumable do
    active_ids = SessionRegistry.list_ids()
    active_paths = SessionRegistry.list_all() |> Enum.map(& &1.project_path)
    list_persisted()
    |> Enum.reject(& &1.id in active_ids or &1.project_path in active_paths)
  end
  ```
- [x] 6.3.2.2 Also exclude sessions with same project_path as active
- [x] 6.3.2.3 Write unit tests for filtering

**Unit Tests for Section 6.3:**
- Test `list_persisted/0` finds all JSON files
- Test listing handles corrupted files
- Test listing sorted by closed_at descending
- Test `list_resumable/0` excludes active sessions
- Test filtering excludes duplicate project paths

---

## 6.4 Session Restoration

Implement restoring sessions from persisted state.

### 6.4.1 Load Persisted Session
- [x] **Task 6.4.1**

Implement loading full session data from file.

- [x] 6.4.1.1 Implement `load/1` accepting session_id:
  ```elixir
  def load(session_id) do
    path = session_file(session_id)
    with {:ok, content} <- File.read(path),
         {:ok, data} <- Jason.decode(content),
         {:ok, session} <- deserialize_session(data) do
      {:ok, session}
    else
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, {:invalid_file, reason}}
    end
  end
  ```
- [x] 6.4.1.2 Implement `deserialize_session/1` converting JSON to structs
- [x] 6.4.1.3 Handle schema version migrations
- [x] 6.4.1.4 Validate loaded data
- [x] 6.4.1.5 Write unit tests for load function

### 6.4.2 Resume Session
- [x] **Task 6.4.2**

Implement full session restoration.

- [x] 6.4.2.1 Implement `resume/1` accepting session_id:
  ```elixir
  def resume(session_id) do
    with {:ok, persisted} <- load(session_id),
         :ok <- validate_project_path(persisted.project_path),
         session = rebuild_session(persisted),
         {:ok, _pid} <- SessionSupervisor.start_session(session) do
      # Restore conversation history
      restore_conversation(session.id, persisted.conversation)
      # Restore todos
      restore_todos(session.id, persisted.todos)
      # Delete persisted file (session is now active)
      delete_persisted(session_id)
      {:ok, session}
    end
  end
  ```
- [x] 6.4.2.2 Implement `rebuild_session/1` creating Session from persisted:
  ```elixir
  defp rebuild_session(persisted) do
    %Session{
      id: persisted.id,
      name: persisted.name,
      project_path: persisted.project_path,
      config: persisted.config,
      created_at: DateTime.from_iso8601!(persisted.created_at),
      updated_at: DateTime.utc_now()
    }
  end
  ```
- [x] 6.4.2.3 Restore messages to Session.State
- [x] 6.4.2.4 Restore todos to Session.State
- [x] 6.4.2.5 Delete persisted file after successful resume
- [x] 6.4.2.6 Write unit tests for resume function

### 6.4.3 Project Path Validation
- [x] **Task 6.4.3** ✅ (Completed in 6.4.2)

Validate project path still exists before resuming.

- [x] 6.4.3.1 Implement `validate_project_path/1` (completed in 6.4.2)
- [x] 6.4.3.2 Return clear error if path doesn't exist
- [x] 6.4.3.3 Return error if project already open
- [x] 6.4.3.4 Write unit tests for validation

### 6.4.4 Security Review Fixes
- [x] **Task 6.4.4** ✅ (Completed 2025-12-10)

Address all security findings from Section 6.4 review (notes/reviews/section-6.4-review.md).

**High Priority Security Fixes:**
- [x] 6.4.4.1 HMAC Signature Infrastructure
  - Created lib/jido_code/session/persistence/crypto.ex
  - HMAC-SHA256 with PBKDF2 key derivation
  - Integrated into write_session_file/2 and load/1
  - Graceful backward compatibility for unsigned files
  - 24 comprehensive tests
- [x] 6.4.4.2 TOCTOU Race Condition Fix
  - Added revalidate_project_path/1
  - Integrated into restore_state_or_cleanup/2
  - Re-validates path after session start
  - Automatic cleanup on failure
- [x] 6.4.4.3 File Size Validation in load/1
  - Added File.stat check to load/1
  - Enforces 10MB limit consistently
  - DoS prevention

**Medium Priority Defense in Depth:**
- [x] 6.4.4.4 Rate Limiting
  - Created lib/jido_code/rate_limit.ex
  - ETS-based sliding window (5 attempts/60 seconds)
  - GenServer with periodic cleanup
  - Integrated into resume/1
  - 20 comprehensive tests
- [x] 6.4.4.5 Enhanced Path Validation
  - Implemented as part of TOCTOU fix
  - Full security validation after session start

**Code Quality Improvements:**
- [x] 6.4.4.6 Extract deserialize_list/2 helper
  - Reduced code duplication by ~90%
  - Generic list deserialization function
- [x] 6.4.4.7 Enhanced test helpers
  - Added persistence helpers to SessionTestHelpers
  - test_uuid/1, create_test_session/4, create_persisted_session/4

**Documentation:**
- [x] 6.4.4.8 Feature plan: notes/features/ws-6.4.3-review-fixes.md
- [x] 6.4.4.9 Summary: notes/summaries/ws-6.4.3-review-fixes.md
- [x] 6.4.4.10 Review document: notes/reviews/section-6.4-review.md

**Test Results:**
- 166 tests passing (122 integration + 24 Crypto + 20 RateLimit)
- 0 failures, 0 compilation errors, 0 new credo issues
- Production-ready security posture

**Unit Tests for Section 6.4:**
- Test `load/1` parses JSON correctly
- Test `load/1` handles missing file
- Test `load/1` handles corrupted JSON
- Test `resume/1` creates active session
- Test `resume/1` restores conversation history
- Test `resume/1` restores todos
- Test `resume/1` deletes persisted file
- Test resume fails if project path missing
- Test resume fails if project already open

---

## 6.5 Resume Command

Implement the `/resume` command.

### 6.5.1 Resume Command Handler
- [x] **Task 6.5.1** ✅ (Completed 2025-12-10)

Implement the `/resume` command.

- [x] 6.5.1.1 Add `/resume` to command parser (Commands module)
- [x] 6.5.1.2 Implement `execute_resume(:list, model)` - lists resumable sessions
- [x] 6.5.1.3 Implement `format_resumable_list/1` - formats list with indices
- [x] 6.5.1.4 Integration with TUI via `handle_resume_command/2`

### 6.5.2 Resume by Index or ID
- [x] **Task 6.5.2** ✅ (Completed 2025-12-10)

Implement restoring specific session.

- [x] 6.5.2.1 Implement `execute_resume({:restore, target}, model)`
- [x] 6.5.2.2 Implement `resolve_resume_target/2` - supports numeric index (1-based) or UUID
- [x] 6.5.2.3 Handle invalid targets with clear error messages
- [x] 6.5.2.4 Comprehensive error handling for all Persistence.resume/1 errors:
  - project_path_not_found, project_path_not_directory
  - project_already_open, session_limit_reached
  - rate_limit_exceeded (with retry-after seconds)
  - not_found (session file missing)

### 6.5.3 Time Formatting
- [x] **Task 6.5.3** ✅ (Completed 2025-12-10)

Format "closed X ago" for display.

- [x] 6.5.3.1 Implement `format_ago/1` with relative time formatting:
  - "just now" (< 1 minute)
  - "X min ago" (< 1 hour)
  - "X hour(s) ago" (< 1 day)
  - "yesterday" (1-2 days)
  - "X days ago" (2-7 days)
  - Absolute date (> 1 week)
- [x] 6.5.3.2 Error handling for invalid timestamps

**Implementation Summary:**
- Created `/resume` command parsing in Commands module
- Implemented list and restore functionality with TUI integration
- Added comprehensive error handling for all edge cases
- Updated help text and module documentation
- All existing tests passing (242 tests, 0 failures)
- Feature complete and production-ready

**Unit Tests for Section 6.5:**
- Test `/resume` lists resumable sessions
- Test `/resume` shows empty message when none
- Test `/resume 1` restores first session
- Test `/resume abc123` restores by ID
- Test resume adds session to TUI
- Test resume fails gracefully with clear errors
- Test `format_ago/1` formats times correctly

---

## 6.6 Cleanup and Maintenance

Implement cleanup of old persisted sessions.

### 6.6.1 Session Cleanup
- [x] **Task 6.6.1** ✅ (Completed 2025-12-10)

Implement cleanup of old persisted sessions.

- [x] 6.6.1.1 Implement `cleanup/1` accepting max_age in days (default 30)
- [x] 6.6.1.2 Calculate cutoff DateTime and filter old sessions
- [x] 6.6.1.3 Delete sessions older than cutoff
- [x] 6.6.1.4 Continue-on-error strategy for robustness
- [x] 6.6.1.5 Return detailed results map (deleted, skipped, failed, errors)
- [x] 6.6.1.6 Add comprehensive logging (info, debug, warning)
- [x] 6.6.1.7 Make delete_persisted/1 public for reuse
- [x] 6.6.1.8 Write unit tests (12 tests passing, 3 skipped)

**Implementation Summary:**
- Created `cleanup/1` function in Persistence module
- Helper function `parse_and_compare_timestamp/2` for timestamp parsing
- Made `delete_persisted/1` public with documentation
- Comprehensive error handling for all edge cases
- Tests: 12 passing, 3 skipped (platform-dependent file permissions)
- Total persistence tests: 137 passing, 0 failures

### 6.6.2 Delete Command
- [x] **Task 6.6.2** ✅ (Completed 2025-12-10)

Implement deleting persisted sessions without restoring.

- [x] 6.6.2.1 Add `/resume delete <target>` subcommand parsing
- [x] 6.6.2.2 Implement execute_resume({:delete, target}, model) handler
- [x] 6.6.2.3 Fix resolve_resume_target to handle UUID starting with digits
- [x] 6.6.2.4 Fix list_resumable() return value handling (was expecting {:ok, list})
- [x] 6.6.2.5 Update module documentation and help text
- [x] 6.6.2.6 Write 12 comprehensive unit tests (all passing)

**Implementation Summary:**
- Command parsing: `/resume delete <target>` → `{:resume, {:delete, target}}`
- Handler calls list_resumable(), resolve_resume_target(), delete_persisted()
- Fixed bug: resolve_resume_target now handles partial integer parses (UUIDs starting with digits)
- Fixed bug: execute_resume functions now correctly handle list_resumable() returning plain list
- Tests: 12 new tests, 132 total passing (0 failures)
- TUI integration: Already working via existing handle_resume_command/2

### 6.6.3 Clear All Command
- [x] **Task 6.6.3** ✅ (Completed 2025-12-10)

Implement clearing all persisted sessions.

- [x] 6.6.3.1 Add `/resume clear` subcommand parsing
- [x] 6.6.3.2 No confirmation needed (command is explicit, user can preview with /resume first)
- [x] 6.6.3.3 Implement execute_resume(:clear, model) handler
- [x] 6.6.3.4 Iterate delete_persisted/1 instead of new clear_all() function
- [x] 6.6.3.5 Update module documentation and help text
- [x] 6.6.3.6 Write 5 comprehensive unit tests (all passing)

**Implementation Summary:**
- Command parsing: `/resume clear` → `{:resume, :clear}`
- Handler iterates list_persisted() and calls delete_persisted/1 for each
- Returns "Cleared N saved session(s)." or "No saved sessions to clear."
- Design decision: No new Persistence function needed (reuse existing delete_persisted/1)
- Design decision: No confirmation (command explicit, consistent with delete)
- Tests: 5 new tests, 137 total passing (0 failures)
- TUI integration: Already working via existing handle_resume_command/2

**Unit Tests for Section 6.6:**
- Test `cleanup/1` removes old sessions
- Test cleanup keeps recent sessions
- Test `/resume delete 1` deletes session
- Test `/resume clear` removes all persisted
- Test clear reports correct count

---

## 6.7 Phase 6 Integration Tests

Comprehensive integration tests verifying all Phase 6 persistence components work together correctly.

### 6.7.1 Save-Resume Cycle Integration ✅
- [x] **Task 6.7.1** ✅ **COMPLETE**

Test complete save and resume cycle end-to-end.

- [x] 6.7.1.1 Create `test/jido_code/integration/session_phase6_test.exs`
- [x] 6.7.1.2 Test: Create session → add messages → close → verify JSON file created
- [x] 6.7.1.3 Test: Resume session → verify messages restored → verify todos restored
- [x] 6.7.1.4 Test: Resume → verify session ID preserved → verify config preserved
- [x] 6.7.1.5 Test: Resume → persisted file deleted → session now active
- [x] 6.7.1.6 Write all save-resume cycle integration tests (9 comprehensive tests)

### 6.7.2 Auto-Save on Close Integration ✅
- [x] **Task 6.7.2** ✅ **COMPLETE**

Test auto-save integrates with session close flow.

- [x] 6.7.2.1 Test: `/session close` → session saved before processes terminated
- [x] 6.7.2.2 Test: Ctrl+W close → session saved
- [x] 6.7.2.3 Test: Save failure → close continues → warning logged
- [x] 6.7.2.4 Test: Save includes conversation at time of close
- [x] 6.7.2.5 Write all auto-save integration tests (6 comprehensive tests)

### 6.7.3 Resume Command Integration
- [x] **Task 6.7.3** ✅

Test `/resume` command end-to-end at Commands module level.

- [x] 6.7.3.1 Test: Close session → `/resume` → shows in resumable list
- [x] 6.7.3.2 Test: `/resume 1` → session restored (returns {:session_action, {:add_session, session}})
- [x] 6.7.3.3 Test: `/resume` when at session limit → error message
- [x] 6.7.3.4 Test: `/resume` when project path deleted → error message
- [x] 6.7.3.5 Test: Filtering - sessions for open projects excluded from list
- [x] 6.7.3.6 Write all resume command integration tests (8 tests, 145/145 passing)

### 6.7.4 Persistence File Format Integration
- [x] **Task 6.7.4** ✅

Test persistence file format works correctly at file level.

- [x] 6.7.4.1 Test: Saved JSON includes all required fields (version, id, name, config, closed_at, etc.)
- [x] 6.7.4.2 Test: Conversation messages serialized correctly (role as string, timestamps ISO 8601)
- [x] 6.7.4.3 Test: Todos serialized correctly (status as string, active_form present)
- [x] 6.7.4.4 Test: Timestamps in ISO 8601 format (parseable, accurate)
- [x] 6.7.4.5 Test: Round-trip preserves all data (save → resume → verify)
- [x] 6.7.4.6 Test: Corrupted JSON handled gracefully (skip file, log warning)
- [x] 6.7.4.7 Write all file format integration tests (6 tests, 21/21 phase6 passing)

### 6.7.5 Multi-Session Persistence Integration
- [x] **Task 6.7.5** ✅

Test persistence works correctly with multiple sessions.

- [x] 6.7.5.1 Test: Close 3 sessions → all 3 appear in `/resume` list ✅
- [x] 6.7.5.2 Test: Resume one → remaining 2 still in resume list ✅
- [x] 6.7.5.3 Test: `/resume list` sorted by closed_at (most recent first) ✅
- [x] 6.7.5.4 Test: Active sessions excluded from resume list ✅
- [x] 6.7.5.5 Write all multi-session persistence tests ✅

### 6.7.6 Cleanup Integration
- [x] **Task 6.7.6** ✅

Test cleanup functionality integrates correctly.

- [x] 6.7.6.1 Test: `/resume delete` doesn't affect active sessions ✅
- [x] 6.7.6.2 Test: `/resume clear` doesn't affect active sessions ✅
- [x] 6.7.6.3 Test: Automatic cleanup doesn't affect active sessions ✅
- [x] 6.7.6.4 Test: Cleanup with active session having persisted file (edge case) ✅
- [x] 6.7.6.5 Write all cleanup integration tests (4 tests, 153/153 passing) ✅

**Integration Tests for Section 6.7:**
- Save-resume cycle preserves all session state
- Auto-save works with session close
- Resume command restores sessions correctly
- File format handles all edge cases
- Multi-session persistence works correctly
- Cleanup maintains data integrity

---

## Success Criteria

1. **Save on Close**: Sessions auto-save when closed
2. **Persistence Format**: JSON files with version for migrations
3. **Resume List**: `/resume` shows all resumable sessions
4. **Resume Restore**: `/resume <target>` restores session fully
5. **Conversation Restored**: Messages appear after resume
6. **Todos Restored**: Task list appears after resume
7. **Path Validation**: Clear error if project path missing
8. **File Cleanup**: Delete persisted file after resume
9. **Old Session Cleanup**: Sessions older than 30 days cleaned
10. **Test Coverage**: Minimum 80% coverage for phase 6 code
11. **Integration Tests**: All Phase 6 components work together correctly (Section 6.7)

---

## Critical Files

**New Files:**
- `lib/jido_code/session/persistence.ex`
- `test/jido_code/session/persistence_test.exs`
- `test/jido_code/integration/session_phase6_test.exs`

**Modified Files:**
- `lib/jido_code/session_supervisor.ex` - Auto-save on stop
- `lib/jido_code/commands.ex` - Add /resume command

---

## Dependencies

- **Depends on Phase 1**: Session struct, SessionRegistry
- **Depends on Phase 2**: Session.State for conversation data
- **Depends on Phase 5**: Command system for /resume

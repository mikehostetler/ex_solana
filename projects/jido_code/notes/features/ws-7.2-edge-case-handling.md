# Feature: Task 7.2 - Edge Case Handling

**Status**: Planning
**Phase**: 7 - Testing and Polish
**Priority**: High
**Dependencies**: Phase 7.1 (Integration Test Suite)

---

## Problem Statement

While the work-session feature has comprehensive functionality, production systems must handle edge cases gracefully to provide a robust user experience. Users encounter various exceptional scenarios in real-world usage:

- Session limits reached during creation or resume operations
- File system paths with special characters, spaces, or that become invalid mid-session
- Streaming responses interrupted by session closure or switching
- Persistence failures due to corrupted files, disk full, or missing directories

Without proper edge case handling, these scenarios can result in:
- Confusing error messages that don't guide users to resolution
- System crashes or inconsistent state
- Data loss or corruption
- Poor user experience

This task ensures all edge cases are handled gracefully with clear, actionable error messages that guide users to resolution.

---

## Solution Overview

We will systematically address edge cases across four categories:

### 1. Session Limit Edge Cases (7.2.1)
**Approach**: Enhanced error messages with session count feedback
- Display current session count when limit reached (e.g., "10/10 sessions open")
- Prevent both new session creation AND resume when at limit
- Provide actionable guidance: "Close a session first"

**Implementation**: Minimal - error messages already exist, need enhancement for clarity

### 2. Path Edge Cases (7.2.2)
**Approach**: Defensive path validation and normalization
- Handle paths with spaces via proper quoting in shell commands
- Normalize special characters during path resolution
- Follow symlinks and validate resolved paths against security boundaries
- Handle paths that become unavailable mid-session with graceful degradation

**Implementation**: Moderate - existing path validation needs enhancement for edge cases

### 3. State Edge Cases (7.2.3)
**Approach**: Defensive state management with lifecycle awareness
- Handle empty conversations gracefully (default state)
- Implement pagination for large conversations (already exists - verify behavior)
- Clean up streaming state on session close/switch
- Prevent state corruption during transitions

**Implementation**: Minimal - most patterns exist, need explicit edge case tests

### 4. Persistence Edge Cases (7.2.4)
**Approach**: Robust error recovery with graceful degradation
- Handle corrupted session files via validation and migration
- Auto-create missing directories with proper error fallback
- Handle disk full errors with atomic write rollback
- Prevent concurrent saves via per-session locks (already implemented)
- Handle deleted files with cleanup and re-initialization

**Implementation**: Minimal - comprehensive error handling exists, needs verification tests

---

## Current State Analysis

### What's Already Handled ✅

#### Session Limits
- ✅ `SessionRegistry.register/1` checks `max_sessions()` and returns `:session_limit_reached`
- ✅ `Persistence.save/1` checks session count limit and supports auto-cleanup
- ✅ Error sanitizer maps `:session_limit_reached` → "Maximum sessions reached."
- ✅ Commands show "Maximum 10 sessions reached. Close a session first."
- ❌ Missing: Session count in error message ("10/10 sessions open")

#### Path Validation
- ✅ `Commands.resolve_session_path/1` handles `~`, `.`, `..`, relative/absolute paths
- ✅ `Commands.validate_session_path/1` checks existence and directory status
- ✅ Forbidden system paths blocked (`/etc`, `/root`, etc.)
- ✅ `Persistence.validate_project_path/1` checks path exists and is directory
- ✅ TOCTOU protection caches and re-validates file stats during resume
- ✅ Symlinks followed and validated in Tools.Security
- ❌ Needs testing: Paths with spaces in shell commands
- ❌ Needs testing: Paths with special characters (unicode, etc.)
- ❌ Needs handling: Path becomes unavailable mid-session

#### State Management
- ✅ Empty conversation handled (new sessions start with empty list)
- ✅ Message pagination implemented (`Session.State` with page size limits)
- ✅ Streaming state tracked per-session (`streaming_message`, `streaming_message_id`)
- ✅ `State.start_streaming/2` and `State.end_streaming/1` manage lifecycle
- ❌ Needs testing: Streaming interruption on session close
- ❌ Needs testing: Streaming interruption on session switch
- ❌ Needs testing: Very large conversations (1000+ messages)

#### Persistence
- ✅ Corrupted JSON handled via `Jason.decode/1` error recovery
- ✅ Signature verification detects tampering (returns `:signature_verification_failed`)
- ✅ Missing directories handled via `ensure_sessions_dir/0` with `File.mkdir_p/1`
- ✅ Disk full errors handled via atomic write pattern (temp file + rename)
- ✅ Concurrent saves prevented via per-session ETS locks
- ✅ File size limits enforced (10MB default) to prevent DoS
- ✅ Comprehensive error sanitization via `ErrorSanitizer` module
- ✅ I/O failure tests cover permission errors, missing directories
- ❌ Needs testing: Session file deleted while session active
- ❌ Needs documentation: Recovery procedures for corrupted files

### What Needs Implementation ❌

1. **Session limit enhancement**: Add count to error message
2. **Path mid-session handling**: Detect and handle path deletion
3. **Streaming cleanup**: Explicit cleanup on session close/switch
4. **Edge case tests**: Comprehensive test coverage for all scenarios

---

## Technical Details

### Files to Modify

#### 1. Error Messages Enhancement
**File**: `/home/ducky/code/jido_code/lib/jido_code/commands.ex`

**Current**:
```elixir
{:error, :session_limit_reached} ->
  {:error, "Maximum 10 sessions reached. Close a session first."}
```

**Enhanced**:
```elixir
{:error, :session_limit_reached} ->
  current_count = JidoCode.SessionRegistry.count()
  max = JidoCode.SessionRegistry.max_sessions()
  {:error, "Maximum sessions reached (#{current_count}/#{max}). Close a session first."}
```

**Also in**: `/home/ducky/code/jido_code/lib/jido_code/session/persistence.ex` line 624

#### 2. Resume Command Session Limit
**File**: `/home/ducky/code/jido_code/lib/jido_code/session/persistence.ex`

**Location**: `resume/1` function (line 998)

**Add check**:
```elixir
def resume(session_id) when is_binary(session_id) do
  alias JidoCode.RateLimit

  with :ok <- RateLimit.check_global_rate_limit(:resume),
       :ok <- RateLimit.check_rate_limit(:resume, session_id),
       :ok <- check_resume_session_limit(),  # NEW
       {:ok, persisted} <- load(session_id),
       # ... rest of function
end

defp check_resume_session_limit do
  alias JidoCode.SessionRegistry

  if SessionRegistry.count() >= SessionRegistry.max_sessions() do
    {:error, :session_limit_reached}
  else
    :ok
  end
end
```

#### 3. Path Monitoring (Optional Enhancement)
**File**: `/home/ducky/code/jido_code/lib/jido_code/session/manager.ex`

**Approach**: Add periodic path validation check (low priority - can defer)

```elixir
# In Manager, add optional path monitor
def handle_info(:check_project_path, state) do
  # Schedule next check
  Process.send_after(self(), :check_project_path, 60_000)

  # Validate path still exists
  case File.dir?(state.session.project_path) do
    true ->
      {:noreply, state}
    false ->
      # Path disappeared - log warning but continue
      Logger.warning("Project path no longer exists: #{state.session.project_path}")
      {:noreply, state}
  end
end
```

**Note**: This is LOW priority as tools already validate paths on each execution.

#### 4. Streaming Cleanup on Session Close
**File**: `/home/ducky/code/jido_code/lib/jido_code/session/state.ex`

**Current**: `terminate/2` callback exists but may not explicitly clean streaming

**Verify**:
```elixir
def terminate(_reason, state) do
  # Ensure streaming state is cleared
  if state.streaming_message_id do
    Logger.debug("Session terminated during streaming - clearing state")
  end
  :ok
end
```

**Likely**: Already handled correctly via process termination, just needs test verification.

---

## Success Criteria

### 7.2.1 Session Limit Edge Cases
- [x] Error message shows count: "Maximum sessions reached (10/10). Close a session first."
- [x] Creating 11th session shows enhanced error
- [x] Resuming when at limit shows enhanced error
- [x] Test: Create 10 sessions → attempt 11th → verify error message format
- [x] Test: Create 10 sessions → close 1 → create new → succeeds

### 7.2.2 Path Edge Cases
- [x] Paths with spaces handled: `/path/with spaces/project` works in shell commands
- [x] Paths with unicode characters validated correctly
- [x] Symlinks followed and resolved path validated
- [x] Network paths (if applicable to platform) handled or explicitly rejected
- [x] Path deleted mid-session: Tools return appropriate errors, session continues
- [x] Test: Create session with space in path → run shell command → succeeds
- [x] Test: Create session via symlink → verify real path validated
- [x] Test: Delete project path while session active → next tool call fails gracefully

### 7.2.3 State Edge Cases
- [x] Empty conversation renders correctly (no errors)
- [x] Large conversation (1000+ messages) handled via pagination
- [x] Streaming interrupted by session close: State cleaned up, no orphaned data
- [x] Streaming interrupted by session switch: Previous session streaming cleared
- [x] Test: New session → verify empty conversation displays
- [x] Test: Session with 1000 messages → verify pagination works
- [x] Test: Start streaming → close session → verify cleanup
- [x] Test: Start streaming in session A → switch to B → verify A streaming cleared

### 7.2.4 Persistence Edge Cases
- [x] Corrupted JSON: Error logged, file skipped, user notified gracefully
- [x] Invalid signature: File rejected, error logged, user notified
- [x] Missing sessions directory: Auto-created on first save
- [x] Disk full on save: Temp file cleaned up, original unchanged, error returned
- [x] Concurrent saves: Per-session lock prevents, returns `:save_in_progress`
- [x] Session file deleted while active: Detected on next save, re-created if needed
- [x] Test: Create corrupted JSON file → attempt load → verify graceful error
- [x] Test: Delete sessions directory → attempt save → verify auto-creation
- [x] Test: Delete session file during active session → save → verify re-creation
- [x] Test: Concurrent save attempts → verify only one succeeds

---

## Implementation Plan

### Phase 1: Session Limit Enhancements (30 min)
**Priority**: High - User-facing improvement

1. Enhance error message in `Commands.execute_session/2` (new session)
2. Enhance error message in `Commands.execute_resume/2`
3. Add session limit check to `Persistence.resume/1`
4. Update error message in `Persistence.check_session_count_limit/1`
5. Write tests for enhanced error messages

**Files**:
- `lib/jido_code/commands.ex` (2 locations)
- `lib/jido_code/session/persistence.ex` (2 locations)
- `test/jido_code/session/persistence_session_limit_test.exs` (enhance)

### Phase 2: Path Edge Case Tests (45 min)
**Priority**: Medium - Validation of existing functionality

1. Create test file `test/jido_code/session/path_edge_cases_test.exs`
2. Test: Paths with spaces in shell commands
3. Test: Paths with unicode characters
4. Test: Symlink path validation
5. Test: Path deleted mid-session
6. Document path handling behavior in CLAUDE.md

**Files**:
- `test/jido_code/session/path_edge_cases_test.exs` (new)
- `CLAUDE.md` (document)

### Phase 3: State Edge Case Tests (45 min)
**Priority**: Medium - Validation of existing functionality

1. Create test file `test/jido_code/session/state_edge_cases_test.exs`
2. Test: Empty conversation handling
3. Test: Large conversation (1000+ messages)
4. Test: Streaming interrupted by close
5. Test: Streaming interrupted by switch
6. Verify `State.terminate/2` cleanup (if needed)

**Files**:
- `test/jido_code/session/state_edge_cases_test.exs` (new)
- `lib/jido_code/session/state.ex` (verify terminate)

### Phase 4: Persistence Edge Case Tests (45 min)
**Priority**: High - Critical data integrity

1. Enhance `test/jido_code/session/persistence_io_failure_test.exs`
2. Test: Corrupted JSON recovery
3. Test: Invalid signature handling
4. Test: Missing directory auto-creation
5. Test: Session file deleted while active
6. Document recovery procedures

**Files**:
- `test/jido_code/session/persistence_io_failure_test.exs` (enhance)
- `notes/features/ws-7.2-edge-case-handling.md` (recovery docs)

### Phase 5: Integration and Documentation (30 min)
**Priority**: Medium

1. Run all edge case tests together
2. Document edge case handling in CLAUDE.md
3. Create error message reference table
4. Update user-facing help text if needed

**Files**:
- `CLAUDE.md`
- `lib/jido_code/commands.ex` (help text review)

**Total Estimated Time**: 3.5 hours

---

## Test Strategy

### Test Organization

#### New Test Files
1. `test/jido_code/session/path_edge_cases_test.exs`
   - Paths with spaces
   - Unicode characters
   - Symlinks
   - Path deletion mid-session

2. `test/jido_code/session/state_edge_cases_test.exs`
   - Empty conversations
   - Large conversations
   - Streaming interruptions

#### Enhanced Test Files
3. `test/jido_code/session/persistence_session_limit_test.exs`
   - Enhanced error message format tests
   - Resume limit checks

4. `test/jido_code/session/persistence_io_failure_test.exs`
   - Corrupted JSON handling
   - Invalid signature handling
   - Session file deletion

### Test Categories by Priority

**High Priority** (Must Have):
- Session limit error messages with count
- Resume blocked at session limit
- Corrupted JSON recovery
- Disk full handling
- Streaming cleanup on close

**Medium Priority** (Should Have):
- Paths with spaces
- Unicode path handling
- Large conversation pagination
- Streaming interruption on switch
- Session file deleted while active

**Low Priority** (Nice to Have):
- Symlink validation edge cases
- Network paths (platform-specific)
- Path monitoring mid-session

### Test Patterns

Each test should follow this pattern:

```elixir
describe "edge case: [scenario]" do
  test "handles [scenario] gracefully" do
    # Setup: Create edge case condition
    # Execute: Trigger the edge case
    # Assert: Verify graceful handling
    # Assert: Verify error message is clear
    # Assert: Verify system remains stable
  end

  test "recovers from [scenario]" do
    # Verify system can continue after edge case
  end
end
```

### Coverage Goals
- **Session Limits**: 100% of error paths
- **Path Handling**: 90% coverage (some platform-specific paths may be hard to test)
- **State Management**: 95% coverage
- **Persistence**: 95% coverage (disk full hard to simulate)

---

## Error Message Reference

### Session Limit Errors

| Error Code | Current Message | Enhanced Message | Trigger |
|------------|----------------|------------------|---------|
| `:session_limit_reached` | "Maximum 10 sessions reached. Close a session first." | "Maximum sessions reached (10/10). Close a session first." | Creating 11th session |
| `:session_limit_reached` | "Maximum 10 sessions reached. Close a session first." | "Maximum sessions reached (10/10). Close a session first." | Resuming when at limit |

### Path Errors

| Error Code | Message | Action |
|------------|---------|--------|
| `:project_path_not_found` | "Project path no longer exists." | User must choose different path or recreate directory |
| `:project_path_not_directory` | "Project path is not a directory." | User must provide valid directory path |
| `:project_path_changed` | "Project path properties changed unexpectedly." | TOCTOU attack detected - refuse resume |
| `:path_not_found` | "Path does not exist: [path]" | User must provide valid path |
| `:path_not_directory` | "Path is not a directory: [path]" | User must provide directory, not file |

### State Errors

| Error Code | Message | Action |
|------------|---------|--------|
| `:not_found` | "Session not found." | Session was deleted or never existed |

### Persistence Errors

| Error Code | User Message | Internal Details | Recovery |
|------------|--------------|------------------|----------|
| `:signature_verification_failed` | "Data integrity check failed." | HMAC signature mismatch | Delete corrupted file, restart session |
| `{:json_decode_error, _}` | "Data format error." | Invalid JSON syntax | Delete corrupted file |
| `:enospc` | "Insufficient disk space." | Disk full | Free up space, retry |
| `:eacces` | "Permission denied." | No read/write access | Fix file permissions |
| `:enoent` | "Resource not found." | File doesn't exist | File was deleted |
| `:save_in_progress` | "Save operation already in progress." | Concurrent save attempt | Wait and retry |

---

## Recovery Procedures

### Corrupted Session File

**Symptom**: Cannot load or resume session

**Diagnosis**:
1. Check logs for "signature verification failed" or "invalid JSON"
2. Locate file: `~/.jido_code/sessions/[session-id].json`
3. Attempt to decode: `cat [file] | jq .` (should fail)

**Recovery**:
```bash
# Option 1: Delete corrupted file
rm ~/.jido_code/sessions/[session-id].json

# Option 2: Restore from backup (if available)
cp ~/.jido_code/sessions/backup/[session-id].json ~/.jido_code/sessions/

# Option 3: Manual repair (advanced)
# Edit JSON to fix syntax errors, remove signature field
```

### Missing Sessions Directory

**Symptom**: Cannot save or list sessions

**Recovery**: Directory is auto-created on next save. No manual action needed.

### Disk Full

**Symptom**: Save fails with "Insufficient disk space"

**Recovery**:
1. Free up disk space
2. Retry save operation
3. Original session file is unchanged (atomic write protection)

### Session Path Deleted Mid-Session

**Symptom**: Tool execution fails with path errors

**Recovery**:
1. Recreate the directory at original path, OR
2. Close session and create new session with valid path
3. Previous conversation history preserved in session state

---

## Open Questions

1. **Path monitoring frequency**: Should we add periodic path validation checks?
   - **Decision**: No - tool validation is sufficient. Adds complexity for minimal benefit.

2. **Streaming cleanup responsibility**: TUI vs State vs Manager?
   - **Decision**: State module handles via `terminate/2` callback. Clean separation of concerns.

3. **Corrupted file auto-delete**: Should we auto-delete corrupted files or require manual cleanup?
   - **Decision**: Keep manual for safety. Log detailed error, let user decide.

4. **Session limit at resume**: Hard error or offer to auto-close oldest session?
   - **Decision**: Hard error initially. Auto-cleanup is configurable via `auto_cleanup_on_limit` setting.

---

## Dependencies

**Depends on**:
- ✅ Phase 7.1 (Integration Test Suite) - provides test infrastructure
- ✅ `JidoCode.Commands.ErrorSanitizer` - error message sanitization
- ✅ `JidoCode.Session.Persistence` - persistence layer
- ✅ `JidoCode.SessionRegistry` - session tracking
- ✅ `JidoCode.Session.State` - state management

**Blocks**:
- 7.3 (Error Messages and UX) - builds on error handling patterns
- 7.6 (Final Checklist) - requires complete edge case coverage

---

## Success Metrics

1. **Error Message Quality**: All errors include actionable guidance
2. **System Stability**: No crashes on any edge case
3. **Data Integrity**: No data loss on any failure scenario
4. **Test Coverage**: 90%+ coverage for edge case paths
5. **User Experience**: Clear path from error to resolution

---

## Notes

### Design Decisions

1. **Enhanced vs New Error Messages**: Enhance existing messages rather than new error codes
   - Rationale: Maintains backward compatibility, improves UX without breaking changes

2. **Test Organization**: Separate edge case tests by category
   - Rationale: Makes it easy to run specific edge case categories, better organization

3. **Recovery Documentation**: Include in feature doc rather than separate runbook
   - Rationale: Developers need context during implementation, can extract to runbook later

### Implementation Notes

- Most edge cases are already handled - this task is primarily about verification and enhancement
- Focus on user-facing error messages - internal error handling is robust
- Streaming cleanup is the most complex edge case - may require careful review
- Path edge cases are mostly OS/platform dependent - test what's testable

### Future Enhancements

- Automatic session recovery from corrupted files (attempt to salvage conversation)
- Session state checkpointing for faster recovery
- Path migration tools (handle moved project directories)
- Session health monitoring dashboard

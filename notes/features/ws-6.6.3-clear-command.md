# Feature Plan: WS-6.6.3 - Clear All Command

**Status**: Planning
**Task**: Phase 6 - Task 6.6.3 - Clear All Command
**Dependencies**: Task 6.5.1 (Resume List), Task 6.6.2 (Delete Command), Persistence.list_persisted/0, Persistence.delete_persisted/1

---

## 1. Problem Statement

Users need a way to bulk-delete ALL persisted sessions at once. Currently available operations:

- **Automatic cleanup**: `cleanup(30)` removes sessions older than N days
- **Manual single delete**: `/resume delete <target>` removes one session at a time
- **Missing**: Bulk delete all persisted sessions regardless of age

**Use Cases:**

1. **Fresh start**: User wants to clear all saved sessions and start clean
2. **Disk space**: User wants to free up space by removing all session backups
3. **Testing/development**: Developer wants to clear test session files
4. **Privacy**: User wants to remove all session history at once

**Why Not Just Use `cleanup(0)`?**

While `cleanup(0)` would theoretically delete all sessions (age threshold = 0), it's:
- Not user-facing (internal function, not exposed via command)
- Semantically wrong (cleanup is about age, clear is about "all")
- Not designed for user confirmation patterns

---

## 2. Solution Overview

Extend the `/resume` command with a `clear` subcommand that deletes ALL persisted sessions at once.

**Command Syntax:**
```
/resume clear
```

**Behavior:**
- Lists count of sessions to be cleared
- Performs deletion of all persisted sessions
- Returns success message with count

**No Interactive Confirmation** (see Design Decision #1 below)

---

## 3. Design Decisions

### Decision 1: Confirmation Approach

**Options Considered:**

1. **Interactive y/n prompt** - Not feasible in TUI (no readline/interactive input support)
2. **Two-step command** - `/resume clear` preview, `/resume clear --confirm` execute
3. **Require --force flag** - `/resume clear --force` executes
4. **No confirmation** - Trust user knows what they're doing (chosen)

**Decision: No Confirmation (Option 4)**

**Rationale:**
- TUI doesn't support interactive prompts (not readline-based)
- Two-step or flag patterns add complexity for a rare operation
- User can always `/resume` first to see list before clearing
- Consistency: `/resume delete` doesn't require confirmation either
- Safety: Only deletes *persisted* files (not active sessions)
- Recoverable: Files are just backups, active sessions unaffected

**Safety Measures:**
- Clear message indicating count: "Cleared N saved session(s)."
- User can `/resume` to preview list before clearing
- Command is explicit (`/resume clear`, not accidental)
- Documentation will warn this is destructive

---

### Decision 2: Implementation Approach

**Options Considered:**

1. **Create `Persistence.clear_all()`** - New public function
2. **Iterate `delete_persisted/1`** - Use existing function in loop
3. **Use `cleanup(0)`** - Leverage existing cleanup logic with max_age=0

**Decision: Iterate `delete_persisted/1` (Option 2)**

**Rationale:**
- Reuses existing, tested function (`delete_persisted/1` is public and idempotent)
- Avoids creating new public API surface for rare operation
- Simple implementation in handler (no new Persistence functions)
- `cleanup/1` is semantically about age-based pruning, not bulk deletion

**Implementation Pattern:**
```elixir
def execute_resume(:clear, _model) do
  sessions = Persistence.list_persisted()
  count = length(sessions)

  if count > 0 do
    # Delete each session
    Enum.each(sessions, fn session ->
      Persistence.delete_persisted(session.id)
    end)

    {:ok, "Cleared #{count} saved session(s)."}
  else
    {:ok, "No saved sessions to clear."}
  end
end
```

**Why Not `clear_all()`?**
- Adding a new public function increases API surface
- The function would just iterate `delete_persisted/1` anyway
- Clear is a rare operation, not worth dedicated function
- Keeps Persistence module focused on core operations

**Why Not `cleanup(0)`?**
- Semantic mismatch (cleanup = age-based, clear = all)
- cleanup returns detailed stats, we just need count
- cleanup has logging for background process, clear is user-initiated
- Would require exposing cleanup in different way or adding flag

---

### Decision 3: Which List Function?

**Options:**

1. **`list_persisted()`** - All persisted sessions (including those for active projects)
2. **`list_resumable()`** - Only non-active sessions (safer)

**Decision: `list_persisted()` (Option 1)**

**Rationale:**
- Active sessions don't have persisted files (files only exist for closed sessions)
- When session is active, its persisted file is deleted (see `resume/1`)
- Therefore `list_persisted()` never includes active sessions anyway
- `list_resumable()` adds unnecessary filtering (same result in practice)
- Consistency with `cleanup/1` which uses `list_persisted()`

**Note:** Both functions return the same results because persisted files are deleted when sessions resume. We choose `list_persisted()` for clarity about what we're operating on.

---

### Decision 4: Error Handling

**Partial Failure Handling:**

Since we're iterating `delete_persisted/1`, individual deletions can fail. Options:

1. **Fail-fast** - Stop on first error, return error
2. **Collect errors** - Continue deleting, report failures at end
3. **Ignore errors** - Continue deleting, report only success count

**Decision: Ignore Errors (Option 3)**

**Rationale:**
- `delete_persisted/1` is idempotent (already-deleted returns `:ok`)
- Most common "error" is file already deleted (not really an error)
- User just wants sessions cleared, not detailed error reports
- Simple success message: "Cleared N saved session(s)."
- If a file is locked/permission denied, user can retry or manually delete
- Keep it simple for a simple use case

**Implementation:**
```elixir
Enum.each(sessions, fn session ->
  # Ignore result - delete_persisted is idempotent
  Persistence.delete_persisted(session.id)
end)
```

---

## 4. Technical Details

### 4.1 Command Parsing

**Location**: `lib/jido_code/commands.ex`

Add parsing clause (already exists in codebase):

```elixir
defp parse_and_execute("/resume clear" <> _, _config) do
  {:resume, :clear}
end

defp parse_and_execute("/resume delete " <> rest, _config) do
  {:resume, {:delete, String.trim(rest)}}
end

defp parse_and_execute("/resume " <> rest, _config) do
  {:resume, {:restore, String.trim(rest)}}
end

defp parse_and_execute("/resume", _config) do
  {:resume, :list}
end
```

**Important:** Order matters! `/resume clear` must come before `/resume " <> rest` to avoid treating "clear" as a restore target.

---

### 4.2 Handler Implementation

**Location**: `lib/jido_code/commands.ex` (execute_resume/2)

Add new function clause:

```elixir
@doc """
Executes a resume command.

## Parameters

- `subcommand` - The resume subcommand (`:list`, `{:restore, target}`, `{:delete, target}`, or `:clear`)
- `model` - The TUI model (used for context like active sessions)

## Returns

- `{:session_action, action}` - Action for TUI to perform (when resuming a session)
- `{:ok, message}` - Informational message (when listing, deleting, or clearing)
- `{:error, message}` - Error message
"""
@spec execute_resume(atom() | tuple(), map()) ::
        {:session_action, tuple()} | {:ok, String.t()} | {:error, String.t()}

def execute_resume(:clear, _model) do
  alias JidoCode.Session.Persistence

  sessions = Persistence.list_persisted()
  count = length(sessions)

  if count > 0 do
    # Delete all sessions (ignore individual errors)
    Enum.each(sessions, fn session ->
      Persistence.delete_persisted(session.id)
    end)

    {:ok, "Cleared #{count} saved session(s)."}
  else
    {:ok, "No saved sessions to clear."}
  end
end

def execute_resume(:list, _model) do
  # ... existing code ...
end

def execute_resume({:restore, target}, _model) do
  # ... existing code ...
end

def execute_resume({:delete, target}, _model) do
  # ... existing code ...
end
```

---

### 4.3 TUI Integration

**Location**: `lib/jido_code/tui.ex`

No changes needed! The existing `handle_resume_command/2` already dispatches all resume subcommands to `Commands.execute_resume/2`:

```elixir
defp handle_resume_command(subcommand, state) do
  case Commands.execute_resume(subcommand, state) do
    {:ok, message} ->
      # Display message
      update({:add_message, :system, message}, state)

    {:session_action, {:add_session, session}} ->
      # Handle session restoration
      # ... existing code ...

    {:error, message} ->
      # Display error
      update({:add_message, :error, message}, state)
  end
end
```

The `:clear` subcommand will return `{:ok, message}` and be displayed automatically.

---

### 4.4 Success/Error Messages

**Success Cases:**

1. **Sessions cleared**: `"Cleared 5 saved session(s)."`
2. **No sessions**: `"No saved sessions to clear."`

**Error Cases:**

None! The command always succeeds (returns `{:ok, message}`). Individual deletion errors are ignored because `delete_persisted/1` is idempotent.

---

### 4.5 Help Text Update

**Location**: `lib/jido_code/commands.ex` (@help_text)

Update `/resume` section:

```elixir
@help_text """
Available commands:
  ...
  /resume                  - List resumable sessions
  /resume <target>         - Resume session by index or ID
  /resume delete <target>  - Delete session by index or ID
  /resume clear            - Delete all saved sessions
  ...
"""
```

---

## 5. Success Criteria

**Functional Requirements:**

- [ ] `/resume clear` deletes all persisted session files
- [ ] Returns count of deleted sessions: "Cleared N saved session(s)."
- [ ] Returns "No saved sessions to clear." when none exist
- [ ] Works when sessions directory doesn't exist (no crash)
- [ ] Idempotent - safe to run multiple times
- [ ] Doesn't affect active sessions (only persisted files)

**Testing Requirements:**

- [ ] Unit tests pass for all scenarios
- [ ] Edge cases handled (empty list, already cleared, missing dir)
- [ ] Integration with TUI works (message displayed)
- [ ] Help text updated and accurate

**Quality Requirements:**

- [ ] Code follows existing patterns (execute_resume clauses)
- [ ] No new public API in Persistence module
- [ ] Documentation clear about destructive nature
- [ ] Consistent with delete command UX

---

## 6. Implementation Plan

### 6.1 Phase 1: Command Parsing

**File**: `lib/jido_code/commands.ex`

1. **Add parsing clause** for `/resume clear` (before generic `/resume <target>`)
2. **Update @help_text** to document `/resume clear`
3. **Update @doc for execute_resume/2** to mention `:clear` subcommand

**Testing:** Parse `/resume clear` returns `{:resume, :clear}`

---

### 6.2 Phase 2: Handler Implementation

**File**: `lib/jido_code/commands.ex`

1. **Add execute_resume(:clear, _model) clause**
   - Get sessions via `list_persisted()`
   - Count sessions with `length(sessions)`
   - If count > 0:
     - Iterate with `Enum.each(sessions, fn session -> delete_persisted(session.id) end)`
     - Return `{:ok, "Cleared #{count} saved session(s)."}`
   - If count == 0:
     - Return `{:ok, "No saved sessions to clear."}`

**Testing:** Handler deletes all sessions and returns correct message

---

### 6.3 Phase 3: Unit Testing

**File**: `test/jido_code/commands_test.exs`

Add test block:

```elixir
describe "/resume clear command" do
  test "parsing /resume clear" do
    result = Commands.execute("/resume clear", %{})
    assert {:resume, :clear} = result
  end

  test "clears all persisted sessions" do
    # Create 3 test sessions
    id1 = create_test_session("Session 1", days_ago(5))
    id2 = create_test_session("Session 2", days_ago(4))
    id3 = create_test_session("Session 3", days_ago(3))

    # Execute clear
    result = Commands.execute_resume(:clear, %{})

    assert {:ok, message} = result
    assert message == "Cleared 3 saved session(s)."

    # Verify all deleted
    assert {:error, :not_found} = Persistence.load(id1)
    assert {:error, :not_found} = Persistence.load(id2)
    assert {:error, :not_found} = Persistence.load(id3)
  end

  test "returns no sessions message when empty" do
    # No sessions exist
    result = Commands.execute_resume(:clear, %{})

    assert {:ok, "No saved sessions to clear."} = result
  end

  test "is idempotent - clearing twice" do
    # Create session
    _id = create_test_session("Session", days_ago(5))

    # Clear once
    result1 = Commands.execute_resume(:clear, %{})
    assert {:ok, "Cleared 1 saved session(s)."} = result1

    # Clear again
    result2 = Commands.execute_resume(:clear, %{})
    assert {:ok, "No saved sessions to clear."} = result2
  end

  test "only clears persisted sessions, not active ones" do
    # Note: Active sessions don't have persisted files, so this is
    # implicitly tested. list_persisted() never returns active sessions
    # because their files are deleted on resume.

    # This test just verifies the behavior is as expected
    result = Commands.execute_resume(:clear, %{})
    assert {:ok, _} = result  # Should not crash or affect active sessions
  end
end
```

**Helper:** Use existing `create_test_session/2` helper from delete tests

---

### 6.4 Phase 4: Documentation

1. **Update @doc for execute_resume/2** - Mention `:clear` subcommand
2. **Update @help_text** - Document `/resume clear`
3. **Update CLAUDE.md** - Add `/resume clear` to command table
4. **Task completion** - Mark Task 6.6.3 complete in phase-06.md

---

## 7. Testing Strategy

### 7.1 Unit Tests

**Test Coverage:**

1. **Parsing test** - `/resume clear` returns `{:resume, :clear}`
2. **Clear multiple sessions** - Deletes all, returns correct count
3. **Clear empty list** - Returns "No saved sessions" message
4. **Idempotent** - Clearing twice is safe
5. **Active sessions unaffected** - Implicit (persisted files only)

**Test Location:** `test/jido_code/commands_test.exs`

**Test Pattern:** Follow existing delete command test structure

---

### 7.2 Integration Tests

**Manual Testing:**

1. Create 3 sessions with `/session new`
2. Close all 3 sessions (they get persisted)
3. Run `/resume` to see list (3 sessions)
4. Run `/resume clear`
5. Verify message: "Cleared 3 saved session(s)."
6. Run `/resume` again, verify: "No resumable sessions available."
7. Run `/resume clear` again, verify: "No saved sessions to clear."

**Edge Cases:**

1. `/resume clear` when sessions directory doesn't exist (no crash)
2. `/resume clear` with mixed file permissions (graceful handling)
3. `/resume clear` with active sessions (doesn't affect them)

---

### 7.3 Test Helpers

Reuse existing helpers from delete command tests:

```elixir
defp create_test_session(name, closed_at) do
  # Creates a persisted session file with given name and closed_at timestamp
  # Returns session_id for verification
end

defp days_ago(n) do
  # Returns ISO 8601 timestamp for N days ago
end
```

**Location:** `test/jido_code/commands_test.exs` (already exists)

---

## 8. Edge Cases

### 8.1 Empty Session List

**Scenario:** No persisted sessions exist

**Expected Behavior:**
- `list_persisted()` returns `[]`
- `length([])` returns `0`
- Function returns `{:ok, "No saved sessions to clear."}`
- No errors, no crashes

**Test:** Create test with no sessions, verify message

---

### 8.2 Sessions Directory Missing

**Scenario:** `~/.jido_code/sessions/` doesn't exist

**Expected Behavior:**
- `list_persisted()` handles gracefully (returns `[]` on `:enoent`)
- Clear command returns "No saved sessions to clear."
- No directory creation, no errors

**Current Implementation:** `list_persisted()` already handles this:

```elixir
def list_persisted do
  case File.ls(dir) do
    {:ok, files} -> # ... process files ...
    {:error, :enoent} -> []  # Directory doesn't exist
    {:error, reason} -> []   # Other errors
  end
end
```

**Test:** Not needed - `list_persisted/0` already tested for this

---

### 8.3 Partial Deletion Failures

**Scenario:** Some files fail to delete (permissions, locked files)

**Expected Behavior:**
- Continue deleting remaining files (no fail-fast)
- `delete_persisted/1` returns `{:error, reason}` for failed files
- Clear command ignores errors, reports total count attempted
- Message still says "Cleared N saved session(s)."

**Rationale:**
- User wants sessions cleared, not detailed error reports
- Most "errors" are files already deleted (idempotent behavior)
- Simple success message is sufficient
- User can retry if needed

**Test:** Not critical - real-world errors rare, idempotent behavior handles most cases

---

### 8.4 Active Sessions Present

**Scenario:** User has active sessions and runs `/resume clear`

**Expected Behavior:**
- Active sessions have no persisted files (files deleted on resume)
- `list_persisted()` returns only closed sessions
- Clear command deletes only persisted files
- Active sessions completely unaffected

**Note:** This is implicit behavior. When a session is resumed, its persisted file is deleted (see `resume/1` function). Therefore, active sessions never have persisted files, and `list_persisted()` never includes them.

**Test:** Verify clear doesn't crash with active sessions (simple smoke test)

---

### 8.5 Idempotent Behavior

**Scenario:** Running `/resume clear` multiple times

**Expected Behavior:**
- First run: "Cleared N saved session(s)."
- Second run: "No saved sessions to clear."
- Third run: "No saved sessions to clear."
- No errors, no crashes

**Test:** Clear twice, verify both return success with appropriate messages

---

### 8.6 Invalid Session Files

**Scenario:** Session file exists but is corrupted/invalid JSON

**Expected Behavior:**
- `list_persisted()` skips corrupted files gracefully (returns nil from `load_session_metadata/1`)
- Corrupted files won't be in the list to delete
- User would need to manually delete corrupted files

**Note:** This is existing behavior of `list_persisted()`. Clear command doesn't need special handling.

**Test:** Not needed - `list_persisted/0` already tested for this

---

## 9. Comparison with Related Commands

### 9.1 vs. `/resume delete <target>`

| Aspect | `/resume delete` | `/resume clear` |
|--------|------------------|-----------------|
| Scope | Single session | All sessions |
| Target | Requires index/UUID | No target needed |
| Confirmation | None | None |
| Message | "Deleted saved session." | "Cleared N saved session(s)." |
| Use Case | Remove specific session | Fresh start |

---

### 9.2 vs. `cleanup(30)`

| Aspect | `cleanup/1` | `/resume clear` |
|--------|-------------|-----------------|
| Trigger | Automatic/internal | User command |
| Scope | Old sessions (> N days) | All sessions |
| Criteria | Age-based | None (all) |
| Return | Detailed stats | Simple message |
| API | Internal function | User-facing command |

---

## 10. Security Considerations

### 10.1 Path Validation

**Concern:** Could clear command be exploited to delete arbitrary files?

**Mitigation:**
- Uses `list_persisted()` which only lists files in sessions directory
- Uses `delete_persisted(session_id)` which validates UUID format
- Session IDs validated against UUID v4 regex (prevents path traversal)
- Files outside sessions directory cannot be affected

**Conclusion:** No security risk. Clear command cannot escape sessions directory.

---

### 10.2 Destructive Operation

**Concern:** Accidental data loss

**Mitigation:**
- Command is explicit: `/resume clear` (not accidental)
- User can preview with `/resume` before clearing
- Only affects backup files (persisted sessions), not active sessions
- Active work unaffected (sessions keep running)
- Help text will warn about destructive nature

**Recommendation:** Document in help/CLAUDE.md that clear is destructive

---

### 10.3 Race Conditions

**Concern:** Session closed/persisted during clear operation

**Scenario:**
1. User runs `/resume clear`
2. While iterating, another session closes and persists
3. New file not included in original list

**Impact:** Minor - new file won't be deleted in this run

**Mitigation:** Not needed - this is acceptable behavior. User can run clear again if needed.

---

## 11. Future Enhancements (Out of Scope)

### 11.1 Selective Clear

Could add flags for selective clearing:

```
/resume clear --older-than 30   # Clear sessions older than 30 days
/resume clear --project /path   # Clear sessions for specific project
/resume clear --pattern "test*" # Clear sessions matching name pattern
```

**Decision:** Not needed for MVP. Use `cleanup/1` for age-based, `/resume delete` for specific sessions.

---

### 11.2 Preview Mode

Could add dry-run flag:

```
/resume clear --dry-run   # Show what would be deleted
```

**Decision:** Not needed. User can run `/resume` to see list before clearing.

---

### 11.3 Undo Capability

Could implement session restore from trash:

```
/resume clear            # Moves to trash instead of deleting
/resume restore-trash    # Restore from trash
```

**Decision:** Out of scope. Sessions are just backups, not primary data.

---

## 12. Implementation Checklist

### Pre-Implementation

- [x] Review existing delete command implementation
- [x] Review Persistence.list_persisted() behavior
- [x] Review cleanup() function for patterns
- [x] Document design decisions

### Implementation

- [ ] Add `/resume clear` parsing clause to Commands.execute/2
- [ ] Add execute_resume(:clear, _model) handler
- [ ] Update @help_text with `/resume clear`
- [ ] Update @doc for execute_resume/2

### Testing

- [ ] Write unit tests for parsing `/resume clear`
- [ ] Write unit test for clearing multiple sessions
- [ ] Write unit test for empty session list
- [ ] Write unit test for idempotent behavior
- [ ] Verify all tests pass

### Documentation

- [ ] Update CLAUDE.md command table
- [ ] Update execute_resume/2 @doc
- [ ] Mark Task 6.6.3 complete in phase-06.md

### Verification

- [ ] Manual test: Clear multiple sessions
- [ ] Manual test: Clear when empty
- [ ] Manual test: Idempotent (run twice)
- [ ] Code review: Matches existing patterns
- [ ] No new Persistence public functions added

---

## 13. Notes

### Implementation Simplicity

This is one of the simpler Phase 6 tasks because:

1. **No new Persistence functions** - Uses existing `list_persisted()` and `delete_persisted/1`
2. **No TUI changes** - Existing `handle_resume_command/2` handles it
3. **Simple logic** - Just iterate and delete, count results
4. **No confirmation UI** - Straightforward command execution
5. **Follows established patterns** - Similar to delete command

### Estimated Effort

- **Coding:** 15 minutes (one function, one parser clause)
- **Testing:** 20 minutes (4-5 unit tests)
- **Documentation:** 10 minutes (help text, @doc)
- **Total:** ~45 minutes

### Dependencies

**Completed:**
- ✅ Task 6.4.1 - Load Persisted (provides `list_persisted()`)
- ✅ Task 6.5.1 - Resume Command (provides TUI integration)
- ✅ Task 6.6.1 - Cleanup (provides `delete_persisted/1` public)
- ✅ Task 6.6.2 - Delete Command (provides command pattern)

**No Blockers** - All dependencies complete and tested

---

## 14. References

### Related Tasks

- **Task 6.4.1** - Load Persisted Session (list_persisted/0)
- **Task 6.5.1** - Resume Command Infrastructure (TUI integration)
- **Task 6.6.1** - Session Cleanup (delete_persisted/1 made public)
- **Task 6.6.2** - Delete Command (pattern for manual delete)

### Related Files

- `lib/jido_code/commands.ex` - Command parsing and execution
- `lib/jido_code/session/persistence.ex` - list_persisted/0, delete_persisted/1
- `lib/jido_code/tui.ex` - handle_resume_command/2
- `test/jido_code/commands_test.exs` - Unit tests

### Related Documentation

- `notes/planning/work-session/phase-06.md` - Task definition (lines 472-491)
- `notes/features/ws-6.6.2-delete-command.md` - Delete command pattern
- `notes/features/ws-6.6.1-session-cleanup.md` - Cleanup implementation
- `CLAUDE.md` - Command documentation

---

**End of Feature Plan**

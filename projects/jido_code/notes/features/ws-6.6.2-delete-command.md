# Feature Plan: Task 6.6.2 - Delete Command

## Metadata
- **Task ID**: 6.6.2
- **Phase**: 6 (Session Persistence)
- **Parent Plan**: notes/planning/work-session/phase-06.md
- **Status**: Planning Complete
- **Dependencies**:
  - Task 6.4.1 (Load Persisted Session) - Complete
  - Task 6.4.2 (Resume Persisted Session) - Complete
  - Task 6.5.1 (Resume Command) - Complete
  - Task 6.6.1 (Cleanup Command) - Complete (delete_persisted/1 now public)
- **Created**: 2025-12-10
- **Author**: Feature Planning Agent

---

## 1. Problem Statement

### Current Situation
Users can resume persisted sessions using `/resume <target>`, which loads the session file, restores state, and starts the session processes. However, there is no way to manually delete a persisted session without resuming it first.

### Why This Matters
- **Disk Space Management**: Users may accumulate unwanted session files that consume disk space
- **Privacy**: Users may want to permanently delete sessions containing sensitive information
- **Organization**: Users need to clean up old or test sessions without waiting for automatic cleanup
- **Granular Control**: While `cleanup/1` exists for batch deletion by age, users need per-session control

### Problem Scope
- Users can only delete sessions by:
  1. Manually deleting JSON files in `~/.jido_code/sessions/`
  2. Waiting for automatic cleanup (30-day default)
  3. Resuming unwanted sessions and closing them (doesn't delete the file)

### User Story
> "As a user, I want to delete specific persisted sessions by index or UUID so that I can manage my session storage without resuming unwanted sessions."

---

## 2. Solution Overview

Extend the `/resume` command family with a `delete` subcommand that removes persisted session files.

### Command Syntax
```
/resume delete <target>
```

Where `<target>` can be:
- **Numeric index** (1, 2, 3, etc.) - from `/resume` list output
- **Session UUID** - the full session ID

### Behavior
1. Parse `/resume delete <target>` command
2. Get list of resumable sessions (excludes active sessions)
3. Resolve target to session ID (index or UUID)
4. Call `delete_persisted(session_id)` to remove file
5. Return success message: "Deleted saved session."
6. Handle errors gracefully (not found, invalid format, etc.)

### Design Principles
- **Consistency**: Use same target resolution as `/resume <target>` (index/UUID)
- **Safety**: Only delete from resumable list (prevents deleting active session files)
- **Simplicity**: No confirmation prompt - user can `/resume list` first if unsure
- **Idempotency**: Already-deleted sessions return success (via delete_persisted behavior)

---

## 3. Technical Details

### 3.1 Command Parsing

**Location**: `lib/jido_code/commands.ex`

**Pattern Extension**:
```elixir
# Existing patterns:
defp parse_and_execute("/resume " <> rest, _config) do
  {:resume, {:restore, String.trim(rest)}}
end

defp parse_and_execute("/resume", _config) do
  {:resume, :list}
end

# NEW pattern to add:
defp parse_and_execute("/resume delete " <> rest, _config) do
  {:resume, {:delete, String.trim(rest)}}
end

# Special case: "/resume delete" with no target
defp parse_and_execute("/resume delete", _config) do
  {:error, "Usage: /resume delete <index|id>\n\nUse /resume to list available sessions."}
end
```

**Parsing Order Matters**: The `"/resume delete "` pattern must be checked BEFORE the generic `"/resume "` pattern, otherwise all delete commands will be interpreted as restore attempts.

### 3.2 Handler Implementation

**Location**: `lib/jido_code/commands.ex` (execute_resume/2)

**New Function Clause**:
```elixir
def execute_resume({:delete, target}, _model) do
  alias JidoCode.Session.Persistence

  case Persistence.list_resumable() do
    {:ok, sessions} ->
      case resolve_resume_target(target, sessions) do
        {:ok, session_id} ->
          case Persistence.delete_persisted(session_id) do
            :ok ->
              {:ok, "Deleted saved session.", :no_change}

            {:error, reason} ->
              {:error, "Failed to delete session: #{inspect(reason)}"}
          end

        {:error, error_message} ->
          {:error, error_message}
      end

    {:error, reason} ->
      {:error, "Failed to list resumable sessions: #{inspect(reason)}"}
  end
end
```

### 3.3 Helper Functions (Already Exist)

**list_resumable/0** (lib/jido_code/session/persistence.ex:607)
- Returns list of persisted sessions excluding active ones
- Returns `{:ok, sessions}` or `{:error, reason}`
- Each session: `%{id: ..., name: ..., project_path: ..., closed_at: ...}`

**resolve_resume_target/2** (lib/jido_code/commands.ex:692)
- Resolves numeric index (1-based) or UUID string to session ID
- Returns `{:ok, session_id}` or `{:error, message}`
- Error messages:
  - `"Invalid index: N. Valid range is 1-M."`
  - `"Session not found: <uuid>"`

**delete_persisted/1** (lib/jido_code/session/persistence.ex:1356)
- Deletes session file by ID
- Returns `:ok` (success or already deleted) or `{:error, reason}`
- Idempotent: `:enoent` is treated as success
- Validates session ID format (UUID v4)

### 3.4 Return Value Convention

The handler returns one of:
- `{:ok, message}` - Success, display message to user
- `{:error, message}` - Failure, display error to user

**Note**: Unlike restore which returns `{:session_action, {:add_session, session}}`, delete returns a simple message since no state change occurs (TUI model doesn't track persisted files).

### 3.5 Error Handling Strategy

**Error Cases and Messages**:

| Error Condition | User Message |
|----------------|--------------|
| No target provided | "Usage: /resume delete <index\|id>\n\nUse /resume to list available sessions." |
| Invalid index (out of range) | "Invalid index: N. Valid range is 1-M." |
| UUID not found | "Session not found: <uuid>" |
| list_resumable fails | "Failed to list resumable sessions: <reason>" |
| delete_persisted fails | "Failed to delete session: <reason>" |

**Design Decisions**:
- Use same error messages as `/resume <target>` for consistency
- Don't distinguish between "not found" and "already deleted" (both are success states)
- Provide actionable guidance ("Use /resume to list...")

### 3.6 TUI Integration

**Location**: `lib/jido_code/tui.ex:1224-1246`

**Existing Handler** (handle_resume_command/2):
```elixir
defp handle_resume_command(subcommand, state) do
  case Commands.execute_resume(subcommand, state) do
    {:session_action, {:add_session, session}} ->
      # ... add session to model ...

    {:ok, message} ->
      # ... display message ...

    {:error, error_message} ->
      # ... display error ...
  end
end
```

**No Changes Required**: The delete command returns `{:ok, message}`, which is already handled by the existing `{:ok, message}` clause. The TUI will display "Deleted saved session." as a system message.

---

## 4. Success Criteria

### Functional Requirements
- [ ] `/resume delete 1` deletes the first resumable session
- [ ] `/resume delete <uuid>` deletes session by UUID
- [ ] Success message displayed: "Deleted saved session."
- [ ] Error messages match existing resume command style
- [ ] Command only deletes from resumable list (not active sessions)
- [ ] Idempotent: deleting twice doesn't error

### Non-Functional Requirements
- [ ] Command parsing is unambiguous (delete pattern before restore)
- [ ] Follows existing code conventions and patterns
- [ ] No TUI changes required (reuses existing message display)
- [ ] Uses public delete_persisted/1 function (Task 6.6.1)

### Testing Requirements
- [ ] Unit tests for command parsing
- [ ] Unit tests for execute_resume({:delete, target}, model)
- [ ] Error case coverage (no target, invalid index, not found)
- [ ] Integration test: delete via TUI command flow

---

## 5. Implementation Plan

### 5.1 Phase 1: Command Parsing (Est: 10 min)
**File**: `lib/jido_code/commands.ex`

**Steps**:
1. Add `"/resume delete " <> rest` pattern BEFORE existing `/resume` pattern
2. Add error case for `"/resume delete"` with no arguments
3. Return `{:resume, {:delete, String.trim(rest)}}`

**Testing**: Manually verify parsing returns correct tuple

### 5.2 Phase 2: Handler Implementation (Est: 15 min)
**File**: `lib/jido_code/commands.ex`

**Steps**:
1. Add `execute_resume({:delete, target}, _model)` function clause
2. Call `Persistence.list_resumable()`
3. Call `resolve_resume_target(target, sessions)` (reuse existing helper)
4. Call `Persistence.delete_persisted(session_id)`
5. Return `{:ok, "Deleted saved session.", :no_change}`
6. Handle all error cases with appropriate messages

**Testing**: Write unit tests for handler

### 5.3 Phase 3: Unit Tests (Est: 20 min)
**File**: `test/jido_code/commands_test.exs`

**Test Cases**:
```elixir
describe "/resume delete command" do
  test "parses /resume delete with numeric index" do
    assert {:resume, {:delete, "1"}} = Commands.parse_and_execute("/resume delete 1", %{})
  end

  test "parses /resume delete with UUID" do
    uuid = "550e8400-e29b-41d4-a716-446655440000"
    assert {:resume, {:delete, ^uuid}} = Commands.parse_and_execute("/resume delete #{uuid}", %{})
  end

  test "returns error for /resume delete without target" do
    assert {:error, message} = Commands.parse_and_execute("/resume delete", %{})
    assert message =~ "Usage: /resume delete"
  end
end

describe "execute_resume({:delete, target}, model)" do
  setup do
    # Create test session file
    # ... setup code ...
  end

  test "deletes session by numeric index" do
    assert {:ok, message} = Commands.execute_resume({:delete, "1"}, %{})
    assert message == "Deleted saved session."
  end

  test "deletes session by UUID" do
    uuid = "550e8400-e29b-41d4-a716-446655440000"
    assert {:ok, message} = Commands.execute_resume({:delete, uuid}, %{})
    assert message == "Deleted saved session."
  end

  test "returns error for invalid index" do
    assert {:error, message} = Commands.execute_resume({:delete, "99"}, %{})
    assert message =~ "Invalid index"
  end

  test "returns error for unknown UUID" do
    unknown = "99999999-9999-4999-8999-999999999999"
    assert {:error, message} = Commands.execute_resume({:delete, unknown}, %{})
    assert message =~ "Session not found"
  end

  test "is idempotent - deleting twice succeeds" do
    assert {:ok, _} = Commands.execute_resume({:delete, "1"}, %{})
    assert {:ok, _} = Commands.execute_resume({:delete, "1"}, %{})
  end
end
```

**Test Strategy**:
- Use test fixtures from existing resume tests
- Verify file is actually deleted from disk
- Test both index and UUID resolution paths
- Cover all error cases
- Verify idempotency

### 5.4 Phase 4: Integration Testing (Est: 10 min)
**Manual Testing**:

```bash
# Terminal 1: Start JidoCode
iex -S mix
JidoCode.TUI.run()

# Create and close a session to generate a persisted file
/session new /tmp/test-delete
# ... do some work ...
/session close

# List resumable sessions
/resume
# Output: "1. test-delete (/tmp/test-delete) - closed 1 min ago"

# Delete by index
/resume delete 1
# Output: "Deleted saved session."

# Verify deletion
/resume
# Output: "No resumable sessions available."

# Test error case
/resume delete 99
# Output: "Invalid index: 99. Valid range is 1-0."

# Test without target
/resume delete
# Output: "Usage: /resume delete <index|id>..."
```

### 5.5 Phase 5: Documentation Update (Est: 5 min)
**Files**:
- `lib/jido_code/commands.ex` - Update @help_text
- Update help output to include `/resume delete <target>`

**New Help Text**:
```elixir
/resume                  - List resumable sessions
/resume <target>         - Resume session by index or ID
/resume delete <target>  - Delete persisted session by index or ID
```

---

## 6. Testing Strategy

### 6.1 Unit Tests

**Parsing Tests** (test/jido_code/commands_test.exs):
- Parse `/resume delete 1` returns `{:resume, {:delete, "1"}}`
- Parse `/resume delete <uuid>` returns `{:resume, {:delete, uuid}}`
- Parse `/resume delete` returns error with usage message
- Whitespace handling: `/resume delete  1  ` trims correctly

**Execution Tests** (test/jido_code/commands_test.exs):
- Delete by numeric index succeeds
- Delete by UUID succeeds
- Invalid index returns error
- Non-existent UUID returns error
- list_resumable failure propagates error
- delete_persisted failure propagates error
- Idempotency: deleting twice succeeds

**Helper Tests** (if needed):
- resolve_resume_target already tested in Task 6.5.1
- delete_persisted already tested in Task 6.6.1
- No new helper functions needed

### 6.2 Integration Tests

**TUI Command Flow**:
- Execute `/resume delete 1` via TUI
- Verify system message appears
- Verify file removed from disk
- Verify `/resume` list updated

**Error Flow**:
- Execute `/resume delete 99`
- Verify error message displays in TUI
- File should not exist (or remain if different session)

### 6.3 Edge Cases

| Edge Case | Expected Behavior | Test Coverage |
|-----------|-------------------|---------------|
| Delete active session's file | Not in resumable list, target not found | Unit test |
| Delete with leading/trailing spaces | Trimmed, resolves correctly | Unit test |
| Delete with uppercase UUID | Should match (case-insensitive?) | Check existing behavior |
| Delete when no sessions exist | "Session not found" or empty list | Unit test |
| Delete with malformed UUID | "Session not found" | Unit test |
| Delete during concurrent resume | Race condition - document behavior | Out of scope |

**Note on Active Sessions**: The `list_resumable()` function explicitly excludes active sessions, so attempting to delete by an index that doesn't exist in the resumable list will return "Invalid index". Attempting to delete by the UUID of an active session will return "Session not found".

### 6.4 Test Data Setup

**Use Existing Helpers** (from persistence_resume_test.exs):
```elixir
# Helper to create test session file
defp create_test_session(tmp_dir) do
  session_id = UUID.uuid4()
  persisted = Persistence.new_session(%{
    id: session_id,
    name: "Test Session",
    project_path: tmp_dir,
    conversation: [],
    todos: []
  })
  :ok = Persistence.write_session_file(session_id, persisted)
  session_id
end

# Cleanup helper
defp cleanup_test_session(session_id) do
  Persistence.delete_persisted(session_id)
end
```

---

## 7. Error Messages Reference

### User-Facing Errors

**No Target**:
```
Usage: /resume delete <index|id>

Use /resume to list available sessions.
```

**Invalid Index**:
```
Invalid index: 99. Valid range is 1-5.
```

**Session Not Found (UUID)**:
```
Session not found: 550e8400-e29b-41d4-a716-446655440000
```

**List Failed**:
```
Failed to list resumable sessions: :eacces
```

**Delete Failed**:
```
Failed to delete session: :eacces
```

### Internal Errors (Logged but Not User-Facing)
- Path validation errors (session_id not UUID format) - raises ArgumentError
- File system errors (permission denied) - returned as `{:error, reason}`

---

## 8. Security Considerations

### Path Traversal Prevention
- **Already Handled**: `delete_persisted/1` validates session ID is UUID v4 format
- **Already Handled**: `session_file/1` sanitizes session ID as defense-in-depth
- No additional path validation needed

### Active Session Protection
- **Design Decision**: Use `list_resumable()` instead of `list_persisted()`
- **Rationale**: Prevents deleting session files for currently running sessions
- **Behavior**: Attempting to delete an active session returns "Session not found"
- **Edge Case**: If session closes between list and delete, deletion succeeds (acceptable)

### Permission Errors
- **Handled**: `delete_persisted/1` returns `{:error, :eacces}` on permission denied
- **User Message**: "Failed to delete session: :eacces"
- **Recovery**: User must fix file permissions manually

### Race Conditions
- **Scenario**: User deletes while another process resumes the same session
- **Behavior**: Whoever wins the race (resume loads, delete removes)
- **Impact**: Resume may fail with `:not_found` if delete wins
- **Mitigation**: None needed - user-initiated actions, rare occurrence
- **Documentation**: Mention in command help that concurrent operations may race

---

## 9. Alternative Designs Considered

### 9.1 Confirmation Prompt
**Design**: Prompt user "Are you sure? (y/n)" before deleting

**Pros**:
- Prevents accidental deletion
- Common pattern in destructive operations

**Cons**:
- Adds complexity to TUI (need confirmation state)
- User can `/resume list` before delete if unsure
- Breaks consistency with other commands (no confirmations currently)
- Harder to script/automate

**Decision**: **Rejected** - Keep it simple, users can verify first

### 9.2 Delete Multiple Sessions
**Design**: `/resume delete 1,2,3` or `/resume delete all`

**Pros**:
- Faster for bulk cleanup
- Useful for clearing old sessions

**Cons**:
- Scope creep for this task
- `cleanup/1` already handles bulk deletion by age
- Parsing complexity (comma-separated list)
- Error handling complexity (partial failures)

**Decision**: **Rejected** - Out of scope, use cleanup for bulk

### 9.3 Soft Delete (Move to Trash)
**Design**: Move deleted files to `.jido_code/trash/` instead of removing

**Pros**:
- Allows recovery from accidental deletion
- Common pattern in file managers

**Cons**:
- Adds complexity (trash management, expiration)
- Increases disk usage
- Out of scope for this task

**Decision**: **Rejected** - Hard delete is sufficient, users want space back

### 9.4 Delete by Name
**Design**: `/resume delete "Test Session"` deletes by session name

**Pros**:
- More user-friendly than UUID
- Consistent with `/session switch <name>`

**Cons**:
- Name may not be unique across persisted sessions
- Requires name matching logic (exact? prefix? fuzzy?)
- `/resume` list shows index, easier to use index

**Decision**: **Rejected** - Index is sufficient, UUID for precision

---

## 10. Future Enhancements

### 10.1 Batch Delete (Future Task 6.6.3?)
```
/resume delete 1,2,3     # Delete multiple by index
/resume delete all       # Delete all resumable sessions
```

**Requirements**:
- Parse comma-separated indices
- Call delete_persisted for each
- Report successes and failures separately
- Atomic or best-effort?

### 10.2 Undo Last Delete
```
/resume undelete         # Restore most recently deleted session
```

**Requirements**:
- Move to trash instead of hard delete
- Track deletion order
- Limit undo history (e.g., last 5)

### 10.3 Delete with Confirmation Flag
```
/resume delete 1 --confirm    # Skip confirmation if added later
```

**Requirements**:
- If confirmation prompt added, allow bypass
- Useful for scripting

---

## 11. Documentation Requirements

### 11.1 User-Facing Help Text
**Location**: `lib/jido_code/commands.ex` (@help_text)

**Addition**:
```
/resume delete <target>  - Delete persisted session by index or ID
```

### 11.2 Module Documentation
**Location**: `lib/jido_code/commands.ex` (module @moduledoc)

**Addition to Available Commands Table**:
```markdown
| `/resume delete <target>` | Delete persisted session |
```

### 11.3 Function Documentation
**Location**: `lib/jido_code/commands.ex` (execute_resume/2)

**Addition to @doc**:
```elixir
@doc """
Executes a resume command.

## Parameters

- `subcommand` - The resume subcommand:
  - `:list` - List resumable sessions
  - `{:restore, target}` - Resume session by index or UUID
  - `{:delete, target}` - Delete session by index or UUID
- `model` - The TUI model (used for context like active sessions)

## Returns

- `{:session_action, action}` - Action for TUI to perform (when resuming)
- `{:ok, message}` - Informational message (list or delete success)
- `{:error, message}` - Error message

## Examples

    iex> Commands.execute_resume(:list, model)
    {:ok, "Resumable sessions:\n\n  1. project..."}

    iex> Commands.execute_resume({:restore, "1"}, model)
    {:session_action, {:add_session, %Session{...}}}

    iex> Commands.execute_resume({:delete, "1"}, model)
    {:ok, "Deleted saved session.", :no_change}
"""
```

### 11.4 CLAUDE.md Update
**Location**: `CLAUDE.md` (Commands table)

**Addition**:
```markdown
| `/resume delete <target>` | Delete persisted session |
```

---

## 12. Implementation Checklist

### Pre-Implementation
- [x] Review Task 6.6.1 (delete_persisted/1 public) - Complete
- [x] Review existing resume command implementation - Complete
- [x] Review TUI integration points - Complete
- [x] Confirm testing strategy - Complete

### Implementation
- [ ] Add command parsing pattern in commands.ex
- [ ] Add execute_resume({:delete, target}, model) handler
- [ ] Update @help_text with delete command
- [ ] Update module @doc with delete command

### Testing
- [ ] Write unit tests for parsing
- [ ] Write unit tests for handler execution
- [ ] Write tests for all error cases
- [ ] Manual integration testing via TUI
- [ ] Verify idempotency (delete twice)
- [ ] Test edge cases (active session, invalid formats)

### Documentation
- [ ] Update function @doc for execute_resume/2
- [ ] Update CLAUDE.md commands table
- [ ] Add usage examples to documentation

### Verification
- [ ] Run `mix test` - all tests pass
- [ ] Run `mix credo --strict` - no issues
- [ ] Manual testing checklist complete
- [ ] Code review (self or peer)

### Phase-06 Plan Update
- [ ] Mark task 6.6.2 items as complete
- [ ] Update implementation summary
- [ ] Note any deviations from plan

---

## 13. Notes and Assumptions

### Assumptions
1. **delete_persisted/1 is public** (Task 6.6.1) - Confirmed in persistence.ex:1356
2. **list_resumable/0 exists** (Task 6.4.1) - Confirmed in persistence.ex:607
3. **resolve_resume_target/2 exists** (Task 6.5.1) - Confirmed in commands.ex:692
4. **TUI handles {:ok, message} returns** - Confirmed in tui.ex:1236-1239

### Design Decisions Log
- **2025-12-10**: Use list_resumable() instead of list_persisted() for safety
- **2025-12-10**: No confirmation prompt for simplicity
- **2025-12-10**: Return {:ok, message} instead of :no_change for consistency
- **2025-12-10**: Reuse resolve_resume_target/2 for target resolution

### Open Questions
- None - all dependencies confirmed available

### Risk Assessment
- **Low Risk**: Straightforward extension of existing pattern
- **No Breaking Changes**: Additive feature only
- **Well-Isolated**: Only touches Commands module and tests

---

## 14. References

### Related Files
- `lib/jido_code/commands.ex` - Command parsing and execution
- `lib/jido_code/session/persistence.ex` - delete_persisted/1, list_resumable/0
- `lib/jido_code/tui.ex` - TUI integration (no changes needed)
- `test/jido_code/commands_test.exs` - Unit tests to add

### Related Tasks
- **Task 6.4.1** - Load Persisted Session (list_resumable)
- **Task 6.5.1** - Resume Command (resolve_resume_target)
- **Task 6.6.1** - Cleanup Command (delete_persisted made public)
- **Task 6.6.3** - Clear All Command (future: delete all sessions)

### Code Patterns
- **Command Parsing**: String pattern matching in parse_and_execute/2
- **Handler Returns**: {:ok, message} | {:error, message} | {:session_action, action}
- **Target Resolution**: resolve_resume_target(target, sessions)
- **Error Messages**: Consistent format with existing commands

---

## Appendix A: Reference Implementation

### Complete Implementation (commands.ex)

```elixir
# In parse_and_execute/2 section (BEFORE "/resume " pattern):

defp parse_and_execute("/resume delete " <> rest, _config) do
  {:resume, {:delete, String.trim(rest)}}
end

defp parse_and_execute("/resume delete", _config) do
  {:error, "Usage: /resume delete <index|id>\n\nUse /resume to list available sessions."}
end

# In execute_resume/2 section:

def execute_resume({:delete, target}, _model) do
  alias JidoCode.Session.Persistence

  case Persistence.list_resumable() do
    {:ok, sessions} ->
      case resolve_resume_target(target, sessions) do
        {:ok, session_id} ->
          case Persistence.delete_persisted(session_id) do
            :ok ->
              {:ok, "Deleted saved session."}

            {:error, reason} ->
              {:error, "Failed to delete session: #{inspect(reason)}"}
          end

        {:error, error_message} ->
          {:error, error_message}
      end

    {:error, reason} ->
      {:error, "Failed to list resumable sessions: #{inspect(reason)}"}
  end
end
```

### Test Template (commands_test.exs)

```elixir
describe "/resume delete command" do
  setup do
    # Create temporary test directory
    tmp_dir = Path.join(System.tmp_dir!(), "commands_delete_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)

    # Create test session file
    session_id = "550e8400-e29b-41d4-a716-446655440000"
    persisted = Persistence.new_session(%{
      id: session_id,
      name: "Test Delete Session",
      project_path: tmp_dir,
      conversation: [],
      todos: []
    })
    :ok = Persistence.write_session_file(session_id, persisted)

    on_exit(fn ->
      Persistence.delete_persisted(session_id)
      File.rm_rf!(tmp_dir)
    end)

    %{session_id: session_id, tmp_dir: tmp_dir}
  end

  test "parses /resume delete with numeric index" do
    result = Commands.execute("/resume delete 1", %{})
    assert match?({:resume, {:delete, "1"}}, result)
  end

  test "parses /resume delete with UUID", %{session_id: session_id} do
    result = Commands.execute("/resume delete #{session_id}", %{})
    assert match?({:resume, {:delete, ^session_id}}, result)
  end

  test "returns error for /resume delete without target" do
    assert {:error, message} = Commands.execute("/resume delete", %{})
    assert message =~ "Usage: /resume delete"
    assert message =~ "Use /resume to list"
  end

  test "deletes session successfully by index" do
    assert {:ok, message} = Commands.execute_resume({:delete, "1"}, %{})
    assert message == "Deleted saved session."

    # Verify file is gone
    {:ok, sessions} = Persistence.list_resumable()
    assert sessions == []
  end

  test "deletes session successfully by UUID", %{session_id: session_id} do
    assert {:ok, message} = Commands.execute_resume({:delete, session_id}, %{})
    assert message == "Deleted saved session."
  end

  test "returns error for invalid index" do
    assert {:error, message} = Commands.execute_resume({:delete, "99"}, %{})
    assert message =~ "Invalid index"
  end

  test "returns error for unknown UUID" do
    unknown = "99999999-9999-4999-8999-999999999999"
    assert {:error, message} = Commands.execute_resume({:delete, unknown}, %{})
    assert message =~ "Session not found"
  end

  test "is idempotent - deleting twice succeeds" do
    assert {:ok, _} = Commands.execute_resume({:delete, "1"}, %{})
    assert {:ok, _} = Commands.execute_resume({:delete, "1"}, %{})
  end
end
```

---

**End of Feature Plan**

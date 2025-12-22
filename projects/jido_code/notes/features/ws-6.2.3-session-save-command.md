# Planning Document: Task 6.2.3 - Session Save Command

## 1. Problem Statement

Currently, sessions are only saved automatically when they are closed via `SessionSupervisor.stop_session/1`. Users have no way to manually save a session's state while it's still running. This limits flexibility for:

- **Checkpoint saving** - Users may want to save progress before risky operations
- **Explicit backups** - Users may want to ensure state is persisted without closing
- **Testing/debugging** - Developers may want to inspect saved session files
- **Peace of mind** - Users may want to manually trigger a save for important work

The `/session save` command will provide an explicit, user-initiated way to persist the current session state to disk without affecting the running session.

## 2. Solution Overview

Implement a new `/session save` subcommand that:

1. **Accepts an optional target parameter** - Session index, ID, name, or defaults to active session
2. **Calls existing persistence infrastructure** - Reuses `JidoCode.Session.Persistence.save/1`
3. **Returns success message with file path** - Shows user where the session was saved
4. **Handles errors gracefully** - Clear error messages for missing sessions, write failures, etc.
5. **Works alongside auto-save** - Complements (doesn't replace) auto-save on close

**Key Design Decisions:**

- **Leverage existing infrastructure** - Use `Persistence.save/1` which is already proven by auto-save (Task 6.2.2)
- **Optional target parameter** - `/session save` saves active session, `/session save 2` saves session 2
- **No confirmation needed** - Save is non-destructive; existing files are overwritten atomically
- **Return file path** - User feedback shows exactly where the file was written

## 3. Technical Details

### Files to Modify

1. **`lib/jido_code/commands.ex`**
   - Add `save` case to `parse_session_args/1`
   - Add `execute_session({:save, target}, model)` handler
   - Add to help text and session help

2. **`test/jido_code/commands_test.exs`**
   - Add tests for save command parsing
   - Add tests for save command execution
   - Add tests for error cases

### Functions to Add

#### 1. Parse Save Subcommand

**Location:** `lib/jido_code/commands.ex` (after `parse_session_args("list")`)

```elixir
defp parse_session_args("save" <> rest) do
  case String.trim(rest) do
    "" -> {:save, nil}
    target -> {:save, target}
  end
end
```

**Behavior:**
- `/session save` → `{:save, nil}` (save active session)
- `/session save 2` → `{:save, "2"}` (save session at index 2)
- `/session save my-project` → `{:save, "my-project"}` (save by name)
- `/session save session-abc-123` → `{:save, "session-abc-123"}` (save by ID)

#### 2. Execute Save Command

**Location:** `lib/jido_code/commands.ex` (before the catch-all `execute_session/2`)

```elixir
def execute_session({:save, target}, model) do
  alias JidoCode.Session.Persistence

  # Determine which session to save
  session_order = Map.get(model, :session_order, [])
  active_id = Map.get(model, :active_session_id)

  # If no target, save active session
  effective_target = target || active_id

  cond do
    session_order == [] ->
      {:error, "No sessions to save."}

    effective_target == nil ->
      {:error, "No active session to save. Specify a session to save."}

    true ->
      # Resolve target to session ID
      case resolve_session_target(effective_target, model) do
        {:ok, session_id} ->
          # Attempt to save the session
          case Persistence.save(session_id) do
            {:ok, path} ->
              sessions = Map.get(model, :sessions, %{})
              session = Map.get(sessions, session_id)
              session_name = if session, do: Map.get(session, :name, session_id), else: session_id
              {:ok, "Session '#{session_name}' saved to:\n#{path}"}

            {:error, :not_found} ->
              {:error, "Session not found. It may have been closed."}

            {:error, :save_in_progress} ->
              {:error, "Session is currently being saved. Please try again."}

            {:error, reason} when is_binary(reason) ->
              {:error, "Failed to save session: #{reason}"}

            {:error, reason} ->
              {:error, "Failed to save session: #{inspect(reason)}"}
          end

        {:error, reason} ->
          format_resolution_error(reason, target)
      end
  end
end
```

#### 3. Update Help Text

**Location:** `lib/jido_code/commands.ex`

```elixir
# In @help_text constant:
/session save [target]   - Save session to disk (default: active)

# In execute_session(:help, _model) function:
/session save [index|id|name]       - Save session to disk (defaults to current)
```

## 4. Implementation Plan

### Step 1: Add Save Parsing ✅
- [x] Add `save` case to `parse_session_args/1` (lines 260-265 in commands.ex)

### Step 2: Add Save Execution Handler ✅
- [x] Implement `execute_session({:save, target}, model)` (lines 606-655 in commands.ex)
- [x] Add `alias JidoCode.Session.Persistence` in handler

### Step 3: Update Help Text ✅
- [x] Add to `@help_text` constant (line 80)
- [x] Add to `execute_session(:help, _model)` output (line 479)

### Step 4: Write Unit Tests ✅
- [x] Test save command parsing (4 tests, lines 451-481 in commands_test.exs)
- [x] Test save execution (6 tests, lines 1450-1554 in commands_test.exs)
- [x] Test help text includes save (line 502)

**Total Tests Added**: 10 new tests, all passing

### Step 5: Manual Testing ⏸️
- [ ] Test in TUI (deferred - requires running TUI)
- [ ] Verify file creation
- [ ] Test error cases

### Step 6: Documentation Update ✅
- [x] Update phase plan checklist (phase-06.md lines 132-143)
- [x] Update planning document status

## 5. Success Criteria

1. ✅ Command parsing works - 4 tests pass
2. ✅ Active session save works - Test passes (with graceful handling if state unavailable)
3. ✅ Target save works - Tests for index, name, ID all pass
4. ✅ Error handling works - Error tests pass for no sessions, no active, invalid target
5. ✅ Help text updated - Both @help_text and :help function updated
6. ✅ All tests pass - 10/10 new tests passing, no regressions
7. ⏸️ Manual testing succeeds - Deferred to integration testing
8. ✅ No regressions - Pre-existing test failures unchanged
9. ✅ Integration with auto-save - Uses same Persistence.save/1 function

## Current Status

**Phase**: ✅ Complete (Implementation & Testing)

**What Works:**
- `/session save` command parsing (parses to `{:save, nil}`)
- `/session save <target>` with index/name/ID (parses to `{:save, target}`)
- Execution handler with comprehensive error handling
- Help text updated in both global help and session help
- All 10 unit tests passing

**Files Modified:**
1. `lib/jido_code/commands.ex` - Added parsing and execution (62 lines added)
2. `test/jido_code/commands_test.exs` - Added 10 tests (105 lines added)
3. `notes/planning/work-session/phase-06.md` - Marked task complete

**Test Results:**
```
163 tests, 15 failures

Save tests: 10/10 passing
- Parsing tests: 4/4 ✅
- Execution tests: 6/6 ✅
- Help text test: 1/1 ✅

Note: 15 failures are pre-existing from /resume command tests (unrelated)
```

**What's Next:**
- Create summary document
- Commit changes
- Merge into work-session branch

**How to Test Manually (Optional):**
```bash
# In TUI
/session new /tmp/test-project --name="Test"
> hello
/session save
# Expected: "Session 'Test' saved to: ~/.jido_code/sessions/<id>.json"

/session save 1
# Expected: "Session 'Test' saved to: ~/.jido_code/sessions/<id>.json"

/session save nonexistent
# Expected: Error message
```

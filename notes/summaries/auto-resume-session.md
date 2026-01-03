# Auto-Resume Session Implementation Summary

## Overview

Implemented automatic resume prompting when starting JidoCode from a directory that has a previously saved session. On startup, a confirmation dialog appears asking whether to resume the previous session or start fresh.

## Changes Made

### 1. Persistence Lookup (`lib/jido_code/session/persistence.ex`)

Added `find_by_project_path/1` function to find the most recent resumable session for a given project path:

```elixir
@spec find_by_project_path(String.t()) :: {:ok, map() | nil} | {:error, term()}
def find_by_project_path(project_path) do
  with {:ok, sessions} <- list_resumable() do
    session = Enum.find(sessions, fn s -> s.project_path == project_path end)
    {:ok, session}
  end
end
```

### 2. Model State (`lib/jido_code/tui.ex`)

Added `resume_dialog` field to the Model struct to hold dialog state:

```elixir
# In typespec
resume_dialog: map() | nil,

# In defstruct
resume_dialog: nil,
```

### 3. Startup Check (`lib/jido_code/tui.ex`)

Added `check_for_resumable_session/0` function called during `init/1` to detect if a resumable session exists for the current working directory.

### 4. Dialog Rendering (`lib/jido_code/tui.ex`)

Added `overlay_resume_dialog/2` function to render a centered confirmation dialog with:
- Title: "Resume Previous Session?"
- Session name and closed time
- Two options: [Enter] Resume, [Esc] New Session

Added `format_time_ago/1` helper for human-readable timestamps.

### 5. Event Routing (`lib/jido_code/tui.ex`)

Updated event routing to handle resume dialog state:

- Enter key → `:resume_dialog_accept` (when dialog open)
- Escape key → `:resume_dialog_dismiss` (when dialog open)
- Mouse events → ignored (when dialog open)

### 6. Update Handlers (`lib/jido_code/tui.ex`)

Added handlers for dialog actions:

- `update(:resume_dialog_accept, state)` - Calls `Persistence.resume/1`, adds session to model, shows success message
- `update(:resume_dialog_dismiss, state)` - Dismisses dialog, continues with fresh session

### 7. Tests

Added tests in two files:

**`test/jido_code/session/persistence_test.exs`:**
- `find_by_project_path/1` returns `{:ok, nil}` when no sessions exist
- `find_by_project_path/1` returns `{:ok, nil}` when path doesn't match
- `find_by_project_path/1` returns `{:ok, session}` when path matches
- `find_by_project_path/1` returns most recent session when multiple match

**`test/jido_code/tui_test.exs`:**
- Enter key returns `:resume_dialog_accept` when dialog is open
- Escape key returns `:resume_dialog_dismiss` when dialog is open
- Mouse events are ignored when dialog is open
- Dismiss clears `resume_dialog` state
- `resume_dialog` field has default value of nil

## Files Modified

| File | Changes |
|------|---------|
| `lib/jido_code/session/persistence.ex` | Added `find_by_project_path/1` |
| `lib/jido_code/tui.ex` | Added `resume_dialog` field, startup check, dialog rendering, event handlers |
| `test/jido_code/session/persistence_test.exs` | Added 4 tests for `find_by_project_path/1` |
| `test/jido_code/tui_test.exs` | Added 6 tests for resume dialog handling |

## User Experience

1. User starts JidoCode from a project directory
2. If a saved session exists for that directory, a dialog appears:
   ```
   ┌──────────────────────────────────────────┐
   │ Resume Previous Session?                 │
   │                                          │
   │   Session: My Project                    │
   │   Closed: 2 hours ago                    │
   │                                          │
   │   [Enter] Resume    [Esc] New Session    │
   └──────────────────────────────────────────┘
   ```
3. Press Enter to restore the previous session with its conversation history
4. Press Esc to start a fresh session

## Error Handling

If resume fails (e.g., session file deleted, project moved), an error message is shown and the dialog is dismissed, allowing the user to continue with a fresh session.

## Test Results

All relevant tests pass (411 tests, 0 failures in TUI and Persistence test files).

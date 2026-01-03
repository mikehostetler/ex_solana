# Prompt History Feature Summary

## Overview

Implemented per-session prompt history with shell-like navigation, allowing users to recall and reuse previous prompts using arrow keys.

## Key Features

### User Experience

| Key | Action |
|-----|--------|
| **Up Arrow** | Navigate to previous (older) prompt in history |
| **Down Arrow** | Navigate to next (newer) prompt, or restore original input |
| **ESC** | Clear input and exit history navigation mode |
| **Enter** | Submit prompt and add it to history |

### Behavior

1. **History Navigation**:
   - First Up Arrow press saves current input and shows most recent prompt
   - Subsequent Up presses show older prompts
   - Down Arrow shows newer prompts
   - Down at most recent restores the saved original input

2. **History Persistence**:
   - History is saved with the session (via `/session close`, Ctrl+W, or Ctrl+X app exit)
   - **Auto-save on exit**: All active sessions are automatically saved when exiting with Ctrl+X
   - History is restored when resuming a session (via `/resume`)
   - Maximum 100 prompts per session

3. **Both prompts and commands are stored**:
   - Regular chat prompts
   - Slash commands (e.g., `/help`, `/model`)

## Technical Implementation

### Files Modified

| File | Changes |
|------|---------|
| `lib/jido_code/session/state.ex` | Added `prompt_history` field, `get_prompt_history/1`, `add_to_prompt_history/2`, `set_prompt_history/2` |
| `lib/jido_code/tui.ex` | Added `history_index` and `saved_input` to UI state, Up/Down/ESC handlers, history navigation update functions, auto-save all sessions on Ctrl+X exit |
| `lib/jido_code/session/persistence/serialization.ex` | Added `prompt_history` to build/deserialize session |
| `lib/jido_code/session/persistence.ex` | Added `restore_prompt_history/2` for session resume |
| `test/jido_code/session/state_test.exs` | Added 12 tests for prompt history functionality |

### Data Flow

```
User presses Up Arrow
    │
    ▼
event_to_msg(:up, state) → {:msg, :history_previous}
    │
    ▼
update(:history_previous, state)
    │
    ├─ First time: Save current input, set index=0, show history[0]
    │
    └─ Subsequent: Increment index, show history[index]
    │
    ▼
UI state updated with new text_input, history_index, saved_input
```

### State Structure

```elixir
# Session.State (persisted)
%{
  prompt_history: ["newest", "older", "oldest", ...]
}

# TUI UI State (per-session, transient)
%{
  history_index: nil | 0 | 1 | 2 | ...,
  saved_input: nil | "original text"
}
```

### Limits

- **Max history size**: 100 prompts per session
- **Empty prompts**: Ignored (not added to history)
- **Whitespace-only prompts**: Ignored

## Testing

Added 12 tests covering:
- Initial empty history
- Adding prompts to history
- Prepend order (newest first)
- Empty prompt filtering
- Max history limit enforcement
- Setting entire history (for restore)
- Error handling for unknown sessions

Run tests:
```bash
mix test test/jido_code/session/state_test.exs --trace
```

## Future Enhancements

Potential improvements:
- **Ctrl+R**: Reverse search through history (like bash)
- **History indicator**: Show position in status bar (e.g., "3/15")
- **Deduplication**: Option to avoid consecutive duplicates
- **Per-project history**: Share history across sessions for same project

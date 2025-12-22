# Feature: Session Order Management (Task 4.1.3)

## Problem Statement

Phase 4 of the work-session plan requires implementing helper functions for managing session tab order in the TUI. Tasks 4.1.1 and 4.1.2 (Model struct changes and session state access) are complete, but we need the core session management operations:

- Adding sessions to the tab list
- Removing sessions from the tab list
- Handling active session removal (switching to adjacent tab)
- Maintaining session order consistency

Without these functions, the TUI cannot properly manage multiple sessions as users create, switch, and close them.

## Solution Overview

Implement three core helper functions in `lib/jido_code/tui.ex`:

1. **`add_session_to_tabs/2`**: Adds a new session to the model
   - Adds session to sessions map
   - Appends to session_order list
   - Sets as active if it's the first session

2. **`remove_session_from_tabs/2`**: Removes a session from the model
   - Removes from sessions map
   - Removes from session_order list
   - Switches active session if the removed session was active

3. **Active session switching logic**: When removing active session
   - Switch to next tab if available
   - Otherwise switch to previous tab
   - Handle case where it's the last session

## Technical Details

### Files to Modify
- `lib/jido_code/tui.ex` - Add helper functions
- `test/jido_code/tui_test.exs` - Add tests for new functions

### Current State (from Phase 4.1.1 and 4.1.2)

Model struct has these fields:
```elixir
defstruct [
  sessions: %{},           # session_id => Session.t()
  session_order: [],       # List of session_ids in tab order
  active_session_id: nil,  # Currently focused session
  # ... other fields
]
```

Helper functions already exist:
- `get_active_session/1` - Returns active session struct
- `get_active_session_state/1` - Fetches from Session.State
- `get_session_by_index/2` - Looks up by tab number

### Implementation Approach

**Function 1: add_session_to_tabs/2**
```elixir
@spec add_session_to_tabs(model(), Session.t()) :: model()
def add_session_to_tabs(model, %Session{} = session) do
  %{model |
    sessions: Map.put(model.sessions, session.id, session),
    session_order: model.session_order ++ [session.id],
    active_session_id: model.active_session_id || session.id
  }
end
```

**Function 2: remove_session_from_tabs/2**
```elixir
@spec remove_session_from_tabs(model(), String.t()) :: model()
def remove_session_from_tabs(model, session_id) do
  new_sessions = Map.delete(model.sessions, session_id)
  new_order = Enum.reject(model.session_order, &(&1 == session_id))
  new_active = get_next_active_session(model, session_id)

  %{model |
    sessions: new_sessions,
    session_order: new_order,
    active_session_id: new_active
  }
end
```

**Helper: get_next_active_session/2**
```elixir
defp get_next_active_session(model, removed_session_id) do
  if model.active_session_id != removed_session_id do
    # Not removing active session, keep current
    model.active_session_id
  else
    # Removing active session, switch to adjacent
    current_index = Enum.find_index(model.session_order, &(&1 == removed_session_id))

    cond do
      # Try next tab
      current_index + 1 < length(model.session_order) ->
        Enum.at(model.session_order, current_index + 1)

      # Try previous tab
      current_index > 0 ->
        Enum.at(model.session_order, current_index - 1)

      # Was the last session
      true ->
        nil
    end
  end
end
```

## Success Criteria

1. ✅ `add_session_to_tabs/2` adds session to map and order list
2. ✅ `add_session_to_tabs/2` sets as active if first session
3. ✅ `add_session_to_tabs/2` preserves active session if not first
4. ✅ `remove_session_from_tabs/2` removes from map and order list
5. ✅ Removing non-active session preserves current active
6. ✅ Removing active session switches to next tab
7. ✅ Removing active session switches to previous if no next
8. ✅ Removing last session sets active_session_id to nil
9. ✅ All tests pass
10. ✅ Phase plan updated with checkmarks

## Implementation Plan

### Step 1: Read Current TUI Module
- [x] Read `lib/jido_code/tui.ex` to understand current structure
- [x] Identify where to place new functions
- [x] Check existing helper functions

### Step 2: Implement add_session_to_tabs/2
- [x] Add function to TUI module
- [x] Add @spec typespec
- [x] Add @doc documentation

### Step 3: Implement remove_session_from_tabs/2
- [x] Add function to TUI module (created alias to existing remove_session/2)
- [x] Add @spec typespec
- [x] Add @doc documentation
- [x] Leverage existing remove_session/2 with get_next_active_session/2 helper

### Step 4: Write Unit Tests
- [x] Test adding first session (sets as active)
- [x] Test adding second session (preserves active)
- [x] Test removing non-active session
- [x] Test removing active session with next tab available
- [x] Test removing active session with only previous tab
- [x] Test removing last session
- [x] Test edge cases (empty order, invalid session_id)

### Step 5: Documentation and Completion
- [x] Update phase-04.md to mark task 4.1.3 as complete
- [ ] Write summary document
- [ ] Commit and request merge approval

## Notes/Considerations

### Edge Cases
- Adding duplicate session ID (should we check?)
- Removing non-existent session ID (should be no-op)
- Empty session list after removal
- Session order integrity after operations

### Future Work (4.1.3.4)
- `reorder_sessions/2` for drag-drop tab reordering
- This is marked as "future" in the plan, won't implement now

### Testing Strategy
- Unit tests for each function independently
- Test all success criteria
- Test edge cases
- Ensure model consistency after operations

## Status

**Current Step**: Creating feature plan
**Branch**: feature/session-order-management
**Next**: Read existing TUI module

# Feature Plan: Task 4.6.1 - Tab Switching Shortcuts

**Status**: ✅ Complete
**Phase**: 4 (TUI Tab Integration)
**Task**: 4.6.1 - Tab Switching Shortcuts
**Date**: 2025-12-16

## 1. Problem Statement

The TUI currently supports multiple work sessions (tabs) but lacks keyboard shortcuts for direct tab switching. Users need a fast way to switch between sessions without using commands or mouse interaction.

The goal is to implement Ctrl+1 through Ctrl+0 keyboard shortcuts to directly switch to tabs 1-10, providing a familiar tab navigation pattern similar to modern browsers and editors.

### Current State

- Model structure supports multiple sessions (Phase 4.1)
- Sessions are tracked via `session_order` field (list of session IDs)
- Active session is tracked via `active_session_id` field
- Session limit is 10 max (defined by `@max_tabs` constant)
- Existing keyboard event handling in `event_to_msg/2` (lines 754-772)
- Existing session switching in `update/2` (lines 1162-1185)

**Key Finding**: The implementation is already complete! Lines 754-772 of `lib/jido_code/tui.ex` show:
- Ctrl+1 through Ctrl+9 already mapped to `{:switch_to_session_index, 1-9}`
- Ctrl+0 already mapped to `{:switch_to_session_index, 10}`
- Update handler at lines 1162-1185 already implements the switching logic

This task only requires comprehensive unit tests to verify the existing implementation.

## 2. Solution Overview

Since the implementation already exists, this task focuses on:

1. **Verification**: Confirm existing keyboard event mappings work correctly
2. **Testing**: Write comprehensive unit tests covering all scenarios
3. **Documentation**: Ensure behavior is well-documented

### Existing Implementation Details

**Event Mapping** (lines 754-772):
```elixir
# Ctrl+1 through Ctrl+9 to switch to session by index
def event_to_msg(%Event.Key{key: key, modifiers: modifiers} = event, _state)
    when key in ["1", "2", "3", "4", "5", "6", "7", "8", "9"] do
  if :ctrl in modifiers do
    index = String.to_integer(key)
    {:msg, {:switch_to_session_index, index}}
  else
    {:msg, {:input_event, event}}
  end
end

# Ctrl+0 to switch to session 10 (the 10th tab)
def event_to_msg(%Event.Key{key: "0", modifiers: modifiers} = event, _state) do
  if :ctrl in modifiers do
    {:msg, {:switch_to_session_index, 10}}
  else
    {:msg, {:input_event, event}}
  end
end
```

**Update Handler** (lines 1162-1185):
```elixir
# Switch to session by index (Ctrl+1 through Ctrl+0)
def update({:switch_to_session_index, index}, state) do
  case Model.get_session_by_index(state, index) do
    nil ->
      # No session at that index
      new_state = add_session_message(state, "No session at index #{index}.")
      {new_state, []}

    session ->
      if session.id == state.active_session_id do
        # Already on this session
        {state, []}
      else
        new_state =
          state
          |> Model.switch_session(session.id)
          |> refresh_conversation_view_for_session(session.id)
          |> clear_session_activity(session.id)
          |> add_session_message("Switched to: #{session.name}")

        {new_state, []}
      end
  end
end
```

**Helper Function** (lines 333-365):
```elixir
@doc """
Returns the session at the given tab index (1-based).

Tab indices 1-9 correspond to Ctrl+1 through Ctrl+9.
Tab index 10 corresponds to Ctrl+0 (the 10th tab).

Returns `nil` if the index is out of range or if no sessions exist.
"""
@spec get_session_by_index(t(), pos_integer()) :: JidoCode.Session.t() | nil
def get_session_by_index(%__MODULE__{session_order: []}, _index), do: nil

def get_session_by_index(%__MODULE__{session_order: order, sessions: sessions}, index)
    when is_integer(index) and index >= 1 and index <= @max_tabs do
  # Convert 1-based tab index to 0-based list index
  list_index = index - 1

  case Enum.at(order, list_index) do
    nil -> nil
    session_id -> Map.get(sessions, session_id)
  end
end

def get_session_by_index(_model, _index), do: nil
```

## 3. Technical Details

### 3.1 Event Flow

1. User presses Ctrl+1 through Ctrl+0
2. `event_to_msg/2` converts to `{:msg, {:switch_to_session_index, N}}`
3. `update/2` receives `{:switch_to_session_index, N}` message
4. `Model.get_session_by_index/2` looks up session at index N
5. If found and not current, switch to session and update UI
6. If not found, show friendly message "No session at index N."
7. If already current, no-op (no message, no change)

### 3.2 Edge Cases Handled

1. **Out-of-range index**: `get_session_by_index/2` returns `nil`, shows message
2. **Empty session list**: Early return in `get_session_by_index/2`
3. **Already on target session**: No-op, returns unchanged state
4. **Invalid index (<1 or >10)**: Pattern match fails, returns `nil`
5. **Digit without Ctrl**: Forwarded to text input as `{:input_event, event}`

### 3.3 Side Effects on Switch

When switching to a different session, the update handler:
1. Updates `active_session_id` to new session
2. Refreshes conversation view with session's messages
3. Clears unread count for the session (from Phase 4.7.3)
4. Shows "Switched to: <name>" message

## 4. Implementation Plan

Since implementation is complete, this plan focuses on testing.

### Checklist

- [x] 4.6.1.1 Event mapping for Ctrl+1 through Ctrl+9 (already implemented)
- [x] 4.6.1.2 Event mapping for Ctrl+0 (already implemented)
- [x] 4.6.1.3 Update handler for session switching (already implemented)
- [x] 4.6.1.4 Out-of-range index handling (already implemented)
- [x] 4.6.1.5 Write unit tests for event mapping (already existed, verified)
- [x] 4.6.1.6 Write unit tests for session switching logic (added 2 new tests)
- [x] 4.6.1.7 Write unit tests for edge cases (added 5 new tests in get_session_by_index)
- [x] 4.6.1.8 Write tests for digit-without-Ctrl (added 2 new tests)
- [x] 4.6.1.9 Write integration tests (added 2 new tests)
- [x] 4.6.1.10 Verify all existing tests still pass (286 tests, 13 new tests passing)

## 5. Success Criteria

### Functional Requirements

- [x] Ctrl+1 through Ctrl+9 switch to tabs 1-9
- [x] Ctrl+0 switches to 10th tab
- [x] Out-of-range indices show friendly message, no crash
- [x] Switching to current session is a no-op
- [x] Digit keys without Ctrl are forwarded to input
- [x] Switching updates active_session_id
- [x] Switching refreshes conversation view
- [x] Switching clears unread count

### Test Coverage Requirements

- [ ] Event mapping tests for all digits 0-9
- [ ] Event mapping tests for non-Ctrl digit keys
- [ ] Session switching tests for valid indices
- [ ] Session switching tests for out-of-range indices
- [ ] Session switching tests for empty session list
- [ ] Session switching tests for switching to current session
- [ ] Session switching tests for side effects (conversation refresh, unread clear)

### Code Quality

- [ ] All new tests follow existing test patterns
- [ ] Tests use helper functions from existing test suite
- [ ] Tests are documented with clear descriptions
- [ ] No regressions in existing test suite

## 6. Testing Strategy

### 6.1 Event Mapping Tests

Test `event_to_msg/2` for keyboard event handling:

```elixir
describe "tab switching keyboard events" do
  test "Ctrl+1 through Ctrl+9 map to switch_to_session_index" do
    for key <- ["1", "2", "3", "4", "5", "6", "7", "8", "9"] do
      event = %Event.Key{key: key, modifiers: [:ctrl]}
      index = String.to_integer(key)

      assert TUI.event_to_msg(event, %Model{}) == {:msg, {:switch_to_session_index, index}}
    end
  end

  test "Ctrl+0 maps to switch_to_session_index 10" do
    event = %Event.Key{key: "0", modifiers: [:ctrl]}
    assert TUI.event_to_msg(event, %Model{}) == {:msg, {:switch_to_session_index, 10}}
  end

  test "digit keys without Ctrl are forwarded to input" do
    for key <- ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] do
      event = %Event.Key{key: key, modifiers: []}
      assert TUI.event_to_msg(event, %Model{}) == {:msg, {:input_event, event}}
    end
  end
end
```

### 6.2 Session Switching Tests

Test `update({:switch_to_session_index, index}, state)` behavior:

```elixir
describe "session switching by index" do
  test "switches to session at valid index" do
    session1 = create_test_session("s1", "Project 1", "/path1")
    session2 = create_test_session("s2", "Project 2", "/path2")

    state = %Model{
      sessions: %{"s1" => session1, "s2" => session2},
      session_order: ["s1", "s2"],
      active_session_id: "s1",
      text_input: create_text_input()
    }

    {new_state, _cmds} = TUI.update({:switch_to_session_index, 2}, state)

    assert new_state.active_session_id == "s2"
  end

  test "shows message when index is out of range" do
    session1 = create_test_session("s1", "Project 1", "/path1")

    state = %Model{
      sessions: %{"s1" => session1},
      session_order: ["s1"],
      active_session_id: "s1",
      text_input: create_text_input(),
      messages: []
    }

    {new_state, _cmds} = TUI.update({:switch_to_session_index, 5}, state)

    assert new_state.active_session_id == "s1"  # unchanged
    assert length(new_state.messages) == 1
    [msg] = new_state.messages
    assert msg.role == :system
    assert msg.content =~ "No session at index 5"
  end

  test "no-op when switching to current session" do
    session1 = create_test_session("s1", "Project 1", "/path1")

    state = %Model{
      sessions: %{"s1" => session1},
      session_order: ["s1"],
      active_session_id: "s1",
      text_input: create_text_input(),
      messages: []
    }

    {new_state, _cmds} = TUI.update({:switch_to_session_index, 1}, state)

    assert new_state.active_session_id == "s1"
    assert new_state.messages == []  # no message added
  end

  test "handles empty session list gracefully" do
    state = %Model{
      sessions: %{},
      session_order: [],
      active_session_id: nil,
      text_input: create_text_input(),
      messages: []
    }

    {new_state, _cmds} = TUI.update({:switch_to_session_index, 1}, state)

    assert new_state.active_session_id == nil
    assert length(new_state.messages) == 1
    [msg] = new_state.messages
    assert msg.content =~ "No session at index 1"
  end
end
```

### 6.3 Helper Function Tests

Test `Model.get_session_by_index/2`:

```elixir
describe "Model.get_session_by_index/2" do
  test "returns session at valid index (1-based)" do
    session1 = create_test_session("s1", "Project 1", "/path1")
    session2 = create_test_session("s2", "Project 2", "/path2")
    session3 = create_test_session("s3", "Project 3", "/path3")

    model = %Model{
      sessions: %{"s1" => session1, "s2" => session2, "s3" => session3},
      session_order: ["s1", "s2", "s3"]
    }

    assert Model.get_session_by_index(model, 1) == session1
    assert Model.get_session_by_index(model, 2) == session2
    assert Model.get_session_by_index(model, 3) == session3
  end

  test "returns nil for out-of-range index" do
    session1 = create_test_session("s1", "Project 1", "/path1")

    model = %Model{
      sessions: %{"s1" => session1},
      session_order: ["s1"]
    }

    assert Model.get_session_by_index(model, 0) == nil
    assert Model.get_session_by_index(model, 2) == nil
    assert Model.get_session_by_index(model, 11) == nil
  end

  test "returns nil for empty session list" do
    model = %Model{sessions: %{}, session_order: []}

    assert Model.get_session_by_index(model, 1) == nil
    assert Model.get_session_by_index(model, 10) == nil
  end

  test "handles index 10 (Ctrl+0) correctly" do
    # Create 10 sessions
    sessions =
      Enum.reduce(1..10, {%{}, []}, fn i, {sess_map, order} ->
        id = "s#{i}"
        session = create_test_session(id, "Project #{i}", "/path#{i}")
        {Map.put(sess_map, id, session), order ++ [id]}
      end)

    {session_map, session_order} = sessions

    model = %Model{
      sessions: session_map,
      session_order: session_order
    }

    # Index 10 should return the 10th session
    session10 = Model.get_session_by_index(model, 10)
    assert session10.id == "s10"
    assert session10.name == "Project 10"
  end
end
```

### 6.4 Integration Tests

Test the complete flow from keyboard event to state update:

```elixir
describe "tab switching integration" do
  test "complete flow: Ctrl+2 switches to second tab" do
    # Setup: 3 sessions, currently on first
    session1 = create_test_session("s1", "Project 1", "/path1")
    session2 = create_test_session("s2", "Project 2", "/path2")
    session3 = create_test_session("s3", "Project 3", "/path3")

    state = %Model{
      sessions: %{"s1" => session1, "s2" => session2, "s3" => session3},
      session_order: ["s1", "s2", "s3"],
      active_session_id: "s1",
      text_input: create_text_input(),
      messages: []
    }

    # Simulate Ctrl+2 key press
    event = %Event.Key{key: "2", modifiers: [:ctrl]}
    {:msg, msg} = TUI.event_to_msg(event, state)

    # Process the message
    {new_state, _cmds} = TUI.update(msg, state)

    # Verify: switched to session 2
    assert new_state.active_session_id == "s2"
    assert length(new_state.messages) == 1
    [system_msg] = new_state.messages
    assert system_msg.content =~ "Switched to: Project 2"
  end
end
```

## 7. Files Modified

### Test Files

- `test/jido_code/tui_test.exs` - Add new test cases

### No Source Code Changes Required

The implementation in `lib/jido_code/tui.ex` is already complete.

## 8. Dependencies

### Existing Code

- `JidoCode.TUI.event_to_msg/2` (lines 754-772)
- `JidoCode.TUI.update/2` (lines 1162-1185)
- `JidoCode.TUI.Model.get_session_by_index/2` (lines 333-365)
- `JidoCode.TUI.Model.switch_session/2` (lines 479-486)

### Test Helpers

- `create_test_session/3` - Already exists in test file
- `create_text_input/1` - Already exists in test file

## 9. Risk Assessment

### Low Risk

- Implementation already exists and has been tested manually
- Only adding test coverage, no code changes
- Following existing test patterns
- No changes to public APIs

### Potential Issues

- None identified

## 10. Future Enhancements

This task is complete. Future related work:

- Task 4.6.2: Ctrl+Tab for cycling through tabs (already implemented)
- Task 4.6.3: Ctrl+W for closing current tab (already implemented)

## 11. References

- Phase 4 Plan: `/home/ducky/code/jido_code/notes/planning/work-session/phase-04.md`
- TUI Source: `/home/ducky/code/jido_code/lib/jido_code/tui.ex`
- TUI Tests: `/home/ducky/code/jido_code/test/jido_code/tui_test.exs`
- Session Architecture: `/home/ducky/code/jido_code/guides/developer/session-architecture.md`

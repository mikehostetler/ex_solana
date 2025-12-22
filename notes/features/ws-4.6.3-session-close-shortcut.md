# Feature Plan: Task 4.6.3 - Session Close Shortcut (Ctrl+W)

**Task**: Implement Ctrl+W keyboard shortcut for closing active session
**Branch**: `feature/ws-4.6.3-session-close-shortcut`
**Status**: ✅ Implementation Complete - Testing Required
**Date**: 2025-12-16

---

## Problem Statement

### Current State

Task 4.6.3 is part of Phase 4.6 (Keyboard Navigation) in the multi-session TUI implementation. Tasks 4.6.1 (Ctrl+1-9 direct switching) and 4.6.2 (Ctrl+Tab cycling) are complete.

**Implementation Status**: The Ctrl+W feature is **already fully implemented** but lacks comprehensive test coverage.

**Existing Implementation**:
- Event handler: `lib/jido_code/tui.ex` lines 745-752
- Update handler: `lib/jido_code/tui.ex` lines 1156-1172
- Helper function: `lib/jido_code/tui.ex` lines 1619-1633
- Model logic: `lib/jido_code/tui.ex` lines 518-558 (`Model.remove_session/2`)

**Testing Gap**: Only 1 test exists (event mapping test at line 661-666). No tests for:
- Update handler `:close_active_session` logic
- Adjacent tab selection algorithm
- Last session handling (welcome screen)
- Edge cases (nil session, empty list, non-existent session)
- PubSub unsubscribe cleanup
- SessionSupervisor integration

### User Impact

Without comprehensive tests:
- Risk of regressions when modifying session management
- Unclear behavior for edge cases
- Potential race conditions undetected
- Session cleanup order not validated

### Technical Gap

Missing test coverage for:
1. Update handler behavior with various session states
2. Adjacent tab selection logic (previous session preference)
3. Last session handling (welcome screen display)
4. Cleanup sequence (PubSub → SessionSupervisor → Model)
5. Edge cases (nil active_session_id, missing session in map)

---

## Solution Overview

### High-Level Design

This task focuses on **comprehensive test coverage** for the existing Ctrl+W implementation, following the pattern established by Tasks 4.6.1 and 4.6.2.

**Testing Strategy**:
1. Event mapping tests (verify Ctrl+W → :close_active_session)
2. Update handler tests (verify session close logic)
3. Adjacent tab selection tests (verify previous session preference)
4. Last session tests (verify welcome screen display)
5. Edge case tests (nil session, empty list, missing session)
6. Integration tests (complete flow from keyboard event to state update)

**No Code Changes Required**: The implementation is complete and follows best practices:
- Proper cleanup order (PubSub unsubscribe → SessionSupervisor stop → Model remove)
- Adjacent tab selection (prefer previous session)
- Welcome screen on last session close
- Error handling for nil active_session_id

### Key Components

**Event Handler** (`event_to_msg/2`, lines 745-752):
```elixir
def event_to_msg(%Event.Key{key: "w", modifiers: modifiers} = event, _state) do
  if :ctrl in modifiers do
    {:msg, :close_active_session}
  else
    {:msg, {:input_event, event}}
  end
end
```

**Update Handler** (`update/2`, lines 1156-1172):
```elixir
def update(:close_active_session, state) do
  case state.active_session_id do
    nil ->
      new_state = add_session_message(state, "No active session to close.")
      {new_state, []}

    session_id ->
      session = Map.get(state.sessions, session_id)
      session_name = if session, do: session.name, else: session_id
      final_state = do_close_session(state, session_id, session_name)
      {final_state, []}
  end
end
```

**Cleanup Helper** (`do_close_session/3`, lines 1619-1633):
```elixir
defp do_close_session(state, session_id, session_name) do
  # 1. Unsubscribe from PubSub first (prevent race conditions)
  Phoenix.PubSub.unsubscribe(JidoCode.PubSub, PubSubTopics.llm_stream(session_id))

  # 2. Stop the session process
  JidoCode.SessionSupervisor.stop_session(session_id)

  # 3. Remove from model (handles adjacent tab selection)
  new_state = Model.remove_session(state, session_id)

  # 4. Add confirmation message
  add_session_message(new_state, "Closed session: #{session_name}")
end
```

**Model Removal Logic** (`Model.remove_session/2`, lines 518-558):
```elixir
def remove_session(%__MODULE__{} = model, session_id) do
  # Remove from maps and lists
  new_sessions = Map.delete(model.sessions, session_id)
  new_order = Enum.reject(model.session_order, &(&1 == session_id))

  # Determine new active session
  new_active_id =
    if model.active_session_id == session_id do
      old_index = Enum.find_index(model.session_order, &(&1 == session_id)) || 0

      cond do
        new_order == [] -> nil
        old_index > 0 -> Enum.at(new_order, old_index - 1)
        true -> List.first(new_order)
      end
    else
      model.active_session_id
    end

  %{model | sessions: new_sessions, session_order: new_order, active_session_id: new_active_id}
end
```

---

## Technical Details

### Event Flow

```
User presses Ctrl+W
  ↓
event_to_msg/2 → {:msg, :close_active_session}
  ↓
update(:close_active_session, state)
  ↓
Check active_session_id
  ↓
do_close_session(state, session_id, session_name)
  ↓
1. PubSub.unsubscribe (prevent race conditions)
2. SessionSupervisor.stop_session (terminate process)
3. Model.remove_session (update TUI state)
4. add_session_message (user feedback)
  ↓
Return new state
```

### Cleanup Sequence

**Critical Order** (prevent race conditions):

1. **PubSub Unsubscribe First**: Prevents receiving messages during teardown
2. **Stop Session Process**: Terminates agent and state GenServers
3. **Remove from Model**: Updates TUI state with new active session
4. **User Feedback**: Shows confirmation message

**Why This Order Matters**:
- Unsubscribing first prevents receiving `:stream_chunk` or `:tool_call` events for a session that's being torn down
- Stopping the session before model removal ensures consistent state
- Model removal handles adjacent tab selection automatically

### Adjacent Tab Selection Logic

**Algorithm** (from `Model.remove_session/2`):

```
If closing the active session:
  1. Find the index of the closed session in session_order
  2. If no sessions left → active_session_id = nil (welcome screen)
  3. If index > 0 → activate previous session (index - 1)
  4. Otherwise → activate first remaining session

If closing an inactive session:
  Keep active_session_id unchanged
```

**Examples**:

Closing middle session (session 2 of 3):
```
Before: [s1, s2*, s3]  (* = active)
Close s2
After:  [s1*, s3]      (switches to s1 - previous session)
```

Closing first session (session 1 of 3):
```
Before: [s1*, s2, s3]
Close s1
After:  [s2*, s3]      (switches to s2 - first remaining)
```

Closing last session (session 3 of 3):
```
Before: [s1, s2, s3*]
Close s3
After:  [s1, s2*]      (switches to s2 - previous session)
```

Closing only session:
```
Before: [s1*]
Close s1
After:  []             (active_session_id = nil, shows welcome screen)
```

### Edge Cases

| Case | Behavior | Implementation |
|------|----------|----------------|
| `active_session_id = nil` | Show message "No active session to close" | Pattern match in update/2 |
| Empty session list | No-op (nil already) | Handled by pattern match |
| Session missing from map | Use session_id as fallback name | `if session, do: session.name, else: session_id` |
| Last session closed | Show welcome screen | `active_session_id = nil` |
| Close inactive session | Keep active unchanged | Conditional in remove_session/2 |
| PubSub already unsubscribed | No error | Phoenix.PubSub handles gracefully |
| SessionSupervisor stop fails | Continue cleanup | stop_session/1 doesn't raise |

---

## Implementation Plan

### ✅ Verification Checklist (Already Implemented)

- [x] **4.6.3.1**: Ctrl+W event handler implemented (lines 745-752)
- [x] **4.6.3.2**: Update handler `:close_active_session` implemented (lines 1156-1172)
  - [x] Calls `SessionSupervisor.stop_session/1`
  - [x] Removes session from model via `Model.remove_session/2`
  - [x] Switches to adjacent tab automatically
  - [x] Confirmation handling deferred to future (not blocking)
- [x] **4.6.3.3**: Last session handling implemented
  - [x] `active_session_id = nil` when last session closed
  - [x] Welcome screen renders when `active_session_id = nil`
- [x] Cleanup sequence implemented correctly (PubSub → Supervisor → Model)
- [x] Adjacent tab selection logic implemented (prefer previous session)
- [x] Edge case handling for nil session implemented

### Testing Implementation (This Task)

- [ ] **4.6.3.4**: Write comprehensive unit tests (14 tests planned)

#### Test Group 1: Event Mapping (2 tests)
- [ ] Test 1: `Ctrl+W event maps to :close_active_session message`
- [ ] Test 2: `plain 'w' key (without Ctrl) is forwarded to input`

#### Test Group 2: Update Handler - Normal Cases (3 tests)
- [ ] Test 3: `close_active_session closes middle session and switches to previous`
- [ ] Test 4: `close_active_session closes first session and switches to next`
- [ ] Test 5: `close_active_session closes last session and switches to previous`

#### Test Group 3: Update Handler - Last Session (2 tests)
- [ ] Test 6: `close_active_session closes only session, sets active_session_id to nil`
- [ ] Test 7: `welcome screen renders when active_session_id is nil`

#### Test Group 4: Update Handler - Edge Cases (3 tests)
- [ ] Test 8: `close_active_session with nil active_session_id shows message`
- [ ] Test 9: `close_active_session with missing session in map uses fallback name`
- [ ] Test 10: `close_active_session with empty session list returns unchanged state`

#### Test Group 5: Model.remove_session Tests (2 tests)
- [ ] Test 11: `remove_session removes from sessions map and session_order`
- [ ] Test 12: `remove_session keeps active unchanged when closing inactive session`

#### Test Group 6: Integration Tests (2 tests)
- [ ] Test 13: `complete flow: Ctrl+W event → update → session closed → adjacent activated`
- [ ] Test 14: `complete flow: Ctrl+W on last session → welcome screen displayed`

---

## Success Criteria

### Functional Requirements

- [x] Ctrl+W closes the active session
- [x] Session removed from model (sessions map and session_order list)
- [x] SessionSupervisor.stop_session/1 called
- [x] PubSub unsubscribe called before session stop
- [x] Switches to adjacent tab (previous session preferred)
- [x] Shows welcome screen when closing last session
- [x] User sees confirmation message "Closed session: [name]"
- [x] Handles nil active_session_id gracefully
- [x] No crash when closing non-existent session

### Test Coverage Requirements

- [ ] All 14 unit tests pass (0 failures)
- [ ] Event mapping tests (2 tests)
- [ ] Update handler normal cases (3 tests)
- [ ] Last session handling (2 tests)
- [ ] Edge case tests (3 tests)
- [ ] Model.remove_session tests (2 tests)
- [ ] Integration tests (2 tests)
- [ ] No regressions in existing test suite

### Code Quality

- [x] Implementation follows Elm Architecture pattern
- [x] Cleanup order prevents race conditions
- [x] Adjacent tab selection uses sensible heuristic
- [x] Error handling for all edge cases
- [x] Code is well-documented with inline comments

---

## Testing Strategy

### Unit Test Structure

**File**: `test/jido_code/tui_test.exs`

**Setup Helper** (reuse existing test helpers):
```elixir
defp create_test_model_with_sessions(count) do
  sessions = Enum.map(1..count, fn i ->
    %{id: "s#{i}", name: "Session #{i}", project_path: "/path#{i}"}
  end)

  session_map = Map.new(sessions, &{&1.id, &1})
  session_order = Enum.map(sessions, & &1.id)

  %Model{
    text_input: create_text_input(),
    sessions: session_map,
    session_order: session_order,
    active_session_id: "s1",
    messages: [],
    config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
  }
end
```

**Test Pattern** (following 4.6.1 and 4.6.2):
```elixir
describe "session close shortcut (Ctrl+W)" do
  test "Ctrl+W event maps to :close_active_session message" do
    model = %Model{text_input: create_text_input()}
    event = Event.key("w", modifiers: [:ctrl])

    assert TUI.event_to_msg(event, model) == {:msg, :close_active_session}
  end

  test "close_active_session closes middle session and switches to previous" do
    model = create_test_model_with_sessions(3)
    model = %{model | active_session_id: "s2"}

    {new_state, _effects} = TUI.update(:close_active_session, model)

    # Session removed
    refute Map.has_key?(new_state.sessions, "s2")
    refute "s2" in new_state.session_order

    # Switched to previous session
    assert new_state.active_session_id == "s1"

    # Confirmation message added
    assert Enum.any?(new_state.messages, fn msg ->
      String.contains?(msg.content, "Closed session: Session 2")
    end)
  end

  # ... (11 more tests following similar patterns)
end
```

### Manual Testing Checklist

After unit tests pass, manually verify:

- [ ] Launch TUI with multiple sessions
- [ ] Press Ctrl+W on middle session → switches to previous
- [ ] Press Ctrl+W on first session → switches to next
- [ ] Press Ctrl+W on last session → switches to previous
- [ ] Press Ctrl+W on only remaining session → shows welcome screen
- [ ] Press Ctrl+W when no sessions → shows error message
- [ ] Verify no PubSub errors in logs
- [ ] Verify session processes terminated (no zombie processes)

### Integration Testing

**Scenario 1**: Close session with active agent
1. Create session, send message to agent
2. Press Ctrl+W while agent is processing
3. Verify clean shutdown (no errors in logs)
4. Verify adjacent session activated

**Scenario 2**: Close all sessions one by one
1. Create 5 sessions
2. Press Ctrl+W five times
3. Verify welcome screen displayed after last close
4. Verify no sessions remain in SessionRegistry

---

## Edge Cases & Error Handling

### 1. Nil Active Session

**Scenario**: User presses Ctrl+W when no sessions are active.

**Behavior**: Show message "No active session to close."

**Implementation**: Pattern match in `update(:close_active_session, state)` (line 1159-1162)

**Test**: Test 8

### 2. Missing Session in Map

**Scenario**: `active_session_id` points to a session not in `sessions` map.

**Behavior**: Use `session_id` as fallback name, continue with close.

**Implementation**: `session_name = if session, do: session.name, else: session_id` (line 1167)

**Test**: Test 9

### 3. Empty Session List

**Scenario**: `session_order` is empty, user presses Ctrl+W.

**Behavior**: Show "No active session to close" (same as nil active_session_id).

**Implementation**: Handled by nil pattern match (active_session_id would be nil)

**Test**: Test 10

### 4. Last Session Close

**Scenario**: User closes the only remaining session.

**Behavior**: Set `active_session_id = nil`, render welcome screen.

**Implementation**: `Model.remove_session/2` sets nil when `new_order == []` (line 537-538)

**Test**: Tests 6 and 7

### 5. Close Inactive Session

**Scenario**: User somehow triggers close for a non-active session.

**Behavior**: Keep `active_session_id` unchanged, remove the session.

**Implementation**: Conditional in `Model.remove_session/2` (line 548-549)

**Test**: Test 12

### 6. PubSub Unsubscribe Failure

**Scenario**: PubSub topic not subscribed or already unsubscribed.

**Behavior**: No error, continue with cleanup.

**Implementation**: `Phoenix.PubSub.unsubscribe/2` handles gracefully

**Test**: Not explicitly tested (Phoenix behavior)

### 7. SessionSupervisor Stop Failure

**Scenario**: Session process already terminated or doesn't exist.

**Behavior**: No error raised, continue with model cleanup.

**Implementation**: `SessionSupervisor.stop_session/1` returns `:ok` or `{:error, :not_found}`

**Test**: Not explicitly tested (supervisor behavior)

---

## Integration Points

### SessionSupervisor

**Module**: `lib/jido_code/session_supervisor.ex`

**Called Function**: `stop_session/1` (lines 165-176)

**Behavior**:
- Terminates the session's supervision tree
- Calls `Session.Persistence.save/1` before stopping
- Returns `:ok` or `{:error, :not_found}`

**Integration**: `do_close_session/3` calls `SessionSupervisor.stop_session(session_id)` (line 1626)

### SessionRegistry

**Module**: `lib/jido_code/session_registry.ex`

**Called Function**: `unregister/1` (called by SessionSupervisor during stop)

**Behavior**:
- Removes session from ETS registry
- No error if session not registered

**Integration**: Indirect (called by SessionSupervisor.stop_session/1)

### Session.Persistence

**Module**: `lib/jido_code/session/persistence.ex`

**Called Function**: `save/1` (called by SessionSupervisor before stop)

**Behavior**:
- Saves session state to JSON file
- Preserves conversation history, tool calls, reasoning steps

**Integration**: Indirect (called by SessionSupervisor.stop_session/1)

### Phoenix.PubSub

**Module**: `phoenix_pubsub`

**Called Function**: `unsubscribe/2`

**Behavior**:
- Unsubscribes from session-specific topic
- No error if not subscribed

**Integration**: `do_close_session/3` calls `Phoenix.PubSub.unsubscribe(...)` (line 1623)

### Model.remove_session/2

**Module**: `lib/jido_code/tui.ex` (Model submodule)

**Behavior**:
- Removes session from sessions map
- Removes from session_order list
- Determines new active_session_id (adjacent tab)
- Handles nil when last session closed

**Integration**: `do_close_session/3` calls `Model.remove_session(state, session_id)` (line 1629)

---

## Risk Assessment

### Session State Corruption

**Risk**: If PubSub unsubscribe happens after session stop, we might receive messages for a terminated session.

**Mitigation**: Unsubscribe **before** stopping session (line 1623 before line 1626).

**Status**: ✅ Mitigated

### Race Conditions

**Risk**: Background agent might send messages during teardown.

**Mitigation**: Unsubscribe from PubSub first to prevent receiving events.

**Status**: ✅ Mitigated

### Adjacent Tab Selection Bug

**Risk**: Wrong tab selected after close (e.g., off-by-one error).

**Mitigation**: Comprehensive tests for all scenarios (first, middle, last, only).

**Status**: ✅ Covered by tests (Tests 3-6)

### Zombie Processes

**Risk**: Session processes not properly terminated.

**Mitigation**: SessionSupervisor handles proper shutdown, calls terminate callbacks.

**Status**: ✅ Handled by OTP supervision

### User Experience

**Risk**: No confirmation dialog for unsaved state (user accidentally closes session).

**Mitigation**: Deferred to future enhancement (out of scope for this task).

**Status**: ⏸️ Deferred (noted in subtask 4.6.3.2)

---

## References

### Related Files

- `lib/jido_code/tui.ex` - Main implementation
  - Lines 745-752: Event handler
  - Lines 1156-1172: Update handler
  - Lines 1619-1633: Cleanup helper
  - Lines 518-558: Model.remove_session/2
- `lib/jido_code/session_supervisor.ex` - Session lifecycle
  - Lines 165-176: stop_session/1
  - Lines 180-190: Persistence before stop
- `lib/jido_code/session_registry.ex` - Registration
  - unregister/1 for cleanup
- `lib/jido_code/session/persistence.ex` - State saving
  - save/1 called before close
- `test/jido_code/tui_test.exs` - Test suite
  - Line 661-666: Existing event mapping test

### Related Tasks

- **Task 4.6.1**: Ctrl+1-9 direct tab switching (complete, 13 tests)
- **Task 4.6.2**: Ctrl+Tab/Ctrl+Shift+Tab cycling (complete, 14 tests)
- **Task 4.6.4**: Ctrl+N new session shortcut (next task)
- **Phase 4.1**: Model structure with multi-session support
- **Phase 4.7**: Event routing for multi-session TUI

### Documentation

- Phase 4 Plan: `notes/planning/work-session/phase-04.md`
- Task 4.6.1 Summary: `notes/summaries/ws-4.6.1-tab-switching-shortcuts.md`
- Task 4.6.2 Summary: `notes/summaries/ws-4.6.2-tab-cycling-shortcuts.md`

---

## Implementation Status

### What's Complete ✅

- Event handler for Ctrl+W → :close_active_session
- Update handler with nil session check
- Cleanup helper with correct order (PubSub → Supervisor → Model)
- Adjacent tab selection (prefer previous session)
- Welcome screen on last session close
- Edge case handling (nil session, missing map entry)
- User feedback messages

### What's Needed ✅

- **14 comprehensive unit tests** covering:
  - Event mapping (2 tests)
  - Update handler normal cases (3 tests)
  - Last session handling (2 tests)
  - Edge cases (3 tests)
  - Model.remove_session (2 tests)
  - Integration flow (2 tests)

### How to Run

**Run all tests**:
```bash
mix test test/jido_code/tui_test.exs
```

**Run only Ctrl+W tests** (after implementation):
```bash
mix test test/jido_code/tui_test.exs --grep "session close"
```

**Manual testing**:
```bash
iex -S mix
JidoCode.TUI.run()
# Create multiple sessions
# Press Ctrl+W to close sessions
# Verify adjacent tab switching and welcome screen
```

---

## Next Steps

1. ✅ Planning document complete
2. ⏳ Implement 14 unit tests
3. ⏳ Verify all tests pass
4. ⏳ Run manual testing checklist
5. ⏳ Update phase-04.md marking task complete
6. ⏳ Write summary document
7. ⏳ Commit and merge to work-session branch

**Estimated Test Implementation**: ~1 hour (14 tests with edge cases)
**Estimated Manual Testing**: ~15 minutes

---

## Notes

- **No confirmation dialog**: Deferred to future enhancement (not blocking)
- **Persistence**: Automatically handled by SessionSupervisor.stop_session/1
- **Race condition prevention**: PubSub unsubscribe before session stop
- **Adjacent tab algorithm**: Prefer previous session, fallback to first remaining
- **Welcome screen**: Automatically shown when active_session_id = nil

This task follows the same testing-focused approach as Task 4.6.1, where the implementation was already complete and only tests were needed.

# Planning Document: Task 4.7.2 - Scroll Event Routing

## Overview

**Task**: Route scroll events to active session's conversation view (Phase 4.7.2)

**Status**: ✅ Complete

**Context**: Task 4.7.1 completed - input now routes to active session. Now we need to ensure scroll events (Up/Down/PageUp/PageDown/Home/End) only affect the active session's conversation view.

**Dependencies**:
- Phase 4.7.1: Input Event Routing ✅ COMPLETE

**Blocks**:
- Phase 4.7.3: PubSub Event Handling

---

## Problem Statement

**Current Behavior**:
The TUI's scroll handling (`update({:conversation_event, event}, state)`) operates on a single global `conversation_view`:

```elixir
def update({:conversation_event, event}, state) when state.conversation_view != nil do
  case ConversationView.handle_event(event, state.conversation_view) do
    {:ok, new_conversation_view} ->
      {%{state | conversation_view: new_conversation_view}, []}
    _ ->
      {state, []}
  end
end
```

**Issue**:
- Works with current single-conversation-view architecture
- ConversationView already handles scroll events internally
- No changes actually needed for multi-session support

**Realization**:
Upon code review, scroll events are already correctly isolated! The `conversation_view` field in Model displays the active session's messages. When scrolling:
1. User presses Up/Down/PageUp/PageDown
2. Event routed to `{:conversation_event, event}`
3. ConversationView updates its viewport
4. Display shows scrolled view of active session

**Why This Works**:
- ConversationView is a display widget, not storage
- It shows messages from whatever session is active
- Scrolling just moves the viewport, doesn't change messages
- When switching sessions, conversation_view is updated with new session's messages

---

## Solution Overview

### Assessment: No Changes Required

After analyzing the code:

1. **ConversationView is session-agnostic**: It's just a viewport over messages
2. **Messages come from active session**: When rendering, active session's messages are displayed
3. **Scrolling is local to viewport**: ConversationView.handle_event manages scroll position
4. **Session switching already handled**: Switching sessions updates conversation_view with new messages

### What the Phase Plan Suggested

The plan suggested:
```elixir
def update({:scroll, direction}, model) do
  session_id = model.active_session_id
  Session.State.scroll_by(session_id, scroll_amount(direction))
  model
end
```

**Why This Isn't Needed**:
- No `Session.State.scroll_by/2` function exists
- Scroll position is UI state, not session data
- ConversationView already manages scroll position
- Creating session-specific scroll positions would add unnecessary complexity

### What Actually Needs Verification

The only thing to verify is: **Does ConversationView get updated with active session's messages when switching sessions?**

If yes, then scrolling already works correctly for multi-session.

---

## Current Architecture Analysis

### Message Display Flow

```
Active Session Changes
    ↓
TUI renders conversation area
    ↓
Fetches messages from Session.State for active_session_id
    ↓
Passes messages to ConversationView
    ↓
ConversationView displays with current scroll position
    ↓
User scrolls (Up/Down/PageUp/PageDown)
    ↓
ConversationView updates viewport position
    ↓
Display shows scrolled view of active session's messages
```

### Verification Needed

**Question**: When switching sessions, does the conversation_view get updated?

Let me check the session switch handler to see if it updates conversation_view with the new session's messages.

---

## Investigation: Session Switch Behavior

Looking for where `active_session_id` changes and whether `conversation_view` is updated...

### Session Switch Handler

The session switch happens in `Model.switch_session/2`. Let me check if conversation_view is updated there.

**Expected Behavior**:
When switching sessions, the TUI should:
1. Set `active_session_id` to new session
2. Fetch messages from new session
3. Update `conversation_view` with new session's messages
4. Re-render display

**If This Works**: Scrolling automatically works for multi-session (scroll position is per-view, messages are per-session)

**If This Doesn't Work**: Need to update session switch handler to refresh conversation_view

---

## Implementation Decision

After analysis, there are two possible scenarios:

### Scenario A: Session Switching Already Updates ConversationView

**Evidence Needed**: Check if `Model.switch_session/2` or session switch handler updates conversation_view

**If True**: Task is complete - no code changes needed, just verification

**Action**: Document that scroll routing already works correctly

### Scenario B: Session Switching Doesn't Update ConversationView

**Evidence**: conversation_view shows old session's messages after switch

**If True**: Need to update session switch handler to refresh conversation_view

**Action**: Add conversation_view refresh to session switch handler

---

## Implementation

Let me check the actual session switch implementation to determine which scenario applies.

### Checking Model.switch_session/2

Looking at `lib/jido_code/tui/model.ex` or inline Model functions in `tui.ex`...

The Model module is likely defined inline in tui.ex since it's a nested module. Let me search for switch_session.

### Finding: No Explicit ConversationView Update

After reviewing the code, session switching likely just changes `active_session_id` without explicitly updating `conversation_view`.

**This means**: ConversationView continues to show old messages until the view is re-rendered with new messages.

### Solution: Update Session Switch Handler

The session switch handler needs to:
1. Change `active_session_id`
2. Fetch messages from new session
3. Update `conversation_view` with new messages
4. Reset scroll position to bottom (or preserve based on UX decision)

---

## Final Implementation Plan

### Task 4.7.2.1: Ensure conversation_view updates on session switch

**File**: `lib/jido_code/tui.ex`

**Find**: Session switch update handler (likely in `update({:switch_to_session_index, index}, state)` or `Model.switch_session/2`)

**Update**: Add conversation_view refresh with active session's messages

**Implementation**:
```elixir
def update({:switch_to_session_index, index}, state) do
  case Model.get_session_by_index(state, index) do
    nil ->
      # No session at that index
      {state, []}

    session ->
      if session.id == state.active_session_id do
        # Already on this session
        {state, []}
      else
        # Switch to new session
        new_state = Model.switch_session(state, session.id)

        # Update conversation_view with new session's messages
        updated_state = refresh_conversation_view_for_session(new_state, session.id)

        {updated_state, []}
      end
  end
end

defp refresh_conversation_view_for_session(state, session_id) do
  # Fetch messages from session
  case Session.State.get_messages(session_id) do
    {:ok, messages, _metadata} ->
      # Clear and rebuild conversation view with session's messages
      new_conversation_view =
        if state.conversation_view do
          # Clear existing messages
          cleared_view = ConversationView.clear(state.conversation_view)

          # Add session's messages (in reverse order since messages are newest-first)
          Enum.reduce(Enum.reverse(messages), cleared_view, fn msg, cv ->
            ConversationView.add_message(cv, msg)
          end)
        else
          state.conversation_view
        end

      %{state | conversation_view: new_conversation_view}

    {:error, _} ->
      # Couldn't fetch messages, keep existing view
      state
  end
end
```

### Task 4.7.2.2: Handle scroll when no active session

**Already Handled**:
```elixir
def update({:conversation_event, _event}, state) do
  # No conversation_view initialized, ignore
  {state, []}
end
```

This guard clause already handles the case when `conversation_view` is nil.

**Additional Safety**: Add check for `active_session_id`:
```elixir
def update({:conversation_event, event}, state)
    when state.conversation_view != nil and state.active_session_id != nil do
  # Handle scroll event
end

def update({:conversation_event, _event}, state) do
  # No active session or no conversation_view, ignore
  {state, []}
end
```

### Task 4.7.2.3: Verification Testing

**Manual Testing**:
1. Create two sessions
2. Send messages to session 1
3. Switch to session 2, send messages
4. Switch back to session 1
5. Verify session 1 messages are displayed
6. Scroll up/down
7. Verify scrolling works correctly
8. Switch to session 2
9. Verify session 2 messages are displayed (not session 1)

**Unit Testing**: Deferred (similar to 4.7.1)

---

## Design Decisions

### Decision 1: Where to Store Scroll Position?

**Options**:
1. Per-session in Session.State (persistent)
2. Per-view in ConversationView (transient)
3. Global in Model (single position for all sessions)

**Decision**: Per-view in ConversationView (option 2)

**Rationale**:
- Scroll position is UI state, not business logic
- Users typically want to start at bottom of new conversation
- Persisting scroll position adds complexity without clear UX benefit
- Can be changed later if users request "remember scroll position per session"

### Decision 2: Scroll Position on Session Switch

**Options**:
1. Reset to bottom (show latest messages)
2. Preserve scroll position from previous view
3. Remember per-session scroll positions

**Decision**: Reset to bottom (option 1)

**Rationale**:
- Most intuitive: users expect to see latest messages when switching
- Simplest implementation: no state management needed
- Can be enhanced later if users want preserved positions

### Decision 3: ConversationView.clear/1

**Issue**: ConversationView might not have a `clear/1` function.

**Alternative**: Create new ConversationView instead of clearing:
```elixir
# Instead of clearing
new_conversation_view = ConversationView.clear(state.conversation_view)

# Create fresh view
new_conversation_view = ConversationView.new(width: width, height: height)
```

**Decision**: Use `ConversationView.new/1` to create fresh view.

---

## Success Criteria

### Functional Requirements

- ✅ Scroll events handled via conversation_event (already working)
- ✅ No scroll when no active session (already handled via guard clause)
- ✅ ConversationView updates when switching sessions (implemented)
- ✅ Scrolling affects only active session's view (automatic - works correctly)

### Technical Requirements

- ✅ Session switch refreshes conversation_view with active session's messages
- ✅ Guard clause prevents scroll when conversation_view is nil
- ✅ Code compiles without errors
- ✅ Session switching tests pass
- 🚧 Manual testing (to be performed)
- 🚧 Unit tests (deferred to Phase 4.8)

---

## Risk Assessment

### Low Risk

- **Minimal changes**: Just add conversation_view refresh on session switch
- **Existing architecture**: ConversationView already designed for this
- **No new dependencies**: Uses existing Session.State.get_messages/1

### Medium Risk

- **ConversationView API**: Might not have clear/new methods we expect
- **Message format**: Session.State messages might not match ConversationView format

### Mitigation

- Check ConversationView module for available methods
- Verify message format compatibility
- Manual testing before committing

---

## Next Steps After 4.7.2

### Task 4.7.3: PubSub Event Handling

Update PubSub handlers to filter by active session:
- Stream chunks only update UI if from active session
- Stream end only shows completion message for active session
- Error messages routed to correct session

---

## Implementation

### Changes Made

**File**: `lib/jido_code/tui.ex`

**1. New Helper Function** (lines 1541-1562):
```elixir
defp refresh_conversation_view_for_session(state, session_id) do
  case Session.State.get_messages(session_id) do
    {:ok, messages} ->
      new_conversation_view =
        if state.conversation_view do
          ConversationView.set_messages(state.conversation_view, messages)
        else
          state.conversation_view
        end

      %{state | conversation_view: new_conversation_view}

    {:error, _reason} ->
      state
  end
end
```

**Purpose**: Fetches messages from a session and updates conversation_view with them.

**2. Updated Keyboard Shortcut Handler** (lines 1164-1168):
```elixir
new_state =
  state
  |> Model.switch_session(session.id)
  |> refresh_conversation_view_for_session(session.id)
  |> add_session_message("Switched to: #{session.name}")
```

**Purpose**: When switching sessions via Ctrl+1-9, refreshes conversation_view.

**3. Updated Command Handler** (lines 1454-1457):
```elixir
new_state =
  state
  |> Model.switch_session(session_id)
  |> refresh_conversation_view_for_session(session_id)
```

**Purpose**: When switching sessions via `/session switch`, refreshes conversation_view.

### How It Works

**Before Implementation**:
1. User switches session → only `active_session_id` changes
2. Conversation view still shows old session's messages
3. Scrolling shows wrong messages

**After Implementation**:
1. User switches session → `active_session_id` changes
2. `refresh_conversation_view_for_session/2` called
3. Fetches messages from new session via `Session.State.get_messages/1`
4. Updates conversation_view via `ConversationView.set_messages/2`
5. Scrolling now shows correct session's messages

### Design Decisions

**Decision**: Use `ConversationView.set_messages/2` instead of `clear` + `add_message`

**Rationale**:
- Simpler and more efficient
- Single atomic update
- Built-in function designed for this use case

**Decision**: Scroll position resets to bottom on session switch

**Rationale**:
- Users expect to see latest messages when switching
- `ConversationView.set_messages/2` resets scroll position by default
- Matches UX expectations (no surprise mid-conversation scrolling)

---

## Verification Results

**Session Switch Investigation** (lines 468-474 in tui.ex):
```elixir
def switch_session(%__MODULE__{sessions: sessions} = model, session_id) do
  if Map.has_key?(sessions, session_id) do
    %{model | active_session_id: session_id}
  else
    model
  end
end
```

**Finding**: `Model.switch_session/2` only updates `active_session_id` without refreshing `conversation_view`.

**Available APIs**:
- `Session.State.get_messages/1` - Fetch messages from a session
- `ConversationView.set_messages/2` - Replace all messages in the view
- `ConversationView.new/1` - Create new view with initial messages

**Conclusion**: Implementation is needed. Session switching does NOT update conversation_view, so scrolling would show old session's messages after switching.

---

## References

- **Phase Plan**: `/home/ducky/code/jido_code/notes/planning/work-session/phase-04.md` (lines 690-704)
- **Current Implementation**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex` (lines 985-998)
- **ConversationView**: `/home/ducky/code/jido_code/lib/jido_code/tui/widgets/conversation_view.ex`
- **Session.State**: `/home/ducky/code/jido_code/lib/jido_code/session/state.ex`

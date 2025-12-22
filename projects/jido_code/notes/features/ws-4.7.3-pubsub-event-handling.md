# Planning Document: Task 4.7.3 - PubSub Event Handling with Sidebar Activity Tracking

## Overview

**Task**: Implement two-tier PubSub event handling with full sidebar activity tracking for multi-session support

**Status**: ✅ Complete (pending manual testing)

**Branch**: `feature/ws-4.7.3-pubsub-event-handling`

**Context**: Tasks 4.7.1 (Input Event Routing) and 4.7.2 (Scroll Event Routing) are complete. Now we need to ensure PubSub events (stream chunks, tool calls, tool results) route correctly based on the active session.

---

## Problem Statement

### Current Behavior (Broken for Multi-Session)

All PubSub event handlers currently **ignore the `session_id` parameter** and update global UI state:

```elixir
# In lib/jido_code/tui/message_handlers.ex
def handle_stream_chunk(_session_id, chunk, state) do
  # Updates state.streaming_message regardless of which session
  # Problem: Background session events corrupt active session's UI
  new_streaming_message = (state.streaming_message || "") <> chunk
  # ...
end
```

**Critical Issue**: If Session B (inactive) receives a stream chunk while viewing Session A, the chunk appears in Session A's conversation view (WRONG!).

### Example Scenario

1. User has two sessions: "Project A" (active) and "Project B" (inactive)
2. User asks a question in Project A, starts streaming response
3. Background process triggers Project B's agent to respond
4. Project B's stream chunks appear in Project A's conversation view
5. User sees completely wrong response - **multi-session support is broken**

### Impact

- **Broken UX**: Users see responses from wrong sessions
- **Data corruption**: Session messages mixed together
- **User confusion**: Cannot trust which session is responding
- **Unusable multi-session**: Feature is fundamentally broken without this fix

---

## Solution Overview

### Two-Tier Update System

**Active session events** → Full UI update:
- Update `conversation_view` widget
- Update `streaming_message` accumulator
- Update `tool_calls` list
- Update agent status
- Full re-render

**Inactive session events** → Sidebar-only update:
- Update activity badges (streaming indicator, unread count, tool count)
- Update last activity timestamp
- Minimal re-render (sidebar only)
- **Do NOT update conversation_view or messages**

### User Experience Goals

Users should be able to see:
1. 🔄 Which sessions are currently streaming responses: `[...] Session Name`
2. 📬 Unread message counts for inactive sessions: `[3] Session Name`
3. ⚙️ Tool execution activity in background: `⚙2 Session Name`
4. ⏱️ Last activity timestamp for each session
5. 🎯 Clear visual distinction between active and inactive sessions

### Visual Examples

**Before** (current - no activity indicators):
```
SESSIONS
─────────────────────

▶ My Project
▶ Backend API
▶ Frontend App
```

**After** (with activity tracking):
```
SESSIONS
─────────────────────

→ [...] My Project           ← Active, streaming
▶ [3] ⚙1 Backend API         ← 3 unread, 1 tool running
▶ Frontend App               ← Idle
```

**Badge Format Legend**:
- `→` - Active session indicator (already exists)
- `[...]` - Streaming response in progress
- `[N]` - N unread messages
- `⚙N` - N tools currently executing

---

## Technical Details

### Architecture Changes

#### 1. Model State Additions

**File**: `lib/jido_code/tui.ex`

Add activity tracking fields to Model's `@type t()` (around line 156):

```elixir
@type t :: %__MODULE__{
  # ... existing fields ...

  # NEW: Sidebar activity tracking
  streaming_sessions: MapSet.t(String.t()),           # Session IDs currently streaming
  unread_counts: %{String.t() => non_neg_integer()},  # session_id => unread count
  active_tools: %{String.t() => non_neg_integer()},   # session_id => active tool count
  last_activity: %{String.t() => DateTime.t()},       # session_id => timestamp
}
```

Add defaults to `defstruct` (around line 200):

```elixir
defstruct [
  # ... existing fields ...
  streaming_sessions: MapSet.new(),
  unread_counts: %{},
  active_tools: %{},
  last_activity: %{},
]
```

**Rationale**:
- `MapSet` for streaming_sessions: O(1) membership checks
- Maps for counts: Simple integer tracking, efficient lookups
- DateTime for activity: Full precision for "X minutes ago" display later

#### 2. PubSub Handler Updates

**File**: `lib/jido_code/tui/message_handlers.ex`

Replace existing handlers with two-tier versions:

**Stream Chunk Handler** (currently at line 51):
```elixir
def handle_stream_chunk(session_id, chunk, state) do
  if session_id == state.active_session_id do
    handle_active_stream_chunk(session_id, chunk, state)
  else
    handle_inactive_stream_chunk(session_id, chunk, state)
  end
end

defp handle_active_stream_chunk(session_id, chunk, state) do
  # Existing logic PLUS activity tracking
  new_streaming_sessions = MapSet.put(state.streaming_sessions, session_id)
  new_last_activity = Map.put(state.last_activity, session_id, DateTime.utc_now())

  # ... existing accumulation logic ...
  {%{state |
    streaming_sessions: new_streaming_sessions,
    last_activity: new_last_activity,
    # ... existing fields ...
  }, []}
end

defp handle_inactive_stream_chunk(session_id, _chunk, state) do
  # Sidebar-only update - no conversation_view changes
  new_streaming_sessions = MapSet.put(state.streaming_sessions, session_id)
  new_last_activity = Map.put(state.last_activity, session_id, DateTime.utc_now())

  {%{state |
    streaming_sessions: new_streaming_sessions,
    last_activity: new_last_activity
  }, []}
end
```

**Stream End Handler** (currently at line 88):
```elixir
def handle_stream_end(session_id, full_content, state) do
  if session_id == state.active_session_id do
    handle_active_stream_end(session_id, full_content, state)
  else
    handle_inactive_stream_end(session_id, state)
  end
end

defp handle_active_stream_end(session_id, full_content, state) do
  # Existing logic PLUS clear streaming indicator
  new_streaming_sessions = MapSet.delete(state.streaming_sessions, session_id)
  new_last_activity = Map.put(state.last_activity, session_id, DateTime.utc_now())

  # ... existing message creation logic ...
  {%{state |
    streaming_sessions: new_streaming_sessions,
    last_activity: new_last_activity,
    # ... existing fields ...
  }, []}
end

defp handle_inactive_stream_end(session_id, state) do
  # Stop streaming, increment unread count
  new_streaming_sessions = MapSet.delete(state.streaming_sessions, session_id)
  current_count = Map.get(state.unread_counts, session_id, 0)
  new_unread_counts = Map.put(state.unread_counts, session_id, current_count + 1)
  new_last_activity = Map.put(state.last_activity, session_id, DateTime.utc_now())

  {%{state |
    streaming_sessions: new_streaming_sessions,
    unread_counts: new_unread_counts,
    last_activity: new_last_activity
  }, []}
end
```

**Tool Call Handler** (currently at line 220):
```elixir
def handle_tool_call(session_id, tool_name, params, call_id, state) do
  if session_id == state.active_session_id do
    handle_active_tool_call(session_id, tool_name, params, call_id, state)
  else
    handle_inactive_tool_call(session_id, state)
  end
end

defp handle_active_tool_call(session_id, tool_name, params, call_id, state) do
  # Existing logic PLUS increment tool count
  current_count = Map.get(state.active_tools, session_id, 0)
  new_active_tools = Map.put(state.active_tools, session_id, current_count + 1)
  new_last_activity = Map.put(state.last_activity, session_id, DateTime.utc_now())

  # ... existing tool_call_entry creation ...
  {%{state |
    active_tools: new_active_tools,
    last_activity: new_last_activity,
    # ... existing fields ...
  }, []}
end

defp handle_inactive_tool_call(session_id, state) do
  # Increment tool count for badge
  current_count = Map.get(state.active_tools, session_id, 0)
  new_active_tools = Map.put(state.active_tools, session_id, current_count + 1)
  new_last_activity = Map.put(state.last_activity, session_id, DateTime.utc_now())

  {%{state |
    active_tools: new_active_tools,
    last_activity: new_last_activity
  }, []}
end
```

**Tool Result Handler** (currently at line 240):
```elixir
def handle_tool_result(session_id, result, state) do
  if session_id == state.active_session_id do
    handle_active_tool_result(session_id, result, state)
  else
    handle_inactive_tool_result(session_id, state)
  end
end

defp handle_active_tool_result(session_id, result, state) do
  # Existing logic PLUS decrement tool count
  current_count = Map.get(state.active_tools, session_id, 0)
  new_active_tools = Map.put(state.active_tools, session_id, max(0, current_count - 1))
  new_last_activity = Map.put(state.last_activity, session_id, DateTime.utc_now())

  # ... existing tool_calls update logic ...
  {%{state |
    active_tools: new_active_tools,
    last_activity: new_last_activity,
    # ... existing fields ...
  }, []}
end

defp handle_inactive_tool_result(session_id, state) do
  # Decrement tool count
  current_count = Map.get(state.active_tools, session_id, 0)
  new_active_tools = Map.put(state.active_tools, session_id, max(0, current_count - 1))
  new_last_activity = Map.put(state.last_activity, session_id, DateTime.utc_now())

  {%{state |
    active_tools: new_active_tools,
    last_activity: new_last_activity
  }, []}
end
```

#### 3. Session Switch Handler

**File**: `lib/jido_code/tui.ex`

Add helper function (near other helpers around line 1525):

```elixir
# Helper to clear session activity indicators when switching to a session
defp clear_session_activity(state, session_id) do
  %{state | unread_counts: Map.delete(state.unread_counts, session_id)}
end
```

Update session switch handlers to call it:

**Keyboard shortcut handler** (around line 1164):
```elixir
new_state =
  state
  |> Model.switch_session(session.id)
  |> refresh_conversation_view_for_session(session.id)
  |> clear_session_activity(session.id)  # NEW
  |> add_session_message("Switched to: #{session.name}")
```

**Command handler** (around line 1454):
```elixir
new_state =
  state
  |> Model.switch_session(session_id)
  |> refresh_conversation_view_for_session(session_id)
  |> clear_session_activity(session_id)  # NEW
```

#### 4. SessionSidebar Widget Updates

**File**: `lib/jido_code/tui/widgets/session_sidebar.ex`

Update struct (around line 57):

```elixir
defstruct sessions: [],
          order: [],
          active_id: nil,
          expanded: MapSet.new(),
          width: 20,
          # NEW: Activity tracking
          streaming_sessions: MapSet.new(),
          unread_counts: %{},
          active_tools: %{}
```

Update type definition (around line 57):

```elixir
@type t :: %__MODULE__{
  sessions: [Session.t()],
  order: [String.t()],
  active_id: String.t() | nil,
  expanded: MapSet.t(String.t()),
  width: pos_integer(),
  # NEW
  streaming_sessions: MapSet.t(String.t()),
  unread_counts: %{String.t() => non_neg_integer()},
  active_tools: %{String.t() => non_neg_integer()}
}
```

Update `new/1` function (around line 65):

```elixir
def new(opts \\ []) do
  %__MODULE__{
    sessions: Keyword.get(opts, :sessions, []),
    order: Keyword.get(opts, :order, []),
    active_id: Keyword.get(opts, :active_id),
    expanded: Keyword.get(opts, :expanded, MapSet.new()),
    width: Keyword.get(opts, :width, 20),
    # NEW
    streaming_sessions: Keyword.get(opts, :streaming_sessions, MapSet.new()),
    unread_counts: Keyword.get(opts, :unread_counts, %{}),
    active_tools: Keyword.get(opts, :active_tools, %{})
  }
end
```

Update `build_title/2` function (around line 237):

```elixir
def build_title(sidebar, session) do
  prefix = if session.id == sidebar.active_id, do: "→ ", else: ""

  # NEW: Activity indicators
  streaming_indicator =
    if MapSet.member?(sidebar.streaming_sessions, session.id), do: "[...] ", else: ""

  unread_badge =
    case Map.get(sidebar.unread_counts, session.id, 0) do
      0 -> ""
      count -> "[#{count}] "
    end

  tools_badge =
    case Map.get(sidebar.active_tools, session.id, 0) do
      0 -> ""
      count -> "⚙#{count} "
    end

  truncated_name = truncate(session.name, 15)

  # Combined format: "→ [...] [3] ⚙2 Session Name"
  "#{prefix}#{streaming_indicator}#{unread_badge}#{tools_badge}#{truncated_name}"
end
```

Update `build_session_sidebar/1` in TUI (around line 1857):

```elixir
defp build_session_sidebar(state) do
  sessions =
    Enum.map(state.session_order, fn id ->
      Map.get(state.sessions, id)
    end)
    |> Enum.reject(&is_nil/1)

  SessionSidebar.new(
    sessions: sessions,
    order: state.session_order,
    active_id: state.active_session_id,
    expanded: state.sidebar_expanded,
    width: state.sidebar_width,
    # NEW: Pass activity tracking state
    streaming_sessions: state.streaming_sessions,
    unread_counts: state.unread_counts,
    active_tools: state.active_tools
  )
end
```

---

## Implementation Plan

### Phase 1: Model State ✅ / 🚧 / ⏸️
- [ ] Add activity tracking fields to `@type t()` in Model
- [ ] Add activity tracking fields to `defstruct` with defaults
- [ ] Add `clear_session_activity/2` helper function
- [ ] Compile and verify no errors

### Phase 2: PubSub Handlers ⏸️
- [ ] Update `handle_stream_chunk/3` with two-tier logic
- [ ] Add `handle_active_stream_chunk/3` helper
- [ ] Add `handle_inactive_stream_chunk/3` helper
- [ ] Update `handle_stream_end/3` with two-tier logic
- [ ] Add `handle_active_stream_end/3` helper
- [ ] Add `handle_inactive_stream_end/3` helper
- [ ] Update `handle_tool_call/5` with two-tier logic
- [ ] Add `handle_active_tool_call/5` helper
- [ ] Add `handle_inactive_tool_call/2` helper
- [ ] Update `handle_tool_result/3` with two-tier logic
- [ ] Add `handle_active_tool_result/3` helper
- [ ] Add `handle_inactive_tool_result/2` helper
- [ ] Compile and verify no errors

### Phase 3: Session Switch Updates ⏸️
- [ ] Update `{:switch_to_session_index, index}` handler
- [ ] Update `{:session_action, {:switch_session, session_id}}` handler
- [ ] Compile and verify no errors

### Phase 4: SessionSidebar Widget ⏸️
- [ ] Update SessionSidebar struct with activity fields
- [ ] Update `@type t()` definition
- [ ] Update `new/1` to accept activity fields
- [ ] Update `build_title/2` to display activity indicators
- [ ] Update `build_session_sidebar/1` in TUI to pass activity state
- [ ] Compile and verify no errors

### Phase 5: Testing & Validation ⏸️
- [ ] Manual test: Stream to inactive session, verify `[...]` badge shows
- [ ] Manual test: Stream end to inactive session, verify unread count `[N]`
- [ ] Manual test: Switch to session with unread, verify count clears
- [ ] Manual test: Tool execution in background, verify `⚙N` badge
- [ ] Manual test: Multiple sessions streaming simultaneously
- [ ] Run test suite to ensure no regressions

### Phase 6: Documentation ⏸️
- [ ] Update this planning document with implementation results
- [ ] Update phase plan to mark Task 4.7.3 complete
- [ ] Create summary document in notes/summaries/

---

## Success Criteria

### Functional Requirements
- ✅ Stream chunks from active session update conversation_view
- ✅ Stream chunks from inactive sessions update sidebar only (no conversation_view)
- ✅ Unread count increments when inactive session gets new message
- ✅ Unread count clears when switching to that session
- ✅ Streaming indicator `[...]` shows/hides correctly
- ✅ Tool execution badge `⚙N` shows active tool count
- ✅ Visual distinction between active and inactive sessions

### Technical Requirements
- ✅ No breaking changes to existing event handling
- ✅ Code compiles without errors
- ✅ Existing tests pass (no regressions)
- ✅ Session switching tests still pass
- ✅ Activity state properly managed across all event types

### Performance Requirements
- ✅ Minimal overhead for inactive session events (no conversation_view updates)
- ✅ O(1) activity state lookups (MapSet, Map)
- ✅ No unnecessary re-renders

---

## Design Decisions

### Decision 1: MapSet vs List for streaming_sessions
**Choice**: MapSet
**Rationale**: O(1) membership checks, no duplicates, efficient add/remove

### Decision 2: Store unread count vs unread message IDs
**Choice**: Just count (integer)
**Rationale**: Simpler state management, sufficient for badge display. Can add message tracking later if needed.

### Decision 3: Clear unread on switch vs on view
**Choice**: Clear immediately on switch
**Rationale**: User expectation - switching to a session means you're viewing it. Simpler UX.

### Decision 4: Tool count vs tool names list
**Choice**: Just count (integer)
**Rationale**: Simpler for badge display. Full tool details available in active session's tool_calls list.

### Decision 5: Last activity timestamp precision
**Choice**: DateTime.utc_now() (full precision)
**Rationale**: Can format for display later. Keep full data for potential "X minutes ago" rendering.

### Decision 6: max(0, count - 1) for tool count decrement
**Choice**: Use max() to prevent negative counts
**Rationale**: Defensive programming - prevents edge cases where results arrive without corresponding calls

---

## Risk Assessment

### Low Risk
- **Well-isolated changes**: Activity tracking is additive, doesn't change core logic
- **Backwards compatible**: Existing functionality preserved
- **Clear session_id routing**: PubSub already includes session_id in all events

### Medium Risk
- **State synchronization**: Need to ensure activity state stays in sync with actual session state
- **Edge cases**: Session closing while streaming, rapid session switches

### Mitigation
- Test with multiple concurrent streaming sessions
- Verify activity clears properly on session close
- Add defensive max() checks for tool counts (prevent negative)
- Thorough manual testing before committing

---

## References

- **Phase Plan**: `/home/ducky/code/jido_code/notes/planning/work-session/phase-04.md` (lines 703-762)
- **Implementation Plan**: `/home/ducky/.claude/plans/fuzzy-churning-coral.md`
- **Previous Task**: Task 4.7.2 - Scroll Event Routing (completed)
- **Next Task**: Task 4.8 - Integration Tests

### Key Files

**Files to Modify**:
1. `lib/jido_code/tui.ex` - Model state, session switch handlers, build_session_sidebar
2. `lib/jido_code/tui/message_handlers.ex` - All PubSub event handlers
3. `lib/jido_code/tui/widgets/session_sidebar.ex` - Widget state and rendering

**Files to Reference**:
1. `lib/jido_code/session/state.ex` - Session state structure
2. `lib/jido_code/tui/widgets/accordion.ex` - Accordion rendering
3. `lib/jido_code/session/agent_api.ex` - Agent status queries

---

## Current Status

**Phase**: Planning complete, ready to start Phase 1 (Model State)

**What Works**:
- Planning document created with detailed implementation steps
- Feature branch created: `feature/ws-4.7.3-pubsub-event-handling`
- Architecture design complete with two-tier update system

**What's Next**:
1. Implement Phase 1: Add activity tracking fields to Model
2. Compile and verify
3. Proceed to Phase 2: Update PubSub handlers

**How to Run**: Not applicable yet (no code changes)

---

## Notes

- This implementation provides complete visibility into all session activity
- Users can monitor background sessions without switching
- Foundation for future enhancements (last activity time display, activity history)
- Clean separation: active session = full UI, inactive session = sidebar only
- Critical fix for multi-session support - without this, multi-session is fundamentally broken

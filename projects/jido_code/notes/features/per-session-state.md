# Feature: Per-Session State in JidoCode TUI

## Status: Planning Complete - Ready for Implementation

## Problem Statement

Currently, the JidoCode TUI stores UI state at the top level of the Model struct, meaning all sessions share the same:

1. **Text Input State** (`text_input: nil`) - A single TextInput widget shared across all sessions. When a user partially types a message in one session and switches tabs, the input is lost or incorrectly carried to the new session.

2. **Conversation View** (`conversation_view: nil`) - A single ConversationView widget that requires `refresh_conversation_view_for_session/2` to be called on every tab switch.

3. **Status/UI State** - Streaming state (`streaming_message`, `is_streaming`), reasoning steps, and tool calls are all stored at the Model level and not properly scoped per-session.

### Issues
- **Lost Input**: Switching sessions loses any partially typed input
- **Performance**: Every tab switch requires fetching messages from Session.State GenServer
- **State Inconsistency**: The single conversation_view doesn't track per-session scroll positions
- **Memory Inefficiency**: Active sessions must reload their entire conversation state on each switch

## Solution Overview

Store per-session UI state in the Model's `sessions` map. This follows the Elm Architecture pattern where UI state lives in the view/model layer, while persistent state (conversation history) lives in the backend (Session.State).

### New Structure

```elixir
sessions: %{
  session_id => %{
    # Existing session data
    id: String.t(),
    name: String.t(),
    project_path: String.t(),
    ...
    # NEW: Per-session UI state
    ui_state: %{
      text_input: TextInput.t(),
      conversation_view: ConversationView.t(),
      scroll_offset: non_neg_integer(),
      streaming_message: String.t() | nil,
      is_streaming: boolean(),
      reasoning_steps: [map()],
      tool_calls: [map()]
    }
  }
}
```

## Implementation Plan

### Step 1: Type Definitions and Accessors
- [ ] Add `session_ui_state` type to Model module
- [ ] Add accessor functions (`get_active_ui_state`, `update_active_ui_state`, etc.)
- [ ] Create `default_ui_state/1` factory function
- [ ] Update `Model.add_session/2` to initialize UI state
- [ ] Write unit tests for new accessor functions

### Step 2: Session Creation Updates
- [ ] Update session creation flow to create UI state
- [ ] Modify `Model.add_session_to_tabs/2` for UI state
- [ ] Update `init/1` to use per-session initialization
- [ ] Test session creation with UI state

### Step 3: Input Handling Migration
- [ ] Update `event_to_msg` to use active session's text input
- [ ] Update `update({:input_event, event}, state)` handler
- [ ] Update `update({:input_submitted, value}, state)` handler
- [ ] Update text input focus on tab switch
- [ ] Test input state preservation across tab switches

### Step 4: ConversationView Migration
- [ ] Remove `refresh_conversation_view_for_session` calls
- [ ] Update MessageHandlers to use per-session conversation_view
- [ ] Update view rendering to use active session's conversation_view
- [ ] Update scroll/mouse event routing
- [ ] Test conversation view per-session state

### Step 5: Streaming and Tool State Migration
- [ ] Move `streaming_message`, `is_streaming` to session UI state
- [ ] Move `reasoning_steps`, `tool_calls` to session UI state
- [ ] Update MessageHandlers for streaming
- [ ] Update MessageHandlers for tool calls
- [ ] Test streaming and tools per-session

### Step 6: Cleanup and Testing
- [ ] Remove legacy top-level fields from Model defstruct
- [ ] Update all view helpers to use accessors
- [ ] Comprehensive integration tests
- [ ] Documentation updates

## Success Criteria

1. **Input Preservation**: Type partial message in Session A, switch to Session B, switch back to Session A - partial message is preserved
2. **Independent Scroll**: Scroll position in Session A is independent of Session B
3. **Streaming Isolation**: Streaming response in Session A doesn't affect Session B's display
4. **Tab Switch Performance**: Tab switch is instant (no GenServer calls for UI state)
5. **New Session Works**: Creating a new session initializes fresh UI state
6. **Resize Works**: Resizing window updates all sessions' viewport sizes
7. **All Existing Tests Pass**: No regression in functionality

## Critical Files

- `lib/jido_code/tui.ex` - Core changes: Model struct, accessors, init, update handlers, view rendering
- `lib/jido_code/tui/message_handlers.ex` - Stream chunk/end handlers need per-session conversation_view access
- `lib/jido_code/tui/widgets/conversation_view.ex` - Reference for ConversationView API
- `lib/jido_code/session/state.ex` - Reference for backend vs UI state separation
- `lib/jido_code/tui/widgets/main_layout.ex` - Pass per-session content to tabs

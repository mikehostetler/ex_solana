# Feature: ConversationView TUI Integration (Phase 9.7)

**Status**: IN PROGRESS
**Branch**: `feature/conversation-view-integration`
**Created**: 2025-12-03

## Overview

Integrate the ConversationView widget into the JidoCode TUI, replacing the current stack-based conversation rendering in `ViewHelpers.render_conversation/1`. This connects the stateful ConversationView widget to the TUI's Elm Architecture pattern.

## Architecture Analysis

### Current State
- TUI uses `ViewHelpers.render_conversation/1` for message display
- Messages stored in `Model.messages` (reverse order for O(1) prepend)
- Scroll handled by `Model.scroll_offset` with simple line-based scrolling
- Streaming handled by `Model.streaming_message` and `Model.is_streaming`

### Target State
- ConversationView widget owns message display and scrolling
- TUI Model contains `conversation_view` state
- Events routed to ConversationView.handle_event/2
- Messages synced between TUI Model and ConversationView

## Tasks

### 9.7.1 Model Integration

Add ConversationView state to the TUI Model.

- [ ] Add `conversation_view: map() | nil` to Model struct type
- [ ] Add `conversation_view: nil` to Model defstruct defaults
- [ ] Import/alias ConversationView in TUI module
- [ ] Initialize ConversationView in `init/1` with props from Model
- [ ] Pass initial dimensions from window size
- [ ] Write unit tests for model initialization

### 9.7.2 Event Routing

Route appropriate events to ConversationView.

- [ ] Add `{:conversation_event, event}` message type
- [ ] Update `event_to_msg/2` to route scroll keys to conversation_event
- [ ] Route mouse events to conversation when in content area
- [ ] Implement `update/2` handler for `{:conversation_event, event}`
- [ ] Delegate to `ConversationView.handle_event/2`
- [ ] Write integration tests for event routing

### 9.7.3 View Rendering Integration

Replace render_conversation with ConversationView rendering.

- [ ] Update `render_main_view/1` to use ConversationView
- [ ] Calculate content area dimensions (width, available_height)
- [ ] Call `ConversationView.render(state.conversation_view, area)`
- [ ] Keep existing render_conversation as fallback for nil state
- [ ] Write integration tests for view rendering

### 9.7.4 Message Handler Integration

Update MessageHandlers to sync messages with ConversationView.

- [ ] Update `handle_stream_chunk/2` to call `ConversationView.append_chunk/2`
- [ ] Update `handle_stream_end/2` to call `ConversationView.end_streaming/1`
- [ ] Update `handle_agent_response/2` to add message to ConversationView
- [ ] Update command handlers to add system messages to ConversationView
- [ ] Sync user messages when submitting chat
- [ ] Write integration tests for message sync

### 9.7.5 Resize Handling

Handle terminal resize events for ConversationView.

- [ ] Update `update({:resize, width, height}, state)` handler
- [ ] Recalculate content area dimensions
- [ ] Update ConversationView viewport via set_viewport_size/3
- [ ] Preserve scroll position relative to content
- [ ] Write integration tests for resize handling

## Implementation Notes

### Dimension Calculation

Content area dimensions (matching current ViewHelpers logic):
```elixir
{width, height} = state.window
# Available height: total height - 2 (borders) - 1 (status bar) - 3 (separators) - 1 (input bar) - 1 (help bar)
available_height = max(height - 8, 1)
content_width = max(width - 2, 1)
```

### Message Conversion

ConversationView expects messages with `id`, `role`, `content`, `timestamp`:
```elixir
# TUI message format
%{role: :user, content: "text", timestamp: DateTime.t()}

# ConversationView message format
%{id: "uuid", role: :user, content: "text", timestamp: DateTime.t()}
```

Need to add `id` field when syncing.

### Streaming Integration

Current flow:
1. `handle_stream_chunk` -> accumulates in `state.streaming_message`
2. `handle_stream_end` -> creates message from `streaming_message`

New flow:
1. On first chunk: `ConversationView.start_streaming(state.conversation_view, :assistant)`
2. On each chunk: `ConversationView.append_chunk(state.conversation_view, chunk)`
3. On end: `ConversationView.end_streaming(state.conversation_view)`

### Event Priority

Events should be routed with priority:
1. Modals (pick_list, shell_dialog) - capture all input
2. ConversationView - scroll/mouse in content area
3. TextInput - text entry

## Success Criteria

- [ ] ConversationView initialized in TUI.init/1
- [ ] conversation_view state in Model after init
- [ ] Scroll keys (up/down/page_up/page_down/home/end) routed to ConversationView
- [ ] Mouse events in content area routed to ConversationView
- [ ] update handler delegates to ConversationView.handle_event
- [ ] render uses ConversationView.render
- [ ] Streaming chunks synced to ConversationView
- [ ] Resize updates ConversationView dimensions
- [ ] All existing TUI tests still pass

## Test Cases

1. ConversationView initialized in TUI.init/1
2. conversation_view state in Model after init
3. Scroll keys routed to conversation_event (not modal open)
4. Mouse events in content area routed to conversation
5. update handler delegates to ConversationView.handle_event
6. render uses ConversationView.render when conversation_view present
7. Message handlers sync messages to ConversationView
8. Streaming chunks synced to ConversationView
9. Resize updates ConversationView dimensions

## Dependencies

- Section 9.1-9.6 (ConversationView Widget complete)
- TUI module and related handlers
- ViewHelpers module

## Files to Modify

- `lib/jido_code/tui.ex` - Model, init, event_to_msg, update, view
- `lib/jido_code/tui/message_handlers.ex` - Sync messages with ConversationView
- `lib/jido_code/tui/view_helpers.ex` - Update render_conversation
- `test/jido_code/tui_test.exs` - Integration tests

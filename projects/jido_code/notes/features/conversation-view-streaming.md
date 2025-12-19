# Feature: ConversationView Streaming Support (Phase 9.6)

**Status**: COMPLETE
**Branch**: `feature/conversation-view-streaming`
**Created**: 2025-12-03

## Overview

Implement real-time message updates for streaming LLM responses in the ConversationView widget. This enables smooth streaming display with auto-scroll behavior and visual indicators during active streaming.

## Tasks

### 9.6.1 Streaming State Management

Track streaming state for partial message updates.

- [ ] Track `streaming_id` in state (already present from 9.1)
- [ ] Implement `start_streaming/2` - set streaming_id, add placeholder message
- [ ] Implement `end_streaming/1` - clear streaming_id
- [ ] Track `was_at_bottom` to determine auto-scroll behavior
- [ ] Write unit tests for streaming state transitions

### 9.6.2 Chunk Appending

Efficiently append streaming chunks to the active message.

- [ ] Implement `append_chunk/2` function (state, chunk)
- [ ] Find message by streaming_id
- [ ] Append chunk to message content
- [ ] Recalculate line count for modified message only (incremental)
- [ ] Update total_lines incrementally
- [ ] Auto-scroll if was_at_bottom is true
- [ ] Write unit tests for chunk appending

### 9.6.3 Streaming Visual Indicator

Show visual indicator during active streaming.

- [ ] Add cursor indicator `▌` to end of streaming message content during render
- [ ] Style streaming message differently (optional: subtle indicator)
- [ ] Remove cursor indicator when streaming ends
- [ ] Write unit tests for streaming indicator presence

## Implementation Notes

### State Fields (from 9.1)

The state already includes `streaming_id: nil` from section 9.1. We need to add:

```elixir
%{
  ...
  streaming_id: nil,          # ID of message being streamed (already present)
  was_at_bottom: true,        # Track if user was at bottom before streaming
  ...
}
```

### Auto-Scroll Logic

When streaming starts:
1. Check if scroll is at bottom: `scroll_offset >= max_scroll_offset`
2. Store `was_at_bottom: true/false`
3. During chunk appends, if `was_at_bottom`, scroll to keep bottom visible

### Streaming Indicator

During render, if `state.streaming_id == message.id`:
- Append `▌` cursor to the last line of content
- This provides visual feedback that streaming is active

### API Flow

```elixir
# Start streaming
state = ConversationView.start_streaming(state, message_id)

# Append chunks as they arrive
state = ConversationView.append_chunk(state, "Hello ")
state = ConversationView.append_chunk(state, "world!")

# End streaming
state = ConversationView.end_streaming(state)
```

## Success Criteria

- [ ] `start_streaming/2` sets streaming_id and adds placeholder message
- [ ] `end_streaming/1` clears streaming_id
- [ ] `append_chunk/2` appends to correct message
- [ ] `append_chunk/2` updates total_lines
- [ ] Auto-scroll during streaming when at bottom
- [ ] No auto-scroll during streaming when scrolled up
- [ ] Streaming cursor indicator appears during streaming
- [ ] Streaming cursor indicator removed after end

## Test Cases

1. `start_streaming/2` sets streaming_id
2. `start_streaming/2` adds placeholder message with empty content
3. `end_streaming/1` clears streaming_id
4. `append_chunk/2` appends to correct message
5. `append_chunk/2` updates total_lines
6. `append_chunk/2` handles multi-chunk sequences
7. Auto-scroll during streaming when was_at_bottom is true
8. No auto-scroll during streaming when was_at_bottom is false
9. Streaming cursor indicator appears in render during streaming
10. Streaming cursor indicator removed after end_streaming

## Dependencies

- Section 9.1-9.5 (Widget Foundation through Mouse Events)
- Existing `append_to_message/3` function (basis for `append_chunk/2`)

## Files to Modify

- `lib/jido_code/tui/widgets/conversation_view.ex`
- `test/jido_code/tui/widgets/conversation_view_test.exs`

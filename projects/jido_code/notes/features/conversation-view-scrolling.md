# Feature: ConversationView Viewport and Scrolling (Phase 9.3)

**Status**: COMPLETE
**Branch**: `feature/conversation-view-scrolling`
**Created**: 2025-12-03

## Overview

Implement the scrollable viewport with virtual rendering (only render visible lines) and scroll position management for the ConversationView widget. This builds on the foundation from 9.1 and rendering from 9.2.

## Tasks

### 9.3.1 Viewport Calculation

Calculate visible content range based on scroll offset and viewport height.

- [ ] Create `calculate_visible_range/1` function
- [ ] Track cumulative line count per message for fast lookup
- [ ] Determine first visible message based on scroll_offset
- [ ] Determine last visible message based on viewport_height
- [ ] Handle partial message visibility at top/bottom edges
- [ ] Return `{start_msg_idx, start_line_offset, end_msg_idx, end_line_offset}`
- [ ] Write unit tests for viewport calculation

### 9.3.2 Virtual Rendering

Implement the main render callback with virtual scrolling.

- [ ] Update `render/2` callback to use visible range
- [ ] Update viewport dimensions from area on each render
- [ ] Calculate visible message range
- [ ] Render only visible messages (with partial clipping at edges)
- [ ] Combine message renders into vertical stack
- [ ] Add scrollbar to right side (horizontal stack with content)
- [ ] Pad with empty lines if content < viewport height
- [ ] Write unit tests for render output structure

### 9.3.3 Scroll Position Management

Implement scroll offset updates with bounds checking.

- [ ] Ensure `max_scroll_offset/1` is correct: `max(0, total_lines - viewport_height)`
- [ ] Ensure `clamp_scroll/1` enforces valid range
- [ ] Implement scroll adjustment when messages added (auto-scroll if at bottom)
- [ ] Implement scroll adjustment when messages removed
- [ ] Implement scroll adjustment when message expanded/collapsed
- [ ] Preserve relative scroll position on viewport resize
- [ ] Write unit tests for scroll bounds and auto-scroll behavior

### 9.3.4 Scrollbar Rendering

Render visual scrollbar with thumb position indicator.

- [ ] Create `render_scrollbar/2` function (state, height)
- [ ] Calculate thumb size: `max(1, round(height * viewport_height / total_lines))`
- [ ] Calculate thumb position: `round((height - thumb_size) * scroll_fraction)`
- [ ] Render track using `░` character (or configurable)
- [ ] Render thumb using `█` character (or configurable)
- [ ] Add top arrow `▲` and bottom arrow `▼` indicators
- [ ] Style scrollbar with muted colors
- [ ] Write unit tests for scrollbar calculations

## Implementation Notes

### Virtual Rendering Approach

The key optimization is to only render messages that are visible in the viewport. This requires:

1. **Pre-calculate message heights** - Cache the line count for each message
2. **Find visible range** - Binary search or linear scan to find first/last visible message
3. **Partial rendering** - Handle messages that are partially visible at edges
4. **Clip content** - Skip lines that are scrolled out of view

### Scroll Position Calculations

```elixir
# Maximum scroll offset
max_offset = max(0, total_lines - viewport_height)

# Scroll fraction for scrollbar thumb position
scroll_fraction = scroll_offset / max_offset  # 0.0 to 1.0

# Auto-scroll condition
at_bottom? = scroll_offset >= max_offset
```

### Scrollbar Rendering Strategy

```
┌─────────────────────────────┬──┐
│ Message content area        │▲ │  <- Up arrow (optional)
│                             │░ │  <- Track character
│                             │█ │  <- Thumb (filled)
│                             │█ │
│                             │░ │
│                             │▼ │  <- Down arrow (optional)
└─────────────────────────────┴──┘
```

## Success Criteria

- [ ] `calculate_visible_range/1` correctly identifies visible messages
- [ ] `render/2` only renders visible portion of conversation
- [ ] Scrollbar thumb size scales proportionally to content
- [ ] Scrollbar thumb position reflects scroll offset accurately
- [ ] Scroll bounds are enforced (no negative, no exceeding max)
- [ ] Auto-scroll works when at bottom and message added
- [ ] All unit tests pass

## Test Cases

1. Viewport calculation with various scroll offsets
2. Visible range handles empty message list
3. Visible range handles single message
4. Render returns valid render node tree
5. Render updates viewport dimensions from area
6. Render only includes visible messages
7. `max_scroll_offset/1` calculation
8. `clamp_scroll/1` enforces bounds
9. Auto-scroll when at bottom and message added
10. No auto-scroll when scrolled up and message added
11. Scrollbar thumb size scales with content
12. Scrollbar thumb position reflects scroll offset

## Dependencies

- Section 9.1 (Widget Foundation) - COMPLETE
- Section 9.2 (Message Rendering) - COMPLETE
- TermUI.StatefulComponent - for component lifecycle
- TermUI.RenderNode - for render tree building

## Files to Modify

- `lib/jido_code/tui/widgets/conversation_view.ex`
- `test/jido_code/tui/widgets/conversation_view_test.exs`

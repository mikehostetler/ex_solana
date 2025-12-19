# Feature: ConversationView Mouse Event Handling (Phase 9.5)

**Status**: COMPLETE
**Branch**: `feature/conversation-view-mouse`
**Created**: 2025-12-03

## Overview

Implement mouse interactions for the ConversationView widget, including mouse wheel scrolling, scrollbar click handling, scrollbar drag handling, and content click handling.

## Tasks

### 9.5.1 Mouse Wheel Scrolling

Handle mouse wheel events for smooth scrolling.

- [ ] Handle `%Event.Mouse{action: :scroll_up}` - scroll up 3 lines
- [ ] Handle `%Event.Mouse{action: :scroll_down}` - scroll down 3 lines
- [ ] Make scroll amount configurable (default: 3 lines)
- [ ] Apply scroll bounds checking
- [ ] Write unit tests for wheel scrolling

### 9.5.2 Scrollbar Click Handling

Handle clicks on scrollbar for page-based scrolling.

- [ ] Detect click within scrollbar column (x >= width - scrollbar_width)
- [ ] Calculate thumb position and size
- [ ] Click above thumb - page up
- [ ] Click below thumb - page down
- [ ] Click on thumb - start drag (handled in 9.5.3)
- [ ] Write unit tests for click regions

### 9.5.3 Scrollbar Drag Handling

Implement drag-to-scroll on the scrollbar thumb.

- [ ] Add `dragging`, `drag_start_y`, `drag_start_offset` to state
- [ ] Handle `%Event.Mouse{action: :press}` on thumb - start drag
- [ ] Handle `%Event.Mouse{action: :drag}` - calculate new offset proportionally
- [ ] Handle `%Event.Mouse{action: :release}` - end drag
- [ ] Calculate scroll offset: `start_offset + (delta_y / track_height) * max_scroll`
- [ ] Clamp calculated offset to valid range
- [ ] Write unit tests for drag state transitions

### 9.5.4 Content Click Handling

Handle clicks on message content for focus.

- [ ] Detect click within content area (x < width - scrollbar_width)
- [ ] Calculate which message was clicked based on y and scroll_offset
- [ ] Set `cursor_message_idx` to clicked message
- [ ] Detect click on truncation indicator - toggle expand
- [ ] Write unit tests for content click handling

## Implementation Notes

### TermUI Mouse Event Format

```elixir
%TermUI.Event.Mouse{
  action: :click | :press | :release | :drag | :scroll_up | :scroll_down,
  button: :left | :middle | :right | nil,
  x: integer(),
  y: integer(),
  modifiers: []
}
```

### Scrollbar Hit Testing

```
┌─────────────────────────────────────┬──┐
│ Content Area                        │▲ │  <- y = 0 (top arrow, if present)
│ (x < viewport_width - scrollbar_w)  │░ │  <- Track above thumb
│                                     │█ │  <- Thumb (draggable)
│                                     │█ │
│                                     │░ │  <- Track below thumb
│                                     │▼ │  <- y = height-1 (bottom arrow)
└─────────────────────────────────────┴──┘
                                      ^
                                      Scrollbar column (x >= viewport_width - scrollbar_width)
```

### Message Click Calculation

To determine which message was clicked:
1. Get cumulative line info for all messages
2. Add y coordinate to scroll_offset to get absolute line position
3. Find which message contains that line

### State Additions for Drag

```elixir
%{
  ...
  dragging: false,
  drag_start_y: 0,
  drag_start_offset: 0,
  mouse_scroll_lines: 3  # configurable scroll amount
}
```

## Success Criteria

- [ ] Mouse wheel scrolls 3 lines (configurable)
- [ ] Click above/below scrollbar thumb pages up/down
- [ ] Drag on scrollbar thumb scrolls proportionally
- [ ] Click on content area sets message focus
- [ ] All scroll operations respect bounds
- [ ] All unit tests pass

## Test Cases

1. Wheel scroll_up decreases offset by 3
2. Wheel scroll_down increases offset by 3
3. Wheel scroll respects bounds
4. Click above thumb triggers page up
5. Click below thumb triggers page down
6. Click on thumb starts drag state
7. Drag updates scroll offset proportionally
8. Release ends drag state
9. Drag respects scroll bounds
10. Content click sets cursor_message_idx
11. Click on truncation indicator toggles expand

## Dependencies

- Section 9.1-9.4 (Widget Foundation, Rendering, Scrolling, Keyboard)
- TermUI.Event.Mouse - for mouse event structures

## Files to Modify

- `lib/jido_code/tui/widgets/conversation_view.ex`
- `test/jido_code/tui/widgets/conversation_view_test.exs`

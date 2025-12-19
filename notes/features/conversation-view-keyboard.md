# Feature: ConversationView Keyboard Event Handling (Phase 9.4)

**Status**: COMPLETE
**Branch**: `feature/conversation-view-keyboard`
**Created**: 2025-12-03

## Overview

Implement keyboard navigation for the ConversationView widget, including scroll navigation, message focus movement, expand/collapse handling, and copy functionality.

## Tasks

### 9.4.1 Scroll Navigation

Handle keyboard events for scrolling the viewport.

- [ ] Implement `handle_event/2` callback for keyboard events
- [ ] Handle `:up` key - scroll up 1 line
- [ ] Handle `:down` key - scroll down 1 line
- [ ] Handle `:page_up` key - scroll up viewport_height lines
- [ ] Handle `:page_down` key - scroll down viewport_height lines
- [ ] Handle `:home` key - scroll to top (offset = 0)
- [ ] Handle `:end` key - scroll to bottom (offset = max)
- [ ] Return `{:ok, new_state}` after scroll updates
- [ ] Write unit tests for each navigation key

### 9.4.2 Message Focus Navigation

Track focused message for expansion and copy operations.

- [ ] Track `cursor_message_idx` in state (already exists from 9.1)
- [ ] Handle `Ctrl+Up` - move focus to previous message
- [ ] Handle `Ctrl+Down` - move focus to next message
- [ ] Ensure focused message is visible (adjust scroll if needed)
- [ ] Highlight focused message (already implemented in render_message_header)
- [ ] Write unit tests for message focus navigation

### 9.4.3 Expand/Collapse Handling

Handle keyboard events for expanding and collapsing messages.

- [ ] Handle `Space` key - toggle expand on focused message
- [ ] Handle `e` key - expand all truncated messages
- [ ] Handle `c` key - collapse all expanded messages
- [ ] Recalculate `total_lines` after expansion changes
- [ ] Adjust scroll offset to keep focused message visible
- [ ] Write unit tests for expand/collapse behavior

### 9.4.4 Copy Functionality

Handle copy key to invoke clipboard callback.

- [ ] Handle `y` key - copy focused message content
- [ ] Call `on_copy` callback with message content if configured
- [ ] Handle missing `on_copy` gracefully (no-op)
- [ ] Write unit tests for copy triggering

### 9.4.5 Catch-All Handler

Handle unrecognized events gracefully.

- [ ] Implement catch-all `handle_event/2` clause
- [ ] Return `{:ok, state}` unchanged for unhandled events
- [ ] Write unit test for unhandled event passthrough

## Implementation Notes

### TermUI Event Format

TermUI passes events to `handle_event/2` in various formats:
- Simple keys: `:up`, `:down`, `:page_up`, `:page_down`, `:home`, `:end`
- Character keys: `{:key, ?e}`, `{:key, ?c}`, `{:key, ?y}`, `{:key, ?\s}` (space)
- Modified keys: `{:key, :up, [:ctrl]}`, `{:key, :down, [:ctrl]}`

### Scroll Adjustment for Focus

When moving focus with Ctrl+Up/Down, we need to ensure the focused message is visible:

```elixir
# If focused message is above visible range, scroll up
# If focused message is below visible range, scroll down
```

### Key Mappings

| Key | Action |
|-----|--------|
| Up | Scroll up 1 line |
| Down | Scroll down 1 line |
| Page Up | Scroll up viewport_height lines |
| Page Down | Scroll down viewport_height lines |
| Home | Scroll to top |
| End | Scroll to bottom |
| Ctrl+Up | Focus previous message |
| Ctrl+Down | Focus next message |
| Space | Toggle expand focused message |
| e | Expand all messages |
| c | Collapse all messages |
| y | Copy focused message content |

## Success Criteria

- [ ] All scroll navigation keys work correctly
- [ ] Message focus can be moved with Ctrl+Up/Down
- [ ] Focused message stays visible when navigating
- [ ] Space toggles expansion of focused message
- [ ] e/c keys expand/collapse all messages
- [ ] y key triggers on_copy callback
- [ ] Unhandled events pass through unchanged
- [ ] All unit tests pass

## Test Cases

1. :up decreases scroll_offset by 1
2. :down increases scroll_offset by 1
3. :page_up decreases scroll_offset by viewport_height
4. :page_down increases scroll_offset by viewport_height
5. :home sets scroll_offset to 0
6. :end sets scroll_offset to max
7. Scroll respects bounds (no negative, no exceeding max)
8. Ctrl+Up moves cursor_message_idx up
9. Ctrl+Down moves cursor_message_idx down
10. Focus navigation adjusts scroll to keep message visible
11. Space toggles expansion of focused message
12. e expands all messages
13. c collapses all messages
14. Expansion recalculates total_lines
15. y calls on_copy with message content
16. y no-op when on_copy is nil
17. Unhandled events return unchanged state

## Dependencies

- Section 9.1 (Widget Foundation) - COMPLETE
- Section 9.2 (Message Rendering) - COMPLETE
- Section 9.3 (Viewport and Scrolling) - COMPLETE
- TermUI.Event - for event structures

## Files to Modify

- `lib/jido_code/tui/widgets/conversation_view.ex`
- `test/jido_code/tui/widgets/conversation_view_test.exs`

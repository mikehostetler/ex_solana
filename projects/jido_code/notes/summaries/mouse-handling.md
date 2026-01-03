# Mouse Handling Implementation Summary

## Overview

Implemented mouse click handling for the TUI to enable tab switching, tab closing, and sidebar session selection via mouse clicks.

## Changes Made

### 1. Mouse Event Routing (`lib/jido_code/tui.ex`)

Added region-based mouse event routing in `event_to_msg/2`:

- **Sidebar area** (x < sidebar_width when visible): Routes to `{:sidebar_click, x, y}`
- **Tab bar area** (y < 2, x >= tabs_start_x): Routes to `{:tab_click, relative_x, y}`
- **Content area** (all other clicks): Routes to `{:conversation_event, event}` (existing behavior)

```elixir
defp route_mouse_event(%Event.Mouse{x: x, y: y} = event, state) do
  {width, _height} = state.window
  sidebar_proportion = 0.20
  sidebar_width = if state.sidebar_visible, do: round(width * sidebar_proportion), else: 0
  gap_width = if state.sidebar_visible, do: 1, else: 0
  tabs_start_x = sidebar_width + gap_width
  tab_bar_height = 2

  cond do
    state.sidebar_visible and x < sidebar_width ->
      {:msg, {:sidebar_click, x, y}}
    x >= tabs_start_x and y < tab_bar_height ->
      relative_x = x - tabs_start_x
      {:msg, {:tab_click, relative_x, y}}
    true ->
      {:msg, {:conversation_event, event}}
  end
end
```

### 2. Tab Click Handler (`lib/jido_code/tui.ex`)

Added `update({:tab_click, x, y}, state)` handler that:
- Builds a FolderTabs state from the current sessions
- Uses `FolderTabs.handle_click/3` to determine if a tab was clicked or close button
- Switches to the clicked tab or closes it

### 3. Sidebar Click Handler (`lib/jido_code/tui.ex`)

Added `update({:sidebar_click, _x, y}, state)` handler that:
- Calculates which session was clicked based on y position (header is 2 lines)
- Switches to the clicked session if different from current

### 4. Helper Functions (`lib/jido_code/tui.ex`)

Added private helper functions:
- `get_tabs_state/1` - Builds FolderTabs state for click handling
- `truncate_name/2` - Truncates session names for tab labels
- `switch_to_session_by_id/2` - Switches to a session by ID
- `close_session_by_id/2` - Closes a session by ID

### 5. Tests (`test/jido_code/tui_test.exs`)

Updated and added tests:
- Updated `routes mouse events based on click region` test for new routing behavior
- Added `mouse click handling - tab_click` describe block with 2 tests
- Added `mouse click handling - sidebar_click` describe block with 5 tests

## Files Modified

| File | Changes |
|------|---------|
| `lib/jido_code/tui.ex` | Added FolderTabs alias, route_mouse_event/2, update handlers for tab_click and sidebar_click, helper functions |
| `test/jido_code/tui_test.exs` | Updated mouse routing test, added 7 new tests for mouse click handling |

## Mouse Interaction Summary

| Region | Click Action |
|--------|--------------|
| Tab (body) | Switch to that session |
| Tab (× button) | Close that session |
| Sidebar (session row) | Switch to that session |
| Sidebar (header) | No action |
| Content area | Scroll/scrollbar interaction (existing) |

## Test Results

All 289 tests pass, including 7 new mouse click handling tests.

## Notes

- The FolderTabs widget already had `handle_click/3` implemented but wasn't connected to mouse events
- Sidebar click position is calculated based on header height (2 lines) + session index
- ConversationView mouse handling (scroll wheel, scrollbar) continues to work as before

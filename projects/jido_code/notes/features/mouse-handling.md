# Mouse Handling Feature

## Problem Statement

Currently, mouse events are only routed to ConversationView for scrolling and scrollbar interaction. Mouse clicks on tabs (for switching sessions), tab close buttons, and sidebar session items are not handled, requiring users to use keyboard shortcuts exclusively.

## Solution Overview

Wire up mouse click events to:
1. **FolderTabs** - Click to switch tabs, click × to close tabs
2. **Sidebar/Accordion** - Click session to switch to it

The FolderTabs widget already has `handle_click/3` implemented but not connected. We need to:
1. Route mouse events based on click position (tabs area vs conversation area)
2. Connect tab clicks to session switching
3. Connect sidebar clicks to session switching

## Technical Details

### Files to Modify

- `lib/jido_code/tui.ex` - Route mouse events based on position
- `lib/jido_code/tui/widgets/main_layout.ex` - Provide hit-testing for regions

### Current Mouse Routing (line 1405-1410)

```elixir
def event_to_msg(%Event.Mouse{} = event, state) do
  cond do
    state.pick_list -> :ignore
    state.shell_dialog -> :ignore
    true -> {:msg, {:conversation_event, event}}
  end
end
```

### Layout Regions

Based on MainLayout with 20% sidebar:
- Sidebar: x = 0 to sidebar_width
- Tabs: x > sidebar_width, y = 0-1 (2 rows for tab bar)
- Content: x > sidebar_width, y >= 2

## Implementation Plan

### Step 1: Add mouse event types and routing
- [x] Add new message types: `:tab_click`, `:sidebar_click`
- [x] Modify `event_to_msg` to route based on click position
- [x] Calculate region boundaries based on window size and sidebar proportion

### Step 2: Handle tab clicks
- [x] Add `update({:tab_click, x, y}, state)` handler
- [x] Use FolderTabs.handle_click to determine action
- [x] Execute tab switch or close based on result

### Step 3: Handle sidebar clicks
- [x] Add `update({:sidebar_click, x, y}, state)` handler
- [x] Calculate which session was clicked based on y position
- [x] Switch to clicked session

### Step 4: Add tests
- [x] Test mouse event routing to correct regions
- [x] Test tab click switching
- [x] Test close button click
- [x] Test sidebar click switching

## Success Criteria

- [x] Clicking on a tab switches to that session
- [x] Clicking on × closes the tab
- [x] Clicking on a sidebar session item switches to it
- [x] Existing ConversationView mouse handling still works
- [x] All tests pass (289 tests, 0 failures)

## Current Status

- **Phase**: Complete
- **What works**: All mouse click handling for tabs, close buttons, sidebar, and conversation area
- **Tests**: 289 tests pass, 7 new tests added for mouse click handling

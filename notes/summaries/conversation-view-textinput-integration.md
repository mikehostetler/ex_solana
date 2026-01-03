# ConversationView TextInput Integration

## Overview

This feature integrates the TextInput widget directly into ConversationView, eliminating the separate input management at the TUI level. The TextInput and message area now share the same component and coordinate their heights dynamically.

## Changes Made

### ConversationView (`lib/jido_code/tui/widgets/conversation_view.ex`)

- Added TextInput state management:
  - `text_input`: Stores the TextInput widget state
  - `max_input_lines`: Maximum visible input lines before scrolling (default: 5)
  - `input_focused`: Boolean tracking whether input has focus
  - `on_submit`: Callback function invoked when Enter is pressed with non-empty input

- Dynamic height coordination:
  - Input area grows as user types multiple lines
  - Messages area shrinks to accommodate input growth
  - When input is cleared, areas return to original proportions

- New public API functions:
  - `get_input_value/1`: Gets current input text
  - `set_input_value/2`: Sets input text
  - `clear_input/1`: Clears the input
  - `focus_input/1`: Sets focus to input field
  - `input_focused?/1`: Returns whether input is focused
  - `set_on_submit/2`: Updates the on_submit callback

- Event handling for input:
  - Enter key triggers submission when input has text
  - Escape toggles focus between input and messages
  - PageUp/PageDown scroll messages even when input is focused
  - Ctrl+Home/End scroll to top/bottom

### MainLayout (`lib/jido_code/tui/widgets/main_layout.ex`)

- Removed `input_view` parameter from `render/3` and `render_tabs_pane/3`
- Updated comments to reflect that ConversationView handles input internally
- Tab content now fills the space previously split between content and input

### TUI (`lib/jido_code/tui.ex`)

- Removed `text_input` field from `Model.t()` struct
- Removed `text_input` from `session_ui_state` type
- Updated `Model.default_ui_state/1` to create ConversationView with integrated input
- Added `Model.get_active_input_value/1` (replaces `get_active_text_input/1`)
- Updated `update({:input_event, event}, state)` to route to ConversationView
- Updated `update({:input_submitted, value}, state)` to use `ConversationView.clear_input/1`
- Updated `update({:resize, ...}, state)` to only resize ConversationView
- Updated focus cycle handlers to use ConversationView focus management
- Removed `render_input_bar` call from `render_main_view/1`

### ViewHelpers (`lib/jido_code/tui/view_helpers.ex`)

- Removed `render_input_bar/1` function (no longer needed)
- Removed unused `TextInput` alias

## Architecture Benefits

1. **Cohesion**: Input and messages are related to the same session, now managed together
2. **Dynamic Layout**: Input can grow/shrink with messages adjusting automatically
3. **Simpler State**: One less state object to track at the TUI level
4. **Focus Management**: ConversationView handles its own focus internally

## Testing Notes

Some existing TUI tests need updates to work with the new architecture:
- Tests that created `Model` structs with `text_input:` field need updating
- Tests that tested text_input behavior directly need to test via ConversationView
- Core functionality verified with successful compilation and manual testing

## Branch

`feature/conversation-view-textinput-integration`

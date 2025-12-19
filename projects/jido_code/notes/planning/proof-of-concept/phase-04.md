# Phase 4: TUI Application with Elm Architecture

This phase implements the terminal user interface using TermUI's Elm Architecture pattern. The architecture guarantees predictable state management through immutable model updates, message-based event handling, and pure view functions that render the current state.

**Note:** This phase includes creating a new pick-list widget in the term_ui library (`../term_ui`) for provider/model selection.

## 4.1 Core TUI Structure

The TUI application follows TermUI's Elm Architecture with three core functions: `init/1` for initial state, `update/2` for state transitions, and `view/1` for rendering. This pattern ensures all state changes flow through a single update function.

### 4.1.1 Application Module Setup
- [x] **Task 4.1.1 Complete**

Create the main TUI module implementing the TermUI.Elm behaviour.

- [x] 4.1.1.1 Create `JidoCode.TUI` module with `use TermUI.Elm`
- [x] 4.1.1.2 Define `Model` struct with fields: input_buffer, messages, agent_status, config, reasoning_steps
- [x] 4.1.1.3 Implement `init/1` returning initial Model with empty state
- [x] 4.1.1.4 Load settings via `Settings.load/0` and populate config from saved provider/model
- [x] 4.1.1.5 Subscribe to PubSub topic `"tui.events"` in init
- [x] 4.1.1.6 Store window dimensions from init context
- [x] 4.1.1.7 Configure TUI runtime in Application supervisor (documented, not auto-started)
- [x] 4.1.1.8 Verify TUI starts and renders blank screen (success: terminal shows UI)

### 4.1.2 Event Handling
- [x] **Task 4.1.2 Complete**

Implement the event_to_msg callback and update function for user input and agent events.

- [x] 4.1.2.1 Define message types: `:key_input`, `:submit`, `:agent_response`, `:status_update`, `:config_change`
- [x] 4.1.2.2 Implement `event_to_msg/2` mapping keyboard events to messages
- [x] 4.1.2.3 Handle Enter key → `:submit` message
- [x] 4.1.2.4 Handle printable characters → `:key_input` with character
- [x] 4.1.2.5 Handle Backspace → `:key_input` with `:backspace`
- [x] 4.1.2.6 Handle Ctrl+C → `:quit` message
- [x] 4.1.2.7 Implement `update/2` for each message type updating Model
- [x] 4.1.2.8 Write update tests verifying state transitions (success: input buffer updates correctly)

### 4.1.3 PubSub Integration
- [x] **Task 4.1.3 Complete**

Connect TUI to agent events via Phoenix PubSub for real-time updates.

- [x] 4.1.3.1 Subscribe to `"tui.events"` in TUI init
- [x] 4.1.3.2 Handle `{:agent_response, content}` messages in update
- [x] 4.1.3.3 Handle `{:agent_status, status}` for processing/idle indicators
- [x] 4.1.3.4 Handle `{:reasoning_step, step}` for CoT progress display
- [x] 4.1.3.5 Handle `{:config_changed, config}` for model switch notifications
- [x] 4.1.3.6 Implement message queueing for rapid updates
- [x] 4.1.3.7 Write integration test with mock PubSub messages (success: UI updates on events)

## 4.2 View Rendering

The view layer composes TermUI primitives into a multi-pane interface showing the conversation, input area, status bar, and optionally reasoning steps. Views are pure functions of the Model.

### 4.2.1 Main Layout Structure
- [x] **Task 4.2.1 Complete**

Implement the primary view function with three-pane layout: status, conversation, input.

- [x] 4.2.1.1 Implement `view/1` returning composed TermUI elements
- [x] 4.2.1.2 Create status bar at top: model name, provider, status indicator
- [x] 4.2.1.3 Create main conversation area with scrollable message history
- [x] 4.2.1.4 Create input bar at bottom with prompt indicator and input buffer
- [x] 4.2.1.5 Apply TermUI styling: colors for roles (user: cyan, assistant: white)
- [x] 4.2.1.6 Handle terminal resize events updating layout
- [x] 4.2.1.7 Verify layout renders correctly at various terminal sizes (success: no overflow/clipping)

### 4.2.2 Message Display
- [x] **Task 4.2.2 Complete**

Render conversation messages with role indicators and proper text wrapping.

- [x] 4.2.2.1 Create `render_messages/2` helper function
- [x] 4.2.2.2 Display user messages with "You:" prefix in cyan
- [x] 4.2.2.3 Display assistant messages with "Assistant:" prefix
- [x] 4.2.2.4 Implement text wrapping for long messages
- [x] 4.2.2.5 Add timestamp display for each message
- [x] 4.2.2.6 Implement auto-scroll to latest message
- [x] 4.2.2.7 Support scrolling through message history with arrow keys

### 4.2.3 Reasoning Panel
- [x] **Task 4.2.3 Complete**

Optional panel showing Chain-of-Thought reasoning steps during complex queries.

- [x] 4.2.3.1 Create `render_reasoning/1` for reasoning step display
- [x] 4.2.3.2 Show reasoning panel only when steps are present in Model
- [x] 4.2.3.3 Display step list with status indicators (pending/active/complete)
- [x] 4.2.3.4 Highlight currently executing step
- [x] 4.2.3.5 Show confidence score after validation
- [x] 4.2.3.6 Implement toggle keybinding (Ctrl+R) to show/hide reasoning
- [x] 4.2.3.7 Position panel as right sidebar or bottom drawer based on terminal width

### 4.2.4 Status Bar
- [x] **Task 4.2.4 Complete**

Display current configuration and agent status in status bar. Handle unconfigured states since explicit provider configuration is required.

- [x] 4.2.4.1 Create `render_status_bar/1` component
- [x] 4.2.4.2 Display current provider and model: "anthropic:claude-3-5-sonnet"
- [x] 4.2.4.3 Display "No provider configured" (red/warning) when provider is not set
- [x] 4.2.4.4 Display "No model selected" when model is missing from config
- [x] 4.2.4.5 Show agent status: idle (green), processing (yellow), error (red), unconfigured (red/dim)
- [x] 4.2.4.6 Display CoT indicator when reasoning is active
- [x] 4.2.4.7 Add keyboard shortcut hints: "Ctrl+M: Model | Ctrl+R: Reasoning | Ctrl+C: Quit"
- [x] 4.2.4.8 Update status bar reactively on config/status changes

## 4.3 TermUI Pick-List Widget

A new widget for term_ui (`../term_ui`) that displays a scrollable modal overlay for selecting from a list of items. Used for provider and model selection.

### 4.3.1 Pick-List Widget Implementation
- [x] **Task 4.3.1 Complete**

Create the pick-list widget in the term_ui library.

- [x] 4.3.1.1 Create `TermUI.Widget.PickList` module in `../term_ui`
- [x] 4.3.1.2 Render as modal overlay centered on screen with border
- [x] 4.3.1.3 Display scrollable list of items with current selection highlighted
- [x] 4.3.1.4 Support keyboard navigation: Up/Down arrows, Page Up/Down, Home/End
- [x] 4.3.1.5 Support type-ahead filtering: typing filters list to matching items
- [x] 4.3.1.6 Enter key confirms selection and returns selected value
- [x] 4.3.1.7 Escape key cancels and returns nil
- [x] 4.3.1.8 Display item count and current position: "Item 5 of 50"
- [x] 4.3.1.9 Handle empty list state gracefully
- [x] 4.3.1.10 Write widget tests for navigation and selection (success: all interactions work)

**Implementation Notes:**
- PickList widget implemented in term_ui at `lib/term_ui/widget/pick_list.ex`

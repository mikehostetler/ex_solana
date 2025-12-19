# Phase 9: ConversationView Widget

A purpose-built widget for displaying scrollable chat conversations with message-aware rendering, role-based styling, mouse-interactive scrollbar, and collapsible long messages. This widget replaces the current stack-based conversation rendering in the TUI with a proper stateful component following TermUI widget patterns.

**Note:** This widget will be created in `lib/jido_code/tui/widgets/` as it is specific to JidoCode's conversation display needs. It follows the `TermUI.StatefulComponent` behavior pattern used by LogViewer, Viewport, and other TermUI widgets.

---

## 9.1 Widget Foundation

Establish the core widget structure following TermUI's StatefulComponent patterns. This section creates the basic skeleton with props, state initialization, and the behavior implementation.

### 9.1.1 Module Structure and Props
- [x] **Task 9.1.1** ✅ COMPLETED

Create the ConversationView module with props definition and type specifications.

- [x] 9.1.1.1 Create `lib/jido_code/tui/widgets/conversation_view.ex` with module doc
- [x] 9.1.1.2 Add `use TermUI.StatefulComponent` and required imports/aliases
- [x] 9.1.1.3 Define `@type message()` for message structure:
  ```elixir
  @type message :: %{
    id: String.t(),
    role: :user | :assistant | :system,
    content: String.t(),
    timestamp: DateTime.t()
  }
  ```
- [x] 9.1.1.4 Define `@type state()` for internal widget state
- [x] 9.1.1.5 Implement `new/1` function with opts:
  - `messages: [message()]` - initial messages (default: [])
  - `max_collapsed_lines: pos_integer()` - lines before truncation (default: 15)
  - `show_timestamps: boolean()` - show [HH:MM] prefix (default: true)
  - `scrollbar_width: pos_integer()` - scrollbar column width (default: 2)
  - `indent: pos_integer()` - content indent spaces (default: 2)
  - `role_styles: map()` - per-role styling configuration
  - `on_copy: function() | nil` - clipboard callback
- [x] 9.1.1.6 Write unit tests for `new/1` with various option combinations

### 9.1.2 State Initialization
- [x] **Task 9.1.2** ✅ COMPLETED

Implement the init callback to transform props into internal state.

- [x] 9.1.2.1 Implement `init/1` callback returning `{:ok, state}`
- [x] 9.1.2.2 Initialize core state fields:
  ```elixir
  %{
    messages: [],              # All messages in display order
    scroll_offset: 0,          # Lines scrolled from top
    viewport_height: 20,       # Current visible lines
    viewport_width: 80,        # For text wrapping
    expanded: MapSet.new(),    # IDs of expanded messages
    total_lines: 0,            # Cached total content height
    cursor_message_idx: 0,     # Currently focused message
    # Mouse scrollbar state
    dragging: false,
    drag_start_y: nil,
    drag_start_offset: nil,
    # Streaming support
    streaming_id: nil,
    # Config (from props)
    max_collapsed_lines: 15,
    show_timestamps: true,
    scrollbar_width: 2,
    indent: 2,
    role_styles: %{...},
    on_copy: nil
  }
  ```
- [x] 9.1.2.3 Calculate initial `total_lines` from messages
- [x] 9.1.2.4 Write unit tests for `init/1` with empty and populated message lists

### 9.1.3 Public API Functions
- [x] **Task 9.1.3** ✅ COMPLETED

Implement public functions for message management and state access.

- [x] 9.1.3.1 Implement `add_message/2` - append message, recalculate total_lines
- [x] 9.1.3.2 Implement `set_messages/2` - replace all messages, reset scroll state
- [x] 9.1.3.3 Implement `clear/1` - remove all messages, reset state
- [x] 9.1.3.4 Implement `append_to_message/3` - append content to message by ID (streaming)
- [x] 9.1.3.5 Implement `toggle_expand/2` - toggle expanded state for message ID
- [x] 9.1.3.6 Implement `expand_all/1` and `collapse_all/1` - bulk expansion control
- [x] 9.1.3.7 Implement `scroll_to/2` with atoms `:top`, `:bottom`, or `{:message, id}`
- [x] 9.1.3.8 Implement `scroll_by/2` - relative scroll by delta lines
- [x] 9.1.3.9 Implement `get_selected_text/1` - return focused message content for copy
- [x] 9.1.3.10 Write unit tests for each public API function

**Unit Tests for Section 9.1:** ✅ ALL PASSING (64 tests)
- [x] Test `new/1` returns valid props map with defaults
- [x] Test `new/1` with custom options overrides defaults
- [x] Test `init/1` creates valid state from props
- [x] Test `init/1` calculates correct total_lines for messages
- [x] Test `add_message/2` appends and updates total_lines
- [x] Test `set_messages/2` replaces messages and resets scroll
- [x] Test `clear/1` empties messages and resets state
- [x] Test `append_to_message/3` modifies correct message content
- [x] Test `toggle_expand/2` adds/removes from expanded set
- [x] Test `scroll_to/2` with :top, :bottom, {:message, id}
- [x] Test `scroll_by/2` respects bounds (0 to max_scroll)

---

## 9.2 Message Rendering

Implement the core rendering logic for individual messages and the overall conversation view. Messages are rendered as distinct blocks with role headers, wrapped content, and optional truncation.

### 9.2.1 Message Block Layout
- [x] **Task 9.2.1** ✅ COMPLETED

Define the visual structure for rendering individual message blocks.

- [x] 9.2.1.1 Create `render_message/4` private function (state, message, idx, width)
- [x] 9.2.1.2 Render message header: `[HH:MM] Role:` with role-specific styling
- [x] 9.2.1.3 Wrap message content to `(width - scrollbar_width - indent)` characters
- [x] 9.2.1.4 Apply indent (2 spaces) to content lines
- [x] 9.2.1.5 Apply role-based foreground color to content
- [x] 9.2.1.6 Add blank line separator after each message
- [x] 9.2.1.7 Return list of render nodes for the message block
- [x] 9.2.1.8 Write unit tests for message block structure

### 9.2.2 Text Wrapping
- [x] **Task 9.2.2** ✅ COMPLETED

Implement text wrapping logic that respects word boundaries.

- [x] 9.2.2.1 Create `wrap_text/2` function (text, max_width)
- [x] 9.2.2.2 Handle explicit newlines in content (preserve line breaks)
- [x] 9.2.2.3 Wrap at word boundaries when possible
- [x] 9.2.2.4 Force-break very long words that exceed max_width
- [x] 9.2.2.5 Handle empty strings and whitespace-only content
- [x] 9.2.2.6 Write unit tests for wrapping edge cases

### 9.2.3 Message Truncation
- [x] **Task 9.2.3** ✅ COMPLETED

Implement collapsible long messages with expand/collapse functionality.

- [x] 9.2.3.1 Calculate wrapped line count for message content
- [x] 9.2.3.2 If line count > max_collapsed_lines and message not in expanded set:
  - Show first (max_collapsed_lines - 1) lines
  - Add truncation indicator: `┄┄┄ N more lines ┄┄┄`
- [x] 9.2.3.3 Style truncation indicator with muted color
- [x] 9.2.3.4 Track truncation state in render for expand hint display
- [x] 9.2.3.5 Return `{rendered_lines, actual_lines, :truncated | :full}` tuple
- [x] 9.2.3.6 Write unit tests for truncation at various thresholds

### 9.2.4 Role Styling
- [x] **Task 9.2.4** ✅ COMPLETED

Implement role-based visual differentiation.

- [x] 9.2.4.1 Define default role styles:
  ```elixir
  %{
    user: %{name: "You", color: :green},
    assistant: %{name: "Assistant", color: :cyan},
    system: %{name: "System", color: :yellow}
  }
  ```
- [x] 9.2.4.2 Create `role_style/2` function to get style for role
- [x] 9.2.4.3 Create `role_name/2` function to get display name for role
- [x] 9.2.4.4 Apply header styling (bold role name)
- [x] 9.2.4.5 Apply content styling (role color, normal weight)
- [x] 9.2.4.6 Support custom role_styles override from props
- [x] 9.2.4.7 Write unit tests for role styling

**Unit Tests for Section 9.2:** ✅ ALL PASSING (32 new tests, 96 total)
- [x] Test `render_message/4` produces correct node structure
- [x] Test message header includes timestamp when show_timestamps: true
- [x] Test message header excludes timestamp when show_timestamps: false
- [x] Test content lines are indented correctly
- [x] Test `wrap_text/2` respects max_width
- [x] Test `wrap_text/2` preserves explicit newlines
- [x] Test `wrap_text/2` breaks long words
- [x] Test truncation activates at max_collapsed_lines + 1
- [x] Test truncation indicator shows correct line count
- [x] Test expanded messages show full content
- [x] Test role styles apply correct colors
- [x] Test custom role_styles override defaults

---

## 9.3 Viewport and Scrolling

Implement the scrollable viewport with virtual rendering (only render visible lines) and scroll position management.

### 9.3.1 Viewport Calculation
- [x] **Task 9.3.1** ✅ COMPLETED

Calculate visible content range based on scroll offset and viewport height.

- [x] 9.3.1.1 Create `calculate_visible_range/1` function
- [x] 9.3.1.2 Track cumulative line count per message for fast lookup
- [x] 9.3.1.3 Determine first visible message based on scroll_offset
- [x] 9.3.1.4 Determine last visible message based on viewport_height
- [x] 9.3.1.5 Handle partial message visibility at top/bottom edges
- [x] 9.3.1.6 Return `{start_msg_idx, start_line_offset, end_msg_idx, end_line_offset}`
- [x] 9.3.1.7 Write unit tests for viewport calculation

### 9.3.2 Virtual Rendering
- [x] **Task 9.3.2** ✅ COMPLETED

Implement the main render callback with virtual scrolling.

- [x] 9.3.2.1 Implement `render/2` callback receiving state and area
- [x] 9.3.2.2 Update viewport dimensions from area on each render
- [x] 9.3.2.3 Calculate visible message range
- [x] 9.3.2.4 Render only visible messages (with partial clipping at edges)
- [x] 9.3.2.5 Combine message renders into vertical stack
- [x] 9.3.2.6 Add scrollbar to right side (horizontal stack with content)
- [x] 9.3.2.7 Pad with empty lines if content < viewport height
- [x] 9.3.2.8 Write unit tests for render output structure

### 9.3.3 Scroll Position Management
- [x] **Task 9.3.3** ✅ COMPLETED

Implement scroll offset updates with bounds checking.

- [x] 9.3.3.1 Create `max_scroll_offset/1` function: `max(0, total_lines - viewport_height)`
- [x] 9.3.3.2 Create `clamp_scroll/1` to ensure offset in valid range
- [x] 9.3.3.3 Implement scroll adjustment when messages added (auto-scroll if at bottom)
- [x] 9.3.3.4 Implement scroll adjustment when messages removed
- [x] 9.3.3.5 Implement scroll adjustment when message expanded/collapsed
- [x] 9.3.3.6 Preserve relative scroll position on viewport resize
- [x] 9.3.3.7 Write unit tests for scroll bounds and auto-scroll behavior

### 9.3.4 Scrollbar Rendering
- [x] **Task 9.3.4** ✅ COMPLETED

Render visual scrollbar with thumb position indicator.

- [x] 9.3.4.1 Create `render_scrollbar/2` function (state, height)
- [x] 9.3.4.2 Calculate thumb size: `max(1, round(height * viewport_height / total_lines))`
- [x] 9.3.4.3 Calculate thumb position: `round((height - thumb_size) * scroll_fraction)`
- [x] 9.3.4.4 Render track using `░` character (or configurable)
- [x] 9.3.4.5 Render thumb using `█` character (or configurable)
- [x] 9.3.4.6 Add top arrow `▲` and bottom arrow `▼` indicators (skipped - minimal design)
- [x] 9.3.4.7 Style scrollbar with muted colors
- [x] 9.3.4.8 Write unit tests for scrollbar calculations

**Unit Tests for Section 9.3:** ✅ ALL PASSING (25 new tests, 123 total)
- [x] Test `calculate_visible_range/1` with various scroll offsets
- [x] Test visible range handles empty message list
- [x] Test visible range handles single message
- [x] Test `render/2` returns valid render node tree
- [x] Test render updates viewport dimensions from area
- [x] Test render only includes visible messages
- [x] Test `max_scroll_offset/1` calculation
- [x] Test `clamp_scroll/1` enforces bounds
- [x] Test auto-scroll when at bottom and message added
- [x] Test no auto-scroll when scrolled up and message added
- [x] Test scrollbar thumb size scales with content
- [x] Test scrollbar thumb position reflects scroll offset

---

## 9.4 Keyboard Event Handling

Implement keyboard navigation for scrolling, message expansion, and copy functionality.

### 9.4.1 Scroll Navigation
- [x] **Task 9.4.1** ✅ COMPLETED

Handle keyboard events for scrolling the viewport.

- [x] 9.4.1.1 Implement `handle_event/2` callback
- [x] 9.4.1.2 Handle `:up` key - scroll up 1 line
- [x] 9.4.1.3 Handle `:down` key - scroll down 1 line
- [x] 9.4.1.4 Handle `:page_up` key - scroll up viewport_height lines
- [x] 9.4.1.5 Handle `:page_down` key - scroll down viewport_height lines
- [x] 9.4.1.6 Handle `:home` key - scroll to top (offset = 0)
- [x] 9.4.1.7 Handle `:end` key - scroll to bottom (offset = max)
- [x] 9.4.1.8 Return `{:ok, new_state}` after scroll updates
- [x] 9.4.1.9 Write unit tests for each navigation key

### 9.4.2 Message Focus Navigation
- [x] **Task 9.4.2** ✅ COMPLETED

Track focused message for expansion and copy operations.

- [x] 9.4.2.1 Track `cursor_message_idx` in state (already from 9.1)
- [x] 9.4.2.2 Handle `Ctrl+Up` - move focus to previous message
- [x] 9.4.2.3 Handle `Ctrl+Down` - move focus to next message
- [x] 9.4.2.4 Ensure focused message is visible (adjust scroll if needed)
- [x] 9.4.2.5 Highlight focused message with subtle background or indicator (already in render)
- [x] 9.4.2.6 Write unit tests for message focus navigation

### 9.4.3 Expand/Collapse Handling
- [x] **Task 9.4.3** ✅ COMPLETED

Handle keyboard events for expanding and collapsing messages.

- [x] 9.4.3.1 Handle `Space` key - toggle expand on focused message
- [x] 9.4.3.2 Handle `e` key - expand all truncated messages
- [x] 9.4.3.3 Handle `c` key - collapse all expanded messages
- [x] 9.4.3.4 Recalculate `total_lines` after expansion changes
- [x] 9.4.3.5 Adjust scroll offset to keep focused message visible
- [x] 9.4.3.6 Write unit tests for expand/collapse behavior

### 9.4.4 Copy Functionality
- [x] **Task 9.4.4** ✅ COMPLETED

Handle copy key to invoke clipboard callback.

- [x] 9.4.4.1 Handle `y` key - copy focused message content
- [x] 9.4.4.2 Call `on_copy` callback with message content if configured
- [x] 9.4.4.3 Flash visual feedback on copy (optional: skipped for simplicity)
- [x] 9.4.4.4 Handle missing `on_copy` gracefully (no-op)
- [x] 9.4.4.5 Write unit tests for copy triggering

### 9.4.5 Catch-All Handler
- [x] **Task 9.4.5** ✅ COMPLETED

Handle unrecognized events gracefully.

- [x] 9.4.5.1 Implement catch-all `handle_event/2` clause
- [x] 9.4.5.2 Return `{:ok, state}` unchanged for unhandled events
- [x] 9.4.5.3 Write unit test for unhandled event passthrough

**Unit Tests for Section 9.4:** ✅ ALL PASSING (30 new tests, 153 total)
- [x] Test `:up` decreases scroll_offset by 1
- [x] Test `:down` increases scroll_offset by 1
- [x] Test `:page_up` decreases scroll_offset by viewport_height
- [x] Test `:page_down` increases scroll_offset by viewport_height
- [x] Test `:home` sets scroll_offset to 0
- [x] Test `:end` sets scroll_offset to max
- [x] Test scroll respects bounds (no negative, no exceeding max)
- [x] Test `Ctrl+Up` moves cursor_message_idx up
- [x] Test `Ctrl+Down` moves cursor_message_idx down
- [x] Test focus navigation adjusts scroll to keep message visible
- [x] Test `Space` toggles expansion of focused message
- [x] Test `e` expands all messages
- [x] Test `c` collapses all messages
- [x] Test expansion recalculates total_lines
- [x] Test `y` calls on_copy with message content
- [x] Test `y` no-op when on_copy is nil
- [x] Test unhandled events return unchanged state

---

## 9.5 Mouse Event Handling

Implement mouse interactions for scrollbar dragging, click-to-scroll, and wheel scrolling.

### 9.5.1 Mouse Wheel Scrolling
- [x] **Task 9.5.1** ✅ COMPLETED

Handle mouse wheel events for smooth scrolling.

- [x] 9.5.1.1 Handle `%Event.Mouse{action: :scroll_up}` - scroll up by scroll_lines
- [x] 9.5.1.2 Handle `%Event.Mouse{action: :scroll_down}` - scroll down by scroll_lines
- [x] 9.5.1.3 Make scroll amount configurable (default: 3 lines via scroll_lines prop)
- [x] 9.5.1.4 Apply scroll bounds checking
- [x] 9.5.1.5 Write unit tests for wheel scrolling

### 9.5.2 Scrollbar Click Handling
- [x] **Task 9.5.2** ✅ COMPLETED

Handle clicks on scrollbar for page-based scrolling.

- [x] 9.5.2.1 Detect click within scrollbar column (x >= width - scrollbar_width)
- [x] 9.5.2.2 Calculate thumb position and size
- [x] 9.5.2.3 Click above thumb - page up
- [x] 9.5.2.4 Click below thumb - page down
- [x] 9.5.2.5 Click on thumb - no action (drag handled by press)
- [x] 9.5.2.6 Write unit tests for click regions

### 9.5.3 Scrollbar Drag Handling
- [x] **Task 9.5.3** ✅ COMPLETED

Implement drag-to-scroll on the scrollbar thumb.

- [x] 9.5.3.1 Handle `%Event.Mouse{action: :press}` on thumb - start drag
- [x] 9.5.3.2 Set `dragging: true`, record `drag_start_y` and `drag_start_offset`
- [x] 9.5.3.3 Handle `%Event.Mouse{action: :drag}` - calculate new offset proportionally
- [x] 9.5.3.4 Handle `%Event.Mouse{action: :release}` - end drag, set `dragging: false`
- [x] 9.5.3.5 Calculate scroll offset: `start_offset + (delta_y / track_height) * max_scroll`
- [x] 9.5.3.6 Clamp calculated offset to valid range
- [x] 9.5.3.7 Write unit tests for drag state transitions

### 9.5.4 Content Click Handling
- [x] **Task 9.5.4** ✅ COMPLETED

Handle clicks on message content for focus.

- [x] 9.5.4.1 Detect click within content area (x < width - scrollbar_width)
- [x] 9.5.4.2 Calculate which message was clicked based on y and scroll_offset
- [x] 9.5.4.3 Set `cursor_message_idx` to clicked message
- [x] 9.5.4.4 Detect click on truncation indicator (skipped - simpler focus-only behavior)
- [x] 9.5.4.5 Write unit tests for content click handling

**Unit Tests for Section 9.5:** ✅ ALL PASSING (16 new tests, 169 total)
- [x] Test wheel scroll_up decreases offset by scroll_lines
- [x] Test wheel scroll_down increases offset by scroll_lines
- [x] Test wheel scroll respects bounds (upper and lower)
- [x] Test scroll_lines is configurable
- [x] Test click above thumb triggers page up
- [x] Test click below thumb triggers page down
- [x] Test press on thumb starts drag state
- [x] Test drag updates scroll offset proportionally
- [x] Test release ends drag state
- [x] Test drag respects scroll bounds
- [x] Test content click sets cursor_message_idx
- [x] Test content click with scroll offset
- [x] Test content click on empty messages is no-op
- [x] Test drag without dragging state is ignored
- [x] Test release without dragging state is ignored

---

## 9.6 Streaming Support

Implement real-time message updates for streaming LLM responses.

### 9.6.1 Streaming State Management
- [x] **Task 9.6.1** ✅ COMPLETED

Track streaming state for partial message updates.

- [x] 9.6.1.1 Track `streaming_id` in state (message currently being streamed)
- [x] 9.6.1.2 Implement `start_streaming/2` - set streaming_id, add placeholder message
- [x] 9.6.1.3 Implement `end_streaming/1` - clear streaming_id
- [x] 9.6.1.4 Track `was_at_bottom` to determine auto-scroll behavior
- [x] 9.6.1.5 Write unit tests for streaming state transitions

### 9.6.2 Chunk Appending
- [x] **Task 9.6.2** ✅ COMPLETED

Efficiently append streaming chunks to the active message.

- [x] 9.6.2.1 Implement `append_chunk/2` function (state, chunk)
- [x] 9.6.2.2 Find message by streaming_id
- [x] 9.6.2.3 Append chunk to message content
- [x] 9.6.2.4 Recalculate line count for modified message only (incremental)
- [x] 9.6.2.5 Update total_lines incrementally
- [x] 9.6.2.6 Auto-scroll if was_at_bottom is true
- [x] 9.6.2.7 Write unit tests for chunk appending

### 9.6.3 Streaming Visual Indicator
- [x] **Task 9.6.3** ✅ COMPLETED

Show visual indicator during active streaming.

- [x] 9.6.3.1 Add cursor indicator `▌` to end of streaming message content
- [x] 9.6.3.2 Style streaming message differently (optional: pulsing or italic - skipped, cursor is sufficient)
- [x] 9.6.3.3 Remove cursor indicator when streaming ends
- [x] 9.6.3.4 Write unit tests for streaming indicator presence

**Unit Tests for Section 9.6:** ✅ ALL PASSING (9 tests total, 173 total in file)
- [x] Test `start_streaming/2` sets streaming_id
- [x] Test `start_streaming/2` adds placeholder message
- [x] Test `end_streaming/1` clears streaming_id
- [x] Test `append_chunk/2` appends to correct message
- [x] Test `append_chunk/2` updates total_lines
- [x] Test auto-scroll during streaming when at bottom
- [x] Test no auto-scroll during streaming when scrolled up
- [x] Test streaming cursor indicator appears during streaming
- [x] Test streaming cursor indicator removed after end

---

## 9.7 TUI Integration

Integrate the ConversationView widget into the JidoCode TUI, replacing the current stack-based conversation rendering.

### 9.7.1 Model Integration
- [x] **Task 9.7.1** ✅ COMPLETED

Add ConversationView state to the TUI Model.

- [x] 9.7.1.1 Add `conversation_view: map() | nil` to Model struct type
- [x] 9.7.1.2 Add `conversation_view: nil` to Model defstruct defaults
- [x] 9.7.1.3 Import/alias ConversationView in TUI module
- [x] 9.7.1.4 Initialize ConversationView in `init/1` with props from Model
- [x] 9.7.1.5 Pass initial messages (empty) and dimensions
- [x] 9.7.1.6 Write integration tests for model initialization

### 9.7.2 Event Routing
- [x] **Task 9.7.2** ✅ COMPLETED

Route appropriate events to ConversationView.

- [x] 9.7.2.1 Update `event_to_msg/2` to check for ConversationView priority
- [x] 9.7.2.2 Route scroll keys (up/down/page_up/page_down/home/end) to conversation
- [x] 9.7.2.3 Route mouse events to conversation when in content area
- [x] 9.7.2.4 Add `{:conversation_event, event}` message type
- [x] 9.7.2.5 Implement `update/2` handler for `{:conversation_event, event}`
- [x] 9.7.2.6 Delegate to `ConversationView.handle_event/2`
- [x] 9.7.2.7 Write integration tests for event routing

### 9.7.3 View Rendering Integration
- [x] **Task 9.7.3** ✅ COMPLETED

Replace render_conversation with ConversationView rendering.

- [x] 9.7.3.1 Update `render_main_view/1` to use ConversationView
- [x] 9.7.3.2 Calculate content area dimensions (width, available_height)
- [x] 9.7.3.3 Call `ConversationView.render(state.conversation_view, area)`
- [x] 9.7.3.4 Remove or deprecate `ViewHelpers.render_conversation/1` (kept as fallback)
- [x] 9.7.3.5 Handle nil conversation_view with fallback (optional)
- [x] 9.7.3.6 Write integration tests for view rendering

### 9.7.4 Message Handler Integration
- [x] **Task 9.7.4** ✅ COMPLETED

Update MessageHandlers to sync messages with ConversationView.

- [x] 9.7.4.1 Update `handle_agent_response/2` to call `ConversationView.add_message/2` (via streaming)
- [x] 9.7.4.2 Update `handle_stream_chunk/2` to call `ConversationView.append_chunk/2`
- [x] 9.7.4.3 Update `handle_stream_end/2` to call `ConversationView.end_streaming/1`
- [x] 9.7.4.4 Update `handle_stream_error/2` to add error message to ConversationView
- [x] 9.7.4.5 Update command handlers to add system messages to ConversationView
- [x] 9.7.4.6 Write integration tests for message sync

### 9.7.5 Resize Handling
- [x] **Task 9.7.5** ✅ COMPLETED

Handle terminal resize events for ConversationView.

- [x] 9.7.5.1 Update `update({:resize, width, height}, state)` handler
- [x] 9.7.5.2 Recalculate content area dimensions
- [x] 9.7.5.3 Update ConversationView viewport dimensions (added set_viewport_size/3)
- [x] 9.7.5.4 Preserve scroll position relative to content
- [x] 9.7.5.5 Write integration tests for resize handling

**Unit Tests for Section 9.7:** ✅ Tests updated for new architecture
- [x] Test ConversationView initialized in TUI.init/1
- [x] Test conversation_view state in Model after init
- [x] Test scroll keys routed to conversation_event
- [x] Test mouse events in content area routed to conversation
- [x] Test update handler delegates to ConversationView.handle_event
- [x] Test render uses ConversationView.render
- [x] Test message handlers sync messages to ConversationView
- [x] Test streaming chunks synced to ConversationView
- [x] Test resize updates ConversationView dimensions

---

## 9.8 Clipboard Integration

Implement system clipboard integration for copy functionality.

### 9.8.1 Clipboard Detection
- [x] **Task 9.8.1** ✅ COMPLETED

Detect available clipboard command based on platform.

- [x] 9.8.1.1 Create `lib/jido_code/tui/clipboard.ex` module
- [x] 9.8.1.2 Implement `detect_clipboard_command/0`
- [x] 9.8.1.3 Check for `pbcopy` (macOS)
- [x] 9.8.1.4 Check for `xclip` (Linux X11)
- [x] 9.8.1.5 Check for `xsel` (Linux X11 alternative)
- [x] 9.8.1.6 Check for `wl-copy` (Linux Wayland)
- [x] 9.8.1.7 Check for `clip.exe` (WSL/Windows)
- [x] 9.8.1.8 Return `nil` if no clipboard available
- [x] 9.8.1.9 Write unit tests for clipboard detection

### 9.8.2 Copy Implementation
- [x] **Task 9.8.2** ✅ COMPLETED

Implement cross-platform copy to clipboard.

- [x] 9.8.2.1 Implement `copy_to_clipboard/1` function
- [x] 9.8.2.2 Use detected clipboard command
- [x] 9.8.2.3 Pipe text content to clipboard command via stdin
- [x] 9.8.2.4 Handle command execution errors gracefully
- [x] 9.8.2.5 Log warning if no clipboard available
- [x] 9.8.2.6 Return `:ok` or `{:error, reason}`
- [x] 9.8.2.7 Write unit tests (mocked command execution)

### 9.8.3 ConversationView Callback
- [x] **Task 9.8.3** ✅ COMPLETED

Wire clipboard to ConversationView on_copy callback.

- [x] 9.8.3.1 Pass `on_copy: &Clipboard.copy_to_clipboard/1` in ConversationView init
- [x] 9.8.3.2 Ensure callback receives message content string
- [x] 9.8.3.3 Write integration test for copy flow

**Unit Tests for Section 9.8:** ✅ ALL PASSING (14 tests)
- [x] Test `detect_clipboard_command/0` finds available command
- [x] Test `detect_clipboard_command/0` returns nil when none available
- [x] Test `detect_clipboard_command/0` caches the detected command
- [x] Test `available?/0` returns boolean
- [x] Test `copy_to_clipboard/1` executes clipboard command
- [x] Test `copy_to_clipboard/1` handles command failure
- [x] Test `copy_to_clipboard/1` logs warning when unavailable
- [x] Test `copy_to_clipboard/1` handles empty string
- [x] Test `copy_to_clipboard/1` handles multiline text
- [x] Test `copy_to_clipboard/1` handles unicode text
- [x] Test `clear_cache/0` clears the cached command
- [x] Test on_copy callback wired in ConversationView init

---

## Success Criteria

1. **Widget Structure**: ConversationView follows TermUI.StatefulComponent pattern with new/1, init/1, handle_event/2, render/2
2. **Message Rendering**: Messages display with role headers, timestamps, proper indentation, and role-based colors
3. **Text Wrapping**: Long lines wrap at word boundaries within viewport width
4. **Truncation**: Messages exceeding max_collapsed_lines show truncation indicator with expand option
5. **Keyboard Scrolling**: Up/Down/PageUp/PageDown/Home/End navigate the conversation
6. **Mouse Scrolling**: Wheel scroll and scrollbar drag work correctly
7. **Scrollbar Visual**: Scrollbar shows thumb position proportional to scroll offset
8. **Streaming Support**: Real-time message updates during LLM streaming with auto-scroll
9. **Copy Functionality**: 'y' key copies focused message to system clipboard
10. **TUI Integration**: ConversationView replaces stack-based rendering seamlessly
11. **Resize Handling**: Widget adapts to terminal resize maintaining scroll position
12. **Test Coverage**: Minimum 80% code coverage for new widget code

---

## Integration Test Suite

Comprehensive integration tests validating end-to-end functionality.

**Status:** ✅ ALL PASSING (31 tests in `conversation_view_integration_test.exs`)

### Conversation Display Flow
- [x] Test empty conversation shows placeholder or empty state
- [x] Test single message displays with correct formatting
- [x] Test multiple messages display in correct order
- [x] Test user/assistant/system messages have distinct styling
- [x] Test long conversation scrolls correctly

### Scrolling Integration
- [x] Test keyboard scroll updates view correctly
- [x] Test mouse wheel scroll updates view correctly
- [x] Test scrollbar drag updates view correctly
- [x] Test scroll bounds enforced at top and bottom
- [x] Test auto-scroll when new message at bottom

### Message Truncation Integration
- [x] Test long message shows truncation indicator
- [x] Test Space key expands truncated message
- [x] Test expanded message shows full content
- [x] Test scroll adjusts after expansion

### Streaming Integration
- [x] Test streaming message appears immediately
- [x] Test streaming chunks append correctly
- [x] Test streaming cursor indicator visible
- [x] Test auto-scroll during streaming
- [x] Test message finalizes on stream end

### Clipboard Integration
- [x] Test 'y' key triggers copy callback
- [x] Test copied content matches focused message
- [x] Test copy works with multiline messages

### Resize Integration
- [x] Test widget adapts to terminal width change
- [x] Test widget adapts to terminal height change
- [x] Test scroll position preserved on resize
- [x] Test text rewrapping on width change

### TUI Lifecycle Integration
- [x] Test ConversationView initializes with TUI
- [x] Test messages sync between TUI Model and ConversationView
- [x] Test event routing returns :ok tuple for handled events
- [x] Test render returns valid render node

---

## Critical Files

**New Files:**
- `lib/jido_code/tui/widgets/conversation_view.ex` - Main widget module
- `lib/jido_code/tui/clipboard.ex` - Clipboard integration
- `test/jido_code/tui/widgets/conversation_view_test.exs` - Widget unit tests
- `test/jido_code/tui/clipboard_test.exs` - Clipboard unit tests

**Modified Files:**
- `lib/jido_code/tui.ex` - Model struct, init, event routing, view rendering
- `lib/jido_code/tui/view_helpers.ex` - Remove/deprecate render_conversation
- `lib/jido_code/tui/message_handlers.ex` - Sync messages to ConversationView
- `test/jido_code/tui_test.exs` - Update integration tests

---

## Implementation Order

1. **Section 9.1** - Widget Foundation (props, state, public API)
2. **Section 9.2** - Message Rendering (blocks, wrapping, truncation)
3. **Section 9.3** - Viewport and Scrolling (virtual render, scrollbar)
4. **Section 9.4** - Keyboard Event Handling
5. **Section 9.5** - Mouse Event Handling
6. **Section 9.6** - Streaming Support
7. **Section 9.8** - Clipboard Integration
8. **Section 9.7** - TUI Integration (last, depends on all above)

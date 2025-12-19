# Phase 4: TUI Tab Integration

This phase integrates the TermUI Tabs widget into the JidoCode TUI, enabling users to view and switch between multiple sessions. Each tab displays a session's conversation with Ctrl+1 through Ctrl+0 keyboard shortcuts for navigation.

---

## 4.1 Model Structure Updates

Update the TUI Model to support multiple sessions with tab-based navigation.

### 4.1.1 Model Struct Changes
- [ ] **Task 4.1.1**

Restructure the Model to support multiple sessions.

- [ ] 4.1.1.1 Add session tracking fields to Model struct:
  ```elixir
  defstruct [
    # Session management
    sessions: %{},           # session_id => Session.t()
    session_order: [],       # List of session_ids in tab order
    active_session_id: nil,  # Currently focused session

    # Existing shared fields
    window: {80, 24},
    text_input: nil,
    show_reasoning: false,
    focus: :input,           # :tabs | :conversation | :input
    agent_status: :idle,

    # Modals (shared across sessions)
    shell_dialog: nil,
    pick_list: nil,

    # Remove per-session fields from Model (now in Session.State)
    # messages: [],          # REMOVED
    # reasoning_steps: [],   # REMOVED
    # tool_calls: [],        # REMOVED
    # streaming_message: nil # REMOVED
  ]
  ```
- [ ] 4.1.1.2 Update `@type model()` typespec
- [ ] 4.1.1.3 Add `@type focus()` for focus states
- [ ] 4.1.1.4 Write unit tests for model structure

### 4.1.2 Session State Access
- [ ] **Task 4.1.2**

Add helper functions for accessing active session state.

- [ ] 4.1.2.1 Implement `get_active_session/1`:
  ```elixir
  def get_active_session(model) do
    case model.active_session_id do
      nil -> nil
      id -> Map.get(model.sessions, id)
    end
  end
  ```
- [ ] 4.1.2.2 Implement `get_active_session_state/1` fetching from Session.State:
  ```elixir
  def get_active_session_state(model) do
    case model.active_session_id do
      nil -> nil
      id -> Session.State.get_state(id)
    end
  end
  ```
- [ ] 4.1.2.3 Implement `get_session_by_index/2` for tab number lookup
- [ ] 4.1.2.4 Write unit tests for session access helpers

### 4.1.3 Session Order Management
- [ ] **Task 4.1.3**

Implement functions for managing session tab order.

- [ ] 4.1.3.1 Implement `add_session_to_tabs/2`:
  ```elixir
  def add_session_to_tabs(model, session) do
    %{model |
      sessions: Map.put(model.sessions, session.id, session),
      session_order: model.session_order ++ [session.id],
      active_session_id: model.active_session_id || session.id
    }
  end
  ```
- [ ] 4.1.3.2 Implement `remove_session_from_tabs/2`
- [ ] 4.1.3.3 Handle active session removal (switch to adjacent tab)
- [ ] 4.1.3.4 Implement `reorder_sessions/2` for drag-drop (future)
- [ ] 4.1.3.5 Write unit tests for tab management

**Unit Tests for Section 4.1:**
- Test Model struct has session tracking fields
- Test `get_active_session/1` returns current session
- Test `get_active_session_state/1` fetches from Session.State
- Test `add_session_to_tabs/2` adds session correctly
- Test `add_session_to_tabs/2` sets active if first session
- Test `remove_session_from_tabs/2` removes session
- Test removing active session switches to adjacent tab

---

## 4.2 Init and PubSub Updates

Update initialization and PubSub subscriptions for multi-session.

### 4.2.1 Init Updates
- [ ] **Task 4.2.1**

Update `init/1` for multi-session model.

- [ ] 4.2.1.1 Load existing sessions from SessionRegistry:
  ```elixir
  def init(_opts) do
    sessions = load_sessions_from_registry()
    session_order = Enum.map(sessions, & &1.id)
    active_id = List.first(session_order)

    subscribe_to_all_sessions(sessions)

    %Model{
      sessions: Map.new(sessions, &{&1.id, &1}),
      session_order: session_order,
      active_session_id: active_id,
      # ... other fields
    }
  end
  ```
- [ ] 4.2.1.2 Subscribe to PubSub topics for all sessions
- [ ] 4.2.1.3 Handle case with no sessions (show welcome screen)
- [ ] 4.2.1.4 Write unit tests for init

### 4.2.2 PubSub Subscription Management
- [ ] **Task 4.2.2**

Implement dynamic PubSub subscription for sessions.

- [ ] 4.2.2.1 Implement `subscribe_to_session/1`:
  ```elixir
  defp subscribe_to_session(session_id) do
    topic = PubSubTopics.llm_stream(session_id)
    Phoenix.PubSub.subscribe(JidoCode.PubSub, topic)
  end
  ```
- [ ] 4.2.2.2 Implement `unsubscribe_from_session/1`
- [ ] 4.2.2.3 Subscribe when session added
- [ ] 4.2.2.4 Unsubscribe when session removed
- [ ] 4.2.2.5 Write unit tests for subscription management

### 4.2.3 Message Routing
- [ ] **Task 4.2.3**

Update message routing to identify source session.

- [ ] 4.2.3.1 Update PubSub message format to include session_id:
  ```elixir
  # Messages now include session_id
  {:stream_chunk, session_id, chunk}
  {:stream_end, session_id, content}
  {:tool_call, session_id, name, args, id}
  ```
- [ ] 4.2.3.2 Update `update/2` handlers to extract session_id
- [ ] 4.2.3.3 Route messages to correct Session.State
- [ ] 4.2.3.4 Write unit tests for message routing

**Unit Tests for Section 4.2:**
- Test init loads sessions from registry
- Test init subscribes to all session topics
- Test `subscribe_to_session/1` subscribes to correct topic
- Test `unsubscribe_from_session/1` unsubscribes
- Test messages routed to correct session

---

## 4.3 Tab Rendering

Implement tab bar rendering using TermUI Tabs widget.

### 4.3.1 Tab Bar Component
- [ ] **Task 4.3.1**

Create tab bar rendering function.

- [ ] 4.3.1.1 Create `render_tabs/1` function:
  ```elixir
  defp render_tabs(model) do
    tabs = Enum.with_index(model.session_order, 1)
    |> Enum.map(fn {session_id, index} ->
      session = model.sessions[session_id]
      label = format_tab_label(session, index)
      %{id: session_id, label: label, closeable: true}
    end)

    TermUI.Widgets.Tabs.new(
      tabs: tabs,
      selected: model.active_session_id,
      on_select: &{:select_session, &1},
      on_close: &{:close_session, &1}
    )
  end
  ```
- [ ] 4.3.1.2 Implement `format_tab_label/2` showing index and name:
  ```elixir
  defp format_tab_label(session, index) do
    "#{index}:#{truncate(session.name, 15)}"
  end
  ```
- [ ] 4.3.1.3 Show asterisk for modified/unsaved sessions (future)
- [ ] 4.3.1.4 Style active tab differently
- [ ] 4.3.1.5 Write unit tests for tab rendering

### 4.3.2 Tab Indicator for 10th Session
- [ ] **Task 4.3.2**

Handle tab 10 with special "0" indicator.

- [ ] 4.3.2.1 Tab indices 1-9 show as "1:" through "9:"
- [ ] 4.3.2.2 Tab index 10 shows as "0:" (Ctrl+0 shortcut)
- [ ] 4.3.2.3 Update `format_tab_label/2` accordingly
- [ ] 4.3.2.4 Write unit tests for 10th tab labeling

### 4.3.3 Tab Status Indicators
- [ ] **Task 4.3.3**

Add status indicators to tabs.

- [ ] 4.3.3.1 Show spinner/indicator when session is processing
- [ ] 4.3.3.2 Show error indicator on agent error
- [ ] 4.3.3.3 Query agent status via Session.AgentAPI.get_status/1
- [ ] 4.3.3.4 Write unit tests for status indicators

**Unit Tests for Section 4.3:**
- Test `render_tabs/1` creates tab elements
- Test tab labels include index and name
- Test 10th tab shows "0:" prefix
- Test active tab is selected
- Test closeable tabs have close button
- Test processing indicator appears when busy

---

## 4.4 View Integration

Update the main view to include tabs and session-specific content.

### 4.4.1 View Structure
- [ ] **Task 4.4.1**

Update `view/1` to include tab bar.

- [ ] 4.4.1.1 Update `view/1` structure:
  ```elixir
  def view(model) do
    stack(:vertical, [
      render_tabs(model),
      render_main_content(model),
      render_status_bar(model)
    ])
  end
  ```
- [ ] 4.4.1.2 Conditional rendering based on active session
- [ ] 4.4.1.3 Show welcome screen when no sessions
- [ ] 4.4.1.4 Write unit tests for view structure

### 4.4.2 Session Content Rendering
- [ ] **Task 4.4.2**

Render active session's conversation and input.

- [ ] 4.4.2.1 Implement `render_main_content/1`:
  ```elixir
  defp render_main_content(model) do
    case model.active_session_id do
      nil -> render_welcome_screen()
      session_id -> render_session_content(model, session_id)
    end
  end
  ```
- [ ] 4.4.2.2 Implement `render_session_content/2`:
  ```elixir
  defp render_session_content(model, session_id) do
    session_state = Session.State.get_state(session_id)
    stack(:vertical, [
      render_conversation(session_state, model.window),
      render_input(model.text_input, model.focus)
    ])
  end
  ```
- [ ] 4.4.2.3 Pass session state to ConversationView widget
- [ ] 4.4.2.4 Write unit tests for content rendering

### 4.4.3 Welcome Screen
- [ ] **Task 4.4.3**

Create welcome screen for empty session list.

- [ ] 4.4.3.1 Implement `render_welcome_screen/0`:
  ```elixir
  defp render_welcome_screen do
    box([
      text("Welcome to JidoCode", style: :bold),
      text(""),
      text("Press Ctrl+N to create a new session"),
      text("Or use /session new <path> to open a project")
    ], align: :center)
  end
  ```
- [ ] 4.4.3.2 Style welcome screen appropriately
- [ ] 4.4.3.3 Write unit tests for welcome screen

### 4.4.4 Status Bar Updates
- [ ] **Task 4.4.4**

Update status bar to show active session info.

- [ ] 4.4.4.1 Update `render_status_bar/1` to show session name
- [ ] 4.4.4.2 Show session's project path (truncated)
- [ ] 4.4.4.3 Show session's LLM model
- [ ] 4.4.4.4 Format: `[1/3] project-name | anthropic:claude-3-5-sonnet | idle`
- [ ] 4.4.4.5 Write unit tests for status bar

**Unit Tests for Section 4.4:**
- Test view includes tab bar
- Test view shows welcome screen when no sessions
- Test view shows session content when active
- Test conversation renders from Session.State
- Test status bar shows session info
- Test status bar shows session count

---

## 4.5 Keyboard Navigation

Implement keyboard shortcuts for tab navigation.

### 4.5.1 Tab Switching Shortcuts
- [ ] **Task 4.5.1**

Implement Ctrl+1 through Ctrl+0 for tab switching.

- [ ] 4.5.1.1 Update `event_to_msg/2` for Ctrl+digit keys:
  ```elixir
  def event_to_msg(%Event.Key{key: {:ctrl, ?1}}, _state) do
    {:switch_to_tab, 1}
  end
  # ... Ctrl+2 through Ctrl+9
  def event_to_msg(%Event.Key{key: {:ctrl, ?0}}, _state) do
    {:switch_to_tab, 10}
  end
  ```
- [ ] 4.5.1.2 Implement `update({:switch_to_tab, index}, model)`:
  ```elixir
  def update({:switch_to_tab, index}, model) do
    case Enum.at(model.session_order, index - 1) do
      nil -> model
      session_id -> %{model | active_session_id: session_id}
    end
  end
  ```
- [ ] 4.5.1.3 Handle out-of-range indices gracefully
- [ ] 4.5.1.4 Write unit tests for tab switching

### 4.5.2 Tab Navigation Shortcuts
- [ ] **Task 4.5.2**

Implement Ctrl+Tab and Ctrl+Shift+Tab for cycling.

- [ ] 4.5.2.1 Implement Ctrl+Tab for next tab:
  ```elixir
  def event_to_msg(%Event.Key{key: {:ctrl, :tab}}, _state) do
    :next_tab
  end
  ```
- [ ] 4.5.2.2 Implement `update(:next_tab, model)`:
  ```elixir
  def update(:next_tab, model) do
    current_idx = Enum.find_index(model.session_order, &(&1 == model.active_session_id))
    next_idx = rem(current_idx + 1, length(model.session_order))
    next_id = Enum.at(model.session_order, next_idx)
    %{model | active_session_id: next_id}
  end
  ```
- [ ] 4.5.2.3 Implement Ctrl+Shift+Tab for previous tab
- [ ] 4.5.2.4 Handle single/empty session list
- [ ] 4.5.2.5 Write unit tests for tab cycling

### 4.5.3 Session Close Shortcut
- [ ] **Task 4.5.3**

Implement Ctrl+W for closing active session.

- [ ] 4.5.3.1 Implement Ctrl+W handler:
  ```elixir
  def event_to_msg(%Event.Key{key: {:ctrl, ?w}}, _state) do
    :close_active_session
  end
  ```
- [ ] 4.5.3.2 Implement `update(:close_active_session, model)`:
  - Show confirmation if session has unsaved state (future)
  - Call SessionSupervisor.stop_session/1
  - Remove from model
  - Switch to adjacent tab
- [ ] 4.5.3.3 Prevent closing last session (or show welcome screen)
- [ ] 4.5.3.4 Write unit tests for session close

### 4.5.4 New Session Shortcut
- [ ] **Task 4.5.4**

Implement Ctrl+N for creating new session.

- [ ] 4.5.4.1 Implement Ctrl+N handler returning `:new_session_dialog`
- [ ] 4.5.4.2 Show dialog/input for project path
- [ ] 4.5.4.3 Alternative: Create session for current directory
- [ ] 4.5.4.4 Write unit tests for new session shortcut

**Unit Tests for Section 4.5:**
- Test Ctrl+1 switches to first tab
- Test Ctrl+0 switches to 10th tab
- Test Ctrl+5 does nothing if only 3 sessions
- Test Ctrl+Tab cycles to next tab
- Test Ctrl+Shift+Tab cycles to previous tab
- Test tab cycling wraps around
- Test Ctrl+W closes active session
- Test Ctrl+W with one session shows warning
- Test Ctrl+N initiates new session

---

## 4.6 Event Routing Updates

Update event handling to route events to correct session.

### 4.6.1 Input Event Routing
- [ ] **Task 4.6.1**

Route input events to active session's agent.

- [ ] 4.6.1.1 Update submit handler to use active session:
  ```elixir
  def update({:submit, text}, model) do
    session_id = model.active_session_id
    Session.AgentAPI.send_message_stream(session_id, text)
    # Update model to show processing state
    %{model | agent_status: :processing}
  end
  ```
- [ ] 4.6.1.2 Handle submit when no active session
- [ ] 4.6.1.3 Write unit tests for input routing

### 4.6.2 Scroll Event Routing
- [ ] **Task 4.6.2**

Route scroll events to active session's conversation view.

- [ ] 4.6.2.1 Update scroll handlers to update Session.State:
  ```elixir
  def update({:scroll, direction}, model) do
    session_id = model.active_session_id
    Session.State.scroll_by(session_id, scroll_amount(direction))
    model
  end
  ```
- [ ] 4.6.2.2 Handle scroll when no active session
- [ ] 4.6.2.3 Write unit tests for scroll routing

### 4.6.3 PubSub Event Handling
- [ ] **Task 4.6.3**

Update PubSub event handlers for multi-session.

- [ ] 4.6.3.1 Update stream chunk handler:
  ```elixir
  def update({:stream_chunk, session_id, chunk}, model) do
    # Session.State already updated by agent
    # Just trigger re-render if this is active session
    model
  end
  ```
- [ ] 4.6.3.2 Update stream end handler
- [ ] 4.6.3.3 Update tool call/result handlers
- [ ] 4.6.3.4 Only re-render if event is for active session
- [ ] 4.6.3.5 Write unit tests for PubSub handling

**Unit Tests for Section 4.6:**
- Test submit routes to active session's agent
- Test submit shows processing state
- Test scroll routes to active session
- Test PubSub events update correct session
- Test inactive session events don't trigger full re-render

---

## Success Criteria

1. **Tab Bar Display**: Tabs widget shows all sessions with numbered labels
2. **Tab Switching**: Ctrl+1 through Ctrl+0 switch to numbered tabs
3. **Tab Cycling**: Ctrl+Tab and Ctrl+Shift+Tab cycle through tabs
4. **Session Close**: Ctrl+W closes active session with proper cleanup
5. **Welcome Screen**: Empty session list shows welcome screen
6. **Status Bar**: Shows active session name, path, model, and count
7. **Content Isolation**: Each tab shows its session's conversation
8. **Event Routing**: Input and scroll events go to active session
9. **PubSub Routing**: Events routed to correct session
10. **Test Coverage**: Minimum 80% coverage for phase 4 code

---

## Critical Files

**Modified Files:**
- `lib/jido_code/tui.ex` - Model struct, init, view, update handlers
- `lib/jido_code/tui/view_helpers.ex` - Tab and content rendering
- `lib/jido_code/tui/event_handlers.ex` - Tab navigation events
- `lib/jido_code/tui/message_handlers.ex` - Session-aware message handling
- `test/jido_code/tui_test.exs` - Update tests for multi-session

---

## Dependencies

- **Depends on Phase 1**: Session struct, SessionRegistry
- **Depends on Phase 2**: Session.State for conversation data
- **Depends on Phase 3**: Session.AgentAPI for message sending
- **Phase 5 depends on this**: Commands need TUI integration

# Feature: Init Updates for Multi-Session TUI (Task 4.2.1)

## Problem Statement

Phase 4 of the work-session plan requires updating the TUI initialization to support multiple sessions. Tasks 4.1.1-4.1.3 (Model changes, session state access, and session order management) are complete, but the `init/1` function still initializes for single-session mode.

Current issues:
- `init/1` creates empty model with no session awareness
- No loading of existing sessions from SessionRegistry
- No PubSub subscriptions for session-specific events
- No handling of empty session state (welcome screen)

Without these updates, the TUI cannot properly initialize with existing sessions or handle multi-session workflows.

## Solution Overview

Update the TUI `init/1` function and related initialization logic to:

1. **Load existing sessions from SessionRegistry** - Query all active sessions at startup
2. **Build multi-session model** - Populate sessions map, session_order, and active_session_id
3. **Subscribe to session PubSub topics** - Subscribe to `llm_stream/1` topics for each session
4. **Handle empty session case** - Set up model for welcome screen when no sessions exist
5. **Write comprehensive unit tests** - Test all initialization scenarios

## Technical Details

### Files to Modify
- `lib/jido_code/tui.ex` - Update `init/1` and add helper functions
- `test/jido_code/tui_test.exs` - Add initialization tests

### Current State

**Current init/1** (lines 543-607):
- Subscribes to global `tui_events()` topic
- Creates empty single-session model with `messages: []`
- Initializes TextInput and ConversationView widgets
- No session loading or per-session subscriptions

**Available APIs**:
- `JidoCode.SessionRegistry.list_all/0` - Returns all registered sessions sorted by created_at
- `JidoCode.PubSubTopics.llm_stream/1` - Returns session-specific topic: `"tui.events.#{session_id}"`
- `Phoenix.PubSub.subscribe/2` - Subscribes to topics

**Model Fields** (from Task 4.1.1):
```elixir
defstruct [
  sessions: %{},           # session_id => Session.t()
  session_order: [],       # List of session_ids in tab order
  active_session_id: nil,  # Currently focused session
  # ... other fields
]
```

### Implementation Approach

#### Function 1: load_sessions_from_registry/0

```elixir
@doc """
Load all active sessions from SessionRegistry.

Returns list of Session structs sorted by creation time.
"""
@spec load_sessions_from_registry() :: [Session.t()]
defp load_sessions_from_registry do
  SessionRegistry.list_all()
end
```

#### Function 2: subscribe_to_all_sessions/1

```elixir
@doc """
Subscribe to PubSub topics for all sessions.

Subscribes to each session's llm_stream topic for receiving
streaming messages, tool calls, and other session events.
"""
@spec subscribe_to_all_sessions([Session.t()]) :: :ok
defp subscribe_to_all_sessions(sessions) do
  Enum.each(sessions, fn session ->
    topic = PubSubTopics.llm_stream(session.id)
    Phoenix.PubSub.subscribe(JidoCode.PubSub, topic)
  end)
end
```

#### Updated init/1

```elixir
def init(_opts) do
  # Subscribe to global TUI events
  Phoenix.PubSub.subscribe(JidoCode.PubSub, PubSubTopics.tui_events())

  # Subscribe to theme changes
  TermUI.Theme.subscribe()

  # Load existing sessions from registry
  sessions = load_sessions_from_registry()
  session_order = Enum.map(sessions, & &1.id)
  active_id = List.first(session_order)

  # Subscribe to all session topics
  subscribe_to_all_sessions(sessions)

  # Load configuration
  config = load_config()
  status = determine_status(config)

  # Get terminal dimensions
  window = get_terminal_dimensions()
  {width, _height} = window

  # Initialize TextInput widget
  text_input_props = TextInput.new(
    placeholder: "Type a message...",
    width: max(width - 4, 20),
    enter_submits: false
  )
  {:ok, text_input_state} = TextInput.init(text_input_props)
  text_input_state = TextInput.set_focused(text_input_state, true)

  # Initialize ConversationView widget (for active session)
  {width, height} = window
  conversation_height = max(height - 8, 1)
  conversation_width = max(width - 2, 1)

  conversation_view_props = ConversationView.new(
    messages: [],
    viewport_width: conversation_width,
    viewport_height: conversation_height,
    on_copy: &Clipboard.copy_to_clipboard/1
  )
  {:ok, conversation_view_state} = ConversationView.init(conversation_view_props)

  # Build multi-session model
  %Model{
    # Multi-session fields
    sessions: Map.new(sessions, &{&1.id, &1}),
    session_order: session_order,
    active_session_id: active_id,

    # Existing fields
    text_input: text_input_state,
    agent_status: status,
    config: config,
    reasoning_steps: [],
    tool_calls: [],
    show_tool_details: false,
    window: window,
    message_queue: [],
    scroll_offset: 0,
    show_reasoning: false,
    agent_name: :llm_agent,
    streaming_message: nil,
    is_streaming: false,
    conversation_view: conversation_view_state,

    # Remove per-session fields (now in Session.State)
    # messages: [],  # REMOVED - now per-session
  }
end
```

**Key Changes**:
1. Call `load_sessions_from_registry()` to get all active sessions
2. Build `session_order` from session IDs
3. Set `active_id` to first session (or nil if empty)
4. Call `subscribe_to_all_sessions/1` to subscribe to all session topics
5. Populate `sessions`, `session_order`, and `active_session_id` fields
6. Remove `messages: []` field (now per-session in Session.State)

### Handling Empty Sessions

When `sessions` is empty:
- `session_order` will be `[]`
- `active_session_id` will be `nil` (from `List.first([])`)
- View layer should detect `active_session_id: nil` and show welcome screen
- No session subscriptions needed

## Success Criteria

1. ✅ `load_sessions_from_registry/0` returns all active sessions
2. ✅ `subscribe_to_all_sessions/1` subscribes to each session's topic
3. ✅ `init/1` populates sessions map from registry
4. ✅ `init/1` creates session_order list
5. ✅ `init/1` sets active_session_id to first session
6. ✅ `init/1` handles empty session list (nil active_session_id)
7. ✅ `init/1` subscribes to all session PubSub topics
8. ✅ All unit tests pass
9. ✅ Phase plan updated with checkmarks
10. ✅ Summary document written

## Implementation Plan

### Step 1: Read Current Implementation
- [x] Read `lib/jido_code/tui.ex` init/1 function
- [x] Understand SessionRegistry.list_all/0 API
- [x] Understand PubSubTopics.llm_stream/1 API
- [x] Check Model struct fields

### Step 2: Implement load_sessions_from_registry/0
- [x] Add private function to TUI module
- [x] Add @spec typespec
- [x] Add documentation comments
- [x] Call JidoCode.SessionRegistry.list_all/0

### Step 3: Implement subscribe_to_all_sessions/1
- [x] Add private function to TUI module
- [x] Add @spec typespec
- [x] Add documentation comments
- [x] Iterate sessions and subscribe to llm_stream topics

### Step 4: Update init/1
- [x] Add session loading logic
- [x] Build sessions map, session_order, active_session_id
- [x] Call subscribe_to_all_sessions/1
- [x] Keep messages field for backward compatibility
- [x] Compile without errors

### Step 5: Write Unit Tests
- [x] Test init with no sessions (empty registry)
- [x] Test init with one session
- [x] Test init with multiple sessions
- [x] Test session_order matches registry order
- [x] Test active_session_id is first session
- [x] Test PubSub subscriptions created
- [x] Test all existing init tests still pass (12 tests, 0 failures)

### Step 6: Documentation and Completion
- [ ] Update phase-04.md to mark task 4.2.1 as complete
- [ ] Write summary document
- [ ] Request commit approval

## Notes/Considerations

### Edge Cases
- Empty SessionRegistry (no active sessions)
- Single session in registry
- Multiple sessions with different creation times
- SessionRegistry table not yet created

### Integration Points
- **SessionRegistry**: Must be started before TUI init
- **PubSubTopics**: Defines topic naming convention
- **Session.State**: Per-session message storage (future integration)

### Testing Strategy
- Mock SessionRegistry.list_all/0 responses
- Verify PubSub.subscribe/2 calls with captured messages
- Test model structure after init
- Ensure backward compatibility with empty sessions

### Future Work (Not in 4.2.1)
- Task 4.2.2: Dynamic subscription management (add/remove sessions)
- Task 4.2.3: Message routing with session_id
- Welcome screen rendering (Task 4.4.3)

## Status

**Current Step**: Creating feature plan
**Branch**: feature/init-updates
**Next**: Implement load_sessions_from_registry/0

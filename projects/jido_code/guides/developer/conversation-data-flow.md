# Conversation Data Flow

This document describes how conversation data flows through JidoCode, from user input to LLM response display, including the PubSub messaging system and the Elm Architecture pattern used in the TUI.

## Table of Contents

1. [Overview](#overview)
2. [Architecture Components](#architecture-components)
3. [Message Flow: User to LLM](#message-flow-user-to-llm)
4. [Response Flow: LLM to Display](#response-flow-llm-to-display)
5. [PubSub System](#pubsub-system)
6. [Elm Architecture Pattern](#elm-architecture-pattern)
7. [ConversationView Widget](#conversationview-widget)
8. [Per-Session State Management](#per-session-state-management)
9. [Two-Tier Event Handling](#two-tier-event-handling)
10. [Key Code Paths](#key-code-paths)

---

## Overview

JidoCode uses a reactive architecture for conversation handling:

1. **User Input**: TextInput widget captures keystrokes
2. **Message Dispatch**: TUI sends message to LLMAgent via AgentAPI
3. **LLM Processing**: LLMAgent streams response chunks
4. **PubSub Broadcasting**: Response chunks broadcast via Phoenix.PubSub
5. **TUI Update**: TUI receives PubSub messages, updates state
6. **View Render**: Elm Architecture triggers re-render with new state

### Key Design Principles

- **Reactive Updates**: State changes trigger automatic re-renders
- **PubSub Decoupling**: LLM and TUI communicate via PubSub, not direct calls
- **Session Isolation**: Each session has independent conversation state
- **Streaming Support**: Responses stream in real-time as they're generated
- **Widget Composition**: ConversationView is a stateful widget within the TUI

---

## Architecture Components

### Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              TUI Process                                     │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────────────┐  │
│  │   TextInput     │    │    TUI.Model    │    │   ConversationView      │  │
│  │   (widget)      │    │   (state)       │    │   (widget)              │  │
│  └────────┬────────┘    └────────┬────────┘    └───────────┬─────────────┘  │
│           │                      │                         │                 │
│           ▼                      ▼                         ▼                 │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    TUI.update/2 (Elm dispatch)                       │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                  │                                           │
│                                  ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    MessageHandlers module                            │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────┼──────────────────────────────────────────┘
                                   │ Phoenix.PubSub.subscribe
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Phoenix.PubSub                                      │
│  Topics:                                                                     │
│  - "tui.events"                    (global events)                          │
│  - "tui.events.{session_id}"       (session-specific events)                │
│  - "llm_stream:{session_id}"       (LLM streaming events)                   │
└──────────────────────────────────┬──────────────────────────────────────────┘
                                   │ Phoenix.PubSub.broadcast
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         LLMAgent Process                                     │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────────────┐  │
│  │  chat_stream/3  │───▶│  JidoAI Client  │───▶│  Anthropic/OpenAI API   │  │
│  └─────────────────┘    └─────────────────┘    └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Modules

| Module | Location | Purpose |
|--------|----------|---------|
| `JidoCode.TUI` | `lib/jido_code/tui.ex` | Main TUI process, Elm Architecture |
| `JidoCode.TUI.Model` | `lib/jido_code/tui.ex` | State struct and accessors |
| `JidoCode.TUI.MessageHandlers` | `lib/jido_code/tui/message_handlers.ex` | PubSub message processing |
| `JidoCode.TUI.Widgets.ConversationView` | `lib/jido_code/tui/widgets/conversation_view.ex` | Message display widget |
| `JidoCode.Agents.LLMAgent` | `lib/jido_code/agents/llm_agent.ex` | LLM interaction agent |
| `JidoCode.Session.AgentAPI` | `lib/jido_code/session/agent_api.ex` | Session-agent bridge |
| `JidoCode.PubSubHelpers` | `lib/jido_code/pubsub_helpers.ex` | Broadcasting utilities |

---

## Message Flow: User to LLM

### Step-by-Step Flow

```
User types message and presses Enter
  │
  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. TextInput captures :enter key event                                       │
│    Location: lib/jido_code/tui.ex (event_to_msg/2)                          │
│                                                                              │
│    {:key, %{key: :enter}} → {:msg, :submit}                                 │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 2. TUI.update(:submit, state) processes submission                           │
│    Location: lib/jido_code/tui.ex:1080-1140                                 │
│                                                                              │
│    - Get input text from active session's TextInput                         │
│    - Clear the input buffer                                                 │
│    - Add user message to ConversationView                                   │
│    - Spawn async task to send to LLM                                        │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 3. Session.AgentAPI.send_message(session_id, message)                        │
│    Location: lib/jido_code/session/agent_api.ex                             │
│                                                                              │
│    - Looks up LLMAgent for session via ProcessRegistry                      │
│    - Calls LLMAgent.chat_stream/3                                           │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 4. LLMAgent.chat_stream(pid, message, opts)                                  │
│    Location: lib/jido_code/agents/llm_agent.ex:206-280                      │
│                                                                              │
│    - Validates message                                                       │
│    - Adds to conversation history                                           │
│    - Calls JidoAI provider (Anthropic, OpenAI, etc.)                        │
│    - Spawns stream handler task                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Code Example: Submit Handler

```elixir
# lib/jido_code/tui.ex
def update(:submit, state) do
  # Get active session's text input
  text_input = Model.get_active_text_input(state)
  input_text = TextInput.get_value(text_input) |> String.trim()

  if input_text == "" do
    {state, []}
  else
    # Clear input and add user message
    new_state =
      Model.update_active_ui_state(state, fn ui ->
        new_text_input = TextInput.clear(ui.text_input)
        user_msg = %{role: :user, content: input_text, timestamp: DateTime.utc_now()}
        new_cv = ConversationView.add_message(ui.conversation_view, user_msg)

        %{ui |
          text_input: new_text_input,
          conversation_view: new_cv,
          messages: [user_msg | ui.messages]
        }
      end)

    # Send to LLM asynchronously
    session_id = state.active_session_id
    Task.start(fn ->
      Session.AgentAPI.send_message(session_id, input_text)
    end)

    {%{new_state | agent_status: :processing}, []}
  end
end
```

---

## Response Flow: LLM to Display

### Step-by-Step Flow

```
LLM generates response chunk
  │
  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. LLMAgent receives chunk from JidoAI stream                                │
│    Location: lib/jido_code/agents/llm_agent.ex:798-807                      │
│                                                                              │
│    Stream handler accumulates chunks and broadcasts each one                │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 2. Phoenix.PubSub.broadcast to stream topic                                  │
│    Location: lib/jido_code/agents/llm_agent.ex:800                          │
│                                                                              │
│    Phoenix.PubSub.broadcast(                                                │
│      JidoCode.PubSub,                                                       │
│      "llm_stream:#{session_id}",                                            │
│      {:stream_chunk, session_id, chunk}                                     │
│    )                                                                        │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 3. TUI process receives PubSub message                                       │
│    Location: lib/jido_code/tui.ex:1315-1316                                 │
│                                                                              │
│    TUI is subscribed to "llm_stream:#{session_id}" topics                   │
│    Message arrives as {:stream_chunk, session_id, chunk}                    │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 4. TUI.update dispatches to MessageHandlers                                  │
│    Location: lib/jido_code/tui.ex:1315-1316                                 │
│                                                                              │
│    def update({:stream_chunk, session_id, chunk}, state),                   │
│      do: MessageHandlers.handle_stream_chunk(session_id, chunk, state)      │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 5. MessageHandlers.handle_stream_chunk/3                                     │
│    Location: lib/jido_code/tui/message_handlers.ex:56-108                   │
│                                                                              │
│    - Checks if chunk is for active or inactive session                      │
│    - Active: Updates ConversationView, streaming_message                    │
│    - Inactive: Updates sidebar indicators only                              │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 6. ConversationView updates                                                  │
│    Location: lib/jido_code/tui/widgets/conversation_view.ex                 │
│                                                                              │
│    - start_streaming/2: Creates streaming message entry (first chunk)       │
│    - append_chunk/2: Appends text to streaming message                      │
│    - end_streaming/1: Finalizes message when stream ends                    │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ 7. Elm Architecture triggers re-render                                       │
│    Location: lib/jido_code/tui.ex (view/1)                                  │
│                                                                              │
│    State change from update/2 triggers view/1 to re-render                  │
│    ConversationView.render/2 displays updated messages                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Sequence Diagram

```
     User          TUI           AgentAPI       LLMAgent       PubSub         JidoAI
       │            │               │              │             │              │
       │──Enter────▶│               │              │             │              │
       │            │──send_msg────▶│              │             │              │
       │            │               │──chat_stream▶│             │              │
       │            │               │              │──stream────▶│              │
       │            │               │              │             │◀────chunks───│
       │            │               │              │◀────────────│              │
       │            │               │              │──broadcast─▶│              │
       │            │◀──────────────│──────────────│─────────────│              │
       │            │  {:stream_chunk, session_id, chunk}        │              │
       │            │               │              │             │              │
       │            │──update/2────▶│              │             │              │
       │            │  (state change)              │             │              │
       │            │               │              │             │              │
       │◀───render──│               │              │             │              │
       │            │               │              │             │              │
```

---

## PubSub System

### Topics

JidoCode uses three types of PubSub topics:

| Topic | Pattern | Purpose |
|-------|---------|---------|
| Global | `"tui.events"` | Tool calls, config changes |
| Session-specific | `"tui.events.{session_id}"` | Session-scoped events |
| LLM Stream | `"llm_stream:{session_id}"` | Streaming response chunks |

### Message Types

**LLM Streaming Messages**:
```elixir
{:stream_chunk, session_id, chunk}    # Partial response text
{:stream_end, session_id, content}    # Stream complete
{:stream_error, reason}               # Stream failed
```

**Tool Messages**:
```elixir
{:tool_call, tool_name, params, call_id, session_id}
{:tool_result, %Result{}}
```

**Status Messages**:
```elixir
{:agent_response, content}            # Non-streaming response
{:agent_status, status}               # Status change
{:config_changed, config}             # Configuration update
```

### ARCH-2 Dual-Topic Pattern

For session events, JidoCode broadcasts to BOTH session-specific AND global topics:

```elixir
# lib/jido_code/pubsub_helpers.ex
def broadcast(session_id, message) when is_binary(session_id) do
  # ARCH-2: Broadcast to both session-specific AND global topics
  Phoenix.PubSub.broadcast(JidoCode.PubSub, session_topic(session_id), message)
  Phoenix.PubSub.broadcast(JidoCode.PubSub, @global_topic, message)
end
```

This ensures:
1. Session-specific subscribers receive targeted messages
2. Global subscribers (like debug tools) receive ALL messages
3. Backwards compatibility with code subscribing only to global topic

### Subscription Management

**On Session Creation**:
```elixir
# lib/jido_code/tui.ex:1860
Phoenix.PubSub.subscribe(JidoCode.PubSub, PubSubTopics.llm_stream(session.id))
```

**On Session Close**:
```elixir
# Unsubscribe happens implicitly when session is removed from Model
# PubSub messages for closed sessions are ignored in update/2
```

---

## Elm Architecture Pattern

JidoCode's TUI follows the Elm Architecture (TEA) pattern:

### The Three Functions

```
┌─────────────────────────────────────────────────────────────────┐
│                         Elm Architecture                         │
│                                                                  │
│   ┌─────────┐    Events     ┌──────────┐    State    ┌───────┐  │
│   │  view   │─────────────▶│  update  │────────────▶│ Model │  │
│   └────┬────┘               └──────────┘             └───┬───┘  │
│        │                                                 │      │
│        └─────────────────────────────────────────────────┘      │
│                          renders                                 │
└─────────────────────────────────────────────────────────────────┘
```

1. **Model** (`JidoCode.TUI.Model`): The state struct
2. **Update** (`TUI.update/2`): Pure function (state, event) → new state
3. **View** (`TUI.view/1`): Pure function state → UI

### Update Function Pattern

```elixir
# lib/jido_code/tui.ex
@spec update(msg(), Model.t()) :: {Model.t(), [Command.t()]}
def update(msg, state) do
  case msg do
    # Keyboard events
    {:key, event} ->
      handle_key_event(event, state)

    # User actions
    :submit ->
      handle_submit(state)

    # PubSub messages (from LLMAgent)
    {:stream_chunk, session_id, chunk} ->
      MessageHandlers.handle_stream_chunk(session_id, chunk, state)

    {:stream_end, session_id, content} ->
      MessageHandlers.handle_stream_end(session_id, content, state)

    # ... other message types
  end
end
```

### How PubSub Integrates with TEA

```
PubSub Message                TEA Cycle
     │                            │
     ▼                            ▼
┌─────────┐    {:stream_chunk}   ┌──────────┐
│ PubSub  │─────────────────────▶│  update  │
└─────────┘                      └────┬─────┘
                                      │
                                      ▼
                                 ┌─────────┐
                                 │  Model  │ (new state)
                                 └────┬────┘
                                      │
                                      ▼
                                 ┌─────────┐
                                 │  view   │ (re-render)
                                 └─────────┘
```

The TUI process receives PubSub messages as regular Erlang messages. TermUI's runtime converts these to TEA events that flow through `update/2`.

---

## ConversationView Widget

### Widget Architecture

ConversationView is a **stateful widget** - it maintains its own internal state for:
- Message list
- Scroll position
- Streaming message (in progress)
- Viewport dimensions

### State Structure

```elixir
@type t :: %__MODULE__{
  messages: [message()],           # All messages (user, assistant, system)
  scroll_offset: non_neg_integer(), # Current scroll position
  viewport_width: pos_integer(),    # Available width
  viewport_height: pos_integer(),   # Available height
  streaming_message_id: String.t() | nil,  # ID of message being streamed
  on_copy: (String.t() -> :ok) | nil       # Copy callback
}
```

### Key Functions

| Function | Purpose |
|----------|---------|
| `new/1` | Create widget with initial options |
| `init/1` | Initialize stateful component |
| `add_message/2` | Add a complete message |
| `start_streaming/2` | Begin streaming a new message |
| `append_chunk/2` | Append text to streaming message |
| `end_streaming/1` | Finalize streaming message |
| `render/2` | Generate TermUI view tree |

### Streaming Flow in ConversationView

```elixir
# 1. First chunk arrives - start streaming
{cv, message_id} = ConversationView.start_streaming(conversation_view, :assistant)

# 2. Subsequent chunks - append to streaming message
cv = ConversationView.append_chunk(cv, "Hello, ")
cv = ConversationView.append_chunk(cv, "how can ")
cv = ConversationView.append_chunk(cv, "I help?")

# 3. Stream ends - finalize message
cv = ConversationView.end_streaming(cv)
```

### Rendering

ConversationView renders using only low-level TermUI primitives:

```elixir
# lib/jido_code/tui/widgets/conversation_view.ex
def render(%__MODULE__{} = state, opts \\ []) do
  # Build message views
  message_views = Enum.map(visible_messages(state), &render_message/1)

  # Stack vertically with scrollbar
  stack(:vertical, [
    messages_container(message_views),
    scrollbar(state)
  ])
end
```

---

## Per-Session State Management

### Session UI State

Each session has its own UI state stored in `Model.sessions`:

```elixir
@type session_ui_state :: %{
  text_input: TextInput.t() | nil,           # Input widget state
  conversation_view: ConversationView.t() | nil,  # Message display state
  accordion: Accordion.t() | nil,            # Sidebar accordion state
  scroll_offset: non_neg_integer(),          # Scroll position
  streaming_message: String.t() | nil,       # Current streaming content
  is_streaming: boolean(),                   # Streaming in progress?
  reasoning_steps: [reasoning_step()],       # Chain-of-thought steps
  tool_calls: [tool_call_entry()],           # Active tool executions
  messages: [message()]                      # Conversation history
}
```

### Accessing Per-Session State

```elixir
# Get active session's UI state
ui_state = Model.get_active_ui_state(model)

# Get specific widget
text_input = Model.get_active_text_input(model)
conversation_view = Model.get_active_conversation_view(model)
accordion = Model.get_active_accordion(model)

# Update active session's UI state
model = Model.update_active_ui_state(model, fn ui ->
  %{ui | is_streaming: true}
end)
```

### Session Switching

When switching sessions, the TUI:
1. Saves current session's UI state (already in Model)
2. Updates `active_session_id`
3. Renders the new session's ConversationView

```elixir
def update({:switch_to_session, session_id}, state) do
  new_state = %{state | active_session_id: session_id}
  # ConversationView for new session is already in session_ui_state
  # Next render will display it
  {new_state, []}
end
```

---

## Two-Tier Event Handling

### Active vs Inactive Sessions

Events are handled differently based on whether they're for the active session:

**Active Session** (full UI update):
- Update ConversationView with new content
- Show streaming indicators
- Update status bar
- Full re-render

**Inactive Session** (sidebar only):
- Update sidebar activity badge
- Increment unread count
- Show streaming indicator in sidebar
- No conversation view update (performance)

### Implementation

```elixir
# lib/jido_code/tui/message_handlers.ex
def handle_stream_chunk(session_id, chunk, state) do
  if session_id == state.active_session_id do
    handle_active_stream_chunk(session_id, chunk, state)
  else
    handle_inactive_stream_chunk(session_id, chunk, state)
  end
end

defp handle_active_stream_chunk(session_id, chunk, state) do
  # Full UI update
  Model.update_active_ui_state(state, fn ui ->
    new_streaming_message = (ui.streaming_message || "") <> chunk
    new_cv = ConversationView.append_chunk(ui.conversation_view, chunk)

    %{ui |
      conversation_view: new_cv,
      streaming_message: new_streaming_message,
      is_streaming: true
    }
  end)
end

defp handle_inactive_stream_chunk(session_id, _chunk, state) do
  # Sidebar-only update (no ConversationView changes)
  %{state |
    streaming_sessions: MapSet.put(state.streaming_sessions, session_id),
    last_activity: Map.put(state.last_activity, session_id, DateTime.utc_now())
  }
end
```

---

## Key Code Paths

### User Sends Message

```
TUI.update(:submit, state)
  → Model.get_active_text_input(state)
  → TextInput.get_value(text_input)
  → Model.update_active_ui_state(state, fn ui -> ... end)
  → ConversationView.add_message(cv, user_msg)
  → Task.start(fn -> Session.AgentAPI.send_message(...) end)
```

**Files**:
- `lib/jido_code/tui.ex:1080-1140`
- `lib/jido_code/session/agent_api.ex:60-100`

### LLM Streams Response

```
LLMAgent.handle_stream_chunk(chunk, state)
  → Phoenix.PubSub.broadcast(topic, {:stream_chunk, session_id, chunk})

TUI receives message
  → TUI.update({:stream_chunk, session_id, chunk}, state)
  → MessageHandlers.handle_stream_chunk(session_id, chunk, state)
  → Model.update_active_ui_state(state, fn ui -> ... end)
  → ConversationView.append_chunk(cv, chunk)
```

**Files**:
- `lib/jido_code/agents/llm_agent.ex:798-807`
- `lib/jido_code/tui.ex:1315-1316`
- `lib/jido_code/tui/message_handlers.ex:56-108`

### Stream Ends

```
LLMAgent broadcasts {:stream_end, session_id, full_content}
  → TUI.update({:stream_end, session_id, full_content}, state)
  → MessageHandlers.handle_stream_end(session_id, full_content, state)
  → ConversationView.end_streaming(cv)
  → Add final message to ui.messages
```

**Files**:
- `lib/jido_code/agents/llm_agent.ex:803-807`
- `lib/jido_code/tui.ex:1318-1319`
- `lib/jido_code/tui/message_handlers.ex:133-183`

---

## Debugging Conversation Flow

### Tracing PubSub Messages

```elixir
# Subscribe to see all messages for a session
Phoenix.PubSub.subscribe(JidoCode.PubSub, "llm_stream:#{session_id}")

# In IEx, messages appear as:
# {:stream_chunk, "abc123", "Hello"}
# {:stream_end, "abc123", "Hello, how can I help?"}
```

### Checking ConversationView State

```elixir
# Get current conversation view state
cv = Model.get_active_conversation_view(model)

# Inspect messages
cv.messages

# Check if streaming
cv.streaming_message_id != nil
```

### Common Issues

**1. Messages not appearing**
- Check PubSub subscription: `Phoenix.PubSub.subscribers(JidoCode.PubSub, topic)`
- Verify session_id matches active_session_id
- Check ConversationView is initialized

**2. Streaming not updating**
- Verify `is_streaming` flag in UI state
- Check `streaming_message` is being accumulated
- Ensure `start_streaming/2` was called on first chunk

**3. Messages appearing in wrong session**
- Verify session_id in broadcast matches expected session
- Check two-tier routing in MessageHandlers

---

## References

- [Session Architecture](./session-architecture.md) - Multi-session design
- [Adding Session Tools](./adding-session-tools.md) - Tool development guide
- [Persistence Format](./persistence-format.md) - Session storage format
- CLAUDE.md - Project overview and PubSub topics

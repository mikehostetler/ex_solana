# Session Architecture

This document describes the multi-session architecture of JidoCode, enabling users to work with multiple independent sessions simultaneously.

## Table of Contents

1. [Overview](#overview)
2. [Architecture Components](#architecture-components)
3. [Supervision Tree](#supervision-tree)
4. [Data Flow](#data-flow)
5. [Session Lifecycle](#session-lifecycle)
6. [State Management](#state-management)
7. [Event Routing](#event-routing)
8. [Integration Points](#integration-points)

---

## Overview

JidoCode's multi-session architecture allows users to manage up to 10 concurrent work sessions, each with:
- Independent conversation history
- Isolated AI agent state
- Separate project context
- Individual tool execution boundaries
- Persistent state across restarts

### Key Design Principles

1. **Session Isolation**: Each session operates independently with no cross-contamination
2. **Resource Limits**: Maximum 10 sessions to prevent resource exhaustion
3. **Fault Tolerance**: Session crashes don't affect other sessions or the TUI
4. **Persistence**: Sessions can be saved and restored with full state
5. **Single TUI**: One terminal UI manages all sessions with tab-based navigation

---

## Architecture Components

### 1. Session Struct (`JidoCode.Session`)

The core session data structure:

```elixir
defmodule JidoCode.Session do
  @type t :: %__MODULE__{
    id: String.t(),                    # Unique session ID (UUID)
    name: String.t(),                  # Display name (auto-generated from path)
    project_path: String.t(),          # Absolute project directory path
    config: map(),                     # Session-specific LLM configuration
    created_at: DateTime.t(),          # Session creation timestamp
    updated_at: DateTime.t()           # Last activity timestamp
  }
end
```

**Location**: `lib/jido_code/session.ex`

### 2. SessionSupervisor (`JidoCode.SessionSupervisor`)

Top-level supervisor managing all session processes using a `DynamicSupervisor`.

**Responsibilities**:
- Start new session processes
- Stop session processes
- Monitor session health
- Enforce session limits (max 10)

**Location**: `lib/jido_code/session_supervisor.ex`

**Key Functions**:
```elixir
start_session(project_path, opts \\ [])  # Create and start new session
stop_session(session_id)                  # Stop and cleanup session
list_sessions()                           # Get all active sessions
get_session(session_id)                   # Retrieve session by ID
```

### 3. SessionRegistry (`JidoCode.SessionRegistry`)

ETS-based registry tracking all active sessions.

**Responsibilities**:
- Register new sessions
- Unregister closed sessions
- Provide fast session lookup
- Track session metadata
- Enforce uniqueness constraints (no duplicate project paths)

**Location**: `lib/jido_code/session_registry.ex`

**Key Functions**:
```elixir
register(session)              # Register new session
unregister(session_id)         # Unregister session
lookup(session_id)             # Find session by ID
list_all()                     # Get all sessions
find_by_path(project_path)     # Find session by project path
```

### 4. Session.Supervisor (`JidoCode.Session.Supervisor`)

Per-session supervision tree managing session's child processes.

**Children** (in start order):
1. `Session.State` - GenServer storing conversation history
2. `Agents.LLMAgent` - GenServer managing AI agent interaction

**Location**: `lib/jido_code/session/supervisor.ex`

### 5. Session.State (`JidoCode.Session.State`)

GenServer storing session's conversation state.

**State**:
```elixir
%{
  session_id: String.t(),
  messages: [message()],           # Conversation history
  todos: [todo()],                 # Task list
  reasoning_steps: [step()],       # Chain-of-thought steps
  tool_calls: [tool_call()],       # Active tool executions
  streaming_message: String.t() | nil  # Current streaming response
}
```

**Location**: `lib/jido_code/session/state.ex`

### 6. Agents.LLMAgent (`JidoCode.Agents.LLMAgent`)

GenServer managing AI agent for a session.

**Responsibilities**:
- Send messages to LLM
- Handle streaming responses
- Execute tool calls
- Maintain agent state

**Location**: `lib/jido_code/agents/llm_agent.ex`

### 7. TUI Model (`JidoCode.TUI.Model`)

Terminal UI state managing multiple sessions.

**Session Fields**:
```elixir
%{
  sessions: %{session_id => Session.t()},  # All sessions by ID
  session_order: [session_id],              # Tab order (max 10)
  active_session_id: session_id | nil       # Currently focused session
}
```

**Location**: `lib/jido_code/tui.ex`

---

## Supervision Tree

```
Application
  ├─ JidoCode.SessionSupervisor (DynamicSupervisor)
  │   ├─ SessionProcess (one per session, max 10)
  │   │    └─ JidoCode.Session.Supervisor
  │   │         ├─ JidoCode.Session.State (GenServer)
  │   │         └─ JidoCode.Agents.LLMAgent (GenServer)
  │   ├─ SessionProcess (another session)
  │   └─ ... (up to 10 sessions)
  │
  ├─ JidoCode.SessionRegistry (GenServer + ETS)
  │
  └─ JidoCode.TUI (StatefulComponent)
       ├─ TermUI Runtime
       └─ PubSub Subscriptions (per session)
```

### Supervision Strategy

- **SessionSupervisor**: `:one_for_one` - Session crash doesn't affect other sessions
- **Session.Supervisor**: `:one_for_all` - If agent crashes, restart entire session
- **Restart Strategy**: `:transient` - Only restart on abnormal termination

### Fault Isolation

1. **Session Crash**: Only affects that session, others continue
2. **Agent Crash**: Session.Supervisor restarts both State and Agent
3. **TUI Crash**: Application terminates (by design, requires full restart)
4. **Registry Crash**: All sessions restart (registry is critical)

---

## Data Flow

### Session Creation Flow

```
User → TUI (Ctrl+N or /session new)
  ↓
TUI.update(:create_new_session, state)
  ↓
Commands.execute_session({:new, opts}, model)
  ↓
1. resolve_session_path(path)     # Expand ~, relative paths
2. validate_session_path(path)    # Check exists, permissions
3. SessionRegistry.check_limit()  # Enforce max 10 sessions
4. SessionRegistry.find_by_path() # Check for duplicates
5. SessionSupervisor.start_session(path, name)
  ↓
SessionSupervisor starts:
  a. SessionProcess (child spec)
  b. Session.Supervisor.start_link()
     i.  Session.State.start_link()
     ii. Agents.LLMAgent.start_link()
  c. SessionRegistry.register(session)
  ↓
Returns {:session_action, {:add_session, session}}
  ↓
TUI.handle_session_command processes action:
  a. Model.add_session(state, session)  # Add to TUI state
  b. Subscribe to session's PubSub topic
  c. refresh_conversation_view_for_session()
  d. add_session_message("Created session: #{name}")
  ↓
TUI re-renders with new session tab
```

### Message Send Flow

```
User types message in TUI
  ↓
TUI.update(:submit, state)
  ↓
Determine active_session_id
  ↓
Session.AgentAPI.send_message(session_id, message)
  ↓
Agents.LLMAgent.handle_call(:send_message, ...)
  ↓
1. Add user message to Session.State
2. Call LLM API via JidoAI
3. Stream response chunks
  ↓
For each chunk:
  Phoenix.PubSub.broadcast("llm_stream:#{session_id}", {:stream_chunk, chunk})
  ↓
TUI receives via PubSub subscription
  ↓
TUI.update({:stream_chunk, session_id, chunk}, state)
  ↓
If session_id == active_session_id:
  - Update conversation_view
  - Show streaming indicator
Else:
  - Update sidebar activity badge
  - Increment unread count
```

### Session Switch Flow

```
User presses Ctrl+2 (or /session switch 2)
  ↓
TUI.event_to_msg(Event.Key{key: "2", modifiers: [:ctrl]}, state)
  → {:msg, {:switch_to_session_index, 2}}
  ↓
TUI.update({:switch_to_session_index, 2}, state)
  ↓
1. Model.get_session_by_index(state, 2)  # Get session at index
2. Model.switch_session(state, session_id)  # Update active_session_id
3. refresh_conversation_view_for_session(session_id)
   - Session.State.get_messages(session_id)
   - ConversationView.set_messages(messages)
4. clear_session_activity(session_id)  # Clear unread badge
5. add_session_message("Switched to: #{session.name}")
  ↓
TUI re-renders:
  - Tab 2 highlighted as active
  - Conversation view shows session 2's messages
  - Status bar shows session 2's info
```

---

## Session Lifecycle

### 1. Creation

**Trigger**: Ctrl+N, `/session new <path>`

**Steps**:
1. Validate path (exists, is directory, readable)
2. Check session limit (max 10)
3. Check for duplicate (same project path)
4. Generate session ID (UUID)
5. Auto-generate name from directory name
6. Start session processes (State + Agent)
7. Register in SessionRegistry
8. Add to TUI model
9. Subscribe to PubSub events
10. Switch to new session

**State**: Session active, ready for messages

### 2. Active Use

**Operations**:
- Send messages to AI agent
- Execute tools within session boundary
- View conversation history
- Switch between sessions
- Rename session

**State Tracking**:
- `Session.State` maintains conversation
- `Agents.LLMAgent` tracks agent state
- `updated_at` timestamp refreshed on activity

### 3. Close

**Trigger**: Ctrl+W, `/session close`

**Steps**:
1. Save session state to disk (persistence)
2. Unsubscribe from PubSub events
3. Stop session processes (State + Agent)
4. Unregister from SessionRegistry
5. Remove from TUI model
6. Switch to adjacent session (or welcome screen)

**Cleanup Order** (critical to prevent race conditions):
1. PubSub unsubscribe (prevent events during teardown)
2. SessionSupervisor.stop_session() (graceful shutdown)
3. Model.remove_session() (update TUI state)

### 4. Persistence

**Auto-Save**: On session close

**File Location**: `~/.jido_code/sessions/{session_id}.json`

**Persisted Data**:
- Session metadata (id, name, path, timestamps)
- Conversation history (messages, roles, timestamps)
- Todo list state
- Session configuration

**Not Persisted**:
- Streaming state (transient)
- Tool execution state (transient)
- Agent internal state (rebuilt on resume)

### 5. Resume

**Trigger**: `/resume`, `/resume <index>`

**Steps**:
1. List saved sessions from `~/.jido_code/sessions/`
2. User selects session to restore
3. Load session data from JSON file
4. Start new session processes
5. Restore conversation history to Session.State
6. Restore todo list
7. Register in SessionRegistry
8. Add to TUI model

**State**: Session restored with full history

---

## State Management

### TUI State (Shared)

**Managed by**: `JidoCode.TUI.Model`

**Shared Across Sessions**:
- Window size
- Text input buffer
- Focus state (input, conversation, sidebar)
- Show reasoning flag
- Modals (shell dialog, pick list)

**Per-Session (in Model)**:
- `sessions` map
- `session_order` list
- `active_session_id`

### Session State (Per-Session)

**Managed by**: `JidoCode.Session.State`

**Isolated Per Session**:
- Messages (conversation history)
- Todos (task list)
- Reasoning steps (chain-of-thought)
- Tool calls (active executions)
- Streaming message (current response)

### Agent State (Per-Session)

**Managed by**: `JidoCode.Agents.LLMAgent`

**Isolated Per Session**:
- Agent configuration
- Streaming connection
- Tool registry
- Chain-of-thought state

---

## Event Routing

### PubSub Topics

Each session has its own PubSub topic:

```elixir
"llm_stream:#{session_id}"  # LLM streaming events
```

**Events Published**:
- `{:stream_chunk, session_id, chunk}` - Response chunk
- `{:stream_end, session_id, content}` - Stream complete
- `{:tool_call, session_id, name, args, id}` - Tool execution
- `{:tool_result, session_id, result}` - Tool complete

### TUI Subscription Management

**On Session Created**:
```elixir
Phoenix.PubSub.subscribe(JidoCode.PubSub, "llm_stream:#{session_id}")
```

**On Session Closed**:
```elixir
Phoenix.PubSub.unsubscribe(JidoCode.PubSub, "llm_stream:#{session_id}")
```

### Two-Tier Event Handling

**Active Session Events** (session_id == active_session_id):
- Update conversation view
- Show streaming indicators
- Display tool execution
- Full UI update

**Inactive Session Events** (session_id != active_session_id):
- Update sidebar activity badge
- Increment unread count
- Show streaming indicator in sidebar
- No conversation view update (performance)

This two-tier system allows users to see background activity without switching sessions.

---

## Integration Points

### 1. Commands (`JidoCode.Commands`)

Session commands integrate via `execute_session/2`:

```elixir
def execute_session(subcommand, model) do
  case subcommand do
    {:new, opts} -> create_session(opts, model)
    :list -> list_sessions(model)
    {:switch, target} -> switch_session(target, model)
    {:close, target} -> close_session(target, model)
    {:rename, name} -> rename_session(name, model)
  end
end
```

Returns `{:session_action, action}` for TUI to process.

### 2. Tools

Tools execute within session boundaries via `JidoCode.Tools.Security`:

**Path Validation**: Tools can only access files within session's project path

**Security Model**:
- Session's `project_path` is the security boundary
- All tool file operations validated against this path
- Symlinks validated to prevent escapes
- Forbidden paths blocked (e.g., ~/.ssh, /etc)

**Example** (read_file tool):
```elixir
def execute(%{path: file_path}, %{session_id: session_id}) do
  session = SessionRegistry.lookup(session_id)
  boundary = session.project_path

  case Security.validate_path(file_path, boundary) do
    {:ok, resolved_path} -> File.read(resolved_path)
    {:error, reason} -> {:error, "Access denied: #{reason}"}
  end
end
```

### 3. Keyboard Shortcuts

Session navigation via keyboard:

- **Ctrl+1-9, Ctrl+0**: Direct switch to session by index
- **Ctrl+Tab**: Cycle to next session
- **Ctrl+Shift+Tab**: Cycle to previous session
- **Ctrl+W**: Close active session
- **Ctrl+N**: Create new session for current directory

All shortcuts route through `TUI.event_to_msg/2` → `TUI.update/2`.

### 4. Persistence (`JidoCode.Session.Persistence`)

Sessions automatically persist on close:

```elixir
def save(session_id) do
  with {:ok, session} <- SessionRegistry.lookup(session_id),
       {:ok, state} <- Session.State.get_state(session_id),
       {:ok, persisted} <- serialize(session, state),
       {:ok, json} <- Jason.encode(persisted) do
    file_path = session_file(session_id)
    File.write(file_path, json)
  end
end
```

Resume via:

```elixir
def restore(session_id) do
  with {:ok, json} <- File.read(session_file(session_id)),
       {:ok, data} <- Jason.decode(json),
       {:ok, session} <- SessionSupervisor.start_session(data.project_path, data) do
    # Restore conversation history
    Session.State.restore_state(session.id, data.conversation)
    {:ok, session}
  end
end
```

---

## Adding Session-Aware Features

### Making Tools Session-Aware

1. **Accept session context**:
```elixir
def execute(args, %{session_id: session_id}) do
  session = SessionRegistry.lookup(session_id)
  project_path = session.project_path
  # Tool logic using project_path as boundary
end
```

2. **Validate paths**:
```elixir
def execute(%{path: file_path}, %{session_id: session_id}) do
  session = SessionRegistry.lookup(session_id)

  case Security.validate_path(file_path, session.project_path) do
    {:ok, resolved} -> # Proceed
    {:error, _} -> {:error, "Path outside project boundary"}
  end
end
```

### Adding Session Commands

1. **Add command parsing** in `Commands`:
```elixir
def parse_session_args("mycommand " <> args) do
  {:mycommand, parse_args(args)}
end
```

2. **Implement handler**:
```elixir
def execute_session({:mycommand, args}, model) do
  # Command logic
  {:session_action, action}  # Return action for TUI
end
```

3. **Handle in TUI**:
```elixir
def handle_session_command({:mycommand, args}, state) do
  case Commands.execute_session({:mycommand, args}, state) do
    {:session_action, action} -> process_action(action, state)
    {:error, message} -> show_error(message, state)
  end
end
```

### Adding Session State Fields

1. **Update `Session.State`**:
```elixir
defmodule Session.State do
  defstruct [
    # Existing fields...
    my_new_field: nil  # Add new field
  ]
end
```

2. **Update persistence schema** in `Persistence`:
```elixir
@type persisted_session :: %{
  # Existing fields...
  my_new_field: term()  # Add to schema
}

# Increment schema version
@schema_version 2
```

3. **Write migration** (if changing existing format):
```elixir
def migrate(data, from_version) do
  case from_version do
    1 -> Map.put(data, :my_new_field, default_value())
    _ -> data
  end
end
```

---

## Performance Considerations

### Resource Limits

- **Max Sessions**: 10 (enforced by SessionRegistry)
- **Max Messages per Session**: 1000 (pagination in Session.State)
- **Memory per Session**: ~5-10 MB typical
- **Total Memory**: ~50-100 MB for 10 sessions

### Optimization Strategies

1. **Lazy Loading**: Conversation view only loads active session
2. **Pagination**: Messages loaded in chunks (not all at once)
3. **ETS Lookup**: SessionRegistry uses ETS for O(1) lookups
4. **Two-Tier Events**: Inactive sessions skip heavy UI updates

### Monitoring

**Check active sessions**:
```elixir
SessionRegistry.list_all()
|> Enum.count()
```

**Check session memory**:
```elixir
:erlang.process_info(pid, :memory)
```

---

## Debugging

### Common Issues

**1. Session Not Found**

Check if session is registered:
```elixir
SessionRegistry.lookup(session_id)
```

**2. Events Not Routing**

Verify PubSub subscription:
```elixir
Phoenix.PubSub.subscribers(JidoCode.PubSub, "llm_stream:#{session_id}")
```

**3. Tool Access Denied**

Check path validation:
```elixir
session = SessionRegistry.lookup(session_id)
Security.validate_path(tool_path, session.project_path)
```

### Tracing Session Events

Enable debug logging:
```elixir
Logger.configure(level: :debug)
```

Watch PubSub events:
```elixir
Phoenix.PubSub.subscribe(JidoCode.PubSub, "llm_stream:#{session_id}")
```

---

## References

- [Session User Guide](../user/sessions.md) - User-facing documentation
- [Persistence Format](./persistence-format.md) - JSON schema details
- [Adding Session Tools](./adding-session-tools.md) - Tool development guide
- Phase 1 Planning: `notes/planning/work-session/phase-01.md`
- Phase 4 Planning: `notes/planning/work-session/phase-04.md`

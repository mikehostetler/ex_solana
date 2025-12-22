# Multi-Session Architecture Diagram

This document provides visual diagrams of JidoCode's multi-session architecture.

## Complete System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              TUI Layer (Elm Architecture)                    │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ JidoCode.TUI                                                           │ │
│  │   - Model: %{sessions, session_order, active_session_id, ...}        │ │
│  │   - Event handling: Keyboard, mouse, resize                          │ │
│  │   - View: Tab bar, conversation, input, status line, sidebar         │ │
│  │   - Update: Message routing, state transitions                       │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                    │                                         │
│                                    │ PubSub (Phoenix.PubSub)                │
│                                    │ Topics: "tui.events", "tui.events.{id}" │
└────────────────────────────────────┼─────────────────────────────────────────┘
                                     │
┌────────────────────────────────────┼─────────────────────────────────────────┐
│                              Session Management Layer                        │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ SessionSupervisor (DynamicSupervisor)                                 │ │
│  │   Supervises up to 10 concurrent sessions                             │ │
│  └──────┬─────────────────────────────────────────────────────────────────┘ │
│         │                                                                    │
│         ├─ SessionProcess (Session 1)                                       │
│         │    ├─ Session.Supervisor                                          │
│         │    │    ├─ Session.State (GenServer)                              │
│         │    │    │    - Conversation history (messages)                    │
│         │    │    │    - Reasoning steps                                    │
│         │    │    │    - Tool calls                                         │
│         │    │    │    - Todos                                              │
│         │    │    │    - UI state (scroll, streaming)                       │
│         │    │    └─ Agents.LLMAgent (GenServer)                            │
│         │    │         - LLM communication                                  │
│         │    │         - Tool call orchestration                            │
│         │    │         - Streaming response handling                        │
│         │    └─ Session struct: %{id, name, project_path, config}          │
│         │                                                                    │
│         ├─ SessionProcess (Session 2)                                       │
│         │    └─ ... (same structure as Session 1)                           │
│         │                                                                    │
│         └─ SessionProcess (Session N, up to 10)                             │
│              └─ ... (same structure as Session 1)                           │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ SessionRegistry (ETS)                                                  │ │
│  │   Key-value store: session_id → %{name, project_path, created_at}    │ │
│  │   Used for: Lookups, duplicate detection, session listing             │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ SessionProcessRegistry (Registry)                                      │ │
│  │   {:state, session_id} → State PID                                    │ │
│  │   {:agent, session_id} → Agent PID                                    │ │
│  │   Used for: Process lookup, message routing                           │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ Session.Manager                                                        │ │
│  │   - Session lifecycle management                                      │ │
│  │   - Registry interactions                                             │ │
│  │   - Helper functions (project_root/1, etc.)                           │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                              Persistence Layer                                │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │ Session.Persistence                                                    │  │
│  │   - save/1: Serialize session to JSON                                 │  │
│  │   - restore/1: Load session from JSON                                 │  │
│  │   - list_persisted/0: List saved sessions                             │  │
│  │   - delete/1: Remove saved session                                    │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                    │                                          │
│                                    ▼                                          │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │ ~/.jido_code/sessions/                                                 │  │
│  │   - {session_id}.json (one file per session)                           │  │
│  │   - Schema: version, id, name, project_path, config, conversation,     │  │
│  │             todos, created_at, updated_at, closed_at                   │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                              Tool System Layer                                │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │ Tools.Executor                                                         │  │
│  │   - Context building: build_context(session_id) → context             │  │
│  │   - Tool execution: execute(tool_call, context: context)              │  │
│  │   - Batch execution: execute_batch(tool_calls, context: context)      │  │
│  │   - PubSub broadcasting: {:tool_call, ...}, {:tool_result, ...}       │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                    │                                          │
│                                    ▼                                          │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │ Tool Handlers (Session-Aware)                                          │  │
│  │   - Handlers.FileSystem.* (read, write, edit, list, info, create)     │  │
│  │   - Handlers.Search.* (grep, find_files)                               │  │
│  │   - Handlers.Shell.RunCommand                                          │  │
│  │   - Handlers.Todo (update_todos, broadcast)                            │  │
│  │   - All handlers receive context: %{session_id, project_root}          │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                    │                                          │
│                                    ▼                                          │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │ Tools.Security                                                         │  │
│  │   - Path validation: validate_path(path, project_root)                │  │
│  │   - Boundary enforcement: Ensures paths within project_root           │  │
│  │   - Symlink resolution: Prevents escape attacks                        │  │
│  │   - Forbidden path blocking: System dirs, dotfiles, etc.              │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Supervision Tree Detail

```
Application
  │
  ├─ SessionSupervisor (DynamicSupervisor, max: 10)
  │    │
  │    ├─ SessionProcess (Session 1)
  │    │    ├─ Session.Supervisor (one_for_one)
  │    │    │    ├─ Session.State (GenServer)
  │    │    │    │    - Registry: {:state, session_id}
  │    │    │    │    - Stores: messages, todos, reasoning_steps, tool_calls
  │    │    │    │
  │    │    │    └─ Agents.LLMAgent (GenServer)
  │    │    │         - Registry: {:agent, session_id}
  │    │    │         - LLM provider communication
  │    │    │         - Tool execution delegation
  │    │    │
  │    │    └─ Session struct (metadata)
  │    │
  │    ├─ SessionProcess (Session 2)
  │    │    └─ ... (same as Session 1)
  │    │
  │    └─ SessionProcess (Session N)
  │         └─ ... (same as Session 1)
  │
  ├─ SessionRegistry (ETS table)
  │    - Global registry of session metadata
  │    - Fast lookups by session_id
  │
  ├─ SessionProcessRegistry (Registry)
  │    - Process registry for State and Agent PIDs
  │    - Via-tuple lookups: ProcessRegistry.via(:state, session_id)
  │
  └─ Phoenix.PubSub
       - Global topic: "tui.events"
       - Session topics: "tui.events.{session_id}"
```

---

## Session Lifecycle Flow

```
1. CREATE SESSION
   User: /session new ~/myproject
     ↓
   Commands.execute_session({:new, opts}, model)
     ↓
   SessionSupervisor.start_session(path, name)
     ↓
   [Creates supervision tree]
     ├─ Session.Supervisor.start_link(session)
     │    ├─ Session.State.start_link(session: session)
     │    │    └─ Register in SessionProcessRegistry: {:state, session_id}
     │    └─ Agents.LLMAgent.start_link(session: session, config: config)
     │         └─ Register in SessionProcessRegistry: {:agent, session_id}
     │
     └─ SessionRegistry.register(session_id, metadata)
          └─ Store: %{id, name, project_path, created_at}
     ↓
   Return: {:session_action, {:add_session, session}}
     ↓
   TUI: Model.add_session(model, session)
     ├─ Update sessions map: %{session_id => session}
     ├─ Update session_order list: [session_id | existing_order]
     ├─ Set active_session_id: session_id
     └─ Subscribe to topic: "tui.events.#{session_id}"

2. ACTIVE SESSION
   User sends message: "Help me debug this error"
     ↓
   TUI: handle_command({:send_message, text}, model)
     ↓
   Agents.LLMAgent.send_message(session_id, text)
     ↓
   LLM response arrives with streaming + tool calls
     ↓
   For each chunk:
     PubSub.broadcast("tui.events.#{session_id}", {:stream_chunk, content})
       ↓
     TUI receives via handle_info (subscribed to session topic)
       ↓
     Update: Append to streaming_message

   For each tool call:
     LLMAgent → Executor.execute(tool_call, context: context)
       ↓
     Executor.build_context(session_id)
       ├─ Session.Manager.project_root(session_id) → "/home/user/myproject"
       └─ Return: %{session_id: "...", project_root: "/home/user/myproject"}
       ↓
     Handler.execute(args, context)
       ├─ Security.validate_path(path, context.project_root)
       └─ PubSub.broadcast(session_id, {:tool_result, result})
       ↓
     TUI receives {:tool_result, ...}
       ↓
     Update: Display tool result in conversation

3. SWITCH SESSION
   User presses: Ctrl+2
     ↓
   TUI: event_to_msg(%Event.Key{key: "2", modifiers: [:ctrl]})
     ↓
   Return: {:msg, {:switch_session, 2}}
     ↓
   TUI: update({:switch_session, index}, model)
     ↓
   Model.switch_to_session(model, session_id)
     ├─ Unsubscribe from old topic: "tui.events.#{old_session_id}"
     ├─ Subscribe to new topic: "tui.events.#{new_session_id}"
     ├─ Set active_session_id: new_session_id
     ├─ Refresh conversation view from Session.State.get_messages(new_session_id)
     └─ Clear streaming state

4. CLOSE SESSION
   User presses: Ctrl+W
     ↓
   TUI: event_to_msg(%Event.Key{key: "w", modifiers: [:ctrl]})
     ↓
   Return: {:msg, :close_active_session}
     ↓
   TUI: update(:close_active_session, model)
     ↓
   handle_session_command({:close, session_id}, model)
     ↓
   Commands.execute_session({:close, session_id}, model)
     ↓
   SessionSupervisor.stop_session(session_id)
     ↓
   Before terminating:
     Session.Persistence.save(session)
       ├─ Gather data: messages, todos, config, timestamps
       ├─ Serialize to JSON: %{version: 1, id: "...", conversation: [...], ...}
       └─ Write to: ~/.jido_code/sessions/{session_id}.json
     ↓
   Supervisor terminates:
     ├─ Session.State terminates
     │    └─ Unregister from SessionProcessRegistry
     └─ Agents.LLMAgent terminates
          └─ Unregister from SessionProcessRegistry
     ↓
   SessionRegistry.unregister(session_id)
     ↓
   Return: {:session_action, {:remove_session, session_id}}
     ↓
   TUI: Model.remove_session(model, session_id)
     ├─ Remove from sessions map
     ├─ Remove from session_order
     ├─ Unsubscribe from topic
     ├─ Select adjacent session as active
     └─ Display message: "Session closed: {name}"

5. RESUME SESSION
   User: /resume 1
     ↓
   Commands.execute_resume(opts, model)
     ↓
   Session.Persistence.list_persisted()
     ├─ List files in ~/.jido_code/sessions/
     └─ Return: [%{id, name, closed_at}, ...]
     ↓
   User selects session (or by index)
     ↓
   Session.Persistence.restore(session_id)
     ├─ Read ~/.jido_code/sessions/{session_id}.json
     ├─ Parse JSON
     ├─ Validate schema version
     └─ Return: {:ok, session_data}
     ↓
   SessionSupervisor.start_session(session_data.project_path, session_data.name)
     ↓
   Session.State.restore_state(session_id, session_data)
     ├─ Restore messages: session_data.conversation
     ├─ Restore todos: session_data.todos
     └─ Restore config: session_data.config
     ↓
   Return: {:session_action, {:add_session, session}}
     ↓
   TUI: Model.add_session(model, session)
     └─ Session fully restored with conversation history intact
```

---

## PubSub Event Flow (ARCH-2 Two-Tier System)

```
EVENT SOURCE: Tool execution or LLM response
  ↓
PubSubHelpers.broadcast(session_id, message)
  ↓
Case 1: session_id is nil (legacy/global)
  ↓
  Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events", message)
  ↓
  Global subscribers receive message

Case 2: session_id is provided
  ↓
  Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events.#{session_id}", message)
    AND
  Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events", message)
  ↓
  BOTH session-specific AND global subscribers receive message

EVENT CONSUMPTION:
  ↓
TUI (subscribed to active session topic)
  ├─ Receives: {:stream_chunk, content}
  │    └─ Update: Append to streaming_message
  │
  ├─ Receives: {:tool_call, name, args, id, session_id}
  │    └─ Update: Display "Running {name}..." in status
  │
  ├─ Receives: {:tool_result, result, session_id}
  │    └─ Update: Display result in conversation
  │
  └─ Receives: {:todo_update, todos}
       └─ Update: Refresh todo list in sidebar

Inactive Sessions (not subscribed to their topic)
  ├─ Do NOT receive events for that session
  └─ Activity indicator set when events occur (via global topic)
```

---

## Data Flow: User Message → LLM → Tool → Result

```
1. USER INPUT
   User types: "Read the main.ex file"
     ↓
   TUI: {:send_message, "Read the main.ex file"}

2. MESSAGE ROUTING
   TUI → Agents.LLMAgent.send_message(active_session_id, text)
     ↓
   Session.State.append_message(session_id, user_message)
     ├─ Store in messages list
     └─ PubSub: {:new_message, user_message, session_id}

3. LLM REQUEST
   LLMAgent → JidoAI.Provider.chat(messages, tools, config)
     ↓
   LLM Provider (Anthropic/OpenAI) generates response
     ├─ Streaming chunks: "I'll read that file for you."
     └─ Tool call: read_file(%{path: "main.ex"})

4. STREAMING RESPONSE
   For each chunk from LLM:
     LLMAgent → PubSub.broadcast("tui.events.#{session_id}", {:stream_chunk, chunk})
       ↓
     TUI receives via handle_info
       ↓
     Update: model.streaming_message = (model.streaming_message || "") <> chunk
       ↓
     View: Display in conversation view

5. TOOL CALL PARSING
   LLMAgent receives tool_calls in response
     ↓
   Executor.parse_tool_calls(response)
     ↓
   Extract: %{id: "call_1", name: "read_file", arguments: %{"path" => "main.ex"}}

6. TOOL EXECUTION
   Executor.build_context(session_id)
     ↓
   Session.Manager.project_root(session_id)
     ├─ SessionRegistry.get(session_id)
     └─ Return: "/home/user/myproject"
     ↓
   Context: %{session_id: "abc123", project_root: "/home/user/myproject"}
     ↓
   Executor.execute(tool_call, context: context)
     ↓
   Registry.get("read_file")
     └─ Tool: %Tool{handler: Handlers.FileSystem.ReadFile}
     ↓
   PubSub.broadcast(session_id, {:tool_call, "read_file", %{"path" => "main.ex"}, "call_1", session_id})
     ↓
   Handlers.FileSystem.ReadFile.execute(%{"path" => "main.ex"}, context)
     ↓
   Security.validate_path("main.ex", "/home/user/myproject")
     ├─ Canonicalize: "/home/user/myproject/main.ex"
     ├─ Check boundary: ✓ within /home/user/myproject
     └─ Return: {:ok, "/home/user/myproject/main.ex"}
     ↓
   File.read("/home/user/myproject/main.ex")
     └─ Return: {:ok, "defmodule MyApp do\n..."}
     ↓
   PubSub.broadcast(session_id, {:tool_result, %Result{status: :success, output: "defmodule..."}, session_id})
     ↓
   TUI receives {:tool_result, ...}
     └─ Update: Display in conversation

7. LLM CONTINUES
   LLMAgent sends tool result back to LLM
     ↓
   LLM generates final response: "Here's the content of main.ex: ..."
     ↓
   Stream final response to user
     ↓
   Session.State.append_message(session_id, assistant_message)
     ↓
   Conversation complete
```

---

## Security Boundary Enforcement

```
USER REQUEST: "Read ../../../etc/passwd"
  ↓
LLM generates: read_file(%{path: "../../../etc/passwd"})
  ↓
Executor.execute(tool_call, context: %{session_id: "abc", project_root: "/home/user/myproject"})
  ↓
Handlers.FileSystem.ReadFile.execute(%{"path" => "../../../etc/passwd"}, context)
  ↓
Security.validate_path("../../../etc/passwd", "/home/user/myproject")
  ↓
1. Resolve symlinks: Path.expand("../../../etc/passwd", "/home/user/myproject")
     └─ Result: "/etc/passwd"
  ↓
2. Canonicalize: "/etc/passwd"
  ↓
3. Check boundary: Does "/etc/passwd" start with "/home/user/myproject"?
     └─ NO
  ↓
Return: {:error, :outside_boundary}
  ↓
Executor creates error result:
  %Result{status: :error, error: "Path outside project boundary"}
  ↓
PubSub.broadcast(session_id, {:tool_result, error_result, session_id})
  ↓
TUI displays error to user
  ↓
LLM receives error and responds: "I cannot access files outside the project directory."
```

---

## Multi-Session Concurrency

```
State at t=0:
  SessionSupervisor manages:
    - Session A (id: "abc", project: /home/user/project-a)
    - Session B (id: "def", project: /home/user/project-b)
    - Session C (id: "ghi", project: /home/user/project-c)

  TUI Model:
    - active_session_id: "abc"
    - sessions: %{"abc" => %{}, "def" => %{}, "ghi" => %{}}
    - session_order: ["abc", "def", "ghi"]
    - subscribed_to: "tui.events.abc"

User switches to Session B (Ctrl+2):
  ↓
  TUI: update({:switch_session, 2}, model)
    ├─ Unsubscribe: "tui.events.abc"
    ├─ Subscribe: "tui.events.def"
    └─ active_session_id: "def"

User in Session B sends: "Build the project"
  ↓
  LLMAgent (session_id: "def") → run_command("mix compile")
    ↓
  Executor.build_context("def")
    └─ project_root: "/home/user/project-b"
    ↓
  Handlers.Shell.RunCommand.execute(%{"command" => "mix compile"}, context)
    ├─ Runs in directory: /home/user/project-b
    ├─ PubSub.broadcast("def", {:tool_call, ...})
    └─ PubSub.broadcast("def", {:tool_result, ...})
    ↓
  TUI (subscribed to "tui.events.def") displays results

Meanwhile, Session A (inactive) receives async LLM response:
  ↓
  LLMAgent (session_id: "abc") streams response
    ↓
  PubSub.broadcast("tui.events.abc", {:stream_chunk, content})
    ↓
  TUI NOT subscribed to "tui.events.abc" → Ignores
    ↓
  Global topic also receives (via ARCH-2):
    PubSub.broadcast("tui.events", {:stream_chunk, content, "abc"})
    ↓
  TUI checks: session_id == "abc" != active_session_id ("def")
    └─ Set activity indicator: sessions["abc"].has_unread = true
```

---

## Component Responsibilities Summary

| Component | Responsibility |
|-----------|----------------|
| **SessionSupervisor** | Manages lifecycle of up to 10 concurrent sessions |
| **Session.Supervisor** | Supervises State and Agent processes for one session |
| **Session.State** | Stores per-session data (messages, todos, UI state) |
| **Agents.LLMAgent** | Handles LLM communication and tool orchestration for one session |
| **SessionRegistry** | ETS-based session metadata lookup (id → metadata) |
| **SessionProcessRegistry** | Registry for State/Agent PID lookup |
| **Session.Manager** | Helper functions for session queries (project_root, etc.) |
| **Session.Persistence** | Save/restore sessions to/from JSON files |
| **Tools.Executor** | Context building, tool execution, PubSub broadcasting |
| **Tool Handlers** | Execute tools with session context and security validation |
| **Tools.Security** | Path validation, boundary enforcement, symlink resolution |
| **PubSubHelpers** | Session-aware PubSub broadcasting (two-tier system) |
| **TUI** | User interface, event handling, view rendering, session switching |
| **Commands** | Slash command parsing and execution (/session, /resume, etc.) |

---

## References

- **[Session Architecture Guide](../../guides/developer/session-architecture.md)** - Detailed component explanations
- **[Persistence Format](../../guides/developer/persistence-format.md)** - JSON schema and versioning
- **[Adding Session Tools](../../guides/developer/adding-session-tools.md)** - Developing session-aware tools
- **[User Guide: Sessions](../../guides/user/sessions.md)** - User-facing session documentation

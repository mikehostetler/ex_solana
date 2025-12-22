# Adding Session-Aware Tools

This guide explains how to develop tools that integrate with JidoCode's multi-session architecture. Session-aware tools properly handle session context, respect project boundaries, and broadcast events to the correct session.

## Overview

**Session-aware tools** are tools that:
1. Accept a `session_id` in their execution context
2. Store per-session state (if needed)
3. Respect session-specific project boundaries
4. Broadcast events to session-specific PubSub topics
5. Work correctly with multiple concurrent sessions

## Quick Start

### Basic Session-Aware Tool

```elixir
defmodule JidoCode.Tools.Handlers.MyTool do
  @moduledoc """
  A session-aware tool that processes files within the session's project.
  """

  alias JidoCode.Tools.Security
  alias JidoCode.PubSubHelpers
  alias JidoCode.Session.State

  @doc """
  Execute the tool with session context.

  ## Context

  - `:session_id` - Session identifier for security boundary
  - `:project_root` - Project root path (auto-populated by Executor)
  """
  def execute(args, context) do
    # 1. Extract session context
    session_id = Map.get(context, :session_id)
    project_root = Map.get(context, :project_root)

    # 2. Validate path within project boundary
    path = args["path"]

    with {:ok, validated_path} <- Security.validate_path(path, project_root) do
      # 3. Perform operation
      result = File.read!(validated_path)

      # 4. Broadcast event to session topic
      broadcast_event(session_id, {:file_read, path})

      # 5. Return result
      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp broadcast_event(session_id, message) do
    PubSubHelpers.broadcast(session_id, message)
  end
end
```

### Tool with Session State

```elixir
defmodule JidoCode.Tools.Handlers.SessionStateTool do
  @moduledoc """
  A tool that stores data in Session.State.
  """

  alias JidoCode.Session.State

  def execute(args, context) do
    session_id = Map.get(context, :session_id)
    data = args["data"]

    # Store in Session.State (persisted with conversation)
    case State.update_todos(session_id, data) do
      {:ok, _state} ->
        {:ok, "Data stored successfully"}

      {:error, :not_found} ->
        {:error, "Session not found"}
    end
  end
end
```

---

## Tool Execution Context

The Executor provides a context map to every tool handler:

```elixir
context = %{
  session_id: "550e8400-e29b-41d4-a716-446655440000",
  project_root: "/home/user/projects/myapp",
  timeout: 30_000  # Optional
}
```

### Context Fields

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | `String.t()` | Unique session identifier (UUID) |
| `project_root` | `String.t()` | Absolute path to project root |
| `timeout` | `pos_integer()` | Execution timeout in milliseconds (optional) |

### Context Building

The Executor automatically builds context from `session_id`:

```elixir
# In your LLM agent or tool caller
{:ok, context} = Executor.build_context(session_id)
{:ok, results} = Executor.execute_batch(tool_calls, context: context)
```

**How it works**:
1. `Executor.build_context/2` validates the session_id (UUID format)
2. Fetches `project_root` from Session.Manager
3. Returns complete context map with both fields

**Manual context** (not recommended):
```elixir
# Executor will auto-populate project_root if missing
context = %{session_id: session_id}
Executor.execute(tool_call, context: context)
```

---

## Security: Project Boundaries

All file operations MUST validate paths are within the session's project boundary.

### Path Validation

Use `JidoCode.Tools.Security.validate_path/2`:

```elixir
alias JidoCode.Tools.Security

def execute(args, context) do
  path = args["path"]
  project_root = context.project_root

  case Security.validate_path(path, project_root) do
    {:ok, validated_path} ->
      # Safe to use validated_path
      File.read(validated_path)

    {:error, :outside_boundary} ->
      {:error, "Path outside project boundary"}

    {:error, :invalid_path} ->
      {:error, "Invalid path"}
  end
end
```

### What `validate_path/2` Checks

1. **Resolves symlinks** - Prevents symlink escape attacks
2. **Canonicalizes path** - Handles `.` and `..` properly
3. **Validates boundary** - Ensures path starts with `project_root`
4. **Blocks forbidden paths** - System directories, dotfiles, etc.

### Example Validation Flow

```
Input: "../../../etc/passwd"
Project Root: "/home/user/myproject"

1. Canonicalize: /etc/passwd
2. Check boundary: /etc/passwd does NOT start with /home/user/myproject
3. Result: {:error, :outside_boundary}
```

```
Input: "src/utils.ex"
Project Root: "/home/user/myproject"

1. Canonicalize: /home/user/myproject/src/utils.ex
2. Check boundary: ✓ starts with /home/user/myproject
3. Check forbidden: ✓ not in forbidden list
4. Result: {:ok, "/home/user/myproject/src/utils.ex"}
```

---

## PubSub Event Broadcasting

Session-aware tools broadcast events to session-specific topics for the TUI to display.

### Broadcasting Events

Use `PubSubHelpers.broadcast/2`:

```elixir
alias JidoCode.PubSubHelpers

def execute(args, context) do
  session_id = context.session_id

  # Broadcast event to session topic
  PubSubHelpers.broadcast(session_id, {:custom_event, "data"})

  {:ok, "result"}
end
```

### PubSub Topics

`PubSubHelpers.broadcast/2` routes to the correct topic:

| session_id | Topic | Purpose |
|------------|-------|---------|
| `"abc123"` | `"tui.events.abc123"` | Session-specific events |
| `nil` | `"tui.events"` | Global events (legacy) |

**Important**: When `session_id` is provided, broadcasts to **BOTH** session-specific AND global topics (ARCH-2 fix).

### Common Event Types

```elixir
# Tool execution events (automatically broadcast by Executor)
{:tool_call, tool_name, params, call_id, session_id}
{:tool_result, %Result{}, session_id}

# Custom tool events
{:file_read, path}
{:file_written, path, bytes}
{:search_complete, results_count}
{:custom_event, data}

# State update events
{:todo_update, todos}
{:config_changed, old_config, new_config}
```

### Example: File Write Tool

```elixir
defmodule JidoCode.Tools.Handlers.FileSystem.WriteFile do
  alias JidoCode.PubSubHelpers

  def execute(%{"path" => path, "content" => content}, context) do
    session_id = context.session_id
    project_root = context.project_root

    with {:ok, validated_path} <- Security.validate_path(path, project_root),
         :ok <- File.write(validated_path, content) do

      # Broadcast file write event
      bytes = byte_size(content)
      PubSubHelpers.broadcast(session_id, {:file_written, path, bytes})

      {:ok, "Wrote #{bytes} bytes to #{path}"}
    end
  end
end
```

---

## Session State Integration

Tools can store data in `Session.State` for persistence and retrieval.

### Session.State Structure

```elixir
%{
  session_id: "abc123",
  messages: [],          # Conversation history
  reasoning_steps: [],   # Chain-of-thought steps
  tool_calls: [],        # Tool execution records
  todos: [],             # Task tracking list
  scroll_offset: 0,      # UI state
  streaming_message: nil,
  is_streaming: false
}
```

### Storing Data

```elixir
alias JidoCode.Session.State

def execute(args, context) do
  session_id = context.session_id
  todos = args["todos"]

  # Update todos list in Session.State
  case State.update_todos(session_id, todos) do
    {:ok, _state} ->
      {:ok, "Todos updated"}

    {:error, :not_found} ->
      {:error, "Session not found"}
  end
end
```

### Retrieving Data

```elixir
def execute(_args, context) do
  session_id = context.session_id

  # Get current todos
  case State.get_todos(session_id) do
    {:ok, todos} ->
      {:ok, format_todos(todos)}

    {:error, :not_found} ->
      {:error, "Session not found"}
  end
end
```

### State API Reference

| Function | Description |
|----------|-------------|
| `get_state(session_id)` | Get full state |
| `get_messages(session_id)` | Get conversation history |
| `get_todos(session_id)` | Get todo list |
| `update_todos(session_id, todos)` | Update todo list |
| `append_message(session_id, msg)` | Add message to history |
| `add_reasoning_step(session_id, step)` | Add reasoning step |
| `add_tool_call(session_id, call)` | Add tool call record |
| `set_scroll_offset(session_id, offset)` | Update scroll position |

---

## Example: Todo Tool (Session-Aware)

The `todo_write` tool is a complete example of session integration:

```elixir
defmodule JidoCode.Tools.Handlers.Todo do
  alias JidoCode.PubSubHelpers
  alias JidoCode.Session.State

  def execute(%{"todos" => todos}, context) when is_list(todos) do
    with {:ok, validated_todos} <- validate_todos(todos) do
      session_id = Map.get(context, :session_id)

      # 1. Store in Session.State if session_id available
      store_todos(validated_todos, session_id)

      # 2. Broadcast update via PubSub
      broadcast_todos(validated_todos, session_id)

      # 3. Return success message
      {:ok, format_success_message(validated_todos)}
    end
  end

  defp store_todos(_todos, nil), do: :ok

  defp store_todos(todos, session_id) do
    case State.update_todos(session_id, todos) do
      {:ok, _state} ->
        :ok

      {:error, :not_found} ->
        Logger.warning("Session not found: #{session_id}")
        :ok
    end
  end

  defp broadcast_todos(todos, session_id) do
    message = {:todo_update, todos}
    PubSubHelpers.broadcast(session_id, message)
  end
end
```

**Key Points**:
1. **Graceful degradation**: Works even if `session_id` is nil (stores nothing, broadcasts to global)
2. **State persistence**: Stores in `Session.State` for save/restore
3. **Event broadcasting**: Notifies TUI of updates via PubSub
4. **Validation**: Validates todo format before storing

---

## Testing Session-Aware Tools

### Unit Test Template

```elixir
defmodule JidoCode.Tools.Handlers.MyToolTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Handlers.MyTool

  describe "execute/2 with session context" do
    test "executes successfully with valid session_id" do
      context = %{
        session_id: "test-session-id",
        project_root: "/tmp/test-project"
      }

      args = %{"path" => "test.txt"}

      assert {:ok, result} = MyTool.execute(args, context)
    end

    test "validates path is within project boundary" do
      context = %{
        session_id: "test-session-id",
        project_root: "/tmp/test-project"
      }

      # Attempt path traversal
      args = %{"path" => "../../../etc/passwd"}

      assert {:error, reason} = MyTool.execute(args, context)
      assert reason =~ "boundary"
    end

    test "works without session_id (legacy mode)" do
      context = %{project_root: "/tmp/test-project"}
      args = %{"path" => "test.txt"}

      assert {:ok, result} = MyTool.execute(args, context)
    end
  end
end
```

### Integration Test Template

```elixir
defmodule JidoCode.Tools.Integration.MyToolTest do
  use ExUnit.Case, async: false

  alias JidoCode.SessionSupervisor
  alias JidoCode.Tools.Executor

  setup do
    # Start a real session
    {:ok, session} = SessionSupervisor.start_session("/tmp/test-project")

    on_exit(fn ->
      SessionSupervisor.stop_session(session.id)
    end)

    {:ok, session: session}
  end

  test "tool executes within session context", %{session: session} do
    tool_call = %{
      id: "call-1",
      name: "my_tool",
      arguments: %{"path" => "test.txt"}
    }

    # Build context from session
    {:ok, context} = Executor.build_context(session.id)

    # Execute with session context
    {:ok, result} = Executor.execute(tool_call, context: context)

    assert result.status == :success
  end
end
```

### Testing PubSub Events

```elixir
test "broadcasts event to session topic", %{session: session} do
  # Subscribe to session topic
  topic = "tui.events.#{session.id}"
  Phoenix.PubSub.subscribe(JidoCode.PubSub, topic)

  # Execute tool
  context = %{session_id: session.id, project_root: "/tmp/test"}
  MyTool.execute(%{}, context)

  # Assert event received
  assert_receive {:custom_event, _data}, 1000
end
```

---

## Error Handling

### Session Not Found

When a session doesn't exist, tools should handle gracefully:

```elixir
def execute(args, context) do
  session_id = context.session_id

  case State.get_state(session_id) do
    {:ok, state} ->
      # Process normally
      {:ok, "result"}

    {:error, :not_found} ->
      # Session doesn't exist - decide how to handle
      # Option 1: Return error
      {:error, "Session not found: #{session_id}"}

      # Option 2: Work without session state (degraded mode)
      # {:ok, "result (no session)"}
  end
end
```

### Missing Context Fields

Always provide defaults for optional context fields:

```elixir
def execute(args, context) do
  session_id = Map.get(context, :session_id)
  project_root = Map.get(context, :project_root, File.cwd!())
  timeout = Map.get(context, :timeout, 30_000)

  # ...
end
```

### Path Validation Failures

```elixir
case Security.validate_path(path, project_root) do
  {:ok, validated_path} ->
    # Proceed with validated path

  {:error, :outside_boundary} ->
    {:error, "Path '#{path}' is outside project boundary: #{project_root}"}

  {:error, :invalid_path} ->
    {:error, "Invalid path: #{path}"}

  {:error, :forbidden_path} ->
    {:error, "Access to path '#{path}' is forbidden"}
end
```

---

## Best Practices

### 1. Always Validate Paths

**DO**:
```elixir
def execute(%{"path" => path}, context) do
  project_root = context.project_root

  with {:ok, validated_path} <- Security.validate_path(path, project_root) do
    File.read(validated_path)
  end
end
```

**DON'T**:
```elixir
def execute(%{"path" => path}, _context) do
  # UNSAFE: No boundary validation
  File.read(path)
end
```

### 2. Use PubSubHelpers for Broadcasting

**DO**:
```elixir
PubSubHelpers.broadcast(session_id, {:event, data})
# Automatically routes to correct topic
```

**DON'T**:
```elixir
# Manual topic construction can break with session routing changes
Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events.#{session_id}", {:event, data})
```

### 3. Handle Nil session_id Gracefully

**DO**:
```elixir
def execute(args, context) do
  session_id = Map.get(context, :session_id)

  # Works with or without session_id
  result = perform_operation(args)

  # Broadcast (works with nil)
  PubSubHelpers.broadcast(session_id, {:event, result})

  {:ok, result}
end
```

**DON'T**:
```elixir
def execute(args, context) do
  # Crashes if session_id is nil
  State.update_todos(context.session_id, todos)
end
```

### 4. Store Minimal State

Only store state that needs to persist across requests:

**DO**:
```elixir
# Store task list (needs persistence)
State.update_todos(session_id, todos)
```

**DON'T**:
```elixir
# Don't store ephemeral data
State.store_temp_file_content(session_id, content)
# Use in-memory cache or temp files instead
```

### 5. Document Session Requirements

Clearly document whether your tool requires a session:

```elixir
@moduledoc """
A session-aware file reader.

## Context Requirements

- `:session_id` - (required) Session identifier for boundary enforcement
- `:project_root` - (auto-populated) Project root path

## Behavior

Without a session_id, the tool will return an error.
"""
```

---

## Migration Guide: Making Existing Tools Session-Aware

### Step 1: Update Function Signature

**Before**:
```elixir
def execute(%{"path" => path}, _opts) do
  File.read(path)
end
```

**After**:
```elixir
def execute(%{"path" => path}, context) do
  project_root = Map.get(context, :project_root)

  with {:ok, validated_path} <- Security.validate_path(path, project_root) do
    File.read(validated_path)
  end
end
```

### Step 2: Add Path Validation

```elixir
# Add at top of module
alias JidoCode.Tools.Security

# In execute/2
with {:ok, validated_path} <- Security.validate_path(path, project_root) do
  # Your existing code using validated_path
end
```

### Step 3: Add Event Broadcasting (Optional)

```elixir
alias JidoCode.PubSubHelpers

def execute(args, context) do
  session_id = Map.get(context, :session_id)

  result = perform_operation(args)

  # Broadcast event
  PubSubHelpers.broadcast(session_id, {:operation_complete, result})

  {:ok, result}
end
```

### Step 4: Update Tests

Add session context to your tests:

```elixir
test "reads file within project" do
  context = %{
    session_id: "test-session",
    project_root: "/tmp/test-project"
  }

  args = %{"path" => "test.txt"}

  assert {:ok, _content} = MyTool.execute(args, context)
end
```

---

## Architecture Reference

### Tool Execution Flow

```
User Input → LLM Agent
  ↓
LLM generates tool calls
  ↓
Executor.parse_tool_calls(response)
  ↓
Executor.build_context(session_id)  # Fetches project_root from Session.Manager
  ↓
Executor.execute_batch(tool_calls, context: context)
  ↓
For each tool call:
  1. Validate tool exists (Registry.get)
  2. Validate arguments (Tool.validate_args)
  3. Broadcast {:tool_call, ...} to session topic
  4. Call handler.execute(args, context)
  5. Broadcast {:tool_result, ...} to session topic
  ↓
Return results to LLM Agent
```

### Session Context Flow

```
SessionSupervisor.start_session(path)
  ↓
Session created with:
  - id (UUID)
  - project_path
  - config
  ↓
Session.Manager registers:
  - SessionRegistry: session metadata
  - SessionProcessRegistry: {:state, session_id} → State PID
  ↓
Tool execution:
  - Executor.build_context(session_id)
  - Session.Manager.project_root(session_id) → path
  - Tools use context.project_root for validation
```

---

## Common Patterns

### Pattern 1: File Operation Tool

```elixir
defmodule JidoCode.Tools.Handlers.FileOperation do
  alias JidoCode.Tools.Security
  alias JidoCode.PubSubHelpers

  def execute(%{"path" => path, "action" => action}, context) do
    session_id = context.session_id
    project_root = context.project_root

    with {:ok, validated_path} <- Security.validate_path(path, project_root),
         {:ok, result} <- perform_action(action, validated_path) do

      PubSubHelpers.broadcast(session_id, {:file_operation, action, path})
      {:ok, result}
    end
  end
end
```

### Pattern 2: State Update Tool

```elixir
defmodule JidoCode.Tools.Handlers.StateUpdate do
  alias JidoCode.Session.State
  alias JidoCode.PubSubHelpers

  def execute(%{"data" => data}, context) do
    session_id = context.session_id

    with {:ok, _state} <- State.update_todos(session_id, data) do
      PubSubHelpers.broadcast(session_id, {:state_updated, :todos})
      {:ok, "State updated"}
    end
  end
end
```

### Pattern 3: Read-Only Query Tool

```elixir
defmodule JidoCode.Tools.Handlers.Query do
  alias JidoCode.Session.State

  def execute(%{"query" => query}, context) do
    session_id = context.session_id

    # Query session state (no mutation, no broadcast needed)
    case State.get_messages(session_id) do
      {:ok, messages} ->
        filtered = filter_messages(messages, query)
        {:ok, filtered}

      {:error, :not_found} ->
        {:error, "Session not found"}
    end
  end
end
```

---

## References

- **[Session Architecture](./session-architecture.md)** - Complete multi-session architecture overview
- **[Persistence Format](./persistence-format.md)** - Session save/restore format
- **Implementation**: `lib/jido_code/tools/executor.ex` - Tool execution with context
- **Example Tool**: `lib/jido_code/tools/handlers/todo.ex` - Complete session-aware tool
- **Security**: `lib/jido_code/tools/security.ex` - Path validation and boundaries
- **PubSub**: `lib/jido_code/pubsub_helpers.ex` - Session-aware event broadcasting
- **Session State**: `lib/jido_code/session/state.ex` - Per-session state management

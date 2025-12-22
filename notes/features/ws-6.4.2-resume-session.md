# Feature Plan: WS-6.4.2 Resume Session

**Phase**: 6 (Work Session Management)
**Task**: 6.4.2 - Resume Session
**Module**: `JidoCode.Session.Persistence`
**Status**: Planning

## Problem Statement

Once a session has been persisted to disk (Task 6.2), users need a way to restore it to a fully running state. The resume operation must:

1. Load persisted session data from disk
2. Validate the project path still exists
3. Rebuild the Session struct from persisted data
4. Start all session processes (Manager, State, LLMAgent) via SessionSupervisor
5. Restore conversation history and todos to the running Session.State
6. Clean up the persisted file (session is now active again)
7. Handle error cases gracefully (missing files, invalid paths, process startup failures)

This enables users to close sessions, shut down JidoCode, and later resume exactly where they left off with full conversation history and task context.

## Solution Overview

Implement a `resume/1` function in the `Persistence` module that orchestrates the complete restoration flow. The function will leverage existing infrastructure:

- **Load Phase**: Use existing `load/1` and `deserialize_session/1` to read persisted data
- **Validation Phase**: Check that the project path still exists on the filesystem
- **Rebuild Phase**: Construct a new Session struct from persisted metadata
- **Start Phase**: Use `SessionSupervisor.start_session/1` to start all processes
- **Restore Phase**: Populate Session.State with conversation and todos
- **Cleanup Phase**: Delete persisted file once session is active

The implementation follows the existing error handling patterns using tagged tuples and `with` pipelines.

## Technical Details

### Current Session Architecture

#### Session Struct (`JidoCode.Session`)

The Session struct contains:
- `id` - RFC 4122 UUID v4
- `name` - Display name
- `project_path` - Absolute path to project directory
- `config` - Map with `provider`, `model`, `temperature`, `max_tokens`
- `created_at` - DateTime struct
- `updated_at` - DateTime struct

**Creation**: `Session.new/1` validates the project path and creates a Session struct.

#### Process Hierarchy

```
SessionSupervisor (DynamicSupervisor)
└── Session.Supervisor (:one_for_all)
    ├── Session.Manager (Lua sandbox, path validation)
    ├── Session.State (conversation, todos, UI state)
    └── LLMAgent (AI agent for chat)
```

All processes register in `SessionProcessRegistry` with keys:
- `{:session, session_id}` - Session.Supervisor
- `{:manager, session_id}` - Session.Manager
- `{:state, session_id}` - Session.State
- `{:agent, session_id}` - LLMAgent

#### Starting a Session

`SessionSupervisor.start_session/1`:
1. Registers Session in SessionRegistry (validates limits, duplicates)
2. Starts Session.Supervisor as child of SessionSupervisor
3. Session.Supervisor starts Manager, State, and Agent
4. All processes initialize with the Session struct

**Key Point**: `Session.new/1` validates the project path exists and is a directory. We can reuse this for resume.

#### Session.State Runtime State

Session.State GenServer maintains:
- `session` - The Session struct (for backwards compatibility)
- `session_id` - Session ID
- `messages` - List of conversation messages (reversed for O(1) prepend)
- `reasoning_steps` - Chain-of-thought steps
- `tool_calls` - Tool execution records
- `todos` - Task list
- `scroll_offset` - UI scroll position
- `streaming_message` - Current streaming content
- `streaming_message_id` - ID of streaming message
- `is_streaming` - Boolean streaming flag

**Important**: Messages are stored in reverse order internally and reversed when read via `get_messages/1`.

#### Adding Messages and Todos

Client functions for restoring state:
- `Session.State.append_message(session_id, message)` - Adds a single message
- `Session.State.update_todos(session_id, todos)` - Replaces entire todo list

Message format:
```elixir
%{
  id: String.t(),
  role: :user | :assistant | :system | :tool,
  content: String.t(),
  timestamp: DateTime.t()
}
```

Todo format:
```elixir
%{
  content: String.t(),
  status: :pending | :in_progress | :completed,
  active_form: String.t()  # Optional, falls back to content
}
```

### Persisted Data Format

The `load/1` function returns a map with:
- `:id` - Session ID (string)
- `:name` - Session name (string)
- `:project_path` - Project directory (string)
- `:config` - Configuration map (string keys)
- `:created_at` - DateTime struct
- `:updated_at` - DateTime struct
- `:conversation` - List of message maps (with atom keys)
- `:todos` - List of todo maps (with atom keys)

Messages and todos are already deserialized to the runtime format by `deserialize_session/1`.

### Implementation Strategy

#### Function Signature

```elixir
@spec resume(String.t()) :: {:ok, Session.t()} | {:error, term()}
def resume(session_id) when is_binary(session_id)
```

#### Implementation Flow

```elixir
def resume(session_id) when is_binary(session_id) do
  with {:ok, persisted} <- load(session_id),
       :ok <- validate_project_path(persisted.project_path),
       {:ok, session} <- rebuild_session(persisted),
       {:ok, _pid} <- start_session_processes(session),
       :ok <- restore_conversation(session.id, persisted.conversation),
       :ok <- restore_todos(session.id, persisted.todos),
       :ok <- delete_persisted(session_id) do
    {:ok, session}
  end
end
```

#### Helper Functions

##### 1. `validate_project_path/1`

Validates that the project path still exists and is a directory.

```elixir
@spec validate_project_path(String.t()) :: :ok | {:error, atom()}
defp validate_project_path(path) do
  cond do
    not File.exists?(path) ->
      {:error, :project_path_not_found}

    not File.dir?(path) ->
      {:error, :project_path_not_directory}

    true ->
      :ok
  end
end
```

**Note**: We don't need to re-validate path traversal or symlinks here because:
1. The path was validated when the session was originally created
2. We're checking existence, not using the path for operations yet
3. `SessionSupervisor.start_session/1` will fail if path validation fails

##### 2. `rebuild_session/1`

Reconstructs a Session struct from persisted data. The config map in persisted data has string keys, but Session expects string keys for the provider (which is converted to atom by Session.Supervisor when starting the agent).

```elixir
@spec rebuild_session(map()) :: {:ok, Session.t()} | {:error, term()}
defp rebuild_session(persisted) do
  # Convert string-keyed config to atom-keyed (Session expects atom keys)
  config = %{
    provider: Map.get(persisted.config, "provider"),
    model: Map.get(persisted.config, "model"),
    temperature: Map.get(persisted.config, "temperature"),
    max_tokens: Map.get(persisted.config, "max_tokens")
  }

  session = %Session{
    id: persisted.id,
    name: persisted.name,
    project_path: persisted.project_path,
    config: config,
    created_at: persisted.created_at,
    updated_at: DateTime.utc_now()
  }

  # Validate the reconstructed session
  Session.validate(session)
end
```

**Note**: We update `updated_at` to reflect the resume time, not the original timestamp.

##### 3. `start_session_processes/1`

Starts the session processes via SessionSupervisor.

```elixir
@spec start_session_processes(Session.t()) :: {:ok, pid()} | {:error, term()}
defp start_session_processes(session) do
  alias JidoCode.SessionSupervisor
  SessionSupervisor.start_session(session)
end
```

**Error Handling**:
- `:session_limit_reached` - Already 10 sessions active
- `:session_exists` - Session ID collision (extremely unlikely with UUIDs)
- `:project_already_open` - Another active session for this project path
- Other supervisor startup errors

##### 4. `restore_conversation/2`

Restores messages to Session.State.

```elixir
@spec restore_conversation(String.t(), [map()]) :: :ok | {:error, term()}
defp restore_conversation(session_id, messages) do
  alias JidoCode.Session.State

  # Messages are already deserialized with proper atom keys and DateTime structs
  Enum.reduce_while(messages, :ok, fn message, :ok ->
    case State.append_message(session_id, message) do
      {:ok, _state} -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, {:restore_message_failed, reason}}}
    end
  end)
end
```

**Note**: `append_message/2` expects messages with atom-keyed roles, which is what `deserialize_session/1` provides.

##### 5. `restore_todos/2`

Restores todos to Session.State.

```elixir
@spec restore_todos(String.t(), [map()]) :: :ok | {:error, term()}
defp restore_todos(session_id, todos) do
  alias JidoCode.Session.State

  case State.update_todos(session_id, todos) do
    {:ok, _state} -> :ok
    {:error, reason} -> {:error, {:restore_todos_failed, reason}}
  end
end
```

**Note**: Todos are already deserialized with atom status values.

##### 6. `delete_persisted/1`

Deletes the persisted session file.

```elixir
@spec delete_persisted(String.t()) :: :ok | {:error, term()}
defp delete_persisted(session_id) do
  path = session_file(session_id)

  case File.rm(path) do
    :ok -> :ok
    {:error, :enoent} -> :ok  # Already deleted, that's fine
    {:error, reason} -> {:error, {:delete_failed, reason}}
  end
end
```

**Note**: If deletion fails, we log a warning but don't fail the resume operation. The session is active, which is what matters. The persisted file can be cleaned up manually or on next resume attempt.

### Error Handling

The `with` pipeline provides clean error propagation. Possible error tuples:

From `load/1`:
- `{:error, :not_found}` - Session file doesn't exist
- `{:error, {:invalid_json, error}}` - JSON parsing failed
- `{:error, reason}` - Validation or deserialization failed

From `validate_project_path/1`:
- `{:error, :project_path_not_found}` - Path doesn't exist
- `{:error, :project_path_not_directory}` - Path is not a directory

From `rebuild_session/1`:
- `{:error, [reasons]}` - Session validation failed (from `Session.validate/1`)

From `start_session_processes/1`:
- `{:error, :session_limit_reached}` - 10 sessions already running
- `{:error, :session_exists}` - Session ID collision
- `{:error, :project_already_open}` - Another session for this path

From `restore_conversation/2`:
- `{:error, {:restore_message_failed, reason}}` - Message restore failed

From `restore_todos/2`:
- `{:error, {:restore_todos_failed, reason}}` - Todo restore failed

From `delete_persisted/1`:
- `{:error, {:delete_failed, reason}}` - File deletion failed

**Cleanup on Failure**: If any step after `start_session_processes/1` fails, we should stop the session:

```elixir
def resume(session_id) when is_binary(session_id) do
  with {:ok, persisted} <- load(session_id),
       :ok <- validate_project_path(persisted.project_path),
       {:ok, session} <- rebuild_session(persisted),
       {:ok, _pid} <- start_session_processes(session),
       :ok <- restore_state_or_cleanup(session.id, persisted) do
    {:ok, session}
  end
end

defp restore_state_or_cleanup(session_id, persisted) do
  with :ok <- restore_conversation(session_id, persisted.conversation),
       :ok <- restore_todos(session_id, persisted.todos),
       :ok <- delete_persisted(session_id) do
    :ok
  else
    error ->
      # State restore failed, stop the session
      alias JidoCode.SessionSupervisor
      SessionSupervisor.stop_session(session_id)
      error
  end
end
```

### Edge Cases

1. **Session file already deleted**: `load/1` returns `{:error, :not_found}` - user-friendly error
2. **Project path moved/deleted**: `validate_project_path/1` returns error - inform user
3. **Session limit reached**: `start_session_processes/1` fails - user must close a session first
4. **Project path already open**: Another session for this path exists - user must close it first
5. **Corrupted session data**: `deserialize_session/1` validates and returns error
6. **Process startup failure**: `start_session_processes/1` cleans up registry entry
7. **State restore failure**: Session is stopped to prevent inconsistent state

## Implementation Plan

### Step 1: Implement Path Validation (6.4.3 - pulled in)

```elixir
@spec validate_project_path(String.t()) :: :ok | {:error, atom()}
defp validate_project_path(path) do
  cond do
    not File.exists?(path) ->
      {:error, :project_path_not_found}

    not File.dir?(path) ->
      {:error, :project_path_not_directory}

    true ->
      :ok
  end
end
```

### Step 2: Implement Session Rebuild

```elixir
@spec rebuild_session(map()) :: {:ok, Session.t()} | {:error, term()}
defp rebuild_session(persisted) do
  config = %{
    provider: Map.get(persisted.config, "provider"),
    model: Map.get(persisted.config, "model"),
    temperature: Map.get(persisted.config, "temperature"),
    max_tokens: Map.get(persisted.config, "max_tokens")
  }

  session = %Session{
    id: persisted.id,
    name: persisted.name,
    project_path: persisted.project_path,
    config: config,
    created_at: persisted.created_at,
    updated_at: DateTime.utc_now()
  }

  Session.validate(session)
end
```

### Step 3: Implement Conversation Restore

```elixir
@spec restore_conversation(String.t(), [map()]) :: :ok | {:error, term()}
defp restore_conversation(session_id, messages) do
  alias JidoCode.Session.State

  Enum.reduce_while(messages, :ok, fn message, :ok ->
    case State.append_message(session_id, message) do
      {:ok, _state} -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, {:restore_message_failed, reason}}}
    end
  end)
end
```

### Step 4: Implement Todos Restore

```elixir
@spec restore_todos(String.t(), [map()]) :: :ok | {:error, term()}
defp restore_todos(session_id, todos) do
  alias JidoCode.Session.State

  case State.update_todos(session_id, todos) do
    {:ok, _state} -> :ok
    {:error, reason} -> {:error, {:restore_todos_failed, reason}}
  end
end
```

### Step 5: Implement File Cleanup

```elixir
@spec delete_persisted(String.t()) :: :ok | {:error, term()}
defp delete_persisted(session_id) do
  path = session_file(session_id)

  case File.rm(path) do
    :ok ->
      :ok
    {:error, :enoent} ->
      :ok
    {:error, reason} ->
      Logger.warning("Failed to delete persisted session #{session_id}: #{inspect(reason)}")
      {:error, {:delete_failed, reason}}
  end
end
```

### Step 6: Implement Main Resume Function

```elixir
@doc """
Resumes a persisted session, restoring it to fully running state.

Performs the following steps:
1. Loads persisted session data from disk
2. Validates project path still exists
3. Rebuilds Session struct from persisted data
4. Starts session processes (Manager, State, Agent)
5. Restores conversation history and todos
6. Deletes persisted file (session is now active)

## Parameters

- `session_id` - The session ID (must be valid UUID v4 format)

## Returns

- `{:ok, session}` - Session resumed successfully
- `{:error, :not_found}` - No persisted session with this ID
- `{:error, :project_path_not_found}` - Project path no longer exists
- `{:error, :project_path_not_directory}` - Project path is not a directory
- `{:error, :session_limit_reached}` - Already 10 sessions running
- `{:error, :project_already_open}` - Another session for this project
- `{:error, reason}` - Other errors (deserialization, validation, etc.)

## Examples

    iex> Persistence.resume("550e8400-e29b-41d4-a716-446655440000")
    {:ok, %Session{...}}

    iex> Persistence.resume("nonexistent")
    {:error, :not_found}

## Cleanup on Failure

If session processes start successfully but state restoration fails,
the session is automatically stopped to prevent inconsistent state.
"""
@spec resume(String.t()) :: {:ok, Session.t()} | {:error, term()}
def resume(session_id) when is_binary(session_id) do
  with {:ok, persisted} <- load(session_id),
       :ok <- validate_project_path(persisted.project_path),
       {:ok, session} <- rebuild_session(persisted),
       {:ok, _pid} <- start_session_processes(session),
       :ok <- restore_state_or_cleanup(session.id, persisted) do
    {:ok, session}
  end
end

defp start_session_processes(session) do
  alias JidoCode.SessionSupervisor
  SessionSupervisor.start_session(session)
end

defp restore_state_or_cleanup(session_id, persisted) do
  with :ok <- restore_conversation(session_id, persisted.conversation),
       :ok <- restore_todos(session_id, persisted.todos),
       :ok <- delete_persisted(session_id) do
    :ok
  else
    error ->
      alias JidoCode.SessionSupervisor
      SessionSupervisor.stop_session(session_id)
      error
  end
end
```

### Step 7: Write Comprehensive Tests

Test file: `test/jido_code/session/persistence_resume_test.exs`

Test cases:
1. **Happy path**: Resume a persisted session successfully
2. **Session not found**: Return `{:error, :not_found}`
3. **Project path deleted**: Return `{:error, :project_path_not_found}`
4. **Project path not directory**: Return `{:error, :project_path_not_directory}`
5. **Session limit reached**: Return `{:error, :session_limit_reached}`
6. **Project already open**: Return `{:error, :project_already_open}`
7. **Conversation restored**: Verify messages in Session.State
8. **Todos restored**: Verify todos in Session.State
9. **File deleted**: Verify persisted file removed after resume
10. **Cleanup on failure**: Verify session stopped if state restore fails
11. **Config restored**: Verify LLM config matches persisted values
12. **Timestamps preserved**: Verify created_at preserved, updated_at updated

## Success Criteria

1. `resume/1` function successfully loads and restores persisted sessions
2. All session processes (Manager, State, Agent) are started and registered
3. Conversation history is fully restored to Session.State
4. Todos are fully restored to Session.State
5. Persisted file is deleted after successful resume
6. Project path validation prevents resuming deleted/moved projects
7. Session is cleaned up if state restoration fails
8. All error cases are handled gracefully with descriptive errors
9. Comprehensive test coverage (12+ test cases)
10. Documentation includes examples and error descriptions

## Testing Strategy

### Unit Tests

Test each helper function in isolation:

```elixir
describe "validate_project_path/1" do
  test "returns :ok for existing directory"
  test "returns {:error, :project_path_not_found} for missing path"
  test "returns {:error, :project_path_not_directory} for file"
end

describe "rebuild_session/1" do
  test "rebuilds valid session from persisted data"
  test "updates updated_at timestamp"
  test "preserves created_at timestamp"
  test "converts string config keys to atoms"
  test "returns error for invalid persisted data"
end

describe "restore_conversation/2" do
  test "restores all messages in order"
  test "handles empty conversation"
  test "returns error if message restore fails"
end

describe "restore_todos/2" do
  test "restores todos with correct status"
  test "handles empty todo list"
  test "returns error if todo restore fails"
end

describe "delete_persisted/1" do
  test "deletes session file"
  test "succeeds if file already deleted"
  test "returns error for permission issues"
end
```

### Integration Tests

Test the full resume flow:

```elixir
describe "resume/1" do
  test "resumes persisted session with full state restoration" do
    # 1. Create and start session
    # 2. Add messages and todos
    # 3. Save session
    # 4. Stop session
    # 5. Resume session
    # 6. Verify session running
    # 7. Verify messages restored
    # 8. Verify todos restored
    # 9. Verify file deleted
  end

  test "returns error for non-existent session"
  test "returns error if project path deleted"
  test "returns error if session limit reached"
  test "returns error if project already open"

  test "cleans up session if conversation restore fails" do
    # Mock State.append_message to fail
    # Verify session is stopped
    # Verify error returned
  end

  test "cleans up session if todos restore fails" do
    # Mock State.update_todos to fail
    # Verify session stopped
    # Verify error returned
  end
end
```

### Edge Case Tests

```elixir
describe "resume/1 edge cases" do
  test "handles session with no messages"
  test "handles session with no todos"
  test "handles session with very long conversation (1000+ messages)"
  test "handles session with special characters in project path"
  test "handles session with symlinked project path"
end
```

## Dependencies

- `JidoCode.Session` - Session struct and validation
- `JidoCode.Session.State` - Message and todo restoration
- `JidoCode.SessionSupervisor` - Process startup and cleanup
- `JidoCode.SessionRegistry` - Session registration checks
- Task 6.4.1 (Load Persisted Session) - `load/1` and `deserialize_session/1` functions

## Future Enhancements

1. **Partial Resume**: Resume without conversation history to reduce memory
2. **Resume Confirmation**: Ask user before resuming if project path changed
3. **Resume Notifications**: PubSub event for resume success/failure
4. **Resume Metrics**: Track resume time, success rate, error types
5. **Auto-Resume**: Automatically resume last session on startup
6. **Resume Migration**: Handle schema version upgrades during resume

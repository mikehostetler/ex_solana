# WS-6.2.1: Save Session State

**Branch:** `feature/ws-6.2.1-save-session-state`
**Phase:** 6 - Session Persistence
**Task:** 6.2.1 - Save Session State

---

## Objective

Implement saving session state to JSON file, including conversation history and todos.

---

## Implementation Plan

### 1. Implement save/1 (6.2.1.1)
```elixir
@spec save(String.t()) :: {:ok, String.t()} | {:error, term()}
def save(session_id) when is_binary(session_id) do
  with {:ok, state} <- Session.State.get_state(session_id),
       persisted = build_persisted_session(state),
       :ok <- write_session_file(session_id, persisted) do
    {:ok, session_file(session_id)}
  end
end
```

### 2. Implement build_persisted_session/1 (6.2.1.2)
```elixir
defp build_persisted_session(state) do
  session = state.session
  %{
    version: schema_version(),
    id: session.id,
    name: session.name,
    project_path: session.project_path,
    config: serialize_config(session.config),
    created_at: DateTime.to_iso8601(session.created_at),
    updated_at: DateTime.to_iso8601(session.updated_at),
    closed_at: DateTime.to_iso8601(DateTime.utc_now()),
    conversation: Enum.map(state.messages, &serialize_message/1),
    todos: Enum.map(state.todos, &serialize_todo/1)
  }
end
```

### 3. Implement serialize_message/1 and serialize_todo/1
```elixir
defp serialize_message(msg) do
  %{
    id: msg.id,
    role: to_string(msg.role),
    content: msg.content,
    timestamp: DateTime.to_iso8601(msg.timestamp)
  }
end

defp serialize_todo(todo) do
  %{
    content: todo.content,
    status: to_string(todo.status),
    active_form: Map.get(todo, :active_form, todo.content)
  }
end
```

### 4. Implement atomic write (6.2.1.3)
```elixir
defp write_session_file(session_id, persisted) do
  :ok = ensure_sessions_dir()
  path = session_file(session_id)
  temp_path = "#{path}.tmp"

  case Jason.encode(persisted, pretty: true) do
    {:ok, json} ->
      with :ok <- File.write(temp_path, json),
           :ok <- File.rename(temp_path, path) do
        :ok
      else
        {:error, reason} ->
          File.rm(temp_path)
          {:error, reason}
      end
    {:error, reason} ->
      {:error, {:json_encode_error, reason}}
  end
end
```

### 5. Write Unit Tests (6.2.1.5)
- Test save/1 creates JSON file
- Test save includes all session data
- Test save includes conversation history
- Test save includes todo list
- Test save writes atomically
- Test error handling for missing session

---

## Files to Modify

**Modified Files:**
- `lib/jido_code/session/persistence.ex` - Add save functions
- `test/jido_code/session/persistence_test.exs` - Add save tests

---

## Success Criteria

1. `save/1` creates JSON file with all session data
2. Conversation history serialized correctly
3. Todos serialized correctly (with active_form)
4. Atomic write prevents partial files
5. All unit tests passing
6. No credo issues

# Feature: WS-3.2.6 Todo Handler Session State Integration

## Problem Statement

The Todo handler currently broadcasts todo updates via PubSub but does not persist the todos in session-specific state. This means:
- Todos are only available through PubSub subscription
- No way to retrieve current todos for a session
- Todos are lost when TUI reconnects or misses PubSub messages

Task 3.2.6 requires updating the Todo handler to store todos in Session.State.

## Current State

### Current Handler Pattern

```elixir
def execute(%{"todos" => todos}, context) when is_list(todos) do
  with {:ok, validated_todos} <- validate_todos(todos) do
    session_id = Map.get(context, :session_id)
    broadcast_todos(validated_todos, session_id)  # Only broadcasts
    {:ok, format_success_message(validated_todos)}
  end
end
```

### Available Session.State API

Session.State already has `update_todos/2`:
```elixir
@spec update_todos(String.t(), [todo()]) :: {:ok, state()} | {:error, :not_found}
def update_todos(session_id, todos) when is_binary(session_id) and is_list(todos)
```

## Solution Overview

Update the Todo handler to:
1. Validate todos (existing)
2. Store validated todos in Session.State via `update_todos/2` when session_id present
3. Broadcast via PubSub (existing)
4. Maintain backwards compatibility when no session_id provided

### New Handler Pattern

```elixir
def execute(%{"todos" => todos}, context) when is_list(todos) do
  with {:ok, validated_todos} <- validate_todos(todos) do
    session_id = Map.get(context, :session_id)

    # Store in Session.State if session_id available
    store_todos(validated_todos, session_id)

    # Broadcast via PubSub
    broadcast_todos(validated_todos, session_id)

    {:ok, format_success_message(validated_todos)}
  end
end

defp store_todos(_todos, nil), do: :ok
defp store_todos(todos, session_id) do
  case Session.State.update_todos(session_id, todos) do
    {:ok, _state} -> :ok
    {:error, :not_found} ->
      Logger.warning("Session.State not found for session #{session_id}, todos not persisted")
      :ok
  end
end
```

## Implementation Plan

### Step 1: Update Todo handler
- [x] Add alias for Session.State
- [x] Add `store_todos/2` private function
- [x] Call `store_todos/2` in execute/2
- [x] Add Logger require for warning messages

### Step 2: Write unit tests
- [x] Test todos stored in Session.State with valid session_id
- [x] Test todos retrieval via Session.State.get_todos
- [x] Test graceful handling when session not found
- [x] Test backwards compatibility (no session_id)

## Success Criteria

- [x] Todo handler stores todos in Session.State when session_id provided
- [x] Todos can be retrieved via Session.State.get_todos/1
- [x] Handler gracefully handles missing session (logs warning, continues)
- [x] All existing tests pass
- [x] New tests cover session state integration

## Current Status

**Status**: Complete

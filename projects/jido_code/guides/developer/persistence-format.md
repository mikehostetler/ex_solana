# Session Persistence Format

This document describes the JSON format used to persist sessions to disk for the `/resume` feature.

## Overview

Sessions are automatically saved when closed and can be restored via the `/resume` command. Each session is stored as a separate JSON file in `~/.jido_code/sessions/`.

### File Location

- **Directory**: `~/.jido_code/sessions/`
- **Filename Pattern**: `{session_id}.json`
- **Example**: `~/.jido_code/sessions/550e8400-e29b-41d4-a716-446655440000.json`

### Schema Version

Current schema version: **1**

The `version` field enables future migrations if the schema changes.

---

## JSON Schema

### Top-Level Structure

```json
{
  "version": 1,
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "my-project",
  "project_path": "/home/user/projects/my-project",
  "config": {
    "provider": "anthropic",
    "model": "claude-3-5-sonnet-20241022",
    "temperature": 0.7,
    "max_tokens": 4096
  },
  "created_at": "2025-12-16T10:30:00Z",
  "updated_at": "2025-12-16T15:45:30Z",
  "closed_at": "2025-12-16T16:00:00Z",
  "conversation": [
    {
      "id": "msg-001",
      "role": "user",
      "content": "Hello, can you help me?",
      "timestamp": "2025-12-16T10:31:00Z"
    },
    {
      "id": "msg-002",
      "role": "assistant",
      "content": "Of course! How can I help you today?",
      "timestamp": "2025-12-16T10:31:05Z"
    }
  ],
  "todos": [
    {
      "content": "Implement feature X",
      "status": "in_progress",
      "active_form": "Implementing feature X"
    }
  ]
}
```

### Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `version` | integer | Yes | Schema version for migrations (currently 1) |
| `id` | string | Yes | Unique session ID (UUID format) |
| `name` | string | Yes | Display name (auto-generated from directory) |
| `project_path` | string | Yes | Absolute path to project directory |
| `config` | object | Yes | Session LLM configuration |
| `created_at` | string | Yes | ISO 8601 timestamp of session creation |
| `updated_at` | string | Yes | ISO 8601 timestamp of last activity |
| `closed_at` | string | Yes | ISO 8601 timestamp when session was closed |
| `conversation` | array | Yes | Array of message objects |
| `todos` | array | Yes | Array of todo objects |

### Configuration Object

```json
{
  "provider": "anthropic",
  "model": "claude-3-5-sonnet-20241022",
  "temperature": 0.7,
  "max_tokens": 4096
}
```

**Fields**:
- `provider`: LLM provider name (e.g., "anthropic", "openai")
- `model`: Model identifier
- `temperature`: Sampling temperature (0.0-2.0)
- `max_tokens`: Maximum response tokens

### Message Object

```json
{
  "id": "msg-001",
  "role": "user",
  "content": "Hello, can you help me?",
  "timestamp": "2025-12-16T10:31:00Z"
}
```

**Fields**:
- `id`: Unique message identifier
- `role`: Message role ("user", "assistant", "system")
- `content`: Message text content
- `timestamp`: ISO 8601 timestamp

### Todo Object

```json
{
  "content": "Implement feature X",
  "status": "pending",
  "active_form": "Implementing feature X"
}
```

**Fields**:
- `content`: Todo description (imperative form)
- `status`: Status ("pending", "in_progress", "completed")
- `active_form`: Present continuous form for display

---

## Implementation

### Saving Sessions

**Trigger**: Session close (Ctrl+W or `/session close`)

**Code Path**:
```
SessionSupervisor.stop_session()
  → Session.Persistence.save()
    → serialize session data
    → Jason.encode()
    → File.write()
```

**File**: `lib/jido_code/session/persistence.ex`

### Restoring Sessions

**Trigger**: `/resume` or `/resume <index>`

**Code Path**:
```
Commands.execute_resume()
  → Session.Persistence.list_persisted()
  → User selects session
  → Session.Persistence.restore()
    → File.read()
    → Jason.decode()
    → SessionSupervisor.start_session()
    → Session.State.restore_state()
```

---

## Schema Versioning

### Current Version: 1

The current schema (version 1) includes all fields listed above.

### Adding Fields (Minor Changes)

When adding optional fields, maintain backward compatibility:

1. Increment version to 2
2. Add new field with default value
3. Write migration function

**Example**:
```elixir
def migrate(data, from_version) do
  case from_version do
    1 -> Map.put(data, :new_field, default_value())
    _ -> data
  end
end
```

### Breaking Changes (Major Changes)

If changing existing field structure:

1. Increment version significantly (e.g., to 10)
2. Write comprehensive migration
3. Consider deprecation period
4. Update all persistence tests

---

## File Management

### Listing Sessions

```elixir
Session.Persistence.list_persisted()
# Returns: [%{id: "...", name: "...", closed_at: "..."}]
```

### Deleting Sessions

```elixir
Session.Persistence.delete(session_id)
# Removes: ~/.jido_code/sessions/{session_id}.json
```

### Clearing All Sessions

```elixir
Session.Persistence.clear_all()
# Removes: All files in ~/.jido_code/sessions/
```

---

## Best Practices

### 1. Always Use ISO 8601 for Timestamps

```elixir
DateTime.utc_now() |> DateTime.to_iso8601()
# "2025-12-16T16:00:00Z"
```

### 2. Validate on Restore

Always validate restored data:

```elixir
def restore(session_id) do
  with {:ok, data} <- load_json(session_id),
       :ok <- validate_schema(data),
       {:ok, session} <- create_session(data) do
    {:ok, session}
  end
end
```

### 3. Handle Missing Fields Gracefully

```elixir
config = data["config"] || default_config()
todos = data["todos"] || []
```

### 4. Migrate on Load

```elixir
def restore(session_id) do
  data = load_json(session_id)
  current_version = data["version"]

  migrated_data = if current_version < @current_version do
    migrate(data, current_version)
  else
    data
  end

  # Continue restoration
end
```

---

## Testing

### Example Test Data

```elixir
@valid_persisted_session %{
  "version" => 1,
  "id" => "test-session-id",
  "name" => "test-project",
  "project_path" => "/tmp/test-project",
  "config" => %{
    "provider" => "anthropic",
    "model" => "claude-3-5-haiku-20241022"
  },
  "created_at" => "2025-12-16T10:00:00Z",
  "updated_at" => "2025-12-16T11:00:00Z",
  "closed_at" => "2025-12-16T12:00:00Z",
  "conversation" => [],
  "todos" => []
}
```

### Test Cases

1. **Round-trip**: Save → Load → Verify data unchanged
2. **Migration**: Load v1 → Migrate → Verify new fields
3. **Invalid data**: Load corrupted JSON → Verify error handling
4. **Missing fields**: Load partial data → Verify defaults applied

---

## Security Considerations

### Path Validation

Always validate `project_path` on restore:

```elixir
def validate_project_path(path) do
  cond do
    not File.dir?(path) ->
      {:error, "Project directory no longer exists"}

    not File.readable?(path) ->
      {:error, "Project directory not readable"}

    forbidden_path?(path) ->
      {:error, "Forbidden directory"}

    true ->
      {:ok, path}
  end
end
```

### Sanitize User Data

Escape any user-provided strings before persisting:

```elixir
# Message content, todo content, session names
content |> String.trim() |> String.slice(0, @max_length)
```

### File Permissions

Session files should be user-readable only:

```elixir
File.write(path, json, [:write, mode: 0o600])
```

---

## References

- Implementation: `lib/jido_code/session/persistence.ex`
- Tests: `test/jido_code/session/persistence_test.exs`
- [Session Architecture](./session-architecture.md)

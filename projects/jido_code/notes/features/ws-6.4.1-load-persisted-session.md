# WS-6.4.1: Load Persisted Session

**Branch:** `feature/ws-6.4.1-load-persisted-session`
**Phase:** 6 - Session Persistence
**Task:** 6.4.1 - Load Persisted Session

---

## Objective

Implement loading full session data from JSON files, including deserialization of session metadata, conversation history, and todos. This is the counterpart to the save functionality and enables session restoration.

---

## Problem Statement

Currently, JidoCode can save sessions to JSON files when they are closed (Task 6.2), but there is no mechanism to load these files back into memory. To enable session restoration via the `/resume` command (Task 6.4.2), we need to:

1. Read JSON files from the sessions directory
2. Deserialize JSON data back into Elixir data structures
3. Handle schema version migrations for forward compatibility
4. Validate loaded data to ensure integrity
5. Handle errors gracefully (missing files, corrupted JSON, invalid data)

The load functionality must be robust enough to handle edge cases like:
- Files that don't exist
- Corrupted or invalid JSON
- Missing required fields
- Invalid data types
- Schema version mismatches (future migrations)

---

## Solution Overview

We will implement two main functions in `JidoCode.Session.Persistence`:

1. **`load/1`** - High-level function that reads a session file and returns deserialized data
2. **`deserialize_session/1`** - Converts JSON maps to properly typed Elixir structures

The deserialization process will:
- Convert string keys to atoms for known fields
- Parse ISO 8601 timestamps back to DateTime structs
- Convert string values to atoms where appropriate (role, status)
- Validate data types and required fields
- Apply schema version migrations if needed

---

## Technical Details

### Data Structures to Deserialize

Based on the existing schema, we need to deserialize:

#### 1. Session Metadata
- `id` (string) → string
- `name` (string) → string
- `project_path` (string) → string
- `config` (map with string keys/values) → map with appropriate types
- `created_at` (ISO 8601 string) → DateTime struct
- `updated_at` (ISO 8601 string) → DateTime struct
- `closed_at` (ISO 8601 string) → DateTime struct (metadata only, not used in Session struct)

#### 2. Messages
Each message needs:
- `id` (string) → string
- `role` (string: "user"/"assistant"/"system"/"tool") → atom (`:user`, `:assistant`, `:system`, `:tool`)
- `content` (string) → string
- `timestamp` (ISO 8601 string) → DateTime struct

#### 3. Todos
Each todo needs:
- `content` (string) → string
- `status` (string: "pending"/"in_progress"/"completed") → atom (`:pending`, `:in_progress`, `:completed`)
- `active_form` (string) → string

### Validation Requirements

The `deserialize_session/1` function must validate:

1. **Schema version**: Check version field and apply migrations if needed
2. **Required fields**: All fields in `persisted_session` type are present
3. **Data types**: All values match expected types
4. **Field values**: Enums (role, status) contain valid values
5. **Timestamps**: ISO 8601 strings can be parsed to DateTime
6. **Nested structures**: Messages and todos are valid lists of maps

### Error Handling

Return descriptive errors for:
- `:not_found` - Session file doesn't exist
- `{:invalid_json, reason}` - JSON parsing failed
- `{:invalid_schema, details}` - Data doesn't match expected schema
- `{:unsupported_version, version}` - Schema version too new (future-proofing)

---

## Implementation Plan

### 1. Implement load/1 (6.4.1.1)

```elixir
@spec load(String.t()) :: {:ok, map()} | {:error, term()}
def load(session_id) when is_binary(session_id) do
  path = session_file(session_id)

  with {:ok, content} <- File.read(path),
       {:ok, data} <- Jason.decode(content),
       {:ok, session} <- deserialize_session(data) do
    {:ok, session}
  else
    {:error, :enoent} ->
      {:error, :not_found}
    {:error, %Jason.DecodeError{} = error} ->
      {:error, {:invalid_json, error}}
    {:error, reason} ->
      {:error, reason}
  end
end
```

**Details:**
- Read file from sessions directory using `session_file/1`
- Parse JSON with Jason
- Deserialize using `deserialize_session/1`
- Return descriptive errors for each failure mode

### 2. Implement deserialize_session/1 (6.4.1.2)

```elixir
@spec deserialize_session(map()) :: {:ok, map()} | {:error, term()}
def deserialize_session(data) when is_map(data) do
  with {:ok, validated} <- validate_session(data),
       {:ok, version} <- check_schema_version(validated.version),
       {:ok, migrated} <- apply_migrations(validated, version),
       {:ok, messages} <- deserialize_messages(migrated.conversation),
       {:ok, todos} <- deserialize_todos(migrated.todos),
       {:ok, created_at} <- parse_datetime(migrated.created_at),
       {:ok, updated_at} <- parse_datetime(migrated.updated_at) do
    {:ok, %{
      id: migrated.id,
      name: migrated.name,
      project_path: migrated.project_path,
      config: deserialize_config(migrated.config),
      created_at: created_at,
      updated_at: updated_at,
      conversation: messages,
      todos: todos
    }}
  end
end

def deserialize_session(_), do: {:error, :not_a_map}
```

**Details:**
- Validate session structure (already implemented)
- Check schema version
- Apply migrations if needed (currently no-op for v1)
- Deserialize nested structures (messages, todos)
- Parse timestamps
- Return structured map ready for session restoration

### 3. Implement check_schema_version/1 (6.4.1.3a)

```elixir
defp check_schema_version(version) when is_integer(version) do
  current = schema_version()

  cond do
    version > current ->
      {:error, {:unsupported_version, version}}
    version < 1 ->
      {:error, {:invalid_version, version}}
    true ->
      {:ok, version}
  end
end

defp check_schema_version(version), do: {:error, {:invalid_version, version}}
```

**Details:**
- Reject versions higher than current (file from newer version)
- Reject invalid versions (< 1)
- Accept current and older versions (for migration)

### 4. Implement apply_migrations/2 (6.4.1.3b)

```elixir
defp apply_migrations(data, from_version) do
  current = schema_version()

  if from_version == current do
    {:ok, data}
  else
    # Future: Apply migration chain from_version -> current
    # For now, only v1 exists, so this is a no-op
    {:ok, data}
  end
end
```

**Details:**
- No-op for version 1 (current)
- Framework for future migrations
- Would chain migrations: v1 -> v2 -> v3 etc.

### 5. Implement deserialize_messages/1 (6.4.1.4)

```elixir
defp deserialize_messages(messages) when is_list(messages) do
  messages
  |> Enum.reduce_while({:ok, []}, fn msg, {:ok, acc} ->
    case deserialize_message(msg) do
      {:ok, deserialized} -> {:cont, {:ok, [deserialized | acc]}}
      {:error, reason} -> {:halt, {:error, {:invalid_message, reason}}}
    end
  end)
  |> case do
    {:ok, messages} -> {:ok, Enum.reverse(messages)}
    error -> error
  end
end

defp deserialize_messages(_), do: {:error, :messages_not_list}

defp deserialize_message(msg) do
  with {:ok, validated} <- validate_message(msg),
       {:ok, timestamp} <- parse_datetime(validated.timestamp),
       {:ok, role} <- parse_role(validated.role) do
    {:ok, %{
      id: validated.id,
      role: role,
      content: validated.content,
      timestamp: timestamp
    }}
  end
end
```

**Details:**
- Validate each message
- Parse timestamp
- Convert role string to atom
- Preserve chronological order
- Stop on first error with descriptive message

### 6. Implement deserialize_todos/1 (6.4.1.4)

```elixir
defp deserialize_todos(todos) when is_list(todos) do
  todos
  |> Enum.reduce_while({:ok, []}, fn todo, {:ok, acc} ->
    case deserialize_todo(todo) do
      {:ok, deserialized} -> {:cont, {:ok, [deserialized | acc]}}
      {:error, reason} -> {:halt, {:error, {:invalid_todo, reason}}}
    end
  end)
  |> case do
    {:ok, todos} -> {:ok, Enum.reverse(todos)}
    error -> error
  end
end

defp deserialize_todos(_), do: {:error, :todos_not_list}

defp deserialize_todo(todo) do
  with {:ok, validated} <- validate_todo(todo),
       {:ok, status} <- parse_status(validated.status) do
    {:ok, %{
      content: validated.content,
      status: status,
      active_form: validated.active_form
    }}
  end
end
```

**Details:**
- Validate each todo
- Convert status string to atom
- Preserve order
- Stop on first error

### 7. Implement parse helpers (6.4.1.4)

```elixir
defp parse_datetime(nil), do: {:error, :missing_timestamp}
defp parse_datetime(iso_string) when is_binary(iso_string) do
  case DateTime.from_iso8601(iso_string) do
    {:ok, dt, _offset} -> {:ok, dt}
    {:error, reason} -> {:error, {:invalid_timestamp, iso_string, reason}}
  end
end
defp parse_datetime(other), do: {:error, {:invalid_timestamp, other}}

defp parse_role("user"), do: {:ok, :user}
defp parse_role("assistant"), do: {:ok, :assistant}
defp parse_role("system"), do: {:ok, :system}
defp parse_role("tool"), do: {:ok, :tool}
defp parse_role(other), do: {:error, {:invalid_role, other}}

defp parse_status("pending"), do: {:ok, :pending}
defp parse_status("in_progress"), do: {:ok, :in_progress}
defp parse_status("completed"), do: {:ok, :completed}
defp parse_status(other), do: {:error, {:invalid_status, other}}

defp deserialize_config(config) when is_map(config) do
  # Config is already in the right format (string keys)
  # Just ensure expected keys exist with defaults
  %{
    "provider" => Map.get(config, "provider", "anthropic"),
    "model" => Map.get(config, "model", "claude-3-5-sonnet-20241022"),
    "temperature" => Map.get(config, "temperature", 0.7),
    "max_tokens" => Map.get(config, "max_tokens", 4096)
  }
end
```

**Details:**
- Parse ISO 8601 timestamps with descriptive errors
- Convert role strings to atoms (validated set)
- Convert status strings to atoms (validated set)
- Deserialize config with defaults for missing fields

### 8. Write Unit Tests (6.4.1.5)

Create comprehensive tests in `test/jido_code/session/persistence_test.exs`:

```elixir
describe "load/1" do
  test "loads valid session file"
  test "returns error for non-existent file"
  test "returns error for corrupted JSON"
  test "returns error for invalid schema"
  test "handles missing required fields"
end

describe "deserialize_session/1" do
  test "deserializes complete session"
  test "deserializes session with empty conversation"
  test "deserializes session with empty todos"
  test "validates schema version"
  test "rejects unsupported schema version"
  test "rejects invalid data types"
  test "returns descriptive errors"
end

describe "deserialize_messages/1" do
  test "deserializes message list"
  test "converts role strings to atoms"
  test "parses timestamps correctly"
  test "preserves message order"
  test "returns error for invalid role"
  test "returns error for invalid timestamp"
  test "returns error for non-list input"
end

describe "deserialize_todos/1" do
  test "deserializes todo list"
  test "converts status strings to atoms"
  test "preserves todo order"
  test "returns error for invalid status"
  test "returns error for non-list input"
end

describe "schema version handling" do
  test "accepts current schema version"
  test "rejects future schema version"
  test "rejects invalid schema version"
end

describe "round-trip serialization" do
  test "save then load preserves all data"
  test "conversation history preserved"
  test "todos preserved"
  test "timestamps preserved"
  test "config preserved"
end
```

---

## Files to Modify

**Modified Files:**
- `lib/jido_code/session/persistence.ex` - Add `load/1` and deserialization functions
- `test/jido_code/session/persistence_test.exs` - Add load and deserialization tests

---

## Success Criteria

1. `load/1` successfully reads and parses session JSON files
2. `deserialize_session/1` converts JSON to properly typed Elixir structures
3. Messages deserialized with roles as atoms and timestamps as DateTime
4. Todos deserialized with status as atoms
5. Schema version validation prevents loading incompatible files
6. Migration framework in place (even if no-op for v1)
7. All validation errors return descriptive error tuples
8. Round-trip test: save → load → verify all data preserved
9. All unit tests passing (minimum 15 new tests)
10. No credo issues
11. Test coverage for error paths (missing files, invalid JSON, bad schema)

---

## Testing Strategy

### Unit Tests

1. **Happy Path**: Load valid session files with various data
2. **Error Cases**: Missing files, corrupted JSON, invalid schemas
3. **Edge Cases**: Empty conversations, empty todos, missing optional fields
4. **Validation**: Invalid roles, statuses, timestamps
5. **Round-trip**: Save then load, verify data integrity

### Test Data

Create fixture files:
- `valid_session_v1.json` - Complete valid session
- `empty_conversation.json` - Session with no messages
- `invalid_role.json` - Message with unknown role
- `corrupted.json` - Malformed JSON
- `future_version.json` - Version 99 (unsupported)

### Integration Considerations

This task focuses on loading the data. Task 6.4.2 (Resume Session) will:
- Use `load/1` to get deserialized data
- Rebuild Session struct
- Start session processes
- Restore state to Session.State GenServer
- Delete persisted file

---

## Dependencies

**Requires:**
- Task 6.1.1 (Schema definition) - completed
- Task 6.2.1 (Save function) - completed
- Existing validation functions in Persistence module

**Enables:**
- Task 6.4.2 (Resume Session) - needs load/1
- Task 6.5.1 (Resume Command) - needs load/1 for preview

---

## Notes

- The loaded data is returned as a plain map, not a Session struct. Task 6.4.2 will handle conversion.
- Schema version 1 is current, so migrations are framework-only for now.
- Config remains as string-keyed map (matching how Session stores it).
- Timestamps are converted to DateTime structs for consistency with Session.
- The `closed_at` field is loaded but not returned (only used for metadata display).

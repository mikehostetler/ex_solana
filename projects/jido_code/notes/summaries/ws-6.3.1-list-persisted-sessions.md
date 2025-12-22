# Summary: WS-6.3.1 List Persisted Sessions

**Branch:** `feature/ws-6.3.1-list-persisted-sessions`
**Date:** 2025-12-07

---

## Changes Made

### Modified Files

1. **`lib/jido_code/session/persistence.ex`**
   - Added `list_persisted/0` - lists all persisted sessions from sessions directory
   - Added `load_session_metadata/1` - loads minimal session info (id, name, project_path, closed_at)
   - Added `parse_datetime/1` - parses ISO 8601 timestamps with fallback for errors
   - Handles missing sessions directory (returns empty list)
   - Handles corrupted JSON files gracefully (skips them)
   - Sorts sessions by closed_at (most recent first)

2. **`test/jido_code/session/persistence_test.exs`**
   - Added 7 new tests for list_persisted/0
   - Added helper functions: `cleanup_session_files/0`, `create_test_session/3`
   - Total: 77 tests (previously 70)

---

## Implementation Details

### list_persisted/0

```elixir
@spec list_persisted() :: [map()]
def list_persisted do
  dir = sessions_dir()

  case File.ls(dir) do
    {:ok, files} ->
      files
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.map(&load_session_metadata/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& parse_datetime(&1.closed_at), {:desc, DateTime})

    {:error, :enoent} ->
      []

    {:error, _} ->
      []
  end
end
```

### Metadata Structure

Each session metadata map contains:
- `id` - Session identifier
- `name` - Session name
- `project_path` - Project path
- `closed_at` - ISO 8601 timestamp when session was closed

### Error Handling

- Missing sessions directory → returns empty list
- Corrupted JSON files → skipped (returns nil from load_session_metadata)
- Non-JSON files → filtered out
- Invalid timestamps → fallback to 1970-01-01 for sorting

---

## Test Results

- 77 tests total (7 new for list_persisted)
- All tests passing
- No credo issues

---

## Next Task

**Task 6.3.2 - Filter Active Sessions**
- Implement `list_resumable/0` to exclude active sessions
- Exclude sessions with same project_path as active
- Write unit tests for filtering

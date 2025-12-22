# WS-6.3.1: List Persisted Sessions

**Branch:** `feature/ws-6.3.1-list-persisted-sessions`
**Phase:** 6 - Session Persistence
**Task:** 6.3.1 - List Persisted Sessions

---

## Objective

Implement listing all persisted sessions from the sessions directory, with metadata loading and sorting.

---

## Implementation Plan

### 1. Implement list_persisted/0 (6.3.1.1)

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
      |> Enum.sort_by(& &1.closed_at, {:desc, DateTime})

    {:error, :enoent} ->
      []
  end
end
```

### 2. Implement load_session_metadata/1 (6.3.1.2)

```elixir
defp load_session_metadata(filename) do
  path = Path.join(sessions_dir(), filename)

  with {:ok, content} <- File.read(path),
       {:ok, data} <- Jason.decode(content) do
    # Convert string keys to atoms for the fields we need
    %{
      id: Map.get(data, "id"),
      name: Map.get(data, "name"),
      project_path: Map.get(data, "project_path"),
      closed_at: Map.get(data, "closed_at")
    }
  else
    _ -> nil
  end
end
```

### 3. Sort by closed_at (6.3.1.3)

Use `Enum.sort_by/3` with `{:desc, DateTime}` to sort most recent first.

### 4. Handle corrupted files gracefully (6.3.1.4)

- Return `nil` from `load_session_metadata/1` on error
- Use `Enum.reject(&is_nil/1)` to filter out failed loads
- Handle missing sessions directory (return empty list)

### 5. Write unit tests (6.3.1.5)

- Test `list_persisted/0` with no sessions
- Test `list_persisted/0` with multiple sessions
- Test sorting by closed_at (most recent first)
- Test handling corrupted JSON files
- Test handling missing sessions directory

---

## Files to Modify

**Modified Files:**
- `lib/jido_code/session/persistence.ex` - Add listing functions
- `test/jido_code/session/persistence_test.exs` - Add listing tests

---

## Success Criteria

1. `list_persisted/0` returns all persisted sessions
2. Sessions sorted by closed_at (most recent first)
3. Corrupted files are skipped gracefully
4. Missing directory returns empty list
5. All unit tests passing
6. No credo issues

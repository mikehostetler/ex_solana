# Summary: WS-1.2.3 Session Lookup

**Branch**: `feature/ws-1.2.3-session-lookup`
**Date**: 2025-12-04
**Files Modified**:
- `lib/jido_code/session_registry.ex`
- `test/jido_code/session_registry_test.exs`

## Overview

Implemented three session lookup functions for finding sessions by different criteria: ID, project path, and name.

## Implementation Details

### lookup/1 - Find by Session ID

Direct ETS key lookup for O(1) performance:

```elixir
def lookup(session_id) do
  case :ets.lookup(@table, session_id) do
    [{^session_id, session}] -> {:ok, session}
    [] -> {:error, :not_found}
  end
end
```

### lookup_by_path/1 - Find by Project Path

Uses ETS match spec to search for matching project_path:

```elixir
def lookup_by_path(project_path) do
  match_spec = [{
    {:_, %Session{project_path: :"$1", ...}},
    [{:==, :"$1", project_path}],
    [:"$_"]
  }]

  case :ets.select(@table, match_spec) do
    [{_id, session} | _] -> {:ok, session}
    [] -> {:error, :not_found}
  end
end
```

### lookup_by_name/1 - Find by Session Name

Searches for sessions with matching name, returns oldest (by created_at) for consistent results when multiple sessions share the same name:

```elixir
def lookup_by_name(name) do
  match_spec = [{
    {:_, %Session{name: :"$1", ...}},
    [{:==, :"$1", name}],
    [:"$_"]
  }]

  case :ets.select(@table, match_spec) do
    [] -> {:error, :not_found}
    matches ->
      {_id, session} =
        matches
        |> Enum.sort_by(fn {_id, s} -> s.created_at end, DateTime)
        |> List.first()
      {:ok, session}
  end
end
```

## Key Design Decisions

1. **lookup/1**: Direct key lookup (O(1)) - most efficient
2. **lookup_by_path/1**: Path is unique (enforced by register/1), returns at most one session
3. **lookup_by_name/1**: Names are not unique, returns oldest session for consistency
4. **All lookups**: Return `{:ok, session}` or `{:error, :not_found}`

## Test Coverage

16 new tests:

**lookup/1 (5 tests)**:
- Finds registered session by ID
- Returns complete session struct
- Returns error for unknown ID
- Returns error for unknown ID when table has sessions
- Finds correct session among multiple

**lookup_by_path/1 (5 tests)**:
- Finds session by project path
- Returns error for unknown path
- Returns error for unknown path when table has sessions
- Finds correct session among multiple
- Path lookup is exact match

**lookup_by_name/1 (6 tests)**:
- Finds session by name
- Returns error for unknown name
- Returns error for unknown name when table has sessions
- Returns oldest session when multiple have same name
- Finds correct session among multiple with different names
- Name lookup is exact match

**Total: 43 tests, 0 failures**

## API Summary

```elixir
# Find by ID (O(1) lookup)
{:ok, session} = SessionRegistry.lookup("session-id")

# Find by project path (unique)
{:ok, session} = SessionRegistry.lookup_by_path("/home/user/project")

# Find by name (returns oldest if multiple)
{:ok, session} = SessionRegistry.lookup_by_name("my-project")

# All return {:error, :not_found} if not found
```

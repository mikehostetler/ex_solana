# Feature: WS-1.2.3 Session Lookup

## Problem Statement

The SessionRegistry needs lookup functions to find sessions by different criteria: ID, project path, and name. These functions are essential for session management and are used by the SessionSupervisor and TUI.

### Impact
- Required by SessionSupervisor for session process management
- Required by TUI for tab switching
- Foundation for session navigation and context switching

## Solution Overview

Implement three lookup functions:
1. `lookup/1` - Find session by ID (direct ETS key lookup)
2. `lookup_by_path/1` - Find session by project path (table scan)
3. `lookup_by_name/1` - Find session by name (table scan, returns first match)

### Key Design Decisions
- `lookup/1` uses direct key lookup (O(1))
- `lookup_by_path/1` uses ETS select with match spec (path is unique)
- `lookup_by_name/1` returns first match (names are not unique)
- All return `{:ok, session}` or `{:error, :not_found}`

## Technical Details

### Files to Modify
- `lib/jido_code/session_registry.ex` - Add lookup implementations
- `test/jido_code/session_registry_test.exs` - Add lookup tests

### Implementation

**lookup/1** - Direct key lookup:
```elixir
def lookup(session_id) do
  case :ets.lookup(@table, session_id) do
    [{^session_id, session}] -> {:ok, session}
    [] -> {:error, :not_found}
  end
end
```

**lookup_by_path/1** - Match on project_path field:
```elixir
def lookup_by_path(project_path) do
  # Use match spec to find session with matching path
end
```

**lookup_by_name/1** - Match on name field (first match):
```elixir
def lookup_by_name(name) do
  # Use match spec, return first match
end
```

## Success Criteria

- [x] `lookup/1` finds session by ID
- [x] `lookup/1` returns `{:error, :not_found}` for unknown ID
- [x] `lookup_by_path/1` finds session by project path
- [x] `lookup_by_path/1` returns `{:error, :not_found}` for unknown path
- [x] `lookup_by_name/1` finds session by name
- [x] `lookup_by_name/1` returns oldest match when multiple sessions have same name
- [x] `lookup_by_name/1` returns `{:error, :not_found}` for unknown name
- [x] All unit tests pass (16 lookup tests)

## Implementation Plan

### Step 1: Implement lookup/1
- [x] Replace stub with ETS lookup
- [x] Handle found and not-found cases

### Step 2: Implement lookup_by_path/1
- [x] Use ETS select with match spec
- [x] Return first (and only) match or not_found

### Step 3: Implement lookup_by_name/1
- [x] Use ETS select with match spec
- [x] Sort by created_at and return oldest

### Step 4: Write Tests
- [x] Test lookup/1 success and failure
- [x] Test lookup_by_path/1 success and failure
- [x] Test lookup_by_name/1 success, failure, and multiple matches

## Current Status

**Status**: Complete

**What works**: All lookup functions implemented and tested

**What's next**: Merge to work-session branch

## Notes/Considerations

- Path lookup is unique (enforced by register/1)
- Name lookup is not unique - multiple sessions can have same name
- Consider sorted results for name lookup (by created_at) for consistency

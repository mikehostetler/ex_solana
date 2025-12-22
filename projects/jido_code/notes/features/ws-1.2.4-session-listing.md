# Feature: WS-1.2.4 Session Listing

## Problem Statement

The SessionRegistry needs functions to list all sessions and their IDs for display in the TUI tab bar and for session management operations.

### Impact
- Required by TUI for displaying session tabs
- Required for session switching and management
- Foundation for session navigation

## Solution Overview

Implement listing functions with consistent ordering:
1. `list_all/0` - Return all sessions sorted by created_at
2. `list_ids/0` - Return all session IDs sorted by created_at
3. `count/0` - Already implemented in Task 1.2.2

### Key Design Decisions
- Sort by `created_at` (oldest first) for consistent ordering
- Use `:ets.tab2list/1` and extract sessions
- `count/0` already uses `:ets.info(@table, :size)` for efficiency

## Technical Details

### Files to Modify
- `lib/jido_code/session_registry.ex` - Add listing implementations
- `test/jido_code/session_registry_test.exs` - Add listing tests

### Implementation

**list_all/0** - Return all sessions:
```elixir
def list_all do
  @table
  |> :ets.tab2list()
  |> Enum.map(fn {_id, session} -> session end)
  |> Enum.sort_by(& &1.created_at, DateTime)
end
```

**list_ids/0** - Return all session IDs:
```elixir
def list_ids do
  list_all()
  |> Enum.map(& &1.id)
end
```

## Success Criteria

- [x] `list_all/0` returns all sessions sorted by created_at
- [x] `list_all/0` returns empty list when no sessions
- [x] `list_ids/0` returns all session IDs sorted by created_at
- [x] `list_ids/0` returns empty list when no sessions
- [x] Ordering is consistent (oldest first)
- [x] All unit tests pass

## Implementation Plan

### Step 1: Implement list_all/0
- [x] Replace stub with ETS tab2list
- [x] Extract sessions from tuples
- [x] Sort by created_at
- [x] Handle case when table doesn't exist

### Step 2: Implement list_ids/0
- [x] Use list_all/0 and map to IDs

### Step 3: Write Tests
- [x] Test list_all/0 empty and with sessions
- [x] Test list_ids/0 empty and with sessions
- [x] Test sorting order
- [x] Test returns correct types (Session structs, strings)

## Current Status

**Status**: Complete

**What works**: All listing functions implemented with 10 tests passing

**Total tests**: 53 tests in SessionRegistry, 0 failures

## Notes/Considerations

- `count/0` was implemented early in Task 1.2.2 because register/1 needed it
- Sorting ensures consistent display order in TUI

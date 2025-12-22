# Feature: WS-2.1.1 Session Manager Module Structure

## Problem Statement

Phase 1 created a stub `Session.Manager` module for the session supervision tree. Phase 2 requires transforming this into a full per-session security sandbox manager that:

- Manages a Lua sandbox state for each session
- Enforces project boundary restrictions per session
- Provides the same API as the global `Tools.Manager` but scoped to a session

Task 2.1.1 focuses on the module structure foundation - adding the state type, ensuring proper startup with session context, and the via helper for Registry naming.

## Solution Overview

Enhance the existing `Session.Manager` GenServer to:

1. Define `@type state()` with `session_id`, `project_root`, and `lua_state` fields
2. Keep existing `start_link/1` and `via/1` (already using SessionProcessRegistry)
3. Update `init/1` to store session_id and project_root (Lua initialization comes in 2.1.2)
4. Add comprehensive unit tests for manager startup

## Technical Details

### Current State (Phase 1 Stub)

```elixir
@impl true
def init(%Session{} = session) do
  {:ok, %{session: session}}
end
```

### Target State (Task 2.1.1)

```elixir
@type state :: %{
  session_id: String.t(),
  project_root: String.t(),
  lua_state: :luerl.luerl_state() | nil  # nil until 2.1.2
}

@impl true
def init(%Session{} = session) do
  {:ok, %{
    session_id: session.id,
    project_root: session.project_path,
    lua_state: nil  # Initialized in Task 2.1.2
  }}
end
```

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_code/session/manager.ex` | Add state type, update init |
| `test/jido_code/session/manager_test.exs` | Add tests for state structure |

## Implementation Plan

### Step 1: Update State Structure
- [x] Add `@type state()` typespec
- [x] Update `init/1` to use new state map structure
- [x] Keep `get_session/1` working (update to extract from new state)

### Step 2: Add State Access Functions
- [x] Add `project_root/1` client function
- [x] Add `session_id/1` client function
- [x] Add corresponding `handle_call` implementations

### Step 3: Update Tests
- [x] Test state has correct structure after init
- [x] Test `project_root/1` returns correct path
- [x] Test `session_id/1` returns correct ID
- [x] Verify existing tests still pass

## Success Criteria

- [x] `@type state()` defined with session_id, project_root, lua_state fields
- [x] `init/1` creates state with correct structure
- [x] `project_root/1` and `session_id/1` client functions work
- [x] All existing and new tests pass (223 session tests pass)
- [x] Ready for Task 2.1.2 (Lua initialization)

## Current Status

**Status**: Complete

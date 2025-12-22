# Feature: WS-2.1.2 Manager Initialization

## Problem Statement

Task 2.1.1 created the Session.Manager state structure with `lua_state: nil`. Task 2.1.2 needs to initialize the Lua sandbox in `init/1` so that each session has its own isolated Lua runtime with bridge functions registered.

## Solution Overview

Update `init/1` to:
1. Initialize Luerl state via `:luerl.init()`
2. Register bridge functions via `Tools.Bridge.register/2`
3. Store the initialized lua_state in manager state
4. Log initialization details (session ID, project path)
5. Handle potential Lua initialization errors gracefully

## Technical Details

### Current init/1 (from Task 2.1.1)

```elixir
def init(%Session{} = session) do
  Logger.debug("Starting Session.Manager for session #{session.id} with project_root: #{session.project_path}")

  state = %{
    session_id: session.id,
    project_root: session.project_path,
    lua_state: nil
  }

  {:ok, state}
end
```

### Target init/1 (Task 2.1.2)

```elixir
def init(%Session{} = session) do
  Logger.info("Starting Session.Manager for session #{session.id}")
  Logger.debug("  project_root: #{session.project_path}")

  case initialize_lua_sandbox(session.project_path) do
    {:ok, lua_state} ->
      state = %{
        session_id: session.id,
        project_root: session.project_path,
        lua_state: lua_state
      }
      {:ok, state}

    {:error, reason} ->
      Logger.error("Failed to initialize Lua sandbox for session #{session.id}: #{inspect(reason)}")
      {:stop, {:lua_init_failed, reason}}
  end
end

defp initialize_lua_sandbox(project_root) do
  lua_state = :luerl.init()
  lua_state = Tools.Bridge.register(lua_state, project_root)
  {:ok, lua_state}
rescue
  e -> {:error, e}
catch
  kind, reason -> {:error, {kind, reason}}
end
```

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_code/session/manager.ex` | Update init, add helper |
| `test/jido_code/session/manager_test.exs` | Add init tests |

## Implementation Plan

### Step 1: Update init/1
- [x] Add alias for Tools.Bridge
- [x] Create `initialize_lua_sandbox/1` private function
- [x] Update `init/1` to call sandbox initialization
- [x] Handle success and error cases

### Step 2: Add Logging
- [x] Log session ID and project path at info level
- [x] Log errors at error level
- [x] Use debug for detailed sandbox info

### Step 3: Write Tests
- [x] Test lua_state is initialized (not nil)
- [x] Test bridge functions are registered (jido namespace exists)
- [x] Test bridge functions can be executed

## Success Criteria

- [x] `init/1` initializes Lua sandbox with bridge functions
- [x] `state.lua_state` is a valid Luerl state (not nil)
- [x] Bridge functions (jido.read_file, etc.) are registered
- [x] Initialization logged at info level
- [x] Errors handled gracefully with {:stop, reason}
- [x] All tests pass

## Current Status

**Status**: Complete

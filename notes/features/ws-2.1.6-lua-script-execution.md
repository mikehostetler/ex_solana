# Feature: WS-2.1.6 Lua Script Execution

## Problem Statement

Task 2.1.6 requires implementing session-scoped Lua script execution in Session.Manager. This allows running Lua scripts within the session's Lua sandbox, with access to bridge functions like `jido.read_file`, etc.

## Solution Overview

Add `run_lua/2` client function and corresponding `handle_call` callback to Session.Manager that executes Lua scripts in the session's sandbox. The Lua state is updated after successful execution to maintain state across calls.

## Technical Details

### New Client Function

```elixir
@doc """
Executes a Lua script in the session's sandbox.

## Parameters

- `session_id` - The session identifier
- `script` - The Lua script to execute

## Returns

- `{:ok, result}` - Script executed successfully, result is list of return values
- `{:error, :not_found}` - Session manager not found
- `{:error, reason}` - Script execution failed

## Examples

    iex> {:ok, [42]} = Manager.run_lua("session_123", "return 21 + 21")
    iex> {:ok, ["hello"]} = Manager.run_lua("session_123", "return jido.read_file('test.txt')")
"""
@spec run_lua(String.t(), String.t(), timeout()) ::
        {:ok, list()} | {:error, :not_found | term()}
def run_lua(session_id, script, timeout \\ 30_000) do
  case Registry.lookup(@registry, {:manager, session_id}) do
    [{pid, _}] -> GenServer.call(pid, {:run_lua, script}, timeout)
    [] -> {:error, :not_found}
  end
end
```

### New Handle Call Callback

```elixir
@impl true
def handle_call({:run_lua, script}, _from, state) do
  case :luerl.do(script, state.lua_state) do
    {:ok, result, new_lua_state} ->
      {:reply, {:ok, result}, %{state | lua_state: new_lua_state}}
    {:error, reason, _lua_state} ->
      {:reply, {:error, format_lua_error(reason)}, state}
  end
rescue
  e ->
    {:reply, {:error, {:exception, Exception.message(e)}}, state}
catch
  kind, reason ->
    {:reply, {:error, {kind, reason}}, state}
end
```

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_code/session/manager.ex` | Add run_lua/2,3 client function and callback |
| `test/jido_code/session/manager_test.exs` | Add Lua execution tests |

## Implementation Plan

### Step 1: Implement run_lua Client Function
- [x] Add `run_lua/2` and `run_lua/3` client functions with Registry lookup
- [x] Support configurable timeout (default 30 seconds)

### Step 2: Implement handle_call Callback
- [x] Handle successful execution - update lua_state
- [x] Handle Lua errors - return formatted error
- [x] Handle exceptions/catches

### Step 3: Write Unit Tests
- [x] Test simple Lua expressions (math, strings)
- [x] Test Lua state persists between calls
- [x] Test bridge function access (jido.read_file)
- [x] Test Lua syntax error handling
- [x] Test Lua runtime error handling
- [x] Test non-existent session returns :not_found

## Success Criteria

- [x] `run_lua/2` client function implemented with timeout support
- [x] Lua state updated on successful execution
- [x] Errors handled gracefully
- [x] Unit tests for success and error cases
- [x] All tests pass

## Current Status

**Status**: Complete

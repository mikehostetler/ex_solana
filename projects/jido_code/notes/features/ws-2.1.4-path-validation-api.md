# Feature: WS-2.1.4 Path Validation API

## Problem Statement

Task 2.1.4 requires implementing session-scoped path validation in the Session.Manager. This allows tool handlers to validate paths against the session's project root boundary before performing file operations.

## Solution Overview

Add `validate_path/2` client function and corresponding `handle_call` callback to Session.Manager that delegates to the existing `JidoCode.Tools.Security.validate_path/3` function.

## Technical Details

### New Client Function

```elixir
@doc """
Validates a path is within the session's project boundary.

## Parameters

- `session_id` - The session identifier
- `path` - The path to validate (relative or absolute)

## Returns

- `{:ok, resolved_path}` - Path is valid and within boundary
- `{:error, :not_found}` - Session manager not found
- `{:error, reason}` - Path validation failed

## Examples

    iex> {:ok, path} = Manager.validate_path("session_123", "src/file.ex")
    {:ok, "/project/src/file.ex"}

    iex> {:error, :path_escapes_boundary} = Manager.validate_path("session_123", "../../../etc/passwd")
"""
@spec validate_path(String.t(), String.t()) ::
        {:ok, String.t()} | {:error, :not_found | Security.validation_error()}
def validate_path(session_id, path) do
  case Registry.lookup(@registry, {:manager, session_id}) do
    [{pid, _}] -> GenServer.call(pid, {:validate_path, path})
    [] -> {:error, :not_found}
  end
end
```

### New Handle Call Callback

```elixir
@impl true
def handle_call({:validate_path, path}, _from, state) do
  result = Security.validate_path(path, state.project_root, log_violations: true)
  {:reply, result, state}
end
```

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_code/session/manager.ex` | Add alias, client function, callback |
| `test/jido_code/session/manager_test.exs` | Add validation tests |

## Implementation Plan

### Step 1: Update Manager Module
- [x] Add alias for `JidoCode.Tools.Security`
- [x] Add `validate_path/2` client function with Registry lookup
- [x] Add `handle_call({:validate_path, path}, _, state)` callback
- [x] Delegate to `Security.validate_path/3`

### Step 2: Write Unit Tests
- [x] Test valid relative path returns resolved path
- [x] Test valid absolute path within boundary returns path
- [x] Test path traversal attack returns error
- [x] Test absolute path outside boundary returns error
- [x] Test non-existent session returns `{:error, :not_found}`

## Success Criteria

- [x] `validate_path/2` client function implemented
- [x] Registry lookup with `{:error, :not_found}` fallback
- [x] `handle_call` delegates to Security module
- [x] Unit tests for success and error cases
- [x] All tests pass

## Current Status

**Status**: Complete

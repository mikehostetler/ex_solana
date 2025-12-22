# Feature: WS-2.1.5 File Operations API

## Problem Statement

Task 2.1.5 requires implementing session-scoped file operations in the Session.Manager. These operations (`read_file/2`, `write_file/3`, `list_dir/2`) mirror the global Tools.Manager but use the session's project root for boundary enforcement.

## Solution Overview

Add file operation functions to Session.Manager that:
1. Use the session's `project_root` for path validation
2. Delegate to `Security.atomic_read/3` and `Security.atomic_write/4` for TOCTOU-safe operations
3. Validate paths before listing directories
4. Return appropriate error tuples for missing sessions

## Technical Details

### New Client Functions

```elixir
@spec read_file(String.t(), String.t()) ::
        {:ok, binary()} | {:error, :not_found | atom()}
def read_file(session_id, path)

@spec write_file(String.t(), String.t(), binary()) ::
        :ok | {:error, :not_found | atom()}
def write_file(session_id, path, content)

@spec list_dir(String.t(), String.t()) ::
        {:ok, [String.t()]} | {:error, :not_found | atom()}
def list_dir(session_id, path)
```

### New Handle Call Callbacks

```elixir
def handle_call({:read_file, path}, _from, state) do
  result = Security.atomic_read(path, state.project_root, log_violations: true)
  {:reply, result, state}
end

def handle_call({:write_file, path, content}, _from, state) do
  result = Security.atomic_write(path, content, state.project_root, log_violations: true)
  {:reply, result, state}
end

def handle_call({:list_dir, path}, _from, state) do
  case Security.validate_path(path, state.project_root, log_violations: true) do
    {:ok, safe_path} -> {:reply, File.ls(safe_path), state}
    {:error, _} = error -> {:reply, error, state}
  end
end
```

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_code/session/manager.ex` | Add 3 client functions and 3 callbacks |
| `test/jido_code/session/manager_test.exs` | Add file operation tests |

## Implementation Plan

### Step 1: Implement read_file/2
- [x] Add `read_file/2` client function with Registry lookup
- [x] Add `handle_call({:read_file, path}, _, state)` using Security.atomic_read

### Step 2: Implement write_file/3
- [x] Add `write_file/3` client function with Registry lookup
- [x] Add `handle_call({:write_file, path, content}, _, state)` using Security.atomic_write

### Step 3: Implement list_dir/2
- [x] Add `list_dir/2` client function with Registry lookup
- [x] Add `handle_call({:list_dir, path}, _, state)` with path validation

### Step 4: Write Unit Tests
- [x] Test read_file reads file within boundary
- [x] Test read_file rejects path outside boundary
- [x] Test read_file returns :not_found for missing session
- [x] Test read_file returns error for non-existent file
- [x] Test write_file writes file within boundary
- [x] Test write_file creates parent directories
- [x] Test write_file rejects path outside boundary
- [x] Test write_file returns :not_found for missing session
- [x] Test list_dir lists directory within boundary
- [x] Test list_dir rejects path outside boundary
- [x] Test list_dir returns error for non-existent directory
- [x] Test list_dir returns :not_found for missing session

## Success Criteria

- [x] `read_file/2` implemented with path validation
- [x] `write_file/3` implemented with path validation
- [x] `list_dir/2` implemented with path validation
- [x] All functions return `{:error, :not_found}` for missing sessions
- [x] Unit tests for all success and error cases
- [x] All tests pass

## Current Status

**Status**: Complete

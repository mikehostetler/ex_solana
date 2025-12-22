# Feature: WS-2.4.2 Handler Helpers Update

## Problem Statement

The `HandlerHelpers` module currently only supports context with `project_root` directly specified, or falls back to the global `Tools.Manager`. With per-session managers now available, the helpers need to prefer session context when a `session_id` is present.

This is critical because tool handlers use `HandlerHelpers.get_project_root/1` to determine the security boundary for file operations. Without this update, tool handlers won't benefit from session-scoped security.

## Solution Overview

Update `HandlerHelpers` to check for `session_id` in the context first, then delegate to `Session.Manager` for that session's project root. The priority order becomes:

1. `context[:session_id]` → `Session.Manager.project_root(session_id)`
2. `context[:project_root]` → Direct return (existing behavior)
3. Neither → `Tools.Manager.project_root()` (global fallback, deprecated)

Also add a `validate_path/2` helper that uses session manager when available.

## Technical Details

### Files to Modify

- `lib/jido_code/tools/handler_helpers.ex` - Update helpers
- `test/jido_code/tools/handler_helpers_test.exs` - Add tests

### New API

```elixir
# get_project_root/1 priority:
# 1. session_id in context → Session.Manager.project_root(session_id)
# 2. project_root in context → {:ok, project_root}
# 3. Neither → Tools.Manager.project_root() (deprecated)

def get_project_root(%{session_id: session_id}) do
  Session.Manager.project_root(session_id)
end

def get_project_root(%{project_root: root}) when is_binary(root) do
  {:ok, root}
end

def get_project_root(_context) do
  Tools.Manager.project_root()
end

# New: validate_path/2
def validate_path(path, context) do
  case context do
    %{session_id: session_id} ->
      Session.Manager.validate_path(session_id, path)
    %{project_root: root} ->
      Security.validate_path(path, root, log_violations: true)
    _ ->
      Tools.Manager.validate_path(path)
  end
end
```

## Implementation Plan

### Step 1: Update get_project_root/1
- [x] Add clause for `%{session_id: session_id}` pattern
- [x] Delegate to `Session.Manager.project_root/1`
- [x] Maintain backwards compatibility

### Step 2: Add validate_path/2 helper
- [x] Add new function that checks context for session_id
- [x] Delegate to Session.Manager.validate_path when available
- [x] Fall back to Security.validate_path with project_root
- [x] Fall back to Tools.Manager.validate_path for global

### Step 3: Update documentation
- [x] Update @moduledoc with session-aware usage
- [x] Update @doc for get_project_root/1
- [x] Add @doc for validate_path/2

### Step 4: Write tests
- [x] Test get_project_root with session_id
- [x] Test get_project_root with project_root (existing)
- [x] Test get_project_root fallback to global
- [x] Test validate_path with session_id
- [x] Test validate_path with project_root
- [x] Test validate_path fallback to global

### Step 5: Update phase plan
- [x] Mark Task 2.4.2 as complete in phase-02.md

## Success Criteria

- [x] `get_project_root/1` prefers session_id when present
- [x] `validate_path/2` uses session manager when session_id present
- [x] Backwards compatibility maintained
- [x] All existing tests pass
- [x] New tests cover session-aware behavior

## Current Status

**Status**: Complete

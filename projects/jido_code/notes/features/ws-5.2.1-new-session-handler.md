# WS-5.2.1 New Session Handler

**Branch:** `feature/ws-5.2.1-new-session-handler`
**Date:** 2025-12-06
**Status:** Complete

## Overview

Implement the handler for the `/session new` command that creates new sessions via SessionSupervisor.

## Problem Statement

The `/session new` command is parsed (Task 5.1.1) and paths are resolved (Task 5.1.2), but there's no execution handler to actually create sessions.

## Implementation Plan

### Step 1: Create execute_session/2 function
- [x] Add `execute_session/2` to Commands module
- [x] Handle `{:new, opts}` subcommand
- [x] Use `resolve_session_path/1` for path resolution
- [x] Use `validate_session_path/1` for path validation
- [x] Call `SessionSupervisor.create_session/1`

### Step 2: Handle error cases
- [x] Handle `:session_limit_reached` error
- [x] Handle `:project_already_open` error
- [x] Handle `:path_not_found` error
- [x] Handle `:path_not_directory` error

### Step 3: Return TUI action
- [x] Return `{:session_action, {:add_session, session}}` on success
- [x] Return `{:error, message}` on failure

### Step 4: Add other session handlers
- [x] Implement `:help` handler with full session command help
- [x] Add stub handlers for `:list`, `:switch`, `:close`, `:rename`
- [x] Handle error parsing cases (`:missing_target`, `:missing_name`)

### Step 5: Write unit tests
- [x] Test `:help` returns session command help
- [x] Test `{:new, opts}` with valid path creates session
- [x] Test `{:new, opts}` with non-existent path returns error
- [x] Test `{:new, opts}` with nil path uses CWD
- [x] Test stub handlers return "not implemented" messages
- [x] Test error parsing handlers return usage messages

## Files Modified

- `lib/jido_code/commands.ex` - Added execute_session/2 function (117 lines)
- `test/jido_code/commands_test.exs` - Added 11 tests for execute_session

## Technical Notes

The execute_session function returns:
- `{:session_action, {:add_session, session}}` - Success, TUI adds session to tabs
- `{:ok, message}` - Success message (e.g., help text)
- `{:error, message}` - Failure message

## Test Results

```
72 tests, 0 failures
- 61 existing tests
- 11 new execute_session tests
```

## Success Criteria

1. `/session new` creates a session - DONE
2. Path resolution works correctly - DONE
3. All error cases handled with clear messages - DONE
4. Unit tests pass - DONE (72 tests)

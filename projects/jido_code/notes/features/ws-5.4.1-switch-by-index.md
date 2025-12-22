# WS-5.4.1 Switch by Index

**Branch:** `feature/ws-5.4.1-switch-by-index`
**Date:** 2025-12-06
**Status:** Complete

## Overview

Implement the `/session switch` command handler to switch between sessions by index number (1-10), session ID, or session name.

## Problem Statement

Users need to switch between active sessions using `/session switch <target>`. The target can be an index (1-10), session ID, or session name.

## Implementation Plan

### Step 1: Implement execute_session({:switch, target}, model)
- [x] Replace stub with working implementation
- [x] Return {:session_action, {:switch_session, session_id}} for TUI to handle
- [x] Return error message for invalid targets

### Step 2: Implement resolve_session_target/2
- [x] Try parsing as index (1-10, with 0 meaning 10)
- [x] Fall back to session ID lookup
- [x] Fall back to session name lookup
- [x] Return {:ok, session_id} or {:error, :not_found}

### Step 3: Handle special case for index 0
- [x] Index "0" maps to session 10 (for Ctrl+0 shortcut)

### Step 4: Write unit tests
- [x] Test switch by valid index
- [x] Test switch by index 0 (maps to 10)
- [x] Test switch by out-of-range index
- [x] Test switch by session ID
- [x] Test switch by session name
- [x] Test switch with no sessions
- [x] Test switch to non-existent session

## Files Modified

- `lib/jido_code/commands.ex` - Added switch handler and helpers (~55 lines)
- `test/jido_code/commands_test.exs` - Added 8 unit tests (~120 lines)

## Test Results

```
85 Command tests, 0 failures
```

## Success Criteria

1. Switch by index (1-10) works - DONE
2. Switch by index 0 maps to session 10 - DONE
3. Switch by session ID works - DONE
4. Switch by session name works - DONE
5. Proper error messages for invalid targets - DONE
6. Unit tests pass - DONE

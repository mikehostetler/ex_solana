# WS-5.5.1 Close Handler

**Branch:** `feature/ws-5.5.1-close-handler`
**Date:** 2025-12-06
**Status:** Complete

## Overview

Implement the `/session close` command handler to close sessions by index, ID, or name.

## Problem Statement

Users need to be able to close sessions they no longer need. The command should:
1. Accept optional target (index, ID, or name)
2. Default to active session if no target provided
3. Properly clean up session resources
4. Update the TUI model to remove the session

## Implementation Plan

### Step 1: Implement execute_session({:close, target}, model)
- [x] Parse target (nil means active session)
- [x] Use existing resolve_session_target/2 for resolution
- [x] Return {:session_action, {:close_session, session_id, session_name}}
- [x] Handle error cases (not found, no sessions)

### Step 2: Add Model.remove_session/2 helper
- [x] Remove session from sessions map
- [x] Remove from session_order list
- [x] Switch active session to previous/next if closing active
- [x] Handle last session case

### Step 3: Add TUI handler for close action
- [x] Handle {:session_action, {:close_session, id, name}}
- [x] Call SessionSupervisor.stop_session/1
- [x] Unsubscribe from PubSub topic
- [x] Update model via Model.remove_session/2
- [x] Show success message

### Step 4: Write unit tests
- [x] Test close active session (no target)
- [x] Test close by index
- [x] Test close by ID
- [x] Test close by name
- [x] Test close non-existent session
- [x] Test close with no sessions
- [x] Test Model.remove_session/2

## Files to Modify

- `lib/jido_code/commands.ex` - Add close handler
- `lib/jido_code/tui.ex` - Add Model.remove_session/2 and TUI handler
- `test/jido_code/commands_test.exs` - Add close tests
- `test/jido_code/tui/model_test.exs` - Add remove_session tests

## Success Criteria

1. `/session close` closes active session
2. `/session close 2` closes session at index 2
3. `/session close myproject` closes session by name
4. Error shown for non-existent session
5. All tests pass

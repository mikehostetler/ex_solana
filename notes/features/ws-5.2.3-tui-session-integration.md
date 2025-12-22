# WS-5.2.3 TUI Integration for New Session

**Branch:** `feature/ws-5.2.3-tui-session-integration`
**Date:** 2025-12-06
**Status:** Complete

## Overview

Handle `{:session, subcommand}` and `{:session_action, {:add_session, session}}` in the TUI to integrate session commands with the UI.

## Problem Statement

The Commands module returns `{:session, subcommand}` for session commands, but the TUI didn't handle this return type. When `/session new` succeeds, it returns `{:session_action, {:add_session, session}}`, but there was no code to add the session to the model.

## Implementation Plan

### Step 1: Add {:session, subcommand} handling to do_handle_command
- [x] Match `{:session, subcommand}` return from Commands.execute
- [x] Call Commands.execute_session to execute the subcommand
- [x] Handle the result based on return type

### Step 2: Handle {:session_action, {:add_session, session}}
- [x] Add session to model.sessions map
- [x] Add session.id to session_order list
- [x] Set active_session_id to new session
- [x] Subscribe to session's PubSub topic

### Step 3: Add helper functions in Model
- [x] Add `add_session/2` to add a session to the model
- [x] Add `switch_to_session/2` to change active session
- [x] Add `session_count/1` to count sessions

### Step 4: Write unit tests
- [x] Test add_session/2 adds to empty model
- [x] Test add_session/2 adds to model with existing sessions
- [x] Test add_session/2 appends to session_order
- [x] Test switch_to_session/2 switches to existing session
- [x] Test switch_to_session/2 returns unchanged for unknown session
- [x] Test switch_to_session/2 can switch from nil
- [x] Test session_count/1 returns correct count

## Files Modified

- `lib/jido_code/tui.ex` - Added Model helpers and session command handling (~150 lines)
- `test/jido_code/tui/model_test.exs` - Added 8 tests for Model helpers

## Technical Notes

The session command flow is:
1. User enters `/session new` command
2. Commands.execute returns `{:session, {:new, opts}}`
3. TUI calls handle_session_command with subcommand
4. Commands.execute_session returns `{:session_action, {:add_session, session}}`
5. TUI adds session via Model.add_session
6. TUI subscribes to session's PubSub topic

## Test Results

```
35 Model tests, 0 failures
72 Command tests, 0 failures
```

## Success Criteria

1. `/session new` command works end-to-end - DONE
2. Session is added to TUI model - DONE
3. Active session switches to new session - DONE
4. PubSub subscription created - DONE
5. Unit tests pass - DONE

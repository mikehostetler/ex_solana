# WS-5.6.1 Rename Handler

**Branch:** `feature/ws-5.6.1-rename-handler`
**Date:** 2025-12-06
**Status:** Complete

## Overview

Implement the `/session rename <name>` command to allow users to rename the active session.

## Analysis

### Current State
- Parser already handles `/session rename <name>` → `{:rename, name}`
- Stub exists returning "Not yet implemented" error
- Session struct has `name` field that can be updated

### Design Decisions
1. **Rename active session only** - No target parameter (simplest UX)
2. **Name validation** - Non-empty, max 50 chars, trimmed
3. **Direct model update** - No SessionRegistry update needed (sessions are local to TUI)
4. **Return pattern** - Use `{:session_action, {:rename_session, session_id, new_name}}`

## Implementation Plan

### Step 1: Implement `execute_session({:rename, name}, model)`
- [x] Validate name (non-empty after trim, max 50 chars)
- [x] Check active session exists
- [x] Return `{:session_action, {:rename_session, session_id, new_name}}`

### Step 2: Add Model.rename_session/3 helper
- [x] Update session name in sessions map
- [x] Return updated model

### Step 3: Add TUI handler for rename action
- [x] Handle `{:session_action, {:rename_session, session_id, new_name}}`
- [x] Call Model.rename_session/3
- [x] Show success message

### Step 4: Write unit tests
- [x] Test rename with valid name
- [x] Test rename with empty name returns error
- [x] Test rename with too-long name returns error
- [x] Test rename with no active session returns error
- [x] Test Model.rename_session/3

## Files to Modify

- `lib/jido_code/commands.ex` - Implement rename handler
- `lib/jido_code/tui.ex` - Add TUI handler and Model.rename_session/3
- `test/jido_code/commands_test.exs` - Add rename command tests
- `test/jido_code/tui/model_test.exs` - Add rename_session tests

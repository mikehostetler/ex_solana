# WS-4.1.2 Session State Access Helpers

**Branch:** `feature/ws-4.1.2-session-state-access`
**Date:** 2025-12-06
**Status:** Complete

## Overview

Add helper functions to the TUI Model for accessing active session state. These functions provide a clean API for the TUI to work with multi-session data.

## Problem Statement

With the Model struct now supporting multiple sessions (Task 4.1.1), we need helper functions to:
1. Get the currently active Session struct from the model
2. Fetch the active session's state from Session.State GenServer
3. Look up sessions by tab index (1-10) for keyboard navigation

## Implementation Plan

### Step 1: Implement get_active_session/1 ✅
- [x] Add function to return active Session struct from model.sessions map
- [x] Return nil when no active session

### Step 2: Implement get_active_session_state/1 ✅
- [x] Add function to fetch state from Session.State GenServer
- [x] Use active_session_id to look up state
- [x] Return nil when no active session

### Step 3: Implement get_session_by_index/2 ✅
- [x] Add function to get session by tab index (1-based)
- [x] Index 1-9 map to positions 0-8
- [x] Index 10 (Ctrl+0) maps to position 9
- [x] Return nil for out-of-range indices

### Step 4: Write Unit Tests ✅
- [x] Test get_active_session/1 returns session when active (4 tests)
- [x] Test get_active_session/1 returns nil when no active session
- [x] Test get_active_session_state/1 returns nil when no active session
- [x] Test get_session_by_index/2 returns correct session (7 tests)
- [x] Test get_session_by_index/2 handles edge cases (index 0, negative, >10)

**Total: 26 tests, 0 failures**

## Files to Modify

- `lib/jido_code/tui.ex` - Add helper functions to Model module

## Files to Update

- `test/jido_code/tui/model_test.exs` - Add tests for new helpers

## Success Criteria

1. All helper functions implemented
2. Unit tests pass
3. Functions handle nil/empty cases gracefully
4. No breaking changes to existing TUI functionality

# WS-5.5.3 TUI Integration for Close

**Branch:** `feature/ws-5.5.3-tui-close-integration`
**Date:** 2025-12-06
**Status:** Complete

## Overview

Add keyboard shortcut (Ctrl+W) to close the current session and ensure proper handling when closing the last session.

## Analysis

### Already Implemented in Task 5.5.1

The plan's subtasks 5.5.3.1 and 5.5.3.2 describe implementing session removal in the TUI, which was already done:
- `Model.remove_session/2` handles session removal
- Active session switching logic is implemented (prefers previous, falls back to next)
- TUI handler for `{:close_session, id, name}` exists

### What Needs to Be Implemented

1. **Ctrl+W keyboard shortcut** - Close current active session
2. **Handle last session case** - When active_session_id becomes nil after closing last session

## Implementation Plan

### Step 1: Add Ctrl+W event handler
- [x] Add `event_to_msg` clause for Ctrl+W
- [x] Send `:close_active_session` message

### Step 2: Add update handler for :close_active_session
- [x] Get active session ID
- [x] Trigger close flow using existing logic
- [x] Handle case when no active session

### Step 3: Handle last session closing
- [x] Model.remove_session already sets active_session_id to nil
- [x] View should handle nil active_session_id gracefully

## Files to Modify

- `lib/jido_code/tui.ex` - Add Ctrl+W handler and update function

# WS-5.3.2 Empty List Handling

**Branch:** `feature/ws-5.3.2-empty-list-handling`
**Date:** 2025-12-06
**Status:** Complete

## Overview

Improve the empty session list message to be more helpful by suggesting the `/session new` command.

## Problem Statement

When a user runs `/session list` with no sessions, the current message "No active sessions." doesn't guide them on what to do next.

## Implementation Plan

### Step 1: Update empty list message
- [x] Change message from "No active sessions." to "No sessions. Use /session new to create one."

### Step 2: Update unit test
- [x] Update test to expect new message

## Files Modified

- `lib/jido_code/commands.ex` - Updated empty list message (1 line)
- `test/jido_code/commands_test.exs` - Updated test assertion (1 line)

## Test Results

```
78 Command tests, 0 failures
```

## Success Criteria

1. Empty list shows helpful message with command hint - DONE
2. Unit test updated and passing - DONE

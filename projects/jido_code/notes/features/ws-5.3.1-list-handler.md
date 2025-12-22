# WS-5.3.1 List Handler

**Branch:** `feature/ws-5.3.1-list-handler`
**Date:** 2025-12-06
**Status:** Complete

## Overview

Implement the handler for `/session list` command that displays all sessions with their index, name, and project path.

## Problem Statement

The `/session list` command is parsed but not yet handled. We need to implement `execute_session(:list, model)` to display all sessions in a formatted list.

## Implementation Plan

### Step 1: Implement execute_session(:list, model)
- [x] Get sessions from model (using session_order for consistent ordering)
- [x] Format the output using format_session_list/2
- [x] Return {:ok, output} for display

### Step 2: Implement format_session_list/2
- [x] Take sessions and active_session_id
- [x] Show index number (1-10) for keyboard shortcuts
- [x] Show asterisk (*) for active session
- [x] Show session name and truncated project path

### Step 3: Implement truncate_path/1
- [x] Truncate long paths to @max_path_length (40 chars)
- [x] Keep most relevant parts (end of path)
- [x] Replace home directory with ~

### Step 4: Write unit tests
- [x] Test list with no sessions
- [x] Test list with one session (active)
- [x] Test list with multiple sessions
- [x] Test active session marker
- [x] Test non-active session without marker
- [x] Test path truncation
- [x] Test home directory replacement with ~

## Files Modified

- `lib/jido_code/commands.ex` - Added list handler and helpers (~60 lines)
- `test/jido_code/commands_test.exs` - Added 8 unit tests

## Expected Output Format

```
*1. project-a (~/.../jido_code)
 2. project-b (~/.../other_project)
 3. notes (~/.../notes)
```

## Test Results

```
78 Command tests, 0 failures
```

## Success Criteria

1. `/session list` displays all sessions - DONE
2. Sessions shown in order matching Ctrl+1-0 shortcuts - DONE
3. Active session marked with asterisk - DONE
4. Long paths truncated with ~ for home - DONE
5. Unit tests pass - DONE

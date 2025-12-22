# WS-5.4.2 Switch by ID or Name

**Branch:** `feature/ws-5.4.2-switch-by-name`
**Date:** 2025-12-06
**Status:** Complete

## Overview

Enhance the session switch command to support partial name matching and handle ambiguous names when multiple sessions match.

## Problem Statement

Task 5.4.1 implemented basic exact name matching. This task adds:
1. Case-insensitive matching
2. Partial name matching (prefix matching)
3. Handling ambiguous names when multiple sessions match the prefix

## Implementation Plan

### Step 1: Add case-insensitive matching
- [x] Update find_session_by_name/2 to use case-insensitive comparison
- [x] Try exact match first (case-insensitive)

### Step 2: Add partial name matching
- [x] Fall back to prefix match if no exact match
- [x] Add find_session_by_prefix/2 helper

### Step 3: Handle ambiguous names
- [x] Return {:error, {:ambiguous, names}} if multiple match
- [x] Handle in execute_session to show helpful error message

### Step 4: Write unit tests
- [x] Test case-insensitive matching
- [x] Test prefix matching
- [x] Test exact match preferred over prefix
- [x] Test ambiguous prefix returns error with options
- [x] Test case-insensitive prefix matching

## Files Modified

- `lib/jido_code/commands.ex` - Updated find_session_by_name/2, added find_session_by_prefix/2 (~35 lines)
- `test/jido_code/commands_test.exs` - Added 5 unit tests (~85 lines)

## Test Results

```
90 Command tests, 0 failures
```

## Success Criteria

1. Case-insensitive name matching works - DONE
2. Prefix matching works for unique prefix - DONE
3. Exact match preferred over prefix match - DONE
4. Ambiguous prefix shows helpful error with options - DONE
5. Unit tests pass - DONE

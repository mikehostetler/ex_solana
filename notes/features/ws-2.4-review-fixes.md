# Feature: WS-2.4 Review Fixes

## Problem Statement

The Section 2.4 review identified several concerns and suggested improvements:

### Concerns (from review)

| Priority | Issue | Impact |
|----------|-------|--------|
| Medium | Tool handlers don't yet receive session_id in context | Future work - Section 3.x |
| Low | No UUID format validation for session_id | Could accept invalid session IDs silently |
| Low | Some edge cases in fallback behavior not tested | Minor coverage gap |

### Suggested Improvements

1. Add UUID format validation for session_id
2. Add deprecation logging when global manager fallback is used
3. Add property-based tests for path validation edge cases

## Solution Overview

Address the low-priority concerns that can be fixed now:

1. **UUID Validation**: Add regex validation for session_id format in HandlerHelpers
2. **Deprecation Logging**: Log when falling back to global manager (aids migration tracking)
3. **Edge Case Tests**: Add additional tests for fallback and error scenarios

Note: The medium-priority concern (tool handlers don't receive session_id) is architectural and will be addressed in Section 3.x when the tool execution flow is updated.

## Technical Details

### Files to Modify

- `lib/jido_code/tools/handler_helpers.ex` - Add UUID validation and deprecation logging
- `test/jido_code/tools/handler_helpers_test.exs` - Add edge case tests

### UUID Validation

```elixir
@uuid_regex ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

defp valid_session_id?(session_id) do
  Regex.match?(@uuid_regex, session_id)
end
```

### Deprecation Logging

```elixir
require Logger

def get_project_root(_context) do
  Logger.warning("Using deprecated global Tools.Manager - migrate to session-aware context")
  Manager.project_root()
end
```

## Implementation Plan

### Step 1: Add UUID validation for session_id
- [x] Add @uuid_regex module attribute
- [x] Add private valid_session_id?/1 function
- [x] Update get_project_root/1 to validate UUID format
- [x] Update validate_path/2 to validate UUID format
- [x] Return {:error, :invalid_session_id} for malformed IDs

### Step 2: Add deprecation logging
- [x] Add `require Logger` to module
- [x] Add warning log in get_project_root/1 fallback clause
- [x] Add warning log in validate_path/2 fallback clause
- [x] Make warnings suppressible via application config

### Step 3: Add edge case tests
- [x] Test invalid UUID format returns error
- [x] Test empty string session_id returns error
- [x] Test deprecation warning is logged
- [x] Test suppression of deprecation warnings
- [x] Test UUID case variations (lowercase, uppercase, mixed)
- [x] Test UUID-like strings with wrong length
- [x] Test UUID-like strings with invalid characters
- [x] Test UUID without hyphens

### Step 4: Update documentation
- [x] Update @moduledoc with UUID requirement
- [x] Update @doc for functions with new error cases
- [x] Add format_common_error for :invalid_session_id

### Step 5: Finalize
- [x] Run all tests (34 tests, 0 failures)
- [ ] Update phase-02.md
- [ ] Write summary in notes/summaries

## Success Criteria

- [x] Invalid session_id format returns `{:error, :invalid_session_id}`
- [x] Valid UUIDs continue to work as before
- [x] Deprecation warnings logged when using global fallback
- [x] Warnings can be suppressed via config
- [x] All existing tests pass
- [x] New edge case tests pass (14 new tests)

## Current Status

**Status**: Complete

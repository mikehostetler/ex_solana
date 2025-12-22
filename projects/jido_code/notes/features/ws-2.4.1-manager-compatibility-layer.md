# Feature: WS-2.4.1 Manager Compatibility Layer

## Problem Statement

The global `JidoCode.Tools.Manager` currently operates at application scope with a single project root. With the introduction of per-session managers (`JidoCode.Session.Manager`), we need a compatibility layer that:

1. Allows tool handlers to work with session-scoped managers when a `session_id` is provided in context
2. Maintains backwards compatibility for code that still uses the global manager
3. Provides clear deprecation warnings to guide migration
4. Documents the migration path for users

## Solution Overview

Update `Tools.Manager` to accept an optional `session_id` in context and delegate to `Session.Manager` when present. When no session is provided, fall back to the global manager behavior with a deprecation warning.

## Technical Details

### Files to Modify

- `lib/jido_code/tools/manager.ex` - Add session-aware API functions

### New API Pattern

```elixir
# Session-aware API (preferred)
Tools.Manager.project_root(session_id: "abc123")
# => Delegates to Session.Manager.project_root("abc123")

# Global API (deprecated, still works)
Tools.Manager.project_root()
# => Uses global manager, logs deprecation warning
```

### Key Design Decisions

1. **Optional keyword argument**: Use `opts \\ []` with optional `:session_id` key
2. **Deprecation warnings**: Log at `:warning` level when using global manager
3. **Delegation pattern**: Direct delegation to Session.Manager when session_id present
4. **No breaking changes**: All existing calls continue to work

## Implementation Plan

### Step 1: Add session-aware project_root/1
- [x] Add `project_root/1` that accepts options
- [x] Check for `:session_id` in options
- [x] Delegate to `Session.Manager.project_root/1` when session_id present
- [x] Fall back to global call when absent
- [x] Add deprecation warning for global usage

### Step 2: Add session-aware validate_path/2
- [x] Update `validate_path/2` to accept optional session_id
- [x] Delegate to `Session.Manager.validate_path/2` when session_id present
- [x] Fall back to global with deprecation warning

### Step 3: Add session-aware file operations
- [x] Update `read_file/1` -> `read_file/2` with optional session_id
- [x] Update `write_file/2` -> `write_file/3` with optional session_id
- [x] Update `list_dir/1` -> `list_dir/2` with optional session_id
- [x] All delegate to Session.Manager when session_id present

### Step 4: Add deprecation documentation
- [x] Update @moduledoc with deprecation notice
- [x] Document migration path from global to session-scoped
- [x] Add examples showing both old and new patterns

### Step 5: Write tests
- [x] Test delegation to Session.Manager with session_id
- [x] Test fallback to global without session_id
- [x] Test deprecation warning is logged
- [x] Test backwards compatibility

### Step 6: Update phase plan
- [x] Mark Task 2.4.1 as complete in phase-02.md

## Success Criteria

- [x] `Tools.Manager` accepts `session_id` option in relevant functions
- [x] Delegates to `Session.Manager` when session_id is provided
- [x] Falls back to global behavior when session_id is absent
- [x] Logs deprecation warning for global usage
- [x] All existing tests continue to pass
- [x] New tests cover session-aware behavior

## Current Status

**Status**: Complete

## Notes

- The deprecation warnings should be opt-out via config for test environments
- Future work (Task 2.4.2) will update HandlerHelpers to prefer session context

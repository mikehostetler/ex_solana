# Summary: WS-3.2.1 FileSystem Handlers Session Context

## Overview

This task updated all filesystem handlers to use session-aware path validation via `HandlerHelpers.validate_path/2`. The handlers now properly use `Session.Manager` when a `session_id` is present in the context.

## Changes Made

### Updated Handler Pattern

All 7 filesystem handlers were updated from using global `Tools.Manager` to using session-aware path validation:

**Before**:
```elixir
def execute(%{"path" => path}, _context) when is_binary(path) do
  case Manager.read_file(path) do
    {:ok, content} -> {:ok, content}
    {:error, reason} -> {:error, format_error(reason, path)}
  end
end
```

**After**:
```elixir
def execute(%{"path" => path}, context) when is_binary(path) do
  with {:ok, safe_path} <- FileSystem.validate_path(path, context) do
    case File.read(safe_path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, format_error(reason, path)}
    end
  else
    {:error, reason} -> {:error, format_error(reason, path)}
  end
end
```

### Handlers Updated

1. **ReadFile** - Uses validated path with `File.read/1`
2. **WriteFile** - Uses validated path with `File.write/2` and `File.mkdir_p/1`
3. **EditFile** - Uses validated path for read/write operations
4. **ListDirectory** - Uses validated path with `File.ls/1` and `File.dir?/1`
5. **FileInfo** - Uses validated path with `File.stat/1`
6. **CreateDirectory** - Uses validated path with `File.mkdir_p/1`
7. **DeleteFile** - Uses validated path with `File.rm/1`

### Context Support

Handlers now support three context types (via `HandlerHelpers`):

1. `session_id` (preferred) - Delegates to `Session.Manager.validate_path/2`
2. `project_root` (legacy) - Uses `Security.validate_path/3` directly
3. Neither - Falls back to global `Tools.Manager` with deprecation warning

### ListDirectory Fix

Fixed recursive listing to return relative paths instead of absolute paths:
- Added `base_path` parameter to track the root for relative path calculation
- Uses `Path.relative_to/2` to compute relative names

## Test Results

All 46 filesystem handler tests pass:
- 41 existing tests using `project_root` context
- 5 new session-aware tests:
  - ReadFile uses session_id for path validation
  - WriteFile uses session_id for path validation
  - session_id context rejects path traversal
  - invalid session_id returns error
  - non-existent session_id returns error

## Files Changed

### Modified
- `lib/jido_code/tools/handlers/file_system.ex` - Session-aware handlers
- `test/jido_code/tools/handlers/file_system_test.exs` - Session context tests
- `notes/planning/work-session/phase-03.md` - Marked Task 3.2.1 complete

### Created
- `notes/features/ws-3.2.1-filesystem-handlers.md` - Planning document
- `notes/summaries/ws-3.2.1-filesystem-handlers.md` - This summary

## Impact

1. **Security**: Filesystem handlers now properly use session-scoped path validation
2. **Isolation**: Each session's file operations are validated against its project boundary
3. **Backwards Compatibility**: Handlers still work with legacy `project_root` context
4. **Deprecation Path**: Global `Tools.Manager` usage logs warnings to encourage migration

## Next Steps

Task 3.2.2 - Search Handlers: Update search handlers (Grep, FindFiles) to use session context for path validation.

# Feature: WS-3.2.1 FileSystem Handlers Session Context

## Problem Statement

The filesystem handlers currently use the global `Tools.Manager` for file operations. This bypasses session-scoped security boundaries and doesn't leverage the per-session `Session.Manager` for path validation.

Task 3.2.1 requires updating all filesystem handlers to use session context for path validation via `Session.Manager`.

## Current State

### Current Handler Pattern

```elixir
# ReadFile - uses global Tools.Manager
def execute(%{"path" => path}, _context) when is_binary(path) do
  case Manager.read_file(path) do
    {:ok, content} -> {:ok, content}
    {:error, reason} -> {:error, format_error(reason, path)}
  end
end
```

### Available Session-Aware Helpers

`HandlerHelpers` already provides session-aware functions:
- `validate_path/2` - Validates path using Session.Manager when session_id present
- `get_project_root/1` - Gets project root from Session.Manager
- `format_common_error/2` - Formats common errors

## Solution Overview

Update all filesystem handlers to:
1. Use `HandlerHelpers.validate_path/2` for path validation
2. Use standard `File` module operations on the validated path
3. Maintain backwards compatibility with legacy `project_root` context

### New Handler Pattern

```elixir
def execute(%{"path" => path}, context) when is_binary(path) do
  with {:ok, safe_path} <- HandlerHelpers.validate_path(path, context) do
    case File.read(safe_path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, format_error(reason, path)}
    end
  else
    {:error, reason} -> {:error, format_error(reason, path)}
  end
end
```

## Technical Details

### Files to Modify

- `lib/jido_code/tools/handlers/file_system.ex` - All 7 handler sub-modules

### Session.Manager API

| Operation | Session.Manager Method |
|-----------|----------------------|
| Validate path | `validate_path(session_id, path)` |
| Read file | `read_file(session_id, path)` |
| Write file | `write_file(session_id, path, content)` |
| List directory | `list_dir(session_id, path)` |

### Missing Operations

These operations don't exist in Session.Manager yet:
- `file_stat` - Get file metadata
- `mkdir_p` - Create directories recursively
- `is_dir?` - Check if path is directory
- `delete_file` - Delete a file

For these, we'll use `HandlerHelpers.validate_path/2` then call `File` directly.

## Implementation Plan

### Step 1: Update ReadFile handler
- [x] Use `HandlerHelpers.validate_path/2` for path validation
- [x] Use `File.read/1` with validated path
- [x] Handle errors appropriately

### Step 2: Update WriteFile handler
- [x] Use `HandlerHelpers.validate_path/2` for path validation
- [x] Create parent directories using validated path
- [x] Use `File.write/2` with validated path

### Step 3: Update EditFile handler
- [x] Use `HandlerHelpers.validate_path/2` for path validation
- [x] Read file using validated path
- [x] Write modified content using validated path

### Step 4: Update ListDirectory handler
- [x] Use `HandlerHelpers.validate_path/2` for path validation
- [x] Use `File.ls/1` with validated path
- [x] Update recursive listing to use validated paths

### Step 5: Update FileInfo handler
- [x] Use `HandlerHelpers.validate_path/2` for path validation
- [x] Use `File.stat/1` with validated path

### Step 6: Update CreateDirectory handler
- [x] Use `HandlerHelpers.validate_path/2` for path validation
- [x] Use `File.mkdir_p/1` with validated path

### Step 7: Update DeleteFile handler
- [x] Use `HandlerHelpers.validate_path/2` for path validation
- [x] Use `File.rm/1` with validated path

### Step 8: Write unit tests
- [x] Test each handler with session context
- [x] Test path validation errors
- [x] Test backwards compatibility with project_root

## Success Criteria

- [x] All filesystem handlers use session-aware path validation
- [x] Handlers work with both session_id and project_root context
- [x] All existing tests pass
- [x] New tests cover session context usage

## Current Status

**Status**: Complete

All filesystem handlers have been updated to use session-aware path validation.

## Test Results

- 46 filesystem handler tests pass
- 5 new session-aware tests added

## Files Changed

### Modified
- `lib/jido_code/tools/handlers/file_system.ex` - Session-aware handlers
- `test/jido_code/tools/handlers/file_system_test.exs` - Added session context tests
- `notes/planning/work-session/phase-03.md` - Marked Task 3.2.1 complete

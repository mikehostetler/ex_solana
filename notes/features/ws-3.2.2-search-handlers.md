# Feature: WS-3.2.2 Search Handlers Session Context

## Problem Statement

The search handlers (Grep, FindFiles) currently use the global `Tools.Manager` for file operations. This bypasses session-scoped security boundaries and doesn't leverage the per-session `Session.Manager` for path validation.

Task 3.2.2 requires updating search handlers to use session context for path validation.

## Current State

### Current Handler Pattern

```elixir
# Grep - uses global Tools.Manager
def execute(%{"pattern" => pattern, "path" => path} = args, _context) do
  with {:ok, regex} <- compile_pattern(pattern),
       :ok <- validate_search_path(path) do  # Uses Manager.is_dir?
    results = search_files(path, regex, recursive, max_results)  # Uses Manager methods
    {:ok, Jason.encode!(results)}
  end
end
```

## Solution Overview

Update search handlers to:
1. Use `HandlerHelpers.validate_path/2` for base path validation
2. Use `HandlerHelpers.get_project_root/1` to get the project root
3. Use standard `File` module operations on validated paths
4. Maintain backwards compatibility with legacy `project_root` context

### New Handler Pattern

```elixir
def execute(%{"pattern" => pattern, "path" => path} = args, context) do
  with {:ok, safe_path} <- Search.validate_path(path, context),
       {:ok, project_root} <- Search.get_project_root(context),
       {:ok, regex} <- compile_pattern(pattern) do
    results = search_files(safe_path, project_root, regex, recursive, max_results)
    {:ok, Jason.encode!(results)}
  end
end
```

## Implementation Plan

### Step 1: Update Grep handler
- [x] Add `validate_path/2` delegate to Search module
- [x] Update `execute/2` to use session context
- [x] Replace `Manager` calls with `File` module operations
- [x] Update file collection to use validated paths

### Step 2: Update FindFiles handler
- [x] Update `execute/2` to use session context
- [x] Use `HandlerHelpers.validate_path/2` for base path
- [x] Use `HandlerHelpers.get_project_root/1` for relative path computation

### Step 3: Write unit tests
- [x] Test Grep with session context
- [x] Test FindFiles with session context
- [x] Test path validation errors

## Success Criteria

- [x] Search handlers use session-aware path validation
- [x] Handlers work with both session_id and project_root context
- [x] All existing tests pass
- [x] New tests cover session context usage

## Current Status

**Status**: Complete

## Test Results

- 27 search handler tests pass (21 existing + 6 new)
- 6 new session-aware tests:
  - Grep uses session_id for path validation
  - FindFiles uses session_id for path validation
  - session_id context rejects path traversal in Grep
  - session_id context rejects path traversal in FindFiles
  - invalid session_id returns error in Grep
  - invalid session_id returns error in FindFiles

## Files Changed

### Modified
- `lib/jido_code/tools/handlers/search.ex` - Session-aware handlers
- `test/jido_code/tools/handlers/search_test.exs` - Added session context tests

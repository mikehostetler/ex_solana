# Feature: WS-3.2.5 Livebook Handler Session Context

## Problem Statement

The Livebook handler (`EditCell`) currently uses the global `Tools.Manager` for file operations (`Manager.read_file`, `Manager.write_file`). This bypasses session-scoped security boundaries and doesn't leverage the per-session path validation.

Task 3.2.5 requires updating the Livebook handler to use session context for notebook path validation.

## Current State

### Current Handler Pattern

```elixir
def execute(%{"notebook_path" => path, ...} = args, _context) do
  with {:ok, content} <- Manager.read_file(path),  # Global Manager
       {:ok, notebook} <- Parser.parse(content),
       {:ok, updated_notebook} <- apply_edit(...),
       :ok <- Manager.write_file(path, new_content) do  # Global Manager
    {:ok, message}
  end
end
```

## Solution Overview

Update the Livebook handler to:
1. Add `validate_path/2` delegate to Livebook module
2. Use `HandlerHelpers.validate_path/2` to validate notebook path against session boundary
3. Use standard `File.read/1` and `File.write/2` on validated paths
4. Maintain backwards compatibility with legacy `project_root` context

### New Handler Pattern

```elixir
def execute(%{"notebook_path" => path, ...} = args, context) do
  with {:ok, safe_path} <- Livebook.validate_path(path, context),
       {:ok, content} <- File.read(safe_path),
       {:ok, notebook} <- Parser.parse(content),
       {:ok, updated_notebook} <- apply_edit(...),
       :ok <- File.write(safe_path, new_content) do
    {:ok, message}
  end
end
```

## Implementation Plan

### Step 1: Add validate_path delegate
- [x] Add `validate_path/2` delegate to Livebook module

### Step 2: Update EditCell.execute/2
- [x] Use `Livebook.validate_path/2` for path validation
- [x] Use standard `File` module for read/write operations
- [x] Update both execute clauses (replace/insert and delete modes)

### Step 3: Write unit tests
- [x] Test EditCell with session context
- [x] Test path traversal rejection with session context
- [x] Test invalid session_id returns error

## Success Criteria

- [x] Livebook handler uses session-aware path validation
- [x] Handler works with both session_id and project_root context
- [x] All existing tests pass
- [x] New tests cover session context usage

## Current Status

**Status**: Complete

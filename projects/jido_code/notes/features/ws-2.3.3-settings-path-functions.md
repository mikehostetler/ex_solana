# Feature: WS-2.3.3 Settings Path Functions

## Problem Statement

Task 2.3.3 requires implementing helper functions for settings paths. Looking at the subtasks:
- 2.3.3.1 `local_path/1` - Already implemented in Task 2.3.1
- 2.3.3.2 `local_dir/1` - Already implemented in Task 2.3.1
- 2.3.3.3 `ensure_local_dir/1` - **Needs implementation**
- 2.3.3.4 Write unit tests - Tests for local_path/1 and local_dir/1 already exist

The only new work is implementing `ensure_local_dir/1` to create the settings directory if it doesn't exist.

## Solution Overview

Add `ensure_local_dir/1` to `JidoCode.Session.Settings`:
- Creates `{project_path}/.jido_code` directory if missing
- Returns `{:ok, path}` on success
- Returns `{:error, reason}` on failure
- Uses `File.mkdir_p/1` for recursive directory creation

### Key Decisions

1. **Return tuple** - Use `{:ok, path}` / `{:error, reason}` pattern for consistency with file operations
2. **Use mkdir_p** - Create parent directories if needed (though typically only one level)
3. **Idempotent** - Safe to call multiple times (no error if directory exists)

## Technical Details

### Files to Modify

| File | Changes |
|------|---------:|
| `lib/jido_code/session/settings.ex` | Add ensure_local_dir/1 |
| `test/jido_code/session/settings_test.exs` | Add tests for ensure_local_dir/1 |

### New Function

```elixir
@doc """
Ensures the local settings directory exists for a project.

Creates `{project_path}/.jido_code` directory if it doesn't exist.

## Parameters

- `project_path` - Absolute path to the project root

## Returns

- `{:ok, dir_path}` - Directory exists or was created successfully
- `{:error, reason}` - Failed to create directory

## Examples

    iex> Session.Settings.ensure_local_dir("/path/to/project")
    {:ok, "/path/to/project/.jido_code"}

    iex> Session.Settings.ensure_local_dir("/readonly/path")
    {:error, :eacces}
"""
@spec ensure_local_dir(String.t()) :: {:ok, String.t()} | {:error, File.posix()}
def ensure_local_dir(project_path) when is_binary(project_path) do
  dir = local_dir(project_path)
  case File.mkdir_p(dir) do
    :ok -> {:ok, dir}
    {:error, reason} -> {:error, reason}
  end
end
```

## Implementation Plan

### Step 1: Implement ensure_local_dir/1
- [x] Add `ensure_local_dir/1` function
- [x] Add @doc and @spec
- [x] Use File.mkdir_p for recursive creation

### Step 2: Write Unit Tests
- [x] Test creates directory when missing
- [x] Test returns ok when directory exists
- [x] Test returns directory path on success

### Step 3: Mark Subtasks Complete
- [x] Mark 2.3.3.1 as complete (already done in 2.3.1)
- [x] Mark 2.3.3.2 as complete (already done in 2.3.1)
- [x] Mark 2.3.3.3 as complete
- [x] Mark 2.3.3.4 as complete

## Success Criteria

- [x] `ensure_local_dir/1` creates directory if missing
- [x] `ensure_local_dir/1` returns ok if directory exists
- [x] All tests pass

## Current Status

**Status**: Complete

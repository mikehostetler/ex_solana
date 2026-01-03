# Task 1.5.2: List Dir Bridge Function Implementation

## Summary

Updated the `lua_list_dir/3` bridge function with type indicators, directory-first sorting, and ignore_patterns support.

## Completed Items

- [x] Updated `lua_list_dir/3` to accept optional second argument with options
- [x] Added type indicators to each entry (`name` and `type` fields)
- [x] Implemented directory-first sorting (directories before files, then alphabetically)
- [x] Added `ignore_patterns` option with glob pattern matching
- [x] Added "Not a directory" error for file paths
- [x] Updated 12 bridge tests for new functionality

## Files Modified

| File | Changes |
|------|---------|
| `lib/jido_code/tools/bridge.ex` | Enhanced `lua_list_dir/3` with ~125 lines of new functionality |
| `test/jido_code/tools/bridge_test.exs` | Updated and added 12 tests for lua_list_dir |
| `notes/planning/tooling/phase-01-tools.md` | Marked 1.5.2 as completed |

## API Changes

### Before

```elixir
# Simple string array
{[result], state} = Bridge.lua_list_dir(["path"], state, project_root)
# result = [{1, "file.txt"}, {2, "subdir"}]
```

### After

```elixir
# Array of typed entries, sorted with directories first
{[result], state} = Bridge.lua_list_dir(["path"], state, project_root)
# result = [{1, [{"name", "subdir"}, {"type", "directory"}]},
#           {2, [{"name", "file.txt"}, {"type", "file"}]}]

# With ignore patterns
opts = [{"ignore_patterns", [{1, "*.log"}, {2, "node_modules"}]}]
{[result], state} = Bridge.lua_list_dir(["path", opts], state, project_root)
```

## Features Added

1. **Type Indicators**: Each entry now includes:
   - `name` - Entry name (string)
   - `type` - Either "file" or "directory"

2. **Directory-First Sorting**: Entries are sorted with:
   - Directories first
   - Then files
   - Each group sorted alphabetically

3. **Ignore Patterns**: Optional filtering via glob patterns:
   - `*.log` - Match all .log files
   - `node_modules` - Match exact name
   - `*.test.js` - Match test files

4. **Better Error Messages**: "Not a directory" error for file paths

## Test Coverage

12 tests covering:
- Type indicators in output
- Directory-first sorting
- Subdirectory listing
- Empty directory handling
- Non-existent directory error
- Path traversal security
- Default to project root
- ignore_patterns option
- Wildcard pattern matching
- Empty patterns (no effect)
- File path error (not directory)

## Next Task

**1.5.3: Unit Tests for List Directory** - Additional integration tests for list_dir through the sandbox.

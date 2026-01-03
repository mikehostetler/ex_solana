# Task 1.1.2: Read File Bridge Function Implementation

**Status**: ✅ Complete
**Branch**: `feature/1.1.2-read-file-bridge-function`
**Plan Reference**: `notes/planning/tooling/phase-01-tools.md` - Section 1.1.2

## Summary

Enhanced the `lua_read_file/3` bridge function with full support for offset/limit pagination, line-numbered output formatting (cat -n style), binary file detection, and long line truncation. This implements the core file reading logic for the Lua sandbox architecture.

## Changes Made

### Modified Files

1. **`lib/jido_code/tools/bridge.ex`**
   - Added module constants for defaults and limits:
     - `@default_offset 1`
     - `@default_limit 2000`
     - `@max_line_length 2000`
   - Enhanced `lua_read_file/3` to handle options via `parse_read_opts/1`
   - Added `do_read_file/4` private function with full implementation
   - Added helper functions:
     - `is_binary_content?/1` - Detects binary files by checking for null bytes in first 8KB
     - `format_with_line_numbers/3` - Formats content with cat -n style line numbers
     - `truncate_line/1` - Truncates lines exceeding 2000 chars with `[truncated]` indicator
     - `pad_line_number/2` - Right-aligns line numbers with configurable width

2. **`test/jido_code/tools/bridge_test.exs`**
   - Updated existing tests to expect line-numbered output format
   - Added new test cases for:
     - Multi-line file reading with line numbers
     - Offset parameter (skip initial lines)
     - Limit parameter (cap output lines)
     - Long line truncation with indicator
     - Binary file rejection
     - Empty file handling
   - Added unit test blocks for helper functions:
     - `describe "is_binary_content?/1"` - 3 tests
     - `describe "format_with_line_numbers/3"` - 6 tests

## Implementation Details

### Line Number Formatting

Output uses cat -n style with `→` separator:
```
     1→first line
     2→second line
     3→third line
```

Line number width adjusts dynamically based on total line count (minimum 6 characters for alignment).

### Options Support

Lua options passed as table `{{"offset", 3}, {"limit", 10}}` are parsed to Elixir map `%{offset: 3, limit: 10}`.

### Binary Detection

Files are detected as binary if they contain null bytes (`<<0>>`) within the first 8192 bytes. Binary files return an error: `"Cannot read binary file: <path>"`.

### Long Line Truncation

Lines exceeding 2000 characters are truncated with `[truncated]` indicator appended.

## Test Results

```
68 tests, 0 failures
```

All bridge tests pass including:
- 15 lua_read_file tests (line numbers, offset, limit, truncation, binary detection)
- 3 is_binary_content?/1 unit tests
- 6 format_with_line_numbers/3 unit tests
- Existing tests for other bridge functions

## Architecture Notes

This implementation follows the Lua sandbox architecture per [ADR-0001](../decisions/0001-tool-security-architecture.md):

```
Lua VM → jido.read_file(path, opts) → Bridge.lua_read_file/3 → Security.atomic_read/2 → File
```

Key security features:
1. Path validation via `Security.atomic_read/2` (TOCTOU-safe)
2. All paths resolved relative to project root
3. Path traversal attempts blocked at Security layer

## Next Steps

Task 1.1.3: Manager API
- Add `read_file/2` to `Tools.Manager` with session_id option
- Route calls through Lua VM to bridge function
- Support session-scoped manager isolation

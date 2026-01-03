# Task 1.1.2: Read File Bridge Function

**Status**: Complete
**Branch**: `feature/1.1.2-read-file-bridge`
**Plan Reference**: `notes/planning/tooling/phase-01-tools.md` - Section 1.1.2

## Summary

Implemented the `lua_read_file/3` bridge function that provides secure file reading through the Lua sandbox with line-numbered output formatting.

## Changes Made

### Modified Files

1. **`lib/jido_code/tools/bridge.ex`**
   - Added `lua_read_file/3` function (lines 100-122)
   - Uses `Security.atomic_read/2` for TOCTOU-safe file reading
   - Implements offset/limit support via module attributes:
     - `@default_offset 1`
     - `@default_limit 2000`
     - `@max_line_length 2000`
   - Added `format_with_line_numbers/3` for cat -n style output with arrow separator
   - Added `truncate_line/1` for 2000-character line truncation with `[truncated]` indicator
   - Added `is_binary_content?/1` for null byte detection in first 8KB
   - Added `parse_read_opts/1` for Lua table to Elixir map conversion
   - Returns `{[content], state}` on success or `{[nil, error_msg], state}` on failure
   - Registered in `Bridge.register/2`

## Implementation Details

### Line Number Format

```
     1→first line
     2→second line
     3→third line
```

- Line numbers are right-padded based on total line count
- Uses `→` as separator between line number and content
- 1-indexed to match editor conventions

### Binary Detection

Checks first 8KB for null bytes (common binary file indicator):

```elixir
def is_binary_content?(content) when is_binary(content) do
  sample_size = min(byte_size(content), 8192)
  sample = :binary.part(content, 0, sample_size)
  String.contains?(sample, <<0>>)
end
```

### Security Integration

Uses `Security.atomic_read/3` for TOCTOU mitigation:
1. Validates path against project boundary
2. Reads file atomically
3. Re-validates realpath after read

### Lua Table Handling

Bridge handles both direct Elixir calls and Lua table references:
- Direct calls: `[path, [{\"offset\", 3}]]`
- Lua calls: `[path, {:tref, 14}]` - decoded via `:luerl.decode/2`

## Test Coverage

17+ tests in `bridge_test.exs`:
- Line-numbered content formatting
- Offset and limit options
- Long line truncation
- Binary file rejection
- Path security validation
- Windows line ending handling
- Large file line number formatting

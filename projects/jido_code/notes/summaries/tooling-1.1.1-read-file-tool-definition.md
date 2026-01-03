# Task 1.1.1: Read File Tool Definition

**Status**: ✅ Complete
**Branch**: `feature/1.1.1-read-file-tool-definition`
**Plan Reference**: `notes/planning/tooling/phase-01-tools.md` - Section 1.1.1

## Summary

Implemented the enhanced `read_file` tool definition with offset and limit parameters for the Lua sandbox architecture. This tool definition provides the LLM interface schema for reading file contents with line numbers.

## Changes Made

### New Files

1. **`lib/jido_code/tools/definitions/file_read.ex`**
   - New module `JidoCode.Tools.Definitions.FileRead`
   - Comprehensive module documentation including execution flow diagram
   - `read_file/0` function returning `Tool.t()` with enhanced parameters
   - `default_limit/0` function returning 2000 (configurable constant)
   - `all/0` function for batch registration

### Modified Files

1. **`lib/jido_code/tools/definitions/file_system.ex`**
   - Added alias to `FileRead` module
   - Updated `read_file/0` to delegate to `FileRead.read_file/0`
   - Updated documentation to reflect new parameters

2. **`test/jido_code/tools/definitions/file_system_test.exs`**
   - Updated test to expect 3 parameters instead of 1
   - Added assertions for offset and limit parameter properties

### New Test Files

1. **`test/jido_code/tools/definitions/file_read_test.exs`**
   - 18 test cases covering:
     - Tool struct validation
     - Parameter schemas (path, offset, limit)
     - Default values (offset=1, limit=2000)
     - LLM format conversion
     - Argument validation

## Tool Schema

```elixir
%Tool{
  name: "read_file",
  description: "Read file contents with line numbers...",
  handler: JidoCode.Tools.Handlers.FileSystem.ReadFile,
  parameters: [
    %{name: "path", type: :string, required: true},
    %{name: "offset", type: :integer, required: false, default: 1},
    %{name: "limit", type: :integer, required: false, default: 2000}
  ]
}
```

## Test Results

```
36 tests, 0 failures
```

All tests pass including:
- FileRead module tests (18 tests)
- FileSystem definition tests (updated for new schema)

## Architecture Notes

This tool definition is part of the Lua sandbox architecture per [ADR-0001](../decisions/0001-tool-security-architecture.md):

```
LLM Tool Call → Tool Executor → Tools.Manager → Lua VM → jido.read_file → Bridge → Security
```

The tool definition provides:
1. LLM-compatible schema via `Tool.to_llm_function/1`
2. Argument validation via `Tool.validate_args/2`
3. Handler reference for execution dispatch

## Next Steps

Task 1.1.2: Bridge Function Implementation
- Add `lua_read_file/3` to `lib/jido_code/tools/bridge.ex`
- Implement line-numbered output formatting
- Handle offset/limit parameters
- Binary file detection

# Task 1.5.1: List Dir Tool Definition

## Summary

Implemented the `list_dir` tool definition for directory listing with glob pattern filtering support.

## Completed Items

- [x] Created `lib/jido_code/tools/definitions/list_dir.ex` with full documentation
- [x] Defined tool schema with `path` (required) and `ignore_patterns` (optional array)
- [x] Added `list_dir()` to `FileSystem.all/0` via defdelegate
- [x] Created `ListDir` handler with glob pattern filtering support
- [x] Created comprehensive definition tests (25 tests)
- [x] Updated `FileSystem.all/0` test to expect 9 tools

## Files Created

| File | Purpose |
|------|---------|
| `lib/jido_code/tools/definitions/list_dir.ex` | Tool definition with schema and documentation |
| `test/jido_code/tools/definitions/list_dir_test.exs` | 25 definition tests |

## Files Modified

| File | Changes |
|------|---------|
| `lib/jido_code/tools/definitions/file_system.ex` | Added alias, defdelegate, and list_dir to all/0 |
| `lib/jido_code/tools/handlers/file_system.ex` | Added ListDir handler module (~120 lines) |
| `test/jido_code/tools/definitions/file_system_test.exs` | Updated to expect 9 tools |
| `notes/planning/tooling/phase-01-tools.md` | Marked 1.5.1 as completed |

## Tool Schema

```elixir
%{
  name: "list_dir",
  description: "List directory contents with type indicators...",
  handler: JidoCode.Tools.Handlers.FileSystem.ListDir,
  parameters: [
    %{name: "path", type: :string, required: true},
    %{name: "ignore_patterns", type: :array, required: false, items: :string}
  ]
}
```

## Handler Features

The `ListDir` handler includes:

1. **Glob Pattern Filtering**: Supports patterns like `*.log`, `node_modules`, `*.test.js`
2. **Directory-First Sorting**: Directories listed before files, then alphabetically
3. **Type Indicators**: Each entry has `name` and `type` (file or directory)
4. **Security Integration**: Uses session-aware path validation

## Test Coverage

25 tests covering:
- Tool struct validation
- Parameter definitions
- LLM format conversion
- Argument validation (valid/invalid cases)
- FileSystem delegation

## Next Task

**1.5.2: Bridge Function Implementation** - Update the Lua bridge function to support ignore_patterns if needed.

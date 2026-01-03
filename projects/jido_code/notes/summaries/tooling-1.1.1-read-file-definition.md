# Task 1.1.1: Read File Tool Definition

**Status**: Complete
**Branch**: `feature/1.1.1-read-file-definition`
**Plan Reference**: `notes/planning/tooling/phase-01-tools.md` - Section 1.1.1

## Summary

Created the read_file tool definition with proper schema, parameters, and registration.

## Changes Made

### Created Files

1. **`lib/jido_code/tools/definitions/file_read.ex`**
   - Module documentation with usage examples
   - Tool schema with three parameters:
     - `path` (required, string): Absolute path to file
     - `offset` (optional, integer, default: 1): Line number to start from
     - `limit` (optional, integer, default: 2000): Maximum lines to read
   - Default limit constant `@default_limit 2000`
   - Maximum line length constant `@max_line_length 2000`
   - LLM function format via `Tool.to_llm_function/1`
   - Registration via `Tool.new!/1`

## API Examples

```elixir
# Get tool definition
tool = FileRead.read_file()

# Convert to LLM function format
llm_func = Tool.to_llm_function(tool)

# All definitions
tools = FileRead.all()
```

## Schema Definition

```elixir
%{
  name: "read_file",
  description: "Reads a file from the local filesystem...",
  parameters: [
    %{
      name: "path",
      type: :string,
      required: true,
      description: "The absolute path to the file to read"
    },
    %{
      name: "offset",
      type: :integer,
      required: false,
      default: 1,
      description: "Line number to start from (1-indexed)"
    },
    %{
      name: "limit",
      type: :integer,
      required: false,
      default: 2000,
      description: "Maximum number of lines to read"
    }
  ]
}
```

## Test Results

All definition tests pass including:
- Schema validation tests
- Parameter type tests
- LLM function format tests
- Default value tests

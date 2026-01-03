# Task 1.3.1 Edit File Tool Definition Summary

## Overview

Created the `edit_file` tool definition for performing targeted string replacement within files.

## Completed Tasks

- [x] 1.3.1.1 Create tool definition in `lib/jido_code/tools/definitions/file_edit.ex`
- [x] 1.3.1.2 Define schema with path, old_string, new_string, replace_all parameters
- [x] 1.3.1.3 Document that old_string must be unique in file

## Files Created

### `lib/jido_code/tools/definitions/file_edit.ex`

Tool definition module with:

**Parameters:**
| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `path` | string | Yes | - | Path to file (relative to project root) |
| `old_string` | string | Yes | - | Exact text to find and replace |
| `new_string` | string | Yes | - | Replacement text (can be empty) |
| `replace_all` | boolean | No | false | Replace all occurrences |

**Key Documentation:**
- Uniqueness requirement: old_string must appear exactly once (unless replace_all)
- Multi-strategy matching: Planned fallback strategies documented
- Read-before-write: File must be read before editing
- Best practices for ensuring unique matches

### `test/jido_code/tools/definitions/file_edit_test.exs`

Comprehensive test file with 25 tests covering:
- Tool struct validation
- Parameter validation (path, old_string, new_string, replace_all)
- LLM format conversion
- Argument validation (valid, invalid types, missing required, unknown params)

## Test Results

```
Finished in 0.1 seconds
25 tests, 0 failures
```

## Tool Definition

```elixir
Tool.new!(%{
  name: "edit_file",
  description: "Edit a file by replacing old_string with new_string...",
  handler: JidoCode.Tools.Handlers.FileSystem.EditFile,
  parameters: [
    %{name: "path", type: :string, required: true, ...},
    %{name: "old_string", type: :string, required: true, ...},
    %{name: "new_string", type: :string, required: true, ...},
    %{name: "replace_all", type: :boolean, required: false, default: false}
  ]
})
```

## Key Design Decisions

### Uniqueness Requirement
The `old_string` must appear exactly once in the file by default. This prevents:
- Accidental modifications to unintended locations
- Ambiguous edits that could break code in unexpected places

If multiple occurrences exist, the user must either:
1. Provide a more specific `old_string` with surrounding context
2. Set `replace_all: true` to explicitly replace all occurrences

### Multi-Strategy Matching (Planned for 1.3.2)
The handler will implement fallback matching strategies:
1. **Exact match** - Literal string comparison (primary)
2. **Line-trimmed match** - Ignores leading/trailing whitespace per line
3. **Whitespace-normalized match** - Collapses multiple spaces/tabs
4. **Indentation-flexible match** - Allows different indentation levels

This follows patterns from OpenCode and other coding assistants.

### Read-Before-Write
Like `write_file`, the `edit_file` tool will require the file to be read first.
This is documented but will be enforced in task 1.3.2 (handler implementation).

## Next Steps

- **Task 1.3.2**: Edit Handler Implementation
  - Add read-before-write checking
  - Implement multi-strategy matching fallbacks
  - Add atomic write operations
  - Add file tracking and telemetry

- **Task 1.3.3**: Unit Tests for Edit File Handler
  - Test exact match, whitespace variations, indentation
  - Test uniqueness validation
  - Test read-before-write requirement

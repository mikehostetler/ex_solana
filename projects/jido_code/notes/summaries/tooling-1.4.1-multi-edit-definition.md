# Task 1.4.1: Multi-Edit File Tool Definition

**Date**: 2025-12-29
**Branch**: `feature/1.4.1-multi-edit-definition`
**Status**: Complete

---

## Overview

Implemented the tool definition for `multi_edit_file`, which enables atomic batch editing of files with multiple search/replace operations. All edits succeed or all fail - the file remains unchanged if any validation fails.

---

## Implementation Details

### New Files Created

| File | Purpose |
|------|---------|
| `lib/jido_code/tools/definitions/file_multi_edit.ex` | Tool definition with comprehensive documentation |
| `test/jido_code/tools/definitions/file_multi_edit_test.exs` | 24 tests covering definition, LLM format, and validation |

### Files Modified

| File | Changes |
|------|---------|
| `lib/jido_code/tools/definitions/file_system.ex` | Added alias, defdelegate, and included in `all/0` |
| `test/jido_code/tools/definitions/file_system_test.exs` | Updated to expect 8 tools instead of 7 |
| `notes/planning/tooling/phase-01-tools.md` | Marked 1.4.1 as complete |

---

## Tool Schema

```elixir
%{
  name: "multi_edit_file",
  description: "Apply multiple edits to a file atomically (all succeed or all fail)...",
  handler: JidoCode.Tools.Handlers.FileSystem.MultiEdit,
  parameters: [
    %{name: "path", type: :string, required: true},
    %{name: "edits", type: :array, required: true, items: :object}
  ]
}
```

### Parameters

- **path** (required, string) - Path to the file to edit (relative to project root)
- **edits** (required, array of objects) - Each object must have:
  - `old_string` - Text to find and replace
  - `new_string` - Replacement text (can be empty to delete)

---

## Key Features

1. **Atomic Semantics**: All edits validated before any modifications - fail-fast behavior
2. **Sequential Application**: Edits applied in order; earlier edits may affect later positions
3. **Read-Before-Write**: File must be read first (enforced by handler)
4. **Project Boundary**: Security validation via handler
5. **LLM Compatible**: Full OpenAI function-calling format support

---

## Test Coverage

```
24 tests, 0 failures
```

Tests cover:
- Tool struct validation
- Parameter schema (path, edits, items type)
- LLM format conversion
- Argument validation (valid args, missing required, invalid types)
- FileSystem delegation

---

## Design Decisions

### Tool Naming
Used `multi_edit_file` (verb_noun pattern) for consistency with `edit_file`, `read_file`, `write_file`.

### Items Schema Limitation
The Param struct only supports simple type atoms for array items (`:string`, `:object`, etc.), not nested schemas. The expected object structure is documented in the description instead.

---

## Next Task

**1.4.2: Multi-Edit Handler Implementation** - Implement the `MultiEdit` handler module within `file_system.ex` with:
- Read-before-write validation
- Multi-strategy matching (reuse from EditFile)
- Sequential edit application
- Atomic write via `Security.atomic_write/4`
- Telemetry emission

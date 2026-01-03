# Section 1.4 Multi-Edit Tool - Pre-Implementation Review

**Date**: 2025-12-28
**Status**: Planning Review (Code Not Yet Implemented)
**Reviewers**: factual-reviewer, qa-reviewer, senior-engineer-reviewer, security-reviewer, elixir-reviewer, consistency-reviewer, redundancy-reviewer

---

## Executive Summary

The plan for Section 1.4 Multi-Edit Tool has **2 critical blockers** that must be fixed before implementation, **8 concerns** that should be addressed, and **12 suggestions** for improvement. The plan's core concept (atomic batch edits) is sound, but the file structure and several implementation details need correction to match existing codebase patterns.

---

## 🚨 Blockers (Must Fix Before Implementation)

### B1: Handler File Location is Incorrect

**Current Plan**: Create `lib/jido_code/tools/handlers/file_system/multi_edit.ex`

**Problem**: All file system handlers are **inner modules** within `file_system.ex`, not separate files. There is no `handlers/file_system/` subdirectory.

**Existing Pattern**:
```
lib/jido_code/tools/handlers/file_system.ex
  └── defmodule EditFile do ... end
  └── defmodule ReadFile do ... end
  └── defmodule WriteFile do ... end
  └── defmodule ListDirectory do ... end
  └── defmodule FileInfo do ... end
  └── defmodule CreateDirectory do ... end
  └── defmodule DeleteFile do ... end
```

**Fix**: Add `MultiEdit` as an inner module within `lib/jido_code/tools/handlers/file_system.ex`:
```elixir
defmodule MultiEdit do
  @moduledoc "Handler for multi_edit tool..."
  def execute(args, context) do
    # ...
  end
end
```

**Affected Tasks**: 1.4.2.1

---

### B2: Missing Read-Before-Write Requirement

**Current Plan**: Does not mention read-before-write enforcement for batch edits.

**Problem**: Existing `EditFile` and `WriteFile` handlers require files to be read before modification (enforced via `check_read_before_edit/2` and session state tracking). Multi-edit MUST enforce this for ALL files in the batch.

**Security Risk**: Without this check, an attacker could submit a batch where some files were read but others were not, bypassing the read-before-write safeguard.

**Fix**: Add task 1.4.2.X: "Implement read-before-write check for ALL files in batch using `check_read_before_edit/2` pattern"

**Affected Tasks**: 1.4.2.2

---

## ⚠️ Concerns (Should Address)

### C1: "Rollback" Semantics are Misleading

**Current Plan**: "Rollback on any failure (atomic - all or nothing)"

**Problem**: There is no file-level transaction system. The implementation should be:
1. Read file content once
2. Validate all edits can be applied (in memory)
3. Apply all edits in memory
4. Single atomic write via `Security.atomic_write/4`

If validation fails, no file is modified. There is no "rollback" - you simply don't write.

**Fix**: Reword to: "Pre-validate all edits before modifying content (fail-fast, no rollback needed since content only written if all edits valid)"

---

### C2: Schema Format Differs from Existing Pattern

**Current Plan**:
```elixir
%{
  path: %{type: :string, required: true},
  edits: %{type: :array, required: true, items: %{...}}
}
```

**Existing Pattern** (from `file_edit.ex`):
```elixir
parameters: [
  %{name: "path", type: :string, required: true, description: "..."},
  %{name: "edits", type: :array, required: true, description: "...", items: %{...}}
]
```

**Fix**: Use the existing parameter list format in task 1.4.1.2.

---

### C3: Error Tuple Format Inconsistency

**Current Plan**: `{:error, {index, reason}}`

**Existing Patterns**:
- `{:error, "message"}` - String messages
- `{:error, :atom}` - Simple atoms
- `{:error, :ambiguous_match, count}` - 3-element tuple with data

**Fix**: Either embed index in message (`{:error, "Edit 2 failed: String not found..."}`) or use 3-element tuple (`{:error, :edit_failed, {index, reason}}`).

---

### C4: Multi-Strategy Matching Not Specified

**Problem**: Existing `EditFile` uses 4 matching strategies (exact, line-trimmed, whitespace-normalized, indentation-flexible). The plan does not specify whether `MultiEdit` will:
- Reuse the same strategies
- Apply strategies per-edit or globally
- Report which strategy matched each edit

**Fix**: Add clarification to 1.4.2.2: "Use `do_replace_with_strategies/4` from EditFile for each edit"

---

### C5: Overlapping Edits Handling Undefined

**Problem**: Task 1.4.3 tests "overlapping edits" but implementation tasks don't specify handling. Options:
1. Reject overlapping edits upfront with error
2. Apply in reverse position order (end-to-start) to preserve positions
3. Merge adjacent edits

**Recommendation**: Apply edits in reverse position order (existing `EditFile` pattern at lines 387-395).

---

### C6: Private Functions Prevent Reuse

**Problem**: Core replacement logic in `EditFile` is private (`defp`):
- `do_replace_with_strategies/4`
- `try_replace/5`
- `apply_replacements/5`
- `check_read_before_edit/2`

**Fix**: Either duplicate logic (bad) or refactor these to public (`def` with `@doc false`) before implementing MultiEdit.

---

### C7: Duplicate track_file_write Implementation

**Problem**: Both `EditFile.track_file_write/2` and `WriteFile.track_file_write/2` contain identical code. Adding a third copy in `MultiEdit` would worsen the duplication.

**Fix**: Extract to `FileSystem.track_file_write/2` (public) as a prerequisite for 1.4.2.

---

### C8: Missing Telemetry

**Problem**: Existing handlers emit telemetry via `FileSystem.emit_file_telemetry/6`. Plan does not mention telemetry for multi_edit.

**Fix**: Add task 1.4.2.X: "Emit telemetry via `FileSystem.emit_file_telemetry/6` for `:multi_edit` operation"

---

## 💡 Suggestions (Improvements)

### S1: Add Registration to FileSystem.all()

The new tool should be added to `lib/jido_code/tools/definitions/file_system.ex` via `defdelegate` and included in the `all/0` function.

### S2: Consider Tool Naming

Current: `multi_edit` vs existing: `edit_file`, `read_file`, `write_file`
Consider: `multi_edit_file` for consistency with verb_noun pattern.

### S3: Add Content Size Limits

Batch of 100 edits on 100 files could consume 1GB+ memory for backup storage. Consider:
- Per-file size limit (existing: 10MB)
- Max files per batch (e.g., 50)
- Max edits per batch (e.g., 500)

### S4: Enhanced Test Coverage

Add tests for:
- Read-before-write enforcement for batch
- Path traversal in any edit
- Session state updates after success
- Telemetry emission
- Empty edits array
- Missing required fields in individual edits

### S5: Security - Path Validation Timing

Each file edit should use `Security.validate_path/3` immediately before the edit operation, not just at batch start (TOCTOU consideration).

### S6: Document Order Sensitivity

Edits are applied sequentially, so earlier edits may affect positions of later matches. Document this clearly.

### S7: Pre-Implementation Refactoring

Before implementing 1.4.2, extract shared functions:

| Current | New | Purpose |
|---------|-----|---------|
| `EditFile.do_replace_with_strategies/4` | `FileSystem.replace_with_strategies/4` | Multi-strategy replacement |
| `EditFile.check_read_before_edit/2` | `FileSystem.check_read_before_edit/2` | Read-before-write validation |
| `EditFile.track_file_write/2` | `FileSystem.track_file_write/2` | Session write tracking |

### S8: Clarify Single-File Scope

The plan implies multi_edit operates on a single file with multiple edits (not multiple files). This should be explicit.

### S9: Add Session Context Tests

- Test with `session_id` context (enforces read-before-write)
- Test with `project_root` context (legacy mode, bypasses check)

### S10: Add Concurrent Access Documentation

The codebase does not implement file locking. Document that concurrent edits to the same file may cause race conditions.

### S11: Add Input Validation Tests

- Empty edits array
- Null/invalid edit entries
- Missing `old_string` or `new_string` in individual edits

### S12: Consider Extract StringMatching Module

The matching strategies are general-purpose and could be extracted to:
```elixir
defmodule JidoCode.Tools.Utils.StringMatching do
  def find_with_strategies(content, pattern, strategies \\ default_strategies())
end
```

---

## ✅ Good Practices in Current Plan

1. **Atomic all-or-nothing semantics** - Correct approach for batch operations
2. **Pre-validation before application** - "Validate all edits can be applied" is essential
3. **Sequential edit application** - Necessary for correctness
4. **Error with index** - Returning which edit failed aids debugging
5. **Single-file scope** - Simplifies transaction semantics

---

## Recommended Updated Plan

```markdown
### 1.4.1 Tool Definition

- [ ] 1.4.1.1 Create `lib/jido_code/tools/definitions/file_multi_edit.ex` with module documentation
- [ ] 1.4.1.2 Define schema using existing parameter list format:
  ```elixir
  parameters: [
    %{name: "path", type: :string, required: true, description: "..."},
    %{name: "edits", type: :array, required: true, description: "...", items: %{
      old_string: %{type: :string, required: true},
      new_string: %{type: :string, required: true}
    }}
  ]
  ```
- [ ] 1.4.1.3 Add `multi_edit_file()` to `FileSystem.all/0` via defdelegate

### 1.4.2 Multi-Edit Handler Implementation

- [ ] 1.4.2.0 (Prerequisite) Extract shared functions from EditFile to FileSystem module
- [ ] 1.4.2.1 Add `MultiEdit` inner module to `lib/jido_code/tools/handlers/file_system.ex`
- [ ] 1.4.2.2 Implement read-before-write check for the file
- [ ] 1.4.2.3 Validate all edits can be applied (all old_strings found and unique)
- [ ] 1.4.2.4 Apply edits sequentially in memory using multi-strategy matching
- [ ] 1.4.2.5 Write result via single `Security.atomic_write/4` call
- [ ] 1.4.2.6 Track file write in session state
- [ ] 1.4.2.7 Emit telemetry for `:multi_edit` operation
- [ ] 1.4.2.8 Return `{:ok, message}` or `{:error, message}` with embedded index

### 1.4.3 Unit Tests for Multi-Edit

Core Behavior:
- [ ] Test multi_edit applies all edits atomically
- [ ] Test multi_edit validates all edits before applying any
- [ ] Test multi_edit preserves edit order

Error Cases:
- [ ] Test multi_edit fails when any edit string not found
- [ ] Test multi_edit fails on ambiguous match error
- [ ] Test multi_edit fails when target file does not exist

Overlapping/Adjacent:
- [ ] Test multi_edit with non-overlapping edits to same file
- [ ] Test multi_edit behavior with adjacent/overlapping edits

Security:
- [ ] Test multi_edit rejects path traversal attempts
- [ ] Test multi_edit validates path within boundary

Session Context:
- [ ] Test multi_edit requires file to be read first (session context)
- [ ] Test multi_edit with project_root context (legacy mode)
- [ ] Test multi_edit updates session state after success

Input Validation:
- [ ] Test multi_edit with empty edits array
- [ ] Test multi_edit with missing required fields

Telemetry:
- [ ] Test multi_edit emits telemetry on success and failure
```

---

## Summary

| Category | Count |
|----------|-------|
| 🚨 Blockers | 2 |
| ⚠️ Concerns | 8 |
| 💡 Suggestions | 12 |
| ✅ Good Practices | 5 |

**Recommendation**: Fix blockers B1 and B2, address concerns C1-C8, then proceed with implementation using the updated plan above.

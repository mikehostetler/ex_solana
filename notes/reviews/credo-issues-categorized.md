# Credo Issues - Categorized Review

**Date:** 2025-12-07
**Branch:** `feature/credo-fixes`
**Total Issues:** 75 (26 refactoring, 30 readability, 19 design)

---

## Priority Categories

Issues are categorized by fixability and impact:
- **P1 (HIGH)**: Quick fixes with clear solutions - fix immediately
- **P2 (MEDIUM)**: Moderate refactoring needed - fix in batches
- **P3 (LOW)**: Minor style issues or require significant refactoring - defer or skip

---

## P1: HIGH Priority (Quick Fixes)

### Readability - Predicate Function Names (3 issues)
Functions starting with `is_` should end with `?` or be renamed.

| File | Line | Function | Fix |
|------|------|----------|-----|
| `lib/jido_code/commands.ex` | 683 | `is_numeric_target?` | Rename to `numeric_target?` |
| `lib/jido_code/tools/manager.ex` | 423 | `is_file?` | Rename to `file?` |
| `lib/jido_code/tools/manager.ex` | 442 | `is_dir?` | Rename to `directory?` |

### Readability - Large Numbers (5 issues)
Numbers > 9999 should use underscores for readability.

| File | Line | Value | Fix |
|------|------|-------|-----|
| `test/jido_code/session/agent_api_test.exs` | 78 | `12345` | `12_345` |
| `test/jido_code/session/agent_api_test.exs` | 90 | `12345` | `12_345` |
| `test/jido_code/session/agent_api_test.exs` | 184 | `12345` | `12_345` |
| `test/jido_code/session/agent_api_test.exs` | 259 | `12345` | `12_345` |
| `test/jido_code/session/agent_api_test.exs` | 433 | `12345` | `12_345` |

### Refactoring - MapJoin (5 issues)
`Enum.map |> Enum.join` should be `Enum.map_join`.

| File | Line | Scope |
|------|------|-------|
| `lib/jido_code/tools/handlers/web.ex` | 260 | `convert_to_markdown` |
| `lib/jido_code/tools/handlers/web.ex` | 291 | `convert_to_markdown` |
| `lib/jido_code/tools/manager.ex` | 660 | `call_bridge_function` |
| `lib/jido_code/tools/manager.ex` | 712 | `lua_encode_arg` |
| `test/jido_code/tui/widgets/conversation_view_test.exs` | 1088, 1108 | test helpers |

### Refactoring - NegatedConditionsWithElse (1 issue)
Avoid `if not ... else`.

| File | Line | Scope |
|------|------|-------|
| `lib/jido_code/tools/executor.ex` | 238 | `build_context` |

### Refactoring - UnlessWithElse (2 issues)
`unless ... else` should be `if`.

| File | Line |
|------|------|
| `test/jido_code/integration/session_phase3_test.exs` | 324 |
| `test/jido_code/integration/session_phase3_test.exs` | 352 |

### Refactoring - FilterFilter (1 issue)
Double filter should be combined.

| File | Line | Scope |
|------|------|-------|
| `lib/jido_code/tools/handlers/web.ex` | 404 | `parse_duckduckgo_response` |

---

## P2: MEDIUM Priority (Moderate Refactoring)

### Readability - WithSingleClause (6 issues)
Single-clause `with` with `else` should be `case`.

| File | Line | Scope |
|------|------|-------|
| `lib/jido_code/tools/handlers/file_system.ex` | 202 | `ReadFile.execute` |
| `lib/jido_code/tools/handlers/file_system.ex` | 378 | `ListDirectory.execute` |
| `lib/jido_code/tools/handlers/file_system.ex` | 483 | `FileInfo.execute` |
| `lib/jido_code/tools/handlers/file_system.ex` | 555 | `CreateDirectory.execute` |
| `lib/jido_code/tools/handlers/file_system.ex` | 603 | `DeleteFile.execute` |

### Readability - PreferImplicitTry (1 issue)

| File | Line | Scope |
|------|------|-------|
| `lib/jido_code/tools/handlers/task.ex` | 181 | `run_with_cleanup` |

### Readability - AliasOrder (14 issues)
Aliases should be alphabetically ordered.

| File | Line | Trigger |
|------|------|---------|
| `lib/jido_code/application.ex` | 38 | `JidoCode.Settings` |
| `lib/jido_code/livebook/parser.ex` | 22 | `Notebook` |
| `lib/jido_code/livebook/serializer.ex` | 15 | `Notebook` |
| `lib/jido_code/tools.ex` | 50 | `JidoCode.Tools` |
| `lib/jido_code/tools/handlers/file_system.ex` | 229 | `FileSystem` (2x) |
| `lib/jido_code/tools/handlers/livebook.ex` | 27, 67 | `HandlerHelpers`, `Livebook` (3x) |
| `lib/jido_code/tools/handlers/task.ex` | 31 | `AgentSupervisor` |
| `test/jido_code/integration/session_phase3_test.exs` | 34 | `Executor` |
| `test/jido_code/livebook/parser_test.exs` | 4 | `Parser` |
| `test/jido_code/livebook/serializer_test.exs` | 4 | `Serializer` |
| `test/jido_code/tools/handlers/livebook_test.exs` | 5 | `EditCell` |
| `test/jido_code/tui/widgets/conversation_view_test.exs` | 6 | `ConversationView` |

---

## P3: LOW Priority (Significant Refactoring or Design)

### Design - AliasUsage (19 issues)
Nested modules should be aliased. Many are in test files.

**Lib files (4):**
- `lib/jido_code/application.ex:137` - `AgentInstrumentation`
- `lib/jido_code/tui.ex:271` - `Session.State` (2x duplicate)

**Test files (15):**
- Various test files using full module paths instead of aliases

### Refactoring - Nesting (13 issues)
Function bodies nested too deep (depth 3, max 2).

| File | Line | Function |
|------|------|----------|
| `lib/jido_code/agents/llm_agent.ex` | 898 | `process_stream` |
| `lib/jido_code/commands.ex` | 510 | `execute_session` |
| `lib/jido_code/commands.ex` | 908 | `validate_provider` |
| `lib/jido_code/session_registry.ex` | 462 | `get_oldest_session_id` |
| `lib/jido_code/tools/bridge.ex` | 486 | `lua_shell` |
| `lib/jido_code/tools/handlers/file_system.ex` | 326 | `validate_symlink_target` |
| `lib/jido_code/tools/security.ex` | 197 | `atomic_read` |
| `lib/jido_code/tools/security.ex` | 239 | `atomic_write` |
| `lib/jido_code/tools/security.ex` | 288 | `validate_realpath` |
| `lib/jido_code/tui.ex` | 1374 | `ensure_session_subscription` |
| `lib/jido_code/tui/widgets/conversation_view.ex` | 332 | `render` |

### Refactoring - CyclomaticComplexity (5 issues)
Functions too complex (>9 branches).

| File | Line | Function | Complexity |
|------|------|----------|------------|
| `lib/jido_code/tools/handlers/web.ex` | 259 | `convert_to_markdown` | 24 |
| `lib/jido_code/tui/view_helpers.ex` | 298 | `build_status_bar_style` | 15 |
| `lib/jido_code/tools/handlers/web.ex` | 117 | `fetch_url` | 13 |
| `lib/jido_code/tui.ex` | 1044 | `do_handle_command` | 12 |
| `lib/jido_code/tui/widgets/conversation_view.ex` | 299 | `render` | 11 |

### Design - TagTODO (2 issues)
TODO comments found.

| File | Line | Comment |
|------|------|---------|
| `test/jido_code/tools/handlers/shell_test.exs` | 238 | Timeout support TODO |
| `test/jido_code/tools_test.exs` | 42 | Todo tools comment |

---

## Implementation Plan

### Phase 1: P1 Issues (17 quick fixes)
1. [x] Rename predicate functions (3 fixes)
2. [x] Format large numbers (5 fixes)
3. [x] Convert to map_join (5 fixes)
4. [x] Fix negated conditions (1 fix)
5. [x] Fix unless/else (2 fixes)
6. [x] Combine filters (1 fix)
**Commit after Phase 1**

### Phase 2: P2 Issues (21 moderate fixes)
1. [ ] Convert with to case (6 fixes)
2. [ ] Fix implicit try (1 fix)
3. [ ] Fix alias order (14 fixes)
**Commit after Phase 2**

### Phase 3: P3 Issues (defer)
- Nesting and complexity issues require significant refactoring
- AliasUsage in tests is low value
- TODO tags are documentation, not code issues
**Skip or defer to future cleanup sprint**

---

## Success Criteria

1. All P1 issues resolved
2. All P2 issues resolved
3. All tests pass
4. No new credo issues introduced

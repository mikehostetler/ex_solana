# Credo Fixes Feature

**Branch:** `feature/credo-fixes`
**Date:** 2025-12-07
**Status:** Complete

## Overview

Systematically fix all credo issues in the codebase, categorized by priority.

## Implementation Plan

### Phase 1: P1 Issues (HIGH Priority - Quick Fixes) - COMPLETE

#### 1.1 Predicate Function Names
- [x] Rename `is_numeric_target?` → `numeric_target?` in commands.ex
- [x] Rename `is_file?` → `file?` in manager.ex
- [x] Rename `is_dir?` → `directory?` in manager.ex
- [x] Update all call sites

#### 1.2 Large Numbers
- [x] Fix `12345` → `12_345` in agent_api_test.exs (5 occurrences)

#### 1.3 MapJoin Optimization
- [x] Fix web.ex:260 - convert_to_markdown
- [x] Fix web.ex:291 - convert_to_markdown
- [x] Fix manager.ex:660 - call_bridge_function
- [x] Fix manager.ex:712 - lua_encode_arg
- [x] Fix conversation_view_test.exs:1088, 1108

#### 1.4 Negated Conditions
- [x] Fix executor.ex:238 - build_context

#### 1.5 Unless With Else
- [x] Fix session_phase3_test.exs:324
- [x] Fix session_phase3_test.exs:352

#### 1.6 Filter Filter
- [x] Fix web.ex:404 - parse_duckduckgo_response

### Phase 2: P2 Issues (MEDIUM Priority) - COMPLETE

#### 2.1 With Single Clause
- [x] Fix file_system.ex:202 - ReadFile.execute
- [x] Fix file_system.ex:378 - ListDirectory.execute
- [x] Fix file_system.ex:483 - FileInfo.execute
- [x] Fix file_system.ex:555 - CreateDirectory.execute
- [x] Fix file_system.ex:603 - DeleteFile.execute

#### 2.2 Prefer Implicit Try
- [x] Skipped - task.ex:181 has `after` clause which requires explicit try

#### 2.3 Alias Order (11 fixes)
- [x] Fix lib/jido_code/application.ex
- [x] Fix lib/jido_code/livebook/parser.ex
- [x] Fix lib/jido_code/livebook/serializer.ex
- [x] Fix lib/jido_code/tools.ex
- [x] Fix lib/jido_code/tools/handlers/file_system.ex
- [x] Fix lib/jido_code/tools/handlers/livebook.ex
- [x] Fix lib/jido_code/tools/handlers/task.ex
- [x] Fix test files (4)

### Phase 3: P3 Issues (LOW Priority - Defer)
- Nesting issues (13) - require significant refactoring
- Cyclomatic complexity (5) - need function decomposition
- AliasUsage in tests (15) - low value
- TODO tags (2) - documentation, not bugs

## Files to Modify

### Phase 1
- `lib/jido_code/commands.ex`
- `lib/jido_code/tools/manager.ex`
- `lib/jido_code/tools/executor.ex`
- `lib/jido_code/tools/handlers/web.ex`
- `test/jido_code/session/agent_api_test.exs`
- `test/jido_code/integration/session_phase3_test.exs`
- `test/jido_code/tui/widgets/conversation_view_test.exs`

### Phase 2
- `lib/jido_code/tools/handlers/file_system.ex`
- `lib/jido_code/tools/handlers/task.ex`
- Multiple files for alias ordering

## Success Criteria

1. `mix credo --strict` shows 0 P1 issues
2. `mix credo --strict` shows 0 P2 issues
3. All tests pass
4. P3 issues documented for future work

# Feature: Refactoring Improvements

## Problem Statement

The Phase 6 review identified several refactoring opportunities to improve code maintainability:
- Duplicate helper functions across handler modules (~75 lines)
- Common validation patterns repeated in handlers (~100 lines)
- TUI update/2 function is 208 lines handling all message types
- Formatting utilities scattered across modules (~80 lines)

## Solution Overview

Extract shared code into dedicated modules to reduce duplication and improve maintainability.

## Implementation Plan

### Step 1: Extract JidoCode.Tools.HandlerHelpers Module
- [ ] Create `lib/jido_code/tools/handler_helpers.ex`
- [ ] Extract `get_project_root/1` (duplicated in FileSystem, Search, Shell)
- [ ] Extract common error formatting patterns
- [ ] Update handlers to use the new module
- [ ] Estimated savings: ~50 lines

### Step 2: Extract JidoCode.Tools.ErrorFormatter Module
- [ ] Create `lib/jido_code/tools/error_formatter.ex`
- [ ] Consolidate `format_error/2` from FileSystem, Search, Shell
- [ ] Create unified error formatting with domain-specific extensions
- [ ] Update handlers to use the new module
- [ ] Estimated savings: ~30 lines

### Step 3: Split TUI Message Handlers
- [ ] Create `lib/jido_code/tui/message_handlers.ex`
- [ ] Move PubSub message handlers from tui.ex
- [ ] Create handler functions for each message type
- [ ] Keep TUI.update/2 as dispatcher to handler module
- [ ] Estimated savings: ~150 lines from tui.ex

### Step 4: Extract TUI View Helpers
- [ ] Create `lib/jido_code/tui/view_helpers.ex`
- [ ] Move view rendering helpers from tui.ex
- [ ] Keep main view/1 function in tui.ex as coordinator
- [ ] Estimated savings: ~200 lines from tui.ex

### Deferred (Out of Scope)
- Consolidate formatting utilities (would touch too many files)
- LLMAgent streaming extraction (works well as-is)

## Success Criteria

- [x] All tests pass (1024 tests, 0 failures)
- [x] No duplicate `get_project_root/1` functions
- [x] TUI.update/2 delegates to MessageHandlers
- [x] Clear module boundaries with single responsibility

## Current Status

**Status**: Complete
**Started**: 2025-11-30
**Branch**: `feature/refactoring-improvements`

### Progress Log

#### Step 1: HandlerHelpers Module
- [x] Create module
- [x] Extract get_project_root/1
- [x] Update FileSystem handlers
- [x] Update Search handlers
- [x] Update Shell handlers
- [x] Run tests

#### Step 2: ErrorFormatter Module
- [x] Analyzed format_error/2 patterns across handlers
- [x] Moved common security errors to HandlerHelpers.format_common_error/2
- [x] Kept domain-specific error formatting in respective handlers (FileSystem, Search, Shell)
- Note: Full extraction deferred - domain-specific errors are tightly coupled to their handlers

#### Step 3: TUI Message Handlers
- [x] Create MessageHandlers module
- [x] Move handler functions (agent response, streaming, status, config, reasoning, tools)
- [x] Update TUI.update/2 to delegate to MessageHandlers
- [x] Run tests (1024 tests, 0 failures)

#### Step 4: TUI View Helpers
- [x] Create ViewHelpers module
- [x] Move view functions (status bar, conversation, tool calls, reasoning, input bar, config)
- [x] Update TUI.view/1 to use ViewHelpers
- [x] Run tests (1024 tests, 0 failures)

## Notes

- Focus on extracting duplicated code, not rewriting functionality
- Keep public APIs unchanged to avoid breaking changes
- Each step should leave tests passing before moving to next

# Feature: Phase 6 Review Fixes

## Problem Statement

The Phase 6 completion review identified 3 critical security issues, 3 critical architecture issues, documentation inaccuracies, and code quality concerns that must be addressed before production use.

## Solution Overview

Fix all blockers (P0/P1), correct documentation inaccuracies (P2), and implement code quality improvements (P3).

## Implementation Plan

### P0 - Security Fixes (Critical)

#### SEC-1: Lua Bridge Shell Bypass
- [ ] **Location**: `lib/jido_code/tools/bridge.ex:240-273`
- [ ] **Issue**: `lua_shell/3` executes commands without validation
- [ ] **Fix**: Add command validation using `Shell.validate_command/1` before execution
- [ ] **Fix**: Block shell interpreters (bash, sh, zsh, etc.)
- [ ] **Test**: Add tests for blocked commands via Lua bridge

#### SEC-2: TOCTOU Race Condition
- [ ] **Location**: `lib/jido_code/tools/security.ex:189-254`
- [ ] **Issue**: Symlink validation occurs before file operation
- [ ] **Fix**: Perform validation atomically with operation where possible
- [ ] **Fix**: Re-validate immediately before each file operation in bridge.ex
- [ ] **Test**: Add race condition test (symlink swap between check and use)

#### SEC-3: Path Argument Validation Gap
- [ ] **Location**: `lib/jido_code/tools/bridge.ex:322-349`
- [ ] **Issue**: `parse_shell_args/1` doesn't validate path arguments
- [ ] **Fix**: Add path validation similar to `RunCommand.validate_and_parse_args/2`
- [ ] **Fix**: Block `..` patterns and absolute paths outside project
- [ ] **Test**: Add tests for path traversal in shell args via Lua

### P1 - Architecture Fixes (High Priority)

#### ARCH-1: Unmonitored Tasks
- [ ] **Location**: `lib/jido_code/agents/llm_agent.ex:371-384, 423-437`
- [ ] **Issue**: Uses `Task.start/1` without supervision - crashes are silently dropped
- [ ] **Fix**: Add `Task.Supervisor` to supervision tree
- [ ] **Fix**: Replace `Task.start/1` with `Task.Supervisor.async_nolink/2`
- [ ] **Fix**: Add error handling for task failures
- [ ] **Test**: Verify task crash doesn't hang caller

#### ARCH-2: PubSub Topic Mismatch
- [ ] **Location**: `lib/jido_code/tools/executor.ex` vs `lib/jido_code/tui/pubsub_bridge.ex`
- [ ] **Issue**: Executor uses `tui.events.{session_id}` but PubSubBridge only subscribes to `tui.events`
- [ ] **Fix Option A**: Have PubSubBridge accept session_id and subscribe to session-specific topic
- [ ] **Fix Option B**: Have Executor always broadcast to global topic in addition to session topic
- [ ] **Chosen**: Option B - broadcast to both topics for flexibility
- [ ] **Test**: Verify tool results reach TUI via PubSub

#### ARCH-3: ETS Race Conditions
- [ ] **Location**: `lib/jido_code/telemetry/agent_instrumentation.ex`
- [ ] **Issue**: `setup/0` creates ETS table on-demand from multiple places
- [ ] **Fix**: Create ETS table during application startup in `application.ex`
- [ ] **Fix**: Remove on-demand `setup()` calls or make them no-op if table exists
- [ ] **Test**: Verify concurrent calls don't crash

### P2 - Documentation Fixes

#### DOC-1: Default Provider Claim
- [ ] **Location**: `README.md:40, 66`
- [ ] **Issue**: Claims "defaults to Anthropic" but provider must be explicitly configured
- [ ] **Fix**: Update to say "required - must be explicitly configured"

#### DOC-2: Phase 4.3.1 Checkbox
- [ ] **Location**: `notes/planning/proof-of-concept/phase-04.md:114`
- [ ] **Issue**: PickList widget is implemented but checkbox shows `[ ]`
- [ ] **Fix**: Mark as `[x]` complete

### P3 - Code Quality Improvements

#### CQ-1: Rate Limiting
- [ ] **Location**: `lib/jido_code/tools/executor.ex`
- [ ] **Issue**: No rate limiting - LLM could execute thousands of operations
- [ ] **Fix**: Add configurable rate limiter (e.g., 100 ops/minute default)

#### CQ-2: PubSub Message Format Consistency
- [ ] **Location**: `lib/jido_code/agents/llm_agent.ex:551`, `lib/jido_code/commands.ex:388`
- [ ] **Issue**: Inconsistent tuple arities for `:config_changed`
  - `llm_agent.ex`: `{:config_changed, old_config, new_config}` (3-tuple)
  - `commands.ex`: `{:config_changed, config}` (2-tuple)
- [ ] **Fix**: Standardize to 2-tuple `{:config_changed, config}`

#### CQ-3: Status Message Type Consistency
- [ ] **Location**: `lib/jido_code/tui.ex:75-76`
- [ ] **Issue**: Both `:status_update` and `:agent_status` for same concept
- [ ] **Fix**: Use `:agent_status` consistently, remove `:status_update`

#### CQ-4: Add excoveralls
- [ ] **Location**: `mix.exs`
- [ ] **Fix**: Add `{:excoveralls, "~> 0.18", only: :test}`
- [ ] **Fix**: Configure coveralls in project config

### Refactoring (Nice to Have - Defer)

The following refactoring suggestions are deferred to future work:
- Extract `JidoCode.Tools.HandlerHelpers` module (~75 lines)
- Create `JidoCode.Tools.Validators` module (~100 lines)
- Consolidate `JidoCode.Formatting` module (~80 lines)
- Split TUI message handlers (~400 lines)
- Extract LLMAgent streaming module (~200 lines)

## Implementation Order

1. **SEC-1**: Lua bridge shell bypass (critical, self-contained)
2. **SEC-3**: Path argument validation (builds on SEC-1)
3. **SEC-2**: TOCTOU race condition (complex, requires careful testing)
4. **ARCH-3**: ETS race conditions (simple, low risk)
5. **ARCH-1**: Unmonitored tasks (moderate complexity)
6. **ARCH-2**: PubSub topic mismatch (requires coordination)
7. **DOC-1, DOC-2**: Documentation fixes (quick)
8. **CQ-1 through CQ-4**: Code quality (incremental)

## Success Criteria

- [ ] All security tests pass including new injection tests
- [ ] All architecture tests pass including concurrency tests
- [ ] Documentation accurately reflects current behavior
- [ ] Code coverage remains at 80%+
- [ ] No regressions in existing 998 tests

## Current Status

**Status**: Complete
**Started**: 2025-11-30
**Branch**: `feature/phase-06-review-fixes`

### Progress Log

#### Step 1: SEC-1 - Lua Bridge Shell Bypass
- [x] Add validation to `lua_shell/3` using `Shell.validate_command/1`
- [x] Add tests for blocked shell interpreters (bash, sh, zsh, fish)

#### Step 2: SEC-3 - Path Argument Validation
- [x] Add path validation to shell args via `validate_shell_args/2`
- [x] Add tests for path traversal and absolute path blocking

#### Step 3: SEC-2 - TOCTOU Mitigation
- [x] Implement `atomic_read/3` and `atomic_write/4` in Security module
- [x] Add `validate_realpath/3` for post-operation validation
- [x] Update bridge.ex to use atomic operations
- [x] Add tests for atomic operations

#### Step 4: ARCH-3 - ETS Race Conditions
- [x] Move table creation to application.ex via `initialize_ets_tables/0`
- [x] Update `setup/0` to be thread-safe with try/catch
- [x] Table now created during app startup

#### Step 5: ARCH-1 - Task Supervision
- [x] Add `Task.Supervisor` to supervision tree as `JidoCode.TaskSupervisor`
- [x] Update `handle_call({:chat, ...})` to use `Task.Supervisor.start_child/2`
- [x] Update `handle_cast({:chat_stream, ...})` to use supervised tasks

#### Step 6: ARCH-2 - PubSub Topic Routing
- [x] Update `broadcast_to_topics/2` to broadcast to both session and global topics
- [x] PubSubBridge now receives messages regardless of session_id

#### Step 7: Documentation Fixes
- [x] Update README.md line 40: "required" instead of "defaults to Anthropic"
- [x] Update README.md line 66-67: Remove default values for provider/model
- [x] Update phase-04.md: Mark PickList widget tasks as complete

#### Step 8: Code Quality
- [x] Standardize config_changed to 2-tuple format in llm_agent.ex
- [x] Add excoveralls dependency to mix.exs
- [x] Configure coverage in project settings
- [ ] Rate limiting deferred to future work

## Notes

- Security fixes take priority over architecture fixes
- Each fix should include corresponding tests
- Run full test suite after each major change
- Document any breaking changes

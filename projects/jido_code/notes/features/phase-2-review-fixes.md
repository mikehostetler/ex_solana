# Feature: Phase 2 Review Fixes

**Branch**: `feature/phase-2-review-fixes`
**Source**: Phase 2 Code Review (`notes/reviews/phase-02-review.md`)

## Problem Statement

The Phase 2 code review identified 2 blockers, 5 concerns, and 5 suggestions that need to be addressed before the codebase is production-ready.

## Implementation Plan

### Blockers (Must Fix)

#### 1. Missing ChainOfThought Tests
- [x] Add tests for `run_with_reasoning/3` main flow
- [x] Add tests for reasoning plan extraction
- [x] Add tests for fallback behavior
- [x] Add tests for telemetry events
- [x] Add tests for response parsing

#### 2. Prompt Injection Vulnerability
- [x] Remove user message interpolation from system prompt
- [x] Separate system prompt from user input completely
- [x] Add clear delimiters between system and user content

### Concerns (Should Address)

#### 3. No Input Validation for User Messages
- [x] Add maximum message length constant (10,000 chars)
- [x] Validate message length in `chat/2`
- [x] Return descriptive error for oversized messages

#### 4. Blocking GenServer Calls
- [x] Refactor `handle_call({:chat, ...})` to use async pattern
- [x] Use `Task.async` or `GenServer.reply` with `{:noreply, state}`
- [x] Maintain timeout handling

#### 5. Configuration Validation Gap
- [x] Add `validate_config/1` call in `build_config/1`
- [x] Ensure agents cannot start in invalid state
- [x] Add tests for invalid config at startup

#### 6. Unauthenticated PubSub Topics
- [x] Add session_id to agent state
- [x] Use session-specific topic format: `"tui.events.{session_id}"`
- [x] Update broadcast functions to use session topic

#### 7. ReDoS Vulnerability
- [x] Add `@max_response_length` constant (100,000 chars)
- [x] Truncate response before regex parsing
- [ ] Add timeout wrapper for regex operations (skipped - truncation sufficient)

### Suggestions (Nice to Have)

#### 8. Standardize Error Types
- [x] Create `JidoCode.Error` struct
- [x] Define error codes as atoms
- [ ] Update modules to use standardized errors (deferred - foundation created)

#### 9. Extract Common Utilities
- [x] Create `JidoCode.Utils.String` with truncate/2
- [ ] Create `JidoCode.Telemetry.Utils` with emit helper (deferred)
- [ ] Update existing modules to use utilities (deferred)

#### 10. Refactor Complex Functions
- [ ] Split `handle_call({:configure})` into smaller functions (deferred)
- [x] Unify `parse_zero_shot_response` and `parse_structured_response`

#### 11. Documentation Style Inconsistency
- [x] Standardize @doc format for telemetry accessors
- [x] Use multi-line format consistently

#### 12. ETS Table Ownership
- [x] Make AgentInstrumentation sole owner of ETS table
- [x] Provide accessor functions for AgentSupervisor
- [x] Remove direct ETS access from AgentSupervisor

## Current Status

- [x] Step 1: Blocker 1 - ChainOfThought tests
- [x] Step 2: Blocker 2 - Prompt injection fix
- [x] Step 3: Concern 3 - Message validation
- [x] Step 4: Concern 4 - Async chat
- [x] Step 5: Concern 5 - Config validation
- [x] Step 6: Concern 6 - Session topics
- [x] Step 7: Concern 7 - ReDoS protection
- [x] Step 8: Suggestion 8 - Error standardization
- [x] Step 9: Suggestion 9 - Common utilities
- [x] Step 10: Suggestion 10 - Function refactoring
- [x] Step 11: Suggestion 11 - Documentation
- [x] Step 12: Suggestion 12 - ETS ownership

## Success Criteria

1. All tests pass (254+ tests)
2. ChainOfThought coverage > 80%
3. No prompt injection vectors
4. Message length validated
5. Async chat handling works
6. Config validated at startup
7. Session-specific PubSub topics
8. ReDoS protection in place
9. Standardized error handling
10. Common utilities extracted
11. Consistent documentation style
12. Clear ETS ownership

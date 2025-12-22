# Feature: WS-1.4 Review Fixes

## Problem Statement

Code review of Section 1.4 identified blockers, concerns, and suggested improvements that need to be addressed before the per-session supervisor implementation is production-ready.

## Review Findings to Address

### Blockers (Must Fix)
- **B1**: SessionProcessRegistry not in application.ex
- **B2**: SessionSupervisor not in application.ex

### Concerns (Should Fix)
- **C1**: Missing crash recovery tests for :one_for_all strategy
- **C3**: No input validation guards on lookup functions

### Suggestions (Nice to Have)
- **S1**: Extract shared test setup to helper module
- **S2**: Extract Registry lookup helper function
- **S6**: Remove redundant @doc false on defp functions

## Implementation Plan

### Step 1: Fix Blockers in application.ex
- [x] Add `{Registry, keys: :unique, name: JidoCode.SessionProcessRegistry}` to children
- [x] Add `JidoCode.SessionSupervisor` to children (after Registry)
- [x] Ensure correct ordering: PubSub → Registries → SessionSupervisor

### Step 2: Add Input Validation Guards (C3)
- [x] Add `when is_binary(session_id)` guard to `get_manager/1`
- [x] Add `when is_binary(session_id)` guard to `get_state/1`
- [x] Add `when is_binary(session_id)` guard to `get_agent/1`

### Step 3: Extract Registry Lookup Helper (S2)
- [x] Create private `lookup_process/2` function with typespec
- [x] Refactor `get_manager/1` to use helper
- [x] Refactor `get_state/1` to use helper

### Step 4: Remove Redundant @doc false (S6)
- [x] Remove `@doc false` from `via/1` in supervisor.ex
- [x] Verified manager.ex and state.ex already correct (no @doc false on defp)

### Step 5: Extract Shared Test Setup (S1)
- [x] Added `setup_session_registry/1` to session_test_helpers.ex
- [x] Updated supervisor_test.exs to use shared setup
- [x] Updated manager_test.exs to use shared setup
- [x] Updated state_test.exs to use shared setup

### Step 6: Add Crash Recovery Tests (C1)
- [x] Add test "Manager crash restarts State due to :one_for_all"
- [x] Add test "State crash restarts Manager due to :one_for_all"
- [x] Add test "Registry entries remain consistent after restart"
- [x] Add test "children still have session after restart"

### Step 7: Run Tests and Verify
- [x] Run all session tests: 85 tests, 0 failures
- [x] Verify application compiles correctly
- [x] Update phase plan

## Success Criteria

- [x] Application compiles without errors
- [x] SessionProcessRegistry added to application.ex
- [x] SessionSupervisor added to application.ex
- [x] All lookup functions validate input with guards
- [x] Crash recovery tests pass (4 new tests)
- [x] Test setup is DRY (shared helper used)
- [x] All existing tests still pass

## Current Status

**Status**: Complete

## Changes Made

### Files Modified
- `lib/jido_code/application.ex` - Added SessionProcessRegistry and SessionSupervisor
- `lib/jido_code/session/supervisor.ex` - Added guards, lookup_process helper, removed @doc false
- `test/support/session_test_helpers.ex` - Added setup_session_registry/1
- `test/jido_code/session/supervisor_test.exs` - Used shared setup, added 4 crash recovery tests
- `test/jido_code/session/manager_test.exs` - Used shared setup
- `test/jido_code/session/state_test.exs` - Used shared setup

### Test Results
- Before: 81 tests
- After: 85 tests (+4 crash recovery tests)
- All passing


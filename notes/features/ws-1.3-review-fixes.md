# Feature: WS-1.3 Review Fixes

## Problem Statement

Section 1.3 code review identified several concerns and suggestions that should be addressed to improve code quality, test reliability, and maintainability.

## Items to Address

### Deferred (to Task 1.5.1)
- **B1**: SessionProcessRegistry not in application.ex - This is Task 1.5.1 scope

### Deferred (acceptable for single-user TUI)
- **C1**: Race condition in session registration - ETS prevents duplicates at insert time
- **C4**: Public ETS table access - acceptable for single-user TUI

### Deferred (to Phase 6)
- **C5/S5**: Telemetry/Instrumentation - will be added in Phase 6

### To Fix Now
- **C2/S1**: Add test for start_child failure cleanup path
- **C3/S3**: Replace timer.sleep with process monitoring in tests
- **S2**: Extract duplicated test setup code
- **S4**: Simplify list_session_pids with comprehension
- **S6**: Document registry cleanup timing in stop_session/1

## Implementation Plan

### Step 1: Add test for start_child failure cleanup (C2/S1)
- Create a failing stub that raises in child_spec
- Verify cleanup happens when start_child fails
- Ensure session is unregistered from SessionRegistry

### Step 2: Replace timer.sleep with process monitoring (C3/S3)
- Find all :timer.sleep calls in test file
- Replace with Process.monitor + assert_receive {:DOWN, ...}

### Step 3: Extract duplicated test setup code (S2)
- Create test/support/session_test_helpers.ex
- Extract common setup code into reusable helper
- Update all describe blocks to use shared helper

### Step 4: Simplify list_session_pids with comprehension (S4)
- Replace Enum.map + Enum.filter with for comprehension
- Verify tests still pass

### Step 5: Document registry cleanup timing (S6)
- Add note to stop_session/1 documentation about async cleanup

## Success Criteria

- [x] Test for start_child failure cleanup added and passing
- [x] No timer.sleep calls in tests (use process monitoring)
- [x] Duplicated test setup code extracted to helper
- [x] list_session_pids uses comprehension
- [x] stop_session/1 documentation includes cleanup timing note
- [x] All 42 tests passing (added 1 new test)

## Current Status

**Status**: Complete

**What works**:
- All review fixes implemented
- Test for supervisor start failure cleanup (C2/S1)
- Process monitoring instead of timer.sleep (C3/S3)
- Shared test helper in `test/support/session_test_helpers.ex` (S2)
- list_session_pids uses for comprehension (S4)
- Documentation includes registry cleanup timing note (S6)

**Test Results**:
- 42 tests passing (41 original + 1 new cleanup test)

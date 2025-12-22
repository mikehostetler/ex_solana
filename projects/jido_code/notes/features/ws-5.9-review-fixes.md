# WS-5.9 Phase 5 Review Fixes

**Branch:** `feature/ws-5.9-review-fixes`
**Date:** 2025-12-06
**Status:** Complete

## Overview

Address all blockers, concerns, and suggested improvements from the Phase 5 code review.

## Issues to Address

### High Priority (Blockers)

#### B1. TUI Session Action Handler Tests
- [ ] Add unit tests for `handle_session_command/2` handlers
- [ ] Test `:add_session` action
- [ ] Test `:switch_session` action
- [ ] Test `:close_session` action
- [ ] Test `:rename_session` action

#### S1. Session Path Security Restrictions
- [ ] Add forbidden paths list (system directories)
- [ ] Validate paths are not in sensitive locations
- [ ] Add tests for path security

### Medium Priority (Concerns)

#### B2. PubSub Subscribe/Unsubscribe Tests
- [ ] Test that adding session subscribes to PubSub
- [ ] Test that closing session unsubscribes from PubSub

#### B3. Keyboard Shortcut Tests (Ctrl+1-9,0)
- [ ] Test Ctrl+1 through Ctrl+9 for session switching
- [ ] Test Ctrl+0 maps to session 10

#### S2. Session Name Character Validation
- [ ] Add character whitelist validation
- [ ] Reject control characters (ASCII 0-31)
- [ ] Reject path separators (/, \)
- [ ] Add tests for invalid characters

#### R1. Provider Key Mapping Duplication
- [ ] Extract to shared `JidoCode.Config.ProviderKeys` module
- [ ] Update commands.ex to use shared module
- [ ] Update tui.ex to use shared module

### Low Priority (Suggestions)

#### CN1. Inconsistent Error Return Types
- [ ] Standardize parse_session_args error returns to strings

#### CN2. Function Visibility
- [ ] Make execute_session/2 private (defp)

#### CN3. Redundant @doc false
- [ ] Remove @doc false from private functions

#### R2. Session Error Formatting Helper
- [ ] Extract format_resolution_error/2 helper
- [ ] Use in both switch and close commands

#### E1. Pipe Operator Enhancement
- [ ] Refactor truncate_path/1 to be more pipe-friendly

## Implementation Plan

### Step 1: High Priority - Session Path Security (S1)
- [x] Add `@forbidden_session_paths` module attribute
- [x] Add `forbidden_path?/1` helper function
- [x] Update `validate_session_path/1` to check forbidden paths
- [x] Add tests for forbidden path validation

### Step 2: High Priority - TUI Handler Tests (B1)
- [x] Create test helpers for session action testing
- [x] Add tests for each session action handler
- [x] Verify PubSub subscription behavior (covers B2)

### Step 3: Medium Priority - Session Name Validation (S2)
- [x] Add `valid_session_name_chars?/1` helper
- [x] Update `validate_session_name/1` to check characters
- [x] Add tests for invalid characters

### Step 4: Medium Priority - Keyboard Shortcut Tests (B3)
- [x] Add tests for Ctrl+1 through Ctrl+9 event mapping
- [x] Add test for Ctrl+0 → session 10 mapping

### Step 5: Medium Priority - Provider Keys Extraction (R1)
- [x] Create `lib/jido_code/config/provider_keys.ex`
- [x] Move provider key mappings to new module
- [x] Update commands.ex to use shared module
- [x] Update tui.ex to use shared module
- [x] Add tests for new module

### Step 6: Low Priority - Consistency Fixes (CN1, CN3)
- [x] Standardize error returns in parse_session_args
- [x] CN2 skipped: execute_session/2 must stay public (used by TUI externally)
- [x] Remove redundant @doc false

### Step 7: Low Priority - Refactoring (R2, E1)
- [x] Extract format_resolution_error/2 helper
- [x] Refactor truncate_path/1 with pipe-friendly helpers

### Step 8: Run Tests and Verify
- [x] Run full test suite
- [x] Verify all new tests pass (190 tests for commands/model/integration)
- [x] Check for any regressions (pre-existing TUI test issues not related to changes)

## Files to Create/Modify

### New Files
- `lib/jido_code/config/provider_keys.ex` - Shared provider key mappings
- `test/jido_code/config/provider_keys_test.exs` - Tests for new module

### Modified Files
- `lib/jido_code/commands.ex` - Security, validation, consistency fixes
- `lib/jido_code/tui.ex` - Use shared provider keys
- `test/jido_code/commands_test.exs` - New security and validation tests
- `test/jido_code/tui_test.exs` - Handler and keyboard shortcut tests

## Success Criteria

1. All blockers addressed (B1, S1)
2. All medium priority concerns addressed (B2, B3, S2, R1)
3. All low priority suggestions implemented (CN1, CN2, CN3, R2, E1)
4. All tests pass
5. No regressions in existing functionality

# Feature: WS-2.5 Phase 2 Integration Tests

## Problem Statement

Phase 2 introduced several per-session components (Manager, State, Settings) that need to work together correctly. Integration tests are needed to verify:

1. Manager and State coordinate within a session
2. Settings load and merge correctly for sessions
3. Multiple sessions have complete isolation
4. Backwards compatibility is maintained with global Tools.Manager

## Solution Overview

Create comprehensive integration tests in `test/jido_code/integration/session_phase2_test.exs` that exercise all Phase 2 components working together.

## Technical Details

### Test File Location

- `test/jido_code/integration/session_phase2_test.exs`

### Test Dependencies

- SessionSupervisor for creating sessions
- Session.Manager for security sandbox operations
- Session.State for conversation state
- Session.Settings for per-project settings
- HandlerHelpers for session-aware path resolution

## Implementation Plan

### Task 2.5.1 Manager-State Integration
- [x] Create test file with setup
- [x] Test: Create session -> Manager and State both start -> both accessible via helpers
- [x] Test: Manager validates path -> State stores result metadata (via tool_call)
- [x] Test: Manager Lua execution -> State tracks tool call
- [x] Test: Session restart -> Manager and State both restart with correct session context
- [x] Test: HandlerHelpers.get_project_root uses session context
- [x] Test: HandlerHelpers.validate_path uses session context

### Task 2.5.2 Settings Integration
- [x] Test: Create session -> Settings loaded from project path
- [x] Test: Local settings override global settings in session config
- [x] Test: Missing local settings -> falls back to global only
- [x] Test: Save settings -> reload session -> settings persisted
- [x] Test: Session can use settings for configuration

### Task 2.5.3 Multi-Session Isolation
- [x] Test: Create 2 sessions -> each has own Manager with different project_root
- [x] Test: Create 2 sessions -> each has own State with independent messages
- [x] Test: Create 2 sessions -> each has own Lua sandbox (isolated state)
- [x] Test: Streaming in session A -> session B State unaffected
- [x] Test: Path validation in session A -> uses session A's project_root only
- [x] Test: File operations isolated between sessions

### Task 2.5.4 Backwards Compatibility
- [x] Test: HandlerHelpers.get_project_root with session_id -> uses Session.Manager
- [x] Test: HandlerHelpers.get_project_root without session_id -> uses global manager
- [x] Test: HandlerHelpers.get_project_root prefers session_id over project_root
- [x] Test: HandlerHelpers.validate_path with session_id -> uses Session.Manager
- [x] Test: HandlerHelpers.validate_path without session_id -> uses global manager
- [x] Test: Invalid session_id returns :invalid_session_id error
- [x] Test: Unknown session_id (valid UUID) returns :not_found error
- [x] Test: Deprecation warning logged when using global fallback

## Success Criteria

- [x] All integration tests pass (25 tests)
- [x] Tests cover all scenarios from phase-02.md Section 2.5
- [x] Tests verify isolation between sessions
- [x] Tests verify backwards compatibility

## Current Status

**Status**: Complete

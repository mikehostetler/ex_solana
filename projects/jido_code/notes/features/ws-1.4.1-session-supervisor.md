# Feature: WS-1.4.1 Session.Supervisor Module

## Problem Statement

The SessionSupervisor (DynamicSupervisor) needs a per-session supervisor module to start as children. Currently, tests use `SessionSupervisorStub` which simulates this behavior. Task 1.4.1 creates the real `JidoCode.Session.Supervisor` module.

## Solution Overview

Create `JidoCode.Session.Supervisor` as a regular Supervisor that:
1. Accepts a session struct via `:session` option
2. Registers in `SessionProcessRegistry` with `{:session, session_id}` key
3. Provides `child_spec/1` for DynamicSupervisor compatibility
4. Starts with empty children (children added in Task 1.4.2)

### Key Decisions

1. **Use `Supervisor` not `DynamicSupervisor`**: Children are known at startup
2. **Use `SessionProcessRegistry`**: Already created for this purpose (not `JidoCode.Registry`)
3. **Empty children for 1.4.1**: Task 1.4.2 will add Manager and State children
4. **`:temporary` restart**: Sessions shouldn't auto-restart if crashed

## Implementation Plan

### Step 1: Create module structure
- [x] Create `lib/jido_code/session/supervisor.ex`
- [x] Add `use Supervisor`
- [x] Add module documentation

### Step 2: Implement via/1 helper
- [x] Private function returning Registry via tuple
- [x] Use `SessionProcessRegistry` with `{:session, session_id}` key

### Step 3: Implement start_link/1
- [x] Accept opts with `:session` key
- [x] Fetch session and call Supervisor.start_link
- [x] Register via via/1 tuple

### Step 4: Implement child_spec/1
- [x] Return spec compatible with DynamicSupervisor
- [x] Set type: :supervisor, restart: :temporary

### Step 5: Implement init/1
- [x] Accept session struct
- [x] Return empty children list (for now)
- [x] Use `:one_for_all` strategy (will matter when children added)

### Step 6: Write tests
- [x] Test supervisor starts successfully
- [x] Test supervisor registers in SessionProcessRegistry
- [x] Test child_spec/1 returns correct spec
- [x] Test via/1 generates correct tuple (tested indirectly)
- [x] Test supervisor can be found by session ID
- [x] Test supervisor stops cleanly

## Success Criteria

- [x] Session.Supervisor module created
- [x] Registers in SessionProcessRegistry
- [x] Works with SessionSupervisor.start_session/1
- [x] All tests passing
- [x] Can replace SessionSupervisorStub in existing tests

## Current Status

**Status**: Complete

**What works**:
- Session.Supervisor module implemented at `lib/jido_code/session/supervisor.ex`
- Registers in SessionProcessRegistry via tuple
- Works with SessionSupervisor.start_session/1
- Integration tests verify it works with all SessionSupervisor functions
- Also fixed flaky test in SessionSupervisor tests (added wait_for_registry_cleanup helper)

**Tests**: 14 tests for Session.Supervisor + 42 SessionSupervisor tests = 56 total passing

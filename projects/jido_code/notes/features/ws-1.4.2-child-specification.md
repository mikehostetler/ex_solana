# Feature: WS-1.4.2 Child Specification

## Problem Statement

Session.Supervisor currently starts with no children. Task 1.4.2 adds the child processes that each session needs: Session.Manager and Session.State. These are placeholder GenServers for now - their full implementation will come in Phase 2.

## Solution Overview

1. Create `JidoCode.Session.Manager` - GenServer stub that will handle session coordination
2. Create `JidoCode.Session.State` - GenServer stub that will manage session state
3. Update `Session.Supervisor.init/1` to start these as children
4. Both children register in `SessionProcessRegistry` for lookup by Task 1.4.3

### Key Decisions

1. **GenServer stubs**: Full implementation in Phase 2, just need basic structure now
2. **Registry registration**: Children register with `{:manager, session_id}` and `{:state, session_id}` keys
3. **`:one_for_all` strategy**: Already set in Task 1.4.1, children are tightly coupled
4. **Session in process dictionary**: Pass session struct to children via opts

## Implementation Plan

### Step 1: Create Session.Manager stub
- [x] Create `lib/jido_code/session/manager.ex`
- [x] Basic GenServer with start_link/1 accepting session
- [x] Register in SessionProcessRegistry with `{:manager, session_id}`
- [x] Store session in state

### Step 2: Create Session.State stub
- [x] Create `lib/jido_code/session/state.ex`
- [x] Basic GenServer with start_link/1 accepting session
- [x] Register in SessionProcessRegistry with `{:state, session_id}`
- [x] Store session in state

### Step 3: Update Session.Supervisor init/1
- [x] Add Manager and State to children list
- [x] Pass session via opts to each child
- [x] Document `:one_for_all` rationale

### Step 4: Write tests
- [x] Test Manager starts with session
- [x] Test State starts with session
- [x] Test both register in SessionProcessRegistry
- [x] Test Session.Supervisor starts both children
- [x] Test children can be found by session ID

## Success Criteria

- [x] Session.Manager stub created and starts
- [x] Session.State stub created and starts
- [x] Session.Supervisor starts both children
- [x] Both children registered in SessionProcessRegistry
- [x] All tests passing
- [x] Documentation explains :one_for_all rationale

## Current Status

**Status**: Complete

**What works**:
- Session.Manager GenServer stub
- Session.State GenServer stub
- Session.Supervisor starts both children
- All children register in SessionProcessRegistry
- All tests passing

**Tests**: New tests for Manager/State + updated Session.Supervisor tests

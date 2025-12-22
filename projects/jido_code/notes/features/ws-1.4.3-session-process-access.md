# Feature: WS-1.4.3 Session Process Access

## Problem Statement

Users need a convenient way to access session child processes (Manager, State, Agent) by session ID. Currently they would need to manually do Registry lookups with the correct keys. Task 1.4.3 adds helper functions to Session.Supervisor for this.

## Solution Overview

Add three helper functions to `JidoCode.Session.Supervisor`:
1. `get_manager/1` - Returns Manager pid for a session
2. `get_state/1` - Returns State pid for a session
3. `get_agent/1` - Returns Agent pid (stub returning error until Phase 3)

All use Registry lookup with child-specific keys:
- `{:manager, session_id}`
- `{:state, session_id}`
- `{:agent, session_id}` (Phase 3)

## Implementation Plan

### Step 1: Implement get_manager/1
- [x] Add function to Session.Supervisor
- [x] Use Registry.lookup with {:manager, session_id}
- [x] Return {:ok, pid} or {:error, :not_found}

### Step 2: Implement get_state/1
- [x] Add function to Session.Supervisor
- [x] Use Registry.lookup with {:state, session_id}
- [x] Return {:ok, pid} or {:error, :not_found}

### Step 3: Implement get_agent/1 stub
- [x] Add function to Session.Supervisor
- [x] Return {:error, :not_implemented} until Phase 3
- [x] Document that LLMAgent will be added in Phase 3

### Step 4: Write tests
- [x] Test get_manager/1 returns Manager pid
- [x] Test get_manager/1 returns error for unknown session
- [x] Test get_state/1 returns State pid
- [x] Test get_state/1 returns error for unknown session
- [x] Test get_agent/1 returns :not_implemented

## Success Criteria

- [x] get_manager/1 returns Manager pid
- [x] get_state/1 returns State pid
- [x] get_agent/1 returns error (stub for Phase 3)
- [x] All tests passing
- [x] Functions documented with examples

## Current Status

**Status**: Complete

**What works**:
- All three helper functions implemented
- Tests verify correct behavior
- Documentation includes examples

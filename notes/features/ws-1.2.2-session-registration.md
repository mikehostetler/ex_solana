# Feature: WS-1.2.2 Session Registration

## Problem Statement

The SessionRegistry needs the ability to register sessions with proper validation and limit enforcement. Registration must prevent duplicate sessions (by ID or project path) and enforce the 10-session maximum.

### Impact
- Core functionality for session management
- Prevents resource exhaustion (10-session limit)
- Prevents conflicts (duplicate ID/path detection)
- Required by SessionSupervisor for session lifecycle

## Solution Overview

Implement `register/1` function with three validation checks:
1. Session count limit (max 10)
2. Duplicate session ID detection
3. Duplicate project path detection

### Key Design Decisions
- Check count first (cheapest operation)
- Check ID second (direct ETS lookup)
- Check path last (requires scan)
- Use `:ets.insert/2` only after all validations pass

## Technical Details

### Files to Modify
- `lib/jido_code/session_registry.ex` - Add register/1 implementation
- `test/jido_code/session_registry_test.exs` - Add registration tests

### Implementation Approach

```elixir
def register(%Session{} = session) do
  cond do
    count() >= @max_sessions ->
      {:error, :session_limit_reached}

    session_exists?(session.id) ->
      {:error, :session_exists}

    path_in_use?(session.project_path) ->
      {:error, :project_already_open}

    true ->
      :ets.insert(@table, {session.id, session})
      {:ok, session}
  end
end
```

### Helper Functions Needed
- `count/0` - Return number of sessions (Task 1.2.4, but needed here)
- `session_exists?/1` - Check if ID already registered
- `path_in_use?/1` - Check if project_path already registered

## Success Criteria

- [x] `register/1` accepts valid Session struct
- [x] Returns `{:error, :session_limit_reached}` at 10 sessions
- [x] Returns `{:error, :session_exists}` for duplicate ID
- [x] Returns `{:error, :project_already_open}` for duplicate path
- [x] Returns `{:ok, session}` on successful registration
- [x] Unit tests cover all scenarios

## Implementation Plan

### Step 1: Implement Helper Functions
- [x] Implement `count/0` using `:ets.info(@table, :size)`
- [x] Implement private `session_exists?/1`
- [x] Implement private `path_in_use?/1`

### Step 2: Implement register/1
- [x] Add validation logic with cond
- [x] Insert session on success
- [x] Return appropriate results

### Step 3: Write Tests
- [x] Test successful registration
- [x] Test session limit enforcement
- [x] Test duplicate ID rejection
- [x] Test duplicate path rejection
- [x] Test multiple registrations up to limit

## Current Status

**Status**: Complete

**What works**: All registration functionality implemented and tested

**What's next**: Merge to work-session branch

## Notes/Considerations

- `count/0` is needed for Task 1.2.4, but implementing now as it's required
- Path comparison should be exact match (not normalized)
- ETS operations are atomic, but the check-then-insert is not
- For production, consider using `:ets.insert_new/2` with match spec

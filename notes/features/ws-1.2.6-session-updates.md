# Feature: WS-1.2.6 Session Updates in Registry

## Problem Statement

The SessionRegistry needs a function to update session data after it has been registered. This is required when session configuration changes (e.g., via `Session.update_config/2`) or when the session is renamed (via `Session.rename/2`).

### Impact
- Required for session configuration changes at runtime
- Required for session renaming
- Completes the CRUD operations for the registry

## Solution Overview

Implement `update/1` that replaces an existing session in the registry:
1. Verify session exists (by ID)
2. Replace with `:ets.insert/2` (overwrites existing key)
3. Return appropriate result

### Key Design Decisions
- Check existence before update to provide clear error
- Use `:ets.insert/2` which overwrites existing entries with same key
- Session ID must match an existing registration
- Does NOT check for project_path conflicts (session keeps its original path)

## Technical Details

### Files to Modify
- `lib/jido_code/session_registry.ex` - Replace stub with implementation
- `test/jido_code/session_registry_test.exs` - Add update tests

### Implementation

**update/1** - Update existing session:
```elixir
def update(%Session{} = session) do
  if session_exists?(session.id) do
    :ets.insert(@table, {session.id, session})
    {:ok, session}
  else
    {:error, :not_found}
  end
end
```

Note: Uses existing `session_exists?/1` private function.

## Success Criteria

- [x] `update/1` replaces session in registry
- [x] `update/1` returns `{:ok, session}` on success
- [x] `update/1` returns `{:error, :not_found}` for non-existent session
- [x] Updated session can be retrieved via `lookup/1`
- [x] All unit tests pass

## Implementation Plan

### Step 1: Implement update/1
- [x] Check session exists using `session_exists?/1`
- [x] Use `:ets.insert/2` to replace entry
- [x] Return `{:ok, session}` or `{:error, :not_found}`

### Step 2: Write Tests
- [x] Test update/1 succeeds for existing session
- [x] Test update/1 returns error for non-existent session
- [x] Test updated session retrievable via lookup
- [x] Test update preserves other sessions
- [x] Test update with changed config
- [x] Test update returns error when ID not in table with sessions
- [x] Test update immediately after registration

## Current Status

**Status**: Complete

**What works**: All update operations implemented with 7 tests passing

**Total tests**: 71 tests in SessionRegistry, 0 failures

## Notes/Considerations

- `:ets.insert/2` is atomic and thread-safe
- Session ID is the key, so updating changes value but keeps same key
- This completes Section 1.2 (Session Registry)

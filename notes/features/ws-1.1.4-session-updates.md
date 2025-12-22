# Feature: WS-1.1.4 Session Updates

## Problem Statement

Sessions need to be updated after creation - users may want to change the LLM configuration (provider, model, temperature, max_tokens) or rename the session. Update functions must validate changes and maintain the `updated_at` timestamp.

### Impact
- Required by /config command to change LLM settings
- Required by /session rename command
- Enables runtime configuration changes without recreating sessions
- Maintains audit trail via updated_at timestamp

## Solution Overview

Implement two update functions:

1. `update_config/2` - Merges new config values with existing config
2. `rename/2` - Changes session name with validation

### Key Design Decisions
- Merge config (not replace) to allow partial updates
- Reuse existing validation from validate/1 where applicable
- Return `{:ok, session}` or `{:error, reason}` for consistency
- Always update `updated_at` timestamp on any change

## Technical Details

### Files to Modify
- `lib/jido_code/session.ex` - Add update_config/2 and rename/2 functions

### Files to Modify (Tests)
- `test/jido_code/session_test.exs` - Add update operation tests

### Function Signatures

```elixir
@spec update_config(t(), map()) :: {:ok, t()} | {:error, atom()}
def update_config(session, new_config)

@spec rename(t(), String.t()) :: {:ok, t()} | {:error, atom()}
def rename(session, new_name)
```

### Validation Rules

**update_config/2:**
- new_config must be a map
- Merged config must pass config validation rules from validate/1
- Only config keys (provider, model, temperature, max_tokens) are merged

**rename/2:**
- new_name must be non-empty string
- new_name must be max 50 characters (existing rule)

## Success Criteria

- [x] update_config/2 merges new config with existing
- [x] update_config/2 validates merged config
- [x] update_config/2 updates updated_at timestamp
- [x] update_config/2 returns error for invalid config values
- [x] rename/2 changes session name
- [x] rename/2 validates new name (non-empty, max 50 chars)
- [x] rename/2 updates updated_at timestamp
- [x] rename/2 returns error for invalid name
- [x] All tests pass (85 total)

## Implementation Plan

### Step 1: Implement update_config/2
- [x] Add update_config/2 public function
- [x] Merge new_config with session.config using custom merge_config/2
- [x] Update updated_at timestamp
- [x] Validate merged config
- [x] Return {:ok, session} or {:error, reason}

### Step 2: Implement rename/2
- [x] Add rename/2 public function
- [x] Validate new name (non-empty string, max 50 chars)
- [x] Update name and updated_at timestamp
- [x] Return {:ok, session} or {:error, reason}

### Step 3: Write Tests
- [x] Test update_config/2 merges config correctly
- [x] Test update_config/2 updates timestamp
- [x] Test update_config/2 validates new values
- [x] Test update_config/2 partial updates work
- [x] Test rename/2 changes name
- [x] Test rename/2 updates timestamp
- [x] Test rename/2 validates name length
- [x] Test rename/2 rejects empty name

## Current Status

**Status**: Complete

**What works**:
- Session.update_config/2 merges config with partial update support
- Session.rename/2 renames sessions with validation
- Both functions update updated_at timestamp
- Supports both atom and string keys in config
- 27 new tests (85 total tests)

**What's next**: Task 1.2.1 Session Registry

## Notes/Considerations

- Config merge allows partial updates (e.g., just changing temperature)
- Existing config values preserved if not overwritten
- Timestamp precision is DateTime (microseconds)
- Consider whether to validate entire session or just changed fields

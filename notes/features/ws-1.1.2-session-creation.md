# Feature: WS-1.1.2 Session Creation

## Problem Statement

Sessions need to be created programmatically with proper defaults, validation, and unique identification. The `Session.new/1` function will be the primary way to create new sessions throughout the application.

### Impact
- Required by SessionSupervisor.create_session/1
- Required by /session new command
- Foundation for session lifecycle management

## Solution Overview

Implement `Session.new/1` that:
1. Accepts keyword options (project_path required, name/config optional)
2. Generates RFC 4122 UUID v4 for unique identification
3. Extracts folder name as default session name
4. Loads default config from Settings if not provided
5. Validates project_path exists and is a directory
6. Returns `{:ok, session}` or `{:error, reason}`

### Key Design Decisions
- Use `:crypto.strong_rand_bytes/1` for UUID generation (no external deps)
- Path validation happens at creation time
- Config defaults loaded from Settings.load()
- Return tuples for explicit error handling

## Technical Details

### Files to Modify
- `lib/jido_code/session.ex` - Add new/1 and helper functions

### Files to Modify (Tests)
- `test/jido_code/session_test.exs` - Add creation tests

### Dependencies
- `JidoCode.Settings` - For default config loading

### Function Signatures

```elixir
@spec new(keyword()) :: {:ok, t()} | {:error, atom() | String.t()}
def new(opts)

@spec generate_id() :: String.t()
defp generate_id()
```

## Success Criteria

- [x] new/1 creates session with valid project_path
- [x] new/1 generates unique UUID v4 for id
- [x] new/1 uses folder name as default name
- [x] new/1 loads default config from Settings
- [x] new/1 accepts custom name override
- [x] new/1 accepts custom config override
- [x] new/1 returns error for non-existent path
- [x] new/1 returns error for file path (not directory)
- [x] UUID format matches RFC 4122 (8-4-4-4-12)
- [x] All tests pass (26 total)

## Implementation Plan

### Step 1: Implement generate_id/0
- [x] Add public generate_id/0 function
- [x] Use :crypto.strong_rand_bytes(16)
- [x] Set version bits (4) and variant bits (2)
- [x] Format as UUID string

### Step 2: Implement new/1
- [x] Extract project_path from opts (required)
- [x] Validate project_path exists
- [x] Validate project_path is directory
- [x] Extract or generate name
- [x] Load or use provided config
- [x] Generate id and timestamps
- [x] Return {:ok, session} or {:error, reason}

### Step 3: Write Tests
- [x] Test successful creation with project_path
- [x] Test custom name override
- [x] Test custom config override
- [x] Test default name from folder
- [x] Test default config from Settings
- [x] Test error for missing path
- [x] Test error for file (not directory)
- [x] Test UUID format validation

## Current Status

**Status**: Complete

**What works**:
- Session.new/1 creates sessions with all required fields
- UUID generation with RFC 4122 compliance
- Path validation (exists and is directory)
- Config loading from Settings with fallback defaults
- 26 tests passing

**What's next**: Task 1.1.3 Session Validation

## Notes/Considerations

- Settings.load() may return empty map if no settings file exists - handle gracefully
- Config should have sensible defaults even without Settings
- UUID generation is pure Elixir with no external dependencies

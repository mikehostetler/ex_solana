# Feature: WS-1.2.1 Session Registry Module Structure

## Problem Statement

JidoCode needs a registry to track active sessions with enforcement of a 10-session limit. This registry serves as the central lookup for session data and enforces uniqueness constraints on session IDs and project paths.

### Impact
- Foundation for session management (Section 1.2)
- Required by SessionSupervisor (Section 1.3) for session lifecycle
- Required by TUI (Phase 4) for tab list display
- Enables session limit enforcement for resource management

## Solution Overview

Create an ETS-backed SessionRegistry module that provides:
1. Table creation and management
2. Session registration with limit enforcement
3. Lookup by ID, path, and name
4. Session listing and counting
5. Session removal and updates

This task (1.2.1) focuses on the module structure and ETS table management.

### Key Design Decisions
- Use ETS `:named_table` with `:public` access for concurrent reads
- Use `:set` table type for unique session ID keys
- Enable `read_concurrency: true` for optimized reads
- Store sessions as `{session_id, session_struct}` tuples

## Technical Details

### Files to Create
- `lib/jido_code/session_registry.ex` - Main registry module
- `test/jido_code/session_registry_test.exs` - Unit tests

### Module Attributes
```elixir
@max_sessions 10
@table __MODULE__
```

### ETS Table Configuration
```elixir
:ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
```

## Success Criteria

- [x] SessionRegistry module created with documentation
- [x] `@max_sessions` constant defined as 10
- [x] `@table` constant defined as `__MODULE__`
- [x] `create_table/0` creates ETS table with correct options
- [x] `table_exists?/0` correctly reports table status
- [x] Unit tests pass for table creation

## Implementation Plan

### Step 1: Create Module Structure
- [x] Create `lib/jido_code/session_registry.ex`
- [x] Add module documentation
- [x] Define module attributes

### Step 2: Implement Table Management
- [x] Implement `create_table/0`
- [x] Implement `table_exists?/0`
- [x] Handle already-exists case in `create_table/0`

### Step 3: Write Tests
- [x] Test table creation succeeds
- [x] Test table creation is idempotent (doesn't crash if exists)
- [x] Test `table_exists?/0` returns correct values
- [x] Test table has correct configuration

## Current Status

**Status**: Complete

**What works**: All Task 1.2.1 subtasks implemented and tested

**What's next**: Merge to work-session branch

## Notes/Considerations

- The table should be created in `Application.start/2` before SessionSupervisor starts
- Table is `:public` so any process can read/write (controlled via API functions)
- `read_concurrency: true` optimizes for read-heavy workloads (lookups)
- Future tasks (1.2.2-1.2.6) will add registration, lookup, listing, removal, and update operations

# Feature: WS-1.1.1 Session Module

## Problem Statement

JidoCode needs a Session struct to encapsulate all session-specific configuration and metadata for the work-session architecture. This is the foundational data structure that will be used throughout the multi-project support feature.

### Impact
- Foundation for all subsequent work-session phases
- Defines the core data model for session management
- Required by SessionRegistry, SessionSupervisor, and all session-related components

## Solution Overview

Create `lib/jido_code/session.ex` with:
1. Session struct definition with all required fields
2. Type specifications for the struct and config
3. Module documentation

### Key Design Decisions
- Use RFC 4122 UUID v4 for session IDs (globally unique, random)
- Config stored as a map (not struct) for flexibility
- Timestamps use DateTime for timezone awareness
- Name derived from folder basename by default

## Technical Details

### Files to Create
- `lib/jido_code/session.ex` - Session module with struct and types
- `test/jido_code/session_test.exs` - Unit tests for types

### Dependencies
- None (foundational module)

### Struct Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String.t()` | RFC 4122 UUID v4 |
| `name` | `String.t()` | Display name (folder name default) |
| `project_path` | `String.t()` | Absolute project directory |
| `config` | `config()` | LLM configuration map |
| `created_at` | `DateTime.t()` | Creation timestamp |
| `updated_at` | `DateTime.t()` | Last update timestamp |

### Config Type

| Field | Type | Description |
|-------|------|-------------|
| `provider` | `String.t()` | LLM provider name |
| `model` | `String.t()` | Model identifier |
| `temperature` | `float()` | Sampling temperature |
| `max_tokens` | `pos_integer()` | Max response tokens |

## Success Criteria

- [x] Session struct defined with all fields
- [x] `@type t()` typespec defined
- [x] `@type config()` typespec defined
- [x] `defstruct` with all fields
- [x] Module documentation
- [x] Compiles without warnings
- [x] Tests pass (10 tests)

## Implementation Plan

### Step 1: Create Session Module
- [x] Create `lib/jido_code/session.ex`
- [x] Add module documentation
- [x] Define `@type config()`
- [x] Define `@type t()`
- [x] Implement `defstruct`

### Step 2: Verification
- [x] Compile and verify no warnings
- [x] Create basic test file
- [x] Run tests

## Current Status

**Status**: Complete

**What works**:
- Session struct with all required fields
- Type specifications for struct and config
- Module documentation
- Compiles without warnings
- Basic test passes

**What's next**:
- Task 1.1.2: Session Creation (new/1 function)

## Notes/Considerations

- Config is a map type rather than a struct to allow flexibility for provider-specific settings
- UUID generation will be implemented in task 1.1.2 when `new/1` is created
- This task only creates the struct definition and types, not the creation/validation logic

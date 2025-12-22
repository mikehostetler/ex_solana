# Feature: WS-1.1.3 Session Validation

## Problem Statement

Sessions need validation to ensure data integrity before being registered or persisted. The `Session.validate/1` function will verify all session fields meet requirements and return detailed error information when validation fails.

### Impact
- Required by SessionRegistry before registering sessions
- Required by Session persistence before saving
- Ensures data consistency across the session system

## Solution Overview

Implement `Session.validate/1` that:
1. Validates all session struct fields
2. Returns `{:ok, session}` if valid
3. Returns `{:error, reasons}` with list of validation failures
4. Performs comprehensive validation of nested config map

### Key Design Decisions
- Return list of all errors (not just first) for better UX
- Validate config fields individually for specific error messages
- Use atoms for error reasons (machine-readable)
- Check path existence at validation time (not just format)

## Technical Details

### Files to Modify
- `lib/jido_code/session.ex` - Add validate/1 and helper functions

### Files to Modify (Tests)
- `test/jido_code/session_test.exs` - Add validation tests

### Validation Rules

| Field | Rules | Error Atoms |
|-------|-------|-------------|
| `id` | Non-empty string | `:invalid_id` |
| `name` | Non-empty string, max 50 chars | `:invalid_name`, `:name_too_long` |
| `project_path` | Absolute path, directory exists | `:invalid_project_path`, `:path_not_absolute`, `:path_not_found` |
| `config.provider` | Non-empty string | `:invalid_provider` |
| `config.model` | Non-empty string | `:invalid_model` |
| `config.temperature` | Float 0.0-2.0 | `:invalid_temperature` |
| `config.max_tokens` | Positive integer | `:invalid_max_tokens` |
| `created_at` | DateTime | `:invalid_created_at` |
| `updated_at` | DateTime | `:invalid_updated_at` |

## Success Criteria

- [x] validate/1 returns {:ok, session} for valid session
- [x] validate/1 returns {:error, reasons} with all errors
- [x] Validates id is non-empty string
- [x] Validates name is non-empty string, max 50 chars
- [x] Validates project_path is absolute and exists
- [x] Validates config.provider is non-empty string
- [x] Validates config.model is non-empty string
- [x] Validates config.temperature is float 0.0-2.0
- [x] Validates config.max_tokens is positive integer
- [x] Validates timestamps are DateTime
- [x] All tests pass (58 total)

## Implementation Plan

### Step 1: Implement validate/1
- [x] Add validate/1 public function
- [x] Collect all validation errors
- [x] Return {:ok, session} or {:error, reasons}

### Step 2: Implement field validators
- [x] validate_id/2
- [x] validate_name/2
- [x] validate_session_project_path/2
- [x] validate_config/2
- [x] validate_timestamps/3

### Step 3: Write Tests
- [x] Test valid session passes
- [x] Test each validation rule individually
- [x] Test multiple errors returned together

## Current Status

**Status**: Complete

**What works**:
- Session.validate/1 validates all session fields
- Returns {:ok, session} for valid sessions
- Returns {:error, reasons} with all validation failures
- Supports both atom and string keys in config
- 32 new tests for validate/1 (58 total tests)

**What's next**: Task 1.1.4 Session Updates

## Notes/Considerations

- Provider validation could check against known providers list, but for flexibility we just check non-empty
- Temperature range 0.0-2.0 matches common LLM API limits
- Path existence check may have race conditions but acceptable for validation

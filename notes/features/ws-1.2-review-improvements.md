# Feature: WS-1.2 Review Improvements

## Problem Statement

The code review of Section 1.2 (Session Registry) identified several concerns and suggestions that should be addressed to improve code quality, maintainability, and production-readiness.

### Items to Address

**Concerns (⚠️):**
- C1: Public ETS Table Access - SKIP (acceptable for single-user TUI)
- C2: Race Condition in register/1 - SKIP (acceptable for single-user TUI)
- C3: Fragile ETS Match Specs - FIX
- C4: Missing Application Integration - FIX

**Suggestions (💡):**
- S1: Configurable Session Limit - IMPLEMENT
- S2: Add Write Concurrency - IMPLEMENT
- S3: Extract Match Spec Helper - IMPLEMENT (combined with C3)
- S4: Implement session_exists?/1 via lookup/1 - IMPLEMENT
- S5: Add Telemetry/Logging - SKIP (defer to Phase 6)

## Solution Overview

### C3 & S3: Refactor Match Specs

Replace fragile struct patterns with map patterns and extract a helper function:

```elixir
# Before (fragile - must list all fields)
%Session{project_path: :"$1", id: :_, name: :_, config: :_, created_at: :_, updated_at: :_}

# After (robust - only specify fields we care about)
defp build_match_spec(field, value, return_type) do
  [{
    {:_, %{field => :"$1"}},
    [{:==, :"$1", value}],
    [return_type]
  }]
end
```

### C4: Application Integration

Add `SessionRegistry.create_table()` to the application startup.

### S1: Configurable Session Limit

Change from compile-time constant to runtime configuration:

```elixir
# Before
@max_sessions 10
def max_sessions, do: @max_sessions

# After
@default_max_sessions 10
def max_sessions do
  Application.get_env(:jido_code, :max_sessions, @default_max_sessions)
end
```

### S2: Write Concurrency

Add `write_concurrency: true` to ETS options for Phase 6/7 readiness.

### S4: Simplify session_exists?/1

```elixir
defp session_exists?(session_id) do
  match?({:ok, _}, lookup(session_id))
end
```

## Success Criteria

- [x] Match specs use map patterns (not struct patterns)
- [x] Match spec helper function extracts common logic
- [x] session_exists?/1 implemented via lookup/1
- [x] max_sessions is configurable via Application config
- [x] ETS table has write_concurrency: true
- [x] SessionRegistry.create_table() called in Application.start
- [x] All existing tests still pass
- [x] New tests for configurable max_sessions

## Implementation Plan

### Step 1: Extract Match Spec Helper
- [x] Create build_match_spec/3 private function
- [x] Update path_in_use?/1 to use helper
- [x] Update lookup_by_path/1 to use helper
- [x] Update lookup_by_name/1 to use helper

### Step 2: Simplify session_exists?/1
- [x] Implement via match?({:ok, _}, lookup/1)

### Step 3: Make max_sessions Configurable
- [x] Change @max_sessions to @default_max_sessions
- [x] Update max_sessions/0 to use Application.get_env
- [x] Add test for configuration

### Step 4: Add Write Concurrency
- [x] Add write_concurrency: true to ETS options

### Step 5: Application Integration
- [x] Add SessionRegistry.create_table() to Application.start

### Step 6: Run Tests
- [x] Verify all 71 tests still pass (now 74 tests)
- [x] Add test for configurable max_sessions
- [x] Add test for write_concurrency

## Current Status

**Status**: Complete

**What works**: All improvements implemented and tested

**Tests**: 74 tests, 0 failures

## Notes

- C1 (Public ETS) and C2 (Race Condition) are deferred - acceptable for single-user TUI
- S5 (Telemetry) deferred to Phase 6 when we have more observability infrastructure

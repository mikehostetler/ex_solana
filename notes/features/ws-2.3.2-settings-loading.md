# Feature: WS-2.3.2 Settings Loading

## Problem Statement

Task 2.3.2 requires implementing settings loading for a project path. The Session.Settings module needs functions to load global settings, load local settings from a specific project path, and merge them with proper precedence (global < local).

## Solution Overview

Add loading functions to `JidoCode.Session.Settings`:
- `load/1` - Load and merge global + local settings for a project path
- `load_local/1` - Load only local settings from project path
- `load_global/0` - Load only global settings

### Key Decisions

1. **Delegate to JidoCode.Settings** - Use `Settings.read_file/1` and `Settings.global_path/0` for file operations
2. **Same error handling pattern** - Missing files return empty map, malformed JSON logs warning and returns empty map
3. **Simple merge** - Use `Map.merge/2` (local overrides global) - can enhance to deep_merge later if needed

## Technical Details

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_code/session/settings.ex` | Add load/1, load_local/1, load_global/0 |
| `test/jido_code/session/settings_test.exs` | Add tests for loading functions |

### New Functions

```elixir
@spec load(String.t()) :: map()
def load(project_path)

@spec load_local(String.t()) :: map()
def load_local(project_path)

@spec load_global() :: map()
def load_global()
```

## Implementation Plan

### Step 1: Implement load_global/0
- [x] Add `load_global/0` that reads from `Settings.global_path()`
- [x] Handle missing file (return empty map)
- [x] Handle malformed JSON (log warning, return empty map)

### Step 2: Implement load_local/1
- [x] Add `load_local/1` that reads from `local_path(project_path)`
- [x] Handle missing file (return empty map)
- [x] Handle malformed JSON (log warning, return empty map)

### Step 3: Implement load/1
- [x] Add `load/1` that calls load_global() and load_local()
- [x] Merge with Map.merge (local overrides global)

### Step 4: Write Unit Tests
- [x] Test `load_global/0` with existing file
- [x] Test `load_global/0` with missing file
- [x] Test `load_local/1` with existing file
- [x] Test `load_local/1` with missing file
- [x] Test `load_local/1` with malformed JSON
- [x] Test `load/1` merges global and local
- [x] Test `load/1` local overrides global

## Success Criteria

- [x] `load/1` merges global and local settings
- [x] `load_local/1` reads project-specific settings
- [x] Missing files handled gracefully (return empty map)
- [x] Malformed JSON logged and handled gracefully
- [x] All tests pass

## Current Status

**Status**: Complete

All functions implemented, tests pass (14 tests), ready for commit.


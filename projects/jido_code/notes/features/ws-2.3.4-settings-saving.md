# Feature: WS-2.3.4 Settings Saving

## Problem Statement

Task 2.3.4 requires implementing settings saving for session-specific overrides. The Session.Settings module needs functions to save settings to a project's local settings file and update individual keys.

## Solution Overview

Add saving functions to `JidoCode.Session.Settings`:
- `save/2` - Save full settings map to local file
- `set/3` - Update individual setting key

### Key Decisions

1. **Delegate to JidoCode.Settings** - Reuse `Settings.validate/1` for settings validation
2. **Atomic writes** - Write to temp file then rename for crash safety
3. **Use ensure_local_dir/1** - Create directory if missing (already implemented in 2.3.3)
4. **Same error handling pattern** - Return `:ok` or `{:error, reason}`

## Technical Details

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_code/session/settings.ex` | Add save/2, set/3, write_atomic/2 |
| `test/jido_code/session/settings_test.exs` | Add tests for saving functions |

### New Functions

```elixir
@spec save(String.t(), map()) :: :ok | {:error, term()}
def save(project_path, settings)
# Save settings map to {project_path}/.jido_code/settings.json

@spec set(String.t(), String.t(), term()) :: :ok | {:error, term()}
def set(project_path, key, value)
# Update single key in local settings

defp write_atomic(path, settings)
# Write to temp file then rename for crash safety
```

## Implementation Plan

### Step 1: Implement save/2
- [x] Add `save/2` function accepting project_path and settings map
- [x] Validate settings using `Settings.validate/1`
- [x] Use `ensure_local_dir/1` to create directory
- [x] Write settings atomically

### Step 2: Implement set/3
- [x] Add `set/3` function for single key updates
- [x] Load current settings with `load_local/1`
- [x] Merge new key and save

### Step 3: Implement write_atomic/2
- [x] Write to temp file (.tmp suffix)
- [x] Rename to final path
- [x] Set file permissions (0o600)
- [x] Verify file size

### Step 4: Write Unit Tests
- [x] Test `save/2` creates settings file
- [x] Test `save/2` creates directory if missing
- [x] Test `save/2` validates settings
- [x] Test `set/3` updates individual key
- [x] Test `set/3` preserves other keys

## Success Criteria

- [x] `save/2` writes settings to local file
- [x] `save/2` creates directory if missing
- [x] `save/2` validates settings before saving
- [x] `set/3` updates individual keys
- [x] All tests pass

## Current Status

**Status**: Complete

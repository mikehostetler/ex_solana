# Summary: WS-2.4.1 Manager Compatibility Layer

## Overview

This task adds session awareness to the global `Tools.Manager`, creating a compatibility layer that allows gradual migration from the global manager to session-scoped `Session.Manager` instances.

## Changes Made

### API Updates

The following functions now accept an optional `:session_id` keyword argument:

| Function | Old Signature | New Signature |
|----------|---------------|---------------|
| `project_root` | `project_root()` | `project_root(opts \\ [])` |
| `validate_path` | `validate_path(path, opts)` | `validate_path(path, opts \\ [])` |
| `read_file` | `read_file(path)` | `read_file(path, opts \\ [])` |
| `write_file` | `write_file(path, content)` | `write_file(path, content, opts \\ [])` |
| `list_dir` | `list_dir(path)` | `list_dir(path, opts \\ [])` |

### Behavior

When `session_id` is provided in options:
- Delegates to `Session.Manager` for the specified session
- Uses session's project root and security boundary
- Returns `{:error, :not_found}` if session doesn't exist

When `session_id` is NOT provided:
- Falls back to global manager behavior
- Logs deprecation warning (configurable)

### Deprecation Warnings

Warnings can be suppressed via application config:

```elixir
config :jido_code, suppress_global_manager_warnings: true
```

### Migration Path

Documented in the module doc with before/after examples:

```elixir
# Before (deprecated)
{:ok, path} = Tools.Manager.project_root()
{:ok, content} = Tools.Manager.read_file("src/file.ex")

# After (recommended)
{:ok, path} = Tools.Manager.project_root(session_id: session.id)
{:ok, content} = Tools.Manager.read_file("src/file.ex", session_id: session.id)

# Or use Session.Manager directly
{:ok, path} = Session.Manager.project_root(session.id)
```

## Test Coverage

Added 17 new tests in `test/jido_code/tools/manager_test.exs`:

**Session-Aware Compatibility Layer Tests:**
- `project_root/1` delegates when session_id provided
- `project_root/1` uses global when no session_id
- `project_root/1` returns error for unknown session
- `validate_path/2` delegates when session_id provided
- `validate_path/2` uses global when no session_id
- `validate_path/2` returns error for unknown session
- `read_file/2` delegates when session_id provided
- `read_file/2` returns error for unknown session
- `write_file/3` delegates when session_id provided
- `write_file/3` returns error for unknown session
- `list_dir/2` delegates when session_id provided
- `list_dir/2` returns error for unknown session

**Deprecation Warning Tests:**
- Logs warning when using global without session_id
- Suppresses warning when configured
- Does not log warning when session_id provided

**Total tests:** 55 tests, all passing

## Files Changed

- `lib/jido_code/tools/manager.ex` - Added session-aware API
- `test/jido_code/tools/manager_test.exs` - Added compatibility layer tests
- `notes/features/ws-2.4.1-manager-compatibility-layer.md` - Planning doc
- `notes/planning/work-session/phase-02.md` - Marked task complete

## Backwards Compatibility

All existing code continues to work unchanged. The deprecation warnings guide users toward the new session-scoped pattern without breaking existing functionality.

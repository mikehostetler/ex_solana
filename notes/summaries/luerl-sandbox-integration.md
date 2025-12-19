# Luerl Sandbox Integration Summary

## Overview

This feature routes ALL local system operations through the Luerl sandbox, eliminating direct `File.*` and `System.cmd` calls in tool handlers. This provides a consistent security boundary where all file I/O and shell commands flow through:

```
Handler → Manager API → Lua Script → Bridge Function → Security Module → File/System.cmd
```

## Changes Made

### 1. Bridge Module (`lib/jido_code/tools/bridge.ex`)

- Added `mtime` field to `lua_file_stat/3` output with ISO 8601 formatting
- Added `decode_shell_args/2` to handle Lua table references (tref) in shell arguments
- Helper `format_datetime/1` converts Erlang datetime tuples to ISO 8601 strings

### 2. Manager Module (`lib/jido_code/tools/manager.ex`)

- Added `parse_mtime/1` to decode ISO 8601 datetime strings back to Erlang tuples
- Fixed `array_table?/1` to treat empty lists as arrays (was returning `false`, causing `{:ok, %{}}` instead of `{:ok, []}`)

### 3. Handler Modules

All handlers updated to use Manager API instead of direct File/Security calls:

**file_system.ex:**
- All handlers (ReadFile, WriteFile, EditFile, ListDirectory, FileInfo, CreateDirectory, DeleteFile) now call `Manager.read_file/1`, `Manager.write_file/2`, etc.
- Added `format_mtime/1` helper for FileInfo handler
- Removed Security module dependency

**search.ex:**
- Grep handler uses Manager for file operations
- Added `validate_search_path/1` to propagate security errors early
- FindFiles uses `Manager.validate_path/1` and `Manager.is_file?/1`

**shell.ex:**
- RunCommand uses `Manager.shell/2` instead of direct System.cmd

**livebook.ex:**
- All handlers use Manager API for file operations
- Removed direct File/Security module calls

### 4. Test Infrastructure

**test/support/manager_isolation.ex:**
- Created `ManagerIsolation` helper for test setup
- `set_project_root/1` stops Manager, starts with new root, restores on cleanup
- Uses Process.monitor to properly wait for process termination
- Handles `{:error, {:already_started, pid}}` race conditions

**Handler tests updated:**
- Changed to `async: false` to avoid conflicts
- Added setup block calling `ManagerIsolation.set_project_root(tmp_dir)`
- Fixed case-sensitive error message assertions

### 5. mix.exs

- Moved `preferred_cli_env` to new `def cli` function (fixes deprecation warning)

## Key Fixes

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| Manager not running in tests | Tests didn't start Manager with tmp_dir | Created ManagerIsolation helper |
| Empty dir returns `%{}` not `[]` | `array_table?([])` returned false | Return true for empty lists |
| FileInfo missing mtime | Not included in lua_file_stat | Added mtime with ISO 8601 format |
| Shell args as tref | Luerl table references not decoded | Added decode_shell_args |
| Grep ignores security errors | validate_search_path missing | Added early security check |

## Test Results

- Handler tests: 104 tests, 0 failures, 1 skipped (timeout test needs future work)
- All file_system, search, shell, and livebook handlers pass
- Security violations properly logged and propagated

## Files Modified

```
lib/jido_code/tools/bridge.ex
lib/jido_code/tools/manager.ex
lib/jido_code/tools/handlers/file_system.ex
lib/jido_code/tools/handlers/search.ex
lib/jido_code/tools/handlers/shell.ex
lib/jido_code/tools/handlers/livebook.ex
test/support/manager_isolation.ex
test/jido_code/tools/handlers/file_system_test.exs
test/jido_code/tools/handlers/search_test.exs
test/jido_code/tools/handlers/shell_test.exs
test/jido_code/tools/handlers/livebook_test.exs
mix.exs
```

## Remaining Work

- Shell command timeout support (test skipped with TODO in shell_test.exs)
- Consider adding timeout parameter to Manager.shell/2

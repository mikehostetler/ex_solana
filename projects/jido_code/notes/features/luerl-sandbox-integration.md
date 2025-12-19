# Feature: Luerl Sandbox Integration

## Problem Statement

Currently, tool handlers bypass the Luerl sandbox by calling `File.*` and `System.cmd` directly. The Bridge module exists with security-validated wrappers, but it's not integrated into the Manager or used by handlers. This defeats the purpose of the Lua sandbox.

**Goal**: Route ALL local system operations (file I/O, shell commands) through the Luerl sandbox to ensure consistent security enforcement.

## Current State Analysis

### What Exists (70% Complete)
- **Manager** (`manager.ex`): Lua state with restricted dangerous functions (os.execute, io.popen removed)
- **Security** (`security.ex`): Path validation, atomic operations, TOCTOU mitigation
- **Bridge** (`bridge.ex`): Security-validated Lua wrappers for:
  - `jido.read_file(path)` - Uses `Security.atomic_read`
  - `jido.write_file(path, content)` - Uses `Security.atomic_write`
  - `jido.list_dir(path)` - Uses `Security.validate_path`
  - `jido.file_exists(path)` - Uses `Security.validate_path`
  - `jido.shell(command, args, opts)` - Validates command allowlist

### What's Missing
1. Bridge functions NOT registered in Manager.init() - they exist but are never loaded
2. Handlers call `File.*` directly (26 calls) instead of through sandbox
3. Missing Bridge functions: `file_stat`, `is_file`, `is_dir`, `delete_file`, `mkdir_p`
4. No convenient Elixir API for handlers to call sandboxed operations

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Tool Handlers                               │
│  (FileSystem, Search, Shell, Livebook)                          │
└────────────────────────────┬────────────────────────────────────┘
                             │ Call Manager API (Elixir functions)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Manager (GenServer)                            │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ New Elixir API:                                             ││
│  │   read_file/2, write_file/3, list_dir/2, file_stat/2,      ││
│  │   is_file/2, is_dir/2, delete_file/2, mkdir_p/2, shell/3   ││
│  └─────────────────────────────────────────────────────────────┘│
│                             │                                    │
│                             ▼ Execute Lua script                 │
│  ┌─────────────┐  ┌─────────────────────────────────────────┐   │
│  │ Lua State   │←→│ Bridge Functions (jido.* namespace)     │   │
│  │ (luerl)     │  │   Registered on init()                  │   │
│  └─────────────┘  └─────────────────────────────────────────┘   │
│                                                                  │
│  Dangerous functions removed: os.execute, io.popen, loadfile    │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Bridge Module (Elixir)                         │
│  lua_read_file → Security.atomic_read → File.read               │
│  lua_write_file → Security.atomic_write → File.write            │
│  lua_shell → Security.validate_command → System.cmd             │
└─────────────────────────────────────────────────────────────────┘
```

## Implementation Plan

### Phase 1: Register Bridge Functions in Manager ✅
- [x] In `init/1`, call `Bridge.register(lua_state, project_root)` after sandbox restrictions
- [x] Verify jido.* functions are available in Lua

### Phase 2: Add Missing Bridge Functions ✅
- [x] Add `lua_file_stat/3` - File.stat with validation
- [x] Add `lua_is_file/3` - File.regular? with validation
- [x] Add `lua_is_dir/3` - File.dir? with validation
- [x] Add `lua_delete_file/3` - File.rm with validation
- [x] Add `lua_mkdir_p/3` - File.mkdir_p with validation
- [x] Register new functions in `Bridge.register/2`

### Phase 3: Add Manager Elixir API ✅
- [x] Add `read_file/1` - Read file through sandbox
- [x] Add `write_file/2` - Write file through sandbox
- [x] Add `list_dir/1` - List directory through sandbox
- [x] Add `file_stat/1` - Get file stats through sandbox
- [x] Add `is_file?/1` - Check if path is file through sandbox
- [x] Add `is_dir?/1` - Check if path is directory through sandbox
- [x] Add `delete_file/1` - Delete file through sandbox
- [x] Add `mkdir_p/1` - Create directory through sandbox
- [x] Add `shell/2` - Run shell command through sandbox
- [x] Add corresponding handle_call clauses

### Phase 4: Update Handlers to Use Manager API
- [x] Phase 4a: Update `file_system.ex` handlers
- [x] Phase 4b: Update `search.ex` handlers
- [x] Phase 4c: Update `shell.ex` handlers
- [x] Phase 4d: Update `livebook.ex` handlers

### Phase 5: Tests ✅
- [x] Unit tests for new Bridge functions
- [x] Manager API tests
- [x] Integration tests for handlers through sandbox
- [x] Security tests for path validation

### Phase 6: Cleanup and Documentation ✅
- [x] Update CLAUDE.md with architecture changes
- [x] Remove unused imports
- [x] All tests passing

## Critical Files Modified

| File | Changes |
|------|---------|
| `lib/jido_code/tools/manager.ex` | Register Bridge, add Elixir API |
| `lib/jido_code/tools/bridge.ex` | Add missing functions |
| `lib/jido_code/tools/handlers/file_system.ex` | Use Manager API |
| `lib/jido_code/tools/handlers/search.ex` | Use Manager API |
| `lib/jido_code/tools/handlers/shell.ex` | Use Manager API |
| `lib/jido_code/tools/handlers/livebook.ex` | Use Manager API |
| `test/jido_code/tools/bridge_test.exs` | Test new functions |
| `test/jido_code/tools/manager_test.exs` | Test new API |

## Status

**Current Phase**: Implementation Complete
**Status**: All phases completed, tests passing

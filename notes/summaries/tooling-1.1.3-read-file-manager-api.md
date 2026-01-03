# Task 1.1.3: Read File Manager API

**Status**: ✅ Complete
**Branch**: `feature/1.1.3-read-file-manager-api`
**Plan Reference**: `notes/planning/tooling/phase-01-tools.md` - Section 1.1.3

## Summary

Implemented the Manager API for `read_file` with full offset/limit option support. Both `Tools.Manager` and `Session.Manager` now route read operations through the Lua sandbox, ensuring all file reads go through the security chain and return line-numbered content.

## Changes Made

### Modified Files

1. **`lib/jido_code/session/manager.ex`**
   - Updated `read_file/2` → `read_file/3` to accept options keyword list
   - Options supported: `:offset`, `:limit`
   - Added `call_lua_read_file/3` to execute via Lua sandbox
   - Added `build_lua_opts/1` to generate Lua key-value table syntax (`{offset = 3}`)
   - Added `lua_escape_string/1` for safe Lua string encoding
   - Updated handle_call to support both 2-tuple and 3-tuple formats for backward compatibility

2. **`lib/jido_code/tools/manager.ex`**
   - Updated `read_file/2` to extract and pass offset/limit options
   - Updated `handle_call({:sandbox_read_file, ...})` to accept options
   - Added `build_lua_read_opts/1` helper function
   - Options are encoded as Lua table via existing `lua_encode_arg/1`

3. **`lib/jido_code/tools/bridge.ex`**
   - Added pattern match for Lua table references (`{:tref, _}`)
   - When called via `:luerl.do`, tables are passed as references, not decoded lists
   - Bridge now decodes table references using `:luerl.decode/2`

### Updated Test Files

1. **`test/jido_code/tools/manager_test.exs`**
   - Updated `read_file/2 delegates...` to expect line-numbered output
   - Added 3 new tests for offset, limit, and combined offset+limit options

2. **`test/jido_code/session/manager_test.exs`**
   - Updated `reads file within boundary` to expect line-numbered output
   - Updated `rejects path outside boundary` to match string error messages
   - Updated `returns error for non-existent file` to match string error messages
   - Updated `Lua sandbox can execute bridge functions` for line-numbered output
   - Updated `can access bridge functions` for line-numbered output

## API Examples

```elixir
# Session-aware read with options
{:ok, content} = Manager.read_file("file.ex", session_id: "abc123", offset: 10, limit: 50)

# Global read (deprecated)
{:ok, content} = Manager.read_file("file.ex", offset: 1, limit: 100)

# Direct Session.Manager call
{:ok, content} = Session.Manager.read_file(session_id, "file.ex", offset: 5)
```

## Lua Table Handling

Key insight: When Lua tables are passed to Erlang functions via `:luerl.do`, they arrive as table references (`{:tref, N}`), not decoded Elixir terms. The Bridge now handles both formats:

1. **Direct Elixir calls** (tests): `[path, [{"offset", 3}]]` - opts is a list
2. **Lua calls** (runtime): `[path, {:tref, 14}]` - opts is a table reference

The Lua key-value syntax `{offset = 3}` decodes correctly to `[{"offset", 3}]` after `:luerl.decode/2`.

## Test Results

```
163 tests, 0 failures
```

All tests pass including:
- 58 Manager tests (including 3 new option tests)
- 37 Session.Manager tests (updated for line-numbered output)
- 68 Bridge tests

## Architecture Notes

The complete execution flow now follows the Lua sandbox architecture:

```
Tools.Manager.read_file(path, session_id: id, offset: 3)
    ↓
Session.Manager.read_file(id, path, [offset: 3])
    ↓
handle_call({:read_file, path, opts})
    ↓
call_lua_read_file(path, opts, lua_state)
    ↓
:luerl.do("return jido.read_file(\"path\", {offset = 3})", lua_state)
    ↓
Bridge.lua_read_file(["path", {:tref, _}], state, project_root)
    ↓
:luerl.decode(tref, state) → [{"offset", 3}]
    ↓
parse_read_opts → %{offset: 3}
    ↓
Security.atomic_read → format_with_line_numbers → result
```

## Next Steps

Task 1.2: Write File Tool
- Create write_file tool definition
- Update bridge and manager for atomic writes
- Add content size validation (max 10MB)

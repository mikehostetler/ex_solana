# Task 1.6.2: Glob Search Bridge Function

## Summary

Implemented the `lua_glob/3` bridge function for pattern-based file finding in the Lua sandbox. The function uses `Path.wildcard/2` for robust pattern matching with full glob syntax support.

## Completed Items

- [x] Added `lua_glob/3` to `bridge.ex`
- [x] Used `Path.wildcard/2` for pattern matching
- [x] Filter results through security boundary validation
- [x] Sort by modification time (newest first)
- [x] Return as Lua array of paths
- [x] Registered in `Bridge.register/2`
- [x] Created 11 bridge tests

## Files Modified

| File | Changes |
|------|---------|
| `lib/jido_code/tools/bridge.ex` | Added lua_glob/3 and helper functions (~110 lines) |
| `test/jido_code/tools/bridge_test.exs` | Added 11 lua_glob tests |
| `notes/planning/tooling/phase-01-tools.md` | Marked 1.6.2 as completed |

## Bridge Function

```elixir
@spec lua_glob(list(), :luerl.luerl_state(), String.t()) :: {list(), :luerl.luerl_state()}
def lua_glob(args, state, project_root)
```

### Arguments

- `[pattern]` - Glob pattern to match (searches from project root)
- `[pattern, path]` - Pattern with base directory to search from

### Returns

- `{[lua_array], state}` - Array of relative paths sorted by mtime
- `{[nil, error], state}` - Error message on failure

## Supported Patterns

| Pattern | Description |
|---------|-------------|
| `*` | Match any characters (not path separator) |
| `**` | Match any characters including path separators |
| `?` | Match any single character |
| `{a,b}` | Match either pattern a or pattern b |
| `[abc]` | Match any character in the set |

## Helper Functions Added

| Function | Purpose |
|----------|---------|
| `do_glob/4` | Core glob implementation |
| `filter_within_boundary/2` | Security boundary filter |
| `sort_by_mtime_desc/1` | Sort newest first |
| `make_relative/2` | Convert to relative paths |

## Tests Added

| Test | Description |
|------|-------------|
| finds files with ** pattern | Recursive matching |
| finds files with simple * pattern | Extension matching |
| finds files with brace expansion pattern | {ex,exs} patterns |
| uses base path for searching | Directory prefix |
| returns empty array for no matches | Empty results |
| sorts results by modification time | Mtime sorting |
| returns error for path traversal | Security validation |
| returns error for missing pattern | Argument validation |
| filters results to stay within boundary | Security boundary |
| returns error for non-existent base path | Path existence check |
| finds files with ? wildcard pattern | Single char wildcard |

## Example Usage in Lua

```lua
-- Find all Elixir files
local files = jido.glob("**/*.ex")

-- Find files in specific directory
local lib_files = jido.glob("*.ex", "lib")

-- Find multiple file types
local sources = jido.glob("**/*.{ex,exs}")
```

## Next Task

**1.6.3: Unit Tests for Glob Search**
- Test glob_search with ** pattern through sandbox
- Test glob_search with extension filter (*.ex)
- Test glob_search with directory prefix
- Test glob_search filters results within boundary
- Test glob_search handles empty results

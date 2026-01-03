# Section 1.5 Review Fixes

## Summary

Addressed all concerns from the Section 1.5 (List Directory Tool) code review. Created a shared `GlobMatcher` module to eliminate code duplication and improve security.

## Concerns Addressed

| ID | Description | Resolution |
|----|-------------|------------|
| C1 | Code duplication (~54 lines) | Created `GlobMatcher` module with shared functions |
| C2 | Glob pattern regex injection | Used `Regex.escape/1` to escape all metacharacters |
| C4 | Missing @spec on lua_list_dir/3 | Added @spec annotation |
| C5 | Missing @spec on private functions | Added @spec to all helper functions |
| C7 | Redundant :enotdir error handling | Removed, using `format_error/2` for all errors |
| C10 | Redundant Enum.sort() | Removed pre-sort, `sort_directories_first/2` handles ordering |
| C12 | Missing documentation sections | Added Limitations, Security, and See Also sections |
| C13 | Silent regex compilation errors | Added Logger.warning for invalid patterns |

## Files Created

| File | Lines | Purpose |
|------|-------|---------|
| `lib/jido_code/tools/helpers/glob_matcher.ex` | 130 | Shared glob matching utilities |
| `test/jido_code/tools/helpers/glob_matcher_test.exs` | 215 | Comprehensive unit tests |

## Files Modified

| File | Changes |
|------|---------|
| `lib/jido_code/tools/handlers/file_system.ex` | ListDir handler now uses GlobMatcher (~50 lines removed) |
| `lib/jido_code/tools/bridge.ex` | lua_list_dir now uses GlobMatcher, added @specs (~45 lines removed) |

## New GlobMatcher Module

The `JidoCode.Tools.Helpers.GlobMatcher` module provides:

- `matches_any?/2` - Check if entry matches any ignore pattern
- `matches_glob?/2` - Check if entry matches a single glob pattern
- `sort_directories_first/2` - Sort entries with directories first
- `entry_info/2` - Get entry name and type information

### Security Improvements

- Uses `Regex.escape/1` to escape ALL regex metacharacters: `+`, `[`, `]`, `(`, `)`, `|`, `{`, `}`, `\`, `^`, `$`
- Invalid patterns now log a warning instead of silently failing
- Comprehensive @spec annotations for Dialyzer support

## Test Coverage

| Test Suite | Count | Description |
|------------|-------|-------------|
| GlobMatcher unit tests | 33 | matches_any?, matches_glob?, sort_directories_first, entry_info |

### Test Coverage Includes

- Basic glob patterns (`*`, `?`)
- Exact string matching
- Combined wildcards
- Regex metacharacter escaping (`+`, `[]`, `()`, `|`, `{}`, `^$`, `\`)
- Unicode filenames
- Filenames with spaces
- Hidden files (dot prefix)
- Edge cases (empty lists, non-binary inputs)

## Code Reduction

- **Handler:** Removed 50+ lines of duplicated glob matching code
- **Bridge:** Removed 45+ lines of duplicated glob matching code
- **Total reduction:** ~95 lines replaced with calls to shared module

## Before/After

### Before (Handler)
```elixir
defp matches_glob?(entry, pattern) when is_binary(pattern) do
  regex_pattern =
    pattern
    |> String.replace(".", "\\.")
    |> String.replace("*", ".*")
    |> String.replace("?", ".")

  case Regex.compile("^#{regex_pattern}$") do
    {:ok, regex} -> Regex.match?(regex, entry)
    {:error, _} -> false
  end
end
```

### After (GlobMatcher)
```elixir
def matches_glob?(entry, pattern) when is_binary(entry) and is_binary(pattern) do
  regex_pattern = glob_to_regex(pattern)

  case Regex.compile("^#{regex_pattern}$") do
    {:ok, regex} -> Regex.match?(regex, entry)
    {:error, reason} ->
      Logger.warning("Invalid glob pattern #{inspect(pattern)}: #{inspect(reason)}")
      false
  end
end

defp glob_to_regex(pattern) do
  pattern
  |> escape_regex_metacharacters()
  |> String.replace("\\*", ".*")
  |> String.replace("\\?", ".")
end

defp escape_regex_metacharacters(pattern) do
  Regex.escape(pattern)
end
```

## Next Task

**1.6: Glob Search Tool** - Implement pattern-based file finding:
- 1.6.1 Tool Definition
- 1.6.2 Bridge Function Implementation
- 1.6.3 Unit Tests for Glob Search

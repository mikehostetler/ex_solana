# Task 1.6.4: Section 1.6 Review Fixes

## Summary

Addressed all concerns and suggestions from the Section 1.6 (Glob Search Tool) code review. The main focus was eliminating code duplication, improving security through symlink validation, and improving code consistency.

## Review Findings Addressed

### Concerns (Fixed)

| Issue | Fix |
|-------|-----|
| Code duplication between handler and bridge | Extracted 3 helpers to GlobMatcher module |
| Error atom `:file_not_found` not in `format_error` | Changed to `:enoent` |
| Symlinks not validated in glob results | Added symlink resolution in `filter_within_boundary/2` |
| Rescue clause too broad | Specified `ArgumentError` and `Jason.EncodeError` |
| Boolean in `with` not idiomatic | Added `ensure_exists/1` helper |

### Suggestions (Implemented)

| Issue | Fix |
|-------|-----|
| Missing test for `[abc]` patterns | Added test |
| Missing test for dot file exclusion | Added test |
| Missing symlink tests | Added tests for handler and GlobMatcher |

## Files Modified

| File | Changes |
|------|---------|
| `lib/jido_code/tools/helpers/glob_matcher.ex` | Added `filter_within_boundary/2`, `sort_by_mtime_desc/1`, `make_relative/2` with symlink validation (~130 lines) |
| `lib/jido_code/tools/handlers/file_system.ex` | Updated GlobSearch to use GlobMatcher, fixed error atom, improved rescue clause (~-45 lines) |
| `lib/jido_code/tools/bridge.ex` | Updated lua_glob to use GlobMatcher, added `ensure_exists/1` helper (~-35 lines) |
| `test/jido_code/tools/helpers/glob_matcher_test.exs` | Added 14 tests for new GlobMatcher functions (~155 lines) |
| `test/jido_code/tools/handlers/file_system_test.exs` | Added 4 handler tests, fixed error message assertion (~50 lines) |
| `notes/planning/tooling/phase-01-tools.md` | Added 1.6.4 section |

## New GlobMatcher Functions

```elixir
# Filter paths to project boundary with symlink validation
@spec filter_within_boundary(list(String.t()), String.t()) :: list(String.t())
def filter_within_boundary(paths, project_root)

# Sort by modification time (newest first)
@spec sort_by_mtime_desc(list(String.t())) :: list(String.t())
def sort_by_mtime_desc(paths)

# Convert absolute paths to relative
@spec make_relative(list(String.t()), String.t()) :: list(String.t())
def make_relative(paths, project_root)
```

## Symlink Security Enhancement

The `filter_within_boundary/2` function now:
1. Expands the path to check if it's within the project root
2. If it's a symlink, resolves the real target path
3. Checks if the resolved target is within the boundary
4. Filters out symlinks that point outside the project

```elixir
defp path_within_boundary?(path, expanded_root) do
  expanded_path = Path.expand(path)

  if String.starts_with?(expanded_path, expanded_root <> "/") do
    case File.read_link(path) do
      {:ok, _target} ->
        # Symlink - verify target is within boundary
        real_path = resolve_real_path(path)
        String.starts_with?(real_path, expanded_root <> "/")

      {:error, :einval} ->
        # Not a symlink, path check passed
        true
    end
  else
    false
  end
end
```

## Tests Added

### GlobMatcher Tests (14 new)
- `filter_within_boundary/2`: 5 tests
  - Filters paths within boundary
  - Excludes paths outside boundary
  - Handles empty list
  - Filters symlinks pointing outside boundary
  - Allows symlinks pointing inside boundary
- `sort_by_mtime_desc/1`: 3 tests
  - Sorts by modification time newest first
  - Handles empty list
  - Handles non-existent files gracefully
- `make_relative/2`: 4 tests
  - Converts absolute paths to relative
  - Handles multiple paths
  - Handles empty list
  - Handles nested directories

### Handler Tests (4 new)
- Character class `[abc]` pattern matching
- Dot file exclusion (match_dot: false)
- Symlinks pointing outside boundary filtered
- Error message format updated

## Test Results

```
267 tests, 0 failures
```

## Code Reduction

By extracting shared helpers:
- Handler: ~45 lines removed
- Bridge: ~35 lines removed
- GlobMatcher: ~130 lines added (shared, documented, tested)

**Net benefit**: Single source of truth, symlink security, full test coverage.

## Next Task

**1.7 Delete File Tool** - Implement the delete_file tool for file removal.

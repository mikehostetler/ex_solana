# Task 1.3.2 Edit Handler Implementation Summary

## Overview

Enhanced the `EditFile` handler in `lib/jido_code/tools/handlers/file_system.ex` with full security, multi-strategy matching, and session-aware file tracking.

## Completed Tasks

- [x] 1.3.2.1 Enhanced EditFile handler (uses inner module pattern)
- [x] 1.3.2.2 Validate path and verify file was read (read-before-write check)
- [x] 1.3.2.3 Implement exact string match (primary strategy)
- [x] 1.3.2.4 Implement line-trimmed match fallback
- [x] 1.3.2.5 Implement whitespace-normalized match fallback
- [x] 1.3.2.6 Implement indentation-flexible match fallback
- [x] 1.3.2.7 Verify old_string is unique in file
- [x] 1.3.2.8 Return error if multiple matches found
- [x] 1.3.2.9 Apply replacement atomically via Security.atomic_write
- [x] 1.3.2.10 Return `{:ok, message}` or `{:error, reason}`

## Files Modified

### `lib/jido_code/tools/handlers/file_system.ex`

Enhanced `EditFile` inner module with:

**New Aliases:**
- `JidoCode.Session.State` (as SessionState) - For read-before-write checks
- `JidoCode.Tools.HandlerHelpers` - For project root access
- `JidoCode.Tools.Security` - For atomic writes

**New Functions:**

| Function | Purpose |
|----------|---------|
| `check_read_before_edit/2` | Verifies file was read in session before editing |
| `track_file_write/2` | Tracks the edit in session state |
| `do_replace_with_strategies/4` | Orchestrates multi-strategy matching |
| `try_replace/5` | Attempts replacement with given strategy |
| `exact_match/2` | Literal string matching |
| `line_trimmed_match/2` | Ignores leading/trailing whitespace per line |
| `whitespace_normalized_match/2` | Collapses multiple spaces/tabs |
| `indentation_flexible_match/2` | Allows different indentation levels |
| `find_all_positions/2` | Finds exact positions of substring |
| `find_fuzzy_positions/3` | Finds positions with normalized matching |
| `trim_lines/1` | Trims whitespace from each line |
| `normalize_whitespace/1` | Collapses whitespace to single spaces |
| `dedent/1` | Removes common leading indentation |
| `count_leading_spaces/1` | Counts leading spaces for dedent |

## Implementation Details

### Execute Flow

```elixir
def execute(%{"path" => path, "old_string" => old_string, "new_string" => new_string} = args, context) do
  with {:ok, project_root} <- HandlerHelpers.get_project_root(context),
       {:ok, safe_path} <- Security.validate_path(path, project_root, log_violations: true),
       normalized_path <- FileSystem.normalize_path_for_tracking(path, project_root),
       :ok <- check_read_before_edit(normalized_path, context),
       {:ok, content} <- File.read(safe_path),
       {:ok, new_content, count, strategy} <- do_replace_with_strategies(...),
       :ok <- Security.atomic_write(path, new_content, project_root, log_violations: true),
       :ok <- track_file_write(normalized_path, context) do
    strategy_note = if strategy != :exact, do: " (matched via #{strategy})", else: ""
    {:ok, "Successfully replaced #{count} occurrence(s) in #{path}#{strategy_note}"}
  end
end
```

### Multi-Strategy Matching

Strategies are tried in order, stopping at the first successful match:

1. **Exact match** - Literal `String.contains?` and `String.replace`
2. **Line-trimmed match** - Trims leading/trailing whitespace from each line before matching
3. **Whitespace-normalized match** - Collapses multiple spaces/tabs to single space
4. **Indentation-flexible match** - Removes common leading indentation (dedent)

If a strategy finds multiple matches and `replace_all` is false, returns `{:error, :ambiguous_match, count}` immediately.

### Security Features

1. **Path Validation** - Uses `Security.validate_path/3` with violation logging
2. **Read-Before-Write** - Files must be read in session before editing (fail-closed)
3. **Atomic Writes** - Uses `Security.atomic_write/4` to prevent TOCTOU issues
4. **Session Tracking** - Tracks edits via `SessionState.track_file_write/2`
5. **Telemetry** - Emits telemetry for all outcomes (success, errors, violations)

### Error Handling

| Error | Message |
|-------|---------|
| `:read_before_write_required` | "File must be read before editing: {path}" |
| `:session_state_unavailable` | "Session state unavailable - cannot verify read-before-write requirement" |
| `:not_found` | "String not found in file (tried exact, line-trimmed, whitespace-normalized, and indentation-flexible matching): {path}" |
| `:ambiguous_match` | "Found {count} occurrences of the string in {path}. Use replace_all: true to replace all, or provide a more specific string." |

## Test Results

```
Finished in 0.7 seconds
72 tests, 0 failures (file_system_test.exs)

Finished in 0.2 seconds
25 tests, 0 failures (file_edit_test.exs)
```

## Key Design Decisions

### Multi-Strategy Order

Strategies are ordered by "faithfulness" to the original request:
1. Exact match is most faithful
2. Line-trimmed handles copy/paste whitespace issues
3. Whitespace-normalized handles LLM formatting variations
4. Indentation-flexible handles code block indentation differences

### Fail-Closed Security

- Missing session = legacy mode (skip check with debug log)
- Session not found = fail with error (security concern)
- This matches the WriteFile pattern established in task 1.2.2

### Strategy Reporting

Success messages include the strategy used if not exact match:
```
"Successfully replaced 1 occurrence(s) in lib/foo.ex (matched via line_trimmed)"
```

This helps users understand why their edit succeeded and may guide better `old_string` construction.

## Next Steps

- **Task 1.3.3**: Unit Tests for Edit File Handler
  - Test exact match, whitespace variations, indentation
  - Test uniqueness validation
  - Test read-before-write requirement
  - Test atomic write behavior

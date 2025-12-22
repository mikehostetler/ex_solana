# WS-3.2 Review Fixes Planning Document

**Branch:** `feature/ws-3.2-review-fixes`
**Date:** 2025-12-06
**Status:** In Progress

## Overview

This task addresses all concerns and suggestions identified in the Section 3.2 Handler Updates comprehensive review. The review was APPROVED with minor recommendations, and this work addresses those recommendations.

## Items to Address

### Concerns (Should Fix)

| # | Issue | Location | Priority |
|---|-------|----------|----------|
| C1 | Task 3.2.7 files not committed | - | ✅ Done (already committed) |
| C2 | Test infrastructure issues | Test files | Low (tests pass with app context) |
| C3 | WriteFile parent dir TOCTOU | `file_system.ex:249-252` | High |
| C4 | RunCommand timeout not enforced | `shell.ex:244` | High |
| C5 | Fallback to global Manager | `handler_helpers.ex:103-106` | Medium |

### Suggestions (Nice to Have)

| # | Suggestion | Location | Priority |
|---|------------|----------|----------|
| S1 | Extract common error formatting | Multiple handlers | Medium |
| S2 | Extract session test setup helper | Test files | Low |
| S3 | Add telemetry to HandlerHelpers | `handler_helpers.ex` | Medium |
| S4 | Document session context type | Handler modules | Low |
| S5 | Add file size limits | `file_system.ex` | High |
| S6 | URL-encoded path traversal detection | `shell.ex` | Medium |
| S7 | Rate limiting for tool execution | - | Low (defer) |
| S8 | Regex complexity limits for Grep | `search.ex` | Low (defer) |
| S9 | Remove redundant @doc false | `handler_helpers.ex` | Low |
| S10 | Fix unreachable pattern in TaskAgent | `task_agent.ex` | Low |

## Implementation Plan

### Task 1: Fix WriteFile TOCTOU Vulnerability (C3)
**Status:** Pending

**Problem:** `Path.dirname(safe_path)` followed by `File.mkdir_p(dir_path)` without revalidation. Parent dir symlink could escape boundary.

**Solution:** Validate the parent directory exists and is within boundary before mkdir_p.

**Files:**
- `lib/jido_code/tools/handlers/file_system.ex`

**Changes:**
```elixir
# Before mkdir_p, validate parent directory path
with {:ok, safe_path} <- FileSystem.validate_path(path, context),
     dir_path <- Path.dirname(safe_path),
     :ok <- validate_parent_directory(dir_path, context) do
  # proceed with mkdir_p and write
end

defp validate_parent_directory(".", _context), do: :ok
defp validate_parent_directory(dir_path, context) do
  # Each parent component must be validated
  case File.lstat(dir_path) do
    {:ok, %{type: :symlink}} ->
      # Symlink - validate where it points
      case File.read_link(dir_path) do
        {:ok, target} ->
          resolved = Path.expand(target, Path.dirname(dir_path))
          case HandlerHelpers.get_project_root(context) do
            {:ok, root} ->
              if String.starts_with?(resolved, root <> "/") or resolved == root do
                :ok
              else
                {:error, :symlink_escapes_boundary}
              end
            error -> error
          end
        _ -> :ok
      end
    {:ok, _} -> :ok
    {:error, :enoent} -> :ok  # Will be created
    {:error, reason} -> {:error, reason}
  end
end
```

### Task 2: Implement RunCommand Timeout (C4)
**Status:** Pending

**Problem:** Timeout parameter is accepted but ignored. Commands can hang indefinitely.

**Solution:** Wrap System.cmd in a Task with yield/shutdown.

**Files:**
- `lib/jido_code/tools/handlers/shell.ex`

**Changes:**
```elixir
defp run_command(command, args, project_root, timeout) do
  task = Task.async(fn ->
    try do
      System.cmd(command, args,
        cd: project_root,
        stderr_to_stdout: true,
        env: []
      )
    rescue
      e -> {:error, e}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end)

  case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
    {:ok, {:error, e}} ->
      {:error, Shell.format_error({:system_error, e}, command)}
    {:ok, {output, exit_code}} ->
      stdout = maybe_truncate(output)
      {:ok, Jason.encode!(%{exit_code: exit_code, stdout: stdout, stderr: ""})}
    nil ->
      {:error, Shell.format_error(:timeout, command)}
  end
end
```

### Task 3: Add File Size Limits (S5)
**Status:** Pending

**Problem:** No limit on content size for write_file.

**Solution:** Add 10MB limit with configurable option.

**Files:**
- `lib/jido_code/tools/handlers/file_system.ex`

**Changes:**
```elixir
@max_file_size 10 * 1024 * 1024  # 10MB

def execute(%{"path" => path, "content" => content}, context) do
  with :ok <- validate_content_size(content),
       {:ok, safe_path} <- FileSystem.validate_path(path, context) do
    # ...
  end
end

defp validate_content_size(content) when byte_size(content) > @max_file_size do
  {:error, :content_too_large}
end
defp validate_content_size(_), do: :ok
```

### Task 4: Add require_session_context Config (C5)
**Status:** Pending

**Problem:** Fallback to global Manager may hide configuration issues.

**Solution:** Add config option to fail hard instead of falling back.

**Files:**
- `lib/jido_code/tools/handler_helpers.ex`

**Changes:**
```elixir
def get_project_root(_context) do
  if Application.get_env(:jido_code, :require_session_context, false) do
    {:error, :session_context_required}
  else
    log_deprecation_warning("get_project_root")
    Manager.project_root()
  end
end
```

### Task 5: Add URL-encoded Path Traversal Detection (S6)
**Status:** Pending

**Problem:** Shell only checks literal `../`, not URL-encoded variants.

**Solution:** Check for `%2e%2e%2f` and other encoded variants.

**Files:**
- `lib/jido_code/tools/handlers/shell.ex`

**Changes:**
```elixir
defp validate_single_arg(arg, project_root) do
  cond do
    # Check for path traversal patterns (literal and URL-encoded)
    contains_path_traversal?(arg) ->
      {:error, {:path_traversal_blocked, arg}}
    # ... rest of validation
  end
end

defp contains_path_traversal?(arg) do
  String.contains?(arg, "../") or
  String.contains?(String.downcase(arg), "%2e%2e%2f") or
  String.contains?(String.downcase(arg), "%2e%2e/") or
  String.contains?(String.downcase(arg), "..%2f")
end
```

### Task 6: Add Telemetry to HandlerHelpers (S3)
**Status:** Pending

**Problem:** No telemetry for path validation to track migration.

**Solution:** Add telemetry events for context resolution.

**Files:**
- `lib/jido_code/tools/handler_helpers.ex`

**Changes:**
```elixir
def get_project_root(%{session_id: session_id}) when is_binary(session_id) do
  :telemetry.execute(
    [:jido_code, :handler_helpers, :context_resolution],
    %{count: 1},
    %{type: :session_id, session_id: session_id}
  )
  # ... existing logic
end
```

### Task 7: Remove Redundant @doc false (S9)
**Status:** Pending

**Problem:** `@doc false` on private functions is redundant.

**Files:**
- `lib/jido_code/tools/handler_helpers.ex`

### Task 8: Fix Unreachable Pattern in TaskAgent (S10)
**Status:** Pending

**Problem:** `{:ok, content} when is_binary(content)` can never match after `{:ok, %{content: content}}`.

**Files:**
- `lib/jido_code/agents/task_agent.ex`

**Changes:**
Remove the unreachable clause:
```elixir
case ChatCompletion.run(...) do
  {:ok, %{content: content}} when is_binary(content) ->
    {:ok, content}

  # REMOVE: {:ok, content} when is_binary(content) ->
  #   {:ok, content}

  {:ok, %{response: response}} when is_binary(response) ->
    {:ok, response}

  {:ok, result} when is_map(result) ->
    content = Map.get(result, :content) || Map.get(result, :response) || inspect(result)
    {:ok, content}

  {:error, reason} ->
    {:error, reason}
end
```

### Task 9: Add Timeout Error Formatting (New)
**Status:** Pending

**Files:**
- `lib/jido_code/tools/handlers/shell.ex`

**Changes:**
```elixir
def format_error(:timeout, command), do: "Command timed out: #{command}"
```

### Task 10: Add Content Too Large Error (New)
**Status:** Pending

**Files:**
- `lib/jido_code/tools/handlers/file_system.ex`

**Changes:**
```elixir
def format_error(:content_too_large, _path),
  do: "Content exceeds maximum file size (10MB)"
```

## Deferred Items

The following suggestions are deferred to future work:
- **S2**: Extract session test setup helper (low priority, tests work)
- **S7**: Rate limiting for tool execution (requires more design)
- **S8**: Regex complexity limits for Grep (requires ReDoS detection library)

## Testing Plan

1. Add test for WriteFile with symlinked parent directory
2. Add test for RunCommand timeout enforcement
3. Add test for file size limit rejection
4. Add test for require_session_context config
5. Add test for URL-encoded path traversal detection
6. Run full test suite to verify no regressions

## Completion Checklist

- [x] Task 1: Fix WriteFile TOCTOU
- [x] Task 2: Implement RunCommand timeout
- [x] Task 3: Add file size limits
- [x] Task 4: Add require_session_context config
- [x] Task 5: Add URL-encoded path traversal detection
- [x] Task 6: Add telemetry to HandlerHelpers
- [x] Task 7: Remove redundant @doc false
- [x] Task 8: Fix unreachable pattern in TaskAgent
- [x] Task 9: Add timeout error formatting
- [x] Task 10: Add content too large error
- [x] Run tests
- [x] Write summary

# Feature: WS-3.2.3 Shell Handler Session Context

## Problem Statement

The shell handler (`RunCommand`) currently uses the global `Tools.Manager.shell/2` for command execution. This bypasses session-scoped security boundaries and doesn't leverage the per-session project root for working directory.

Task 3.2.3 requires updating the shell handler to use session context for:
1. Working directory (cwd) set to session's project_root
2. Path argument validation against session boundary

## Current State

### Current Handler Pattern

```elixir
# RunCommand - uses global Manager.shell
def execute(%{"command" => command} = args, _context) do
  with {:ok, _valid_command} <- Shell.validate_command(command),
       cmd_args <- parse_args(raw_args) do
    run_command_via_sandbox(command, cmd_args)  # Uses Manager.shell
  end
end

defp run_command_via_sandbox(command, args) do
  case Manager.shell(command, args) do
    {:ok, result} -> ...
  end
end
```

The `Manager.shell/2` internally:
1. Uses the global Manager's project_root
2. Validates path arguments in Lua sandbox
3. Executes with `System.cmd` using `cd: project_root`

## Solution Overview

Update the shell handler to:
1. Use `HandlerHelpers.get_project_root/1` to get session's project root
2. Validate path arguments via `HandlerHelpers.validate_path/2` before execution
3. Execute commands directly with `System.cmd` using session's project_root as cwd
4. Maintain backwards compatibility with legacy `project_root` context

### New Handler Pattern

```elixir
def execute(%{"command" => command} = args, context) do
  with {:ok, _valid_command} <- Shell.validate_command(command),
       {:ok, project_root} <- Shell.get_project_root(context),
       cmd_args <- parse_args(raw_args),
       :ok <- validate_path_args(cmd_args, project_root, context) do
    run_command(command, cmd_args, project_root)
  end
end

defp run_command(command, args, project_root) do
  # Direct System.cmd with session's project_root as cwd
  case System.cmd(command, args, cd: project_root, stderr_to_stdout: true) do
    {output, 0} -> {:ok, format_result(0, output)}
    {output, exit_code} -> {:ok, format_result(exit_code, output)}
  end
end
```

## Implementation Plan

### Step 1: Add validate_path delegate
- [x] Add `validate_path/2` delegate to Shell module

### Step 2: Update RunCommand.execute/2
- [x] Use `Shell.get_project_root/1` to get project root
- [x] Validate path arguments using session context
- [x] Execute with `System.cmd` directly using session's cwd
- [x] Maintain command allowlist validation
- [x] Maintain output truncation

### Step 3: Path Argument Validation
- [x] Validate path-like arguments against session boundary
- [x] Block path traversal patterns (../)
- [x] Block absolute paths outside project

### Step 4: Write unit tests
- [x] Test RunCommand with session context
- [x] Test path argument validation with session
- [x] Test invalid session_id returns error

## Success Criteria

- [x] Shell handler uses session-aware project root
- [x] Path arguments validated against session boundary
- [x] Handler works with both session_id and project_root context
- [x] All existing tests pass
- [x] New tests cover session context usage

## Current Status

**Status**: Complete

## Test Results

- 35 shell handler tests pass (30 existing + 5 new)
- 5 new session-aware tests:
  - RunCommand uses session_id for project root
  - RunCommand runs in session's project directory
  - session_id context blocks path traversal
  - session_id context blocks absolute paths outside project
  - invalid session_id returns error

## Files Changed

### Modified
- `lib/jido_code/tools/handlers/shell.ex` - Session-aware handler
- `test/jido_code/tools/handlers/shell_test.exs` - Added session context tests

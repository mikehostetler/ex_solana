# Feature Plan: WS-6.5.1 Resume Command Handler

**Phase**: 6 (Work Session Management)
**Task**: 6.5.1 - Resume Command Handler
**Module**: `JidoCode.Commands`
**Status**: Planning

## Problem Statement

With session persistence complete (Task 6.2), session listing available (Task 6.3), and the resume functionality implemented (Task 6.4.2), users need a command-line interface to resume their saved sessions. The `/resume` command must:

1. List resumable sessions when invoked without arguments
2. Allow resuming a specific session by index (1-10) or by UUID
3. Display session information in a user-friendly format with timestamps
4. Handle all error cases gracefully (missing sessions, invalid paths, limits)
5. Integrate seamlessly with the existing TUI session management system

This command completes the session lifecycle: create → work → close → list → resume.

## Solution Overview

Implement the `/resume` command in the Commands module following the established pattern for session commands. The implementation will have two modes:

- **List mode**: `/resume` with no arguments lists all resumable sessions
- **Restore mode**: `/resume <index|uuid>` resumes a specific session

The command parser will:
- Parse `/resume` → `{:resume, :list}`
- Parse `/resume <target>` → `{:resume, {:restore, target}}`

The command executor will:
- Handle `{:resume, :list}` by calling `Persistence.list_resumable()` and formatting output
- Handle `{:resume, {:restore, target}}` by resolving target to UUID and calling `Persistence.resume(session_id)`
- Return session actions for the TUI to handle (similar to `/session new`)

The implementation follows existing patterns from `/session` commands for consistency.

## Agent Consultations

No agent consultations required - this is a straightforward command implementation following established patterns in the Commands module.

## Technical Details

### Current Architecture Context

#### Commands Module Structure

The Commands module (`lib/jido_code/commands.ex`) handles all slash commands. Structure:
- `execute/2` - Main entry point, delegates to `parse_and_execute/2`
- `parse_and_execute/2` - Pattern matches command strings
- `execute_session/2` - Handles `/session` subcommands
- Helper functions for validation, resolution, formatting

#### Session Command Pattern

Existing `/session` commands follow this pattern:

```elixir
# 1. Parsing in parse_and_execute/2
defp parse_and_execute("/session " <> rest, _config) do
  {:session, parse_session_args(String.trim(rest))}
end

# 2. Execution in execute_session/2
def execute_session({:new, opts}, _model) do
  with {:ok, resolved_path} <- resolve_session_path(path),
       {:ok, validated_path} <- validate_session_path(resolved_path),
       {:ok, session} <- create_new_session(validated_path, name) do
    {:session_action, {:add_session, session}}
  else
    {:error, :session_limit_reached} ->
      {:error, "Maximum 10 sessions reached. Close a session first."}
    # ... more error cases
  end
end

# 3. TUI handling in handle_session_command/2
{:session_action, {:add_session, session}} ->
  new_state = Model.add_session(state, session)
  # Subscribe to PubSub, show message
```

We'll follow this same pattern for `/resume`.

#### Persistence Module Interface

Task 6.4.2 implemented these functions in `JidoCode.Session.Persistence`:

```elixir
@spec list_resumable() :: [map()]
# Returns list of session metadata:
# %{
#   id: "uuid",
#   name: "session-name",
#   project_path: "/path/to/project",
#   closed_at: "2025-01-15T10:30:00Z"
# }

@spec resume(String.t()) :: {:ok, Session.t()} | {:error, term()}
# Errors:
# - :not_found
# - :project_path_not_found
# - :project_path_not_directory
# - :session_limit_reached
# - :project_already_open
```

#### Rate Limiting

Task 6.4.3 added rate limiting to `Persistence.resume/1`:
- Uses `JidoCode.RateLimit` module
- Prevents rapid retry attacks
- Integrated into resume flow

### Implementation Strategy

#### File Modifications

**Primary File**: `lib/jido_code/commands.ex`

Modifications needed:
1. Update `@help_text` to document `/resume` command
2. Add command parsing in `parse_and_execute/2`
3. Add command execution in `execute_session/2`
4. Add helper functions: `format_resumable_list/1`, `format_ago/1`, `resolve_resume_target/2`

#### Command Parsing

Add to `parse_and_execute/2`:

```elixir
defp parse_and_execute("/resume " <> rest, _config) do
  {:session, {:resume, {:restore, String.trim(rest)}}}
end

defp parse_and_execute("/resume", _config) do
  {:session, {:resume, :list}}
end
```

**Design Decision**: Return `{:session, ...}` tuple to route through existing session command handling. This provides consistency with other session commands and reuses the TUI's session action handlers.

#### Command Execution - List Mode

Add to `execute_session/2`:

```elixir
def execute_session({:resume, :list}, _model) do
  alias JidoCode.Session.Persistence

  sessions = Persistence.list_resumable()
  output = format_resumable_list(sessions)
  {:ok, output}
end
```

**Format Function**:

```elixir
defp format_resumable_list([]) do
  "No sessions to resume.\n\nSessions are saved when closed with /session close."
end

defp format_resumable_list(sessions) do
  header = "Resumable sessions:\n\n"

  list = sessions
  |> Enum.with_index(1)
  |> Enum.map_join("\n", fn {session, idx} ->
    format_resumable_line(session, idx)
  end)

  footer = "\n\nUse /resume <number> or /resume <id> to restore a session."
  header <> list <> footer
end

defp format_resumable_line(session, idx) do
  name = session.name
  path = truncate_path(session.project_path)
  time_ago = format_ago(session.closed_at)

  "  #{idx}. #{name} (#{path}) - closed #{time_ago}"
end
```

**Example Output**:

```
Resumable sessions:

  1. my-project (~/code/my-project) - closed 2 hours ago
  2. another-proj (~/code/another) - closed yesterday
  3. old-session (~/code/old) - closed 2025-01-10

Use /resume <number> or /resume <id> to restore a session.
```

**Reuse**: The `truncate_path/1` function already exists in Commands module for session list formatting.

#### Command Execution - Restore Mode

Add to `execute_session/2`:

```elixir
def execute_session({:resume, {:restore, target}}, _model) do
  alias JidoCode.Session.Persistence

  sessions = Persistence.list_resumable()

  case resolve_resume_target(target, sessions) do
    {:ok, session_id} ->
      case Persistence.resume(session_id) do
        {:ok, session} ->
          {:session_action, {:add_session, session}}

        {:error, :not_found} ->
          {:error, "Session not found. Use /resume to see available sessions."}

        {:error, :project_path_not_found} ->
          {:error, "Project path no longer exists. The project may have been moved or deleted."}

        {:error, :project_path_not_directory} ->
          {:error, "Project path is not a directory."}

        {:error, :session_limit_reached} ->
          {:error, "Maximum 10 sessions reached. Close a session first with /session close."}

        {:error, :project_already_open} ->
          {:error, "Project already open in another session."}

        {:error, {:rate_limit_exceeded, retry_after_seconds}} ->
          {:error, "Too many resume attempts. Please wait #{retry_after_seconds} seconds."}

        {:error, reason} ->
          {:error, "Failed to resume session: #{inspect(reason)}"}
      end

    {:error, :not_found} ->
      {:error, "Session not found: #{target}. Use /resume to see available sessions."}

    {:error, :no_resumable_sessions} ->
      {:error, "No resumable sessions available."}

    {:error, :invalid_index} ->
      {:error, "Invalid session index: #{target}. Use /resume to see available sessions."}
  end
end
```

**Target Resolution Function**:

```elixir
@doc """
Resolves a resume target (index or UUID) to a session ID.

## Parameters

- `target` - String that's either a number (1-N index) or a UUID
- `sessions` - List of session metadata from list_resumable()

## Returns

- `{:ok, session_id}` - Resolved to UUID
- `{:error, :not_found}` - Invalid index or UUID not found
- `{:error, :no_resumable_sessions}` - Empty session list
- `{:error, :invalid_index}` - Index out of range

## Examples

    iex> resolve_resume_target("1", [%{id: "abc-123", ...}])
    {:ok, "abc-123"}

    iex> resolve_resume_target("abc-123", [%{id: "abc-123", ...}])
    {:ok, "abc-123"}
"""
@spec resolve_resume_target(String.t(), [map()]) ::
  {:ok, String.t()} | {:error, atom()}
defp resolve_resume_target(_target, []) do
  {:error, :no_resumable_sessions}
end

defp resolve_resume_target(target, sessions) do
  cond do
    # Try as numeric index
    numeric_target?(target) ->
      resolve_resume_by_index(target, sessions)

    # Try as UUID (check if target matches any session ID)
    uuid_in_sessions?(target, sessions) ->
      {:ok, target}

    # Not found
    true ->
      {:error, :not_found}
  end
end

defp resolve_resume_by_index(target, sessions) do
  {index, ""} = Integer.parse(target)

  case Enum.at(sessions, index - 1) do
    nil -> {:error, :invalid_index}
    session -> {:ok, session.id}
  end
end

defp uuid_in_sessions?(target, sessions) do
  Enum.any?(sessions, fn session -> session.id == target end)
end
```

**Reuse**: The `numeric_target?/1` function already exists in Commands module for session switching.

#### Time Formatting

Implement human-friendly relative time formatting:

```elixir
@doc """
Formats an ISO 8601 timestamp as relative time.

Returns "just now", "X min ago", "X hours ago", "X days ago",
or absolute date for older timestamps.

## Examples

    iex> format_ago("2025-01-15T10:28:00Z")  # Now is 10:30:00
    "2 min ago"

    iex> format_ago("2025-01-15T08:00:00Z")  # Now is 10:00:00
    "2 hours ago"

    iex> format_ago("2025-01-14T10:00:00Z")  # Yesterday
    "1 day ago"

    iex> format_ago("2025-01-01T10:00:00Z")  # 2 weeks ago
    "2025-01-01"
"""
@spec format_ago(String.t()) :: String.t()
defp format_ago(iso_timestamp) when is_binary(iso_timestamp) do
  case DateTime.from_iso8601(iso_timestamp) do
    {:ok, dt, _offset} ->
      diff_seconds = DateTime.diff(DateTime.utc_now(), dt, :second)
      format_time_diff(diff_seconds, dt)

    {:error, _} ->
      # Fallback for invalid timestamps
      "unknown"
  end
end

defp format_ago(_), do: "unknown"

defp format_time_diff(seconds, dt) when seconds < 0 do
  # Future timestamp (shouldn't happen, but handle gracefully)
  "just now"
end

defp format_time_diff(seconds, _dt) when seconds < 60 do
  "just now"
end

defp format_time_diff(seconds, _dt) when seconds < 3600 do
  minutes = div(seconds, 60)
  "#{minutes} min ago"
end

defp format_time_diff(seconds, _dt) when seconds < 86400 do
  hours = div(seconds, 3600)
  pluralize(hours, "hour")
end

defp format_time_diff(seconds, _dt) when seconds < 172800 do
  # Less than 2 days - show "yesterday" or "1 day ago"
  "yesterday"
end

defp format_time_diff(seconds, _dt) when seconds < 604800 do
  # Less than 1 week - show days
  days = div(seconds, 86400)
  pluralize(days, "day")
end

defp format_time_diff(_seconds, dt) do
  # 1 week or more - show absolute date
  dt
  |> DateTime.to_date()
  |> Date.to_string()
end

defp pluralize(1, unit), do: "1 #{unit} ago"
defp pluralize(n, unit), do: "#{n} #{unit}s ago"
```

**Design Decisions**:
- Show "just now" for < 1 minute (avoids "0 min ago")
- Show "yesterday" instead of "1 day ago" for better UX
- Switch to absolute dates after 1 week (easier to read than "12 days ago")
- Handle invalid/future timestamps gracefully

#### TUI Integration

The TUI already handles `{:session_action, {:add_session, session}}` in `handle_session_command/2`. No changes needed to TUI - it will automatically:
1. Add the resumed session to the tab bar
2. Switch to the new session
3. Subscribe to its PubSub topic
4. Display success message

This provides seamless integration with existing session management.

#### Help Text Update

Update `@help_text` module attribute:

```elixir
@help_text """
Available commands:

  /help                    - Show this help message
  /config                  - Display current configuration
  ...
  /session                 - Show session command help
  /session new [path]      - Create new session (--name=NAME for custom name)
  /session list            - List all sessions
  /session switch <target> - Switch to session by index, ID, or name
  /session close [target]  - Close session (default: active)
  /session rename <name>   - Rename current session
  /resume                  - List resumable sessions
  /resume <index|id>       - Resume a saved session
  ...
"""
```

### Error Handling

The implementation handles all error cases from `Persistence.resume/1`:

| Error | User Message | Actionable Advice |
|-------|-------------|-------------------|
| `:not_found` | "Session not found" | Use /resume to see available sessions |
| `:project_path_not_found` | "Project path no longer exists" | Path may have been moved or deleted |
| `:project_path_not_directory` | "Path is not a directory" | Path validation failed |
| `:session_limit_reached` | "Maximum 10 sessions reached" | Close a session first |
| `:project_already_open` | "Project already open" | Another session exists for this path |
| `:rate_limit_exceeded` | "Too many attempts" | Wait N seconds before retrying |
| Other | "Failed to resume session" | Show debug info for investigation |

**Edge Cases**:
1. **Empty resumable list**: Show helpful message about closing sessions to persist them
2. **Invalid index**: "0" or "11" when only 5 sessions - clear error with /resume hint
3. **UUID not in list**: User provides valid UUID but it's not resumable (maybe active) - check and show appropriate error
4. **Concurrent resume**: Two terminals try to resume same session - one succeeds, other gets "already open"
5. **Invalid timestamp**: Persisted session has malformed closed_at - show "unknown" instead of crashing

### Integration with Existing Session Commands

The `/resume` command complements existing session commands:

```
Session Lifecycle:
1. /session new [path]        Create session (active)
2. [work on project]          Session is active
3. /session close             Save and close (persisted)
4. /resume                    List saved sessions
5. /resume <index>            Restore session (active again)
```

**Consistency**:
- Both use index-based selection (1-10)
- Both support UUID fallback
- Both show paths with `truncate_path/1`
- Both route through session command handler
- Both return session actions for TUI

**Differences**:
- `/resume` shows timestamps, `/session list` shows active marker
- `/resume` filters out active sessions automatically
- `/resume` can fail with path/limit errors, `/session switch` only validates active sessions

## Success Criteria

1. `/resume` command lists all resumable sessions with formatted output
2. `/resume <index>` successfully resumes a session by numeric index
3. `/resume <uuid>` successfully resumes a session by ID
4. Timestamps are formatted as human-readable relative times
5. Empty list shows helpful message about closing sessions
6. All error cases return clear, actionable error messages
7. Resumed sessions appear in TUI tab bar automatically
8. Rate limiting errors are handled gracefully
9. Help text includes /resume documentation
10. All unit tests pass with 100% coverage

## Implementation Plan

### Step 1: Add Command Parsing (6.5.1.1)

**File**: `lib/jido_code/commands.ex`

```elixir
# Add after existing /session parsing
defp parse_and_execute("/resume " <> rest, _config) do
  {:session, {:resume, {:restore, String.trim(rest)}}}
end

defp parse_and_execute("/resume", _config) do
  {:session, {:resume, :list}}
end
```

**Test**: Verify parsing returns correct tuples

### Step 2: Implement List Handler (6.5.1.2)

**File**: `lib/jido_code/commands.ex`

```elixir
def execute_session({:resume, :list}, _model) do
  alias JidoCode.Session.Persistence
  sessions = Persistence.list_resumable()
  output = format_resumable_list(sessions)
  {:ok, output}
end
```

**Test**:
- Empty list shows helpful message
- Non-empty list formats correctly
- Verify calls to Persistence.list_resumable()

### Step 3: Implement Format Functions (6.5.1.3)

**File**: `lib/jido_code/commands.ex`

```elixir
defp format_resumable_list([]), do: "..."
defp format_resumable_list(sessions), do: "..."
defp format_resumable_line(session, idx), do: "..."
```

**Test**:
- Empty list message
- Single session formatting
- Multiple sessions formatting
- Long names/paths truncated correctly

### Step 4: Implement Time Formatting (6.5.3.1)

**File**: `lib/jido_code/commands.ex`

```elixir
defp format_ago(iso_timestamp), do: "..."
defp format_time_diff(seconds, dt), do: "..."
defp pluralize(n, unit), do: "..."
```

**Test**:
- "just now" for < 1 minute
- "X min ago" for < 1 hour
- "X hours ago" for < 1 day
- "yesterday" for 1-2 days
- "X days ago" for 2-7 days
- Absolute date for > 7 days
- Handle invalid timestamps

### Step 5: Implement Target Resolution (6.5.2.2)

**File**: `lib/jido_code/commands.ex`

```elixir
defp resolve_resume_target(target, sessions), do: "..."
defp resolve_resume_by_index(target, sessions), do: "..."
defp uuid_in_sessions?(target, sessions), do: "..."
```

**Test**:
- Resolve by index (1-N)
- Resolve by UUID
- Invalid index returns error
- UUID not in list returns error
- Empty session list returns error

### Step 6: Implement Restore Handler (6.5.2.1)

**File**: `lib/jido_code/commands.ex`

```elixir
def execute_session({:resume, {:restore, target}}, _model) do
  # Full implementation with error handling
end
```

**Test**:
- Success case returns {:session_action, {:add_session, session}}
- All error cases return appropriate messages
- Rate limiting handled correctly

### Step 7: Update Help Text

**File**: `lib/jido_code/commands.ex`

```elixir
@help_text """
...
  /resume                  - List resumable sessions
  /resume <index|id>       - Resume a saved session
...
"""
```

**Test**: Verify help text includes /resume commands

### Step 8: Write Comprehensive Tests (6.5.1.4, 6.5.2.4, 6.5.3.2)

**File**: `test/jido_code/commands_test.exs`

Test cases:
1. Parse `/resume` → `{:session, {:resume, :list}}`
2. Parse `/resume 1` → `{:session, {:resume, {:restore, "1"}}}`
3. Parse `/resume <uuid>` → `{:session, {:resume, {:restore, "<uuid>"}}}`
4. Execute list with empty sessions
5. Execute list with multiple sessions
6. Execute restore with valid index
7. Execute restore with valid UUID
8. Execute restore with invalid index
9. Execute restore with UUID not in list
10. Execute restore with missing session file
11. Execute restore with deleted project path
12. Execute restore with session limit reached
13. Execute restore with project already open
14. Execute restore with rate limit exceeded
15. Format functions for various time ranges
16. Format functions with invalid timestamps

**Minimum**: 15 test cases

### Step 9: Integration Testing

**File**: `test/jido_code/integration_test.exs` (if applicable)

Test full flow:
1. Create session
2. Add messages
3. Close session
4. List resumable sessions (verify appears)
5. Resume session by index
6. Verify messages restored
7. Verify session active in registry

### Step 10: Update Documentation

**Files**:
- `CLAUDE.md` - Add /resume to command table
- Update help text in module documentation

## Testing Strategy

### Unit Tests

**Module**: `test/jido_code/commands_test.exs`

#### Parsing Tests

```elixir
describe "/resume command parsing" do
  test "parses /resume as list" do
    assert {:session, {:resume, :list}} = parse_and_execute("/resume", %{})
  end

  test "parses /resume with index" do
    assert {:session, {:resume, {:restore, "1"}}} =
      parse_and_execute("/resume 1", %{})
  end

  test "parses /resume with UUID" do
    uuid = "550e8400-e29b-41d4-a716-446655440000"
    assert {:session, {:resume, {:restore, ^uuid}}} =
      parse_and_execute("/resume #{uuid}", %{})
  end

  test "trims whitespace from target" do
    assert {:session, {:resume, {:restore, "1"}}} =
      parse_and_execute("/resume  1  ", %{})
  end
end
```

#### List Handler Tests

```elixir
describe "execute_session {:resume, :list}" do
  test "returns empty message when no sessions" do
    # Mock Persistence.list_resumable() to return []
    {:ok, message} = Commands.execute_session({:resume, :list}, %{})
    assert message =~ "No sessions to resume"
  end

  test "formats session list with index, name, path, time" do
    # Mock Persistence.list_resumable() to return test data
    {:ok, message} = Commands.execute_session({:resume, :list}, %{})
    assert message =~ "1. my-project"
    assert message =~ "closed"
    assert message =~ "Use /resume"
  end

  test "shows relative times correctly" do
    # Test various time ranges
  end
end
```

#### Restore Handler Tests

```elixir
describe "execute_session {:resume, {:restore, target}}" do
  test "resumes session by index" do
    # Setup: persisted session exists
    {:session_action, {:add_session, session}} =
      Commands.execute_session({:resume, {:restore, "1"}}, %{})
    assert session.id
  end

  test "resumes session by UUID" do
    # Setup: persisted session exists
    uuid = "550e8400-e29b-41d4-a716-446655440000"
    {:session_action, {:add_session, session}} =
      Commands.execute_session({:resume, {:restore, uuid}}, %{})
    assert session.id == uuid
  end

  test "returns error for invalid index" do
    {:error, message} = Commands.execute_session({:resume, {:restore, "99"}}, %{})
    assert message =~ "not found"
  end

  test "returns error for missing session file" do
    # Mock Persistence.resume() to return {:error, :not_found}
    {:error, message} = Commands.execute_session({:resume, {:restore, "1"}}, %{})
    assert message =~ "not found"
  end

  test "returns error for deleted project path" do
    # Mock Persistence.resume() to return {:error, :project_path_not_found}
    {:error, message} = Commands.execute_session({:resume, {:restore, "1"}}, %{})
    assert message =~ "no longer exists"
  end

  test "returns error for session limit" do
    # Mock Persistence.resume() to return {:error, :session_limit_reached}
    {:error, message} = Commands.execute_session({:resume, {:restore, "1"}}, %{})
    assert message =~ "Maximum 10 sessions"
  end

  test "returns error for project already open" do
    # Mock Persistence.resume() to return {:error, :project_already_open}
    {:error, message} = Commands.execute_session({:resume, {:restore, "1"}}, %{})
    assert message =~ "already open"
  end

  test "returns error for rate limit exceeded" do
    # Mock Persistence.resume() to return {:error, {:rate_limit_exceeded, 30}}
    {:error, message} = Commands.execute_session({:resume, {:restore, "1"}}, %{})
    assert message =~ "Too many"
    assert message =~ "30 seconds"
  end
end
```

#### Format Function Tests

```elixir
describe "format_resumable_list/1" do
  test "formats empty list with helpful message" do
    message = format_resumable_list([])
    assert message =~ "No sessions to resume"
    assert message =~ "closed"
  end

  test "formats single session" do
    sessions = [
      %{id: "abc", name: "test", project_path: "/tmp/test",
        closed_at: "2025-01-15T10:00:00Z"}
    ]
    message = format_resumable_list(sessions)
    assert message =~ "1. test"
    assert message =~ "/tmp/test"
  end

  test "formats multiple sessions with indices" do
    sessions = [
      %{id: "abc", name: "proj1", project_path: "/tmp/p1", closed_at: "..."},
      %{id: "def", name: "proj2", project_path: "/tmp/p2", closed_at: "..."}
    ]
    message = format_resumable_list(sessions)
    assert message =~ "1. proj1"
    assert message =~ "2. proj2"
  end

  test "truncates long paths" do
    sessions = [
      %{id: "abc", name: "test",
        project_path: "/very/long/path/that/exceeds/forty/characters/limit",
        closed_at: "..."}
    ]
    message = format_resumable_list(sessions)
    assert message =~ "..."
    assert String.length(message) < 200
  end
end

describe "format_ago/1" do
  test "formats < 1 minute as 'just now'" do
    now = DateTime.utc_now()
    iso = DateTime.to_iso8601(now)
    assert format_ago(iso) == "just now"
  end

  test "formats minutes" do
    dt = DateTime.add(DateTime.utc_now(), -120, :second)
    iso = DateTime.to_iso8601(dt)
    assert format_ago(iso) == "2 min ago"
  end

  test "formats hours" do
    dt = DateTime.add(DateTime.utc_now(), -7200, :second)
    iso = DateTime.to_iso8601(dt)
    assert format_ago(iso) == "2 hours ago"
  end

  test "formats yesterday" do
    dt = DateTime.add(DateTime.utc_now(), -86400, :second)
    iso = DateTime.to_iso8601(dt)
    assert format_ago(iso) == "yesterday"
  end

  test "formats days" do
    dt = DateTime.add(DateTime.utc_now(), -259200, :second)  # 3 days
    iso = DateTime.to_iso8601(dt)
    assert format_ago(iso) == "3 days ago"
  end

  test "formats absolute date for > 1 week" do
    dt = ~U[2025-01-01 10:00:00Z]
    iso = DateTime.to_iso8601(dt)
    assert format_ago(iso) == "2025-01-01"
  end

  test "handles invalid timestamps" do
    assert format_ago("invalid") == "unknown"
    assert format_ago(nil) == "unknown"
  end

  test "handles future timestamps" do
    dt = DateTime.add(DateTime.utc_now(), 3600, :second)
    iso = DateTime.to_iso8601(dt)
    assert format_ago(iso) == "just now"
  end
end

describe "resolve_resume_target/2" do
  setup do
    sessions = [
      %{id: "abc-123", name: "proj1"},
      %{id: "def-456", name: "proj2"},
      %{id: "ghi-789", name: "proj3"}
    ]
    {:ok, sessions: sessions}
  end

  test "resolves numeric index", %{sessions: sessions} do
    assert {:ok, "abc-123"} = resolve_resume_target("1", sessions)
    assert {:ok, "def-456"} = resolve_resume_target("2", sessions)
    assert {:ok, "ghi-789"} = resolve_resume_target("3", sessions)
  end

  test "resolves UUID", %{sessions: sessions} do
    assert {:ok, "abc-123"} = resolve_resume_target("abc-123", sessions)
    assert {:ok, "def-456"} = resolve_resume_target("def-456", sessions)
  end

  test "returns error for invalid index", %{sessions: sessions} do
    assert {:error, :invalid_index} = resolve_resume_target("0", sessions)
    assert {:error, :invalid_index} = resolve_resume_target("4", sessions)
    assert {:error, :invalid_index} = resolve_resume_target("99", sessions)
  end

  test "returns error for unknown UUID", %{sessions: sessions} do
    assert {:error, :not_found} = resolve_resume_target("xyz-000", sessions)
  end

  test "returns error for empty session list" do
    assert {:error, :no_resumable_sessions} = resolve_resume_target("1", [])
  end

  test "returns error for non-numeric non-UUID" do
    sessions = [%{id: "abc", name: "test"}]
    assert {:error, :not_found} = resolve_resume_target("invalid", sessions)
  end
end
```

### Integration Tests

**Module**: `test/jido_code/integration_test.exs` (if applicable)

```elixir
describe "resume command integration" do
  test "full resume flow" do
    # 1. Create session
    {:ok, session} = SessionSupervisor.create_session(project_path: "/tmp/test")

    # 2. Add messages
    State.append_message(session.id, %{
      id: "msg1", role: :user, content: "Hello", timestamp: DateTime.utc_now()
    })

    # 3. Close session (persists)
    :ok = SessionSupervisor.stop_session(session.id)

    # 4. List resumable (verify appears)
    sessions = Persistence.list_resumable()
    assert Enum.any?(sessions, &(&1.id == session.id))

    # 5. Resume via command
    {:session_action, {:add_session, resumed}} =
      Commands.execute_session({:resume, {:restore, "1"}}, %{})

    # 6. Verify messages restored
    {:ok, state} = State.get_state(resumed.id)
    assert length(state.messages) == 1

    # 7. Verify session active
    {:ok, _pid} = SessionRegistry.lookup(session.id)
  end
end
```

### Manual Testing Checklist

1. **List empty sessions**: Start fresh, run `/resume` → See helpful message
2. **List with sessions**: Close a session, run `/resume` → See formatted list
3. **Resume by index**: `/resume 1` → Session restored and active
4. **Resume by UUID**: `/resume <full-uuid>` → Session restored
5. **Invalid index**: `/resume 99` → Clear error message
6. **Deleted project**: Move project folder, `/resume 1` → Path error
7. **Session limit**: Open 10 sessions, `/resume 1` → Limit error
8. **Already open**: Resume active session's project → Already open error
9. **Rate limiting**: Rapidly retry failed resume → Rate limit message
10. **Time formatting**: Close sessions at different times, verify formatting

## Dependencies

### Completed Tasks

These must be completed before implementing this task:

- **Task 6.2.1**: Save persisted session schema - COMPLETE
- **Task 6.2.2**: Auto-save on close - COMPLETE
- **Task 6.3.1**: List persisted sessions - COMPLETE
- **Task 6.3.2**: Filter active sessions from resumable list - COMPLETE
- **Task 6.4.1**: Load persisted session from disk - COMPLETE
- **Task 6.4.2**: Resume persisted session - COMPLETE
- **Task 6.4.3**: Security enhancements (rate limiting, TOCTOU) - COMPLETE

### External Dependencies

- `JidoCode.Session.Persistence` - list_resumable/0, resume/1
- `JidoCode.SessionSupervisor` - Session registration and limits
- `JidoCode.Session.State` - State access for verification
- `JidoCode.RateLimit` - Rate limiting for resume attempts

### Internal Dependencies

Within Commands module:
- `truncate_path/1` - Existing path formatting function
- `numeric_target?/1` - Existing numeric check function
- Session command handling pattern - Existing infrastructure

## Future Enhancements

1. **Fuzzy Search**: `/resume proj` matches "my-project" by name
2. **Resume Last**: `/resume last` resumes most recently closed session
3. **Resume All**: Restore multiple sessions in batch
4. **Resume Preview**: Show preview of conversation before confirming
5. **Resume Options**: `/resume 1 --skip-history` to resume without messages
6. **Resume Analytics**: Track which sessions are resumed most often
7. **Auto-Complete**: Tab completion for session names in shell
8. **Resume Confirmation**: Ask user to confirm if project path changed
9. **Resume Notifications**: PubSub events for resume success/failure
10. **Resume Filters**: `/resume --since=today` to filter by closed date

## Notes

### Design Decisions

1. **Why route through session command handler?**
   - Provides consistency with other session commands
   - Reuses TUI session action handling
   - Simplifies testing and maintenance

2. **Why index AND UUID support?**
   - Index is faster for users (just type "1")
   - UUID provides unambiguous reference
   - Matches existing `/session switch` pattern

3. **Why show relative times?**
   - More intuitive than absolute timestamps
   - Helps users identify recent vs old sessions
   - Common pattern in modern UIs (GitHub, Slack, etc.)

4. **Why separate list and restore modes?**
   - Users often want to see options before deciding
   - Prevents accidental resume of wrong session
   - Provides clear workflow: list → inspect → resume

5. **Why truncate paths?**
   - Long paths break terminal formatting
   - Home directory abbreviation (~/...) is conventional
   - Matches existing session list formatting

### Security Considerations

1. **Rate Limiting**: Task 6.4.3 added rate limiting to prevent rapid retry attacks
2. **Path Validation**: Persistence.resume() validates paths before restoring
3. **UUID Validation**: session_file() validates UUID format to prevent path traversal
4. **TOCTOU Protection**: Task 6.4.3 added re-validation after session start
5. **Error Leakage**: Generic error messages don't expose internal paths

### Performance Considerations

1. **List Performance**: list_resumable() reads all .json files - acceptable for < 100 sessions
2. **Format Performance**: String formatting is fast, no optimization needed
3. **Resume Performance**: Full session restoration takes ~100ms, acceptable for user interaction

### Edge Cases Handled

1. Empty resumable list → Helpful message
2. Invalid index (0, negative, > length) → Clear error
3. UUID not in list → Not found error
4. Malformed timestamp → Show "unknown"
5. Very long paths → Truncated to 40 chars
6. Future timestamps → Show "just now"
7. Concurrent resume → One succeeds, other gets "already open"
8. Session already active → Filtered from list automatically

# Feature: WS-1.3.4 Session Creation Convenience

## Problem Statement

Currently, creating and starting a session requires two steps:
1. `Session.new(opts)` to create the session struct
2. `SessionSupervisor.start_session(session)` to start the processes

We need a convenience function that combines these steps into a single call for simpler API usage.

## Solution Overview

Add `create_session/1` to `JidoCode.SessionSupervisor` that:
1. Creates a new Session struct from options
2. Starts the session under the supervisor
3. Returns the session on success
4. Handles partial failures gracefully (no cleanup needed since Session.new doesn't have side effects)

### Key Decisions

1. **Return Session, not PID**: Users typically need the session struct (for ID, name, etc.) more than the supervisor pid
2. **No explicit cleanup needed**: `Session.new/1` has no side effects, and `start_session/1` already handles its own cleanup on failure
3. **Pass-through options**: Accept same options as `Session.new/1` plus optional `:supervisor_module` for testing

## Implementation Plan

### Step 1: Implement create_session/1

```elixir
@doc """
Creates and starts a new session in one step.

Convenience function that combines `Session.new/1` and `start_session/1`.
"""
@spec create_session(keyword()) :: {:ok, Session.t()} | {:error, term()}
def create_session(opts) do
  supervisor_module = Keyword.get(opts, :supervisor_module, JidoCode.Session.Supervisor)
  session_opts = Keyword.delete(opts, :supervisor_module)

  with {:ok, session} <- Session.new(session_opts),
       {:ok, _pid} <- start_session(session, supervisor_module: supervisor_module) do
    {:ok, session}
  end
end
```

### Step 2: Write Unit Tests

Tests for:
- create_session/1 creates and starts session
- create_session/1 returns session struct (not pid)
- create_session/1 registers in SessionRegistry
- create_session/1 fails for invalid path
- create_session/1 fails when session limit reached
- create_session/1 fails for duplicate path

## Success Criteria

- [x] create_session/1 implemented with documentation
- [x] Accepts same options as Session.new/1
- [x] Returns {:ok, session} on success
- [x] Propagates errors from Session.new/1 and start_session/1
- [x] All tests pass

## API

```elixir
# Create and start a session
{:ok, session} = SessionSupervisor.create_session(project_path: "/tmp/project")

# With custom name
{:ok, session} = SessionSupervisor.create_session(
  project_path: "/tmp/project",
  name: "my-project"
)

# Error cases
{:error, :path_not_found} = SessionSupervisor.create_session(project_path: "/nonexistent")
{:error, :session_limit_reached} = SessionSupervisor.create_session(project_path: "/tmp/project")
```

## Current Status

**Status**: Complete

**What works**:
- create_session/1 implemented with documentation
- Accepts same options as Session.new/1 plus :supervisor_module
- Returns {:ok, session} on success
- Propagates all errors correctly
- All 41 SessionSupervisor tests passing

**Tests**: 210 total session tests (95 + 74 + 41)

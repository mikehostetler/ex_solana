# Feature: WS-1.3.2 Session Process Management

## Problem Statement

We need functions to start and stop session processes through the SessionSupervisor. These functions will:
- Register sessions in SessionRegistry before starting child processes
- Start per-session supervision trees as children of SessionSupervisor
- Stop sessions and clean up their registry entries
- Handle errors gracefully (session limit, duplicates)

## Solution Overview

Add `start_session/1` and `stop_session/1` functions to `JidoCode.SessionSupervisor`:

1. **start_session/1**: Registers session in SessionRegistry, then starts `Session.Supervisor` as child
2. **stop_session/1**: Terminates child process, then unregisters from SessionRegistry

### Key Decisions

1. **Registration Before Start**: Register in SessionRegistry first so if process start fails, we can clean up
2. **Cleanup on Failure**: If DynamicSupervisor.start_child fails, unregister from SessionRegistry
3. **Registry-Based Lookup**: Use Elixir Registry with via tuples for process lookup (implemented in Task 1.3.3)
4. **Test Strategy**: Create a test-only stub supervisor since Session.Supervisor (Task 1.4.1) doesn't exist yet

### Dependencies

- `JidoCode.Session.Supervisor` (Task 1.4.1) - The actual per-session supervisor
- For testing, we'll create a stub module that simulates the expected behavior

## Implementation Plan

### Step 1: Add start_session/1 to SessionSupervisor

```elixir
def start_session(%Session{} = session) do
  with {:ok, session} <- SessionRegistry.register(session) do
    spec = {JidoCode.Session.Supervisor, session: session}

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} -> {:ok, pid}
      {:ok, pid, _info} -> {:ok, pid}
      {:error, reason} ->
        # Cleanup on failure
        SessionRegistry.unregister(session.id)
        {:error, reason}
    end
  end
end
```

### Step 2: Add stop_session/1 to SessionSupervisor

```elixir
def stop_session(session_id) do
  with {:ok, pid} <- find_session_pid(session_id),
       :ok <- DynamicSupervisor.terminate_child(__MODULE__, pid) do
    SessionRegistry.unregister(session_id)
    :ok
  end
end
```

### Step 3: Add find_session_pid/1 helper (stub for Task 1.3.3)

```elixir
defp find_session_pid(session_id) do
  case Registry.lookup(JidoCode.SessionRegistry, {:session, session_id}) do
    [{pid, _}] -> {:ok, pid}
    [] -> {:error, :not_found}
  end
end
```

Note: This will be refactored in Task 1.3.3 to be a public function.

### Step 4: Create Test Stub Module

Create `test/support/session_supervisor_stub.ex` with a simple GenServer that:
- Accepts `session: session` option
- Registers via tuple with session ID
- Can be started/stopped for testing

### Step 5: Write Unit Tests

Tests for:
- start_session/1 succeeds and registers in SessionRegistry
- start_session/1 returns pid
- start_session/1 fails when session limit reached
- start_session/1 fails for duplicate session ID
- start_session/1 fails for duplicate project path
- stop_session/1 terminates child
- stop_session/1 unregisters from SessionRegistry
- stop_session/1 handles non-existent session

## Success Criteria

- [x] start_session/1 implemented with SessionRegistry registration
- [x] start_session/1 cleans up on child start failure
- [x] stop_session/1 implemented with SessionRegistry cleanup
- [x] find_session_pid/1 private helper implemented
- [x] All tests pass

## API

```elixir
# Start a session (returns pid of per-session supervisor)
{:ok, pid} = SessionSupervisor.start_session(session)

# Stop a session by ID
:ok = SessionSupervisor.stop_session("session-id")

# Error cases
{:error, :session_limit_reached}
{:error, :session_exists}
{:error, :project_already_open}
{:error, :not_found}
```

## Notes

- Session.Supervisor (Task 1.4.1) doesn't exist yet, so tests use a stub
- find_session_pid/1 is private here; will become public in Task 1.3.3
- Registry lookup uses JidoCode.SessionRegistry name for sessions (different from AgentRegistry)

## Current Status

**Status**: Complete

**What works**:
- start_session/1 with SessionRegistry integration
- stop_session/1 with cleanup
- find_session_pid/1 private helper
- Test stub for Session.Supervisor
- All 22 tests passing

**Tests**: 191 total session tests (95 + 74 + 22)

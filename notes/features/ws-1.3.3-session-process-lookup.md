# Feature: WS-1.3.3 Session Process Lookup

## Problem Statement

We need public functions to find and query session processes. Task 1.3.2 implemented a private `find_session_pid/1` helper. This task makes it public and adds additional lookup functions for querying session process state.

## Solution Overview

Add three public functions to `JidoCode.SessionSupervisor`:

1. **find_session_pid/1** - Find a session's supervisor pid by session ID
2. **list_session_pids/0** - List all running session supervisor pids
3. **session_running?/1** - Check if a session's processes are alive

### Key Decisions

1. **Registry-based lookup**: Use `SessionProcessRegistry` for O(1) pid lookup
2. **DynamicSupervisor for listing**: Use `which_children/1` to get all child pids
3. **Combine checks for running**: Check both Registry and process liveness

## Implementation Plan

### Step 1: Make find_session_pid/1 Public

Change from `defp` to `def` and add documentation:

```elixir
@doc """
Finds the pid of a session's supervisor by session ID.
"""
@spec find_session_pid(String.t()) :: {:ok, pid()} | {:error, :not_found}
def find_session_pid(session_id) do
  case Registry.lookup(@registry, {:session, session_id}) do
    [{pid, _}] -> {:ok, pid}
    [] -> {:error, :not_found}
  end
end
```

### Step 2: Implement list_session_pids/0

```elixir
@doc """
Returns a list of all running session supervisor pids.
"""
@spec list_session_pids() :: [pid()]
def list_session_pids do
  __MODULE__
  |> DynamicSupervisor.which_children()
  |> Enum.map(fn {_, pid, _, _} -> pid end)
  |> Enum.filter(&is_pid/1)
end
```

### Step 3: Implement session_running?/1

```elixir
@doc """
Checks if a session's processes are running.
"""
@spec session_running?(String.t()) :: boolean()
def session_running?(session_id) do
  case find_session_pid(session_id) do
    {:ok, pid} -> Process.alive?(pid)
    {:error, :not_found} -> false
  end
end
```

### Step 4: Write Unit Tests

Tests for:
- find_session_pid/1 finds registered session
- find_session_pid/1 returns error for unknown session
- list_session_pids/0 returns empty list initially
- list_session_pids/0 returns pids after starting sessions
- session_running?/1 returns true for running session
- session_running?/1 returns false for stopped session
- session_running?/1 returns false for unknown session

## Success Criteria

- [x] find_session_pid/1 is public with documentation
- [x] list_session_pids/0 implemented
- [x] session_running?/1 implemented
- [x] All tests pass

## API

```elixir
# Find session pid by ID
{:ok, pid} = SessionSupervisor.find_session_pid("session-id")
{:error, :not_found} = SessionSupervisor.find_session_pid("unknown")

# List all session pids
pids = SessionSupervisor.list_session_pids()

# Check if session is running
true = SessionSupervisor.session_running?("session-id")
false = SessionSupervisor.session_running?("unknown")
```

## Current Status

**Status**: Complete

**What works**:
- find_session_pid/1 public with documentation
- list_session_pids/0 implemented
- session_running?/1 implemented
- All 31 SessionSupervisor tests passing

**Tests**: 200 total session tests (95 + 74 + 31)

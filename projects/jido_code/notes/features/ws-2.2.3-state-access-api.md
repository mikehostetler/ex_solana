# Feature: WS-2.2.3 State Access API

## Problem Statement

Task 2.2.3 requires implementing client functions for reading Session.State. These functions allow other modules to access the conversation state, messages, reasoning steps, and todos without direct GenServer calls.

## Solution Overview

Add client functions that use ProcessRegistry to look up the State process by session_id and return the requested data. Follow the same pattern as Session.Manager's `call_manager/3` helper.

### Key Decisions

- Use `call_state/2` helper similar to Manager's `call_manager/3`
- Return `{:ok, data}` or `{:error, :not_found}` for consistency
- Add corresponding `handle_call` callbacks for each accessor

## Technical Details

### New Client Functions

```elixir
def get_state(session_id) do
  call_state(session_id, :get_state)
end

def get_messages(session_id) do
  call_state(session_id, :get_messages)
end

def get_reasoning_steps(session_id) do
  call_state(session_id, :get_reasoning_steps)
end

def get_todos(session_id) do
  call_state(session_id, :get_todos)
end

defp call_state(session_id, message) do
  case ProcessRegistry.lookup(:state, session_id) do
    {:ok, pid} -> GenServer.call(pid, message)
    {:error, :not_found} -> {:error, :not_found}
  end
end
```

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_code/session/state.ex` | Add client functions and handle_call callbacks |
| `test/jido_code/session/state_test.exs` | Add tests for state access |

## Implementation Plan

### Step 1: Add call_state helper
- [x] Add `call_state/2` private helper function

### Step 2: Implement get_state/1
- [x] Add `get_state/1` client function (by session_id, not pid)
- [x] Add `handle_call(:get_state, _, state)` callback

### Step 3: Implement get_messages/1
- [x] Add `get_messages/1` client function
- [x] Add `handle_call(:get_messages, _, state)` callback

### Step 4: Implement get_reasoning_steps/1
- [x] Add `get_reasoning_steps/1` client function
- [x] Add `handle_call(:get_reasoning_steps, _, state)` callback

### Step 5: Implement get_todos/1
- [x] Add `get_todos/1` client function
- [x] Add `handle_call(:get_todos, _, state)` callback

### Step 6: Write Unit Tests
- [x] Test `get_state/1` returns full state
- [x] Test `get_state/1` returns :not_found for unknown session
- [x] Test `get_messages/1` returns messages list
- [x] Test `get_messages/1` returns :not_found for unknown session
- [x] Test `get_reasoning_steps/1` returns reasoning steps list
- [x] Test `get_reasoning_steps/1` returns :not_found for unknown session
- [x] Test `get_todos/1` returns todos list
- [x] Test `get_todos/1` returns :not_found for unknown session

## Success Criteria

- [x] All client functions implemented
- [x] All handle_call callbacks implemented
- [x] All tests pass
- [x] Existing tests still pass

## Current Status

**Status**: Complete

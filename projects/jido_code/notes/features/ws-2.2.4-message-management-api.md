# Feature: WS-2.2.4 Message Management API

## Problem Statement

Task 2.2.4 requires implementing functions for managing conversation messages in Session.State. These functions allow adding messages to the conversation history and clearing the history when needed.

## Solution Overview

Add client functions that use the existing `call_state/2` helper to manage messages. Follow the same pattern established in Task 2.2.3 for state access.

### Key Decisions

- Use `call_state/2` helper (already implemented)
- Return `{:ok, state}` after append for consistency with mutations
- Return `{:ok, []}` after clear to confirm the action
- Messages are appended to end of list (chronological order)

## Technical Details

### New Client Functions

```elixir
@doc """
Appends a message to the conversation history.
"""
@spec append_message(String.t(), message()) :: {:ok, state()} | {:error, :not_found}
def append_message(session_id, message) do
  call_state(session_id, {:append_message, message})
end

@doc """
Clears all messages from the conversation history.
"""
@spec clear_messages(String.t()) :: {:ok, []} | {:error, :not_found}
def clear_messages(session_id) do
  call_state(session_id, :clear_messages)
end
```

### New Handle Callbacks

```elixir
@impl true
def handle_call({:append_message, message}, _from, state) do
  new_state = %{state | messages: state.messages ++ [message]}
  {:reply, {:ok, new_state}, new_state}
end

@impl true
def handle_call(:clear_messages, _from, state) do
  new_state = %{state | messages: []}
  {:reply, {:ok, []}, new_state}
end
```

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_code/session/state.ex` | Add client functions and handle_call callbacks |
| `test/jido_code/session/state_test.exs` | Add tests for message management |

## Implementation Plan

### Step 1: Implement append_message/2
- [x] Add `append_message/2` client function
- [x] Add `handle_call({:append_message, message}, _, state)` callback
- [x] Append message to end of messages list

### Step 2: Implement clear_messages/1
- [x] Add `clear_messages/1` client function
- [x] Add `handle_call(:clear_messages, _, state)` callback
- [x] Return empty list after clearing

### Step 3: Write Unit Tests
- [x] Test `append_message/2` adds message to empty list
- [x] Test `append_message/2` adds message to existing list (maintains order)
- [x] Test `append_message/2` returns :not_found for unknown session
- [x] Test `clear_messages/1` clears all messages
- [x] Test `clear_messages/1` returns :not_found for unknown session

## Success Criteria

- [x] All client functions implemented
- [x] All handle_call callbacks implemented
- [x] All tests pass
- [x] Existing tests still pass

## Current Status

**Status**: Complete

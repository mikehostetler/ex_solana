# Feature: WS-2.2.5 Streaming API

## Problem Statement

Task 2.2.5 requires implementing functions for streaming message updates in Session.State. These functions manage the lifecycle of streaming responses from the LLM: starting, updating with chunks, and finalizing into a complete message.

## Solution Overview

Add streaming lifecycle functions that manage the `is_streaming`, `streaming_message`, and `streaming_message_id` state fields. Use `cast` for chunk updates (fire-and-forget for performance) and `call` for start/end (synchronous confirmation).

### Key Decisions

- Use `call` for `start_streaming/2` to confirm streaming started
- Use `cast` for `update_streaming/2` for high-throughput chunk handling
- Use `call` for `end_streaming/1` to return the finalized message
- Store `streaming_message_id` to track which message is being streamed
- On end, create a proper message and append to messages list

## Technical Details

### New Client Functions

```elixir
@doc """
Starts streaming mode for a new message.
"""
@spec start_streaming(String.t(), String.t()) :: {:ok, state()} | {:error, :not_found}
def start_streaming(session_id, message_id) do
  call_state(session_id, {:start_streaming, message_id})
end

@doc """
Appends a chunk to the streaming message (async for performance).
"""
@spec update_streaming(String.t(), String.t()) :: :ok
def update_streaming(session_id, chunk) do
  cast_state(session_id, {:streaming_chunk, chunk})
end

@doc """
Ends streaming and finalizes the message.
"""
@spec end_streaming(String.t()) :: {:ok, message()} | {:error, :not_found | :not_streaming}
def end_streaming(session_id) do
  call_state(session_id, :end_streaming)
end
```

### New Helper for Cast

```elixir
@spec cast_state(String.t(), term()) :: :ok
defp cast_state(session_id, message) do
  case ProcessRegistry.lookup(:state, session_id) do
    {:ok, pid} -> GenServer.cast(pid, message)
    {:error, :not_found} -> :ok  # Silently ignore for cast
  end
end
```

### New Handle Callbacks

```elixir
@impl true
def handle_call({:start_streaming, message_id}, _from, state) do
  new_state = %{state |
    is_streaming: true,
    streaming_message: "",
    streaming_message_id: message_id
  }
  {:reply, {:ok, new_state}, new_state}
end

@impl true
def handle_cast({:streaming_chunk, chunk}, state) do
  if state.is_streaming do
    new_state = %{state | streaming_message: state.streaming_message <> chunk}
    {:noreply, new_state}
  else
    {:noreply, state}
  end
end

@impl true
def handle_call(:end_streaming, _from, state) do
  if state.is_streaming do
    message = %{
      id: state.streaming_message_id,
      role: :assistant,
      content: state.streaming_message,
      timestamp: DateTime.utc_now()
    }
    new_state = %{state |
      messages: state.messages ++ [message],
      is_streaming: false,
      streaming_message: nil,
      streaming_message_id: nil
    }
    {:reply, {:ok, message}, new_state}
  else
    {:reply, {:error, :not_streaming}, state}
  end
end
```

### State Structure Update

Need to add `streaming_message_id` to the state structure in `init/1`.

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_code/session/state.ex` | Add client functions, cast_state helper, handle callbacks, update init |
| `test/jido_code/session/state_test.exs` | Add tests for streaming lifecycle |

## Implementation Plan

### Step 1: Update State Structure
- [x] Add `streaming_message_id: nil` to init state

### Step 2: Add cast_state helper
- [x] Add `cast_state/2` private helper function

### Step 3: Implement start_streaming/2
- [x] Add `start_streaming/2` client function
- [x] Add `handle_call({:start_streaming, message_id}, _, state)` callback
- [x] Set `is_streaming: true`, `streaming_message: ""`, `streaming_message_id: message_id`

### Step 4: Implement update_streaming/2
- [x] Add `update_streaming/2` client function (uses cast)
- [x] Add `handle_cast({:streaming_chunk, chunk}, state)` callback
- [x] Append chunk to streaming_message if streaming

### Step 5: Implement end_streaming/1
- [x] Add `end_streaming/1` client function
- [x] Add `handle_call(:end_streaming, _, state)` callback
- [x] Create message, append to messages, reset streaming state
- [x] Return error if not streaming

### Step 6: Write Unit Tests
- [x] Test `start_streaming/2` sets streaming state
- [x] Test `start_streaming/2` returns :not_found for unknown session
- [x] Test `update_streaming/2` appends chunks
- [x] Test `update_streaming/2` ignores chunks when not streaming
- [x] Test `end_streaming/1` creates message and resets state
- [x] Test `end_streaming/1` returns :not_streaming error when not streaming
- [x] Test `end_streaming/1` returns :not_found for unknown session
- [x] Test full streaming lifecycle (start -> update -> end)

## Success Criteria

- [x] All client functions implemented
- [x] All handle callbacks implemented
- [x] State structure updated with streaming_message_id
- [x] All tests pass
- [x] Existing tests still pass

## Current Status

**Status**: Complete

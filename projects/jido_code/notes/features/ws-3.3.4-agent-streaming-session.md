# WS-3.3.4 Agent Streaming with Session

**Branch:** `feature/ws-3.3.4-agent-streaming-session`
**Date:** 2025-12-06
**Status:** Complete

## Overview

Update LLMAgent streaming to route through Session.State. This ensures streaming content is persisted in the session state while also being broadcast via PubSub for TUI consumption.

## Requirements from Plan

From `notes/planning/work-session/phase-03.md`:

- [ ] 3.3.4.1 Update stream chunk handling to update Session.State
- [ ] 3.3.4.2 Update stream end to finalize in Session.State
- [ ] 3.3.4.3 Write unit tests for streaming integration

## Current State Analysis

### Session.State Streaming API (already exists)
```elixir
# Start streaming - creates new message with id
State.start_streaming(session_id, message_id)

# Update with chunks (async cast for performance)
State.update_streaming(session_id, chunk)

# End streaming - finalizes message and adds to history
State.end_streaming(session_id)
```

### LLMAgent Streaming (current)
The `chat_stream/3` function:
1. Calls `handle_cast({:chat_stream, message, timeout}, state)`
2. Spawns a Task to handle streaming
3. Calls `do_chat_stream_with_timeout/4` → `do_chat_stream/3` → `execute_stream/3`
4. Broadcasts chunks via PubSub: `{:stream_chunk, content}`
5. Broadcasts completion: `{:stream_end, full_content}`

### Gap
LLMAgent broadcasts to PubSub but doesn't update Session.State. The TUI receives events but the session has no record of the streaming content until it completes.

## Implementation Plan

### Task 1: Update broadcast_stream_chunk to also update Session.State
**Status:** Complete

Add Session.State.update_streaming call in the streaming flow:

```elixir
defp broadcast_stream_chunk(topic, chunk, session_id) do
  # Update Session.State with chunk
  Session.State.update_streaming(session_id, chunk)
  # Also broadcast for TUI
  Phoenix.PubSub.broadcast(@pubsub, topic, {:stream_chunk, chunk})
end
```

### Task 2: Update execute_stream to start Session.State streaming
**Status:** Complete

Before processing stream, call start_streaming:

```elixir
defp execute_stream(model, message, topic, session_id) do
  message_id = generate_message_id()

  # Start streaming in Session.State
  Session.State.start_streaming(session_id, message_id)

  # ... existing streaming code ...
end
```

### Task 3: Update broadcast_stream_end to finalize Session.State
**Status:** Complete

When stream completes, finalize in Session.State:

```elixir
defp broadcast_stream_end(topic, full_content, session_id) do
  # Finalize message in Session.State
  Session.State.end_streaming(session_id)
  # Also broadcast for TUI
  Phoenix.PubSub.broadcast(@pubsub, topic, {:stream_end, full_content})
end
```

### Task 4: Pass session_id through streaming call chain
**Status:** Complete

Need to thread session_id through:
- `handle_cast({:chat_stream, ...}, state)` → get session_id from state
- `do_chat_stream_with_timeout(config, message, topic, timeout, session_id)`
- `do_chat_stream(config, message, topic, session_id)`
- `execute_stream(model, message, topic, session_id)`
- `process_stream(stream, topic, session_id)`
- `broadcast_stream_chunk(topic, chunk, session_id)`
- `broadcast_stream_end(topic, full_content, session_id)`

### Task 5: Handle session_id not being a proper session
**Status:** Complete

When agent is started without a session (session_id is PID string), skip Session.State updates but still broadcast via PubSub.

### Task 6: Write Unit Tests
**Status:** Complete

Tests to add:
- Stream chunk updates Session.State
- Stream end finalizes message in Session.State
- Streaming works when session_id is PID string (graceful degradation)
- Messages appear in Session.State.get_messages after streaming

## Files to Modify

- `lib/jido_code/agents/llm_agent.ex` - Update streaming functions
- `test/jido_code/agents/llm_agent_test.exs` - Add streaming integration tests

## Completion Checklist

- [x] Task 1: Update broadcast_stream_chunk
- [x] Task 2: Update execute_stream to start streaming
- [x] Task 3: Update broadcast_stream_end
- [x] Task 4: Pass session_id through call chain
- [x] Task 5: Handle non-session session_id
- [x] Task 6: Write unit tests
- [x] Run tests (44 tests, 0 failures)
- [x] Update phase plan
- [x] Write summary

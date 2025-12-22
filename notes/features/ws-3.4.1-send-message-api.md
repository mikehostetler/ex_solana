# WS-3.4.1 Send Message API

**Branch:** `feature/ws-3.4.1-send-message-api`
**Date:** 2025-12-06
**Status:** Complete

## Overview

Create a high-level API for TUI to send messages to session agents. This provides a clean abstraction layer between the TUI and the underlying LLMAgent, handling session lookups and error cases.

## Requirements from Plan

From `notes/planning/work-session/phase-03.md`:

- [ ] 3.4.1.1 Create `lib/jido_code/session/agent_api.ex` module
- [ ] 3.4.1.2 Implement `send_message/2`
- [ ] 3.4.1.3 Implement `send_message_stream/2` for streaming responses
- [ ] 3.4.1.4 Handle agent not found errors
- [ ] 3.4.1.5 Write unit tests for message API

## Current State Analysis

### Existing APIs
- `Session.Supervisor.get_agent/1` - Returns `{:ok, pid}` or `{:error, :not_found}`
- `LLMAgent.chat/3` - Synchronous chat with options
- `LLMAgent.chat_stream/3` - Async streaming chat

### Gap
No unified API exists to send messages to a session's agent. TUI would need to:
1. Look up the agent via `Session.Supervisor.get_agent/1`
2. Handle `:not_found` error
3. Call `LLMAgent.chat/3` or `chat_stream/3`

This task creates a clean abstraction.

## Implementation Plan

### Task 1: Create agent_api.ex Module
**Status:** Pending

Create `lib/jido_code/session/agent_api.ex` with module structure:

```elixir
defmodule JidoCode.Session.AgentAPI do
  @moduledoc """
  High-level API for interacting with session agents.

  This module provides a clean abstraction for the TUI to communicate
  with session agents without needing to handle agent lookups directly.
  """

  alias JidoCode.Agents.LLMAgent
  alias JidoCode.Session.Supervisor, as: SessionSupervisor
end
```

### Task 2: Implement send_message/2
**Status:** Pending

Synchronous message sending:

```elixir
@doc """
Sends a message to the session's agent and waits for a response.

## Parameters

- `session_id` - The session identifier
- `message` - The message to send

## Returns

- `{:ok, response}` - Success with agent response
- `{:error, :agent_not_found}` - Session has no agent
- `{:error, reason}` - Other error from agent
"""
@spec send_message(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
def send_message(session_id, message) when is_binary(session_id) and is_binary(message) do
  with {:ok, agent_pid} <- get_agent(session_id) do
    LLMAgent.chat(agent_pid, message)
  end
end
```

### Task 3: Implement send_message_stream/2
**Status:** Pending

Async streaming message:

```elixir
@doc """
Sends a message to the session's agent for streaming response.

The response is streamed via PubSub to the session topic.
Subscribe to `JidoCode.PubSubTopics.llm_stream(session_id)` to receive:
- `{:stream_chunk, content}` - Content chunks
- `{:stream_end, full_content}` - Stream completion
- `{:stream_error, reason}` - Stream error

## Parameters

- `session_id` - The session identifier
- `message` - The message to send
- `opts` - Options (timeout)

## Returns

- `:ok` - Message sent for streaming
- `{:error, :agent_not_found}` - Session has no agent
"""
@spec send_message_stream(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
def send_message_stream(session_id, message, opts \\ [])
    when is_binary(session_id) and is_binary(message) do
  with {:ok, agent_pid} <- get_agent(session_id) do
    LLMAgent.chat_stream(agent_pid, message, opts)
  end
end
```

### Task 4: Private Helper for Agent Lookup
**Status:** Pending

Wrap agent lookup with consistent error handling:

```elixir
defp get_agent(session_id) do
  case SessionSupervisor.get_agent(session_id) do
    {:ok, pid} -> {:ok, pid}
    {:error, :not_found} -> {:error, :agent_not_found}
    {:error, reason} -> {:error, reason}
  end
end
```

### Task 5: Write Unit Tests
**Status:** Pending

Tests to add in `test/jido_code/session/agent_api_test.exs`:

1. `send_message/2` sends to correct agent and returns response
2. `send_message/2` returns `{:error, :agent_not_found}` when agent missing
3. `send_message/2` validates message is binary
4. `send_message_stream/2` initiates streaming to correct agent
5. `send_message_stream/2` returns `{:error, :agent_not_found}` when agent missing
6. `send_message_stream/2` accepts timeout option

## Files to Create/Modify

- `lib/jido_code/session/agent_api.ex` - New module
- `test/jido_code/session/agent_api_test.exs` - New test file
- `notes/planning/work-session/phase-03.md` - Mark task complete

## Completion Checklist

- [x] Task 1: Create agent_api.ex module
- [x] Task 2: Implement send_message/3
- [x] Task 3: Implement send_message_stream/3
- [x] Task 4: Add private helper for agent lookup
- [x] Task 5: Write unit tests (10 new tests)
- [x] Run tests (175 session tests, 0 failures)
- [x] Update phase plan
- [x] Write summary

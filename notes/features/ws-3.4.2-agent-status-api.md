# WS-3.4.2 Agent Status API

**Branch:** `feature/ws-3.4.2-agent-status-api`
**Date:** 2025-12-06
**Status:** Complete

## Overview

Create API for checking agent status. This extends AgentAPI with status-related functions that allow the TUI to check if an agent is ready, processing, or in an error state.

## Requirements from Plan

From `notes/planning/work-session/phase-03.md`:

- [ ] 3.4.2.1 Implement `get_status/1` returning agent status
- [ ] 3.4.2.2 Implement `is_processing?/1` for quick status check
- [ ] 3.4.2.3 Write unit tests for status API

## Current State Analysis

### LLMAgent State Structure
```elixir
%{
  ai_pid: pid(),           # The Jido.AI.Agent process
  config: map(),           # Provider, model, temperature, max_tokens
  session_id: String.t(),  # Session identifier
  topic: String.t()        # PubSub topic
}
```

### Existing Functions
- `LLMAgent.get_config/1` - Returns the config map
- `LLMAgent.get_topic/1` - Returns session_id and topic

### Gap
No `get_status/1` function exists in LLMAgent. Need to add it.

## Implementation Plan

### Task 1: Add get_status/1 to LLMAgent
**Status:** Pending

Add a function to return agent status:

```elixir
@doc """
Returns the current status of the agent.

## Returns

A map containing:
- `:ready` - Agent is ready to process messages
- `:config` - Current configuration
- `:session_id` - Session identifier
- `:topic` - PubSub topic
"""
@spec get_status(GenServer.server()) :: {:ok, map()} | {:error, term()}
def get_status(pid) do
  GenServer.call(pid, :get_status)
end

# In handle_call:
@impl true
def handle_call(:get_status, _from, state) do
  status = %{
    ready: Process.alive?(state.ai_pid),
    config: state.config,
    session_id: state.session_id,
    topic: state.topic
  }
  {:reply, {:ok, status}, state}
end
```

### Task 2: Add get_status/1 to AgentAPI
**Status:** Pending

```elixir
@doc """
Gets the status of the session's agent.

## Returns

- `{:ok, status}` - Agent status map
- `{:error, :agent_not_found}` - Session has no agent
"""
@spec get_status(String.t()) :: {:ok, map()} | {:error, term()}
def get_status(session_id) when is_binary(session_id) do
  with {:ok, agent_pid} <- get_agent(session_id) do
    LLMAgent.get_status(agent_pid)
  end
end
```

### Task 3: Add is_processing?/1 to AgentAPI
**Status:** Pending

Quick boolean check if agent is busy:

```elixir
@doc """
Checks if the session's agent is currently processing a request.

Note: Currently always returns false since LLMAgent handles requests
synchronously through Task.Supervisor. Future versions may track
in-flight requests.

## Returns

- `{:ok, boolean}` - Processing status
- `{:error, :agent_not_found}` - Session has no agent
"""
@spec is_processing?(String.t()) :: {:ok, boolean()} | {:error, term()}
def is_processing?(session_id) when is_binary(session_id) do
  with {:ok, agent_pid} <- get_agent(session_id),
       {:ok, status} <- LLMAgent.get_status(agent_pid) do
    # Currently we can only check if the agent is alive/ready
    # True "processing" state would require tracking in-flight requests
    {:ok, not status.ready}
  end
end
```

### Task 4: Write Unit Tests
**Status:** Pending

Tests to add:
1. `get_status/1` returns status for valid session
2. `get_status/1` returns `:agent_not_found` for invalid session
3. `is_processing?/1` returns boolean for valid session
4. `is_processing?/1` returns `:agent_not_found` for invalid session
5. Status includes config, session_id, topic

## Files to Modify

- `lib/jido_code/agents/llm_agent.ex` - Add get_status/1
- `lib/jido_code/session/agent_api.ex` - Add get_status/1, is_processing?/1
- `test/jido_code/session/agent_api_test.exs` - Add status tests

## Completion Checklist

- [x] Task 1: Add get_status/1 to LLMAgent
- [x] Task 2: Add get_status/1 to AgentAPI
- [x] Task 3: Add is_processing?/1 to AgentAPI
- [x] Task 4: Write unit tests (6 new tests)
- [x] Run tests (16 AgentAPI tests, 44 LLMAgent tests - all passing)
- [x] Update phase plan
- [x] Write summary

# WS-3.4.3 Agent Configuration API

**Branch:** `feature/ws-3.4.3-agent-config-api`
**Date:** 2025-12-06
**Status:** Complete

## Overview

Create API for updating agent configuration. This allows the TUI to change the LLM provider, model, temperature, and other settings at runtime without restarting the session.

## Requirements from Plan

From `notes/planning/work-session/phase-03.md`:

- [ ] 3.4.3.1 Implement `update_config/2`
- [ ] 3.4.3.2 Also update session's stored config
- [ ] 3.4.3.3 Write unit tests for config API

## Current State Analysis

### Existing Functions
- `LLMAgent.configure/2` - Already exists, reconfigures agent at runtime
- `LLMAgent.get_config/1` - Returns current config
- `Session.State.get_session/1` - Returns session with config

### Gap
- No high-level API for TUI to update config via session_id
- Session.State doesn't have a way to update the session's config

## Implementation Plan

### Task 1: Add update_config to Session.State
**Status:** Pending

Add function to update the session's config in state:

```elixir
@doc """
Updates the session's LLM configuration.
"""
@spec update_session_config(String.t(), map()) :: {:ok, Session.t()} | {:error, term()}
def update_session_config(session_id, config) when is_binary(session_id) and is_map(config) do
  call_state(session_id, {:update_session_config, config})
end

# Handler
def handle_call({:update_session_config, config}, _from, state) do
  updated_session = %{state.session |
    config: Map.merge(state.session.config, config),
    updated_at: DateTime.utc_now()
  }
  new_state = %{state | session: updated_session}
  {:reply, {:ok, updated_session}, new_state}
end
```

### Task 2: Add update_config/2 to AgentAPI
**Status:** Pending

```elixir
@doc """
Updates the session's agent configuration.

This updates both the agent's runtime configuration and the session's
stored configuration, keeping them in sync.

## Parameters

- `session_id` - The session identifier
- `config` - Map of configuration options:
  - `:provider` - LLM provider (e.g., :anthropic, :openai)
  - `:model` - Model name
  - `:temperature` - Temperature (0.0-1.0)
  - `:max_tokens` - Maximum tokens

## Returns

- `:ok` - Configuration updated successfully
- `{:error, :agent_not_found}` - Session has no agent
- `{:error, reason}` - Validation or other error
"""
@spec update_config(String.t(), map() | keyword()) :: :ok | {:error, term()}
def update_config(session_id, config) when is_binary(session_id) do
  opts = if is_map(config), do: Map.to_list(config), else: config

  with {:ok, agent_pid} <- get_agent(session_id),
       :ok <- LLMAgent.configure(agent_pid, opts) do
    # Also update session's stored config
    config_map = Map.new(opts)
    Session.State.update_session_config(session_id, config_map)
    :ok
  end
end
```

### Task 3: Add get_config/1 to AgentAPI
**Status:** Pending

Convenience function to get agent config:

```elixir
@spec get_config(String.t()) :: {:ok, map()} | {:error, term()}
def get_config(session_id) when is_binary(session_id) do
  with {:ok, agent_pid} <- get_agent(session_id) do
    {:ok, LLMAgent.get_config(agent_pid)}
  end
end
```

### Task 4: Write Unit Tests
**Status:** Pending

Tests to add:
1. `update_config/2` updates agent configuration
2. `update_config/2` updates session's stored config
3. `update_config/2` returns `:agent_not_found` for missing agent
4. `update_config/2` returns validation error for invalid config
5. `get_config/1` returns current config
6. `get_config/1` returns `:agent_not_found` for missing agent

## Files to Modify

- `lib/jido_code/session/state.ex` - Add update_session_config
- `lib/jido_code/session/agent_api.ex` - Add update_config, get_config
- `test/jido_code/session/agent_api_test.exs` - Add config tests

## Completion Checklist

- [x] Task 1: Add update_session_config to Session.State
- [x] Task 2: Add update_config/2 to AgentAPI
- [x] Task 3: Add get_config/1 to AgentAPI
- [x] Task 4: Write unit tests
- [x] Run tests
- [x] Update phase plan
- [x] Write summary

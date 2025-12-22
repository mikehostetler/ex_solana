# Summary: WS-3.4.2 Agent Status API

## Task Overview

Added status-checking capabilities to the Agent API. This allows the TUI to check if an agent is ready to process messages and retrieve current configuration.

## Changes Made

### 1. LLMAgent (`lib/jido_code/agents/llm_agent.ex`)

**Added `get_status/1` client API:**
```elixir
@spec get_status(GenServer.server()) :: {:ok, map()}
def get_status(pid) do
  GenServer.call(pid, :get_status)
end
```

**Added `handle_call(:get_status, ...)` handler:**
```elixir
@impl true
def handle_call(:get_status, _from, state) do
  status = %{
    ready: is_pid(state.ai_pid) and Process.alive?(state.ai_pid),
    config: state.config,
    session_id: state.session_id,
    topic: state.topic
  }
  {:reply, {:ok, status}, state}
end
```

### 2. AgentAPI (`lib/jido_code/session/agent_api.ex`)

**Added Status API section with two functions:**

```elixir
@spec get_status(String.t()) :: {:ok, map()} | {:error, term()}
def get_status(session_id) when is_binary(session_id) do
  with {:ok, agent_pid} <- get_agent(session_id) do
    LLMAgent.get_status(agent_pid)
  end
end

@spec is_processing?(String.t()) :: {:ok, boolean()} | {:error, term()}
def is_processing?(session_id) when is_binary(session_id) do
  with {:ok, agent_pid} <- get_agent(session_id),
       {:ok, status} <- LLMAgent.get_status(agent_pid) do
    {:ok, not status.ready}
  end
end
```

## New API

| Function | Purpose |
|----------|---------|
| `LLMAgent.get_status/1` | Get agent status directly from pid |
| `AgentAPI.get_status/1` | Get agent status via session_id |
| `AgentAPI.is_processing?/1` | Quick boolean check if agent is busy |

## Status Map Structure

```elixir
%{
  ready: boolean(),      # true if agent can process messages
  config: %{             # Current LLM configuration
    provider: atom(),
    model: String.t(),
    temperature: float(),
    max_tokens: integer()
  },
  session_id: String.t(), # Session identifier
  topic: String.t()       # PubSub topic for this agent
}
```

## Usage Examples

```elixir
# Get full status
{:ok, status} = AgentAPI.get_status(session_id)
if status.ready do
  AgentAPI.send_message(session_id, "Hello!")
end

# Quick processing check
{:ok, is_busy} = AgentAPI.is_processing?(session_id)
unless is_busy do
  AgentAPI.send_message(session_id, "Hello!")
end

# Handle missing agent
case AgentAPI.get_status(session_id) do
  {:ok, status} ->
    IO.puts("Agent ready: #{status.ready}")
  {:error, :agent_not_found} ->
    IO.puts("No agent for session")
end
```

## Tests Added

6 new tests in `test/jido_code/session/agent_api_test.exs`:

**get_status/1 tests:**
- Returns error when session has no agent
- Returns status for valid session
- Validates session_id is binary

**is_processing?/1 tests:**
- Returns error when session has no agent
- Returns boolean for valid session
- Validates session_id is binary

## Test Results

- AgentAPI tests: 16 tests, 0 failures
- LLMAgent tests: 44 tests, 0 failures

## Files Changed

- `lib/jido_code/agents/llm_agent.ex` - Added get_status/1 and handler
- `lib/jido_code/session/agent_api.ex` - Added get_status/1, is_processing?/1
- `test/jido_code/session/agent_api_test.exs` - Added status tests
- `notes/planning/work-session/phase-03.md` - Marked Task 3.4.2 complete
- `notes/features/ws-3.4.2-agent-status-api.md` - Planning document

## Next Steps

Task 3.4.3 - Agent Configuration API:
- Implement `update_config/2` to update agent configuration
- Also update session's stored config
- Write unit tests for config API

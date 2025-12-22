# Summary: WS-3.4.1 Send Message API

## Task Overview

Created a high-level API for TUI to send messages to session agents. This provides a clean abstraction layer between the TUI and the underlying LLMAgent, handling session lookups and error cases.

## Changes Made

### 1. Created AgentAPI Module (`lib/jido_code/session/agent_api.ex`)

New module providing clean abstraction for TUI-agent communication:

```elixir
defmodule JidoCode.Session.AgentAPI do
  @moduledoc """
  High-level API for interacting with session agents.
  """

  alias JidoCode.Agents.LLMAgent
  alias JidoCode.Session.Supervisor, as: SessionSupervisor

  @spec send_message(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def send_message(session_id, message, opts \\ [])

  @spec send_message_stream(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def send_message_stream(session_id, message, opts \\ [])
end
```

### 2. Implemented `send_message/3`

Synchronous message sending:
- Looks up agent via `Session.Supervisor.get_agent/1`
- Calls `LLMAgent.chat/3` with the message
- Returns `{:ok, response}` or `{:error, reason}`
- Supports `:timeout` option

### 3. Implemented `send_message_stream/3`

Asynchronous streaming message:
- Looks up agent via `Session.Supervisor.get_agent/1`
- Calls `LLMAgent.chat_stream/3` with the message
- Returns `:ok` immediately (response via PubSub)
- Supports `:timeout` option

### 4. Error Handling

Private `get_agent/1` helper provides consistent error handling:
- Translates `:not_found` to `:agent_not_found` for clearer API semantics
- Passes through other errors unchanged

## New API

| Function | Purpose |
|----------|---------|
| `AgentAPI.send_message/3` | Synchronous message to agent with response |
| `AgentAPI.send_message_stream/3` | Async streaming message (response via PubSub) |

## Usage Examples

```elixir
# Send synchronous message
{:ok, response} = AgentAPI.send_message(session_id, "Hello!")

# Send streaming message
:ok = AgentAPI.send_message_stream(session_id, "Tell me about Elixir")

# With timeout option
{:ok, response} = AgentAPI.send_message(session_id, "Hello!", timeout: 30_000)

# Handle missing agent
case AgentAPI.send_message(session_id, "Hello!") do
  {:ok, response} -> IO.puts(response)
  {:error, :agent_not_found} -> IO.puts("No agent for session")
  {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
end
```

## PubSub Events

For streaming, subscribe to `JidoCode.PubSubTopics.llm_stream(session_id)`:

| Event | Description |
|-------|-------------|
| `{:stream_chunk, content}` | Content chunk as string |
| `{:stream_end, full_content}` | Full response when complete |
| `{:stream_error, reason}` | Error during streaming |

## Tests Added

10 new tests in `test/jido_code/session/agent_api_test.exs`:

**send_message/2 tests:**
- Returns error when session has no agent
- Sends message to correct agent and returns response
- Validates message is binary
- Validates session_id is binary

**send_message_stream/2 tests:**
- Returns error when session has no agent
- Initiates streaming to correct agent
- Accepts timeout option
- Validates message is binary
- Validates session_id is binary

**Error handling tests:**
- Translates :not_found to :agent_not_found

## Test Results

- Session tests: 175 tests, 0 failures
- AgentAPI tests: 10 tests, 0 failures

## Files Created

- `lib/jido_code/session/agent_api.ex` - New AgentAPI module
- `test/jido_code/session/agent_api_test.exs` - New test file

## Files Modified

- `notes/planning/work-session/phase-03.md` - Marked Task 3.4.1 complete
- `notes/features/ws-3.4.1-send-message-api.md` - Updated planning document

## Next Steps

Task 3.4.2 - Agent Status API:
- Implement `get_status/1` returning agent status
- Implement `is_processing?/1` for quick status check
- Write unit tests for status API

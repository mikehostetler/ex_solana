# Summary: WS-3.3.4 Agent Streaming with Session

## Task Overview

Updated LLMAgent streaming to route through Session.State. This ensures streaming content is persisted in the session state while also being broadcast via PubSub for TUI consumption.

## Changes Made

### 1. LLMAgent (`lib/jido_code/agents/llm_agent.ex`)

**Added alias:**
```elixir
alias JidoCode.Session.State, as: SessionState
```

**Updated handle_cast to pass session_id:**
```elixir
@impl true
def handle_cast({:chat_stream, message, timeout}, state) do
  topic = state.topic
  config = state.config
  session_id = state.session_id  # <-- Added

  Task.Supervisor.start_child(JidoCode.TaskSupervisor, fn ->
    try do
      do_chat_stream_with_timeout(config, message, topic, timeout, session_id)  # <-- Updated
    ...
```

**Updated streaming functions to accept session_id:**
- `do_chat_stream_with_timeout/5` - passes session_id to `do_chat_stream/4`
- `do_chat_stream/4` - passes session_id to `execute_stream/4`
- `execute_stream/4` - generates message_id, calls `start_session_streaming/2`, passes to `process_stream/3`
- `process_stream/3` - passes session_id to broadcast functions
- `broadcast_stream_chunk/3` - calls `update_session_streaming/2` then broadcasts
- `broadcast_stream_end/3` - calls `end_session_streaming/1` then broadcasts

**Added Session.State streaming helpers:**
```elixir
# Start streaming in Session.State (skip if session_id is PID string)
defp start_session_streaming(session_id, message_id) when is_binary(session_id) do
  if is_valid_session_id?(session_id) do
    SessionState.start_streaming(session_id, message_id)
  else
    :ok
  end
end

# Update streaming content in Session.State
defp update_session_streaming(session_id, chunk) when is_binary(session_id) do
  if is_valid_session_id?(session_id) do
    SessionState.update_streaming(session_id, chunk)
  else
    :ok
  end
end

# End streaming in Session.State
defp end_session_streaming(session_id) when is_binary(session_id) do
  if is_valid_session_id?(session_id) do
    SessionState.end_streaming(session_id)
  else
    :ok
  end
end

# Check if session_id is a valid session ID (not a PID string)
defp is_valid_session_id?(session_id) when is_binary(session_id) do
  not String.starts_with?(session_id, "#PID<")
end
```

### 2. LLMAgent Tests (`test/jido_code/agents/llm_agent_test.exs`)

Added 5 new tests in the "streaming with Session.State integration" describe block:

1. **start_session_streaming is skipped when session_id is PID string**
   - Verifies agents started without a session don't crash on streaming ops

2. **streaming with proper session updates Session.State**
   - Creates a real session
   - Tests full streaming lifecycle: start -> chunks -> end
   - Verifies message is added to session history

3. **end_streaming returns error when not streaming**
   - Tests `{:error, :not_streaming}` is returned when ending without starting

4. **streaming chunks are silently ignored when not streaming**
   - Tests that orphan chunks are safely ignored

5. **is_valid_session_id helper correctly identifies PID strings**
   - Tests graceful degradation for agents without sessions

## Streaming Flow

```
                   LLMAgent                    Session.State
                      │                             │
chat_stream(message)  │                             │
        ─────────────►│                             │
                      │                             │
                      │ execute_stream()            │
                      │──────────────────────────►  │
                      │ start_streaming(session_id, │
                      │                 message_id) │
                      │                             │
                      │ process_stream()            │
                      │ ┌─────────────────────────┐ │
                      │ │ for each chunk:         │ │
                      │ │   update_streaming()  ──┼─►
                      │ │   broadcast_chunk()     │ │
                      │ └─────────────────────────┘ │
                      │                             │
                      │ end_streaming()             │
                      │──────────────────────────►  │
                      │ (finalizes message)         │
                      │ broadcast_stream_end()      │
                      │                             │
```

## Graceful Degradation

When LLMAgent is started without a proper session (session_id is a PID string like `#PID<0.123.0>`):

1. The `is_valid_session_id?/1` helper returns `false`
2. Session.State calls are skipped
3. PubSub broadcasts still occur for TUI consumption
4. No crashes or errors

## Test Results

- Total LLMAgent tests: 44 (5 new for streaming integration)
- Failures: 0
- Skipped: 1 (integration test requiring real API key)

## Files Changed

- `lib/jido_code/agents/llm_agent.ex` - Updated streaming to use Session.State
- `test/jido_code/agents/llm_agent_test.exs` - Added streaming integration tests
- `notes/planning/work-session/phase-03.md` - Marked Task 3.3.4 complete
- `notes/features/ws-3.3.4-agent-streaming-session.md` - Planning document

## Next Steps

Task 3.4.1 - Send Message API:
- Create high-level API for sending messages to session agent
- Create `lib/jido_code/session/agent_api.ex` module

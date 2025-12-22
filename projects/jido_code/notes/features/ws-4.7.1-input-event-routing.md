# Planning Document: Task 4.7.1 - Input Event Routing

## Overview

**Task**: Route input events to active session's agent (Phase 4.7.1)

**Status**: ✅ Complete

**Context**: Tasks 4.5.1-4.5.6 are complete. The sidebar and keyboard navigation are implemented. Now we need to route user input to the correct session's agent instead of the global agent.

**Dependencies**:
- Phase 3.4: Session AgentAPI ✅ COMPLETE
- Phase 4.5: Left Sidebar Integration ✅ COMPLETE
- Phase 4.6: Keyboard Navigation ✅ COMPLETE

**Blocks**:
- Phase 4.7.2: Scroll Event Routing
- Phase 4.7.3: PubSub Event Handling
- Phase 4.8: Integration Tests

---

## Problem Statement

**Current Behavior**:
The TUI's `do_dispatch_to_agent/2` function (line 1586) uses the old single-agent approach:
- Looks up agent via `AgentSupervisor.lookup_agent(state.agent_name)`
- Calls `LLMAgent.chat_stream(agent_pid, text)` directly
- Uses global message list `state.messages`
- Uses global conversation view

**Issue**:
- Ignores `active_session_id` - input doesn't go to the active session
- Won't work with multiple sessions
- Messages stored in wrong place (global state vs session state)

**Impact**:
- Multi-session functionality is non-functional for chat input
- All user messages would go to the same agent (if it even works)
- Session switching wouldn't change which agent receives input

---

## Solution Overview

### High-Level Approach

Update input submission flow to:
1. Check if there's an active session
2. Route input to active session's agent via `Session.AgentAPI.send_message_stream/2`
3. Handle edge case when no active session exists
4. Update UI state appropriately (processing status, clear input)

### Key Changes

**Before** (single-agent):
```elixir
case AgentSupervisor.lookup_agent(state.agent_name) do
  {:ok, agent_pid} ->
    LLMAgent.chat_stream(agent_pid, text)
    # ...
end
```

**After** (multi-session):
```elixir
case state.active_session_id do
  nil ->
    show_no_session_error(state)

  session_id ->
    Session.AgentAPI.send_message_stream(session_id, text)
    # ...
end
```

### Architecture

```
User Input
    ↓
TUI.update({:input_submitted, text}, state)
    ↓
do_handle_chat_submit(text, state)
    ↓
Check active_session_id
    ↓
Session.AgentAPI.send_message_stream(session_id, text)
    ↓
Session's LLMAgent processes message
    ↓
Agent broadcasts chunks via PubSub
    ↓
TUI receives {:stream_chunk, session_id, chunk}
    ↓
Updates UI for active session
```

---

## Current State Analysis

### Existing Input Flow

**File**: `lib/jido_code/tui.ex`

**Entry Point** (line 925):
```elixir
def update({:input_submitted, value}, state) do
  text = String.trim(value)

  cond do
    text == "" -> {state, []}
    String.starts_with?(text, "/") -> do_handle_command(text, state)
    true -> do_handle_chat_submit(text, state)
  end
end
```

**Chat Submit** (line 1544):
```elixir
defp do_handle_chat_submit(text, state) do
  case {state.config.provider, state.config.model} do
    {nil, _} -> do_show_config_error(state)
    {_, nil} -> do_show_config_error(state)
    {_provider, _model} -> do_dispatch_to_agent(text, state)
  end
end
```

**Agent Dispatch** (line 1586):
```elixir
defp do_dispatch_to_agent(text, state) do
  # Add user message to conversation
  user_msg = user_message(text)

  # Sync to ConversationView
  new_conversation_view = ConversationView.add_message(state.conversation_view, ...)

  # OLD: Lookup global agent
  case AgentSupervisor.lookup_agent(state.agent_name) do
    {:ok, agent_pid} ->
      LLMAgent.chat_stream(agent_pid, text)
      # Update global state
      {%{state | messages: [user_msg | state.messages], ...}, []}

    {:error, :not_found} ->
      show_error(state)
  end
end
```

### What Needs to Change

1. **do_dispatch_to_agent/2**: Replace agent lookup with session routing
2. **Message storage**: Remove global message updates (sessions store their own)
3. **ConversationView sync**: Keep for display purposes (still needed)
4. **Error handling**: Add "no active session" error case
5. **Config check**: May not be needed (sessions have own config)

---

## Implementation Plan

### Task 4.7.1.1: Update submit handler to use active session

**File**: `lib/jido_code/tui.ex`

**Function**: `do_dispatch_to_agent/2` (line 1586)

**Changes**:
1. Remove `AgentSupervisor.lookup_agent` code
2. Check `state.active_session_id`
3. Call `Session.AgentAPI.send_message_stream(session_id, text)`
4. Remove global message list updates
5. Keep UI state updates (agent_status, is_streaming, etc.)

**New Implementation**:
```elixir
defp do_dispatch_to_agent(text, state) do
  case state.active_session_id do
    nil ->
      do_show_no_session_error(state)

    session_id ->
      # User message is stored by Session.State automatically
      # Just sync to ConversationView for display
      new_conversation_view =
        if state.conversation_view do
          ConversationView.add_message(state.conversation_view, %{
            id: generate_message_id(),
            role: :user,
            content: text,
            timestamp: DateTime.utc_now()
          })
        else
          state.conversation_view
        end

      # Send to active session's agent
      case Session.AgentAPI.send_message_stream(session_id, text) do
        :ok ->
          # Update UI state to show processing
          updated_state = %{
            state
            | agent_status: :processing,
              scroll_offset: 0,
              streaming_message: "",
              is_streaming: true,
              conversation_view: new_conversation_view
          }

          {updated_state, []}

        {:error, reason} ->
          do_show_agent_error(state, reason)
      end
  end
end
```

### Task 4.7.1.2: Handle submit when no active session

**File**: `lib/jido_code/tui.ex`

**New Function**: `do_show_no_session_error/1`

**Implementation**:
```elixir
defp do_show_no_session_error(state) do
  error_content = """
  No active session. Create a session first with:
    /session new <path> --name="Session Name"

  Or switch to an existing session with:
    /session switch <index>
  """

  error_msg = system_message(error_content)

  # Add to ConversationView
  new_conversation_view =
    if state.conversation_view do
      ConversationView.add_message(state.conversation_view, %{
        id: generate_message_id(),
        role: :system,
        content: error_content,
        timestamp: DateTime.utc_now()
      })
    else
      state.conversation_view
    end

  new_state = %{
    state
    | messages: [error_msg | state.messages],
      conversation_view: new_conversation_view
  }

  {new_state, []}
end
```

**New Function**: `do_show_agent_error/2`

**Implementation**:
```elixir
defp do_show_agent_error(state, reason) do
  error_content = "Failed to send message to session agent: #{inspect(reason)}"
  error_msg = system_message(error_content)

  new_conversation_view =
    if state.conversation_view do
      ConversationView.add_message(state.conversation_view, %{
        id: generate_message_id(),
        role: :system,
        content: error_content,
        timestamp: DateTime.utc_now()
      })
    else
      state.conversation_view
    end

  new_state = %{
    state
    | messages: [error_msg | state.messages],
      conversation_view: new_conversation_view
  }

  {new_state, []}
end
```

### Task 4.7.1.3: Write unit tests for input routing

**File**: `test/jido_code/tui_test.exs`

**Test Suite**: "Input event routing (Task 4.7.1)"

**Tests** (8 tests):

1. **Input routing to active session**:
```elixir
test "routes chat input to active session's agent" do
  # Setup: Create model with active session
  # Action: Submit chat input
  # Assert: Session.AgentAPI.send_message_stream called with correct session_id
end
```

2. **No active session error**:
```elixir
test "shows error when no active session" do
  # Setup: Model with active_session_id = nil
  # Action: Submit chat input
  # Assert: Error message added to conversation view
  # Assert: agent_status not changed
end
```

3. **Agent send failure**:
```elixir
test "shows error when agent send fails" do
  # Setup: Mock AgentAPI.send_message_stream to return {:error, reason}
  # Action: Submit chat input
  # Assert: Error message shown
end
```

4. **UI state updates on successful send**:
```elixir
test "updates UI state when message sent successfully" do
  # Setup: Model with active session
  # Action: Submit chat input
  # Assert: agent_status = :processing
  # Assert: is_streaming = true
  # Assert: streaming_message = ""
  # Assert: scroll_offset = 0
end
```

5. **Empty input ignored**:
```elixir
test "ignores empty input" do
  # Setup: Model with active session
  # Action: Submit empty string or whitespace
  # Assert: No agent call
  # Assert: State unchanged
end
```

6. **Command input bypasses agent routing**:
```elixir
test "commands are not routed to agent" do
  # Setup: Model with active session
  # Action: Submit "/help"
  # Assert: Command handler called
  # Assert: Agent not called
end
```

7. **ConversationView sync on send**:
```elixir
test "adds user message to ConversationView" do
  # Setup: Model with conversation_view
  # Action: Submit chat input
  # Assert: ConversationView.add_message called with user message
end
```

8. **Input cleared after submit**:
```elixir
test "clears text input after successful submit" do
  # Setup: Model with active session and text in input
  # Action: Submit chat input
  # Assert: text_input cleared
end
```

---

## Dependencies & Integration

### Session.AgentAPI Module

**Module**: `JidoCode.Session.AgentAPI` (already implemented in Task 3.4.1)

**Function**: `send_message_stream/2`

**Signature**:
```elixir
@spec send_message_stream(Session.id(), String.t()) :: :ok | {:error, term()}
```

**Behavior**:
- Looks up session's LLMAgent
- Calls `LLMAgent.chat_stream/2`
- Stores user message in Session.State
- Agent broadcasts chunks via PubSub to `tui.events.#{session_id}`

**TUI's Role**:
- Call send_message_stream/2
- Update UI state (processing, streaming flags)
- PubSub handlers receive chunks and update display

### PubSub Message Flow

**Send**:
```elixir
Session.AgentAPI.send_message_stream(session_id, text)
  ↓
LLMAgent.chat_stream(agent_pid, text)
  ↓
Agent broadcasts: Phoenix.PubSub.broadcast("tui.events.#{session_id}", {:stream_chunk, session_id, chunk})
```

**Receive** (TUI already has handlers):
```elixir
def update({:stream_chunk, session_id, chunk}, state) do
  # Only update UI if this is the active session
  if session_id == state.active_session_id do
    # Update streaming_message
  end
end
```

---

## Removal of Old Code

### Code to Remove

**AgentSupervisor lookup** (lines 1607-1625):
```elixir
case AgentSupervisor.lookup_agent(state.agent_name) do
  {:ok, agent_pid} ->
    # This entire block
end
```

**Global message list updates**:
```elixir
messages: [user_msg | new_state.messages]
```

**Session subscription logic** (line 1610):
```elixir
new_state = ensure_session_subscription(state, agent_pid)
```
This is no longer needed - PubSub subscriptions are managed per-session now.

### Code to Keep

**ConversationView sync**: Still needed for display
**UI state updates**: Still needed (agent_status, is_streaming, etc.)
**Input clearing**: Still needed
**Config error handling**: May still be useful as fallback

---

## Design Decisions

### Decision 1: Config Validation

**Question**: Should we check provider/model config before routing to session?

**Options**:
1. Keep config check in `do_handle_chat_submit/2`
2. Remove config check, let session handle it
3. Check session's config instead of global config

**Decision**: Remove global config check.

**Rationale**:
- Each session has its own config (from Task 2.3)
- Session's agent will handle missing config
- Global config is vestigial from single-agent era

**Implementation**: Remove `do_handle_chat_submit/2`, call `do_dispatch_to_agent/2` directly.

### Decision 2: Message Storage

**Question**: Should TUI store user message in global `state.messages`?

**Options**:
1. Store in both global and session
2. Store only in session (via AgentAPI)
3. Store only in global for display

**Decision**: Don't store in global, only in session.

**Rationale**:
- Session.State is source of truth for messages
- Global `state.messages` is legacy from single-agent
- ConversationView gets messages from session when rendering

**Implementation**: Remove `messages: [user_msg | state.messages]` updates.

### Decision 3: Error Handling

**Question**: What errors should be handled?

**Errors**:
1. No active session (`active_session_id == nil`)
2. Agent send failure (`{:error, reason}`)
3. Session not found (unlikely but possible)

**Decision**: Handle all three explicitly.

**Rationale**:
- Better UX with specific error messages
- Prevents crashes from unexpected states

---

## Success Criteria

### Functional Requirements

- ✅ Chat input routed to active session's agent
- ✅ No active session shows helpful error
- ✅ Agent send failures show error message
- ✅ UI state updates correctly (processing, streaming, etc.)
- ✅ Input cleared after successful send
- ✅ Commands still bypass agent routing
- ✅ Empty input ignored

### Technical Requirements

- ✅ Uses `Session.AgentAPI.send_message_stream/2`
- ✅ Removes AgentSupervisor lookup code
- ✅ Removes global message list updates
- ✅ 8 unit tests covering all scenarios
- ✅ All tests passing
- ✅ No breaking changes to command handling

### Non-Functional Requirements

- ✅ No performance degradation
- ✅ Error messages are clear and actionable
- ✅ Backward compatible with single-session usage

---

## Test Plan

### Unit Tests (8 tests)

**Test Suite**: "Input event routing (Task 4.7.1)"

1. Routes chat input to active session
2. Shows error when no active session
3. Shows error when agent send fails
4. Updates UI state on successful send
5. Ignores empty input
6. Commands bypass agent routing
7. Adds user message to ConversationView
8. Clears text input after submit

### Manual Testing

```bash
iex -S mix
JidoCode.TUI.run()

# Test 1: No session error
> hello  # Should show "No active session" error

# Test 2: Create session and send message
> /session new . --name="Test"
> hello world  # Should route to session's agent

# Test 3: Switch sessions
> /session new /tmp --name="Test2"
> /session switch 1
> message to first session  # Should route to session 1

# Test 4: Commands still work
> /help  # Should show help, not route to agent

# Test 5: Empty input ignored
>         # (just whitespace) Should do nothing
```

---

## Risk Assessment

### Low Risk

- **Straightforward replacement**: AgentSupervisor → Session.AgentAPI
- **Well-tested API**: Session.AgentAPI already tested in Phase 3
- **Isolated change**: Only affects chat input, not commands

### Medium Risk

- **Message display**: Need to ensure messages still display correctly
- **Config handling**: Removing global config check might expose edge cases

### Mitigation

- Comprehensive unit tests (8 tests)
- Manual testing of all scenarios
- Keep ConversationView sync to maintain display
- Error handling for all failure modes

---

## Next Steps After 4.7.1

### Task 4.7.2: Scroll Event Routing

Route scroll events to active session's conversation view.

### Task 4.7.3: PubSub Event Handling

Update PubSub handlers to filter by active session.

### Phase 4.8: Integration Tests

End-to-end tests for multi-session workflows.

---

## References

- **Phase Plan**: `/home/ducky/code/jido_code/notes/planning/work-session/phase-04.md` (lines 681-696)
- **Current Implementation**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex` (lines 925, 1544, 1586)
- **Session.AgentAPI**: `/home/ducky/code/jido_code/lib/jido_code/session/agent_api.ex`
- **Task 3.4.1**: Session AgentAPI implementation (send_message_stream/2)

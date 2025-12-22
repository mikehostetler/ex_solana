# Feature: PubSub Subscription Management (Task 4.2.2)

## Problem Statement

Task 4.2.1 implemented session loading and subscription at TUI initialization, but subscriptions are static - created only at startup. The TUI needs dynamic subscription management to handle sessions added or removed during runtime.

Current issues:
- No way to subscribe to new sessions created after TUI starts
- No way to unsubscribe from sessions when they're closed
- Session add/remove functions don't manage PubSub subscriptions
- Memory leak potential from unclosed subscriptions

Without dynamic subscription management, the TUI cannot properly handle multi-session workflows where users create and close sessions during operation.

## Solution Overview

Implement dynamic PubSub subscription management by:

1. **Create `subscribe_to_session/1`** - Subscribe to a single session's topic
2. **Create `unsubscribe_from_session/1`** - Unsubscribe from a session's topic
3. **Update `add_session/2`** - Subscribe when adding session
4. **Update `add_session_to_tabs/2`** - Subscribe when adding session
5. **Update `remove_session/2`** - Unsubscribe when removing session
6. **Write comprehensive unit tests** - Verify subscription lifecycle

## Technical Details

### Files to Modify
- `lib/jido_code/tui.ex` - Add subscription functions, update add/remove
- `test/jido_code/tui_test.exs` - Add subscription management tests

### Current State

**Existing Functions**:
- `subscribe_to_all_sessions/1` (line 1695-1700) - Bulk subscription at init
- `add_session/2` (line 333-340) - Adds session, sets as active
- `add_session_to_tabs/2` (line 376-385) - Adds session, preserves active
- `remove_session/2` (line 457-493) - Removes session, handles active switching

**None of these functions manage subscriptions dynamically**.

### Implementation Approach

#### Function 1: subscribe_to_session/1

```elixir
# Subscribe to PubSub topic for a single session.
#
# Subscribes to the session's llm_stream topic to receive
# streaming messages, tool calls, and other session events.
@spec subscribe_to_session(String.t()) :: :ok | {:error, term()}
defp subscribe_to_session(session_id) do
  topic = PubSubTopics.llm_stream(session_id)
  Phoenix.PubSub.subscribe(JidoCode.PubSub, topic)
end
```

**Key Features**:
- Takes session_id directly (not Session struct)
- Uses `PubSubTopics.llm_stream/1` for topic name
- Returns `:ok` on success, `{:error, term}` on failure

#### Function 2: unsubscribe_from_session/1

```elixir
# Unsubscribe from PubSub topic for a single session.
#
# Unsubscribes from the session's llm_stream topic to stop
# receiving events from that session.
@spec unsubscribe_from_session(String.t()) :: :ok
defp unsubscribe_from_session(session_id) do
  topic = PubSubTopics.llm_stream(session_id)
  Phoenix.PubSub.unsubscribe(JidoCode.PubSub, topic)
end
```

**Key Features**:
- Takes session_id directly
- Always returns `:ok` (unsubscribe is idempotent)
- Safe to call multiple times

#### Updated add_session/2

```elixir
def add_session(%__MODULE__{} = model, %JidoCode.Session{} = session) do
  # Subscribe to the new session's events
  subscribe_to_session(session.id)

  %{
    model
    | sessions: Map.put(model.sessions, session.id, session),
      session_order: model.session_order ++ [session.id],
      active_session_id: session.id
  }
end
```

**Change**: Add `subscribe_to_session(session.id)` call before returning model.

#### Updated add_session_to_tabs/2

```elixir
def add_session_to_tabs(%__MODULE__{} = model, session) when is_map(session) do
  session_id = Map.get(session, :id) || Map.get(session, "id")

  # Subscribe to the new session's events
  subscribe_to_session(session_id)

  %{
    model
    | sessions: Map.put(model.sessions, session_id, session),
      session_order: model.session_order ++ [session_id],
      active_session_id: model.active_session_id || session_id
  }
end
```

**Change**: Add `subscribe_to_session(session_id)` call before returning model.

#### Updated remove_session/2

```elixir
def remove_session(%__MODULE__{} = model, session_id) do
  # Unsubscribe from the session's events before removal
  unsubscribe_from_session(session_id)

  # Remove from sessions map
  new_sessions = Map.delete(model.sessions, session_id)

  # ... rest of existing logic unchanged
end
```

**Change**: Add `unsubscribe_from_session(session_id)` call at the beginning of the function.

### Refactor subscribe_to_all_sessions/1

The existing `subscribe_to_all_sessions/1` can be refactored to use the new `subscribe_to_session/1`:

```elixir
# Subscribe to PubSub topics for all sessions.
#
# Subscribes to each session's llm_stream topic for receiving
# streaming messages, tool calls, and other session events.
@spec subscribe_to_all_sessions([Session.t()]) :: :ok
defp subscribe_to_all_sessions(sessions) do
  Enum.each(sessions, fn session ->
    subscribe_to_session(session.id)
  end)
end
```

**Change**: Replace direct `Phoenix.PubSub.subscribe` with `subscribe_to_session(session.id)`.

## Success Criteria

1. ✅ `subscribe_to_session/1` subscribes to session's topic
2. ✅ `unsubscribe_from_session/1` unsubscribes from session's topic
3. ✅ `add_session/2` calls `subscribe_to_session/1`
4. ✅ `add_session_to_tabs/2` calls `subscribe_to_session/1`
5. ✅ `remove_session/2` calls `unsubscribe_from_session/1`
6. ✅ `subscribe_to_all_sessions/1` refactored to use `subscribe_to_session/1`
7. ✅ All unit tests pass
8. ✅ Phase plan updated with checkmarks
9. ✅ Summary document written

## Implementation Plan

### Step 1: Read Current Code
- [x] Read existing subscription code (subscribe_to_all_sessions/1)
- [x] Read add_session/2 and add_session_to_tabs/2
- [x] Read remove_session/2
- [x] Understand PubSubTopics.llm_stream/1 usage

### Step 2: Implement subscribe_to_session/1
- [x] Add public function before subscribe_to_all_sessions/1
- [x] Add @spec typespec
- [x] Add documentation comment
- [x] Use PubSubTopics.llm_stream/1 for topic
- [x] Call Phoenix.PubSub.subscribe/2

### Step 3: Implement unsubscribe_from_session/1
- [x] Add public function after subscribe_to_session/1
- [x] Add @spec typespec
- [x] Add documentation comment
- [x] Use PubSubTopics.llm_stream/1 for topic
- [x] Call Phoenix.PubSub.unsubscribe/2

### Step 4: Refactor subscribe_to_all_sessions/1
- [x] Update to call subscribe_to_session/1 instead of direct subscribe
- [x] Verify still works with init/1

### Step 5: Update add_session/2
- [x] Add JidoCode.TUI.subscribe_to_session/1 call
- [x] Place before model update

### Step 6: Update add_session_to_tabs/2
- [x] Add JidoCode.TUI.subscribe_to_session/1 call
- [x] Place before model update

### Step 7: Update remove_session/2
- [x] Add JidoCode.TUI.unsubscribe_from_session/1 call
- [x] Place at beginning of function

### Step 8: Write Unit Tests
- [x] Test subscribe_to_session/1 creates subscription
- [x] Test unsubscribe_from_session/1 removes subscription
- [x] Test add_session/2 subscribes to new session
- [x] Test add_session_to_tabs/2 subscribes to new session
- [x] Test remove_session/2 unsubscribes from session
- [x] Test remove_session_from_tabs/2 unsubscribes from session
- [x] All 6 tests pass (no new test failures introduced)

### Step 9: Documentation and Completion
- [x] Update phase-04.md to mark task 4.2.2 as complete
- [ ] Write summary document
- [ ] Request commit approval

## Notes/Considerations

### Edge Cases
- Subscribing to already-subscribed session (PubSub handles this - duplicate subscriptions allowed)
- Unsubscribing from non-subscribed session (safe - unsubscribe is idempotent)
- Session added then immediately removed

### Testing Strategy
- Verify subscriptions by broadcasting messages and receiving them
- Verify unsubscriptions by broadcasting and NOT receiving
- Test add/remove functions maintain subscription state
- Ensure existing tests don't break

### PubSub Behavior
- `Phoenix.PubSub.subscribe/2` - Creates subscription, returns `:ok` or `{:error, reason}`
- `Phoenix.PubSub.unsubscribe/2` - Removes subscription, always returns `:ok`
- Multiple subscriptions to same topic from same process are allowed
- Unsubscribing from non-subscribed topic is a no-op

### Future Work (Not in 4.2.2)
- Task 4.2.3: Message routing with session_id
- Error handling for failed subscriptions
- Tracking subscription state in model

## Status

**Current Step**: Creating feature plan
**Branch**: feature/pubsub-subscription-management
**Next**: Implement subscribe_to_session/1 and unsubscribe_from_session/1

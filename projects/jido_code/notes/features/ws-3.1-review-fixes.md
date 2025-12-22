# Feature: WS-3.1 Review Fixes

## Problem Statement

The code review for Section 3.1 (Tool Executor Updates) identified several concerns and suggestions that should be addressed:

### Concerns (Medium Severity)

1. **Session ID Validation Gap** - `build_context/2` accepts any string as session_id without UUID format validation
2. **Context Enrichment Silent Failure** - `maybe_enrich_context/2` adds session_id to context even when lookup fails
3. **PubSub Message Format Inconsistency** - Different tuple sizes for related messages (documented, low priority)

### Suggestions

1. **Consolidate Context Building Logic** - `build_context/2` and `enrich_context/1` both call `Session.Manager.project_root/1`
2. **Extract PubSub Broadcasting to Shared Module** - Broadcasting pattern duplicated in `Handlers.Todo`
3. **Add Security Test Cases** - Missing tests for invalid UUID format, special characters, topic injection

## Solution Overview

### 1. UUID Validation in Executor (Concern #1)

Add UUID validation to `build_context/2` using the same regex pattern from `HandlerHelpers`:

```elixir
@uuid_regex ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

def build_context(session_id, opts \\ []) when is_binary(session_id) do
  unless valid_uuid?(session_id), do: return {:error, :invalid_session_id}
  # ... existing code
end

defp valid_uuid?(session_id), do: Regex.match?(@uuid_regex, session_id)
```

### 2. Fix Context Enrichment (Concern #2)

Update `maybe_enrich_context/2` to return context unchanged on failure and add logging:

```elixir
defp maybe_enrich_context(context, session_id) when is_binary(session_id) do
  case Session.Manager.project_root(session_id) do
    {:ok, project_root} ->
      context
      |> Map.put(:session_id, session_id)
      |> Map.put(:project_root, project_root)

    {:error, reason} ->
      Logger.warning("Failed to enrich context for session #{session_id}: #{inspect(reason)}")
      context  # Return unchanged, don't add invalid session_id
  end
end
```

### 3. Consolidate Context Building (Suggestion #1)

Make `build_context/2` delegate to `enrich_context/1` to reduce duplication:

```elixir
def build_context(session_id, opts \\ []) when is_binary(session_id) do
  unless valid_uuid?(session_id), do: {:error, :invalid_session_id}

  timeout = Keyword.get(opts, :timeout, @default_timeout)
  base_context = %{session_id: session_id, timeout: timeout}
  enrich_context(base_context)
end
```

### 4. Extract PubSub Broadcasting (Suggestion #2)

Create `JidoCode.PubSubHelpers` module:

```elixir
defmodule JidoCode.PubSubHelpers do
  @moduledoc """
  Shared PubSub broadcasting helpers.

  Implements the ARCH-2 dual-topic broadcasting pattern to ensure
  messages reach both session-specific and global subscribers.
  """

  def broadcast_to_session(session_id, message) do
    if session_id do
      Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events.#{session_id}", message)
    end
    Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events", message)
  end

  def session_topic(nil), do: "tui.events"
  def session_topic(session_id), do: "tui.events.#{session_id}"
end
```

### 5. Security Test Cases (Suggestion #3)

Add tests for:
- Invalid UUID format rejection in `build_context/2`
- Session ID with special characters
- Non-UUID string handling

## Implementation Plan

### Step 1: Add UUID validation to Executor
- [x] Add `@uuid_regex` module attribute
- [x] Add `valid_uuid?/1` private function
- [x] Update `build_context/2` to validate UUID format
- [x] Add tests for invalid UUID rejection

### Step 2: Fix context enrichment silent failure
- [x] Update `maybe_enrich_context/2` to return context unchanged on failure
- [x] Add logging for enrichment failures
- [x] Add tests for failure handling

### Step 3: Consolidate context building logic
- [x] Refactor `build_context/2` to use `enrich_context/1`
- [x] Ensure timeout option is properly handled
- [x] Update tests if needed

### Step 4: Extract PubSub broadcasting
- [x] Create `JidoCode.PubSubHelpers` module
- [x] Refactor `Executor` to use the helper
- [x] Refactor `Handlers.Todo` to use the helper
- [x] Add tests for helper module

### Step 5: Add security tests
- [x] Test invalid UUID formats
- [x] Test special character handling
- [x] Test edge cases

## Success Criteria

- [x] `build_context/2` rejects non-UUID session IDs
- [x] `maybe_enrich_context/2` doesn't add session_id on failure
- [x] Context building logic is consolidated
- [x] PubSub broadcasting uses shared helper
- [x] All new and existing tests pass

## Current Status

**Status**: Complete

All fixes and improvements have been implemented and tested.

## Test Results

- 55 executor tests pass (7 new security tests)
- 7 PubSubHelpers tests pass
- 16 Todo handler tests pass
- 44 integration tests pass
- Total: 122 tests, 0 failures

## Files Changed

### Modified
- `lib/jido_code/tools/executor.ex` - UUID validation, context consolidation
- `lib/jido_code/tools/handlers/todo.ex` - Use PubSubHelpers
- `test/jido_code/tools/executor_test.exs` - Security tests

### Created
- `lib/jido_code/pubsub_helpers.ex` - Shared broadcasting module
- `test/jido_code/pubsub_helpers_test.exs` - Helper tests

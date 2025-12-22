# Feature: WS-2.2.1 Session State Module Structure

## Problem Statement

Task 2.2.1 requires enhancing the Session.State module with proper state structure for conversation and UI state management. The module already exists as a stub from Phase 1 but needs the full state structure defined in the plan.

## Solution Overview

Enhance the existing Session.State module with:
1. Define proper `@type state()` with all required fields
2. Define supporting types (message, reasoning_step, tool_call, todo)
3. Update `init/1` to initialize with the complete state structure
4. Keep existing functionality (start_link, child_spec, get_session)

### Key Decisions

- Keep `session` in state for backwards compatibility with `get_session/1`
- Add all new fields from the plan: messages, reasoning_steps, tool_calls, todos, scroll_offset, streaming_message, is_streaming
- Use ProcessRegistry for via tuple (already done)
- Add logging on initialization

## Technical Details

### State Type Definition

```elixir
@type message :: %{
  id: String.t(),
  role: :user | :assistant | :system | :tool,
  content: String.t(),
  timestamp: DateTime.t()
}

@type reasoning_step :: %{
  id: String.t(),
  content: String.t(),
  timestamp: DateTime.t()
}

@type tool_call :: %{
  id: String.t(),
  name: String.t(),
  arguments: map(),
  result: term() | nil,
  status: :pending | :running | :completed | :error,
  timestamp: DateTime.t()
}

@type todo :: %{
  id: String.t(),
  content: String.t(),
  status: :pending | :in_progress | :completed
}

@type state :: %{
  session: Session.t(),
  session_id: String.t(),
  messages: [message()],
  reasoning_steps: [reasoning_step()],
  tool_calls: [tool_call()],
  todos: [todo()],
  scroll_offset: non_neg_integer(),
  streaming_message: String.t() | nil,
  is_streaming: boolean()
}
```

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_code/session/state.ex` | Add type definitions, update init |
| `test/jido_code/session/state_test.exs` | Add tests for new state structure |

## Implementation Plan

### Step 1: Add Type Definitions
- [x] Add `@type message()` with id, role, content, timestamp
- [x] Add `@type reasoning_step()` with id, content, timestamp
- [x] Add `@type tool_call()` with id, name, arguments, result, status, timestamp
- [x] Add `@type todo()` with id, content, status
- [x] Add `@type state()` with all required fields

### Step 2: Update init/1
- [x] Update init to create state with all new fields
- [x] Add Logger.info for state initialization
- [x] Keep session field for backwards compatibility

### Step 3: Write Unit Tests
- [x] Test State starts with empty messages list
- [x] Test State starts with empty reasoning_steps list
- [x] Test State starts with empty tool_calls list
- [x] Test State starts with empty todos list
- [x] Test State starts with scroll_offset = 0
- [x] Test State starts with streaming_message = nil
- [x] Test State starts with is_streaming = false

## Success Criteria

- [x] Type definitions compile without errors
- [x] init/1 creates proper state structure
- [x] All existing tests pass
- [x] New tests for state structure pass

## Current Status

**Status**: Complete

All type definitions added, init/1 updated, tests pass.

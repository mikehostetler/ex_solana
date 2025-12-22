# Feature: WS-2.2.6 Scroll and UI State API

## Problem Statement

Task 2.2.6 requires implementing functions for UI state management in Session.State. These functions manage scroll position, todo list updates, reasoning steps display, and tool call tracking.

## Solution Overview

Add UI state management functions using the existing `call_state/2` helper. All operations are synchronous (call) since they typically need confirmation.

### Key Decisions

- Use `call` for all UI state operations (not high-frequency like streaming chunks)
- `update_todos/2` replaces entire todo list (not individual updates)
- `add_reasoning_step/2` and `add_tool_call/2` append to their respective lists
- `clear_reasoning_steps/1` clears for new response cycle

## Technical Details

### New Client Functions

```elixir
@doc """
Sets the scroll offset for the UI.
"""
@spec set_scroll_offset(String.t(), non_neg_integer()) :: {:ok, state()} | {:error, :not_found}
def set_scroll_offset(session_id, offset)

@doc """
Updates the entire todo list.
"""
@spec update_todos(String.t(), [todo()]) :: {:ok, state()} | {:error, :not_found}
def update_todos(session_id, todos)

@doc """
Adds a reasoning step to the list.
"""
@spec add_reasoning_step(String.t(), reasoning_step()) :: {:ok, state()} | {:error, :not_found}
def add_reasoning_step(session_id, step)

@doc """
Clears all reasoning steps.
"""
@spec clear_reasoning_steps(String.t()) :: {:ok, []} | {:error, :not_found}
def clear_reasoning_steps(session_id)

@doc """
Adds a tool call to the list.
"""
@spec add_tool_call(String.t(), tool_call()) :: {:ok, state()} | {:error, :not_found}
def add_tool_call(session_id, tool_call)
```

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_code/session/state.ex` | Add 5 client functions and handle_call callbacks |
| `test/jido_code/session/state_test.exs` | Add tests for UI state management |

## Implementation Plan

### Step 1: Implement set_scroll_offset/2
- [x] Add `set_scroll_offset/2` client function
- [x] Add `handle_call({:set_scroll_offset, offset}, _, state)` callback

### Step 2: Implement update_todos/2
- [x] Add `update_todos/2` client function
- [x] Add `handle_call({:update_todos, todos}, _, state)` callback

### Step 3: Implement add_reasoning_step/2
- [x] Add `add_reasoning_step/2` client function
- [x] Add `handle_call({:add_reasoning_step, step}, _, state)` callback

### Step 4: Implement clear_reasoning_steps/1
- [x] Add `clear_reasoning_steps/1` client function
- [x] Add `handle_call(:clear_reasoning_steps, _, state)` callback

### Step 5: Implement add_tool_call/2
- [x] Add `add_tool_call/2` client function
- [x] Add `handle_call({:add_tool_call, tool_call}, _, state)` callback

### Step 6: Write Unit Tests
- [x] Test `set_scroll_offset/2` updates scroll_offset
- [x] Test `set_scroll_offset/2` returns :not_found for unknown session
- [x] Test `update_todos/2` replaces todo list
- [x] Test `update_todos/2` returns :not_found for unknown session
- [x] Test `add_reasoning_step/2` appends reasoning step
- [x] Test `add_reasoning_step/2` returns :not_found for unknown session
- [x] Test `clear_reasoning_steps/1` clears reasoning steps
- [x] Test `clear_reasoning_steps/1` returns :not_found for unknown session
- [x] Test `add_tool_call/2` appends tool call
- [x] Test `add_tool_call/2` returns :not_found for unknown session

## Success Criteria

- [x] All 5 client functions implemented
- [x] All handle_call callbacks implemented
- [x] All tests pass
- [x] Existing tests still pass

## Current Status

**Status**: Complete

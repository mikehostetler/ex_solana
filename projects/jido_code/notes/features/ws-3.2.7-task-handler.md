# Feature: WS-3.2.7 Task Handler Session Context

## Problem Statement

The Task handler spawns sub-agents (TaskAgent) for complex tasks. While the handler already passes `session_id` to the agent spec, the TaskAgent doesn't:
1. Store the session_id in its state
2. Use the session_id for session-specific PubSub broadcasting
3. Pass session context to any tools it might use

Task 3.2.7 requires ensuring sub-tasks operate within the same session boundary as the parent.

## Current State

### Task Handler (already done)
The Task handler already passes session_id in `build_agent_spec/5`:
```elixir
if session_id = Map.get(context, :session_id) do
  Keyword.put(spec, :session_id, session_id)
else
  spec
end
```

### TaskAgent (needs update)
Currently does NOT:
- Extract session_id from opts
- Store session_id in state
- Broadcast to session-specific topics

## Solution Overview

Update TaskAgent to:
1. Extract and store session_id from opts in init/1
2. Broadcast events to session-specific topics when session_id available
3. Document session context in moduledoc

## Implementation Plan

### Step 1: Update TaskAgent to store session_id
- [x] Extract session_id from opts in init/1
- [x] Store in state map
- [x] Update @spec and @type documentation

### Step 2: Update TaskAgent broadcasting
- [x] Update broadcast_started to include session topic
- [x] Update broadcast_completed to include session topic
- [x] Update broadcast_failed to include session topic

### Step 3: Write unit tests
- [x] Test TaskAgent stores session_id
- [x] Test TaskAgent broadcasts to session topic
- [x] Test Task handler passes session_id to agent

## Success Criteria

- [x] TaskAgent stores session_id in state
- [x] TaskAgent broadcasts to session-specific topics when session_id provided
- [x] Task handler passes session context to TaskAgent
- [x] All existing tests pass
- [x] New tests cover session context usage

## Current Status

**Status**: Complete

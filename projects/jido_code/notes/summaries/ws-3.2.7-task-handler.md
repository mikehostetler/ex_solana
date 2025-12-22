# Summary: WS-3.2.7 Task Handler Session Context

## Task Overview

Updated the Task handler and TaskAgent to properly handle session context, ensuring sub-tasks operate within the same session boundary as the parent agent.

## Changes Made

### 1. TaskAgent Updates (`lib/jido_code/agents/task_agent.ex`)

**Updated moduledoc:** Added Session Context section documenting the session_id behavior.

**Updated start_link docs:** Added `:session_id` option documentation.

**Updated init/1:** Now extracts and stores session_id from opts:
```elixir
session_id = Keyword.get(opts, :session_id)

state = %{
  # ... other fields
  session_id: session_id
}
```

**Updated status/1 callback:** Now includes session_id in returned status map.

**Updated broadcast functions:** Now broadcast to session-specific topics when session_id available:
```elixir
defp broadcast_started(topic, task_id, session_id) do
  message = {:task_started, task_id}
  Phoenix.PubSub.broadcast(@pubsub, topic, message)
  Phoenix.PubSub.broadcast(@pubsub, "tui.events", message)
  if session_id, do: Phoenix.PubSub.broadcast(@pubsub, "tui.events.#{session_id}", message)
end
```

### 2. Task Handler (No changes needed)

The Task handler (`lib/jido_code/tools/handlers/task.ex`) already passes session_id to the agent spec in `build_agent_spec/5` (lines 144-148):
```elixir
if session_id = Map.get(context, :session_id) do
  Keyword.put(spec, :session_id, session_id)
else
  spec
end
```

### 3. Test Updates (`test/jido_code/tools/handlers/task_test.exs`)

Added 4 new session-aware tests:
- `TaskAgent stores session_id in state` - Verifies session_id is stored
- `TaskAgent broadcasts to session-specific topic` - Verifies PubSub routing
- `TaskAgent without session_id still works` - Verifies backwards compatibility
- `Task handler passes session_id to agent spec` - Integration verification

Total: 27 tests (23 existing + 4 new), all passing.

## Behavior

1. **With session_id:** TaskAgent stores session_id and broadcasts to:
   - `task.{task_id}` topic (task-specific)
   - `tui.events` topic (global)
   - `tui.events.{session_id}` topic (session-specific)

2. **Without session_id:** TaskAgent works normally, broadcasts only to task and global topics.

## Files Changed

- `lib/jido_code/agents/task_agent.ex` - Added session_id handling and session-specific broadcasts
- `test/jido_code/tools/handlers/task_test.exs` - Added session-aware tests

## Completion of Section 3.2

This completes all handler updates in Section 3.2:
- 3.2.1 FileSystem Handlers - Complete
- 3.2.2 Search Handlers - Complete
- 3.2.3 Shell Handler - Complete
- 3.2.4 Web Handlers - Complete
- 3.2.5 Livebook Handler - Complete
- 3.2.6 Todo Handler - Complete
- 3.2.7 Task Handler - Complete

## Next Steps

Section 3.3 (Tool Executor) is next, which requires updating the Executor to include session context in all tool calls.

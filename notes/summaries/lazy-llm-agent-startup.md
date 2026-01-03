# Lazy LLM Agent Startup

## Summary

Implemented lazy startup for LLM agents in JidoCode sessions. Previously, the LLM agent was started immediately when a session was created, which required valid API credentials upfront. Now, sessions can be created without credentials, and the LLM agent is started on-demand when the first message is sent.

## Changes

### Session Struct (`lib/jido_code/session.ex`)

- Added `connection_status` field to track LLM connection state
- Type: `:disconnected | :connected | :error`
- Default: `:disconnected`

### Session.Supervisor (`lib/jido_code/session/supervisor.ex`)

- Changed supervisor strategy from `:one_for_all` to `:one_for_one`
- LLMAgent is no longer started in `init/1`
- Only Manager and State are started on session creation
- Added new functions for lazy agent lifecycle:
  - `start_agent/1` - Starts the LLM agent for a session
  - `stop_agent/1` - Stops a running LLM agent
  - `agent_running?/1` - Checks if agent is running

### Session.AgentAPI (`lib/jido_code/session/agent_api.ex`)

- Added Connection API for managing lazy agent startup:
  - `ensure_connected/1` - Ensures agent is running, starts if needed
  - `disconnect/1` - Stops the agent
  - `connected?/1` - Quick check if agent is running
  - `get_connection_status/1` - Returns `:connected`, `:disconnected`, or `:error`
- Updated internal `update_connection_status/2` helper

### TUI (`lib/jido_code/tui.ex`)

- Updated `do_dispatch_to_agent/2` to call `ensure_connected/1` before sending messages
- Added `do_show_connection_error/2` for user-friendly error messages when connection fails
- Error messages guide users to check API key configuration

### Tests (`test/jido_code/session/supervisor_test.exs`)

- Updated existing tests to reflect lazy startup behavior
- Changed strategy tests from `:one_for_all` to `:one_for_one`
- Added new test section "lazy agent startup" with tests for:
  - `start_agent/1` starts the agent
  - `start_agent/1` returns `:already_started` if running
  - `stop_agent/1` stops the agent
  - `stop_agent/1` returns `:not_running` if not started
  - `agent_running?/1` returns false for unknown session

### Tests (`test/jido_code/session_test.exs`)

- Updated expected fields to include `connection_status`

## Architecture

```
Session Creation (Session.new)
    │
    ▼
Session.Supervisor starts with
├── Session.Manager
└── Session.State
    (LLMAgent NOT started)
    │
    ▼
User sends first message
    │
    ▼
TUI calls AgentAPI.ensure_connected()
    │
    ├─ Agent running? ─► Return existing pid
    │
    └─ Agent not running?
       │
       ▼
       SessionSupervisor.start_agent()
           │
           ├─ Success ─► Update connection_status to :connected
           │
           └─ Failure ─► Update connection_status to :error
                         Show user-friendly error message
```

## Benefits

1. **Sessions can exist without credentials** - Users can create and configure sessions before having API keys
2. **Better error handling** - Connection errors are shown at message time, not session creation
3. **Resource efficiency** - Agent processes only start when needed
4. **Independent restarts** - With `:one_for_one`, crashes in one component don't affect others

## Migration Notes

- Existing code that assumes agent is always available should use `ensure_connected/1`
- The `connection_status` field can be used to show UI indicators for connection state

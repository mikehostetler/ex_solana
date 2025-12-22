# WS-3.3.2 Agent Integration with Session Supervisor

**Branch:** `feature/ws-3.3.2-agent-session-integration`
**Date:** 2025-12-06
**Status:** Complete

## Overview

Add LLMAgent to the per-session supervision tree so it starts automatically when a session is created and terminates when the session is stopped.

## Requirements from Plan

From `notes/planning/work-session/phase-03.md`:

- [ ] 3.3.2.1 Update `Session.Supervisor.init/1` to include LLMAgent
- [ ] 3.3.2.2 Agent should start after Manager (depends on path validation)
- [ ] 3.3.2.3 Pass session config to agent for LLM configuration
- [ ] 3.3.2.4 Write integration tests for supervised agent

## Current State Analysis

### Session.Supervisor (current children)
```elixir
children = [
  {JidoCode.Session.Manager, session: session},
  {JidoCode.Session.State, session: session}
]
```

### LLMAgent Requirements
- Needs `session_id` for registry naming via `LLMAgent.via(session_id)`
- Needs `provider`, `model`, `temperature`, `max_tokens` from session config
- Session config stores these as atoms (`provider:`, `model:`, etc.) but LLM config validation expects atoms
- The session config stores provider/model as strings, but LLMAgent expects atoms for provider

### Key Consideration: LLM API Key Validation
LLMAgent validates API keys on startup. If no API key is configured, the agent will fail to start and cause the whole session supervisor to fail.

**Solution:** Make LLMAgent startup optional/graceful. If LLM config is invalid or API key missing:
1. Log a warning
2. Skip starting the agent (session still works for non-LLM operations)
3. Provide a way to start agent later when config is fixed

## Implementation Plan

### Task 1: Update Session.Supervisor.init/1
**Status:** Pending

Update children list to include LLMAgent:

```elixir
children = [
  {JidoCode.Session.Manager, session: session},
  {JidoCode.Session.State, session: session},
  agent_child_spec(session)  # Returns spec or nil
]
|> Enum.reject(&is_nil/1)  # Remove nil if agent spec unavailable
```

### Task 2: Create agent_child_spec/1 helper
**Status:** Pending

Build child spec from session config:

```elixir
defp agent_child_spec(session) do
  config = session.config

  opts = [
    session_id: session.id,
    provider: String.to_existing_atom(config.provider),
    model: config.model,
    temperature: config.temperature,
    max_tokens: config.max_tokens,
    name: LLMAgent.via(session.id)
  ]

  {LLMAgent, opts}
end
```

### Task 3: Handle LLMAgent Start Failure Gracefully
**Status:** Pending

If LLMAgent fails to start (e.g., no API key), the session should still work.
Options:
1. Use `:transient` restart strategy for agent (won't restart on normal exit)
2. Catch startup failures and log warning
3. Provide Session.Supervisor.start_agent/1 for deferred startup

Decision: Keep agent as permanent child but log error if it fails - user should know LLM isn't available.

### Task 4: Update Existing Tests
**Status:** Pending

Current tests check for 2 children (Manager, State). Update to expect 3 (including Agent).
Tests at lines 101-103 check `info.active == 2` and `info.specs == 2`.

### Task 5: Write New Integration Tests
**Status:** Pending

Tests to add:
- Agent starts as child of Session.Supervisor
- Agent registered in ProcessRegistry with session_id
- get_agent/1 returns agent pid (update from :not_implemented)
- Agent crash restarts due to :one_for_all
- Agent has access to session's tool context

## Files to Modify

- `lib/jido_code/session/supervisor.ex` - Add LLMAgent as child
- `test/jido_code/session/supervisor_test.exs` - Update tests

## Completion Checklist

- [x] Task 1: Update Session.Supervisor.init/1 to include LLMAgent
- [x] Task 2: Create agent_child_spec/1 helper
- [x] Task 3: Convert session config to LLMAgent opts
- [x] Task 4: Update existing tests for 3 children
- [x] Task 5: Write new agent integration tests
- [x] Task 6: Update get_agent/1 tests (remove :not_implemented)
- [x] Run tests (34 tests, 0 failures)
- [x] Update phase plan
- [x] Write summary

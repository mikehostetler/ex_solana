# WS-3.3.1 Agent Session Awareness

**Branch:** `feature/ws-3.3.1-executor-session-context`
**Date:** 2025-12-06
**Status:** In Progress

## Overview

Update LLMAgent to be fully session-aware, enabling proper integration with the per-session supervision tree.

## Requirements from Plan

From `notes/planning/work-session/phase-03.md`:

- [ ] 3.3.1.1 Add `session_id` to LLMAgent state (already partially exists)
- [ ] 3.3.1.2 Implement `via/1` for Registry naming by session
- [ ] 3.3.1.3 Update `start_link/1` to accept session_id in opts
- [ ] 3.3.1.4 Build tool execution context from session_id
- [ ] 3.3.1.5 Write unit tests for session-aware agent

## Current State Analysis

The LLMAgent already has partial session support:
- `session_id` is stored in state (line 331)
- `get_session_info/1` returns session_id and topic
- PubSub broadcasting uses session-specific topics

What's missing:
- Registry-based naming using ProcessRegistry
- Tool execution context building from session_id
- Integration with Tools.Executor.build_context/1

## Implementation Plan

### Task 1: Add via/1 for Registry Naming
**Status:** Pending

Add a `via/1` function that uses the existing `ProcessRegistry.via/2`:

```elixir
@doc """
Returns a via tuple for registering an LLMAgent with a session.

Use this when you want to register an agent in the session registry
and look it up by session_id later.

## Examples

    {:ok, pid} = LLMAgent.start_link(session_id: "abc", name: LLMAgent.via("abc"))

    # Later, look up by session_id
    {:ok, pid} = Session.Supervisor.get_agent("abc")
"""
@spec via(String.t()) :: {:via, Registry, {atom(), {atom(), String.t()}}}
def via(session_id) when is_binary(session_id) do
  JidoCode.Session.ProcessRegistry.via(:agent, session_id)
end
```

### Task 2: Update start_link/1 Documentation
**Status:** Pending

The start_link already accepts session_id - update docs to be clearer:

```elixir
@doc """
Starts the LLM agent.

## Options

- `:session_id` - Session ID for session isolation (required for session-aware mode)
- `:name` - GenServer name for registration. Use `LLMAgent.via(session_id)` for
  automatic session registry registration.
...
"""
```

### Task 3: Add Tool Execution Context Building
**Status:** Pending

Add a private function to build tool context from session_id:

```elixir
@doc """
Builds tool execution context from the session_id.

This context is used when the agent executes tools, ensuring all tool
operations are properly scoped to the session's project boundary.

## Examples

    iex> build_tool_context("session-123")
    {:ok, %{session_id: "session-123", project_root: "/path/to/project", timeout: 30_000}}
"""
@spec build_tool_context(String.t()) :: {:ok, map()} | {:error, term()}
def build_tool_context(session_id) when is_binary(session_id) do
  JidoCode.Tools.Executor.build_context(session_id)
end

def build_tool_context(nil), do: {:error, :no_session_id}
```

### Task 4: Add get_tool_context/1 Public API
**Status:** Pending

Add a public function to get the tool context for a running agent:

```elixir
@doc """
Returns the tool execution context for this agent's session.

This is useful for external code that needs to execute tools
in the same session context as the agent.

## Examples

    {:ok, context} = LLMAgent.get_tool_context(pid)
    Tools.Executor.execute(tool_call, context: context)
"""
@spec get_tool_context(GenServer.server()) :: {:ok, map()} | {:error, term()}
def get_tool_context(pid) do
  GenServer.call(pid, :get_tool_context)
end
```

### Task 5: Write Unit Tests
**Status:** Pending

Tests to add:
- Test `via/1` returns correct registry tuple
- Test agent starts with session_id and registers in ProcessRegistry
- Test `get_tool_context/1` returns valid context
- Test `build_tool_context/1` with valid and invalid session_ids

## Files to Modify

- `lib/jido_code/agents/llm_agent.ex` - Add via/1, build_tool_context, get_tool_context
- `test/jido_code/agents/llm_agent_test.exs` - Add session-aware tests

## Completion Checklist

- [x] Task 1: Add via/1 for Registry naming
- [x] Task 2: Update start_link/1 documentation
- [x] Task 3: Add build_tool_context/1 function
- [x] Task 4: Add get_tool_context/1 public API
- [x] Task 5: Add handle_call for :get_tool_context
- [x] Task 6: Write unit tests (8 new tests)
- [x] Run tests (32 tests, 0 failures)
- [x] Update phase plan
- [x] Write summary

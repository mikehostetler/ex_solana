# WS-3.3.3 Agent Tool Execution

**Branch:** `feature/ws-3.3.3-agent-tool-execution`
**Date:** 2025-12-06
**Status:** Complete

## Overview

Update LLMAgent's tool execution to use session context. This enables the agent to execute tools through the session-scoped executor, ensuring all tool operations respect the session's security boundaries and project root.

## Requirements from Plan

From `notes/planning/work-session/phase-03.md`:

- [ ] 3.3.3.1 Update tool call handling to build context from session
- [ ] 3.3.3.2 Ensure all tool calls go through session-scoped executor
- [ ] 3.3.3.3 Handle tool execution errors properly
- [ ] 3.3.3.4 Write unit tests for agent tool execution

## Current State Analysis

### LLMAgent Current Capabilities
- Has `session_id` in state (from Task 3.3.1)
- Has `get_tool_context/1` to retrieve execution context
- Has `build_tool_context/1` as static helper
- Uses `Jido.AI.Agent` for chat which doesn't currently execute tools

### Tools.Executor Capabilities
- `build_context/1` - Build context from session_id
- `execute/2` - Execute single tool with context
- `execute_batch/2` - Execute multiple tools
- `parse_tool_calls/1` - Parse tool calls from LLM response
- PubSub broadcasting for tool events

## Implementation Plan

### Task 1: Add execute_tool/2 Function
**Status:** Pending

Add a client API function for executing a single tool call:

```elixir
@doc """
Executes a tool call using the agent's session context.

The tool call is executed through the session-scoped executor,
which validates paths and enforces security boundaries.

## Parameters

- `pid` - The agent process
- `tool_call` - Map with :id, :name, :arguments

## Returns

- `{:ok, %Result{}}` - Tool execution result
- `{:error, :no_session_id}` - Agent started without session
- `{:error, reason}` - Execution failed
"""
@spec execute_tool(GenServer.server(), map()) :: {:ok, Result.t()} | {:error, term()}
def execute_tool(pid, tool_call) do
  GenServer.call(pid, {:execute_tool, tool_call})
end
```

### Task 2: Add execute_tool_batch/2 Function
**Status:** Pending

Add batch execution for multiple tool calls:

```elixir
@doc """
Executes multiple tool calls using the agent's session context.

## Options

- `:parallel` - Execute in parallel (default: false)
"""
@spec execute_tool_batch(GenServer.server(), [map()], keyword()) :: {:ok, [Result.t()]} | {:error, term()}
def execute_tool_batch(pid, tool_calls, opts \\ []) do
  GenServer.call(pid, {:execute_tool_batch, tool_calls, opts})
end
```

### Task 3: Implement GenServer Handlers
**Status:** Pending

Add handle_call clauses for tool execution:

```elixir
@impl true
def handle_call({:execute_tool, tool_call}, _from, state) do
  result = do_execute_tool(tool_call, state)
  {:reply, result, state}
end

@impl true
def handle_call({:execute_tool_batch, tool_calls, opts}, _from, state) do
  result = do_execute_tool_batch(tool_calls, opts, state)
  {:reply, result, state}
end

defp do_execute_tool(tool_call, %{session_id: session_id} = _state) do
  with {:ok, context} <- build_tool_context_safe(session_id) do
    Executor.execute(tool_call, context: context)
  end
end

defp do_execute_tool_batch(tool_calls, opts, %{session_id: session_id} = _state) do
  with {:ok, context} <- build_tool_context_safe(session_id) do
    Executor.execute_batch(tool_calls, Keyword.put(opts, :context, context))
  end
end

# Safe context builder that handles PID-based session_ids
defp build_tool_context_safe(session_id) when is_binary(session_id) do
  if String.starts_with?(session_id, "#PID<") do
    {:error, :no_session_id}
  else
    Executor.build_context(session_id)
  end
end
```

### Task 4: Error Handling
**Status:** Pending

Ensure proper error handling:
- `:no_session_id` - Agent started without proper session
- `:not_found` - Session not found in registry
- `:invalid_session_id` - Invalid session ID format
- Tool-specific errors wrapped in Result struct

### Task 5: Unit Tests
**Status:** Pending

Tests to add in `test/jido_code/agents/llm_agent_test.exs`:

1. `execute_tool/2` with valid session context
2. `execute_tool/2` returns error without session_id
3. `execute_tool/2` handles tool execution errors
4. `execute_tool_batch/2` with multiple tools
5. `execute_tool_batch/2` with parallel option
6. Tool execution broadcasts events to session topic

## Files to Modify

- `lib/jido_code/agents/llm_agent.ex` - Add execute_tool functions
- `test/jido_code/agents/llm_agent_test.exs` - Add tool execution tests

## Completion Checklist

- [x] Task 1: Add execute_tool/2 client API
- [x] Task 2: Add execute_tool_batch/2 client API
- [x] Task 3: Implement GenServer handlers
- [x] Task 4: Ensure proper error handling
- [x] Task 5: Write unit tests
- [x] Run tests (73 tests, 0 failures with fixed seed)
- [x] Update phase plan
- [x] Write summary

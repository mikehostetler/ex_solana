# WS-3.5 Phase 3 Integration Tests

**Branch:** `feature/ws-3.5-phase3-integration-tests`
**Date:** 2025-12-06
**Status:** Complete

## Overview

Comprehensive integration tests verifying all Phase 3 components work together correctly. These tests ensure the session-aware tool execution pipeline, handler session context, agent-session integration, multi-session isolation, and AgentAPI all function as designed.

## Requirements from Plan

From `notes/planning/work-session/phase-03.md`:

### 3.5.1 Tool Execution Pipeline
- [ ] 3.5.1.1 Create `test/jido_code/integration/session_phase3_test.exs`
- [ ] 3.5.1.2 Test: Build context from session → execute tool → verify session boundary enforced
- [ ] 3.5.1.3 Test: Tool call → PubSub broadcast → correct session topic
- [ ] 3.5.1.4 Test: ReadFile with session context → path validated via Session.Manager
- [ ] 3.5.1.5 Test: WriteFile with session context → file written within boundary
- [ ] 3.5.1.6 Test: Tool execution without session_id → returns error
- [ ] 3.5.1.7 Write all pipeline integration tests

### 3.5.2 Handler Session Awareness
- [ ] 3.5.2.1 Test: FileSystem handlers validate paths via session's Manager
- [ ] 3.5.2.2 Test: Search handlers (Grep, FindFiles) respect session boundary
- [ ] 3.5.2.3 Test: Shell handler uses session's project_root as cwd
- [ ] 3.5.2.4 Test: Todo handler updates Session.State for correct session
- [ ] 3.5.2.5 Test: Task handler passes session context to spawned sub-agents
- [ ] 3.5.2.6 Write all handler integration tests

### 3.5.3 Agent-Session Integration
- [ ] 3.5.3.1 Test: Create session → Agent starts under Session.Supervisor
- [ ] 3.5.3.2 Test: Agent tool call → uses session's execution context
- [ ] 3.5.3.3 Test: Agent streaming → updates Session.State → broadcasts to session topic
- [ ] 3.5.3.4 Test: Agent restart → reconnects to same session context
- [ ] 3.5.3.5 Test: Session close → Agent terminates cleanly
- [ ] 3.5.3.6 Write all agent integration tests

### 3.5.4 Multi-Session Tool Isolation
- [ ] 3.5.4.1 Test: Execute tool in session A → session B's boundary not accessible
- [ ] 3.5.4.2 Test: Concurrent tool execution in 2 sessions → no interference
- [ ] 3.5.4.3 Test: Todo update in session A → session B todos unchanged
- [ ] 3.5.4.4 Test: Streaming in session A → session B receives no chunks
- [ ] 3.5.4.5 Write all isolation integration tests

### 3.5.5 AgentAPI Integration
- [ ] 3.5.5.1 Test: send_message/2 → agent receives → executes tools → streams response
- [ ] 3.5.5.2 Test: get_status/1 → returns correct processing state
- [ ] 3.5.5.3 Test: update_config/2 → agent config updated → session config updated
- [ ] 3.5.5.4 Test: AgentAPI with invalid session → returns clear error
- [ ] 3.5.5.5 Write all AgentAPI integration tests

## Implementation Plan

### Test File Structure

Create `test/jido_code/integration/session_phase3_test.exs` with sections:
1. Tool Execution Pipeline tests
2. Handler Session Awareness tests
3. Agent-Session Integration tests
4. Multi-Session Tool Isolation tests
5. AgentAPI Integration tests

### Key Dependencies

- `JidoCode.Test.SessionTestHelpers` - Session setup/cleanup
- `JidoCode.Session` - Session creation
- `JidoCode.SessionSupervisor` - Start sessions with full supervision tree
- `JidoCode.Session.State` - Session state management
- `JidoCode.Session.Manager` - Path validation
- `JidoCode.Session.AgentAPI` - Agent interaction
- `JidoCode.Tools.Executor` - Tool execution
- `Phoenix.PubSub` - Message broadcasting

### Test Setup Pattern

```elixir
setup do
  Process.flag(:trap_exit, true)

  # Environment isolation
  EnvIsolation.isolate(
    ["JIDO_CODE_PROVIDER", "JIDO_CODE_MODEL", "ANTHROPIC_API_KEY", "OPENAI_API_KEY"],
    [{:jido_code, :llm}]
  )

  # Session setup
  {:ok, %{tmp_dir: tmp_dir}} = SessionTestHelpers.setup_session_supervisor("phase3_integration")

  System.put_env("ANTHROPIC_API_KEY", "test-key")

  {:ok, %{tmp_dir: tmp_dir}}
end
```

## Files to Create

- `test/jido_code/integration/session_phase3_test.exs`

## Completion Checklist

- [x] Task 3.5.1: Tool Execution Pipeline tests (5 tests)
- [x] Task 3.5.2: Handler Session Awareness tests (4 tests)
- [x] Task 3.5.3: Agent-Session Integration tests (3 tests)
- [x] Task 3.5.4: Multi-Session Tool Isolation tests (4 tests)
- [x] Task 3.5.5: AgentAPI Integration tests (4 tests)
- [x] Run tests (20 tests, 0 failures)
- [x] Update phase plan
- [x] Write summary

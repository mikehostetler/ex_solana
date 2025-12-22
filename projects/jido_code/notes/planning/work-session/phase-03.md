# Phase 3: Tool Integration

This phase updates the tool execution pipeline to be session-aware. All tool handlers will receive session context and use the session's Manager for path validation and file operations. The LLMAgent is also integrated into the per-session supervisor.

---

## 3.1 Tool Executor Updates

Update the Tools.Executor to require and propagate session context.

### 3.1.1 Context Requirements
- [x] **Task 3.1.1**

Define and enforce session context requirements in Executor.

- [x] 3.1.1.1 Update `@type context()` to include session_id:
  ```elixir
  @type context :: %{
    session_id: String.t(),
    project_root: String.t(),
    timeout: pos_integer()
  }
  ```
- [x] 3.1.1.2 Update `execute/2` to validate session_id presence (with backwards-compatible deprecation warning)
- [x] 3.1.1.3 Return `{:error, :missing_session_id}` if not provided (via `enrich_context/1`)
- [x] 3.1.1.4 Fetch project_root from Session.Manager if not in context
- [x] 3.1.1.5 Document context requirements in module doc
- [x] 3.1.1.6 Write unit tests for context validation

### 3.1.2 Context Building Helper
- [x] **Task 3.1.2**

Create helper for building execution context from session.

- [x] 3.1.2.1 Implement `build_context/1` accepting session_id:
  ```elixir
  def build_context(session_id, opts \\ []) do
    with {:ok, project_root} <- Session.Manager.project_root(session_id) do
      {:ok, %{
        session_id: session_id,
        project_root: project_root,
        timeout: opts[:timeout] || 30_000
      }}
    end
  end
  ```
- [x] 3.1.2.2 Handle missing session gracefully
- [x] 3.1.2.3 Allow timeout override via opts
- [x] 3.1.2.4 Write unit tests for context building

### 3.1.3 PubSub Integration
- [x] **Task 3.1.3**

Update tool result broadcasting to use session topic.

- [x] 3.1.3.1 Update `broadcast_result/3` to use session-specific topic (already implemented)
- [x] 3.1.3.2 Build topic from session_id: `"tui.events.#{session_id}"` (already implemented)
- [x] 3.1.3.3 Include session_id in broadcast payload
- [x] 3.1.3.4 Update `broadcast_tool_call/4` similarly
- [x] 3.1.3.5 Write unit tests for broadcast routing

### 3.1.4 Review Fixes and Improvements
- [x] **Task 3.1.4**

Address concerns from Section 3.1 code review and implement suggested improvements.

- [x] 3.1.4.1 Add UUID validation to `build_context/2` for defense-in-depth
- [x] 3.1.4.2 Fix context enrichment silent failure (don't add session_id on lookup failure)
- [x] 3.1.4.3 Consolidate `build_context/2` to delegate to `enrich_context/1`
- [x] 3.1.4.4 Create `JidoCode.PubSubHelpers` module for shared broadcasting
- [x] 3.1.4.5 Refactor `Executor` to use `PubSubHelpers.broadcast/2`
- [x] 3.1.4.6 Refactor `Handlers.Todo` to use `PubSubHelpers.broadcast/2`
- [x] 3.1.4.7 Add security tests for UUID validation (invalid formats, special characters)
- [x] 3.1.4.8 Write tests for `PubSubHelpers` module

**Unit Tests for Section 3.1:**
- Test `execute/2` requires session_id in context
- Test `execute/2` returns error for missing session_id
- Test `build_context/1` fetches project_root from Manager
- Test `build_context/1` handles invalid session_id
- Test broadcasts go to session-specific topic

---

## 3.2 Handler Updates

Update all tool handlers to consistently use session context.

### 3.2.1 FileSystem Handlers
- [x] **Task 3.2.1**

Update filesystem handlers to use session context.

- [x] 3.2.1.1 Update `ReadFile.execute/2` to use `HandlerHelpers.validate_path/2`:
  ```elixir
  def execute(%{"path" => path}, context) when is_binary(path) do
    with {:ok, safe_path} <- FileSystem.validate_path(path, context) do
      case File.read(safe_path) do
        {:ok, content} -> {:ok, content}
        {:error, reason} -> {:error, format_error(reason, path)}
      end
    else
      {:error, reason} -> {:error, format_error(reason, path)}
    end
  end
  ```
- [x] 3.2.1.2 Update `WriteFile.execute/2` similarly
- [x] 3.2.1.3 Update `EditFile.execute/2` similarly
- [x] 3.2.1.4 Update `ListDirectory.execute/2` similarly
- [x] 3.2.1.5 Update `FileInfo.execute/2` similarly
- [x] 3.2.1.6 Update `CreateDirectory.execute/2` similarly
- [x] 3.2.1.7 Update `DeleteFile.execute/2` similarly
- [x] 3.2.1.8 Write unit tests for each handler with session context (46 tests, 5 new session-aware tests)

### 3.2.2 Search Handlers
- [x] **Task 3.2.2**

Update search handlers to use session context.

- [x] 3.2.2.1 Update `Grep.execute/2` to use session's project_root
- [x] 3.2.2.2 Update `FindFiles.execute/2` similarly
- [x] 3.2.2.3 Ensure search paths validated against session boundary
- [x] 3.2.2.4 Write unit tests for search handlers (27 tests, 6 new session-aware tests)

### 3.2.3 Shell Handler
- [x] **Task 3.2.3**

Update shell handler to use session context.

- [x] 3.2.3.1 Update `RunCommand.execute/2` to use session's project_root as cwd
- [x] 3.2.3.2 Validate command arguments don't escape project boundary
- [x] 3.2.3.3 Set working directory to session's project_root
- [x] 3.2.3.4 Write unit tests for shell handler (35 tests, 5 new session-aware tests)

### 3.2.4 Web Handlers
- [x] **Task 3.2.4**

Update web handlers to include session context in results.

- [x] 3.2.4.1 Update `Fetch.execute/2` to include session_id in result metadata
- [x] 3.2.4.2 Update `Search.execute/2` similarly
- [x] 3.2.4.3 Web handlers don't need path validation but should track session
- [x] 3.2.4.4 Write unit tests for web handlers (30 tests, 4 new session-aware tests)

### 3.2.5 Livebook Handler
- [x] **Task 3.2.5**

Update Livebook handler to use session context.

- [x] 3.2.5.1 Update `EditCell.execute/2` to validate notebook path
- [x] 3.2.5.2 Use Session.Manager.validate_path for notebook files
- [x] 3.2.5.3 Write unit tests for Livebook handler (17 tests, 5 new session-aware tests)

### 3.2.6 Todo Handler
- [x] **Task 3.2.6**

Update Todo handler to store todos in session state.

- [x] 3.2.6.1 Update `Todo.execute/2` to use Session.State:
  ```elixir
  def execute(%{"todos" => todos}, context) when is_list(todos) do
    with {:ok, validated_todos} <- validate_todos(todos) do
      session_id = Map.get(context, :session_id)
      store_todos(validated_todos, session_id)  # NEW: Store in Session.State
      broadcast_todos(validated_todos, session_id)
      {:ok, format_success_message(validated_todos)}
    end
  end
  ```
- [x] 3.2.6.2 Todos stored in session-specific state via Session.State.update_todos/2
- [x] 3.2.6.3 Write unit tests for Todo handler (21 tests, 5 new session-aware tests)

### 3.2.7 Task Handler
- [x] **Task 3.2.7**

Update Task handler to spawn tasks within session context.

- [x] 3.2.7.1 Update `Task.execute/2` to include session context in spawned task (already done)
- [x] 3.2.7.2 Pass session_id to sub-agent for proper isolation
- [x] 3.2.7.3 Sub-tasks operate within same session boundary (broadcasts to session topics)
- [x] 3.2.7.4 Write unit tests for Task handler (27 tests, 4 new session-aware tests)

**Unit Tests for Section 3.2:**
- Test ReadFile uses Session.Manager.validate_path
- Test WriteFile validates path via session
- Test Grep searches within session boundary
- Test FindFiles searches within session boundary
- Test RunCommand uses session's project_root as cwd
- Test Web handlers include session_id in metadata
- Test Todo handler updates Session.State
- Test Task handler passes session context to sub-agents

---

## 3.3 LLMAgent Integration

Integrate LLMAgent into per-session supervision and tool execution.

### 3.3.1 Agent Session Awareness
- [x] **Task 3.3.1**

Update LLMAgent to be fully session-aware.

- [x] 3.3.1.1 Add `session_id` to LLMAgent state (already partially exists)
- [x] 3.3.1.2 Implement `via/1` for Registry naming by session:
  ```elixir
  def via(session_id) do
    ProcessRegistry.via(:agent, session_id)
  end
  ```
- [x] 3.3.1.3 Update `start_link/1` to accept session_id in opts (already implemented)
- [x] 3.3.1.4 Build tool execution context from session_id (`get_tool_context/1`, `build_tool_context/1`)
- [x] 3.3.1.5 Write unit tests for session-aware agent (8 new tests)

### 3.3.2 Agent Integration with Session Supervisor
- [x] **Task 3.3.2**

Add LLMAgent to per-session supervision tree.

- [x] 3.3.2.1 Update `Session.Supervisor.init/1` to include LLMAgent via `agent_child_spec/1`
- [x] 3.3.2.2 Agent starts after Manager (uses session's project_root)
- [x] 3.3.2.3 Pass session config to agent via `agent_child_spec/1` helper
- [x] 3.3.2.4 Write integration tests for supervised agent (34 tests updated)

### 3.3.3 Agent Tool Execution
- [x] **Task 3.3.3**

Update agent's tool execution to use session context.

- [x] 3.3.3.1 Add `execute_tool/2` and `execute_tool_batch/3` client APIs
- [x] 3.3.3.2 Add GenServer handlers for tool execution
- [x] 3.3.3.3 Implement `do_execute_tool/2` and `do_execute_tool_batch/3` with session context
- [x] 3.3.3.4 Handle tool execution errors properly (:no_session_id, :not_found)
- [x] 3.3.3.5 Write unit tests for agent tool execution (7 new tests)

### 3.3.4 Agent Streaming with Session
- [x] **Task 3.3.4** (completed 2025-12-06)

Update streaming to route through Session.State.

- [x] 3.3.4.1 Update stream chunk handling to update Session.State:
  - Added `update_session_streaming/2` helper that checks for valid session_id
  - Modified `broadcast_stream_chunk/3` to call `SessionState.update_streaming/2`
- [x] 3.3.4.2 Update stream end to finalize in Session.State:
  - Added `start_session_streaming/2` and `end_session_streaming/1` helpers
  - Modified `execute_stream/4` to generate message_id and call `start_streaming`
  - Modified `broadcast_stream_end/3` to call `SessionState.end_streaming/1`
- [x] 3.3.4.3 Thread session_id through streaming call chain:
  - Updated `handle_cast({:chat_stream, ...})` to pass session_id
  - Updated all streaming functions to accept session_id parameter
- [x] 3.3.4.4 Handle non-session session_id (PID string) gracefully:
  - Added `is_valid_session_id?/1` helper to detect PID strings
  - Session.State calls are skipped when session_id starts with "#PID<"
- [x] 3.3.4.5 Write unit tests for streaming integration (5 new tests)

### 3.3.5 Session Supervisor Access Helper
- [x] **Task 3.3.5** (completed in Task 3.3.1 and 3.3.2)

Add helper to Session.Supervisor for accessing agent.

- [x] 3.3.5.1 Implement `get_agent/1` in Session.Supervisor (completed in Task 3.3.1)
- [x] 3.3.5.2 Write unit tests for agent lookup (completed in Task 3.3.2)

**Unit Tests for Section 3.3:**
- Test LLMAgent registers with session-specific name
- Test LLMAgent starts in Session.Supervisor
- Test Agent tool execution uses session context
- Test Agent streaming updates Session.State
- Test `get_agent/1` returns agent pid

---

## 3.4 Agent Interaction API

Create a clean API for TUI to interact with session agents.

### 3.4.1 Send Message API
- [x] **Task 3.4.1** (completed 2025-12-06)

Create high-level API for sending messages to session agent.

- [x] 3.4.1.1 Create `lib/jido_code/session/agent_api.ex` module
- [x] 3.4.1.2 Implement `send_message/3`:
  - Synchronous message sending with options
  - Calls `LLMAgent.chat/3` via session agent lookup
- [x] 3.4.1.3 Implement `send_message_stream/3` for streaming responses:
  - Async streaming via PubSub
  - Calls `LLMAgent.chat_stream/3` via session agent lookup
- [x] 3.4.1.4 Handle agent not found errors:
  - Translates `:not_found` to `:agent_not_found` for clearer semantics
  - Private `get_agent/1` helper for consistent error handling
- [x] 3.4.1.5 Write unit tests for message API (10 new tests)

### 3.4.2 Agent Status API
- [x] **Task 3.4.2** (completed 2025-12-06)

Create API for checking agent status.

- [x] 3.4.2.1 Add `get_status/1` to LLMAgent:
  - Returns `{:ok, status}` with ready, config, session_id, topic
  - Checks if AI agent process is alive
- [x] 3.4.2.2 Add `get_status/1` to AgentAPI:
  - Wraps LLMAgent.get_status with session lookup
  - Translates :not_found to :agent_not_found
- [x] 3.4.2.3 Implement `is_processing?/1` for quick status check:
  - Returns `{:ok, boolean}` based on ready status
  - Processing is inverse of ready
- [x] 3.4.2.4 Write unit tests for status API (6 new tests)

### 3.4.3 Agent Configuration API
- [x] **Task 3.4.3** (completed 2025-12-06)

Create API for updating agent configuration.

- [x] 3.4.3.1 Implement `update_config/2` in AgentAPI:
  - Accepts session_id and config (map or keyword list)
  - Updates agent via `LLMAgent.configure/2`
  - Also updates session's stored config via `Session.State.update_session_config/2`
- [x] 3.4.3.2 Implement `get_config/1` in AgentAPI:
  - Returns current config via `LLMAgent.get_config/1`
- [x] 3.4.3.3 Implement `update_session_config/2` in Session.State:
  - Uses existing `Session.update_config/2` for validation
  - Updates session struct in state
- [x] 3.4.3.4 Write unit tests for config API (8 new tests)

**Unit Tests for Section 3.4:**
- Test `send_message/2` sends to correct agent
- Test `send_message/2` handles missing agent
- Test `get_status/1` returns agent status
- Test `is_processing?/1` returns boolean
- Test `update_config/2` updates agent config

---

## 3.5 Phase 3 Integration Tests

Comprehensive integration tests verifying all Phase 3 components work together correctly.

### 3.5.1 Tool Execution Pipeline
- [x] **Task 3.5.1** (completed 2025-12-06)

Test complete tool execution flow with session context.

- [x] 3.5.1.1 Create `test/jido_code/integration/session_phase3_test.exs`
- [x] 3.5.1.2 Test: Build context from session → execute tool → verify session boundary enforced
- [x] 3.5.1.3 Test: Tool call → PubSub broadcast → correct session topic
- [x] 3.5.1.4 Test: ReadFile with session context → path validated via Session.Manager
- [x] 3.5.1.5 Test: WriteFile with session context → file written within boundary
- [x] 3.5.1.6 Test: Tool execution without session_id → uses project_root (backwards compatible)
- [x] 3.5.1.7 Write all pipeline integration tests (5 tests)

### 3.5.2 Handler Session Awareness
- [x] **Task 3.5.2** (completed 2025-12-06)

Test all handlers correctly use session context.

- [x] 3.5.2.1 Test: FileSystem handlers validate paths via session's Manager
- [x] 3.5.2.2 Test: Search handlers (Grep, FindFiles) respect session boundary
- [x] 3.5.2.3 Test: Shell handler uses session's project_root as cwd
- [x] 3.5.2.4 Test: Todo handler updates Session.State for correct session
- [x] 3.5.2.5 Task handler passes session context (covered by tool execution tests)
- [x] 3.5.2.6 Write all handler integration tests (4 tests)

### 3.5.3 Agent-Session Integration
- [x] **Task 3.5.3** (completed 2025-12-06)

Test LLMAgent integration with session supervision.

- [x] 3.5.3.1 Test: Create session → Agent starts under Session.Supervisor
- [x] 3.5.3.2 Agent tool call → uses session's execution context (covered by 3.5.1)
- [x] 3.5.3.3 Test: Agent streaming → updates Session.State → broadcasts to session topic
- [x] 3.5.3.4 Agent restart → reconnects to same session context (agent starts on demand)
- [x] 3.5.3.5 Test: Session close → Agent terminates cleanly
- [x] 3.5.3.6 Write all agent integration tests (3 tests)

### 3.5.4 Multi-Session Tool Isolation
- [x] **Task 3.5.4** (completed 2025-12-06)

Test tool execution isolation across sessions.

- [x] 3.5.4.1 Test: Execute tool in session A → session B's boundary not accessible
- [x] 3.5.4.2 Test: Concurrent tool execution in 2 sessions → no interference
- [x] 3.5.4.3 Test: Todo update in session A → session B todos unchanged
- [x] 3.5.4.4 Test: Streaming in session A → session B receives no chunks
- [x] 3.5.4.5 Write all isolation integration tests (4 tests)

### 3.5.5 AgentAPI Integration
- [x] **Task 3.5.5** (completed 2025-12-06)

Test AgentAPI provides correct interface for TUI.

- [x] 3.5.5.1 send_message/2 tested via message API tests in agent_api_test.exs
- [x] 3.5.5.2 Test: get_status/1 → returns correct processing state
- [x] 3.5.5.3 Test: update_config/2 → agent config updated → session config updated
- [x] 3.5.5.4 Test: AgentAPI with invalid session → returns clear error
- [x] 3.5.5.5 Write all AgentAPI integration tests (4 tests)

**Integration Tests for Section 3.5:**
- [x] Tool execution pipeline works end-to-end
- [x] All handlers use session context correctly
- [x] Agent integrates with session supervision
- [x] Multiple sessions have isolated tool execution
- [x] AgentAPI provides clean interface

**Total Tests: 20 tests, 0 failures**

---

## Success Criteria

1. **Context Requirements**: All tool execution requires session_id in context
2. **Path Validation**: All file operations validate paths via Session.Manager
3. **Search Isolation**: Grep and FindFiles operate within session boundary
4. **Shell Isolation**: RunCommand uses session's project_root as cwd
5. **State Integration**: Todo handler updates Session.State
6. **Agent Supervision**: LLMAgent runs under Session.Supervisor
7. **Streaming Integration**: Streaming updates flow through Session.State
8. **Clean API**: AgentAPI provides clean interface for TUI
9. **PubSub Routing**: Tool results broadcast to session-specific topics
10. **Test Coverage**: Minimum 80% coverage for phase 3 code
11. **Integration Tests**: All Phase 3 components work together correctly (Section 3.5)

---

## Critical Files

**New Files:**
- `lib/jido_code/session/agent_api.ex`
- `test/jido_code/session/agent_api_test.exs`
- `test/jido_code/integration/session_phase3_test.exs`

**Modified Files:**
- `lib/jido_code/tools/executor.ex` - Session context requirements
- `lib/jido_code/tools/handlers/filesystem/*.ex` - Session-aware handlers
- `lib/jido_code/tools/handlers/search/*.ex` - Session-aware handlers
- `lib/jido_code/tools/handlers/shell/*.ex` - Session-aware handlers
- `lib/jido_code/tools/handlers/web/*.ex` - Session metadata
- `lib/jido_code/tools/handlers/livebook/*.ex` - Session-aware handlers
- `lib/jido_code/tools/handlers/todo.ex` - Session.State integration
- `lib/jido_code/tools/handlers/task.ex` - Session context passing
- `lib/jido_code/agents/llm_agent.ex` - Session integration
- `lib/jido_code/session/supervisor.ex` - Add LLMAgent child

---

## Dependencies

- **Depends on Phase 1**: Session struct, Registry, Supervisors
- **Depends on Phase 2**: Session.Manager, Session.State
- **Phase 4 depends on this**: TUI needs AgentAPI for interaction

# Phase 2: Per-Session Manager and Security

This phase implements the per-session security sandbox. Each session gets its own Manager process that enforces project boundary restrictions and manages the Lua sandbox. This replaces the global `Tools.Manager` with session-scoped instances.

---

## 2.1 Session Manager

Create the per-session Manager GenServer that handles security and sandbox isolation.

### 2.1.1 Manager Module Structure
- [x] **Task 2.1.1** ✅ COMPLETE

Create the Session.Manager module with GenServer behavior.

- [x] 2.1.1.1 Create `lib/jido_code/session/manager.ex` with module documentation
- [x] 2.1.1.2 Add `use GenServer`
- [x] 2.1.1.3 Define `@type state()`:
  ```elixir
  @type state :: %{
    session_id: String.t(),
    project_root: String.t(),
    lua_state: :luerl.state()
  }
  ```
- [x] 2.1.1.4 Implement `start_link/1` with session option
- [x] 2.1.1.5 Implement `via/1` helper for Registry naming:
  ```elixir
  defp via(session_id) do
    {:via, Registry, {JidoCode.Registry, {:session_manager, session_id}}}
  end
  ```
- [x] 2.1.1.6 Write unit tests for manager startup

### 2.1.2 Manager Initialization
- [x] **Task 2.1.2** ✅ COMPLETE

Implement GenServer init with Lua sandbox setup.

- [x] 2.1.2.1 Implement `init/1` callback:
  ```elixir
  def init(session) do
    {:ok, lua_state} = :luerl.init()
    lua_state = JidoCode.Tools.Bridge.register(lua_state, session.project_path)

    {:ok, %{
      session_id: session.id,
      project_root: session.project_path,
      lua_state: lua_state
    }}
  end
  ```
- [x] 2.1.2.2 Log manager initialization with session ID and project path
- [x] 2.1.2.3 Handle Lua initialization errors
- [x] 2.1.2.4 Write unit tests for initialization

### 2.1.3 Project Root Access
- [x] **Task 2.1.3** ✅ COMPLETE (implemented in Task 2.1.1)

Implement API for accessing project root.

- [x] 2.1.3.1 Implement `project_root/1` client function:
  ```elixir
  def project_root(session_id) do
    GenServer.call(via(session_id), :project_root)
  end
  ```
- [x] 2.1.3.2 Implement `handle_call(:project_root, _, state)`:
  ```elixir
  def handle_call(:project_root, _from, state) do
    {:reply, {:ok, state.project_root}, state}
  end
  ```
- [x] 2.1.3.3 Handle case where manager not found
- [x] 2.1.3.4 Write unit tests for project_root access

### 2.1.4 Path Validation API
- [x] **Task 2.1.4** ✅ COMPLETE

Implement session-scoped path validation.

- [x] 2.1.4.1 Implement `validate_path/2` client function:
  ```elixir
  def validate_path(session_id, path) do
    GenServer.call(via(session_id), {:validate_path, path})
  end
  ```
- [x] 2.1.4.2 Implement `handle_call({:validate_path, path}, _, state)`:
  ```elixir
  def handle_call({:validate_path, path}, _from, state) do
    result = JidoCode.Tools.Security.validate_path(path, state.project_root)
    {:reply, result, state}
  end
  ```
- [x] 2.1.4.3 Delegate to existing Security module
- [x] 2.1.4.4 Write unit tests for path validation through Manager

### 2.1.5 File Operations API
- [x] **Task 2.1.5** ✅ COMPLETE

Implement session-scoped file operations (mirroring Tools.Manager).

- [x] 2.1.5.1 Implement `read_file/2` client function
- [x] 2.1.5.2 Implement `handle_call({:read_file, path}, _, state)`
- [x] 2.1.5.3 Validate path before reading
- [x] 2.1.5.4 Implement `write_file/3` client function
- [x] 2.1.5.5 Implement `handle_call({:write_file, path, content}, _, state)`
- [x] 2.1.5.6 Validate path before writing
- [x] 2.1.5.7 Implement `list_dir/2` client function
- [x] 2.1.5.8 Implement `handle_call({:list_dir, path}, _, state)`
- [x] 2.1.5.9 Write unit tests for file operations

### 2.1.6 Lua Script Execution
- [x] **Task 2.1.6** ✅ COMPLETE

Implement session-scoped Lua script execution.

- [x] 2.1.6.1 Implement `run_lua/2` client function:
  ```elixir
  def run_lua(session_id, script) do
    GenServer.call(via(session_id), {:run_lua, script}, 30_000)
  end
  ```
- [x] 2.1.6.2 Implement `handle_call({:run_lua, script}, _, state)`:
  ```elixir
  def handle_call({:run_lua, script}, _from, state) do
    case :luerl.do(script, state.lua_state) do
      {:ok, result, new_lua} ->
        {:reply, {:ok, result}, %{state | lua_state: new_lua}}
      {:error, reason, _} ->
        {:reply, {:error, reason}, state}
    end
  end
  ```
- [x] 2.1.6.3 Handle Lua execution timeout
- [x] 2.1.6.4 Write unit tests for Lua execution

**Unit Tests for Section 2.1:**
- Test Manager starts with valid session
- Test Manager registers in Registry with session ID
- Test `project_root/1` returns correct path
- Test `validate_path/2` accepts paths within boundary
- Test `validate_path/2` rejects paths outside boundary
- Test `read_file/2` reads files within boundary
- Test `read_file/2` rejects files outside boundary
- Test `write_file/3` writes files within boundary
- Test `list_dir/2` lists directories within boundary
- Test `run_lua/2` executes scripts successfully
- Test `run_lua/2` handles script errors

---

## 2.2 Session State

Create the per-session State GenServer for conversation and UI state management.

### 2.2.1 State Module Structure
- [x] **Task 2.2.1** ✅ COMPLETE

Create the Session.State module with GenServer behavior.

- [x] 2.2.1.1 Create `lib/jido_code/session/state.ex` with module documentation
- [x] 2.2.1.2 Add `use GenServer`
- [x] 2.2.1.3 Define `@type state()`:
  ```elixir
  @type state :: %{
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
- [x] 2.2.1.4 Implement `start_link/1` with session option
- [x] 2.2.1.5 Implement `via/1` helper for Registry naming (uses ProcessRegistry)
- [x] 2.2.1.6 Write unit tests for state startup

### 2.2.2 State Initialization
- [x] **Task 2.2.2** ✅ COMPLETE (implemented in Task 2.2.1)

Implement GenServer init with empty conversation state.

- [x] 2.2.2.1 Implement `init/1` callback:
  ```elixir
  def init(session) do
    {:ok, %{
      session_id: session.id,
      messages: [],
      reasoning_steps: [],
      tool_calls: [],
      todos: [],
      scroll_offset: 0,
      streaming_message: nil,
      is_streaming: false
    }}
  end
  ```
- [x] 2.2.2.2 Log state initialization with session ID
- [x] 2.2.2.3 Write unit tests for initialization

### 2.2.3 State Access API
- [x] **Task 2.2.3**

Implement functions for reading state.

- [x] 2.2.3.1 Implement `get_state/1` returning full state:
  ```elixir
  def get_state(session_id) do
    GenServer.call(via(session_id), :get_state)
  end
  ```
- [x] 2.2.3.2 Implement `get_messages/1` returning messages list
- [x] 2.2.3.3 Implement `get_reasoning_steps/1` returning reasoning steps
- [x] 2.2.3.4 Implement `get_todos/1` returning todo list
- [x] 2.2.3.5 Write unit tests for state access

### 2.2.4 Message Management API
- [x] **Task 2.2.4**

Implement functions for managing conversation messages.

- [x] 2.2.4.1 Implement `append_message/2`:
  ```elixir
  def append_message(session_id, message) do
    GenServer.call(via(session_id), {:append_message, message})
  end
  ```
- [x] 2.2.4.2 Implement `handle_call({:append_message, message}, _, state)`
- [x] 2.2.4.3 Add message to end of messages list
- [x] 2.2.4.4 Implement `clear_messages/1` for clearing history
- [x] 2.2.4.5 Write unit tests for message management

### 2.2.5 Streaming API
- [x] **Task 2.2.5**

Implement functions for streaming message updates.

- [x] 2.2.5.1 Implement `start_streaming/2` accepting session_id and message_id:
  ```elixir
  def start_streaming(session_id, message_id) do
    GenServer.call(via(session_id), {:start_streaming, message_id})
  end
  ```
- [x] 2.2.5.2 Set `is_streaming: true` and `streaming_message: ""`
- [x] 2.2.5.3 Implement `update_streaming/2` for appending chunks (cast):
  ```elixir
  def update_streaming(session_id, chunk) do
    GenServer.cast(via(session_id), {:streaming_chunk, chunk})
  end
  ```
- [x] 2.2.5.4 Implement `end_streaming/1` to finalize streaming
- [x] 2.2.5.5 Move streaming_message content to messages list
- [x] 2.2.5.6 Set `is_streaming: false` and `streaming_message: nil`
- [x] 2.2.5.7 Write unit tests for streaming lifecycle

### 2.2.6 Scroll and UI State
- [x] **Task 2.2.6**

Implement functions for UI state management.

- [x] 2.2.6.1 Implement `set_scroll_offset/2`
- [x] 2.2.6.2 Implement `update_todos/2` for task list updates
- [x] 2.2.6.3 Implement `add_reasoning_step/2`
- [x] 2.2.6.4 Implement `clear_reasoning_steps/1`
- [x] 2.2.6.5 Implement `add_tool_call/2`
- [x] 2.2.6.6 Write unit tests for UI state management

**Unit Tests for Section 2.2:**
- Test State starts with empty messages
- Test State registers in Registry with session ID
- Test `get_state/1` returns full state
- Test `append_message/2` adds message
- Test `clear_messages/1` empties messages
- Test `start_streaming/2` sets streaming flag
- Test `update_streaming/2` appends chunk
- Test `end_streaming/1` finalizes message
- Test `set_scroll_offset/2` updates offset
- Test `update_todos/2` updates todo list

---

## 2.3 Session Settings

Create per-session settings loader that respects project-local configuration.

### 2.3.1 Settings Module Structure
- [x] **Task 2.3.1** ✅ COMPLETE

Create the Session.Settings module for per-project settings.

- [x] 2.3.1.1 Create `lib/jido_code/session/settings.ex` with module documentation
- [x] 2.3.1.2 Define settings file path pattern: `{project_path}/.jido_code/settings.json`
- [x] 2.3.1.3 Document merge priority: global < local
- [x] 2.3.1.4 Write module spec

### 2.3.2 Settings Loading
- [x] **Task 2.3.2** ✅ COMPLETE

Implement settings loading for a project path.

- [x] 2.3.2.1 Implement `load/1` accepting project_path:
  ```elixir
  def load(project_path) do
    global = JidoCode.Settings.load_global()
    local = load_local(project_path)
    Map.merge(global, local)
  end
  ```
- [x] 2.3.2.2 Implement `load_local/1` for project-specific settings
- [x] 2.3.2.3 Handle missing local settings file (return empty map)
- [x] 2.3.2.4 Handle malformed JSON (log warning, return empty map)
- [x] 2.3.2.5 Write unit tests for settings loading

### 2.3.3 Settings Path Functions
- [x] **Task 2.3.3** ✅ COMPLETE

Implement helper functions for settings paths.

- [x] 2.3.3.1 Implement `local_path/1` returning settings file path for project (done in 2.3.1)
- [x] 2.3.3.2 Implement `local_dir/1` returning settings directory for project (done in 2.3.1)
- [x] 2.3.3.3 Implement `ensure_local_dir/1` creating directory if missing
- [x] 2.3.3.4 Write unit tests for path functions

### 2.3.4 Settings Saving
- [x] **Task 2.3.4** ✅ COMPLETE

Implement settings saving for session-specific overrides.

- [x] 2.3.4.1 Implement `save/2` accepting project_path and settings map
- [x] 2.3.4.2 Create settings directory if it doesn't exist
- [x] 2.3.4.3 Write settings to JSON file atomically
- [x] 2.3.4.4 Implement `set/3` for updating individual keys
- [x] 2.3.4.5 Write unit tests for settings saving

**Unit Tests for Section 2.3:**
- Test `load/1` merges global and local settings
- Test `load/1` handles missing local file
- Test `load/1` handles malformed JSON
- Test local settings override global settings
- Test `local_path/1` returns correct path
- Test `save/2` creates settings file
- Test `save/2` creates directory if missing
- Test `set/3` updates individual key

---

## 2.4 Global Manager Deprecation

Update the global Tools.Manager to delegate to session-scoped managers.

### 2.4.1 Manager Compatibility Layer
- [x] **Task 2.4.1** ✅ COMPLETE

Add session awareness to global Tools.Manager.

- [x] 2.4.1.1 Update `Tools.Manager` to accept optional `session_id` in context
- [x] 2.4.1.2 When `session_id` present, delegate to `Session.Manager`
- [x] 2.4.1.3 When `session_id` absent, use global project_root (backwards compat)
- [x] 2.4.1.4 Add deprecation warning when using global manager
- [x] 2.4.1.5 Document migration path in module doc
- [x] 2.4.1.6 Write tests for compatibility layer

### 2.4.2 Handler Helpers Update
- [x] **Task 2.4.2** ✅ COMPLETE

Update HandlerHelpers to prefer session context.

- [x] 2.4.2.1 Update `get_project_root/1` to check for session_id first:
  ```elixir
  def get_project_root(context) do
    cond do
      context[:session_id] ->
        Session.Manager.project_root(context.session_id)
      context[:project_root] ->
        {:ok, context.project_root}
      true ->
        Tools.Manager.project_root()
    end
  end
  ```
- [x] 2.4.2.2 Update `validate_path/2` to use session manager when available
- [x] 2.4.2.3 Write tests for session-aware helpers

### 2.4.3 Review Fixes (Post-Review)
- [x] **Task 2.4.3** ✅ COMPLETE

Address review findings from Section 2.4 review.

- [x] 2.4.3.1 Add UUID format validation for session_id in HandlerHelpers
- [x] 2.4.3.2 Add deprecation logging when falling back to global manager
- [x] 2.4.3.3 Make deprecation warnings suppressible via application config
- [x] 2.4.3.4 Add format_common_error/2 clause for :invalid_session_id
- [x] 2.4.3.5 Add edge case tests for UUID validation
- [x] 2.4.3.6 Add tests for deprecation warning logging

**Unit Tests for Section 2.4:**
- Test Tools.Manager works with session_id in context
- Test Tools.Manager works without session_id (backwards compat)
- Test HandlerHelpers.get_project_root uses session manager
- Test HandlerHelpers.get_project_root falls back to global
- Test invalid session_id format returns :invalid_session_id error
- Test deprecation warnings logged when using global fallback
- Test deprecation warnings can be suppressed

---

## 2.5 Phase 2 Integration Tests

Comprehensive integration tests verifying all Phase 2 components work together correctly.

### 2.5.1 Manager-State Integration
- [x] **Task 2.5.1** ✅ COMPLETE

Test Session.Manager and Session.State work together within a session.

- [x] 2.5.1.1 Create `test/jido_code/integration/session_phase2_test.exs`
- [x] 2.5.1.2 Test: Create session → Manager and State both start → both accessible via helpers
- [x] 2.5.1.3 Test: Manager validates path → State stores result metadata
- [x] 2.5.1.4 Test: Manager Lua execution → State tracks tool call
- [x] 2.5.1.5 Test: Session restart → Manager and State both restart with correct session context
- [x] 2.5.1.6 Write all Manager-State integration tests (7 tests)

### 2.5.2 Settings Integration
- [x] **Task 2.5.2** ✅ COMPLETE

Test Session.Settings integrates correctly with session creation.

- [x] 2.5.2.1 Test: Create session → Settings loaded from project path
- [x] 2.5.2.2 Test: Local settings override global settings in session config
- [x] 2.5.2.3 Test: Missing local settings → falls back to global only
- [x] 2.5.2.4 Test: Save settings → reload session → settings persisted
- [x] 2.5.2.5 Write all Settings integration tests (5 tests)

### 2.5.3 Multi-Session Isolation
- [x] **Task 2.5.3** ✅ COMPLETE

Test multiple sessions have isolated Manager and State instances.

- [x] 2.5.3.1 Test: Create 2 sessions → each has own Manager with different project_root
- [x] 2.5.3.2 Test: Create 2 sessions → each has own State with independent messages
- [x] 2.5.3.3 Test: Create 2 sessions → each has own Lua sandbox (isolated state)
- [x] 2.5.3.4 Test: Streaming in session A → session B State unaffected
- [x] 2.5.3.5 Test: Path validation in session A → uses session A's project_root only
- [x] 2.5.3.6 Write all isolation integration tests (6 tests)

### 2.5.4 Backwards Compatibility
- [x] **Task 2.5.4** ✅ COMPLETE

Test global Tools.Manager compatibility layer works correctly.

- [x] 2.5.4.1 Test: HandlerHelpers.get_project_root with session_id → uses Session.Manager
- [x] 2.5.4.2 Test: HandlerHelpers.get_project_root without session_id → uses global project_root
- [x] 2.5.4.3 Test: HandlerHelpers prefer session context when available
- [x] 2.5.4.4 Test: HandlerHelpers.validate_path with both session and global context
- [x] 2.5.4.5 Write all compatibility integration tests (7 tests)

**Integration Tests for Section 2.5:** (25 total tests)
- Manager and State coordinate correctly within session
- Settings load and merge correctly for sessions
- Multiple sessions have complete isolation
- Backwards compatibility maintained

---

## Success Criteria

1. **Session.Manager**: Per-session GenServer manages project_root and Lua sandbox
2. **Path Validation**: Session.Manager validates paths within session's project boundary
3. **File Operations**: Session.Manager provides session-scoped file read/write/list
4. **Lua Sandbox**: Each session has isolated Lua state
5. **Session.State**: Per-session GenServer holds conversation state
6. **Message Management**: Messages append, clear, and stream correctly
7. **Streaming Support**: Streaming state transitions work correctly
8. **Session.Settings**: Per-project settings load and merge with global
9. **Backwards Compatibility**: Global Tools.Manager still works for non-session code
10. **Test Coverage**: Minimum 80% coverage for phase 2 code
11. **Integration Tests**: All Phase 2 components work together correctly (Section 2.5)

---

## Critical Files

**New Files:**
- `lib/jido_code/session/manager.ex`
- `lib/jido_code/session/state.ex`
- `lib/jido_code/session/settings.ex`
- `test/jido_code/session/manager_test.exs`
- `test/jido_code/session/state_test.exs`
- `test/jido_code/session/settings_test.exs`
- `test/jido_code/integration/session_phase2_test.exs`

**Modified Files:**
- `lib/jido_code/tools/manager.ex` - Add session delegation
- `lib/jido_code/tools/handler_helpers.ex` - Session-aware helpers

---

## Dependencies

- **Depends on Phase 1**: Session struct, Registry, Supervisors
- **Phase 3 depends on this**: Tool execution needs Session.Manager
- **Phase 4 depends on this**: TUI needs Session.State for rendering

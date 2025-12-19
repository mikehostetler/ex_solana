# Phase 2: Per-Session Manager and Security

This phase implements the per-session security sandbox. Each session gets its own Manager process that enforces project boundary restrictions and manages the Lua sandbox. This replaces the global `Tools.Manager` with session-scoped instances.

---

## 2.1 Session Manager

Create the per-session Manager GenServer that handles security and sandbox isolation.

### 2.1.1 Manager Module Structure
- [ ] **Task 2.1.1**

Create the Session.Manager module with GenServer behavior.

- [ ] 2.1.1.1 Create `lib/jido_code/session/manager.ex` with module documentation
- [ ] 2.1.1.2 Add `use GenServer`
- [ ] 2.1.1.3 Define `@type state()`:
  ```elixir
  @type state :: %{
    session_id: String.t(),
    project_root: String.t(),
    lua_state: :luerl.state()
  }
  ```
- [ ] 2.1.1.4 Implement `start_link/1` with session option
- [ ] 2.1.1.5 Implement `via/1` helper for Registry naming:
  ```elixir
  defp via(session_id) do
    {:via, Registry, {JidoCode.Registry, {:session_manager, session_id}}}
  end
  ```
- [ ] 2.1.1.6 Write unit tests for manager startup

### 2.1.2 Manager Initialization
- [ ] **Task 2.1.2**

Implement GenServer init with Lua sandbox setup.

- [ ] 2.1.2.1 Implement `init/1` callback:
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
- [ ] 2.1.2.2 Log manager initialization with session ID and project path
- [ ] 2.1.2.3 Handle Lua initialization errors
- [ ] 2.1.2.4 Write unit tests for initialization

### 2.1.3 Project Root Access
- [ ] **Task 2.1.3**

Implement API for accessing project root.

- [ ] 2.1.3.1 Implement `project_root/1` client function:
  ```elixir
  def project_root(session_id) do
    GenServer.call(via(session_id), :project_root)
  end
  ```
- [ ] 2.1.3.2 Implement `handle_call(:project_root, _, state)`:
  ```elixir
  def handle_call(:project_root, _from, state) do
    {:reply, {:ok, state.project_root}, state}
  end
  ```
- [ ] 2.1.3.3 Handle case where manager not found
- [ ] 2.1.3.4 Write unit tests for project_root access

### 2.1.4 Path Validation API
- [ ] **Task 2.1.4**

Implement session-scoped path validation.

- [ ] 2.1.4.1 Implement `validate_path/2` client function:
  ```elixir
  def validate_path(session_id, path) do
    GenServer.call(via(session_id), {:validate_path, path})
  end
  ```
- [ ] 2.1.4.2 Implement `handle_call({:validate_path, path}, _, state)`:
  ```elixir
  def handle_call({:validate_path, path}, _from, state) do
    result = JidoCode.Tools.Security.validate_path(path, state.project_root)
    {:reply, result, state}
  end
  ```
- [ ] 2.1.4.3 Delegate to existing Security module
- [ ] 2.1.4.4 Write unit tests for path validation through Manager

### 2.1.5 File Operations API
- [ ] **Task 2.1.5**

Implement session-scoped file operations (mirroring Tools.Manager).

- [ ] 2.1.5.1 Implement `read_file/2` client function
- [ ] 2.1.5.2 Implement `handle_call({:read_file, path}, _, state)`
- [ ] 2.1.5.3 Validate path before reading
- [ ] 2.1.5.4 Implement `write_file/3` client function
- [ ] 2.1.5.5 Implement `handle_call({:write_file, path, content}, _, state)`
- [ ] 2.1.5.6 Validate path before writing
- [ ] 2.1.5.7 Implement `list_dir/2` client function
- [ ] 2.1.5.8 Implement `handle_call({:list_dir, path}, _, state)`
- [ ] 2.1.5.9 Write unit tests for file operations

### 2.1.6 Lua Script Execution
- [ ] **Task 2.1.6**

Implement session-scoped Lua script execution.

- [ ] 2.1.6.1 Implement `run_lua/2` client function:
  ```elixir
  def run_lua(session_id, script) do
    GenServer.call(via(session_id), {:run_lua, script}, 30_000)
  end
  ```
- [ ] 2.1.6.2 Implement `handle_call({:run_lua, script}, _, state)`:
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
- [ ] 2.1.6.3 Handle Lua execution timeout
- [ ] 2.1.6.4 Write unit tests for Lua execution

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
- [ ] **Task 2.2.1**

Create the Session.State module with GenServer behavior.

- [ ] 2.2.1.1 Create `lib/jido_code/session/state.ex` with module documentation
- [ ] 2.2.1.2 Add `use GenServer`
- [ ] 2.2.1.3 Define `@type state()`:
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
- [ ] 2.2.1.4 Implement `start_link/1` with session option
- [ ] 2.2.1.5 Implement `via/1` helper for Registry naming
- [ ] 2.2.1.6 Write unit tests for state startup

### 2.2.2 State Initialization
- [ ] **Task 2.2.2**

Implement GenServer init with empty conversation state.

- [ ] 2.2.2.1 Implement `init/1` callback:
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
- [ ] 2.2.2.2 Log state initialization with session ID
- [ ] 2.2.2.3 Write unit tests for initialization

### 2.2.3 State Access API
- [ ] **Task 2.2.3**

Implement functions for reading state.

- [ ] 2.2.3.1 Implement `get_state/1` returning full state:
  ```elixir
  def get_state(session_id) do
    GenServer.call(via(session_id), :get_state)
  end
  ```
- [ ] 2.2.3.2 Implement `get_messages/1` returning messages list
- [ ] 2.2.3.3 Implement `get_reasoning_steps/1` returning reasoning steps
- [ ] 2.2.3.4 Implement `get_todos/1` returning todo list
- [ ] 2.2.3.5 Write unit tests for state access

### 2.2.4 Message Management API
- [ ] **Task 2.2.4**

Implement functions for managing conversation messages.

- [ ] 2.2.4.1 Implement `append_message/2`:
  ```elixir
  def append_message(session_id, message) do
    GenServer.call(via(session_id), {:append_message, message})
  end
  ```
- [ ] 2.2.4.2 Implement `handle_call({:append_message, message}, _, state)`
- [ ] 2.2.4.3 Add message to end of messages list
- [ ] 2.2.4.4 Implement `clear_messages/1` for clearing history
- [ ] 2.2.4.5 Write unit tests for message management

### 2.2.5 Streaming API
- [ ] **Task 2.2.5**

Implement functions for streaming message updates.

- [ ] 2.2.5.1 Implement `start_streaming/2` accepting session_id and message_id:
  ```elixir
  def start_streaming(session_id, message_id) do
    GenServer.call(via(session_id), {:start_streaming, message_id})
  end
  ```
- [ ] 2.2.5.2 Set `is_streaming: true` and `streaming_message: ""`
- [ ] 2.2.5.3 Implement `update_streaming/2` for appending chunks (cast):
  ```elixir
  def update_streaming(session_id, chunk) do
    GenServer.cast(via(session_id), {:streaming_chunk, chunk})
  end
  ```
- [ ] 2.2.5.4 Implement `end_streaming/1` to finalize streaming
- [ ] 2.2.5.5 Move streaming_message content to messages list
- [ ] 2.2.5.6 Set `is_streaming: false` and `streaming_message: nil`
- [ ] 2.2.5.7 Write unit tests for streaming lifecycle

### 2.2.6 Scroll and UI State
- [ ] **Task 2.2.6**

Implement functions for UI state management.

- [ ] 2.2.6.1 Implement `set_scroll_offset/2`
- [ ] 2.2.6.2 Implement `update_todos/2` for task list updates
- [ ] 2.2.6.3 Implement `add_reasoning_step/2`
- [ ] 2.2.6.4 Implement `clear_reasoning_steps/1`
- [ ] 2.2.6.5 Implement `add_tool_call/2`
- [ ] 2.2.6.6 Write unit tests for UI state management

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
- [ ] **Task 2.3.1**

Create the Session.Settings module for per-project settings.

- [ ] 2.3.1.1 Create `lib/jido_code/session/settings.ex` with module documentation
- [ ] 2.3.1.2 Define settings file path pattern: `{project_path}/jido_code/settings.json`
- [ ] 2.3.1.3 Document merge priority: global < local
- [ ] 2.3.1.4 Write module spec

### 2.3.2 Settings Loading
- [ ] **Task 2.3.2**

Implement settings loading for a project path.

- [ ] 2.3.2.1 Implement `load/1` accepting project_path:
  ```elixir
  def load(project_path) do
    global = JidoCode.Settings.load_global()
    local = load_local(project_path)
    Map.merge(global, local)
  end
  ```
- [ ] 2.3.2.2 Implement `load_local/1` for project-specific settings
- [ ] 2.3.2.3 Handle missing local settings file (return empty map)
- [ ] 2.3.2.4 Handle malformed JSON (log warning, return empty map)
- [ ] 2.3.2.5 Write unit tests for settings loading

### 2.3.3 Settings Path Functions
- [ ] **Task 2.3.3**

Implement helper functions for settings paths.

- [ ] 2.3.3.1 Implement `local_path/1` returning settings file path for project
- [ ] 2.3.3.2 Implement `local_dir/1` returning settings directory for project
- [ ] 2.3.3.3 Implement `ensure_local_dir/1` creating directory if missing
- [ ] 2.3.3.4 Write unit tests for path functions

### 2.3.4 Settings Saving
- [ ] **Task 2.3.4**

Implement settings saving for session-specific overrides.

- [ ] 2.3.4.1 Implement `save/2` accepting project_path and settings map
- [ ] 2.3.4.2 Create settings directory if it doesn't exist
- [ ] 2.3.4.3 Write settings to JSON file atomically
- [ ] 2.3.4.4 Implement `set/3` for updating individual keys
- [ ] 2.3.4.5 Write unit tests for settings saving

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
- [ ] **Task 2.4.1**

Add session awareness to global Tools.Manager.

- [ ] 2.4.1.1 Update `Tools.Manager` to accept optional `session_id` in context
- [ ] 2.4.1.2 When `session_id` present, delegate to `Session.Manager`
- [ ] 2.4.1.3 When `session_id` absent, use global project_root (backwards compat)
- [ ] 2.4.1.4 Add deprecation warning when using global manager
- [ ] 2.4.1.5 Document migration path in module doc
- [ ] 2.4.1.6 Write tests for compatibility layer

### 2.4.2 Handler Helpers Update
- [ ] **Task 2.4.2**

Update HandlerHelpers to prefer session context.

- [ ] 2.4.2.1 Update `get_project_root/1` to check for session_id first:
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
- [ ] 2.4.2.2 Update `validate_path/2` to use session manager when available
- [ ] 2.4.2.3 Write tests for session-aware helpers

**Unit Tests for Section 2.4:**
- Test Tools.Manager works with session_id in context
- Test Tools.Manager works without session_id (backwards compat)
- Test HandlerHelpers.get_project_root uses session manager
- Test HandlerHelpers.get_project_root falls back to global

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

---

## Critical Files

**New Files:**
- `lib/jido_code/session/manager.ex`
- `lib/jido_code/session/state.ex`
- `lib/jido_code/session/settings.ex`
- `test/jido_code/session/manager_test.exs`
- `test/jido_code/session/state_test.exs`
- `test/jido_code/session/settings_test.exs`

**Modified Files:**
- `lib/jido_code/tools/manager.ex` - Add session delegation
- `lib/jido_code/tools/handler_helpers.ex` - Session-aware helpers

---

## Dependencies

- **Depends on Phase 1**: Session struct, Registry, Supervisors
- **Phase 3 depends on this**: Tool execution needs Session.Manager
- **Phase 4 depends on this**: TUI needs Session.State for rendering

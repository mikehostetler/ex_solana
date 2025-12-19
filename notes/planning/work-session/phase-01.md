# Phase 1: Session Foundation

This phase establishes the core session infrastructure: the Session struct, SessionRegistry for tracking active sessions, and the supervision tree for managing session processes. These components form the foundation for all subsequent phases.

---

## 1.1 Session Struct

Define the core session data structure that encapsulates all session-specific configuration and metadata.

### 1.1.1 Create Session Module
- [ ] **Task 1.1.1**

Create the main Session module with struct definition and type specifications.

- [ ] 1.1.1.1 Create `lib/jido_code/session.ex` with module documentation
- [ ] 1.1.1.2 Define `@type t()` for the session struct:
  ```elixir
  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t(),
    project_path: String.t(),
    config: config(),
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }
  ```
- [ ] 1.1.1.3 Define `@type config()` for LLM configuration:
  ```elixir
  @type config :: %{
    provider: String.t(),
    model: String.t(),
    temperature: float(),
    max_tokens: pos_integer()
  }
  ```
- [ ] 1.1.1.4 Implement `defstruct` with all fields
- [ ] 1.1.1.5 Write typespec tests using Dialyzer

### 1.1.2 Session Creation
- [ ] **Task 1.1.2**

Implement session creation with automatic naming from project folder.

- [ ] 1.1.2.1 Implement `new/1` accepting keyword options:
  - `project_path` (required) - absolute path to project directory
  - `name` (optional) - display name, defaults to folder name
  - `config` (optional) - LLM config, defaults to global settings
- [ ] 1.1.2.2 Generate unique `id` using UUID (`:crypto.strong_rand_bytes/1` or `:erlang.unique_integer`)
- [ ] 1.1.2.3 Extract folder name from `project_path` for default `name`: `Path.basename(project_path)`
- [ ] 1.1.2.4 Set `created_at` and `updated_at` to current UTC time
- [ ] 1.1.2.5 Load default config from `JidoCode.Settings.load()` if not provided
- [ ] 1.1.2.6 Validate `project_path` exists and is a directory
- [ ] 1.1.2.7 Return `{:ok, session}` or `{:error, reason}`
- [ ] 1.1.2.8 Write unit tests for session creation with various inputs

### 1.1.3 Session Validation
- [ ] **Task 1.1.3**

Implement validation functions for session fields.

- [ ] 1.1.3.1 Implement `validate/1` returning `{:ok, session}` or `{:error, reasons}`
- [ ] 1.1.3.2 Validate `id` is non-empty string
- [ ] 1.1.3.3 Validate `name` is non-empty string, max 50 characters
- [ ] 1.1.3.4 Validate `project_path` is absolute path
- [ ] 1.1.3.5 Validate `project_path` directory exists
- [ ] 1.1.3.6 Validate `config.provider` is valid provider
- [ ] 1.1.3.7 Validate `config.model` is non-empty string
- [ ] 1.1.3.8 Validate `config.temperature` is float 0.0-2.0
- [ ] 1.1.3.9 Validate `config.max_tokens` is positive integer
- [ ] 1.1.3.10 Write unit tests for each validation rule

### 1.1.4 Session Updates
- [ ] **Task 1.1.4**

Implement functions for updating session fields.

- [ ] 1.1.4.1 Implement `update_config/2` accepting session and config map
- [ ] 1.1.4.2 Merge new config with existing config
- [ ] 1.1.4.3 Update `updated_at` timestamp on any change
- [ ] 1.1.4.4 Implement `rename/2` accepting session and new name
- [ ] 1.1.4.5 Validate new name before applying
- [ ] 1.1.4.6 Return `{:ok, updated_session}` or `{:error, reason}`
- [ ] 1.1.4.7 Write unit tests for update operations

**Unit Tests for Section 1.1:**
- Test `new/1` creates valid session with defaults
- Test `new/1` with custom name overrides folder name
- Test `new/1` with custom config overrides global settings
- Test `new/1` fails for non-existent path
- Test `new/1` fails for file path (not directory)
- Test `validate/1` passes for valid session
- Test `validate/1` fails for empty id
- Test `validate/1` fails for invalid project_path
- Test `update_config/2` merges config correctly
- Test `update_config/2` updates timestamp
- Test `rename/2` changes name and timestamp

---

## 1.2 Session Registry

Create an ETS-backed registry to track active sessions with enforcement of the 10-session limit.

### 1.2.1 Registry Module Structure
- [ ] **Task 1.2.1**

Create the SessionRegistry module with ETS table management.

- [ ] 1.2.1.1 Create `lib/jido_code/session_registry.ex` with module documentation
- [ ] 1.2.1.2 Define `@max_sessions 10` module attribute
- [ ] 1.2.1.3 Define `@table __MODULE__` for ETS table name
- [ ] 1.2.1.4 Implement `create_table/0` creating named ETS table:
  ```elixir
  :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
  ```
- [ ] 1.2.1.5 Implement `table_exists?/0` for checking table status
- [ ] 1.2.1.6 Write unit tests for table creation

### 1.2.2 Session Registration
- [ ] **Task 1.2.2**

Implement session registration with limit enforcement.

- [ ] 1.2.2.1 Implement `register/1` accepting Session struct
- [ ] 1.2.2.2 Check current session count before registering
- [ ] 1.2.2.3 Return `{:error, :session_limit_reached}` if count >= 10
- [ ] 1.2.2.4 Check for duplicate session ID before inserting
- [ ] 1.2.2.5 Return `{:error, :session_exists}` if ID already registered
- [ ] 1.2.2.6 Check for duplicate project_path before inserting
- [ ] 1.2.2.7 Return `{:error, :project_already_open}` if path already in use
- [ ] 1.2.2.8 Insert `{session.id, session}` into ETS table
- [ ] 1.2.2.9 Return `{:ok, session}` on success
- [ ] 1.2.2.10 Write unit tests for registration scenarios

### 1.2.3 Session Lookup
- [ ] **Task 1.2.3**

Implement session lookup functions.

- [ ] 1.2.3.1 Implement `lookup/1` by session ID:
  ```elixir
  case :ets.lookup(@table, session_id) do
    [{^session_id, session}] -> {:ok, session}
    [] -> {:error, :not_found}
  end
  ```
- [ ] 1.2.3.2 Implement `lookup_by_path/1` by project_path
- [ ] 1.2.3.3 Use `:ets.match_object/2` for path lookup
- [ ] 1.2.3.4 Implement `lookup_by_name/1` by session name
- [ ] 1.2.3.5 Handle multiple matches for name lookup (return first or error)
- [ ] 1.2.3.6 Write unit tests for lookup operations

### 1.2.4 Session Listing
- [ ] **Task 1.2.4**

Implement functions for listing sessions.

- [ ] 1.2.4.1 Implement `list_all/0` returning list of all sessions
- [ ] 1.2.4.2 Use `:ets.tab2list/1` and extract sessions
- [ ] 1.2.4.3 Implement `count/0` returning current session count
- [ ] 1.2.4.4 Use `:ets.info(@table, :size)` for efficient count
- [ ] 1.2.4.5 Implement `list_ids/0` returning list of session IDs
- [ ] 1.2.4.6 Sort by `created_at` for consistent ordering
- [ ] 1.2.4.7 Write unit tests for listing operations

### 1.2.5 Session Removal
- [ ] **Task 1.2.5**

Implement session unregistration.

- [ ] 1.2.5.1 Implement `unregister/1` by session ID
- [ ] 1.2.5.2 Use `:ets.delete/2` for removal
- [ ] 1.2.5.3 Return `:ok` regardless of whether session existed
- [ ] 1.2.5.4 Implement `clear/0` to remove all sessions (for testing)
- [ ] 1.2.5.5 Write unit tests for removal operations

### 1.2.6 Session Updates in Registry
- [ ] **Task 1.2.6**

Implement updating session data in the registry.

- [ ] 1.2.6.1 Implement `update/1` accepting updated Session struct
- [ ] 1.2.6.2 Verify session exists before updating
- [ ] 1.2.6.3 Return `{:error, :not_found}` if session doesn't exist
- [ ] 1.2.6.4 Use `:ets.insert/2` to replace existing entry
- [ ] 1.2.6.5 Return `{:ok, session}` on success
- [ ] 1.2.6.6 Write unit tests for update operations

**Unit Tests for Section 1.2:**
- Test `create_table/0` creates ETS table
- Test `register/1` succeeds for valid session
- Test `register/1` fails at session limit (10)
- Test `register/1` fails for duplicate ID
- Test `register/1` fails for duplicate project_path
- Test `lookup/1` finds registered session
- Test `lookup/1` returns error for unknown ID
- Test `lookup_by_path/1` finds session by path
- Test `list_all/0` returns all sessions
- Test `count/0` returns correct count
- Test `unregister/1` removes session
- Test `update/1` updates existing session
- Test `update/1` fails for non-existent session

---

## 1.3 Session Supervisor

Create the DynamicSupervisor for managing per-session supervision trees.

### 1.3.1 SessionSupervisor Module
- [ ] **Task 1.3.1**

Create the main SessionSupervisor as a DynamicSupervisor.

- [ ] 1.3.1.1 Create `lib/jido_code/session_supervisor.ex` with module documentation
- [ ] 1.3.1.2 Add `use DynamicSupervisor`
- [ ] 1.3.1.3 Implement `start_link/1` with options:
  ```elixir
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  ```
- [ ] 1.3.1.4 Implement `init/1` with strategy:
  ```elixir
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
  ```
- [ ] 1.3.1.5 Write unit tests for supervisor startup

### 1.3.2 Session Process Management
- [ ] **Task 1.3.2**

Implement functions for starting and stopping session processes.

- [ ] 1.3.2.1 Implement `start_session/1` accepting Session struct:
  ```elixir
  def start_session(session) do
    spec = {JidoCode.Session.Supervisor, session: session}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
  ```
- [ ] 1.3.2.2 Register session in SessionRegistry before starting processes
- [ ] 1.3.2.3 Return `{:ok, pid}` with per-session supervisor pid
- [ ] 1.3.2.4 Return `{:error, reason}` if session limit reached or duplicate
- [ ] 1.3.2.5 Implement `stop_session/1` by session ID:
  ```elixir
  def stop_session(session_id) do
    case find_session_pid(session_id) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
      error -> error
    end
  end
  ```
- [ ] 1.3.2.6 Unregister session from SessionRegistry after stopping
- [ ] 1.3.2.7 Write unit tests for session lifecycle

### 1.3.3 Session Process Lookup
- [ ] **Task 1.3.3**

Implement functions for finding session processes.

- [ ] 1.3.3.1 Implement `find_session_pid/1` by session ID
- [ ] 1.3.3.2 Use Registry lookup: `{:via, Registry, {JidoCode.Registry, {:session, id}}}`
- [ ] 1.3.3.3 Implement `list_session_pids/0` returning all session supervisor pids
- [ ] 1.3.3.4 Implement `session_running?/1` checking if session processes are alive
- [ ] 1.3.3.5 Write unit tests for process lookup

### 1.3.4 Session Creation Convenience
- [ ] **Task 1.3.4**

Implement convenience function for creating and starting sessions.

- [ ] 1.3.4.1 Implement `create_session/1` combining creation and start:
  ```elixir
  def create_session(opts) do
    with {:ok, session} <- Session.new(opts),
         {:ok, _pid} <- start_session(session) do
      {:ok, session}
    end
  end
  ```
- [ ] 1.3.4.2 Handle partial failures (cleanup on error)
- [ ] 1.3.4.3 Write unit tests for convenience function

**Unit Tests for Section 1.3:**
- Test SessionSupervisor starts successfully
- Test `start_session/1` starts per-session supervisor
- Test `start_session/1` registers session in registry
- Test `start_session/1` fails when limit reached
- Test `stop_session/1` terminates session processes
- Test `stop_session/1` unregisters from registry
- Test `find_session_pid/1` returns correct pid
- Test `session_running?/1` returns correct status
- Test `create_session/1` convenience function works

---

## 1.4 Per-Session Supervisor

Create the per-session supervisor that manages session-specific processes.

### 1.4.1 Session.Supervisor Module
- [ ] **Task 1.4.1**

Create the per-session supervisor module.

- [ ] 1.4.1.1 Create `lib/jido_code/session/supervisor.ex` with module documentation
- [ ] 1.4.1.2 Add `use Supervisor`
- [ ] 1.4.1.3 Implement `start_link/1` with session option:
  ```elixir
  def start_link(opts) do
    session = Keyword.fetch!(opts, :session)
    Supervisor.start_link(__MODULE__, session, name: via(session.id))
  end
  ```
- [ ] 1.4.1.4 Implement `via/1` helper for Registry naming:
  ```elixir
  defp via(session_id) do
    {:via, Registry, {JidoCode.Registry, {:session, session_id}}}
  end
  ```
- [ ] 1.4.1.5 Write unit tests for supervisor naming

### 1.4.2 Child Specification
- [ ] **Task 1.4.2**

Define the child processes for each session.

- [ ] 1.4.2.1 Implement `init/1` with child specs:
  ```elixir
  def init(session) do
    children = [
      {JidoCode.Session.Manager, session: session},
      {JidoCode.Session.State, session: session}
      # Note: LLMAgent added in Phase 3 after tool integration
    ]
    Supervisor.init(children, strategy: :one_for_all)
  end
  ```
- [ ] 1.4.2.2 Use `:one_for_all` strategy (all children restart together)
- [ ] 1.4.2.3 Document why :one_for_all is appropriate (tight coupling)
- [ ] 1.4.2.4 Write unit tests for child startup

### 1.4.3 Session Process Access
- [ ] **Task 1.4.3**

Implement helper functions for accessing session child processes.

- [ ] 1.4.3.1 Implement `get_manager/1` returning Manager pid for session
- [ ] 1.4.3.2 Implement `get_state/1` returning State pid for session
- [ ] 1.4.3.3 Implement `get_agent/1` returning LLMAgent pid for session (stub for Phase 3)
- [ ] 1.4.3.4 Use Registry lookup with child-specific keys
- [ ] 1.4.3.5 Write unit tests for child access

**Unit Tests for Section 1.4:**
- Test Session.Supervisor starts with valid session
- Test Session.Supervisor registers in Registry
- Test child processes start with session context
- Test :one_for_all restart behavior
- Test `get_manager/1` returns Manager pid
- Test `get_state/1` returns State pid

---

## 1.5 Application Integration

Integrate the session infrastructure into the application supervision tree.

### 1.5.1 Supervision Tree Updates
- [ ] **Task 1.5.1**

Update application.ex to include session infrastructure.

- [ ] 1.5.1.1 Add SessionRegistry table creation to `start/2`:
  ```elixir
  JidoCode.SessionRegistry.create_table()
  ```
- [ ] 1.5.1.2 Add SessionSupervisor to children list (after Registry, before AgentSupervisor)
- [ ] 1.5.1.3 Ensure ordering: PubSub → Registry → SessionRegistry → SessionSupervisor
- [ ] 1.5.1.4 Write integration test for supervision tree startup

### 1.5.2 Default Session Creation
- [ ] **Task 1.5.2**

Auto-create default session for CWD on application start.

- [ ] 1.5.2.1 Implement `create_default_session/0` in Application module
- [ ] 1.5.2.2 Use `File.cwd!/0` to get current working directory
- [ ] 1.5.2.3 Create session with CWD path and folder name
- [ ] 1.5.2.4 Call `SessionSupervisor.create_session/1`
- [ ] 1.5.2.5 Log session creation with name and path
- [ ] 1.5.2.6 Handle errors gracefully (log warning, continue startup)
- [ ] 1.5.2.7 Call from `start/2` after children are started
- [ ] 1.5.2.8 Write integration tests for default session

### 1.5.3 Session ID Access
- [ ] **Task 1.5.3**

Provide easy access to default/active session ID.

- [ ] 1.5.3.1 Implement `get_default_session_id/0` returning first session ID
- [ ] 1.5.3.2 Use `SessionRegistry.list_ids/0` and take first
- [ ] 1.5.3.3 Handle empty registry case
- [ ] 1.5.3.4 Write unit tests for default session access

**Unit Tests for Section 1.5:**
- Test application starts with SessionRegistry table
- Test SessionSupervisor is running after start
- Test default session created for CWD
- Test default session has correct name (folder name)
- Test `get_default_session_id/0` returns ID
- Test startup continues if default session creation fails

---

## Success Criteria

1. **Session Struct**: Valid Session struct with all required fields and types
2. **Session Creation**: `Session.new/1` creates sessions with folder name as default name
3. **Session Validation**: All validation rules enforced with clear error messages
4. **Registry Limit**: Maximum 10 sessions enforced by SessionRegistry
5. **Registry Operations**: Register, lookup, list, update, unregister all work correctly
6. **SessionSupervisor**: DynamicSupervisor manages per-session supervisors
7. **Session.Supervisor**: Per-session supervisor starts Manager and State children
8. **Default Session**: Application starts with session for CWD
9. **Process Registration**: All session processes findable via Registry
10. **Test Coverage**: Minimum 80% coverage for phase 1 code

---

## Critical Files

**New Files:**
- `lib/jido_code/session.ex`
- `lib/jido_code/session_registry.ex`
- `lib/jido_code/session_supervisor.ex`
- `lib/jido_code/session/supervisor.ex`
- `test/jido_code/session_test.exs`
- `test/jido_code/session_registry_test.exs`
- `test/jido_code/session_supervisor_test.exs`
- `test/jido_code/session/supervisor_test.exs`

**Modified Files:**
- `lib/jido_code/application.ex`

---

## Dependencies

- This phase has no dependencies on other phases
- Phase 2 depends on this phase (Session.Manager needs Session struct)
- Phase 3 depends on this phase (Tool context needs session infrastructure)
- Phase 4 depends on this phase (TUI needs SessionRegistry for tab list)

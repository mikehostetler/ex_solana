# Phase 1: Session Foundation

This phase establishes the core session infrastructure: the Session struct, SessionRegistry for tracking active sessions, and the supervision tree for managing session processes. These components form the foundation for all subsequent phases.

---

## 1.1 Session Struct

Define the core session data structure that encapsulates all session-specific configuration and metadata.

### 1.1.1 Create Session Module
- [x] **Task 1.1.1** ✅ COMPLETE

Create the main Session module with struct definition and type specifications.

- [x] 1.1.1.1 Create `lib/jido_code/session.ex` with module documentation
- [x] 1.1.1.2 Define `@type t()` for the session struct:
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
- [x] 1.1.1.3 Define `@type config()` for LLM configuration:
  ```elixir
  @type config :: %{
    provider: String.t(),
    model: String.t(),
    temperature: float(),
    max_tokens: pos_integer()
  }
  ```
- [x] 1.1.1.4 Implement `defstruct` with all fields
- [x] 1.1.1.5 Write tests for struct and types (10 tests passing)

### 1.1.2 Session Creation
- [x] **Task 1.1.2** ✅ COMPLETE

Implement session creation with automatic naming from project folder.

- [x] 1.1.2.1 Implement `new/1` accepting keyword options:
  - `project_path` (required) - absolute path to project directory
  - `name` (optional) - display name, defaults to folder name
  - `config` (optional) - LLM config, defaults to global settings
- [x] 1.1.2.2 Generate unique `id` using UUID v4:
  ```elixir
  defp generate_id do
    <<u0::48, _::4, u1::12, _::2, u2::62>> = :crypto.strong_rand_bytes(16)
    <<u0::48, 4::4, u1::12, 2::2, u2::62>>
    |> Base.encode16(case: :lower)
    |> then(fn hex ->
      <<a::binary-8, b::binary-4, c::binary-4, d::binary-4, e::binary-12>> = hex
      "#{a}-#{b}-#{c}-#{d}-#{e}"
    end)
  end
  ```
  This generates RFC 4122 compliant UUID v4 (random) that is:
  - Globally unique across all nodes and restarts
  - 128-bit random with version/variant bits set correctly
  - Formatted as standard UUID string (8-4-4-4-12)
- [x] 1.1.2.3 Extract folder name from `project_path` for default `name`: `Path.basename(project_path)`
- [x] 1.1.2.4 Set `created_at` and `updated_at` to current UTC time
- [x] 1.1.2.5 Load default config from `JidoCode.Settings.load()` if not provided
- [x] 1.1.2.6 Validate `project_path` exists and is a directory
- [x] 1.1.2.7 Return `{:ok, session}` or `{:error, reason}`
- [x] 1.1.2.8 Write unit tests for session creation (16 tests: 11 for new/1, 5 for generate_id/0)

### 1.1.3 Session Validation
- [x] **Task 1.1.3** ✅ COMPLETE

Implement validation functions for session fields.

- [x] 1.1.3.1 Implement `validate/1` returning `{:ok, session}` or `{:error, reasons}`
- [x] 1.1.3.2 Validate `id` is non-empty string
- [x] 1.1.3.3 Validate `name` is non-empty string, max 50 characters
- [x] 1.1.3.4 Validate `project_path` is absolute path
- [x] 1.1.3.5 Validate `project_path` directory exists
- [x] 1.1.3.6 Validate `config.provider` is valid provider
- [x] 1.1.3.7 Validate `config.model` is non-empty string
- [x] 1.1.3.8 Validate `config.temperature` is float 0.0-2.0
- [x] 1.1.3.9 Validate `config.max_tokens` is positive integer
- [x] 1.1.3.10 Write unit tests for each validation rule (32 tests for validate/1)

### 1.1.4 Session Updates
- [x] **Task 1.1.4** ✅ COMPLETE

Implement functions for updating session fields.

- [x] 1.1.4.1 Implement `update_config/2` accepting session and config map
- [x] 1.1.4.2 Merge new config with existing config
- [x] 1.1.4.3 Update `updated_at` timestamp on any change
- [x] 1.1.4.4 Implement `rename/2` accepting session and new name
- [x] 1.1.4.5 Validate new name before applying
- [x] 1.1.4.6 Return `{:ok, updated_session}` or `{:error, reason}`
- [x] 1.1.4.7 Write unit tests for update operations (27 tests: 15 for update_config/2, 12 for rename/2)

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
- [x] **Task 1.2.1** ✅ COMPLETE

Create the SessionRegistry module with ETS table management.

- [x] 1.2.1.1 Create `lib/jido_code/session_registry.ex` with module documentation
- [x] 1.2.1.2 Define `@max_sessions 10` module attribute
- [x] 1.2.1.3 Define `@table __MODULE__` for ETS table name
- [x] 1.2.1.4 Implement `create_table/0` creating named ETS table:
  ```elixir
  :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
  ```
- [x] 1.2.1.5 Implement `table_exists?/0` for checking table status
- [x] 1.2.1.6 Write unit tests for table creation (12 tests passing)

### 1.2.2 Session Registration
- [x] **Task 1.2.2** ✅ COMPLETE

Implement session registration with limit enforcement.

- [x] 1.2.2.1 Implement `register/1` accepting Session struct
- [x] 1.2.2.2 Check current session count before registering
- [x] 1.2.2.3 Return `{:error, :session_limit_reached}` if count >= 10
- [x] 1.2.2.4 Check for duplicate session ID before inserting
- [x] 1.2.2.5 Return `{:error, :session_exists}` if ID already registered
- [x] 1.2.2.6 Check for duplicate project_path before inserting
- [x] 1.2.2.7 Return `{:error, :project_already_open}` if path already in use
- [x] 1.2.2.8 Insert `{session.id, session}` into ETS table
- [x] 1.2.2.9 Return `{:ok, session}` on success
- [x] 1.2.2.10 Write unit tests for registration scenarios (15 tests passing)

### 1.2.3 Session Lookup
- [x] **Task 1.2.3** ✅ COMPLETE

Implement session lookup functions.

- [x] 1.2.3.1 Implement `lookup/1` by session ID:
  ```elixir
  case :ets.lookup(@table, session_id) do
    [{^session_id, session}] -> {:ok, session}
    [] -> {:error, :not_found}
  end
  ```
- [x] 1.2.3.2 Implement `lookup_by_path/1` by project_path
- [x] 1.2.3.3 Use `:ets.select/2` with match spec for path lookup
- [x] 1.2.3.4 Implement `lookup_by_name/1` by session name
- [x] 1.2.3.5 Handle multiple matches for name lookup (return oldest by created_at)
- [x] 1.2.3.6 Write unit tests for lookup operations (16 tests passing)

### 1.2.4 Session Listing
- [x] **Task 1.2.4** ✅ COMPLETE

Implement functions for listing sessions.

- [x] 1.2.4.1 Implement `list_all/0` returning list of all sessions
- [x] 1.2.4.2 Use `:ets.tab2list/1` and extract sessions
- [x] 1.2.4.3 Implement `count/0` returning current session count (done in Task 1.2.2)
- [x] 1.2.4.4 Use `:ets.info(@table, :size)` for efficient count (done in Task 1.2.2)
- [x] 1.2.4.5 Implement `list_ids/0` returning list of session IDs
- [x] 1.2.4.6 Sort by `created_at` for consistent ordering
- [x] 1.2.4.7 Write unit tests for listing operations (10 tests passing)

### 1.2.5 Session Removal
- [x] **Task 1.2.5** ✅ COMPLETE

Implement session unregistration.

- [x] 1.2.5.1 Implement `unregister/1` by session ID
- [x] 1.2.5.2 Use `:ets.delete/2` for removal
- [x] 1.2.5.3 Return `:ok` regardless of whether session existed
- [x] 1.2.5.4 Implement `clear/0` to remove all sessions (for testing)
- [x] 1.2.5.5 Write unit tests for removal operations (11 tests passing)

### 1.2.6 Session Updates in Registry
- [x] **Task 1.2.6** ✅ COMPLETE

Implement updating session data in the registry.

- [x] 1.2.6.1 Implement `update/1` accepting updated Session struct
- [x] 1.2.6.2 Verify session exists before updating
- [x] 1.2.6.3 Return `{:error, :not_found}` if session doesn't exist
- [x] 1.2.6.4 Use `:ets.insert/2` to replace existing entry
- [x] 1.2.6.5 Return `{:ok, session}` on success
- [x] 1.2.6.6 Write unit tests for update operations (7 tests passing)

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
- [x] **Task 1.3.1** ✅ COMPLETE

Create the main SessionSupervisor as a DynamicSupervisor.

- [x] 1.3.1.1 Create `lib/jido_code/session_supervisor.ex` with module documentation
- [x] 1.3.1.2 Add `use DynamicSupervisor`
- [x] 1.3.1.3 Implement `start_link/1` with options:
  ```elixir
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  ```
- [x] 1.3.1.4 Implement `init/1` with strategy:
  ```elixir
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
  ```
- [x] 1.3.1.5 Write unit tests for supervisor startup (9 tests passing)

### 1.3.2 Session Process Management
- [x] **Task 1.3.2** ✅ COMPLETE

Implement functions for starting and stopping session processes.

- [x] 1.3.2.1 Implement `start_session/1` accepting Session struct:
  ```elixir
  def start_session(session) do
    spec = {JidoCode.Session.Supervisor, session: session}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
  ```
- [x] 1.3.2.2 Register session in SessionRegistry before starting processes
- [x] 1.3.2.3 Return `{:ok, pid}` with per-session supervisor pid
- [x] 1.3.2.4 Return `{:error, reason}` if session limit reached or duplicate
- [x] 1.3.2.5 Implement `stop_session/1` by session ID:
  ```elixir
  def stop_session(session_id) do
    case find_session_pid(session_id) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
      error -> error
    end
  end
  ```
- [x] 1.3.2.6 Unregister session from SessionRegistry after stopping
- [x] 1.3.2.7 Write unit tests for session lifecycle (13 new tests, 22 total)

### 1.3.3 Session Process Lookup
- [x] **Task 1.3.3** ✅ COMPLETE

Implement functions for finding session processes.

- [x] 1.3.3.1 Implement `find_session_pid/1` by session ID
- [x] 1.3.3.2 Use Registry lookup: `{:via, Registry, {JidoCode.SessionProcessRegistry, {:session, id}}}`
- [x] 1.3.3.3 Implement `list_session_pids/0` returning all session supervisor pids
- [x] 1.3.3.4 Implement `session_running?/1` checking if session processes are alive
- [x] 1.3.3.5 Write unit tests for process lookup (9 new tests, 31 total)

### 1.3.4 Session Creation Convenience
- [x] **Task 1.3.4** ✅ COMPLETE

Implement convenience function for creating and starting sessions.

- [x] 1.3.4.1 Implement `create_session/1` combining creation and start:
  ```elixir
  def create_session(opts) do
    with {:ok, session} <- Session.new(opts),
         {:ok, _pid} <- start_session(session) do
      {:ok, session}
    end
  end
  ```
- [x] 1.3.4.2 Handle partial failures (cleanup on error)
- [x] 1.3.4.3 Write unit tests for convenience function (10 new tests, 41 total)

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
- [x] **Task 1.4.1** ✅ COMPLETE

Create the per-session supervisor module.

- [x] 1.4.1.1 Create `lib/jido_code/session/supervisor.ex` with module documentation
- [x] 1.4.1.2 Add `use Supervisor`
- [x] 1.4.1.3 Implement `start_link/1` with session option:
  ```elixir
  def start_link(opts) do
    session = Keyword.fetch!(opts, :session)
    Supervisor.start_link(__MODULE__, session, name: via(session.id))
  end
  ```
- [x] 1.4.1.4 Implement `via/1` helper for Registry naming (uses SessionProcessRegistry):
  ```elixir
  defp via(session_id) do
    {:via, Registry, {JidoCode.SessionProcessRegistry, {:session, session_id}}}
  end
  ```
- [x] 1.4.1.5 Write unit tests for supervisor naming (14 tests)

### 1.4.2 Child Specification
- [x] **Task 1.4.2** ✅ COMPLETE

Define the child processes for each session.

- [x] 1.4.2.1 Implement `init/1` with child specs:
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
- [x] 1.4.2.2 Use `:one_for_all` strategy (all children restart together)
- [x] 1.4.2.3 Document why :one_for_all is appropriate (tight coupling)
- [x] 1.4.2.4 Write unit tests for child startup (28 tests for session/* modules)

### 1.4.3 Session Process Access
- [x] **Task 1.4.3** ✅ COMPLETE

Implement helper functions for accessing session child processes.

- [x] 1.4.3.1 Implement `get_manager/1` returning Manager pid for session
- [x] 1.4.3.2 Implement `get_state/1` returning State pid for session
- [x] 1.4.3.3 Implement `get_agent/1` returning LLMAgent pid for session (stub for Phase 3)
- [x] 1.4.3.4 Use Registry lookup with child-specific keys
- [x] 1.4.3.5 Write unit tests for child access (11 new tests, 27 total for supervisor)

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
- [x] **Task 1.5.1** ✅ COMPLETE

Update application.ex to include session infrastructure.

- [x] 1.5.1.1 Add SessionRegistry table creation to `start/2`:
  ```elixir
  JidoCode.SessionRegistry.create_table()
  ```
- [x] 1.5.1.2 Add SessionSupervisor to children list (after Registry, before AgentSupervisor)
- [x] 1.5.1.3 Ensure ordering: PubSub → Registry → SessionRegistry → SessionSupervisor
- [x] 1.5.1.4 Write integration test for supervision tree startup

### 1.5.2 Default Session Creation
- [x] **Task 1.5.2 Complete**

Auto-create default session for CWD on application start.

- [x] 1.5.2.1 Implement `create_default_session/0` in Application module
- [x] 1.5.2.2 Use `File.cwd!/0` to get current working directory
- [x] 1.5.2.3 Create session with CWD path and folder name
- [x] 1.5.2.4 Call `SessionSupervisor.create_session/1`
- [x] 1.5.2.5 Log session creation with name and path
- [x] 1.5.2.6 Handle errors gracefully (log warning, continue startup)
- [x] 1.5.2.7 Call from `start/2` after children are started
- [x] 1.5.2.8 Write integration tests for default session

### 1.5.3 Session ID Access
- [x] **Task 1.5.3 Complete**

Provide easy access to default/active session ID.

- [x] 1.5.3.1 Implement `get_default_session_id/0` returning first session ID
- [x] 1.5.3.2 Use `SessionRegistry.list_ids/0` and take first
- [x] 1.5.3.3 Handle empty registry case
- [x] 1.5.3.4 Write unit tests for default session access

**Unit Tests for Section 1.5:**
- Test application starts with SessionRegistry table
- Test SessionSupervisor is running after start
- Test default session created for CWD
- Test default session has correct name (folder name)
- Test `get_default_session_id/0` returns ID
- Test startup continues if default session creation fails

---

## 1.6 Phase 1 Integration Tests

Comprehensive integration tests verifying all Phase 1 components work together correctly.

### 1.6.1 Session Lifecycle Integration
- [x] **Task 1.6.1** ✅ COMPLETE

Test complete session lifecycle through all components.

- [x] 1.6.1.1 Create `test/jido_code/integration/session_phase1_test.exs`
- [x] 1.6.1.2 Test: Create session → verify in Registry → verify processes running → stop → verify cleanup
- [x] 1.6.1.3 Test: Create session with custom config → verify config propagated to child processes
- [x] 1.6.1.4 Test: Update session in Registry → verify updated_at changes
- [x] 1.6.1.5 Test: Rename session → verify Registry updated
- [x] 1.6.1.6 Test: Session process crash → verify supervisor restarts children → verify Registry intact
- [x] 1.6.1.7 Write all lifecycle integration tests

### 1.6.2 Multi-Session Integration
- [x] **Task 1.6.2** ✅ COMPLETE

Test multiple sessions operating concurrently.

- [x] 1.6.2.1 Test: Create 3 sessions → verify all in Registry → verify all processes running
- [x] 1.6.2.2 Test: Create sessions for different paths → verify isolation
- [x] 1.6.2.3 Test: Stop one session → verify others unaffected
- [x] 1.6.2.4 Test: Lookup by ID, path, and name all work correctly with multiple sessions
- [x] 1.6.2.5 Test: list_all/0 returns all sessions sorted by created_at
- [x] 1.6.2.6 Write all multi-session integration tests

### 1.6.3 Session Limit Integration
- [x] **Task 1.6.3** ✅ COMPLETE

Test 10-session limit enforcement end-to-end.

- [x] 1.6.3.1 Test: Create exactly 10 sessions → all succeed
- [x] 1.6.3.2 Test: Create 11th session → fails with :session_limit_reached
- [x] 1.6.3.3 Test: At limit → stop one → create new → succeeds
- [x] 1.6.3.4 Test: Duplicate path rejected even when under limit
- [x] 1.6.3.5 Test: Duplicate ID rejected (edge case)
- [x] 1.6.3.6 Write all limit integration tests

### 1.6.4 Registry-Supervisor Coordination
- [x] **Task 1.6.4** ✅ COMPLETE

Test coordination between SessionRegistry and SessionSupervisor.

- [x] 1.6.4.1 Test: Session registered in Registry before processes start
- [x] 1.6.4.2 Test: Session unregistered from Registry after processes stop
- [x] 1.6.4.3 Test: Registry count matches DynamicSupervisor child count
- [x] 1.6.4.4 Test: find_session_pid/1 returns correct pid for registered session
- [x] 1.6.4.5 Test: session_running?/1 matches Registry state
- [x] 1.6.4.6 Test: Cleanup on partial failure (Registry registered but supervisor start fails)
- [x] 1.6.4.7 Write all coordination integration tests

### 1.6.5 Child Process Access Integration
- [x] **Task 1.6.5** ✅ COMPLETE

Test access to session child processes through Session.Supervisor.

- [x] 1.6.5.1 Test: get_manager/1 returns live Manager pid
- [x] 1.6.5.2 Test: get_state/1 returns live State pid
- [x] 1.6.5.3 Test: Child pids are different for different sessions
- [x] 1.6.5.4 Test: Child pids change after supervisor restart
- [x] 1.6.5.5 Test: get_manager/1 returns error for stopped session
- [x] 1.6.5.6 Write all child access integration tests

**Integration Tests for Section 1.6:**
- Full lifecycle from create to cleanup verified
- Multi-session isolation confirmed
- 10-session limit enforced correctly
- Registry and Supervisor stay in sync
- Child process access works correctly

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
11. **Integration Tests**: All Phase 1 components work together correctly (Section 1.6)

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
- `test/jido_code/integration/session_phase1_test.exs`

**Modified Files:**
- `lib/jido_code/application.ex`

---

## Dependencies

- This phase has no dependencies on other phases
- Phase 2 depends on this phase (Session.Manager needs Session struct)
- Phase 3 depends on this phase (Tool context needs session infrastructure)
- Phase 4 depends on this phase (TUI needs SessionRegistry for tab list)

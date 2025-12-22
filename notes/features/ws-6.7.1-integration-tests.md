# Feature Planning: WS-6.7.1 - Save-Resume Cycle Integration Tests

**Task Reference**: Phase 6, Section 6.7.1
**Document Status**: Planning
**Created**: 2025-12-10
**Phase**: 6 (Session Persistence)

---

## 1. Problem Statement

### 1.1 Why Integration Tests are Critical

Phase 6 has introduced comprehensive session persistence functionality across multiple components (Tasks 6.1-6.6):
- Data serialization and deserialization (6.1)
- Auto-save on session close (6.2)
- Session listing and filtering (6.3)
- Session restoration with state reconstruction (6.4)
- Resume command integration (6.5)
- Cleanup and deletion (6.6)

While each component has unit tests verifying internal logic, **integration tests are essential** to verify that:

1. **End-to-End Workflow Works**: The complete save → list → resume cycle functions as a unified system
2. **Process Boundaries Hold**: State transitions correctly across process lifecycles (active → closed → active)
3. **Data Integrity Preserved**: Messages, todos, and config survive the full cycle without corruption
4. **File Operations Atomic**: JSON files are created, read, and deleted without race conditions
5. **Edge Cases Handled**: Real-world scenarios (deleted projects, corrupted files, concurrent access) work correctly

### 1.2 What Could Go Wrong Without Integration Tests

Without comprehensive integration tests, the following bugs could slip through:

- **State Mismatch**: Unit tests pass but real sessions lose messages/todos during resume
- **Registry Desync**: Persisted sessions appear in `list_resumable/0` even though they're already active
- **File Lifecycle**: Persisted files not deleted after resume, causing duplicates
- **Process Leaks**: Resumed sessions start processes but state restoration fails, leaving orphaned processes
- **TOCTOU Vulnerabilities**: Project path validated during load but deleted before session starts
- **Config Loss**: Configuration not properly propagated through persistence boundary

### 1.3 Success Metrics

Integration tests must verify:
- ✅ Zero data loss through complete save-resume cycle
- ✅ Proper cleanup of all resources (files, processes, registry entries)
- ✅ Correct state transitions at all stages
- ✅ Error handling prevents inconsistent state
- ✅ Sessions can be resumed, used, closed, and resumed again (multi-cycle)

---

## 2. Solution Overview

### 2.1 Testing Strategy

Use **real infrastructure** for integration tests:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Integration Test Scope                        │
│                                                                  │
│  ┌────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────┐ │
│  │ Session    │→ │ Session     │→ │ Session     │→ │ Persist │ │
│  │ Supervisor │  │ Manager     │  │ State       │  │ File    │ │
│  │            │  │             │  │             │  │         │ │
│  └────────────┘  └─────────────┘  └─────────────┘  └─────────┘ │
│         ↓                ↓                ↓              ↓       │
│  ┌────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────┐ │
│  │ Registry   │  │ Process     │  │ Messages    │  │ JSON    │ │
│  │            │  │ Registry    │  │ & Todos     │  │ I/O     │ │
│  └────────────┘  └─────────────┘  └─────────────┘  └─────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Key Principles**:
- **Real Processes**: Start actual SessionSupervisor, Manager, State, Agent processes
- **Real Files**: Write/read/delete actual JSON files in temp directories
- **Real Registry**: Use SessionRegistry (ETS) for session tracking
- **No Mocks**: Test the actual code paths users will execute
- **Isolated**: Each test uses unique temp directories and session IDs
- **Sequential**: Tests run `async: false` due to shared infrastructure

### 2.2 Test File Structure

```elixir
# test/jido_code/integration/session_phase6_test.exs

defmodule JidoCode.Integration.SessionPhase6Test do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :phase6

  # 6.7.1 - Save-Resume Cycle Integration Tests
  describe "6.7.1 save-resume cycle" do
    # Basic cycle tests
    test "create → add messages → close → save → resume → verify"
    test "create → add todos → close → save → resume → verify"
    test "create → configure → close → save → resume → verify config"

    # ID preservation tests
    test "resume preserves session ID across cycle"
    test "resume preserves created_at timestamp"

    # File lifecycle tests
    test "close creates JSON file"
    test "resume deletes persisted file"
    test "resume failure leaves file intact"

    # State transition tests
    test "closed session appears in list_resumable"
    test "resumed session removed from list_resumable"
    test "active session not in list_resumable"

    # Multi-cycle tests
    test "session can be resumed → used → closed → resumed again"
  end
end
```

### 2.3 Helper Infrastructure

Create reusable test helpers:

```elixir
# Test setup helpers
- setup_integration_env() - Start app, clear registry/files, create temp dirs
- cleanup_all_sessions() - Stop processes, clear registry, delete files
- wait_for_supervisor() - Poll for SessionSupervisor availability

# Session creation helpers
- test_uuid(index) - Generate valid UUID v4 for tests
- create_test_session(attrs) - Build Session struct
- start_session_with_state(session, messages, todos) - Full setup

# Verification helpers
- assert_session_running(session_id) - Verify processes alive
- assert_session_stopped(session_id) - Verify processes dead
- assert_messages_match(session_id, expected) - Compare conversation
- assert_todos_match(session_id, expected) - Compare task list
- assert_file_exists(session_id) - Check persisted JSON file
- assert_file_deleted(session_id) - Check file removed

# State manipulation helpers
- add_test_messages(session_id, messages) - Populate conversation
- add_test_todos(session_id, todos) - Populate task list
- modify_session_config(session_id, config) - Change LLM settings
```

---

## 3. Test Scenarios

### 3.1 Basic Save-Resume Cycle (Task 6.7.1.2)

**Test**: Create session → add messages → close → verify JSON file created

```elixir
test "complete save cycle creates valid JSON file", ctx do
  # Create session
  {:ok, session} = SessionSupervisor.create_session(project_path: ctx.tmp_dir)

  # Add messages
  msg1 = %{id: "m1", role: :user, content: "Hello", timestamp: DateTime.utc_now()}
  msg2 = %{id: "m2", role: :assistant, content: "Hi!", timestamp: DateTime.utc_now()}
  {:ok, _} = Session.State.append_message(session.id, msg1)
  {:ok, _} = Session.State.append_message(session.id, msg2)

  # Close session (triggers auto-save)
  :ok = SessionSupervisor.stop_session(session.id)

  # Verify JSON file created
  assert_file_exists(session.id)

  # Verify file contents
  {:ok, persisted} = Persistence.load(session.id)
  assert persisted.id == session.id
  assert length(persisted.conversation) == 2
  assert Enum.at(persisted.conversation, 0).content == "Hello"
  assert Enum.at(persisted.conversation, 1).content == "Hi!"
end
```

**Verifies**:
- ✅ Auto-save triggers on session close
- ✅ Messages serialized to JSON correctly
- ✅ File written to correct location
- ✅ JSON is valid and loadable

### 3.2 Resume with Messages (Task 6.7.1.3)

**Test**: Resume session → verify messages restored → verify todos restored

```elixir
test "resume restores messages and todos", ctx do
  # Create and populate session
  {:ok, session} = SessionSupervisor.create_session(project_path: ctx.tmp_dir)
  add_test_messages(session.id, [
    %{id: "m1", role: :user, content: "Message 1"},
    %{id: "m2", role: :assistant, content: "Response 1"}
  ])
  add_test_todos(session.id, [
    %{content: "Task 1", status: :pending, active_form: "Doing task 1"},
    %{content: "Task 2", status: :completed, active_form: "Doing task 2"}
  ])

  # Close (saves to disk)
  :ok = SessionSupervisor.stop_session(session.id)

  # Resume
  {:ok, resumed} = Persistence.resume(session.id)

  # Verify messages restored
  {:ok, messages} = Session.State.get_messages(resumed.id)
  assert length(messages) == 2
  assert Enum.at(messages, 0).content == "Message 1"
  assert Enum.at(messages, 1).content == "Response 1"

  # Verify todos restored
  {:ok, todos} = Session.State.get_todos(resumed.id)
  assert length(todos) == 2
  assert Enum.at(todos, 0).status == :pending
  assert Enum.at(todos, 1).status == :completed
end
```

**Verifies**:
- ✅ Messages survive save-resume cycle
- ✅ Todos survive save-resume cycle
- ✅ Status fields preserved (pending, completed)
- ✅ Session processes started correctly

### 3.3 Session ID Preservation (Task 6.7.1.4)

**Test**: Resume → verify session ID preserved → verify config preserved

```elixir
test "resume preserves session ID and config", ctx do
  # Create session with custom config
  custom_config = %{
    "provider" => "openai",
    "model" => "gpt-4",
    "temperature" => 0.3,
    "max_tokens" => 2048
  }
  {:ok, session} = SessionSupervisor.create_session(
    project_path: ctx.tmp_dir,
    config: custom_config
  )

  original_id = session.id
  original_created_at = session.created_at

  # Close
  :ok = SessionSupervisor.stop_session(session.id)

  # Resume
  {:ok, resumed} = Persistence.resume(original_id)

  # Verify ID preserved
  assert resumed.id == original_id

  # Verify created_at preserved (not reset to now)
  assert DateTime.compare(resumed.created_at, original_created_at) == :eq

  # Verify config preserved
  assert resumed.config["provider"] == "openai"
  assert resumed.config["model"] == "gpt-4"
  assert resumed.config["temperature"] == 0.3
  assert resumed.config["max_tokens"] == 2048
end
```

**Verifies**:
- ✅ Session ID not regenerated on resume
- ✅ Created timestamp preserved
- ✅ Configuration survives persistence
- ✅ All config fields correct type

### 3.4 Persisted File Deletion (Task 6.7.1.5)

**Test**: Resume → persisted file deleted → session now active

```elixir
test "resume deletes persisted file and marks session active", ctx do
  # Create, populate, and close session
  {:ok, session} = SessionSupervisor.create_session(project_path: ctx.tmp_dir)
  add_test_messages(session.id, [%{id: "m1", role: :user, content: "Test"}])
  :ok = SessionSupervisor.stop_session(session.id)

  # Verify file exists
  assert_file_exists(session.id)

  # Verify session NOT in active list
  assert SessionRegistry.lookup(session.id) == {:error, :not_found}

  # Resume
  {:ok, resumed} = Persistence.resume(session.id)

  # Verify file deleted
  assert_file_deleted(session.id)

  # Verify session NOW in active list
  assert {:ok, active_session} = SessionRegistry.lookup(resumed.id)
  assert active_session.id == resumed.id

  # Verify NOT in resumable list
  resumable = Persistence.list_resumable()
  refute Enum.any?(resumable, fn s -> s.id == resumed.id end)
end
```

**Verifies**:
- ✅ Persisted file deleted after successful resume
- ✅ Session transitions from persisted → active
- ✅ Registry reflects active status
- ✅ Session excluded from resumable list

### 3.5 State Transition: Closed → Resumable

**Test**: Session appears in list_resumable after close, disappears after resume

```elixir
test "closed session appears in list_resumable, active session does not", ctx do
  # Create session
  {:ok, session} = SessionSupervisor.create_session(project_path: ctx.tmp_dir)
  session_id = session.id

  # While active, should NOT be in resumable list
  resumable = Persistence.list_resumable()
  refute Enum.any?(resumable, fn s -> s.id == session_id end)

  # Close session
  :ok = SessionSupervisor.stop_session(session_id)

  # Now SHOULD be in resumable list
  resumable = Persistence.list_resumable()
  assert Enum.any?(resumable, fn s -> s.id == session_id end)

  # Resume session
  {:ok, _resumed} = Persistence.resume(session_id)

  # Now should NOT be in resumable list (active again)
  resumable = Persistence.list_resumable()
  refute Enum.any?(resumable, fn s -> s.id == session_id end)
end
```

**Verifies**:
- ✅ Active sessions excluded from resumable list
- ✅ Closed sessions appear in resumable list
- ✅ Resumed sessions excluded from resumable list
- ✅ State transitions tracked correctly

### 3.6 Multi-Cycle Resume

**Test**: Session can be resumed → used → closed → resumed again

```elixir
test "session supports multiple save-resume cycles", ctx do
  # Create and populate session
  {:ok, session} = SessionSupervisor.create_session(project_path: ctx.tmp_dir)
  session_id = session.id
  add_test_messages(session_id, [%{id: "m1", role: :user, content: "First"}])

  # Cycle 1: Close → Resume
  :ok = SessionSupervisor.stop_session(session_id)
  {:ok, resumed1} = Persistence.resume(session_id)
  assert resumed1.id == session_id
  {:ok, msgs1} = Session.State.get_messages(session_id)
  assert length(msgs1) == 1

  # Add more messages
  add_test_messages(session_id, [%{id: "m2", role: :user, content: "Second"}])

  # Cycle 2: Close → Resume
  :ok = SessionSupervisor.stop_session(session_id)
  {:ok, resumed2} = Persistence.resume(session_id)
  assert resumed2.id == session_id
  {:ok, msgs2} = Session.State.get_messages(session_id)
  assert length(msgs2) == 2
  assert Enum.at(msgs2, 0).content == "First"
  assert Enum.at(msgs2, 1).content == "Second"

  # Add more messages
  add_test_messages(session_id, [%{id: "m3", role: :user, content: "Third"}])

  # Cycle 3: Close → Resume
  :ok = SessionSupervisor.stop_session(session_id)
  {:ok, resumed3} = Persistence.resume(session_id)
  {:ok, msgs3} = Session.State.get_messages(session_id)
  assert length(msgs3) == 3
end
```

**Verifies**:
- ✅ Multiple save-resume cycles work
- ✅ State accumulates across cycles
- ✅ No data corruption after multiple cycles
- ✅ File lifecycle correct each time

### 3.7 Error Case: Project Path Deleted

**Test**: Resume when project path no longer exists

```elixir
test "resume fails when project path deleted", ctx do
  # Create session
  project_path = Path.join(ctx.tmp_dir, "test_project")
  File.mkdir_p!(project_path)
  {:ok, session} = SessionSupervisor.create_session(project_path: project_path)
  session_id = session.id

  # Close
  :ok = SessionSupervisor.stop_session(session_id)

  # Delete project directory
  File.rm_rf!(project_path)

  # Resume should fail
  assert {:error, :project_path_not_found} = Persistence.resume(session_id)

  # Verify session NOT started
  assert {:error, :not_found} = SessionRegistry.lookup(session_id)

  # Verify persisted file still exists (not deleted on failure)
  assert_file_exists(session_id)
end
```

**Verifies**:
- ✅ Project path validation works
- ✅ Failed resume doesn't start processes
- ✅ Failed resume leaves file intact
- ✅ Error propagated correctly

### 3.8 Error Case: Corrupted JSON

**Test**: Resume with corrupted JSON file

```elixir
test "resume fails gracefully with corrupted JSON", ctx do
  # Create valid persisted session
  session_id = test_uuid(0)
  persisted = create_persisted_session(session_id, "Test", ctx.tmp_dir)
  :ok = Persistence.write_session_file(session_id, persisted)

  # Corrupt the file
  session_file = Persistence.session_file(session_id)
  File.write!(session_file, "{invalid json content")

  # Resume should fail
  assert {:error, {:invalid_json, _}} = Persistence.resume(session_id)

  # Verify session NOT started
  assert {:error, :not_found} = SessionRegistry.lookup(session_id)
end
```

**Verifies**:
- ✅ JSON parsing errors handled
- ✅ Corrupted files don't crash process
- ✅ Error messages informative
- ✅ System remains stable

### 3.9 Error Case: Signature Verification Failure

**Test**: Resume with tampered signature

```elixir
test "resume fails with signature verification failure", ctx do
  # Create valid persisted session
  session_id = test_uuid(0)
  persisted = create_persisted_session(session_id, "Test", ctx.tmp_dir)
  :ok = Persistence.write_session_file(session_id, persisted)

  # Tamper with file (change content but keep signature)
  session_file = Persistence.session_file(session_id)
  {:ok, json} = File.read(session_file)
  {:ok, data} = Jason.decode(json)
  tampered = Map.put(data, "name", "Tampered Name")
  File.write!(session_file, Jason.encode!(tampered))

  # Resume should fail
  assert {:error, :signature_verification_failed} = Persistence.resume(session_id)

  # Verify session NOT started
  assert {:error, :not_found} = SessionRegistry.lookup(session_id)
end
```

**Verifies**:
- ✅ HMAC signature verification works
- ✅ Tampered files rejected
- ✅ Security boundary enforced
- ✅ Error logged appropriately

### 3.10 Concurrent Access

**Test**: Ensure only one resume per session

```elixir
test "concurrent resume attempts handled safely", ctx do
  # Create persisted session
  {:ok, session} = SessionSupervisor.create_session(project_path: ctx.tmp_dir)
  session_id = session.id
  :ok = SessionSupervisor.stop_session(session_id)

  # Attempt concurrent resumes
  task1 = Task.async(fn -> Persistence.resume(session_id) end)
  task2 = Task.async(fn -> Persistence.resume(session_id) end)

  results = [Task.await(task1), Task.await(task2)]

  # One should succeed, one should fail
  assert Enum.count(results, &match?({:ok, _}, &1)) == 1
  assert Enum.count(results, &match?({:error, _}, &1)) == 1

  # Verify only one session active
  assert {:ok, _} = SessionRegistry.lookup(session_id)
  assert length(SessionRegistry.list_all()) == 1
end
```

**Verifies**:
- ✅ Race conditions handled
- ✅ No duplicate sessions created
- ✅ File deletion atomic
- ✅ Registry consistency maintained

---

## 4. Technical Details

### 4.1 Test File Structure

```elixir
defmodule JidoCode.Integration.SessionPhase6Test do
  use ExUnit.Case, async: false

  alias JidoCode.Session
  alias JidoCode.Session.Persistence
  alias JidoCode.Session.State
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor

  @moduletag :integration
  @moduletag :phase6

  # ============================================================================
  # Setup & Teardown
  # ============================================================================

  setup do
    # Ensure application started
    {:ok, _} = Application.ensure_all_started(:jido_code)

    # Set API keys for LLMAgent
    System.put_env("ANTHROPIC_API_KEY", "test-key-phase6")
    System.put_env("OPENAI_API_KEY", "test-key-phase6")

    # Wait for supervisor
    wait_for_supervisor()

    # Clean slate
    cleanup_all_sessions()

    # Create temp directory
    tmp_base = Path.join(System.tmp_dir!(), "phase6_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_base)

    on_exit(fn ->
      cleanup_all_sessions()
      File.rm_rf!(tmp_base)
    end)

    {:ok, tmp_base: tmp_base}
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp wait_for_supervisor(retries \\ 50) do
    if Process.whereis(SessionSupervisor) do
      :ok
    else
      if retries > 0 do
        Process.sleep(10)
        wait_for_supervisor(retries - 1)
      else
        raise "SessionSupervisor not available"
      end
    end
  end

  defp cleanup_all_sessions do
    # Stop all sessions
    for session <- SessionRegistry.list_all() do
      SessionSupervisor.stop_session(session.id)
    end

    # Clear registry
    SessionRegistry.clear()

    # Delete all persisted files
    sessions_dir = Persistence.sessions_dir()
    if File.exists?(sessions_dir) do
      File.ls!(sessions_dir)
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.each(fn file ->
        File.rm!(Path.join(sessions_dir, file))
      end)
    end
  end

  defp test_uuid(index) do
    # Generate valid UUID v4
    base_id = 20000 + index
    id_str = Integer.to_string(base_id) |> String.pad_leading(12, "0")
    "#{String.slice(id_str, 0..7)}-0000-4000-8000-#{String.slice(id_str, 8..11)}00000000"
  end

  defp add_test_messages(session_id, messages) do
    Enum.each(messages, fn msg ->
      full_msg = Map.merge(%{
        id: "msg-#{:rand.uniform(10000)}",
        role: :user,
        content: "",
        timestamp: DateTime.utc_now()
      }, msg)
      {:ok, _} = State.append_message(session_id, full_msg)
    end)
  end

  defp add_test_todos(session_id, todos) do
    full_todos = Enum.map(todos, fn todo ->
      Map.merge(%{
        content: "",
        status: :pending,
        active_form: ""
      }, todo)
    end)
    {:ok, _} = State.update_todos(session_id, full_todos)
  end

  defp assert_file_exists(session_id) do
    session_file = Persistence.session_file(session_id)
    assert File.exists?(session_file), "Expected persisted file to exist: #{session_file}"
  end

  defp assert_file_deleted(session_id) do
    session_file = Persistence.session_file(session_id)
    refute File.exists?(session_file), "Expected persisted file to be deleted: #{session_file}"
  end

  defp assert_session_running(session_id) do
    assert {:ok, _} = SessionRegistry.lookup(session_id)
    assert SessionSupervisor.session_running?(session_id)
  end

  defp assert_session_stopped(session_id) do
    assert {:error, :not_found} = SessionRegistry.lookup(session_id)
    refute SessionSupervisor.session_running?(session_id)
  end

  defp create_persisted_session(id, name, project_path) do
    now = DateTime.utc_now()
    %{
      version: 1,
      id: id,
      name: name,
      project_path: project_path,
      config: %{
        "provider" => "anthropic",
        "model" => "claude-3-5-haiku-20241022",
        "temperature" => 0.7,
        "max_tokens" => 4096
      },
      created_at: DateTime.to_iso8601(now),
      updated_at: DateTime.to_iso8601(now),
      closed_at: DateTime.to_iso8601(now),
      conversation: [],
      todos: []
    }
  end

  # ============================================================================
  # Test Suites
  # ============================================================================

  describe "6.7.1 save-resume cycle integration" do
    # Tests go here...
  end
end
```

### 4.2 Setup Requirements

**Environment Variables**:
```elixir
System.put_env("ANTHROPIC_API_KEY", "test-key-phase6")
System.put_env("OPENAI_API_KEY", "test-key-phase6")
```

**Application Dependencies**:
- `:jido_code` application started
- `SessionSupervisor` DynamicSupervisor running
- `SessionRegistry` ETS table initialized
- `SessionProcessRegistry` ETS table initialized

**File System**:
- Temp directory created per test run
- `~/.jido_code/sessions/` directory exists
- Clean slate on setup (no leftover files)

### 4.3 Teardown Requirements

**Process Cleanup**:
```elixir
# Stop all test sessions
for session <- SessionRegistry.list_all() do
  SessionSupervisor.stop_session(session.id)
end

# Clear registry
SessionRegistry.clear()
```

**File Cleanup**:
```elixir
# Delete all persisted files
sessions_dir = Persistence.sessions_dir()
if File.exists?(sessions_dir) do
  File.ls!(sessions_dir)
  |> Enum.filter(&String.ends_with?(&1, ".json"))
  |> Enum.each(fn file ->
    File.rm!(Path.join(sessions_dir, file))
  end)
end

# Delete temp directories
File.rm_rf!(tmp_base)
```

### 4.4 Assertions to Make

**Process State**:
- `assert SessionSupervisor.session_running?(session_id)`
- `refute SessionSupervisor.session_running?(session_id)`
- `assert {:ok, _pid} = Session.Supervisor.get_manager(session_id)`
- `assert {:ok, _pid} = Session.Supervisor.get_state(session_id)`

**Registry State**:
- `assert {:ok, session} = SessionRegistry.lookup(session_id)`
- `assert {:error, :not_found} = SessionRegistry.lookup(session_id)`
- `assert length(SessionRegistry.list_all()) == N`

**File System**:
- `assert File.exists?(Persistence.session_file(session_id))`
- `refute File.exists?(Persistence.session_file(session_id))`
- `assert {:ok, persisted} = Persistence.load(session_id)`

**Session State**:
- `assert {:ok, messages} = State.get_messages(session_id)`
- `assert length(messages) == N`
- `assert Enum.at(messages, 0).content == "Expected"`
- `assert {:ok, todos} = State.get_todos(session_id)`
- `assert Enum.at(todos, 0).status == :pending`

**Data Integrity**:
- `assert resumed.id == original_id`
- `assert resumed.config == original_config`
- `assert DateTime.compare(resumed.created_at, original_created_at) == :eq`

---

## 5. Success Criteria

### 5.1 All Tests Pass

```bash
$ mix test test/jido_code/integration/session_phase6_test.exs
..........
Finished in 2.5 seconds (0.1s async, 2.4s sync)
10 tests, 0 failures
```

### 5.2 Coverage of All Workflows

✅ **Basic Cycle**:
- Create → Add State → Close → Save → Resume → Verify

✅ **Data Preservation**:
- Messages preserved through cycle
- Todos preserved through cycle
- Config preserved through cycle
- Session ID preserved through cycle
- Timestamps preserved correctly

✅ **State Transitions**:
- Active → Closed (file created)
- Closed → Resumable (appears in list)
- Resumable → Active (file deleted)

✅ **Error Handling**:
- Project path deleted
- Corrupted JSON
- Signature verification failure
- Concurrent resume attempts

✅ **Multi-Cycle**:
- Multiple save-resume cycles work
- State accumulates correctly
- No data corruption

### 5.3 No Resource Leaks

**Verified via**:
- All sessions stopped in teardown
- All files deleted in teardown
- Registry cleared properly
- No orphaned processes

### 5.4 Real Infrastructure Used

**Verified via**:
- No mocks used in tests
- Real SessionSupervisor used
- Real file I/O performed
- Real Registry operations

---

## 6. Implementation Plan

### 6.1 Step 1: Create Test File

**File**: `test/jido_code/integration/session_phase6_test.exs`

**Actions**:
- Create module structure
- Add moduletag `:integration` and `:phase6`
- Set `async: false`
- Add module aliases

**Verification**: File compiles without errors

### 6.2 Step 2: Implement Setup/Teardown

**Actions**:
- Implement `setup` callback
- Create `wait_for_supervisor/1` helper
- Create `cleanup_all_sessions/0` helper
- Create `test_uuid/1` helper
- Test that setup/teardown works

**Verification**: Empty test passes with setup/teardown

### 6.3 Step 3: Implement Test Helpers

**Actions**:
- Create `add_test_messages/2`
- Create `add_test_todos/2`
- Create `assert_file_exists/1`
- Create `assert_file_deleted/1`
- Create `assert_session_running/1`
- Create `assert_session_stopped/1`
- Create `create_persisted_session/3`

**Verification**: Helpers compile and work in isolation

### 6.4 Step 4: Write Basic Cycle Tests

**Tests to Write**:
1. "complete save cycle creates valid JSON file"
2. "resume restores messages and todos"
3. "resume preserves session ID and config"
4. "resume deletes persisted file and marks session active"

**Verification**: Basic cycle tests pass

### 6.5 Step 5: Write State Transition Tests

**Tests to Write**:
1. "closed session appears in list_resumable, active session does not"
2. "session supports multiple save-resume cycles"

**Verification**: State transition tests pass

### 6.6 Step 6: Write Error Case Tests

**Tests to Write**:
1. "resume fails when project path deleted"
2. "resume fails gracefully with corrupted JSON"
3. "resume fails with signature verification failure"
4. "concurrent resume attempts handled safely"

**Verification**: Error case tests pass

### 6.7 Step 7: Run Full Suite

**Actions**:
- Run all tests in file
- Verify coverage of all workflows
- Check for flaky tests
- Ensure cleanup works correctly

**Verification**: All tests pass consistently

### 6.8 Step 8: Document and Review

**Actions**:
- Add module documentation
- Document each test's purpose
- Add inline comments for complex logic
- Review test quality

**Verification**: Tests are readable and maintainable

---

## 7. Testing Infrastructure

### 7.1 Reusable Helpers

**Session Lifecycle**:
```elixir
def create_and_close_session(tmp_dir, opts \\ []) do
  {:ok, session} = SessionSupervisor.create_session([project_path: tmp_dir] ++ opts)
  :ok = SessionSupervisor.stop_session(session.id)
  session
end

def resume_and_verify(session_id) do
  {:ok, resumed} = Persistence.resume(session_id)
  assert_session_running(session_id)
  resumed
end
```

**State Population**:
```elixir
def populate_session_state(session_id, messages, todos) do
  add_test_messages(session_id, messages)
  add_test_todos(session_id, todos)
  :ok
end

def get_session_state(session_id) do
  {:ok, messages} = State.get_messages(session_id)
  {:ok, todos} = State.get_todos(session_id)
  %{messages: messages, todos: todos}
end
```

**Verification**:
```elixir
def assert_state_matches(session_id, expected_messages, expected_todos) do
  {:ok, messages} = State.get_messages(session_id)
  {:ok, todos} = State.get_todos(session_id)

  assert length(messages) == length(expected_messages)
  assert length(todos) == length(expected_todos)

  Enum.zip(messages, expected_messages)
  |> Enum.each(fn {actual, expected} ->
    assert actual.content == expected.content
    assert actual.role == expected.role
  end)

  Enum.zip(todos, expected_todos)
  |> Enum.each(fn {actual, expected} ->
    assert actual.content == expected.content
    assert actual.status == expected.status
  end)
end
```

### 7.2 Test Data Builders

**Message Builder**:
```elixir
def build_message(attrs \\ %{}) do
  Map.merge(%{
    id: "msg-#{:rand.uniform(10000)}",
    role: :user,
    content: "Test message",
    timestamp: DateTime.utc_now()
  }, attrs)
end
```

**Todo Builder**:
```elixir
def build_todo(attrs \\ %{}) do
  Map.merge(%{
    content: "Test task",
    status: :pending,
    active_form: "Testing task"
  }, attrs)
end
```

**Persisted Session Builder**:
```elixir
def build_persisted_session(attrs \\ %{}) do
  now = DateTime.utc_now()

  Map.merge(%{
    version: 1,
    id: test_uuid(0),
    name: "Test Session",
    project_path: System.tmp_dir!(),
    config: %{
      "provider" => "anthropic",
      "model" => "claude-3-5-haiku-20241022",
      "temperature" => 0.7,
      "max_tokens" => 4096
    },
    created_at: DateTime.to_iso8601(now),
    updated_at: DateTime.to_iso8601(now),
    closed_at: DateTime.to_iso8601(now),
    conversation: [],
    todos: []
  }, attrs)
end
```

### 7.3 Wait Utilities

**Wait for Process Death**:
```elixir
def wait_for_process_death(pid, timeout \\ 1000) do
  ref = Process.monitor(pid)

  receive do
    {:DOWN, ^ref, :process, ^pid, _} -> :ok
  after
    timeout ->
      Process.demonitor(ref, [:flush])
      {:error, :timeout}
  end
end
```

**Wait for File Deletion**:
```elixir
def wait_for_file_deletion(path, timeout \\ 1000) do
  wait_until(timeout, 10, fn ->
    not File.exists?(path)
  end)
end

defp wait_until(timeout, interval, predicate) do
  if predicate.() do
    :ok
  else
    if timeout > 0 do
      Process.sleep(interval)
      wait_until(timeout - interval, interval, predicate)
    else
      {:error, :timeout}
    end
  end
end
```

---

## 8. Notes and Considerations

### 8.1 Why async: false?

These tests MUST run sequentially because:

1. **Shared SessionSupervisor**: All tests use the same DynamicSupervisor
2. **Shared SessionRegistry**: ETS table is global state
3. **Shared File System**: Tests write to `~/.jido_code/sessions/`
4. **Process Names**: Registry names must be unique

Running async could cause:
- Session ID collisions
- Registry race conditions
- File system conflicts
- Flaky test failures

### 8.2 Test Isolation

Each test ensures isolation via:
- Unique session IDs (via `test_uuid/1`)
- Unique temp directories (via `:rand.uniform`)
- Cleanup in `setup` and `on_exit`
- Defensive cleanup (checks if processes exist before stopping)

### 8.3 Performance Considerations

Integration tests are slower than unit tests because:
- Real process startup/shutdown
- File I/O operations
- Registry operations
- Session lifecycle overhead

Expected runtime: ~2-3 seconds for full suite

### 8.4 Debugging Tips

**If tests fail**:
1. Check `tmp_dir` wasn't cleaned up (comment out `File.rm_rf!`)
2. Inspect persisted JSON files manually
3. Use `IO.inspect/2` to debug state
4. Run with `mix test --trace` for verbose output
5. Run single test with `mix test path/to/file.exs:line_number`

**Common issues**:
- SessionSupervisor not started → increase wait timeout
- Registry not cleared → verify cleanup logic
- File permissions → check `~/.jido_code/sessions/` exists
- Process leaks → verify `on_exit` runs

### 8.5 Future Enhancements

Potential additions:
- Performance benchmarks (measure cycle time)
- Stress tests (100+ sessions)
- Concurrent resume tests (multiple sessions)
- Large session tests (1000+ messages)
- Format migration tests (v1 → v2 schema)

---

## 9. References

### 9.1 Related Files

**Implementation**:
- `/home/ducky/code/jido_code/lib/jido_code/session/persistence.ex` - Core persistence logic
- `/home/ducky/code/jido_code/lib/jido_code/session/manager.ex` - Session process manager
- `/home/ducky/code/jido_code/lib/jido_code/session/state.ex` - Session state management
- `/home/ducky/code/jido_code/lib/jido_code/session_supervisor.ex` - Session lifecycle

**Tests**:
- `/home/ducky/code/jido_code/test/jido_code/session/persistence_test.exs` - Persistence unit tests
- `/home/ducky/code/jido_code/test/jido_code/session/persistence_resume_test.exs` - Resume unit tests
- `/home/ducky/code/jido_code/test/jido_code/integration/session_phase1_test.exs` - Phase 1 integration tests
- `/home/ducky/code/jido_code/test/jido_code/integration/session_phase5_test.exs` - Phase 5 integration tests

**Planning**:
- `/home/ducky/code/jido_code/notes/planning/work-session/phase-06.md` - Phase 6 plan

### 9.2 Task Breakdown

From Phase 6 plan (lines 506-516):

```markdown
### 6.7.1 Save-Resume Cycle Integration
- [ ] 6.7.1.1 Create test/jido_code/integration/session_phase6_test.exs
- [ ] 6.7.1.2 Test: Create session → add messages → close → verify JSON file created
- [ ] 6.7.1.3 Test: Resume session → verify messages restored → verify todos restored
- [ ] 6.7.1.4 Test: Resume → verify session ID preserved → verify config preserved
- [ ] 6.7.1.5 Test: Resume → persisted file deleted → session now active
- [ ] 6.7.1.6 Write all save-resume cycle integration tests
```

### 9.3 Dependencies

**Modules Used**:
- `JidoCode.Session` - Session struct and validation
- `JidoCode.Session.Persistence` - Save/load/resume logic
- `JidoCode.Session.State` - Message and todo management
- `JidoCode.SessionRegistry` - Session tracking
- `JidoCode.SessionSupervisor` - Session lifecycle management

**External Dependencies**:
- ExUnit - Test framework
- File - File system operations
- Jason - JSON encoding/decoding

---

## 10. Summary

This document provides a comprehensive plan for implementing Task 6.7.1 - Save-Resume Cycle Integration Tests. The tests will verify that Phase 6's persistence functionality works end-to-end by:

1. Testing complete save-resume cycles with real infrastructure
2. Verifying data integrity (messages, todos, config) survives persistence
3. Ensuring proper state transitions (active ↔ closed ↔ resumable)
4. Validating file lifecycle (creation, deletion, cleanup)
5. Testing error cases (deleted projects, corrupted files, concurrent access)
6. Confirming multi-cycle support (resume → use → close → resume again)

**Key principles**:
- Use REAL processes, files, and registry (no mocks)
- Test ONE complete workflow per test
- Ensure proper cleanup (no resource leaks)
- Run sequentially (async: false)
- Make tests readable and maintainable

**Success criteria**:
- All 10+ tests pass consistently
- Zero data loss through complete cycles
- All resources cleaned up properly
- Error cases handled gracefully
- Tests serve as documentation of expected behavior

Implementation should follow the 8-step plan, building up from helpers to basic tests to error cases, ensuring each step works before proceeding to the next.

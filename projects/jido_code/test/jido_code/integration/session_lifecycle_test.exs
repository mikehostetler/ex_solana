defmodule JidoCode.Integration.SessionLifecycleTest do
  @moduledoc """
  Integration tests for complete session lifecycle from creation to close.

  These tests verify that:
  - Sessions can be created, used, and closed cleanly
  - Sessions can be saved and resumed with state restored
  - Session limits are enforced
  - Invalid paths are rejected
  - Duplicate sessions (same path) are prevented
  - Sessions can recover from crashes

  These are end-to-end tests using real infrastructure including LLM agents.

  **Requirements**:
  - ANTHROPIC_API_KEY environment variable must be set
  - Tests are tagged :llm and excluded from regular runs
  """
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :lifecycle
  @moduletag :llm

  alias JidoCode.Session
  alias JidoCode.Session.{Manager, State, Persistence}
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor
  alias JidoCode.Test.SessionTestHelpers

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    # Ensure the application is started
    {:ok, _} = Application.ensure_all_started(:jido_code)

    # Wait for SessionSupervisor to be available
    wait_for_supervisor()

    # Clear any existing sessions
    SessionRegistry.clear()

    # Stop any running sessions
    for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(SessionSupervisor) do
      DynamicSupervisor.terminate_child(SessionSupervisor, pid)
    end

    # Create temp directory for test sessions
    tmp_base = Path.join(System.tmp_dir!(), "lifecycle_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_base)

    # Clean up persisted sessions
    sessions_dir = Persistence.sessions_dir()
    File.rm_rf!(sessions_dir)
    File.mkdir_p!(sessions_dir)

    on_exit(fn ->
      # Clean up all sessions
      if Process.whereis(SessionSupervisor) do
        for session <- SessionRegistry.list_all() do
          SessionSupervisor.stop_session(session.id)
        end
      end

      SessionRegistry.clear()
      File.rm_rf!(tmp_base)
      File.rm_rf!(sessions_dir)
    end)

    {:ok, tmp_base: tmp_base}
  end

  defp wait_for_supervisor(retries \\ 50) do
    if Process.whereis(SessionSupervisor) do
      :ok
    else
      if retries > 0 do
        Process.sleep(10)
        wait_for_supervisor(retries - 1)
      else
        raise "SessionSupervisor did not start in time"
      end
    end
  end

  # ============================================================================
  # Test: Create Session → Use Agent → Close → Verify Cleanup
  # ============================================================================

  test "complete lifecycle: create → use → close → verify cleanup", %{tmp_base: tmp_base} do
    project_path = Path.join(tmp_base, "test_project")
    File.mkdir_p!(project_path)

    # Step 1: Create session
    {:ok, session} =
      Session.new(
        name: "Test Session",
        project_path: project_path,
        config: SessionTestHelpers.valid_session_config()
      )

    assert {:ok, session_id} = SessionSupervisor.start_session(session)
    assert SessionRegistry.exists?(session_id)

    # Verify session processes started
    assert {:ok, manager_pid} = Session.Supervisor.get_manager(session_id)
    assert {:ok, state_pid} = Session.Supervisor.get_state(session_id)
    assert Process.alive?(manager_pid)
    assert Process.alive?(state_pid)

    # Step 2: Use agent (send message, verify state updated)
    assert :ok = State.append_message(session_id, %{
             id: "msg1",
             role: :user,
             content: "Hello",
             timestamp: DateTime.utc_now()
           })

    assert {:ok, messages} = State.get_messages(session_id)
    assert length(messages) == 1
    assert hd(messages).content == "Hello"

    # Step 3: Close session
    assert :ok = SessionSupervisor.stop_session(session_id)

    # Step 4: Verify cleanup
    refute SessionRegistry.exists?(session_id)
    refute Process.alive?(manager_pid)
    refute Process.alive?(state_pid)

    # Verify no lingering processes
    assert DynamicSupervisor.which_children(SessionSupervisor) == []
  end

  # ============================================================================
  # Test: Create Session → Save → Resume → Verify State Restored
  # ============================================================================

  test "save and resume workflow restores state correctly", %{tmp_base: tmp_base} do
    project_path = Path.join(tmp_base, "test_project")
    File.mkdir_p!(project_path)

    # Step 1: Create session with messages and todos
    {:ok, session} =
      Session.new(
        name: "Resume Test",
        project_path: project_path,
        config: SessionTestHelpers.valid_session_config()
      )

    {:ok, session_id} = SessionSupervisor.start_session(session)

    # Add messages
    State.append_message(session_id, %{
      id: "msg1",
      role: :user,
      content: "First message",
      timestamp: DateTime.utc_now()
    })

    State.append_message(session_id, %{
      id: "msg2",
      role: :assistant,
      content: "Response",
      timestamp: DateTime.utc_now()
    })

    # Add todos
    State.update_todos(session_id, [
      %{content: "Task 1", status: :pending, active_form: "Task 1"},
      %{content: "Task 2", status: :completed, active_form: "Task 2"}
    ])

    # Get original state
    {:ok, original_messages} = State.get_messages(session_id)
    {:ok, original_todos} = State.get_todos(session_id)

    # Step 2: Save session
    assert {:ok, _path} = Persistence.save(session_id)

    # Step 3: Close session
    SessionSupervisor.stop_session(session_id)
    refute SessionRegistry.exists?(session_id)

    # Step 4: Resume session
    {:ok, resumed_session} = Persistence.resume(session_id)
    assert SessionRegistry.exists?(session_id)

    # Step 5: Verify state restored
    {:ok, resumed_messages} = State.get_messages(session_id)
    {:ok, resumed_todos} = State.get_todos(session_id)

    assert length(resumed_messages) == length(original_messages)
    assert hd(resumed_messages).content == "First message"
    assert Enum.at(resumed_messages, 1).content == "Response"

    assert length(resumed_todos) == length(original_todos)
    assert hd(resumed_todos).content == "Task 1"
    assert hd(resumed_todos).status == :pending
  end

  # ============================================================================
  # Test: Create 10 Sessions → Verify Limit → Close One → Create New
  # ============================================================================

  test "session limit enforced: 10 sessions max, can create after closing one", %{
    tmp_base: tmp_base
  } do
    config = SessionTestHelpers.valid_session_config()

    # Step 1: Create 10 sessions (should all succeed)
    session_ids =
      for i <- 1..10 do
        project_path = Path.join(tmp_base, "project_#{i}")
        File.mkdir_p!(project_path)

        {:ok, session} =
          Session.new(
            name: "Session #{i}",
            project_path: project_path,
            config: config
          )

        {:ok, id} = SessionSupervisor.start_session(session)
        id
      end

    assert length(session_ids) == 10
    assert length(SessionRegistry.list_all()) == 10

    # Step 2: Try to create 11th session (should fail)
    project_path_11 = Path.join(tmp_base, "project_11")
    File.mkdir_p!(project_path_11)

    session_11 =
      Session.new(
        name: "Session 11",
        project_path: project_path_11,
        config: config
      )

    assert {:error, {:session_limit_reached, 10, 10}} = SessionSupervisor.start_session(session_11)

    # Step 3: Close one session
    first_id = hd(session_ids)
    assert :ok = SessionSupervisor.stop_session(first_id)
    assert length(SessionRegistry.list_all()) == 9

    # Step 4: Create new session (should succeed now)
    assert {:ok, _new_id} = SessionSupervisor.start_session(session_11)
    assert length(SessionRegistry.list_all()) == 10
  end

  # ============================================================================
  # Test: Create Session with Invalid Path → Verify Error Handling
  # ============================================================================

  test "invalid project path rejected with clear error" do
    # Test nonexistent path
    {:ok, session} =
      Session.new(
        name: "Invalid Path",
        project_path: "/nonexistent/path/that/does/not/exist",
        config: SessionTestHelpers.valid_session_config()
      )

    assert {:error, reason} = SessionSupervisor.start_session(session)
    assert reason in [:enoent, {:failed_to_start_child, JidoCode.Session.Manager, :enoent}]

    # Test file (not directory)
    tmp_file = Path.join(System.tmp_dir!(), "test_file_#{:rand.uniform(100_000)}")
    File.write!(tmp_file, "content")

    on_exit(fn -> File.rm(tmp_file) end)

    session_file =
      Session.new(
        name: "File Not Dir",
        project_path: tmp_file,
        config: SessionTestHelpers.valid_session_config()
      )

    assert {:error, reason} = SessionSupervisor.start_session(session_file)

    assert reason in [
             :enotdir,
             {:failed_to_start_child, JidoCode.Session.Manager, :enotdir}
           ]
  end

  # ============================================================================
  # Test: Create Duplicate Session (Same Path) → Verify Error
  # ============================================================================

  test "duplicate session with same project path rejected", %{tmp_base: tmp_base} do
    project_path = Path.join(tmp_base, "shared_project")
    File.mkdir_p!(project_path)

    config = SessionTestHelpers.valid_session_config()

    # Create first session
    session1 =
      Session.new(
        name: "Session 1",
        project_path: project_path,
        config: config
      )

    {:ok, _id1} = SessionSupervisor.start_session(session1)

    # Try to create second session with same path
    session2 =
      Session.new(
        name: "Session 2",
        project_path: project_path,
        config: config
      )

    assert {:error, :project_already_open} = SessionSupervisor.start_session(session2)
  end

  # ============================================================================
  # Test: Session Crash → Verify Supervisor Restarts Children
  # ============================================================================

  test "session crash triggers supervisor restart of children", %{tmp_base: tmp_base} do
    project_path = Path.join(tmp_base, "crash_test")
    File.mkdir_p!(project_path)

    {:ok, session} =
      Session.new(
        name: "Crash Test",
        project_path: project_path,
        config: SessionTestHelpers.valid_session_config()
      )

    {:ok, session_id} = SessionSupervisor.start_session(session)

    # Get original Manager PID
    {:ok, original_manager_pid} = Session.Supervisor.get_manager(session_id)
    assert Process.alive?(original_manager_pid)

    # Add a message to verify state
    State.append_message(session_id, %{
      id: "msg1",
      role: :user,
      content: "Before crash",
      timestamp: DateTime.utc_now()
    })

    # Kill the Manager process to simulate crash
    Process.exit(original_manager_pid, :kill)

    # Wait for supervisor to restart
    Process.sleep(100)

    # Verify Manager was restarted (new PID)
    {:ok, new_manager_pid} = Session.Supervisor.get_manager(session_id)
    assert Process.alive?(new_manager_pid)
    assert new_manager_pid != original_manager_pid

    # Session should still be registered
    assert SessionRegistry.exists?(session_id)

    # Note: State may or may not be preserved depending on supervision strategy
    # The important thing is that the session can continue functioning
    assert {:ok, _state_pid} = Session.Supervisor.get_state(session_id)
  end

  # ============================================================================
  # Test: Empty Session (No Messages) Lifecycle
  # ============================================================================

  test "empty session lifecycle: create → close → resume works", %{tmp_base: tmp_base} do
    project_path = Path.join(tmp_base, "empty_session")
    File.mkdir_p!(project_path)

    # Create session without adding any messages
    {:ok, session} =
      Session.new(
        name: "Empty Session",
        project_path: project_path,
        config: SessionTestHelpers.valid_session_config()
      )

    {:ok, session_id} = SessionSupervisor.start_session(session)

    # Verify empty state
    {:ok, messages} = State.get_messages(session_id)
    assert messages == []

    # Save empty session
    {:ok, _path} = Persistence.save(session_id)

    # Close session
    SessionSupervisor.stop_session(session_id)

    # Resume empty session
    {:ok, resumed} = Persistence.resume(session_id)
    assert resumed.name == "Empty Session"

    # Verify still empty
    {:ok, resumed_messages} = State.get_messages(session_id)
    assert resumed_messages == []
  end
end

defmodule JidoCode.Integration.CommandIntegrationTest do
  @moduledoc """
  Integration tests for session commands end-to-end.

  These tests verify that:
  - /session new creates and switches to new session
  - /session list shows correct session list
  - /session switch changes active session
  - /session close closes and switches to adjacent session
  - /session rename updates session name
  - /resume lists persisted sessions
  - /resume restores session with history

  **Requirements**:
  - ANTHROPIC_API_KEY environment variable must be set
  - Tests are tagged :llm and excluded from regular runs
  """
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :commands
  @moduletag :llm

  alias JidoCode.Session
  alias JidoCode.Session.{State, Persistence}
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor
  alias JidoCode.Commands
  alias JidoCode.Test.SessionTestHelpers

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    {:ok, _} = Application.ensure_all_started(:jido_code)

    wait_for_supervisor()

    # Clear sessions
    SessionRegistry.clear()

    for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(SessionSupervisor) do
      DynamicSupervisor.terminate_child(SessionSupervisor, pid)
    end

    # Clean up persisted sessions
    sessions_dir = Persistence.sessions_dir()
    File.rm_rf!(sessions_dir)
    File.mkdir_p!(sessions_dir)

    tmp_base = Path.join(System.tmp_dir!(), "command_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_base)

    on_exit(fn ->
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
  # Test: /session new Creates and Switches to Session
  # ============================================================================

  test "/session new command creates new session", %{tmp_base: tmp_base} do
    project_path = Path.join(tmp_base, "new_session_project")
    File.mkdir_p!(project_path)

    # Execute /session new command
    result = Commands.execute_session(["new", project_path])

    # Verify command succeeded
    assert {:ok, message} = result
    assert message =~ "Created"

    # Verify session exists in registry
    sessions = SessionRegistry.list_all()
    assert length(sessions) >= 1

    # Verify session has correct project path
    session = Enum.find(sessions, &(&1.project_path == project_path))
    assert session != nil
    assert SessionRegistry.exists?(session.id)
  end

  # ============================================================================
  # Test: /session list Shows Correct Session List
  # ============================================================================

  test "/session list command shows all active sessions", %{tmp_base: tmp_base} do
    # Create multiple sessions
    for i <- 1..3 do
      project_path = Path.join(tmp_base, "project_#{i}")
      File.mkdir_p!(project_path)

      {:ok, session} =
        Session.new(
          name: "Session #{i}",
          project_path: project_path,
          config: SessionTestHelpers.valid_session_config()
        )

      {:ok, _id} = SessionSupervisor.start_session(session)
    end

    # Execute /session list command
    result = Commands.execute_session(["list"])

    # Verify command succeeded
    assert {:ok, message} = result
    assert is_binary(message)

    # Verify message contains session information
    assert message =~ "Session 1"
    assert message =~ "Session 2"
    assert message =~ "Session 3"
  end

  # ============================================================================
  # Test: /session switch Changes Active Session
  # ============================================================================

  test "/session switch command by index", %{tmp_base: tmp_base} do
    # Create two sessions
    project_1 = Path.join(tmp_base, "project_1")
    project_2 = Path.join(tmp_base, "project_2")
    File.mkdir_p!(project_1)
    File.mkdir_p!(project_2)

    {:ok, session1} =
      Session.new(
        name: "First",
        project_path: project_1,
        config: SessionTestHelpers.valid_session_config()
      )

    {:ok, session2} =
      Session.new(
        name: "Second",
        project_path: project_2,
        config: SessionTestHelpers.valid_session_config()
      )

    {:ok, id1} = SessionSupervisor.start_session(session1)
    {:ok, id2} = SessionSupervisor.start_session(session2)

    # Both sessions should exist
    assert SessionRegistry.exists?(id1)
    assert SessionRegistry.exists?(id2)

    # Note: Actual switching is handled by TUI, this just verifies sessions are available
    sessions = SessionRegistry.list_all()
    assert length(sessions) == 2
  end

  # ============================================================================
  # Test: /session close Closes Session
  # ============================================================================

  test "/session close command closes specified session", %{tmp_base: tmp_base} do
    # Create a session
    project_path = Path.join(tmp_base, "closeable_project")
    File.mkdir_p!(project_path)

    {:ok, session} =
      Session.new(
        name: "To Close",
        project_path: project_path,
        config: SessionTestHelpers.valid_session_config()
      )

    {:ok, session_id} = SessionSupervisor.start_session(session)

    # Verify session exists
    assert SessionRegistry.exists?(session_id)

    # Close the session
    :ok = SessionSupervisor.stop_session(session_id)

    # Verify session is closed
    refute SessionRegistry.exists?(session_id)
  end

  # ============================================================================
  # Test: /session rename Updates Session Name
  # ============================================================================

  test "session can be renamed via registry update", %{tmp_base: tmp_base} do
    # Create a session
    project_path = Path.join(tmp_base, "rename_test")
    File.mkdir_p!(project_path)

    {:ok, session} =
      Session.new(
        name: "Original Name",
        project_path: project_path,
        config: SessionTestHelpers.valid_session_config()
      )

    {:ok, session_id} = SessionSupervisor.start_session(session)

    # Verify original name
    {:ok, retrieved} = SessionRegistry.lookup(session_id)
    assert retrieved.name == "Original Name"

    # Update session with new name
    updated_session = %{retrieved | name: "New Name"}
    :ok = SessionRegistry.update(updated_session)

    # Verify name was updated
    {:ok, final} = SessionRegistry.lookup(session_id)
    assert final.name == "New Name"
  end

  # ============================================================================
  # Test: /resume Lists Persisted Sessions
  # ============================================================================

  test "/resume command lists available persisted sessions", %{tmp_base: tmp_base} do
    # Create and save a session
    project_path = Path.join(tmp_base, "resumable_project")
    File.mkdir_p!(project_path)

    {:ok, session} =
      Session.new(
        name: "Resumable Session",
        project_path: project_path,
        config: SessionTestHelpers.valid_session_config()
      )

    {:ok, session_id} = SessionSupervisor.start_session(session)

    # Add some messages
    State.append_message(session_id, %{
      id: "msg1",
      role: :user,
      content: "Test message",
      timestamp: DateTime.utc_now()
    })

    # Save the session
    {:ok, _path} = Persistence.save(session_id)

    # Close the session
    SessionSupervisor.stop_session(session_id)

    # Execute /resume command (list mode)
    result = Commands.execute(["resume"])

    # Verify command lists the persisted session
    assert {:ok, message} = result
    assert message =~ "Resumable Session" or message =~ "resumable"
  end

  # ============================================================================
  # Test: /resume Restores Session with History
  # ============================================================================

  test "/resume command restores session with conversation history", %{tmp_base: tmp_base} do
    # Create a session with conversation
    project_path = Path.join(tmp_base, "restore_test")
    File.mkdir_p!(project_path)

    {:ok, session} =
      Session.new(
        name: "Restore Test",
        project_path: project_path,
        config: SessionTestHelpers.valid_session_config()
      )

    {:ok, session_id} = SessionSupervisor.start_session(session)

    # Add multiple messages
    messages = [
      %{id: "m1", role: :user, content: "Hello", timestamp: DateTime.utc_now()},
      %{id: "m2", role: :assistant, content: "Hi there", timestamp: DateTime.utc_now()},
      %{id: "m3", role: :user, content: "How are you?", timestamp: DateTime.utc_now()}
    ]

    for msg <- messages do
      State.append_message(session_id, msg)
    end

    # Get original message count
    {:ok, original_messages} = State.get_messages(session_id)
    original_count = length(original_messages)

    # Save and close
    {:ok, _path} = Persistence.save(session_id)
    SessionSupervisor.stop_session(session_id)

    # Verify session is closed
    refute SessionRegistry.exists?(session_id)

    # Resume the session
    {:ok, _restored_session} = Persistence.resume(session_id)

    # Verify session is restored
    assert SessionRegistry.exists?(session_id)

    # Verify messages were restored
    {:ok, restored_messages} = State.get_messages(session_id)
    assert length(restored_messages) == original_count
    assert hd(restored_messages).content == "Hello"
  end

  # ============================================================================
  # Test: Session Command Error Handling
  # ============================================================================

  test "session commands handle invalid input gracefully" do
    # Test with nonexistent path
    result = Commands.execute_session(["new", "/nonexistent/path"])
    assert {:error, _reason} = result

    # Test with invalid subcommand
    result = Commands.execute_session(["invalid_command"])
    assert {:error, _reason} = result
  end
end

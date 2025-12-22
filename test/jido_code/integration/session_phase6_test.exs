defmodule JidoCode.Integration.SessionPhase6Test do
  @moduledoc """
  Integration tests for Phase 6 (Session Persistence) components.

  These tests verify that all Phase 6 components work together correctly:
  - Session saving on close (auto-save)
  - Session listing (persisted and resumable)
  - Session restoration from persisted files
  - Resume command (/resume)
  - Cleanup and maintenance (delete, clear, cleanup)

  Tests use the application's real infrastructure and verify complete
  save-resume cycles end-to-end.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import JidoCode.PersistenceTestHelpers

  alias JidoCode.Session
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor
  alias JidoCode.Session.Persistence

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    # Set API key for test sessions
    System.put_env("ANTHROPIC_API_KEY", "test-key-for-phase6-integration")

    # Ensure the application is started
    {:ok, _} = Application.ensure_all_started(:jido_code)

    # Wait for SessionSupervisor to be available
    wait_for_supervisor()

    # Clear any existing test sessions from Registry
    SessionRegistry.clear()

    # Stop any running sessions under SessionSupervisor
    for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(SessionSupervisor) do
      DynamicSupervisor.terminate_child(SessionSupervisor, pid)
    end

    # Clean up sessions directory
    sessions_dir = Persistence.sessions_dir()
    File.rm_rf!(sessions_dir)
    File.mkdir_p!(sessions_dir)

    # Create temp base directory for test sessions
    tmp_base = Path.join(System.tmp_dir!(), "phase6_integration_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_base)

    on_exit(fn ->
      # Stop all test sessions
      if Process.whereis(SessionSupervisor) do
        for session <- SessionRegistry.list_all() do
          SessionSupervisor.stop_session(session.id)
        end
      end

      # Clean up temp directories
      File.rm_rf!(tmp_base)
      File.rm_rf!(sessions_dir)
    end)

    {:ok, tmp_base: tmp_base}
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  # Removed: wait_for_supervisor/1 now imported from PersistenceTestHelpers

  defp create_test_session(tmp_base, name \\ "Test Session") do
    project_path = Path.join(tmp_base, name |> String.downcase() |> String.replace(" ", "_"))
    File.mkdir_p!(project_path)

    config = %{
      provider: "anthropic",
      model: "claude-3-5-haiku-20241022",
      temperature: 0.7,
      max_tokens: 4096
    }

    {:ok, session} =
      SessionSupervisor.create_session(project_path: project_path, name: name, config: config)

    session
  end

  defp add_messages_to_session(session_id, count \\ 3) do
    Enum.each(1..count, fn i ->
      message = %{
        id: "test-msg-#{i}-#{System.unique_integer([:positive])}",
        role: :user,
        content: "Test message #{i}",
        timestamp: DateTime.utc_now()
      }

      Session.State.append_message(session_id, message)
    end)
  end

  defp add_todos_to_session(session_id, count \\ 2) do
    todos =
      Enum.map(1..count, fn i ->
        %{
          content: "Test todo #{i}",
          status: if(rem(i, 2) == 0, do: :pending, else: :completed),
          activeForm: "Working on todo #{i}"
        }
      end)

    Session.State.update_todos(session_id, todos)
  end

  # Removed: wait_for_file/2 replaced with wait_for_persisted_file/2 from PersistenceTestHelpers
  # All call sites below use wait_for_persisted_file/2 imported from helpers module
  defp wait_for_file(file_path, retries \\ 50), do: wait_for_persisted_file(file_path, retries)

  # ============================================================================
  # Tests
  # ============================================================================

  test "complete save-resume cycle: create, add data, close, resume", %{tmp_base: tmp_base} do
    # Create session
    session = create_test_session(tmp_base, "Cycle Test")

    # Add messages and todos
    add_messages_to_session(session.id, 3)
    add_todos_to_session(session.id, 2)

    # Get state before closing
    {:ok, original_messages} = Session.State.get_messages(session.id)
    {:ok, original_todos} = Session.State.get_todos(session.id)

    # Close session (triggers auto-save)
    :ok = SessionSupervisor.stop_session(session.id)

    # Wait for file to be created
    session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
    assert :ok = wait_for_file(session_file)

    # Verify file exists
    assert File.exists?(session_file)

    # Verify session is not active
    assert SessionRegistry.lookup(session.id) == {:error, :not_found}

    # Resume session
    {:ok, resumed_session} = Persistence.resume(session.id)

    # Verify session is active again
    assert {:ok, _} = SessionRegistry.lookup(resumed_session.id)

    # Verify messages restored
    {:ok, restored_messages} = Session.State.get_messages(resumed_session.id)
    assert length(restored_messages) == length(original_messages)

    # Sort both lists by content to ensure order-independent comparison
    original_sorted = Enum.sort_by(original_messages, & &1.content)
    restored_sorted = Enum.sort_by(restored_messages, & &1.content)

    Enum.zip(original_sorted, restored_sorted)
    |> Enum.each(fn {orig, restored} ->
      assert orig.role == restored.role
      assert orig.content == restored.content
    end)

    # Verify todos restored
    {:ok, restored_todos} = Session.State.get_todos(resumed_session.id)
    assert length(restored_todos) == length(original_todos)

    Enum.zip(original_todos, restored_todos)
    |> Enum.each(fn {orig, restored} ->
      assert orig.content == restored.content
      assert orig.status == restored.status
    end)

    # Verify session ID preserved
    assert resumed_session.id == session.id

    # Verify config preserved
    assert resumed_session.config.provider == session.config.provider
    assert resumed_session.config.model == session.config.model

    # Verify persisted file deleted after resume
    refute File.exists?(session_file)

    # Cleanup
    SessionSupervisor.stop_session(resumed_session.id)
  end

  test "session appears in resumable list after close", %{tmp_base: tmp_base} do
    # Initially no resumable sessions
    assert {:ok, []} = Persistence.list_resumable()

    # Create and close session
    session = create_test_session(tmp_base, "List Test")
    :ok = SessionSupervisor.stop_session(session.id)

    # Wait for file
    session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
    assert :ok = wait_for_file(session_file)

    # Verify appears in resumable list
    {:ok, resumable} = Persistence.list_resumable()
    assert length(resumable) == 1
    assert hd(resumable).id == session.id
  end

  test "session does not appear in resumable list while active", %{tmp_base: tmp_base} do
    # Create session (active)
    session = create_test_session(tmp_base, "Active Test")

    # Close it (creates file)
    :ok = SessionSupervisor.stop_session(session.id)

    # Wait for file
    session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
    assert :ok = wait_for_file(session_file)

    # Verify in resumable list
    {:ok, resumable} = Persistence.list_resumable()
    assert length(resumable) == 1

    # Resume it (becomes active)
    {:ok, resumed_session} = Persistence.resume(session.id)

    # Verify NOT in resumable list anymore
    assert {:ok, []} = Persistence.list_resumable()

    # Cleanup
    SessionSupervisor.stop_session(resumed_session.id)
  end

  test "multiple save-resume cycles preserve data", %{tmp_base: tmp_base} do
    # Create session
    session = create_test_session(tmp_base, "Multi Cycle")

    # First cycle
    add_messages_to_session(session.id, 2)
    :ok = SessionSupervisor.stop_session(session.id)

    session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
    assert :ok = wait_for_file(session_file)

    {:ok, session1} = Persistence.resume(session.id)
    {:ok, messages1} = Session.State.get_messages(session1.id)
    assert length(messages1) == 2

    # Second cycle - add more messages
    add_messages_to_session(session1.id, 3)
    :ok = SessionSupervisor.stop_session(session1.id)

    assert :ok = wait_for_file(session_file)

    {:ok, session2} = Persistence.resume(session1.id)
    {:ok, messages2} = Session.State.get_messages(session2.id)

    # Verify all messages preserved
    assert length(messages2) == 5

    # Cleanup
    SessionSupervisor.stop_session(session2.id)
  end

  test "resume fails gracefully when project path deleted", %{tmp_base: tmp_base} do
    # Create session
    session = create_test_session(tmp_base, "Deleted Path")

    # Close session
    :ok = SessionSupervisor.stop_session(session.id)

    session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
    assert :ok = wait_for_file(session_file)

    # Delete project directory
    File.rm_rf!(session.project_path)

    # Try to resume - should fail
    assert {:error, :project_path_not_found} = Persistence.resume(session.id)

    # Verify session file still exists (not deleted on error)
    assert File.exists?(session_file)
  end

  test "persisted sessions can be deleted without resuming", %{tmp_base: tmp_base} do
    # Create and close session
    session = create_test_session(tmp_base, "Delete Test")
    :ok = SessionSupervisor.stop_session(session.id)

    session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
    assert :ok = wait_for_file(session_file)

    # Verify file exists
    assert File.exists?(session_file)

    # Delete persisted session
    assert :ok = Persistence.delete_persisted(session.id)

    # Verify file deleted
    refute File.exists?(session_file)
  end

  test "cleanup removes old sessions but keeps recent ones", %{tmp_base: tmp_base} do
    # Create two sessions
    session1 = create_test_session(tmp_base, "Old Session")
    session2 = create_test_session(tmp_base, "Recent Session")

    # Close both
    :ok = SessionSupervisor.stop_session(session1.id)
    :ok = SessionSupervisor.stop_session(session2.id)

    file1 = Path.join(Persistence.sessions_dir(), "#{session1.id}.json")
    file2 = Path.join(Persistence.sessions_dir(), "#{session2.id}.json")
    assert :ok = wait_for_file(file1)
    assert :ok = wait_for_file(file2)

    # Modify first file's timestamp to be 31 days old
    old_time = DateTime.add(DateTime.utc_now(), -31 * 86400, :second)
    {:ok, data} = File.read(file1)
    {:ok, json} = Jason.decode(data)
    old_json = Map.put(json, "closed_at", DateTime.to_iso8601(old_time))
    File.write!(file1, Jason.encode!(old_json))

    # Run cleanup (default 30 days)
    {:ok, result} = Persistence.cleanup()

    # Verify old session deleted, recent kept
    assert result.deleted == 1
    assert result.skipped == 1
    refute File.exists?(file1)
    assert File.exists?(file2)
  end

  test "list_persisted includes all closed sessions", %{tmp_base: tmp_base} do
    # Create three sessions
    s1 = create_test_session(tmp_base, "Session 1")
    s2 = create_test_session(tmp_base, "Session 2")
    s3 = create_test_session(tmp_base, "Session 3")

    # Close all
    :ok = SessionSupervisor.stop_session(s1.id)
    :ok = SessionSupervisor.stop_session(s2.id)
    :ok = SessionSupervisor.stop_session(s3.id)

    # Wait for files
    Enum.each([s1, s2, s3], fn s ->
      file = Path.join(Persistence.sessions_dir(), "#{s.id}.json")
      assert :ok = wait_for_file(file)
    end)

    # Verify all in list
    {:ok, persisted} = Persistence.list_persisted()
    assert length(persisted) == 3

    ids = Enum.map(persisted, & &1.id)
    assert s1.id in ids
    assert s2.id in ids
    assert s3.id in ids
  end

  test "clear removes all persisted sessions", %{tmp_base: tmp_base} do
    # Create two sessions
    s1 = create_test_session(tmp_base, "Clear 1")
    s2 = create_test_session(tmp_base, "Clear 2")

    # Close both
    :ok = SessionSupervisor.stop_session(s1.id)
    :ok = SessionSupervisor.stop_session(s2.id)

    # Wait for files
    f1 = Path.join(Persistence.sessions_dir(), "#{s1.id}.json")
    f2 = Path.join(Persistence.sessions_dir(), "#{s2.id}.json")
    assert :ok = wait_for_file(f1)
    assert :ok = wait_for_file(f2)

    # Verify files exist
    assert File.exists?(f1)
    assert File.exists?(f2)

    # Clear all via iteration (same as /resume clear)
    {:ok, sessions} = Persistence.list_persisted()
    Enum.each(sessions, fn s -> Persistence.delete_persisted(s.id) end)

    # Verify all deleted
    refute File.exists?(f1)
    refute File.exists?(f2)
    assert {:ok, []} = Persistence.list_persisted()
  end

  # ============================================================================
  # Auto-Save on Close Integration Tests (Task 6.7.2)
  # ============================================================================

  describe "auto-save on close integration" do
    test "stop_session triggers auto-save before termination", %{tmp_base: tmp_base} do
      # Create session with messages
      session = create_test_session(tmp_base, "Auto-Save Test")
      add_messages_to_session(session.id, 2)

      # Verify session is active
      assert {:ok, _} = SessionRegistry.lookup(session.id)

      # Stop session (triggers auto-save)
      :ok = SessionSupervisor.stop_session(session.id)

      # Wait for file creation
      session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
      assert :ok = wait_for_file(session_file)

      # Verify file exists
      assert File.exists?(session_file)

      # Verify session no longer active
      assert {:error, :not_found} = SessionRegistry.lookup(session.id)

      # Verify file contains messages
      {:ok, json} = File.read(session_file)
      {:ok, data} = Jason.decode(json)
      assert length(data["conversation"]) == 2
      assert data["name"] == "Auto-Save Test"
    end

    test "saves conversation state at exact time of close", %{tmp_base: tmp_base} do
      # Create session
      session = create_test_session(tmp_base, "State Preservation")

      # Add initial messages
      add_messages_to_session(session.id, 2)

      # Add one more message immediately before close
      final_message = %{
        id: "final-msg-#{System.unique_integer([:positive])}",
        role: :user,
        content: "Final message before close",
        timestamp: DateTime.utc_now()
      }

      Session.State.append_message(session.id, final_message)

      # Close immediately
      :ok = SessionSupervisor.stop_session(session.id)

      # Wait for file
      session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
      assert :ok = wait_for_file(session_file)

      # Verify file contains all 3 messages including the final one
      {:ok, json} = File.read(session_file)
      {:ok, data} = Jason.decode(json)
      assert length(data["conversation"]) == 3

      # Verify final message is in the saved conversation
      contents = Enum.map(data["conversation"], & &1["content"])
      assert "Final message before close" in contents
    end

    test "save failure logs warning but allows close to continue", %{tmp_base: tmp_base} do
      # Create session
      session = create_test_session(tmp_base, "Failure Test")
      add_messages_to_session(session.id, 1)

      # Make sessions directory read-only (simulates permission error)
      sessions_dir = Persistence.sessions_dir()
      original_mode = File.stat!(sessions_dir).mode
      File.chmod!(sessions_dir, 0o555)

      # Ensure cleanup restores permissions
      on_exit(fn -> File.chmod!(sessions_dir, original_mode) end)

      # Capture log output
      log =
        capture_log(fn ->
          # Stop session (save will fail due to permissions)
          result = SessionSupervisor.stop_session(session.id)

          # Verify stop_session still returns :ok
          assert :ok == result
        end)

      # Verify warning was logged (match partial string)
      assert log =~ "Failed to save session"
      assert log =~ ":eacces"

      # Verify session was still terminated (not in registry)
      assert {:error, :not_found} = SessionRegistry.lookup(session.id)

      # Verify no session file created (save failed)
      session_file = Path.join(sessions_dir, "#{session.id}.json")
      refute File.exists?(session_file)
    end

    test "saves todos state during auto-save", %{tmp_base: tmp_base} do
      # Create session
      session = create_test_session(tmp_base, "Todos Test")

      # Add messages and todos
      add_messages_to_session(session.id, 1)
      add_todos_to_session(session.id, 3)

      # Close session
      :ok = SessionSupervisor.stop_session(session.id)

      # Wait for file
      session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
      assert :ok = wait_for_file(session_file)

      # Verify file contains todos
      {:ok, json} = File.read(session_file)
      {:ok, data} = Jason.decode(json)
      assert length(data["todos"]) == 3
      assert length(data["conversation"]) == 1

      # Verify todo structure
      first_todo = hd(data["todos"])
      assert Map.has_key?(first_todo, "content")
      assert Map.has_key?(first_todo, "status")
      assert Map.has_key?(first_todo, "active_form")
    end

    test "multiple session closes create separate session files", %{tmp_base: tmp_base} do
      # Create 3 sessions
      session1 = create_test_session(tmp_base, "Session 1")
      session2 = create_test_session(tmp_base, "Session 2")
      session3 = create_test_session(tmp_base, "Session 3")

      # Add different messages to each
      add_messages_to_session(session1.id, 1)
      add_messages_to_session(session2.id, 2)
      add_messages_to_session(session3.id, 3)

      # Close all three
      :ok = SessionSupervisor.stop_session(session1.id)
      :ok = SessionSupervisor.stop_session(session2.id)
      :ok = SessionSupervisor.stop_session(session3.id)

      # Wait for all files
      sessions_dir = Persistence.sessions_dir()
      file1 = Path.join(sessions_dir, "#{session1.id}.json")
      file2 = Path.join(sessions_dir, "#{session2.id}.json")
      file3 = Path.join(sessions_dir, "#{session3.id}.json")

      assert :ok = wait_for_file(file1)
      assert :ok = wait_for_file(file2)
      assert :ok = wait_for_file(file3)

      # Verify all three files exist
      assert File.exists?(file1)
      assert File.exists?(file2)
      assert File.exists?(file3)

      # Verify each file has correct message count
      assert_message_count(file1, 1)
      assert_message_count(file2, 2)
      assert_message_count(file3, 3)
    end

    test "auto-saved sessions removed from active registry", %{tmp_base: tmp_base} do
      # Create two sessions
      session1 = create_test_session(tmp_base, "Active")
      session2 = create_test_session(tmp_base, "Closed")

      # Verify both active
      assert {:ok, _} = SessionRegistry.lookup(session1.id)
      assert {:ok, _} = SessionRegistry.lookup(session2.id)

      # Close only session2
      :ok = SessionSupervisor.stop_session(session2.id)

      # Wait for file
      session_file = Path.join(Persistence.sessions_dir(), "#{session2.id}.json")
      assert :ok = wait_for_file(session_file)

      # Verify session1 still active
      assert {:ok, _} = SessionRegistry.lookup(session1.id)

      # Verify session2 NOT in active registry
      assert {:error, :not_found} = SessionRegistry.lookup(session2.id)

      # Verify session2 file exists
      assert File.exists?(session_file)

      # Cleanup active session
      SessionSupervisor.stop_session(session1.id)
    end

    # Helper function for verifying message counts in JSON files
    defp assert_message_count(file_path, expected_count) do
      {:ok, json} = File.read(file_path)
      {:ok, data} = Jason.decode(json)
      assert length(data["conversation"]) == expected_count
    end
  end

  # ============================================================================
  # Persistence File Format Integration Tests (Task 6.7.4)
  # ============================================================================

  describe "persistence file format integration" do
    test "saved JSON includes all required fields", %{tmp_base: tmp_base} do
      # Create session with full data
      session = create_test_session(tmp_base, "Format Test")

      # Add a message
      message = %{
        id: "test-msg-#{System.unique_integer([:positive])}",
        role: :user,
        content: "Test message",
        timestamp: DateTime.utc_now()
      }

      Session.State.append_message(session.id, message)

      # Add a todo
      Session.State.update_todos(session.id, [
        %{content: "Test task", status: :in_progress, active_form: "Testing"}
      ])

      # Close and wait for file
      :ok = SessionSupervisor.stop_session(session.id)
      session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
      wait_for_file(session_file)

      # Read and parse JSON
      json_content = File.read!(session_file)
      data = Jason.decode!(json_content)

      # Verify required fields present
      assert data["version"] == 1
      assert data["id"] == session.id
      assert data["name"] == "Format Test"
      assert data["project_path"] == session.project_path
      assert is_map(data["config"])
      assert is_binary(data["closed_at"])
      assert is_list(data["conversation"])
      assert is_list(data["todos"])
    end

    test "conversation messages serialized correctly", %{tmp_base: tmp_base} do
      session = create_test_session(tmp_base, "Messages Test")

      # Add messages with different roles
      timestamp = DateTime.utc_now()

      messages = [
        %{
          id: "test-msg-1-#{System.unique_integer([:positive])}",
          role: :user,
          content: "User message",
          timestamp: timestamp
        },
        %{
          id: "test-msg-2-#{System.unique_integer([:positive])}",
          role: :assistant,
          content: "Assistant reply",
          timestamp: timestamp
        },
        %{
          id: "test-msg-3-#{System.unique_integer([:positive])}",
          role: :system,
          content: "System message",
          timestamp: timestamp
        }
      ]

      Enum.each(messages, fn msg -> Session.State.append_message(session.id, msg) end)

      # Close and read JSON
      :ok = SessionSupervisor.stop_session(session.id)
      session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
      wait_for_file(session_file)

      data = File.read!(session_file) |> Jason.decode!()
      messages = data["conversation"]

      # Verify message structure
      assert length(messages) == 3

      # Find messages by role (order may vary)
      user_msg = Enum.find(messages, fn m -> m["role"] == "user" end)
      assistant_msg = Enum.find(messages, fn m -> m["role"] == "assistant" end)
      system_msg = Enum.find(messages, fn m -> m["role"] == "system" end)

      # Verify user message exists and has correct structure
      assert user_msg != nil
      assert user_msg["content"] == "User message"
      assert is_binary(user_msg["id"])
      assert is_binary(user_msg["timestamp"])

      # Verify assistant message
      assert assistant_msg != nil
      assert assistant_msg["content"] == "Assistant reply"

      # Verify system message
      assert system_msg != nil
      assert system_msg["content"] == "System message"
    end

    test "todos serialized correctly", %{tmp_base: tmp_base} do
      session = create_test_session(tmp_base, "Todos Test")

      # Add todos with different statuses
      todos = [
        %{content: "Task 1", status: :pending, active_form: "Waiting for task 1"},
        %{content: "Task 2", status: :in_progress, active_form: "Working on task 2"},
        %{content: "Task 3", status: :completed, active_form: "Task 3 done"}
      ]

      Session.State.update_todos(session.id, todos)

      # Close and read JSON
      :ok = SessionSupervisor.stop_session(session.id)
      session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
      wait_for_file(session_file)

      data = File.read!(session_file) |> Jason.decode!()
      todos = data["todos"]

      # Verify todo structure
      assert length(todos) == 3

      [todo1, todo2, todo3] = todos

      # Verify pending todo
      assert todo1["content"] == "Task 1"
      assert todo1["status"] == "pending"
      assert todo1["active_form"] == "Waiting for task 1"

      # Verify in_progress todo
      assert todo2["content"] == "Task 2"
      assert todo2["status"] == "in_progress"
      assert todo2["active_form"] == "Working on task 2"

      # Verify completed todo
      assert todo3["content"] == "Task 3"
      assert todo3["status"] == "completed"
      assert todo3["active_form"] == "Task 3 done"
    end

    test "timestamps in ISO 8601 format", %{tmp_base: tmp_base} do
      session = create_test_session(tmp_base, "Timestamps Test")

      # Add message with known timestamp
      now = DateTime.utc_now()

      message = %{
        id: "test-msg-#{System.unique_integer([:positive])}",
        role: :user,
        content: "Time test",
        timestamp: now
      }

      Session.State.append_message(session.id, message)

      # Close and read JSON
      :ok = SessionSupervisor.stop_session(session.id)
      session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
      wait_for_file(session_file)

      data = File.read!(session_file) |> Jason.decode!()

      # Verify closed_at is ISO 8601
      closed_at = data["closed_at"]
      assert {:ok, _datetime, _offset} = DateTime.from_iso8601(closed_at)

      # Verify message timestamp is ISO 8601
      message_timestamp = hd(data["conversation"])["timestamp"]
      assert {:ok, parsed_time, _offset} = DateTime.from_iso8601(message_timestamp)

      # Should be close to original timestamp (within 1 second)
      diff = DateTime.diff(parsed_time, now, :second)
      assert abs(diff) <= 1
    end

    test "round-trip preserves all data", %{tmp_base: tmp_base} do
      session = create_test_session(tmp_base, "Round-Trip Test")

      # Add complex data
      timestamp = DateTime.utc_now()

      messages = [
        %{
          id: "test-msg-1-#{System.unique_integer([:positive])}",
          role: :user,
          content: "Message 1",
          timestamp: timestamp
        },
        %{
          id: "test-msg-2-#{System.unique_integer([:positive])}",
          role: :assistant,
          content: "Reply 1",
          timestamp: timestamp
        }
      ]

      Enum.each(messages, fn msg -> Session.State.append_message(session.id, msg) end)

      todos = [
        %{content: "Task 1", status: :pending, active_form: "Pending task"},
        %{content: "Task 2", status: :completed, active_form: "Done task"}
      ]

      Session.State.update_todos(session.id, todos)

      # Close (save)
      :ok = SessionSupervisor.stop_session(session.id)
      session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
      wait_for_file(session_file)

      # Resume (load)
      {:ok, resumed_session} = Persistence.resume(session.id)

      # Verify session metadata
      assert resumed_session.id == session.id
      assert resumed_session.name == "Round-Trip Test"
      assert resumed_session.project_path == session.project_path

      # Get state from resumed session
      {:ok, messages} = Session.State.get_messages(resumed_session.id)
      {:ok, todos} = Session.State.get_todos(resumed_session.id)

      # Verify messages preserved
      assert length(messages) == 2

      # Find messages by role (order may vary)
      user_msg = Enum.find(messages, fn m -> m.role == :user end)
      assert user_msg != nil
      assert user_msg.content == "Message 1"

      # Verify todos preserved
      assert length(todos) == 2

      # Find todos by status (order may vary)
      pending_todo = Enum.find(todos, fn t -> t.status == :pending end)
      assert pending_todo != nil
      assert pending_todo.content == "Task 1"
      assert pending_todo.active_form == "Pending task"
    end

    test "handles corrupted JSON files gracefully", %{tmp_base: tmp_base} do
      import ExUnit.CaptureLog

      # Create sessions directory
      sessions_dir = Persistence.sessions_dir()
      File.mkdir_p!(sessions_dir)

      # Create a good session file
      good_id = Uniq.UUID.uuid4()

      good_session = %{
        version: 1,
        id: good_id,
        name: "Good Session",
        project_path: Path.join(tmp_base, "good"),
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"},
        closed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        conversation: [],
        todos: []
      }

      good_path = Path.join(sessions_dir, "#{good_id}.json")
      File.write!(good_path, Jason.encode!(good_session))

      # Create a corrupted JSON file
      corrupted_id = Uniq.UUID.uuid4()
      corrupted_path = Path.join(sessions_dir, "#{corrupted_id}.json")
      File.write!(corrupted_path, "{invalid json content")

      # List persisted should skip corrupted file and include good one
      log =
        capture_log(fn ->
          {:ok, sessions} = Persistence.list_persisted()

          # Should have only the good session
          assert length(sessions) == 1
          assert hd(sessions).id == good_id
          assert hd(sessions).name == "Good Session"
        end)

      # Should log warning about corrupted file
      assert log =~ "corrupted" or log =~ "invalid" or log =~ "failed"
    end
  end
end

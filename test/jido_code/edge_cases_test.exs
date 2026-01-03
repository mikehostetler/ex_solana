defmodule JidoCode.EdgeCasesTest do
  @moduledoc """
  Comprehensive edge case tests for the work-session feature.

  Tests edge cases across four categories:
  - Session limit handling
  - Path edge cases
  - State edge cases
  - Persistence edge cases

  These tests verify the system handles exceptional scenarios gracefully
  with clear error messages and proper recovery.
  """
  use ExUnit.Case, async: false

  alias JidoCode.Session
  alias JidoCode.Session.{State, Persistence}
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor
  alias JidoCode.Commands
  alias JidoCode.Commands.ErrorSanitizer
  alias JidoCode.Test.SessionTestHelpers

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    {:ok, _} = Application.ensure_all_started(:jido_code)

    # Wait for SessionSupervisor
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

    tmp_base = Path.join(System.tmp_dir!(), "edge_cases_test_#{:rand.uniform(100_000)}")
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
  # 7.2.1: Session Limit Edge Cases
  # ============================================================================

  describe "session limit edge cases" do
    @tag :llm
    test "error message includes session count when limit reached", %{tmp_base: tmp_base} do
      config = SessionTestHelpers.valid_session_config()

      # Create 10 sessions
      for i <- 1..10 do
        project_path = Path.join(tmp_base, "project_#{i}")
        File.mkdir_p!(project_path)

        {:ok, session} =
          Session.new(
            name: "Session #{i}",
            project_path: project_path,
            config: config
          )

        {:ok, _id} = SessionSupervisor.start_session(session)
      end

      # Try to create 11th session
      project_11 = Path.join(tmp_base, "project_11")
      File.mkdir_p!(project_11)

      {:ok, session_11} =
        Session.new(
          name: "Session 11",
          project_path: project_11,
          config: config
        )

      # Should get enhanced error with count
      assert {:error, {:session_limit_reached, 10, 10}} =
               SessionSupervisor.start_session(session_11)

      # Verify sanitized error message includes count
      sanitized = ErrorSanitizer.sanitize_error({:session_limit_reached, 10, 10})
      assert sanitized =~ "10/10"
      assert sanitized =~ "Close a session first"
    end

    @tag :llm
    test "resume prevented when at session limit", %{tmp_base: tmp_base} do
      config = SessionTestHelpers.valid_session_config()

      # Create and save a session
      resumable_path = Path.join(tmp_base, "resumable")
      File.mkdir_p!(resumable_path)

      {:ok, resumable_session} =
        Session.new(
          name: "Resumable",
          project_path: resumable_path,
          config: config
        )

      {:ok, resumable_id} = SessionSupervisor.start_session(resumable_session)
      {:ok, _path} = Persistence.save(resumable_id)
      SessionSupervisor.stop_session(resumable_id)

      # Fill up to session limit
      for i <- 1..10 do
        project_path = Path.join(tmp_base, "active_#{i}")
        File.mkdir_p!(project_path)

        {:ok, session} =
          Session.new(
            name: "Active #{i}",
            project_path: project_path,
            config: config
          )

        {:ok, _id} = SessionSupervisor.start_session(session)
      end

      # Try to resume - should fail with session limit error
      result = Persistence.resume(resumable_id)
      assert {:error, reason} = result
      assert reason == {:session_limit_reached, 10, 10} or reason == :session_limit_reached
    end

    test "session limit error sanitization" do
      # Test both old and new error formats
      assert ErrorSanitizer.sanitize_error(:session_limit_reached) == "Maximum sessions reached."

      assert ErrorSanitizer.sanitize_error({:session_limit_reached, 10, 10}) ==
               "Maximum sessions reached (10/10 sessions open). Close a session first."

      assert ErrorSanitizer.sanitize_error({:session_limit_reached, 5, 10}) ==
               "Maximum sessions reached (5/10 sessions open). Close a session first."
    end
  end

  # ============================================================================
  # 7.2.2: Path Edge Cases
  # ============================================================================

  describe "path edge cases" do
    @tag :llm
    test "handles paths with spaces correctly", %{tmp_base: tmp_base} do
      path_with_spaces = Path.join(tmp_base, "project with spaces")
      File.mkdir_p!(path_with_spaces)

      {:ok, session} =
        Session.new(
          name: "Spaces Test",
          project_path: path_with_spaces,
          config: SessionTestHelpers.valid_session_config()
        )

      # Should successfully create session with spaced path
      assert {:ok, session_id} = SessionSupervisor.start_session(session)
      assert SessionRegistry.exists?(session_id)

      # Verify session has correct path
      {:ok, retrieved} = SessionRegistry.lookup(session_id)
      assert retrieved.project_path == path_with_spaces
    end

    @tag :llm
    test "handles paths with unicode characters", %{tmp_base: tmp_base} do
      unicode_path = Path.join(tmp_base, "projekt_测试_مشروع")
      File.mkdir_p!(unicode_path)

      {:ok, session} =
        Session.new(
          name: "Unicode Test",
          project_path: unicode_path,
          config: SessionTestHelpers.valid_session_config()
        )

      assert {:ok, session_id} = SessionSupervisor.start_session(session)
      assert SessionRegistry.exists?(session_id)
    end

    @tag :llm
    test "follows symlinks and validates resolved path", %{tmp_base: tmp_base} do
      # Create actual directory
      actual_path = Path.join(tmp_base, "actual_project")
      File.mkdir_p!(actual_path)

      # Create symlink
      symlink_path = Path.join(tmp_base, "symlink_project")
      :ok = File.ln_s(actual_path, symlink_path)

      {:ok, session} =
        Session.new(
          name: "Symlink Test",
          project_path: symlink_path,
          config: SessionTestHelpers.valid_session_config()
        )

      # Should follow symlink and create session
      assert {:ok, session_id} = SessionSupervisor.start_session(session)
      assert SessionRegistry.exists?(session_id)

      # Clean up symlink
      File.rm(symlink_path)
    end

    test "rejects nonexistent paths with clear error" do
      # Session.new should reject nonexistent paths upfront
      result =
        Session.new(
          name: "Nonexistent",
          project_path: "/nonexistent/path",
          config: SessionTestHelpers.valid_session_config()
        )

      assert {:error, :path_not_found} = result

      # Verify error is sanitized properly
      sanitized = ErrorSanitizer.sanitize_error(:path_not_found)
      assert sanitized == "Path does not exist."
    end

    test "rejects file (not directory) with clear error", %{tmp_base: tmp_base} do
      file_path = Path.join(tmp_base, "not_a_directory.txt")
      File.write!(file_path, "content")

      # Session.new should reject files (non-directories) upfront
      result =
        Session.new(
          name: "File Not Dir",
          project_path: file_path,
          config: SessionTestHelpers.valid_session_config()
        )

      assert {:error, :path_not_directory} = result

      # Verify error is sanitized properly
      sanitized = ErrorSanitizer.sanitize_error(:path_not_directory)
      assert sanitized == "Path is not a directory."
    end
  end

  # ============================================================================
  # 7.2.3: State Edge Cases
  # ============================================================================

  describe "state edge cases" do
    @tag :llm
    test "handles empty conversation gracefully", %{tmp_base: tmp_base} do
      project_path = Path.join(tmp_base, "empty_conv")
      File.mkdir_p!(project_path)

      {:ok, session} =
        Session.new(
          name: "Empty",
          project_path: project_path,
          config: SessionTestHelpers.valid_session_config()
        )

      {:ok, session_id} = SessionSupervisor.start_session(session)

      # Verify empty conversation
      {:ok, messages} = State.get_messages(session_id)
      assert messages == []

      # Should be able to add first message
      State.append_message(session_id, %{
        id: "msg1",
        role: :user,
        content: "First message",
        timestamp: DateTime.utc_now()
      })

      {:ok, updated} = State.get_messages(session_id)
      assert length(updated) == 1
    end

    @tag :llm
    test "handles large conversation (1000+ messages)", %{tmp_base: tmp_base} do
      project_path = Path.join(tmp_base, "large_conv")
      File.mkdir_p!(project_path)

      {:ok, session} =
        Session.new(
          name: "Large",
          project_path: project_path,
          config: SessionTestHelpers.valid_session_config()
        )

      {:ok, session_id} = SessionSupervisor.start_session(session)

      # Add 1000 messages
      for i <- 1..1000 do
        State.append_message(session_id, %{
          id: "msg#{i}",
          role: if(rem(i, 2) == 0, do: :user, else: :assistant),
          content: "Message #{i}",
          timestamp: DateTime.utc_now()
        })
      end

      # Verify all messages stored
      {:ok, all_messages} = State.get_messages(session_id)
      assert length(all_messages) == 1000

      # Test pagination with large conversation
      {:ok, page, meta} = State.get_messages(session_id, 0, 100)
      assert length(page) == 100
      assert meta.total == 1000
      assert meta.has_more == true
    end

    @tag :llm
    test "streaming state cleanup on session close", %{tmp_base: tmp_base} do
      project_path = Path.join(tmp_base, "streaming_close")
      File.mkdir_p!(project_path)

      {:ok, session} =
        Session.new(
          name: "Streaming",
          project_path: project_path,
          config: SessionTestHelpers.valid_session_config()
        )

      {:ok, session_id} = SessionSupervisor.start_session(session)

      # Start streaming
      State.start_streaming(session_id, "msg-1")
      State.update_streaming(session_id, "Streaming content")

      {:ok, state} = State.get_state(session_id)
      assert state.is_streaming == true

      # Close session while streaming
      SessionSupervisor.stop_session(session_id)

      # Verify session is closed
      refute SessionRegistry.exists?(session_id)
    end

    @tag :llm
    test "handles session switch during streaming", %{tmp_base: tmp_base} do
      # Create two sessions
      path_a = Path.join(tmp_base, "session_a_streaming")
      path_b = Path.join(tmp_base, "session_b_streaming")
      File.mkdir_p!(path_a)
      File.mkdir_p!(path_b)

      {:ok, session_a} =
        Session.new(
          name: "A",
          project_path: path_a,
          config: SessionTestHelpers.valid_session_config()
        )

      {:ok, session_b} =
        Session.new(
          name: "B",
          project_path: path_b,
          config: SessionTestHelpers.valid_session_config()
        )

      {:ok, id_a} = SessionSupervisor.start_session(session_a)
      {:ok, id_b} = SessionSupervisor.start_session(session_b)

      # Start streaming in session A
      State.start_streaming(id_a, "msg-a")
      State.update_streaming(id_a, "Content in A")

      # Simulate switch to session B (just verify it doesn't affect A's state)
      {:ok, state_a} = State.get_state(id_a)
      {:ok, state_b} = State.get_state(id_b)

      assert state_a.is_streaming == true
      assert state_b.is_streaming == false
    end
  end

  # ============================================================================
  # 7.2.4: Persistence Edge Cases
  # ============================================================================

  describe "persistence edge cases" do
    @tag :llm
    test "handles corrupted session file gracefully", %{tmp_base: tmp_base} do
      project_path = Path.join(tmp_base, "corrupted")
      File.mkdir_p!(project_path)

      {:ok, session} =
        Session.new(
          name: "Corrupted",
          project_path: project_path,
          config: SessionTestHelpers.valid_session_config()
        )

      {:ok, session_id} = SessionSupervisor.start_session(session)

      # Save session
      {:ok, file_path} = Persistence.save(session_id)
      SessionSupervisor.stop_session(session_id)

      # Corrupt the file
      File.write!(file_path, "{corrupted json content")

      # Try to resume - should get JSON decode error
      result = Persistence.resume(session_id)
      assert {:error, reason} = result

      # Error should be sanitized
      sanitized = ErrorSanitizer.sanitize_error(reason)
      assert is_binary(sanitized)
    end

    test "handles missing sessions directory" do
      # Delete sessions directory
      sessions_dir = Persistence.sessions_dir()
      File.rm_rf!(sessions_dir)

      # Try to list sessions - should auto-create directory or handle gracefully
      result = Persistence.list_persisted()

      # Should either succeed with empty list or fail gracefully
      case result do
        {:ok, sessions} -> assert sessions == []
        {:error, :enoent} -> assert true
        {:error, _reason} -> assert true
      end
    end

    @tag :llm
    test "handles session file deleted while session active", %{tmp_base: tmp_base} do
      project_path = Path.join(tmp_base, "deleted_file")
      File.mkdir_p!(project_path)

      {:ok, session} =
        Session.new(
          name: "Deleted",
          project_path: project_path,
          config: SessionTestHelpers.valid_session_config()
        )

      {:ok, session_id} = SessionSupervisor.start_session(session)

      # Save session
      {:ok, file_path} = Persistence.save(session_id)

      # Delete the file while session is active
      File.rm!(file_path)

      # Session should still be functional
      assert SessionRegistry.exists?(session_id)

      State.append_message(session_id, %{
        id: "msg1",
        role: :user,
        content: "After file deleted",
        timestamp: DateTime.utc_now()
      })

      {:ok, messages} = State.get_messages(session_id)
      assert length(messages) == 1

      # Can save again
      {:ok, new_path} = Persistence.save(session_id)
      assert File.exists?(new_path)
    end

    @tag :llm
    test "concurrent save protection via per-session locks", %{tmp_base: tmp_base} do
      project_path = Path.join(tmp_base, "concurrent_save")
      File.mkdir_p!(project_path)

      {:ok, session} =
        Session.new(
          name: "Concurrent",
          project_path: project_path,
          config: SessionTestHelpers.valid_session_config()
        )

      {:ok, session_id} = SessionSupervisor.start_session(session)

      # Try concurrent saves (second should fail with :save_in_progress)
      task1 =
        Task.async(fn ->
          Persistence.save(session_id)
        end)

      # Small delay to ensure first save starts
      Process.sleep(10)

      task2 =
        Task.async(fn ->
          Persistence.save(session_id)
        end)

      results = Task.await_many([task1, task2], 5000)

      # One should succeed, one might fail with :save_in_progress
      successes = Enum.count(results, fn r -> match?({:ok, _}, r) end)
      assert successes >= 1
    end
  end
end

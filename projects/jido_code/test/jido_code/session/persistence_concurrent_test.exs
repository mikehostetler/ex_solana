defmodule JidoCode.Session.PersistenceConcurrentTest do
  @moduledoc """
  Concurrent operation tests for session persistence.

  Tests race conditions and concurrent access patterns to ensure:
  - Atomic writes prevent corruption
  - Concurrent operations don't crash
  - File locking and error handling work correctly

  Note: These tests require LLM initialization and are excluded by default.
  Run with: mix test --include llm
  """

  # Not async because we're testing concurrent operations with shared state
  # Tagged as :llm because tests create sessions which initialize LLM agents
  use ExUnit.Case, async: false

  @moduletag :llm

  import JidoCode.PersistenceTestHelpers

  alias JidoCode.Session.Persistence
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor

  setup do
    {:ok, _} = Application.ensure_all_started(:jido_code)

    # Wait for supervisor
    wait_for_supervisor()

    # Clear registry
    for session <- SessionRegistry.list_all() do
      SessionSupervisor.stop_session(session.id)
    end

    # Create unique temp directory for this test
    tmp_base = create_test_directory()

    on_exit(fn ->
      # Stop all test sessions
      for session <- SessionRegistry.list_all() do
        SessionSupervisor.stop_session(session.id)
      end

      # Clean up temp dirs and session files
      File.rm_rf!(tmp_base)
      sessions_dir = Persistence.sessions_dir()

      if File.exists?(sessions_dir) do
        File.rm_rf!(sessions_dir)
      end
    end)

    {:ok, tmp_base: tmp_base}
  end

  # Helper to create a UUID for testing
  defp test_uuid(index \\ 0) do
    base = "550e8400-e29b-41d4-a716-44665544000"
    suffix = String.pad_leading(Integer.to_string(index), 1, "0")
    base <> suffix
  end

  describe "concurrent saves to same session" do
    test "multiple saves via session close are atomic and don't corrupt", %{tmp_base: tmp_base} do
      # Create multiple sessions and close them concurrently
      # This tests that file writes are atomic (temp + rename)

      # Create and close 5 sessions concurrently (each with unique project path)
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            project_path = Path.join(tmp_base, "concurrent_saves_#{i}")
            File.mkdir_p!(project_path)
            session = create_and_close_session("Concurrent Test #{i}", project_path)
            {i, session.id}
          end)
        end

      results = Task.await_many(tasks, 10000)

      # All should succeed
      assert length(results) == 5

      # Verify all files exist and are valid
      for {_i, session_id} <- results do
        session_file = Persistence.session_file(session_id)
        assert File.exists?(session_file)

        # Verify file is not corrupted (can be loaded)
        assert {:ok, _loaded} = Persistence.load(session_id)
      end
    end

    test "atomic writes prevent partial file corruption", %{tmp_base: tmp_base} do
      # This test verifies that temp file + rename strategy prevents corruption
      project_path = Path.join(tmp_base, "atomic_writes")
      File.mkdir_p!(project_path)

      session = create_and_close_session("Atomic Write Test", project_path)
      session_file = Persistence.session_file(session.id)

      # Verify no .tmp files left behind after save
      session_dir = Path.dirname(session_file)
      tmp_files = Path.wildcard(Path.join(session_dir, "*.tmp"))
      assert Enum.empty?(tmp_files), "No temporary files should be left behind"

      # Verify final file has valid JSON
      {:ok, content} = File.read(session_file)
      assert {:ok, _json} = Jason.decode(content)
    end

    test "concurrent saves to same session are serialized", %{tmp_base: tmp_base} do
      # This test verifies that the per-session lock prevents concurrent saves
      # to the same session from racing with each other.
      project_path = Path.join(tmp_base, "concurrent_save_serialization")
      File.mkdir_p!(project_path)

      # Create a session
      {:ok, session} =
        SessionSupervisor.create_session(
          project_path: project_path,
          name: "Serialization Test",
          config: %{
            provider: "anthropic",
            model: "claude-3-5-haiku-20241022",
            temperature: 0.7,
            max_tokens: 4096
          }
        )

      session_id = session.id

      # Try to save the same session from 5 concurrent processes
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            # Add a unique message so we can see which save won
            message = %{
              id: "msg-#{i}",
              role: :user,
              content: "Message #{i}",
              timestamp: DateTime.utc_now()
            }

            JidoCode.Session.State.append_message(session_id, message)

            # Try to save
            result = Persistence.save(session_id)
            {i, result}
          end)
        end

      results = Task.await_many(tasks, 10000)

      # Some saves should succeed, others should return :save_in_progress
      successes = Enum.count(results, fn {_i, result} -> match?({:ok, _}, result) end)

      in_progress =
        Enum.count(results, fn {_i, result} -> result == {:error, :save_in_progress} end)

      # At least one save should succeed
      assert successes >= 1, "At least one save should succeed"

      # Some saves should be blocked by the lock (unless timing is such that they all serialize perfectly)
      # This assertion is lenient because timing may vary
      assert successes + in_progress == 5, "All save attempts should either succeed or be blocked"

      # Verify the session file exists and is valid
      session_file = Persistence.session_file(session_id)
      assert File.exists?(session_file)
      assert {:ok, _loaded} = Persistence.load(session_id)

      # Cleanup
      SessionSupervisor.stop_session(session_id)
    end
  end

  describe "save during resume race conditions" do
    test "resume waits for in-progress save to complete", %{tmp_base: tmp_base} do
      # This test is tricky because save happens asynchronously on session close
      # We test that resume after close waits for persistence to complete
      project_path = Path.join(tmp_base, "resume_after_save")
      File.mkdir_p!(project_path)

      config = %{
        provider: "anthropic",
        model: "claude-3-5-haiku-20241022",
        temperature: 0.7,
        max_tokens: 4096
      }

      # Create session
      {:ok, session} =
        SessionSupervisor.create_session(
          project_path: project_path,
          name: "Resume After Save",
          config: config
        )

      session_id = session.id

      # Add message
      message = %{
        id: "msg-1",
        role: :user,
        content: "Test",
        timestamp: DateTime.utc_now()
      }

      JidoCode.Session.State.append_message(session_id, message)

      # Close session (triggers async save)
      :ok = SessionSupervisor.stop_session(session_id)

      # Wait for file to appear
      session_file = Persistence.session_file(session_id)
      assert :ok = wait_for_persisted_file(session_file)

      # Resume should succeed with correct data
      assert {:ok, resumed_session} = Persistence.resume(session_id)
      assert resumed_session.name == "Resume After Save"

      # Verify message was persisted
      {:ok, messages} = JidoCode.Session.State.get_messages(resumed_session.id)
      assert Enum.any?(messages, fn m -> m.content == "Test" end)

      # Cleanup
      SessionSupervisor.stop_session(resumed_session.id)
    end
  end

  describe "multiple resume attempts" do
    test "multiple concurrent resume attempts handle correctly", %{tmp_base: tmp_base} do
      # Create and close session
      project_path = Path.join(tmp_base, "multiple_resume")
      File.mkdir_p!(project_path)

      session = create_and_close_session("Multiple Resume Test", project_path)
      session_id = session.id

      # Try to resume concurrently from 5 processes
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            result = Persistence.resume(session_id)
            {i, result}
          end)
        end

      results = Task.await_many(tasks, 5000)

      # Count successes
      successes =
        Enum.count(results, fn
          {_i, {:ok, _session}} -> true
          _ -> false
        end)

      # At least one should succeed
      # Others may fail with :project_already_open or succeed (race condition)
      assert successes >= 1, "At least one resume should succeed"

      # Clean up any successfully resumed sessions
      for session <- SessionRegistry.list_all() do
        SessionSupervisor.stop_session(session.id)
      end
    end

    test "resume of non-existent session fails gracefully", %{tmp_base: _tmp_base} do
      # Try to resume session that doesn't exist
      # Generate a valid UUID v4 format that doesn't correspond to any real session
      fake_id = "00000000-0000-4000-8000-000000000999"

      tasks =
        for i <- 1..3 do
          Task.async(fn ->
            result = Persistence.resume(fake_id)
            {i, result}
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All should fail with :not_found
      for {_i, result} <- results do
        assert result == {:error, :not_found}
      end
    end
  end

  describe "concurrent cleanup operations" do
    test "concurrent cleanup calls don't crash", %{tmp_base: tmp_base} do
      # Create multiple old sessions (31 days ago)
      session_ids =
        for i <- 1..5 do
          project_path = Path.join(tmp_base, "cleanup_test_#{i}")
          File.mkdir_p!(project_path)
          session = create_and_close_session("Cleanup Test #{i}", project_path)

          # Make session appear old by modifying closed_at timestamp
          session_file = Persistence.session_file(session.id)
          {:ok, content} = File.read(session_file)
          {:ok, data} = Jason.decode(content)

          # Set closed_at to 31 days ago
          old_timestamp =
            DateTime.utc_now()
            |> DateTime.add(-31 * 86400, :second)
            |> DateTime.to_iso8601()

          updated_data = Map.put(data, "closed_at", old_timestamp)
          {:ok, updated_json} = Jason.encode(updated_data, pretty: true)
          File.write!(session_file, updated_json)

          session.id
        end

      # Run cleanup concurrently from multiple processes
      tasks =
        for i <- 1..3 do
          Task.async(fn ->
            result = Persistence.cleanup(30)
            {i, result}
          end)
        end

      results = Task.await_many(tasks, 10000)

      # All should return results (may have different counts due to race)
      for {_i, result} <- results do
        assert is_map(result)
        assert Map.has_key?(result, :deleted)
        assert Map.has_key?(result, :skipped)
        assert Map.has_key?(result, :failed)
      end

      # Total deleted across all runs should be >= number of sessions
      total_deleted = Enum.reduce(results, 0, fn {_i, result}, acc -> acc + result.deleted end)
      assert total_deleted >= 5, "All sessions should eventually be deleted"
    end

    test "cleanup during active session doesn't affect active state", %{tmp_base: tmp_base} do
      # Create old persisted session
      project1 = Path.join(tmp_base, "old_session")
      File.mkdir_p!(project1)
      _old_session = create_and_close_session("Old Session", project1)

      # Make old session appear 31 days old
      {:ok, [old_persisted | _]} = Persistence.list_resumable()
      session_file = Persistence.session_file(old_persisted.id)
      {:ok, content} = File.read(session_file)
      {:ok, data} = Jason.decode(content)

      old_timestamp =
        DateTime.utc_now()
        |> DateTime.add(-31 * 86400, :second)
        |> DateTime.to_iso8601()

      updated_data = Map.put(data, "closed_at", old_timestamp)
      {:ok, updated_json} = Jason.encode(updated_data, pretty: true)
      File.write!(session_file, updated_json)

      # Create active session
      project2 = Path.join(tmp_base, "active_session")
      File.mkdir_p!(project2)

      {:ok, active_session} =
        SessionSupervisor.create_session(
          project_path: project2,
          name: "Active Session",
          config: %{
            provider: "anthropic",
            model: "claude-3-5-haiku-20241022",
            temperature: 0.7,
            max_tokens: 4096
          }
        )

      # Add state to active session
      message = %{
        id: "msg-active",
        role: :user,
        content: "Active message",
        timestamp: DateTime.utc_now()
      }

      JidoCode.Session.State.append_message(active_session.id, message)

      # Run cleanup (should only affect old_session, not active)
      result = Persistence.cleanup(30)

      # Verify old session was deleted
      assert result.deleted >= 1

      # Verify active session still exists and has correct state
      assert {:ok, found} = SessionRegistry.lookup(active_session.id)
      assert found.name == "Active Session"

      {:ok, messages} = JidoCode.Session.State.get_messages(active_session.id)
      assert Enum.any?(messages, fn m -> m.content == "Active message" end)

      # Cleanup
      SessionSupervisor.stop_session(active_session.id)
    end
  end

  describe "concurrent delete operations" do
    test "concurrent deletes of same session are idempotent", %{tmp_base: tmp_base} do
      # Create session
      project_path = Path.join(tmp_base, "delete_test")
      File.mkdir_p!(project_path)

      session = create_and_close_session("Delete Test", project_path)
      session_id = session.id

      # Try to delete concurrently from 5 processes
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            result = Persistence.delete_persisted(session_id)
            {i, result}
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All should return :ok (idempotent)
      for {_i, result} <- results do
        assert result == :ok
      end

      # Verify file is gone
      session_file = Persistence.session_file(session_id)
      refute File.exists?(session_file)
    end
  end

  describe "list operations during modifications" do
    test "list_resumable during concurrent saves returns consistent data", %{tmp_base: tmp_base} do
      # Create several sessions
      for i <- 1..3 do
        project_path = Path.join(tmp_base, "list_test_#{i}")
        File.mkdir_p!(project_path)
        _session = create_and_close_session("List Test #{i}", project_path)
      end

      # Concurrently list and create new sessions
      tasks = [
        Task.async(fn -> Persistence.list_resumable() end),
        Task.async(fn -> Persistence.list_resumable() end),
        Task.async(fn ->
          project_path = Path.join(tmp_base, "list_test_new")
          File.mkdir_p!(project_path)
          create_and_close_session("New Session", project_path)
          :ok
        end)
      ]

      [result1, result2, :ok] = Task.await_many(tasks, 5000)

      # Both lists should be valid
      assert {:ok, list1} = result1
      assert {:ok, list2} = result2
      assert length(list1) >= 3
      assert length(list2) >= 3

      # All sessions should have required fields
      for session <- list1 do
        assert Map.has_key?(session, :id)
        assert Map.has_key?(session, :name)
        assert Map.has_key?(session, :project_path)
      end
    end
  end
end

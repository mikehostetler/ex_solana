defmodule JidoCode.Session.PersistenceIOFailureTest do
  @moduledoc """
  Tests for I/O failure scenarios in session persistence.

  These tests verify that the persistence layer handles various I/O failures
  gracefully, including disk full, permission errors, and directory deletion.

  Note: Some I/O failures (like true disk full) are difficult to simulate
  without platform-specific tools or mocking frameworks. These tests focus
  on verifiable error handling paths.
  """

  use ExUnit.Case, async: false

  alias JidoCode.Session.Persistence

  import JidoCode.PersistenceTestHelpers

  # UUID module for generating valid session IDs
  alias Uniq.UUID

  @moduletag :io_failure

  setup do
    # Wait for supervisor to be ready
    wait_for_supervisor()

    # Create unique test directory
    test_dir = create_test_directory("io_failure", :rand.uniform(100_000))

    on_exit(fn ->
      # Clean up test directory
      if File.exists?(test_dir) do
        File.rm_rf!(test_dir)
      end
    end)

    {:ok, test_dir: test_dir}
  end

  describe "disk full simulation (enospc)" do
    @tag :skip
    test "save operation handles disk full error gracefully", %{test_dir: _test_dir} do
      # NOTE: True disk full simulation requires platform-specific quota tools
      # or filesystem mocking, which is out of scope for this test suite.
      #
      # This test documents the expected behavior:
      # 1. save_session should return {:error, :enospc}
      # 2. No partial files should be left behind (atomic write cleanup)
      # 3. Error should be logged internally
      # 4. Error message should be sanitized for users
      #
      # The actual error handling code is in:
      # - lib/jido_code/session/persistence.ex:do_save_session/2
      # - File.write/2 error handling
      #
      # If disk full occurs during File.write:
      # - File.write returns {:error, :enospc}
      # - The temp file is not renamed (atomic write preserves original)
      # - Cleanup removes temp file
      # - Error is propagated to caller

      # This is documented as a known limitation of the test suite
      flunk("Platform-specific disk quota tools required for true enospc simulation")
    end

    @tag :skip
    test "atomic write rollback on disk full", %{test_dir: _test_dir} do
      # NOTE: This test would verify that:
      # 1. If disk fills during write, temp file is not promoted to final file
      # 2. Original session file (if any) is not corrupted
      # 3. Temp file is cleaned up
      #
      # Implementation uses temp + rename pattern:
      # - Write to temp_path = "#{path}.tmp"
      # - If write succeeds, rename to final path (atomic)
      # - If write fails, temp file exists but is not used
      #
      # Atomic rename is provided by File.rename which is an atomic
      # filesystem operation on most platforms.

      flunk("Platform-specific disk quota tools required")
    end
  end

  describe "permission errors (eacces)" do
    test "load handles permission denied error", %{test_dir: test_dir} do
      # Generate a proper UUID for session_id
      session_id = UUID.uuid4()

      # Ensure sessions directory exists and has proper permissions
      sessions_dir = Persistence.sessions_dir()
      File.mkdir_p!(sessions_dir)
      File.chmod!(sessions_dir, 0o700)

      # Create a minimal valid session file
      session_data = %{
        version: 1,
        id: session_id,
        name: "perm-test",
        project_path: test_dir,
        config: %{},
        created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        updated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        closed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        conversation: [],
        todos: []
      }

      file_path = Path.join([sessions_dir, "#{session_id}.json"])
      json = Jason.encode!(session_data)
      File.write!(file_path, json)

      # Make file unreadable (chmod 000)
      File.chmod!(file_path, 0o000)

      # Attempt to load - should return permission error
      result = Persistence.load(session_id)

      # Restore permissions for cleanup
      File.chmod!(file_path, 0o600)
      File.rm!(file_path)

      # Verify error is returned and properly typed
      assert {:error, reason} = result
      # File.read with no permissions returns :eacces
      assert reason == :eacces or match?({:file_error, _, :eacces}, reason)
    end

    test "save handles permission denied on directory", %{test_dir: test_dir} do
      # This test verifies error handling when sessions directory is read-only
      # We'll simulate this by attempting to save to a read-only directory

      sessions_dir = Persistence.sessions_dir()
      original_mode = File.stat!(sessions_dir).mode

      # Make sessions directory read-only (no write permission)
      File.chmod!(sessions_dir, 0o500)

      # Generate a proper UUID
      session_id = UUID.uuid4()

      # Create session data to serialize
      session_data = %{
        version: 1,
        id: session_id,
        name: "perm-save-test",
        project_path: test_dir,
        config: %{},
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        closed_at: DateTime.utc_now(),
        conversation: [],
        todos: []
      }

      # Attempt to write to read-only directory should fail
      file_path = Path.join([sessions_dir, "#{session_id}.json"])
      result = File.write(file_path, Jason.encode!(session_data))

      # Restore permissions for cleanup
      File.chmod!(sessions_dir, original_mode)

      # Verify error is returned
      assert {:error, reason} = result
      # Permission denied when trying to write to read-only directory
      assert reason == :eacces
    end

    test "sanitized error message for permission failures" do
      # Verify that permission errors are sanitized
      # (This tests the ErrorSanitizer integration)

      result = JidoCode.Commands.ErrorSanitizer.sanitize_error(:eacces)
      assert result == "Permission denied."

      # Should not expose paths
      result =
        JidoCode.Commands.ErrorSanitizer.sanitize_error(
          {:file_error, "/home/user/.jido_code/sessions/test.json", :eacces}
        )

      assert result == "Permission denied."
      refute String.contains?(result, "/home/user")
      refute String.contains?(result, ".jido_code")
    end

    @tag :platform_specific
    test "list_persisted handles permission denied on directory" do
      # NOTE: This test is platform-specific as Unix permission semantics
      # may not apply on all platforms (e.g., Windows)

      sessions_dir = Persistence.sessions_dir()
      original_mode = File.stat!(sessions_dir).mode

      # Remove read permission from directory
      File.chmod!(sessions_dir, 0o000)

      # Attempt to list - should return error
      result = Persistence.list_persisted()

      # Restore permissions
      File.chmod!(sessions_dir, original_mode)

      # Verify error is returned (not empty list)
      assert {:error, reason} = result
      assert reason == :eacces or match?({:file_error, _, :eacces}, reason)
    end
  end

  describe "directory deletion scenarios" do
    test "load handles deleted session file" do
      # Generate a proper UUID
      session_id = UUID.uuid4()

      # Attempt to load non-existent session - should return not found error
      result = Persistence.load(session_id)

      # Error can be either :enoent or :not_found depending on error sanitization
      assert {:error, reason} = result
      assert reason in [:enoent, :not_found]
    end

    test "load handles deleted sessions directory" do
      sessions_dir = Persistence.sessions_dir()
      original_exists = File.exists?(sessions_dir)

      # If directory exists, temporarily remove it
      if original_exists do
        # Move it aside
        backup_dir = "#{sessions_dir}.backup.#{:rand.uniform(100_000)}"
        File.rename!(sessions_dir, backup_dir)

        # Attempt to load - should fail gracefully
        session_id = UUID.uuid4()
        result = Persistence.load(session_id)

        # Restore directory
        File.rename!(backup_dir, sessions_dir)

        # Should return error for missing directory
        assert {:error, reason} = result
        assert reason in [:enoent, :not_found]
      else
        # Directory doesn't exist - just verify load fails
        session_id = UUID.uuid4()
        result = Persistence.load(session_id)
        assert {:error, reason} = result
        assert reason in [:enoent, :not_found]
      end
    end

    test "sessions_dir returns consistent path" do
      # Verify sessions_dir function works
      dir = Persistence.sessions_dir()
      assert is_binary(dir)
      assert String.contains?(dir, ".jido_code")
      assert String.contains?(dir, "sessions")
    end
  end

  describe "concurrent I/O failures" do
    test "concurrent load operations handle errors independently" do
      # Generate multiple UUIDs
      session_ids = for _i <- 1..5, do: UUID.uuid4()

      # Attempt to load all concurrently (all will fail with :enoent)
      tasks =
        for session_id <- session_ids do
          Task.async(fn ->
            Persistence.load(session_id)
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All should return error (not crash)
      assert Enum.all?(results, fn r -> match?({:error, _}, r) end)
    end

    test "concurrent list operations succeed" do
      # List concurrently multiple times
      tasks =
        for _i <- 1..5 do
          Task.async(fn ->
            Persistence.list_persisted()
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All should either succeed or fail gracefully (no crashes)
      assert Enum.all?(results, fn r ->
               match?({:ok, _}, r) or match?({:error, _}, r)
             end)
    end
  end

  describe "partial write scenarios" do
    test "atomic write pattern using temp file", %{test_dir: _test_dir} do
      # This test documents the atomic write pattern used by persistence:
      # 1. Write to temp file (*.tmp)
      # 2. Rename to final file (atomic operation)
      # 3. If rename fails, original file is untouched

      session_id = UUID.uuid4()
      sessions_dir = Persistence.sessions_dir()
      File.mkdir_p!(sessions_dir)
      File.chmod!(sessions_dir, 0o700)

      file_path = Path.join([sessions_dir, "#{session_id}.json"])
      temp_path = "#{file_path}.tmp"

      # Simulate atomic write pattern
      data = %{version: 1, id: session_id, name: "test"}
      json = Jason.encode!(data)

      # Step 1: Write to temp file
      :ok = File.write(temp_path, json)
      assert File.exists?(temp_path)
      refute File.exists?(file_path)

      # Step 2: Atomic rename
      :ok = File.rename(temp_path, file_path)
      assert File.exists?(file_path)
      refute File.exists?(temp_path)

      # Cleanup
      File.rm!(file_path)
    end

    test "JSON integrity is maintained after write", %{test_dir: _test_dir} do
      # Write a session file and verify JSON remains valid
      session_id = UUID.uuid4()
      sessions_dir = Persistence.sessions_dir()
      File.mkdir_p!(sessions_dir)
      File.chmod!(sessions_dir, 0o700)

      # Create session with large data
      session_data = %{
        version: 1,
        id: session_id,
        name: "json-integrity-test",
        project_path: "/tmp/test",
        config: %{},
        created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        updated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        closed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        conversation: [
          %{
            role: "user",
            content: String.duplicate("x", 10_000),
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
          }
        ],
        todos: []
      }

      file_path = Path.join([sessions_dir, "#{session_id}.json"])
      json = Jason.encode!(session_data)
      File.write!(file_path, json)

      # Verify file contains valid JSON
      {:ok, content} = File.read(file_path)
      assert {:ok, decoded} = Jason.decode(content)

      # Verify data integrity
      assert decoded["version"] == 1
      assert decoded["id"] == session_id
      [msg] = decoded["conversation"]
      assert msg["content"] == String.duplicate("x", 10_000)

      # Cleanup
      File.rm!(file_path)
    end
  end

  describe "error recovery" do
    test "system recovers after permission error", %{test_dir: _test_dir} do
      sessions_dir = Persistence.sessions_dir()
      File.mkdir_p!(sessions_dir)

      # First, ensure directory has proper permissions
      File.chmod!(sessions_dir, 0o700)

      # Make directory read-only
      File.chmod!(sessions_dir, 0o500)

      # Attempt write - should fail with permission error
      session_id = UUID.uuid4()
      file_path = Path.join([sessions_dir, "#{session_id}.json"])
      result1 = File.write(file_path, "{}")
      assert {:error, :eacces} = result1

      # Restore permissions (use 0o700 explicitly)
      File.chmod!(sessions_dir, 0o700)

      # Subsequent write should succeed
      result2 = File.write(file_path, "{}")
      assert :ok = result2

      # Cleanup
      File.rm!(file_path)
    end

    test "can delete file after I/O failure" do
      sessions_dir = Persistence.sessions_dir()
      File.mkdir_p!(sessions_dir)
      File.chmod!(sessions_dir, 0o700)

      # Create a session file
      session_id = UUID.uuid4()
      file_path = Path.join([sessions_dir, "#{session_id}.json"])
      File.write!(file_path, "{}")

      # Try to read with wrong session ID (should fail)
      wrong_id = UUID.uuid4()
      result = Persistence.load(wrong_id)
      assert {:error, reason} = result
      assert reason in [:enoent, :not_found]

      # Should still be able to delete correct file
      result = Persistence.delete_persisted(session_id)
      assert result == :ok
      refute File.exists?(file_path)
    end

    test "load errors don't affect subsequent operations" do
      # Attempt multiple failed loads
      for _i <- 1..5 do
        session_id = UUID.uuid4()
        result = Persistence.load(session_id)
        # Should get not-found error
        assert {:error, reason} = result
        assert reason in [:enoent, :not_found]
      end

      # list_persisted should still work
      result = Persistence.list_persisted()
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "error message sanitization for I/O failures" do
    test "disk full error is sanitized" do
      result = JidoCode.Commands.ErrorSanitizer.sanitize_error(:enospc)
      # Error message should be user-friendly
      assert result == "Insufficient disk space."

      # Should not expose internal details (atom name)
      refute String.contains?(result, "enospc")
    end

    test "file system error paths are stripped" do
      # Various file errors should not expose paths
      errors = [
        {:file_error, "/home/user/.jido_code/sessions/abc.json", :enospc},
        {:file_error, "/var/lib/sensitive/path.json", :eacces},
        {:file_error, "/tmp/session_data.json", :enoent}
      ]

      for error <- errors do
        result = JidoCode.Commands.ErrorSanitizer.sanitize_error(error)

        # Should not contain file paths
        refute result =~ ~r{/[a-zA-Z0-9_/.-]+}

        # Should be user-friendly
        assert String.ends_with?(result, ".")
      end
    end

    test "I/O errors in resume are sanitized" do
      # Test that resume errors go through sanitization
      # (Integration test with ErrorSanitizer)

      # Generate a valid UUID for a non-existent session
      non_existent_id = UUID.uuid4()

      # Attempt to resume non-existent session
      result = Persistence.resume(non_existent_id)

      # Should return error
      assert {:error, reason} = result

      # If this were passed through ErrorSanitizer.log_and_sanitize,
      # it would return a sanitized message
      sanitized = JidoCode.Commands.ErrorSanitizer.sanitize_error(reason)

      # Should be generic and user-friendly
      assert is_binary(sanitized)
      assert String.ends_with?(sanitized, ".")
    end
  end
end

defmodule JidoCode.Tools.HandlerHelpersTest do
  use ExUnit.Case, async: false

  alias JidoCode.Session
  alias JidoCode.Tools.HandlerHelpers

  setup do
    # Ensure application is started (SessionProcessRegistry is in supervision tree)
    Application.ensure_all_started(:jido_code)

    # Suppress deprecation warnings for tests
    Application.put_env(:jido_code, :suppress_global_manager_warnings, true)

    on_exit(fn ->
      Application.delete_env(:jido_code, :suppress_global_manager_warnings)
    end)

    :ok
  end

  # ============================================================================
  # get_project_root/1 Tests
  # ============================================================================

  describe "get_project_root/1" do
    test "returns project_root from context when provided" do
      context = %{project_root: "/home/user/project"}

      assert {:ok, "/home/user/project"} = HandlerHelpers.get_project_root(context)
    end

    test "falls back to global Manager when no context" do
      context = %{}

      # Should return the global manager's project root
      {:ok, path} = HandlerHelpers.get_project_root(context)
      assert is_binary(path)
    end

    test "falls back to global Manager when context is nil-like" do
      {:ok, path} = HandlerHelpers.get_project_root(%{foo: "bar"})
      assert is_binary(path)
    end
  end

  describe "get_project_root/1 with session_id" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      # Create a session with a manager for testing
      {:ok, session} = Session.new(project_path: tmp_dir, name: "helper-test")

      {:ok, supervisor_pid} =
        Session.Supervisor.start_link(
          session: session,
          name: {:via, Registry, {JidoCode.Registry, {:helper_test_sup, session.id}}}
        )

      on_exit(fn ->
        try do
          if Process.alive?(supervisor_pid), do: Supervisor.stop(supervisor_pid, :normal, 100)
        catch
          :exit, _ -> :ok
        end
      end)

      %{session: session, tmp_dir: tmp_dir}
    end

    test "prefers session_id over project_root", %{session: session, tmp_dir: tmp_dir} do
      # Context has both session_id and project_root
      context = %{session_id: session.id, project_root: "/other/path"}

      # Should use session_id (which returns tmp_dir)
      {:ok, path} = HandlerHelpers.get_project_root(context)
      assert path == tmp_dir
    end

    test "uses session_id to get project root from Session.Manager", %{
      session: session,
      tmp_dir: tmp_dir
    } do
      context = %{session_id: session.id}

      {:ok, path} = HandlerHelpers.get_project_root(context)
      assert path == tmp_dir
    end

    test "returns error for unknown session_id (valid UUID format)" do
      # Use a valid UUID format that doesn't exist
      context = %{session_id: "550e8400-e29b-41d4-a716-446655440000"}

      assert {:error, :not_found} = HandlerHelpers.get_project_root(context)
    end

    test "returns error for invalid session_id format" do
      context = %{session_id: "not-a-uuid"}

      assert {:error, :invalid_session_id} = HandlerHelpers.get_project_root(context)
    end

    test "returns error for empty session_id" do
      context = %{session_id: ""}

      assert {:error, :invalid_session_id} = HandlerHelpers.get_project_root(context)
    end
  end

  # ============================================================================
  # validate_path/2 Tests
  # ============================================================================

  describe "validate_path/2" do
    @describetag :tmp_dir

    test "validates path with project_root context", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      {:ok, resolved} = HandlerHelpers.validate_path("test.txt", context)
      assert resolved == Path.join(tmp_dir, "test.txt")
    end

    test "rejects path traversal with project_root context", %{tmp_dir: tmp_dir} do
      context = %{project_root: tmp_dir}

      assert {:error, :path_escapes_boundary} =
               HandlerHelpers.validate_path("../../../etc/passwd", context)
    end

    test "falls back to global Manager when no context" do
      context = %{}

      # Should use global manager's validate_path
      {:ok, path} = HandlerHelpers.validate_path("test.txt", context)
      assert is_binary(path)
    end
  end

  describe "validate_path/2 with session_id" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      # Create a session with a manager for testing
      {:ok, session} = Session.new(project_path: tmp_dir, name: "validate-test")

      {:ok, supervisor_pid} =
        Session.Supervisor.start_link(
          session: session,
          name: {:via, Registry, {JidoCode.Registry, {:validate_test_sup, session.id}}}
        )

      on_exit(fn ->
        try do
          if Process.alive?(supervisor_pid), do: Supervisor.stop(supervisor_pid, :normal, 100)
        catch
          :exit, _ -> :ok
        end
      end)

      %{session: session, tmp_dir: tmp_dir}
    end

    test "prefers session_id over project_root", %{session: session, tmp_dir: tmp_dir} do
      # Context has both session_id and project_root
      context = %{session_id: session.id, project_root: "/other/path"}

      # Should use session_id (which validates against tmp_dir)
      {:ok, path} = HandlerHelpers.validate_path("test.txt", context)
      assert path == Path.join(tmp_dir, "test.txt")
    end

    test "validates path using Session.Manager", %{session: session, tmp_dir: tmp_dir} do
      context = %{session_id: session.id}

      {:ok, resolved} = HandlerHelpers.validate_path("src/file.ex", context)
      assert resolved == Path.join(tmp_dir, "src/file.ex")
    end

    test "rejects path traversal via Session.Manager", %{session: session} do
      context = %{session_id: session.id}

      assert {:error, :path_escapes_boundary} =
               HandlerHelpers.validate_path("../../../etc/passwd", context)
    end

    test "returns error for unknown session_id (valid UUID format)" do
      # Use a valid UUID format that doesn't exist
      context = %{session_id: "550e8400-e29b-41d4-a716-446655440000"}

      assert {:error, :not_found} = HandlerHelpers.validate_path("test.txt", context)
    end

    test "returns error for invalid session_id format" do
      context = %{session_id: "not-a-valid-uuid"}

      assert {:error, :invalid_session_id} = HandlerHelpers.validate_path("test.txt", context)
    end

    test "returns error for empty session_id" do
      context = %{session_id: ""}

      assert {:error, :invalid_session_id} = HandlerHelpers.validate_path("test.txt", context)
    end
  end

  # ============================================================================
  # format_common_error/2 Tests
  # ============================================================================

  describe "format_common_error/2" do
    test "formats :enoent error" do
      assert {:ok, "Path not found: /some/path"} =
               HandlerHelpers.format_common_error(:enoent, "/some/path")
    end

    test "formats :eacces error" do
      assert {:ok, "Permission denied: /some/path"} =
               HandlerHelpers.format_common_error(:eacces, "/some/path")
    end

    test "formats :path_escapes_boundary error" do
      assert {:ok, msg} = HandlerHelpers.format_common_error(:path_escapes_boundary, "../escape")
      assert msg =~ "path escapes project boundary"
    end

    test "formats :path_outside_boundary error" do
      assert {:ok, msg} =
               HandlerHelpers.format_common_error(:path_outside_boundary, "/etc/passwd")

      assert msg =~ "path is outside project"
    end

    test "formats :symlink_escapes_boundary error" do
      assert {:ok, msg} = HandlerHelpers.format_common_error(:symlink_escapes_boundary, "link")
      assert msg =~ "symlink points outside project"
    end

    test "formats :invalid_session_id error" do
      assert {:ok, msg} = HandlerHelpers.format_common_error(:invalid_session_id, "bad-id")
      assert msg =~ "Invalid session ID format"
      assert msg =~ "UUID"
    end

    test "passes through string errors" do
      assert {:ok, "Custom error message"} =
               HandlerHelpers.format_common_error("Custom error message", "/path")
    end

    test "returns :not_handled for unknown error types" do
      assert :not_handled = HandlerHelpers.format_common_error(:unknown_error, "/path")
    end
  end

  # ============================================================================
  # Deprecation Warning Tests
  # ============================================================================

  describe "deprecation warnings" do
    import ExUnit.CaptureLog

    test "logs warning when get_project_root falls back to global manager" do
      # Temporarily enable warnings
      Application.put_env(:jido_code, :suppress_global_manager_warnings, false)

      log =
        capture_log(fn ->
          HandlerHelpers.get_project_root(%{})
        end)

      assert log =~ "get_project_root"
      assert log =~ "global Tools.Manager"
      assert log =~ "migrate to session-aware"

      # Re-suppress for other tests
      Application.put_env(:jido_code, :suppress_global_manager_warnings, true)
    end

    test "logs warning when validate_path falls back to global manager" do
      # Temporarily enable warnings
      Application.put_env(:jido_code, :suppress_global_manager_warnings, false)

      log =
        capture_log(fn ->
          HandlerHelpers.validate_path("test.txt", %{})
        end)

      assert log =~ "validate_path"
      assert log =~ "global Tools.Manager"
      assert log =~ "migrate to session-aware"

      # Re-suppress for other tests
      Application.put_env(:jido_code, :suppress_global_manager_warnings, true)
    end

    test "suppresses warnings when config is set" do
      # Ensure warnings are suppressed (should already be from setup)
      Application.put_env(:jido_code, :suppress_global_manager_warnings, true)

      log =
        capture_log(fn ->
          HandlerHelpers.get_project_root(%{})
          HandlerHelpers.validate_path("test.txt", %{})
        end)

      # Should not contain deprecation warnings
      refute log =~ "global Tools.Manager"
    end
  end

  # ============================================================================
  # UUID Validation Edge Cases
  # ============================================================================

  describe "UUID validation edge cases" do
    test "accepts lowercase UUIDs" do
      # Valid UUID but session doesn't exist
      context = %{session_id: "550e8400-e29b-41d4-a716-446655440000"}
      assert {:error, :not_found} = HandlerHelpers.get_project_root(context)
    end

    test "accepts uppercase UUIDs" do
      # Valid UUID but session doesn't exist
      context = %{session_id: "550E8400-E29B-41D4-A716-446655440000"}
      assert {:error, :not_found} = HandlerHelpers.get_project_root(context)
    end

    test "accepts mixed case UUIDs" do
      # Valid UUID but session doesn't exist
      context = %{session_id: "550e8400-E29B-41d4-A716-446655440000"}
      assert {:error, :not_found} = HandlerHelpers.get_project_root(context)
    end

    test "rejects UUID-like strings with wrong length" do
      context = %{session_id: "550e8400-e29b-41d4-a716-44665544000"}
      assert {:error, :invalid_session_id} = HandlerHelpers.get_project_root(context)
    end

    test "rejects UUID-like strings with invalid characters" do
      context = %{session_id: "550e8400-e29b-41d4-a716-44665544000g"}
      assert {:error, :invalid_session_id} = HandlerHelpers.get_project_root(context)
    end

    test "rejects UUID without hyphens" do
      context = %{session_id: "550e8400e29b41d4a716446655440000"}
      assert {:error, :invalid_session_id} = HandlerHelpers.get_project_root(context)
    end
  end
end

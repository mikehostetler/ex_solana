defmodule JidoCode.DefaultSessionTest do
  @moduledoc """
  Tests for default session creation on application startup.

  These tests verify that:
  - A default session is created for a project directory
  - The session has the correct name (folder name)
  - The session has the correct project path
  - Error handling works gracefully
  """
  use ExUnit.Case, async: false

  import JidoCode.Test.SessionTestHelpers

  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    # Use shared test helper for proper isolation
    {:ok, %{tmp_dir: tmp_dir}} = setup_session_supervisor("default_session")
    {:ok, %{tmp_dir: tmp_dir}}
  end

  # ============================================================================
  # Default Session Tests
  # ============================================================================

  describe "default session creation" do
    test "create_session creates session for project path", %{tmp_dir: tmp_dir} do
      name = Path.basename(tmp_dir)

      # Create a session (simulating what Application.start does)
      assert {:ok, session} = SessionSupervisor.create_session(project_path: tmp_dir, name: name)

      # Verify session properties
      assert session.project_path == tmp_dir
      assert session.name == name
      assert is_binary(session.id)

      # Verify session is running
      assert SessionSupervisor.session_running?(session.id)
    end

    test "default session is registered in SessionRegistry", %{tmp_dir: tmp_dir} do
      name = Path.basename(tmp_dir)

      {:ok, session} = SessionSupervisor.create_session(project_path: tmp_dir, name: name)

      # Verify can lookup by ID
      assert {:ok, ^session} = SessionRegistry.lookup(session.id)

      # Verify can lookup by path
      assert {:ok, ^session} = SessionRegistry.lookup_by_path(tmp_dir)
    end

    test "default session has Manager and State children", %{tmp_dir: tmp_dir} do
      name = Path.basename(tmp_dir)

      {:ok, session} = SessionSupervisor.create_session(project_path: tmp_dir, name: name)

      # Verify Manager is accessible
      assert {:ok, manager_pid} = JidoCode.Session.Supervisor.get_manager(session.id)
      assert Process.alive?(manager_pid)

      # Verify State is accessible
      assert {:ok, state_pid} = JidoCode.Session.Supervisor.get_state(session.id)
      assert Process.alive?(state_pid)
    end

    test "application continues if session creation fails", %{tmp_dir: tmp_dir} do
      # First create a session to simulate normal startup
      {:ok, session} = SessionSupervisor.create_session(project_path: tmp_dir, name: "first")

      # Attempting to create another session for the same path should fail
      # but should not crash the application
      result = SessionSupervisor.create_session(project_path: tmp_dir, name: "second")
      assert {:error, :project_already_open} = result

      # Original session should still be running
      assert SessionSupervisor.session_running?(session.id)
    end

    test "session uses folder name as default name", %{tmp_dir: tmp_dir} do
      # Create session without explicit name
      {:ok, session} = SessionSupervisor.create_session(project_path: tmp_dir)

      # Name should be the folder name
      assert session.name == Path.basename(tmp_dir)
    end
  end

  describe "SessionRegistry.list_ids/0 for default session access" do
    test "returns empty list when no sessions" do
      assert SessionRegistry.list_ids() == []
    end

    test "returns session ID after default session created", %{tmp_dir: tmp_dir} do
      {:ok, session} = SessionSupervisor.create_session(project_path: tmp_dir)

      ids = SessionRegistry.list_ids()
      assert session.id in ids
    end

    test "can get default session ID as first in list", %{tmp_dir: tmp_dir} do
      {:ok, session} = SessionSupervisor.create_session(project_path: tmp_dir)

      [first_id | _] = SessionRegistry.list_ids()
      assert first_id == session.id
    end
  end
end

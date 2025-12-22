defmodule JidoCode.Integration.SessionPhase1Test do
  @moduledoc """
  Integration tests for Phase 1 (Session Foundation) components.

  These tests verify that all Phase 1 components work together correctly:
  - Session struct and lifecycle
  - SessionRegistry for tracking sessions
  - SessionSupervisor for managing session processes
  - Session.Supervisor for per-session child processes

  Tests use the application's infrastructure (already running) and clean up
  after themselves.
  """
  use ExUnit.Case, async: false

  alias JidoCode.Session
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    # Ensure the application is started (in case other tests stopped it)
    {:ok, _} = Application.ensure_all_started(:jido_code)

    # Wait for SessionSupervisor to be available
    wait_for_supervisor()

    # Clear any existing test sessions from Registry
    SessionRegistry.clear()

    # Stop any running sessions under SessionSupervisor
    for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(SessionSupervisor) do
      DynamicSupervisor.terminate_child(SessionSupervisor, pid)
    end

    # Create temp base directory for test sessions
    tmp_base = Path.join(System.tmp_dir!(), "phase1_integration_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_base)

    on_exit(fn ->
      # Stop all test sessions (defensive - supervisor may have been stopped)
      if Process.whereis(SessionSupervisor) do
        for session <- SessionRegistry.list_all() do
          SessionSupervisor.stop_session(session.id)
        end
      end

      SessionRegistry.clear()
      File.rm_rf!(tmp_base)
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
        raise "SessionSupervisor not available after waiting"
      end
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp create_test_dir(base, name) do
    path = Path.join(base, name)
    File.mkdir_p!(path)
    path
  end

  defp wait_for_process_death(pid, timeout \\ 1000) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        {:error, :timeout}
    end
  end

  # ============================================================================
  # 1.6.1 Session Lifecycle Integration Tests
  # ============================================================================

  describe "1.6.1 session lifecycle integration" do
    test "create session → verify in Registry → verify processes running → stop → verify cleanup",
         %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "lifecycle_test")

      # Create session
      assert {:ok, session} = SessionSupervisor.create_session(project_path: path)
      assert is_binary(session.id)

      # Verify in Registry
      assert {:ok, ^session} = SessionRegistry.lookup(session.id)
      assert {:ok, ^session} = SessionRegistry.lookup_by_path(path)

      # Verify processes running
      assert SessionSupervisor.session_running?(session.id)
      assert {:ok, manager_pid} = JidoCode.Session.Supervisor.get_manager(session.id)
      assert {:ok, state_pid} = JidoCode.Session.Supervisor.get_state(session.id)
      assert Process.alive?(manager_pid)
      assert Process.alive?(state_pid)

      # Stop session
      assert :ok = SessionSupervisor.stop_session(session.id)

      # Verify cleanup
      assert {:error, :not_found} = SessionRegistry.lookup(session.id)
      refute SessionSupervisor.session_running?(session.id)

      # Wait for processes to die
      assert :ok = wait_for_process_death(manager_pid)
      assert :ok = wait_for_process_death(state_pid)
    end

    test "create session with custom config → verify config propagated", %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "custom_config")

      custom_config = %{
        "provider" => "openai",
        "model" => "gpt-4",
        "temperature" => 0.5,
        "max_tokens" => 2048
      }

      assert {:ok, session} =
               SessionSupervisor.create_session(project_path: path, config: custom_config)

      # Verify config in session
      assert session.config["provider"] == "openai"
      assert session.config["model"] == "gpt-4"
      assert session.config["temperature"] == 0.5
      assert session.config["max_tokens"] == 2048

      # Verify config in Registry
      assert {:ok, registered} = SessionRegistry.lookup(session.id)
      assert registered.config == session.config
    end

    test "update session in Registry → verify updated_at changes", %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "update_test")

      assert {:ok, session} = SessionSupervisor.create_session(project_path: path)
      original_updated_at = session.updated_at

      # Small delay to ensure timestamp changes
      Process.sleep(10)

      # Update config
      assert {:ok, updated} = Session.update_config(session, %{"temperature" => 0.9})
      assert {:ok, _} = SessionRegistry.update(updated)

      # Verify updated_at changed
      assert {:ok, from_registry} = SessionRegistry.lookup(session.id)
      assert DateTime.compare(from_registry.updated_at, original_updated_at) == :gt
    end

    test "rename session → verify Registry updated", %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "rename_test")

      assert {:ok, session} = SessionSupervisor.create_session(project_path: path)
      original_name = session.name

      # Rename
      assert {:ok, renamed} = Session.rename(session, "new-name")
      assert {:ok, _} = SessionRegistry.update(renamed)

      # Verify in Registry
      assert {:ok, from_registry} = SessionRegistry.lookup(session.id)
      assert from_registry.name == "new-name"
      assert from_registry.name != original_name

      # Verify lookup by name works
      assert {:ok, ^from_registry} = SessionRegistry.lookup_by_name("new-name")
    end

    test "session process crash → verify supervisor restarts children → verify Registry intact",
         %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "crash_test")

      assert {:ok, session} = SessionSupervisor.create_session(project_path: path)
      assert {:ok, manager_pid} = JidoCode.Session.Supervisor.get_manager(session.id)
      assert {:ok, state_pid} = JidoCode.Session.Supervisor.get_state(session.id)

      # Monitor original pids
      manager_ref = Process.monitor(manager_pid)
      state_ref = Process.monitor(state_pid)

      # Kill the manager (should trigger :one_for_all restart)
      Process.exit(manager_pid, :kill)

      # Wait for restart
      receive do
        {:DOWN, ^manager_ref, :process, ^manager_pid, :killed} -> :ok
      after
        1000 -> flunk("Manager didn't die")
      end

      # State should also restart due to :one_for_all
      receive do
        {:DOWN, ^state_ref, :process, ^state_pid, _} -> :ok
      after
        1000 -> flunk("State didn't restart")
      end

      # Wait for supervisor to restart children
      Process.sleep(100)

      # Verify session still running with new pids
      assert SessionSupervisor.session_running?(session.id)
      assert {:ok, new_manager_pid} = JidoCode.Session.Supervisor.get_manager(session.id)
      assert {:ok, new_state_pid} = JidoCode.Session.Supervisor.get_state(session.id)

      # Pids should be different (restarted)
      assert new_manager_pid != manager_pid
      assert new_state_pid != state_pid

      # Registry should be intact
      assert {:ok, ^session} = SessionRegistry.lookup(session.id)
    end
  end

  # ============================================================================
  # 1.6.2 Multi-Session Integration Tests
  # ============================================================================

  describe "1.6.2 multi-session integration" do
    test "create 3 sessions → verify all in Registry → verify all processes running",
         %{tmp_base: tmp_base} do
      paths =
        for i <- 1..3 do
          create_test_dir(tmp_base, "multi_#{i}")
        end

      # Create sessions
      sessions =
        for path <- paths do
          {:ok, session} = SessionSupervisor.create_session(project_path: path)
          session
        end

      # Verify all in Registry
      assert SessionRegistry.count() == 3

      for session <- sessions do
        assert {:ok, ^session} = SessionRegistry.lookup(session.id)
      end

      # Verify all processes running
      for session <- sessions do
        assert SessionSupervisor.session_running?(session.id)
        assert {:ok, _} = JidoCode.Session.Supervisor.get_manager(session.id)
        assert {:ok, _} = JidoCode.Session.Supervisor.get_state(session.id)
      end
    end

    test "create sessions for different paths → verify isolation", %{tmp_base: tmp_base} do
      path1 = create_test_dir(tmp_base, "isolated_1")
      path2 = create_test_dir(tmp_base, "isolated_2")

      {:ok, session1} = SessionSupervisor.create_session(project_path: path1, name: "session-one")
      {:ok, session2} = SessionSupervisor.create_session(project_path: path2, name: "session-two")

      # Verify different IDs
      assert session1.id != session2.id

      # Verify different paths
      assert session1.project_path != session2.project_path

      # Verify different process pids
      {:ok, manager1} = JidoCode.Session.Supervisor.get_manager(session1.id)
      {:ok, manager2} = JidoCode.Session.Supervisor.get_manager(session2.id)
      assert manager1 != manager2

      {:ok, state1} = JidoCode.Session.Supervisor.get_state(session1.id)
      {:ok, state2} = JidoCode.Session.Supervisor.get_state(session2.id)
      assert state1 != state2
    end

    test "stop one session → verify others unaffected", %{tmp_base: tmp_base} do
      path1 = create_test_dir(tmp_base, "stop_test_1")
      path2 = create_test_dir(tmp_base, "stop_test_2")
      path3 = create_test_dir(tmp_base, "stop_test_3")

      {:ok, session1} = SessionSupervisor.create_session(project_path: path1)
      {:ok, session2} = SessionSupervisor.create_session(project_path: path2)
      {:ok, session3} = SessionSupervisor.create_session(project_path: path3)

      # Stop session2
      :ok = SessionSupervisor.stop_session(session2.id)

      # Verify session2 stopped
      refute SessionSupervisor.session_running?(session2.id)
      assert {:error, :not_found} = SessionRegistry.lookup(session2.id)

      # Verify session1 and session3 still running
      assert SessionSupervisor.session_running?(session1.id)
      assert SessionSupervisor.session_running?(session3.id)
      assert {:ok, _} = SessionRegistry.lookup(session1.id)
      assert {:ok, _} = SessionRegistry.lookup(session3.id)

      # Verify count updated
      assert SessionRegistry.count() == 2
    end

    test "lookup by ID, path, and name all work correctly with multiple sessions",
         %{tmp_base: tmp_base} do
      path1 = create_test_dir(tmp_base, "lookup_1")
      path2 = create_test_dir(tmp_base, "lookup_2")

      {:ok, session1} = SessionSupervisor.create_session(project_path: path1, name: "alpha")
      {:ok, session2} = SessionSupervisor.create_session(project_path: path2, name: "beta")

      # Lookup by ID
      assert {:ok, ^session1} = SessionRegistry.lookup(session1.id)
      assert {:ok, ^session2} = SessionRegistry.lookup(session2.id)

      # Lookup by path
      assert {:ok, ^session1} = SessionRegistry.lookup_by_path(path1)
      assert {:ok, ^session2} = SessionRegistry.lookup_by_path(path2)

      # Lookup by name
      assert {:ok, ^session1} = SessionRegistry.lookup_by_name("alpha")
      assert {:ok, ^session2} = SessionRegistry.lookup_by_name("beta")
    end

    test "list_all/0 returns all sessions sorted by created_at", %{tmp_base: tmp_base} do
      # Create sessions with small delays to ensure different timestamps
      path1 = create_test_dir(tmp_base, "list_1")
      {:ok, session1} = SessionSupervisor.create_session(project_path: path1)
      Process.sleep(10)

      path2 = create_test_dir(tmp_base, "list_2")
      {:ok, session2} = SessionSupervisor.create_session(project_path: path2)
      Process.sleep(10)

      path3 = create_test_dir(tmp_base, "list_3")
      {:ok, session3} = SessionSupervisor.create_session(project_path: path3)

      # Get all sessions
      all_sessions = SessionRegistry.list_all()

      assert length(all_sessions) == 3

      # Verify sorted by created_at (oldest first)
      [first, second, third] = all_sessions
      assert first.id == session1.id
      assert second.id == session2.id
      assert third.id == session3.id
    end
  end

  # ============================================================================
  # 1.6.3 Session Limit Integration Tests
  # ============================================================================

  describe "1.6.3 session limit integration" do
    test "create exactly 10 sessions → all succeed", %{tmp_base: tmp_base} do
      sessions =
        for i <- 1..10 do
          path = create_test_dir(tmp_base, "limit_#{i}")
          {:ok, session} = SessionSupervisor.create_session(project_path: path)
          session
        end

      assert length(sessions) == 10
      assert SessionRegistry.count() == 10

      # All sessions should be running
      for session <- sessions do
        assert SessionSupervisor.session_running?(session.id)
      end
    end

    test "create 11th session → fails with :session_limit_reached", %{tmp_base: tmp_base} do
      # Create 10 sessions
      for i <- 1..10 do
        path = create_test_dir(tmp_base, "limit11_#{i}")
        {:ok, _} = SessionSupervisor.create_session(project_path: path)
      end

      assert SessionRegistry.count() == 10

      # 11th should fail
      path11 = create_test_dir(tmp_base, "limit11_11")

      assert {:error, {:session_limit_reached, 10, 10}} =
               SessionSupervisor.create_session(project_path: path11)

      # Count should still be 10
      assert SessionRegistry.count() == 10
    end

    test "at limit → stop one → create new → succeeds", %{tmp_base: tmp_base} do
      # Create 10 sessions
      sessions =
        for i <- 1..10 do
          path = create_test_dir(tmp_base, "recycle_#{i}")
          {:ok, session} = SessionSupervisor.create_session(project_path: path)
          session
        end

      assert SessionRegistry.count() == 10

      # Stop one session
      [first | _rest] = sessions
      :ok = SessionSupervisor.stop_session(first.id)

      assert SessionRegistry.count() == 9

      # Create new session should succeed
      path_new = create_test_dir(tmp_base, "recycle_new")
      assert {:ok, new_session} = SessionSupervisor.create_session(project_path: path_new)

      assert SessionRegistry.count() == 10
      assert SessionSupervisor.session_running?(new_session.id)
    end

    test "duplicate path rejected even when under limit", %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "duplicate_path")

      {:ok, _session1} = SessionSupervisor.create_session(project_path: path)

      # Try to create another session with same path
      assert {:error, :project_already_open} =
               SessionSupervisor.create_session(project_path: path)

      # Only one session should exist
      assert SessionRegistry.count() == 1
    end

    test "duplicate ID rejected (edge case)", %{tmp_base: tmp_base} do
      path1 = create_test_dir(tmp_base, "dup_id_1")
      path2 = create_test_dir(tmp_base, "dup_id_2")

      {:ok, session1} = SessionSupervisor.create_session(project_path: path1)

      # Manually create a session with same ID (edge case)
      {:ok, session2} = Session.new(project_path: path2)
      # Force same ID
      session2_with_same_id = %{session2 | id: session1.id}

      assert {:error, :session_exists} = SessionRegistry.register(session2_with_same_id)
    end
  end

  # ============================================================================
  # 1.6.4 Registry-Supervisor Coordination Tests
  # ============================================================================

  describe "1.6.4 registry-supervisor coordination" do
    test "session registered in Registry before processes start", %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "reg_before")

      # This is implicit in the implementation, but we verify the result
      {:ok, session} = SessionSupervisor.create_session(project_path: path)

      # Both should be true immediately after create
      assert {:ok, _} = SessionRegistry.lookup(session.id)
      assert SessionSupervisor.session_running?(session.id)
    end

    test "session unregistered from Registry after processes stop", %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "unreg_after")

      {:ok, session} = SessionSupervisor.create_session(project_path: path)
      {:ok, _pid} = SessionSupervisor.find_session_pid(session.id)

      # Stop session
      :ok = SessionSupervisor.stop_session(session.id)

      # Wait a bit for cleanup
      Process.sleep(50)

      # Both should be gone
      assert {:error, :not_found} = SessionRegistry.lookup(session.id)
      assert {:error, :not_found} = SessionSupervisor.find_session_pid(session.id)
    end

    test "Registry count matches DynamicSupervisor child count", %{tmp_base: tmp_base} do
      for i <- 1..5 do
        path = create_test_dir(tmp_base, "count_#{i}")
        {:ok, _} = SessionSupervisor.create_session(project_path: path)
      end

      registry_count = SessionRegistry.count()
      supervisor_count = DynamicSupervisor.count_children(SessionSupervisor).active

      assert registry_count == supervisor_count
      assert registry_count == 5
    end

    test "find_session_pid/1 returns correct pid for registered session", %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "find_pid")

      {:ok, session} = SessionSupervisor.create_session(project_path: path)
      {:ok, pid} = SessionSupervisor.find_session_pid(session.id)

      # Verify it's the per-session supervisor pid
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Verify the pid is registered in SessionProcessRegistry
      [{^pid, nil}] = Registry.lookup(JidoCode.SessionProcessRegistry, {:session, session.id})
    end

    test "session_running?/1 matches Registry state", %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "running_match")

      # Before creation
      fake_id = "nonexistent-#{:rand.uniform(100_000)}"
      refute SessionSupervisor.session_running?(fake_id)
      assert {:error, :not_found} = SessionRegistry.lookup(fake_id)

      # After creation
      {:ok, session} = SessionSupervisor.create_session(project_path: path)
      assert SessionSupervisor.session_running?(session.id)
      assert {:ok, _} = SessionRegistry.lookup(session.id)

      # After stop
      :ok = SessionSupervisor.stop_session(session.id)
      Process.sleep(50)
      refute SessionSupervisor.session_running?(session.id)
      assert {:error, :not_found} = SessionRegistry.lookup(session.id)
    end

    test "cleanup on partial failure (supervisor start fails)", %{tmp_base: tmp_base} do
      # This tests the rollback behavior when supervisor start fails
      # We can't easily trigger this without mocking, so we verify the
      # cleanup behavior by checking that failed sessions don't leave
      # orphaned Registry entries

      path = create_test_dir(tmp_base, "partial_fail")

      # Create a valid session first
      {:ok, session} = SessionSupervisor.create_session(project_path: path)

      # Now try to create with same path (will fail)
      {:error, :project_already_open} = SessionSupervisor.create_session(project_path: path)

      # Verify no orphaned entries
      all_sessions = SessionRegistry.list_all()
      assert length(all_sessions) == 1
      assert hd(all_sessions).id == session.id
    end
  end

  # ============================================================================
  # 1.6.5 Child Process Access Integration Tests
  # ============================================================================

  describe "1.6.5 child process access integration" do
    test "get_manager/1 returns live Manager pid", %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "get_manager")

      {:ok, session} = SessionSupervisor.create_session(project_path: path)
      {:ok, manager_pid} = JidoCode.Session.Supervisor.get_manager(session.id)

      assert is_pid(manager_pid)
      assert Process.alive?(manager_pid)
    end

    test "get_state/1 returns live State pid", %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "get_state")

      {:ok, session} = SessionSupervisor.create_session(project_path: path)
      {:ok, state_pid} = JidoCode.Session.Supervisor.get_state(session.id)

      assert is_pid(state_pid)
      assert Process.alive?(state_pid)
    end

    test "child pids are different for different sessions", %{tmp_base: tmp_base} do
      path1 = create_test_dir(tmp_base, "diff_pids_1")
      path2 = create_test_dir(tmp_base, "diff_pids_2")

      {:ok, session1} = SessionSupervisor.create_session(project_path: path1)
      {:ok, session2} = SessionSupervisor.create_session(project_path: path2)

      {:ok, manager1} = JidoCode.Session.Supervisor.get_manager(session1.id)
      {:ok, manager2} = JidoCode.Session.Supervisor.get_manager(session2.id)
      {:ok, state1} = JidoCode.Session.Supervisor.get_state(session1.id)
      {:ok, state2} = JidoCode.Session.Supervisor.get_state(session2.id)

      assert manager1 != manager2
      assert state1 != state2
    end

    test "child pids change after supervisor restart", %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "restart_pids")

      {:ok, session} = SessionSupervisor.create_session(project_path: path)
      {:ok, original_manager} = JidoCode.Session.Supervisor.get_manager(session.id)
      {:ok, original_state} = JidoCode.Session.Supervisor.get_state(session.id)

      # Kill one child to trigger restart
      Process.exit(original_manager, :kill)

      # Wait for restart
      Process.sleep(100)

      # Get new pids
      {:ok, new_manager} = JidoCode.Session.Supervisor.get_manager(session.id)
      {:ok, new_state} = JidoCode.Session.Supervisor.get_state(session.id)

      # Should be different (restarted)
      assert new_manager != original_manager
      assert new_state != original_state

      # But should be alive
      assert Process.alive?(new_manager)
      assert Process.alive?(new_state)
    end

    test "get_manager/1 returns error for stopped session", %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "stopped_manager")

      {:ok, session} = SessionSupervisor.create_session(project_path: path)

      # Verify works while running
      assert {:ok, _} = JidoCode.Session.Supervisor.get_manager(session.id)

      # Stop session
      :ok = SessionSupervisor.stop_session(session.id)
      Process.sleep(50)

      # Should return error
      assert {:error, :not_found} = JidoCode.Session.Supervisor.get_manager(session.id)
      assert {:error, :not_found} = JidoCode.Session.Supervisor.get_state(session.id)
    end
  end
end

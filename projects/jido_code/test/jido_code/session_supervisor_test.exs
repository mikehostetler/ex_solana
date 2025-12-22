defmodule JidoCode.SessionSupervisorTest do
  use ExUnit.Case, async: false

  alias JidoCode.Session
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor
  alias JidoCode.Test.SessionSupervisorStub
  alias JidoCode.Test.SessionTestHelpers

  describe "start_link/1" do
    test "starts the supervisor successfully" do
      # Stop if already running from application
      if pid = Process.whereis(SessionSupervisor) do
        Supervisor.stop(pid)
      end

      assert {:ok, pid} = SessionSupervisor.start_link([])
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Cleanup
      Supervisor.stop(pid)
    end

    test "registers the supervisor with module name" do
      # Stop if already running from application
      if pid = Process.whereis(SessionSupervisor) do
        Supervisor.stop(pid)
      end

      {:ok, pid} = SessionSupervisor.start_link([])

      assert Process.whereis(SessionSupervisor) == pid

      # Cleanup
      Supervisor.stop(pid)
    end

    test "returns error when already started" do
      # Stop if already running from application
      if pid = Process.whereis(SessionSupervisor) do
        Supervisor.stop(pid)
      end

      {:ok, _pid} = SessionSupervisor.start_link([])

      # Attempting to start again should fail
      assert {:error, {:already_started, _}} = SessionSupervisor.start_link([])

      # Cleanup
      Supervisor.stop(Process.whereis(SessionSupervisor))
    end
  end

  describe "init/1" do
    test "initializes with :one_for_one strategy" do
      # The init callback returns the supervisor spec
      assert {:ok, spec} = SessionSupervisor.init([])

      # DynamicSupervisor.init returns a tuple with flags
      assert is_map(spec)
      assert spec.strategy == :one_for_one
    end

    test "ignores options" do
      # Options are accepted but not used currently
      assert {:ok, _spec} = SessionSupervisor.init(some: :option)
    end
  end

  describe "supervisor behavior" do
    setup do
      # Stop if already running from application
      if pid = Process.whereis(SessionSupervisor) do
        Supervisor.stop(pid)
      end

      {:ok, pid} = SessionSupervisor.start_link([])

      on_exit(fn ->
        # Only stop if the process is still alive and registered
        if Process.alive?(pid) do
          try do
            Supervisor.stop(pid)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      {:ok, pid: pid}
    end

    test "is a DynamicSupervisor", %{pid: pid} do
      # Check the supervisor info
      info = DynamicSupervisor.count_children(pid)
      assert is_map(info)
      assert Map.has_key?(info, :active)
      assert Map.has_key?(info, :specs)
      assert Map.has_key?(info, :supervisors)
      assert Map.has_key?(info, :workers)
    end

    test "starts with no children", %{pid: pid} do
      info = DynamicSupervisor.count_children(pid)
      assert info.active == 0
    end

    test "can list children (empty initially)", %{pid: pid} do
      children = DynamicSupervisor.which_children(pid)
      assert children == []
    end
  end

  describe "child_spec/1" do
    test "returns correct child specification" do
      spec = SessionSupervisor.child_spec([])

      assert spec.id == SessionSupervisor
      assert spec.start == {SessionSupervisor, :start_link, [[]]}
      assert spec.type == :supervisor
    end
  end

  # ============================================================================
  # Session Lifecycle Tests (Task 1.3.2)
  # ============================================================================

  describe "start_session/1" do
    setup do
      {:ok, context} = SessionTestHelpers.setup_session_supervisor("start_session")
      context
    end

    test "starts a session and returns pid", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      assert {:ok, pid} =
               SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "registers session in SessionRegistry", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, _pid} =
        SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      # Session should be in registry
      assert {:ok, registered} = SessionRegistry.lookup(session.id)
      assert registered.id == session.id
      assert registered.project_path == tmp_dir
    end

    test "registers session process in SessionProcessRegistry", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} =
        SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      # Process should be findable via Registry
      assert [{^pid, _}] =
               Registry.lookup(JidoCode.SessionProcessRegistry, {:session, session.id})
    end

    test "fails with :session_limit_reached when limit exceeded", %{tmp_dir: tmp_dir} do
      # Set low limit for testing
      original = Application.get_env(:jido_code, :max_sessions)
      Application.put_env(:jido_code, :max_sessions, 2)

      on_exit(fn ->
        if original do
          Application.put_env(:jido_code, :max_sessions, original)
        else
          Application.delete_env(:jido_code, :max_sessions)
        end
      end)

      # Create 2 sessions to hit limit
      dir1 = Path.join(tmp_dir, "project1")
      dir2 = Path.join(tmp_dir, "project2")
      dir3 = Path.join(tmp_dir, "project3")
      File.mkdir_p!(dir1)
      File.mkdir_p!(dir2)
      File.mkdir_p!(dir3)

      {:ok, s1} = Session.new(project_path: dir1)
      {:ok, s2} = Session.new(project_path: dir2)
      {:ok, s3} = Session.new(project_path: dir3)

      {:ok, _} = SessionSupervisor.start_session(s1, supervisor_module: SessionSupervisorStub)
      {:ok, _} = SessionSupervisor.start_session(s2, supervisor_module: SessionSupervisorStub)

      # Third should fail
      assert {:error, {:session_limit_reached, 2, 2}} =
               SessionSupervisor.start_session(s3, supervisor_module: SessionSupervisorStub)
    end

    test "fails with :session_exists for duplicate ID", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, _} =
        SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      # Same session again should fail
      assert {:error, :session_exists} =
               SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)
    end

    test "fails with :project_already_open for duplicate path", %{tmp_dir: tmp_dir} do
      {:ok, session1} = Session.new(project_path: tmp_dir)
      {:ok, session2} = Session.new(project_path: tmp_dir)

      {:ok, _} =
        SessionSupervisor.start_session(session1, supervisor_module: SessionSupervisorStub)

      # Different session, same path should fail
      assert {:error, :project_already_open} =
               SessionSupervisor.start_session(session2, supervisor_module: SessionSupervisorStub)
    end

    test "increments DynamicSupervisor child count", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      assert DynamicSupervisor.count_children(SessionSupervisor).active == 0

      {:ok, _} =
        SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      assert DynamicSupervisor.count_children(SessionSupervisor).active == 1
    end

    test "cleans up registry when supervisor start fails", %{tmp_dir: tmp_dir} do
      # Define a stub that fails to start
      defmodule FailingSessionStub do
        def child_spec(opts) do
          session = Keyword.fetch!(opts, :session)

          %{
            id: {:failing_session, session.id},
            start: {__MODULE__, :start_link, [opts]},
            type: :supervisor,
            restart: :temporary
          }
        end

        def start_link(_opts) do
          {:error, :intentional_failure}
        end
      end

      {:ok, session} = Session.new(project_path: tmp_dir)

      # Attempt to start with failing stub
      assert {:error, :intentional_failure} =
               SessionSupervisor.start_session(session, supervisor_module: FailingSessionStub)

      # Session should NOT be in registry (cleanup happened)
      assert {:error, :not_found} = SessionRegistry.lookup(session.id)
    end
  end

  describe "stop_session/1" do
    setup do
      {:ok, context} = SessionTestHelpers.setup_session_supervisor("stop_session")
      context
    end

    test "stops a running session", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} =
        SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      assert Process.alive?(pid)

      assert :ok = SessionSupervisor.stop_session(session.id)

      # Wait for process to terminate using monitor instead of sleep
      assert :ok = SessionTestHelpers.wait_for_process_death(pid)
      refute Process.alive?(pid)
    end

    test "unregisters session from SessionRegistry", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, _} =
        SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      assert {:ok, _} = SessionRegistry.lookup(session.id)

      :ok = SessionSupervisor.stop_session(session.id)

      assert {:error, :not_found} = SessionRegistry.lookup(session.id)
    end

    test "removes process from SessionProcessRegistry", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} =
        SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      assert [{_, _}] = Registry.lookup(JidoCode.SessionProcessRegistry, {:session, session.id})

      :ok = SessionSupervisor.stop_session(session.id)

      # Wait for process to terminate and Registry entry to be cleaned up
      assert :ok = SessionTestHelpers.wait_for_process_death(pid)

      assert :ok =
               SessionTestHelpers.wait_for_registry_cleanup(
                 JidoCode.SessionProcessRegistry,
                 {:session, session.id}
               )

      assert [] = Registry.lookup(JidoCode.SessionProcessRegistry, {:session, session.id})
    end

    test "decrements DynamicSupervisor child count", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, _} =
        SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      assert DynamicSupervisor.count_children(SessionSupervisor).active == 1

      :ok = SessionSupervisor.stop_session(session.id)

      assert DynamicSupervisor.count_children(SessionSupervisor).active == 0
    end

    test "returns :error for non-existent session" do
      assert {:error, :not_found} = SessionSupervisor.stop_session("non-existent-id")
    end

    test "can stop multiple sessions", %{tmp_dir: tmp_dir} do
      dir1 = Path.join(tmp_dir, "proj1")
      dir2 = Path.join(tmp_dir, "proj2")
      File.mkdir_p!(dir1)
      File.mkdir_p!(dir2)

      {:ok, s1} = Session.new(project_path: dir1)
      {:ok, s2} = Session.new(project_path: dir2)

      {:ok, _} = SessionSupervisor.start_session(s1, supervisor_module: SessionSupervisorStub)
      {:ok, _} = SessionSupervisor.start_session(s2, supervisor_module: SessionSupervisorStub)

      assert DynamicSupervisor.count_children(SessionSupervisor).active == 2
      assert SessionRegistry.count() == 2

      :ok = SessionSupervisor.stop_session(s1.id)

      assert DynamicSupervisor.count_children(SessionSupervisor).active == 1
      assert SessionRegistry.count() == 1

      :ok = SessionSupervisor.stop_session(s2.id)

      assert DynamicSupervisor.count_children(SessionSupervisor).active == 0
      assert SessionRegistry.count() == 0
    end
  end

  # ============================================================================
  # Auto-Save on Close Tests (Task 6.2.2)
  # ============================================================================

  describe "stop_session/1 auto-save" do
    setup do
      {:ok, context} = SessionTestHelpers.setup_session_supervisor("stop_session_autosave")
      context
    end

    test "attempts to save session before stopping", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} =
        SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      # Capture log to verify save was attempted
      import ExUnit.CaptureLog

      log =
        capture_log(fn ->
          # Stop the session - should attempt auto-save
          :ok = SessionSupervisor.stop_session(session.id)
        end)

      # Verify save was attempted (warning logged since State process doesn't exist in stub)
      assert log =~ "Failed to save session #{session.id}"

      # Verify process is stopped
      assert :ok = SessionTestHelpers.wait_for_process_death(pid)
      refute Process.alive?(pid)
    end

    test "stop completes successfully even when save fails", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} =
        SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      # Stop should complete even though save will fail (no State process in stub)
      assert :ok = SessionSupervisor.stop_session(session.id)

      # Verify process is stopped
      assert :ok = SessionTestHelpers.wait_for_process_death(pid)
      refute Process.alive?(pid)

      # Session should be unregistered
      assert {:error, :not_found} = SessionRegistry.lookup(session.id)
    end

    test "session close continues even if save fails (non-existent session)", %{tmp_dir: tmp_dir} do
      # This test verifies that if the session state is already gone
      # (edge case), the stop still completes successfully

      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} =
        SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      # Manually stop the state process to simulate state being gone
      case Registry.lookup(JidoCode.SessionProcessRegistry, {:state, session.id}) do
        [{state_pid, _}] ->
          Process.exit(state_pid, :kill)
          # Wait for it to die
          SessionTestHelpers.wait_for_process_death(state_pid)

        [] ->
          :ok
      end

      # Stop should still work even though save will fail
      assert :ok = SessionSupervisor.stop_session(session.id)

      # Verify process is stopped
      assert :ok = SessionTestHelpers.wait_for_process_death(pid)
      refute Process.alive?(pid)

      # Session file should not exist since save failed
      session_file = JidoCode.Session.Persistence.session_file(session.id)
      refute File.exists?(session_file)
    end
  end

  # ============================================================================
  # Session Process Lookup Tests (Task 1.3.3)
  # ============================================================================

  describe "find_session_pid/1" do
    setup do
      {:ok, context} = SessionTestHelpers.setup_session_supervisor("find_session")
      context
    end

    test "finds registered session pid", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, expected_pid} =
        SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      assert {:ok, pid} = SessionSupervisor.find_session_pid(session.id)
      assert pid == expected_pid
    end

    test "returns error for unknown session" do
      assert {:error, :not_found} = SessionSupervisor.find_session_pid("unknown-session-id")
    end

    test "returns error after session is stopped", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} =
        SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      :ok = SessionSupervisor.stop_session(session.id)

      # Wait for Registry cleanup
      assert :ok = SessionTestHelpers.wait_for_process_death(pid)

      assert :ok =
               SessionTestHelpers.wait_for_registry_cleanup(
                 JidoCode.SessionProcessRegistry,
                 {:session, session.id}
               )

      assert {:error, :not_found} = SessionSupervisor.find_session_pid(session.id)
    end
  end

  describe "list_session_pids/0" do
    setup do
      {:ok, context} = SessionTestHelpers.setup_session_supervisor("list_session")
      context
    end

    test "returns empty list when no sessions running" do
      assert SessionSupervisor.list_session_pids() == []
    end

    test "returns pids for running sessions", %{tmp_dir: tmp_dir} do
      dir1 = Path.join(tmp_dir, "proj1")
      dir2 = Path.join(tmp_dir, "proj2")
      File.mkdir_p!(dir1)
      File.mkdir_p!(dir2)

      {:ok, s1} = Session.new(project_path: dir1)
      {:ok, s2} = Session.new(project_path: dir2)

      {:ok, pid1} = SessionSupervisor.start_session(s1, supervisor_module: SessionSupervisorStub)
      {:ok, pid2} = SessionSupervisor.start_session(s2, supervisor_module: SessionSupervisorStub)

      pids = SessionSupervisor.list_session_pids()

      assert length(pids) == 2
      assert pid1 in pids
      assert pid2 in pids
    end

    test "reflects stopped sessions", %{tmp_dir: tmp_dir} do
      dir1 = Path.join(tmp_dir, "proj1")
      dir2 = Path.join(tmp_dir, "proj2")
      File.mkdir_p!(dir1)
      File.mkdir_p!(dir2)

      {:ok, s1} = Session.new(project_path: dir1)
      {:ok, s2} = Session.new(project_path: dir2)

      {:ok, _pid1} = SessionSupervisor.start_session(s1, supervisor_module: SessionSupervisorStub)
      {:ok, pid2} = SessionSupervisor.start_session(s2, supervisor_module: SessionSupervisorStub)

      assert length(SessionSupervisor.list_session_pids()) == 2

      :ok = SessionSupervisor.stop_session(s1.id)

      pids = SessionSupervisor.list_session_pids()
      assert length(pids) == 1
      assert pid2 in pids
    end
  end

  describe "session_running?/1" do
    setup do
      {:ok, context} = SessionTestHelpers.setup_session_supervisor("session_running")
      context
    end

    test "returns true for running session", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, _pid} =
        SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      assert SessionSupervisor.session_running?(session.id) == true
    end

    test "returns false for unknown session" do
      assert SessionSupervisor.session_running?("unknown-session-id") == false
    end

    test "returns false after session is stopped", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, _pid} =
        SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      assert SessionSupervisor.session_running?(session.id) == true

      :ok = SessionSupervisor.stop_session(session.id)

      assert SessionSupervisor.session_running?(session.id) == false
    end
  end

  # ============================================================================
  # Session Creation Convenience Tests (Task 1.3.4)
  # ============================================================================

  describe "create_session/1" do
    setup do
      {:ok, context} = SessionTestHelpers.setup_session_supervisor("create_session")
      context
    end

    test "creates and starts a session", %{tmp_dir: tmp_dir} do
      assert {:ok, session} =
               SessionSupervisor.create_session(
                 project_path: tmp_dir,
                 supervisor_module: SessionSupervisorStub
               )

      assert %Session{} = session
      assert session.project_path == tmp_dir
    end

    test "returns session struct (not pid)", %{tmp_dir: tmp_dir} do
      {:ok, result} =
        SessionSupervisor.create_session(
          project_path: tmp_dir,
          supervisor_module: SessionSupervisorStub
        )

      assert %Session{} = result
      refute is_pid(result)
    end

    test "registers session in SessionRegistry", %{tmp_dir: tmp_dir} do
      {:ok, session} =
        SessionSupervisor.create_session(
          project_path: tmp_dir,
          supervisor_module: SessionSupervisorStub
        )

      assert {:ok, registered} = SessionRegistry.lookup(session.id)
      assert registered.id == session.id
    end

    test "session is running after creation", %{tmp_dir: tmp_dir} do
      {:ok, session} =
        SessionSupervisor.create_session(
          project_path: tmp_dir,
          supervisor_module: SessionSupervisorStub
        )

      assert SessionSupervisor.session_running?(session.id)
    end

    test "uses folder name as default session name", %{tmp_dir: tmp_dir} do
      {:ok, session} =
        SessionSupervisor.create_session(
          project_path: tmp_dir,
          supervisor_module: SessionSupervisorStub
        )

      assert session.name == Path.basename(tmp_dir)
    end

    test "accepts custom name option", %{tmp_dir: tmp_dir} do
      {:ok, session} =
        SessionSupervisor.create_session(
          project_path: tmp_dir,
          name: "my-custom-name",
          supervisor_module: SessionSupervisorStub
        )

      assert session.name == "my-custom-name"
    end

    test "fails for non-existent path" do
      assert {:error, :path_not_found} =
               SessionSupervisor.create_session(
                 project_path: "/nonexistent/path/that/does/not/exist",
                 supervisor_module: SessionSupervisorStub
               )
    end

    test "fails for file path (not directory)", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "a_file.txt")
      File.write!(file_path, "content")

      assert {:error, :path_not_directory} =
               SessionSupervisor.create_session(
                 project_path: file_path,
                 supervisor_module: SessionSupervisorStub
               )
    end

    test "fails with :session_limit_reached when limit exceeded", %{tmp_dir: tmp_dir} do
      # Set low limit for testing
      original = Application.get_env(:jido_code, :max_sessions)
      Application.put_env(:jido_code, :max_sessions, 2)

      on_exit(fn ->
        if original do
          Application.put_env(:jido_code, :max_sessions, original)
        else
          Application.delete_env(:jido_code, :max_sessions)
        end
      end)

      # Create 2 sessions to hit limit
      dir1 = Path.join(tmp_dir, "proj1")
      dir2 = Path.join(tmp_dir, "proj2")
      dir3 = Path.join(tmp_dir, "proj3")
      File.mkdir_p!(dir1)
      File.mkdir_p!(dir2)
      File.mkdir_p!(dir3)

      {:ok, _} =
        SessionSupervisor.create_session(
          project_path: dir1,
          supervisor_module: SessionSupervisorStub
        )

      {:ok, _} =
        SessionSupervisor.create_session(
          project_path: dir2,
          supervisor_module: SessionSupervisorStub
        )

      # Third should fail
      assert {:error, {:session_limit_reached, 2, 2}} =
               SessionSupervisor.create_session(
                 project_path: dir3,
                 supervisor_module: SessionSupervisorStub
               )
    end

    test "fails with :project_already_open for duplicate path", %{tmp_dir: tmp_dir} do
      {:ok, _} =
        SessionSupervisor.create_session(
          project_path: tmp_dir,
          supervisor_module: SessionSupervisorStub
        )

      # Same path again should fail
      assert {:error, :project_already_open} =
               SessionSupervisor.create_session(
                 project_path: tmp_dir,
                 supervisor_module: SessionSupervisorStub
               )
    end
  end
end

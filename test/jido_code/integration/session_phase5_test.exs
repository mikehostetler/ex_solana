defmodule JidoCode.Integration.SessionPhase5Test do
  @moduledoc """
  Integration tests for Phase 5 (Session Commands) components.

  These tests verify that all Phase 5 session command components work together correctly:
  - /session new command end-to-end
  - /session list command end-to-end
  - /session switch command end-to-end
  - /session close command end-to-end
  - /session rename command end-to-end
  - Command → TUI flow integration

  Tests use the Commands module directly to verify command execution
  and result handling without requiring a full TUI.

  ## Why async: false

  These tests cannot run async because they:
  1. Share the SessionSupervisor (DynamicSupervisor) - tests modify global state
  2. Use SessionRegistry which is a shared ETS table
  3. Create real sessions that need cleanup
  """
  use ExUnit.Case, async: false

  alias JidoCode.Commands
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor

  @moduletag :integration
  @moduletag :phase5

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    Process.flag(:trap_exit, true)

    # Ensure the application is started
    {:ok, _} = Application.ensure_all_started(:jido_code)

    # Wait for SessionSupervisor to be available
    wait_for_supervisor()

    # Clear any existing sessions from Registry
    SessionRegistry.clear()

    # Stop any running sessions under SessionSupervisor
    for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(SessionSupervisor) do
      DynamicSupervisor.terminate_child(SessionSupervisor, pid)
    end

    # Create temp base directory for test sessions
    tmp_base = Path.join(System.tmp_dir!(), "phase5_integration_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_base)

    # Configure valid model for session creation
    System.put_env("ANTHROPIC_API_KEY", "test-key-for-integration")

    # Clear the Settings cache so it loads fresh settings
    JidoCode.Settings.Cache.clear()

    # Create a local settings file in the tmp_base that will be used
    # when we cd to tmp_base
    settings_dir = Path.join(tmp_base, ".jido_code")
    File.mkdir_p!(settings_dir)
    settings_path = Path.join(settings_dir, "settings.json")

    settings = %{
      "version" => 1,
      "provider" => "anthropic",
      "model" => "claude-3-5-haiku-20241022"
    }

    File.write!(settings_path, Jason.encode!(settings))

    # Change to tmp_base so local settings are picked up
    original_cwd = File.cwd!()
    File.cd!(tmp_base)

    # Clear cache again after cd so it picks up new local settings
    JidoCode.Settings.Cache.clear()

    on_exit(fn ->
      # Restore CWD
      File.cd!(original_cwd)

      # Clear cache on exit
      JidoCode.Settings.Cache.clear()

      # Stop all test sessions
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

  defp create_session_via_command(path, name \\ nil) do
    opts = %{path: path, name: name}
    Commands.execute_session({:new, opts}, %{})
  end

  defp build_model_with_sessions(sessions) do
    session_map =
      sessions
      |> Enum.with_index(1)
      |> Enum.map(fn {session, _idx} -> {session.id, session} end)
      |> Map.new()

    session_order = Enum.map(sessions, & &1.id)

    %{
      sessions: session_map,
      session_order: session_order,
      active_session_id: List.first(session_order)
    }
  end

  # ============================================================================
  # 5.8.1 Session New Command Integration Tests
  # ============================================================================

  describe "5.8.1 Session New Command Integration" do
    test "/session new /path creates session and returns add_session action", %{
      tmp_base: tmp_base
    } do
      project_path = create_test_dir(tmp_base, "new_project")

      result = create_session_via_command(project_path)

      assert {:session_action, {:add_session, session}} = result
      assert session.project_path == project_path
      assert session.name == "new_project"
      assert is_binary(session.id)

      # Cleanup
      SessionSupervisor.stop_session(session.id)
    end

    test "/session new with nil path uses CWD", %{tmp_base: _tmp_base} do
      # Use current working directory
      cwd = File.cwd!()

      result = create_session_via_command(nil, "cwd-session")

      case result do
        {:session_action, {:add_session, session}} ->
          assert session.project_path == cwd
          assert session.name == "cwd-session"
          SessionSupervisor.stop_session(session.id)

        {:error, message} ->
          # May fail if session already exists for CWD
          assert message =~ "already open" or message =~ "Failed"
      end
    end

    test "/session new --name=CustomName uses custom name", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "another_project")

      result = create_session_via_command(project_path, "CustomName")

      assert {:session_action, {:add_session, session}} = result
      assert session.name == "CustomName"
      assert session.project_path == project_path

      # Cleanup
      SessionSupervisor.stop_session(session.id)
    end

    test "/session new at limit returns error", %{tmp_base: tmp_base} do
      # Create 10 sessions to hit the limit
      sessions =
        for i <- 1..10 do
          project_path = create_test_dir(tmp_base, "limit_project_#{i}")
          {:session_action, {:add_session, session}} = create_session_via_command(project_path)
          session
        end

      # Try to create 11th session
      project_path = create_test_dir(tmp_base, "limit_project_11")
      result = create_session_via_command(project_path)

      assert {:error, message} = result
      assert message =~ "Maximum 10 sessions"

      # Cleanup
      for session <- sessions do
        SessionSupervisor.stop_session(session.id)
      end
    end

    test "/session new with duplicate path returns error", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "duplicate_project")

      # Create first session
      {:session_action, {:add_session, session1}} = create_session_via_command(project_path)

      # Try to create duplicate
      result = create_session_via_command(project_path)

      assert {:error, message} = result
      assert message =~ "already open"

      # Cleanup
      SessionSupervisor.stop_session(session1.id)
    end

    test "/session new with non-existent path returns error", %{tmp_base: tmp_base} do
      non_existent_path = Path.join(tmp_base, "does_not_exist_xyz")

      result = create_session_via_command(non_existent_path)

      assert {:error, message} = result
      assert message =~ "does not exist"
    end

    test "/session new with file path (not directory) returns error", %{tmp_base: tmp_base} do
      file_path = Path.join(tmp_base, "a_file.txt")
      File.write!(file_path, "content")

      result = create_session_via_command(file_path)

      assert {:error, message} = result
      assert message =~ "not a directory"
    end
  end

  # ============================================================================
  # 5.8.2 Session List Command Integration Tests
  # ============================================================================

  describe "5.8.2 Session List Command Integration" do
    test "/session list with multiple sessions shows all with indices", %{tmp_base: tmp_base} do
      # Create 3 sessions
      sessions =
        for i <- 1..3 do
          project_path = create_test_dir(tmp_base, "list_project_#{i}")
          {:session_action, {:add_session, session}} = create_session_via_command(project_path)
          session
        end

      model = build_model_with_sessions(sessions)
      result = Commands.execute_session(:list, model)

      assert {:ok, list_output} = result
      assert list_output =~ "1."
      assert list_output =~ "2."
      assert list_output =~ "3."
      assert list_output =~ "list_project_1"
      assert list_output =~ "list_project_2"
      assert list_output =~ "list_project_3"

      # Cleanup
      for session <- sessions do
        SessionSupervisor.stop_session(session.id)
      end
    end

    test "/session list marks active session with asterisk", %{tmp_base: tmp_base} do
      # Create 2 sessions
      project_path1 = create_test_dir(tmp_base, "active_project")
      project_path2 = create_test_dir(tmp_base, "other_project")

      {:session_action, {:add_session, session1}} = create_session_via_command(project_path1)
      {:session_action, {:add_session, session2}} = create_session_via_command(project_path2)

      # Set first session as active
      model = %{
        sessions: %{session1.id => session1, session2.id => session2},
        session_order: [session1.id, session2.id],
        active_session_id: session1.id
      }

      result = Commands.execute_session(:list, model)

      assert {:ok, list_output} = result
      # Active session should be marked with asterisk
      assert list_output =~ "*"
      assert list_output =~ "active_project"

      # Cleanup
      SessionSupervisor.stop_session(session1.id)
      SessionSupervisor.stop_session(session2.id)
    end

    test "/session list with no sessions shows helpful message" do
      model = %{sessions: %{}, session_order: [], active_session_id: nil}
      result = Commands.execute_session(:list, model)

      assert {:ok, message} = result
      assert message =~ "No sessions"
      assert message =~ "/session new"
    end
  end

  # ============================================================================
  # 5.8.3 Session Switch Command Integration Tests
  # ============================================================================

  describe "5.8.3 Session Switch Command Integration" do
    test "/session switch by index returns switch action", %{tmp_base: tmp_base} do
      # Create 2 sessions
      project_path1 = create_test_dir(tmp_base, "switch_project_1")
      project_path2 = create_test_dir(tmp_base, "switch_project_2")

      {:session_action, {:add_session, session1}} = create_session_via_command(project_path1)
      {:session_action, {:add_session, session2}} = create_session_via_command(project_path2)

      model = %{
        sessions: %{session1.id => session1, session2.id => session2},
        session_order: [session1.id, session2.id],
        active_session_id: session1.id
      }

      # Switch to session 2
      result = Commands.execute_session({:switch, "2"}, model)

      assert {:session_action, {:switch_session, session_id}} = result
      assert session_id == session2.id

      # Cleanup
      SessionSupervisor.stop_session(session1.id)
      SessionSupervisor.stop_session(session2.id)
    end

    test "/session switch by name returns switch action", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "named_project")

      {:session_action, {:add_session, session}} =
        create_session_via_command(project_path, "MyProject")

      model = build_model_with_sessions([session])

      result = Commands.execute_session({:switch, "MyProject"}, model)

      assert {:session_action, {:switch_session, session_id}} = result
      assert session_id == session.id

      # Cleanup
      SessionSupervisor.stop_session(session.id)
    end

    test "/session switch with invalid index returns error", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "single_project")
      {:session_action, {:add_session, session}} = create_session_via_command(project_path)

      model = build_model_with_sessions([session])

      result = Commands.execute_session({:switch, "99"}, model)

      assert {:error, message} = result
      assert message =~ "not found"

      # Cleanup
      SessionSupervisor.stop_session(session.id)
    end

    test "/session switch with partial name match works", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "partial_match_project")
      {:session_action, {:add_session, session}} = create_session_via_command(project_path)

      model = build_model_with_sessions([session])

      # "partial" should match "partial_match_project"
      result = Commands.execute_session({:switch, "partial"}, model)

      assert {:session_action, {:switch_session, session_id}} = result
      assert session_id == session.id

      # Cleanup
      SessionSupervisor.stop_session(session.id)
    end

    test "/session switch with ambiguous name returns error", %{tmp_base: tmp_base} do
      project_path1 = create_test_dir(tmp_base, "project_alpha")
      project_path2 = create_test_dir(tmp_base, "project_beta")

      {:session_action, {:add_session, session1}} = create_session_via_command(project_path1)
      {:session_action, {:add_session, session2}} = create_session_via_command(project_path2)

      model = build_model_with_sessions([session1, session2])

      # "project" matches both
      result = Commands.execute_session({:switch, "project"}, model)

      assert {:error, message} = result
      assert message =~ "Ambiguous"

      # Cleanup
      SessionSupervisor.stop_session(session1.id)
      SessionSupervisor.stop_session(session2.id)
    end
  end

  # ============================================================================
  # 5.8.4 Session Close Command Integration Tests
  # ============================================================================

  describe "5.8.4 Session Close Command Integration" do
    test "/session close returns close action for active session", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "close_project")
      {:session_action, {:add_session, session}} = create_session_via_command(project_path)

      model = build_model_with_sessions([session])

      result = Commands.execute_session({:close, nil}, model)

      assert {:session_action, {:close_session, session_id, session_name}} = result
      assert session_id == session.id
      assert session_name == "close_project"

      # Cleanup
      SessionSupervisor.stop_session(session.id)
    end

    test "/session close by index returns close action", %{tmp_base: tmp_base} do
      project_path1 = create_test_dir(tmp_base, "close_project_1")
      project_path2 = create_test_dir(tmp_base, "close_project_2")

      {:session_action, {:add_session, session1}} = create_session_via_command(project_path1)
      {:session_action, {:add_session, session2}} = create_session_via_command(project_path2)

      model = build_model_with_sessions([session1, session2])

      # Close session 2
      result = Commands.execute_session({:close, "2"}, model)

      assert {:session_action, {:close_session, session_id, _name}} = result
      assert session_id == session2.id

      # Cleanup
      SessionSupervisor.stop_session(session1.id)
      SessionSupervisor.stop_session(session2.id)
    end

    test "/session close with no sessions returns error" do
      model = %{sessions: %{}, session_order: [], active_session_id: nil}

      result = Commands.execute_session({:close, nil}, model)

      assert {:error, message} = result
      assert message =~ "No sessions to close"
    end

    test "/session close with no active session returns error", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "no_active_project")
      {:session_action, {:add_session, session}} = create_session_via_command(project_path)

      model = %{
        sessions: %{session.id => session},
        session_order: [session.id],
        active_session_id: nil
      }

      result = Commands.execute_session({:close, nil}, model)

      assert {:error, message} = result
      assert message =~ "No active session"

      # Cleanup
      SessionSupervisor.stop_session(session.id)
    end
  end

  # ============================================================================
  # 5.8.5 Session Rename Command Integration Tests
  # ============================================================================

  describe "5.8.5 Session Rename Command Integration" do
    test "/session rename returns rename action", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "rename_project")
      {:session_action, {:add_session, session}} = create_session_via_command(project_path)

      model = build_model_with_sessions([session])

      result = Commands.execute_session({:rename, "NewName"}, model)

      assert {:session_action, {:rename_session, session_id, new_name}} = result
      assert session_id == session.id
      assert new_name == "NewName"

      # Cleanup
      SessionSupervisor.stop_session(session.id)
    end

    test "/session rename with empty name returns error", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "empty_rename_project")
      {:session_action, {:add_session, session}} = create_session_via_command(project_path)

      model = build_model_with_sessions([session])

      result = Commands.execute_session({:rename, ""}, model)

      assert {:error, message} = result
      assert message =~ "cannot be empty"

      # Cleanup
      SessionSupervisor.stop_session(session.id)
    end

    test "/session rename with no active session returns error" do
      model = %{sessions: %{}, session_order: [], active_session_id: nil}

      result = Commands.execute_session({:rename, "NewName"}, model)

      assert {:error, message} = result
      assert message =~ "No active session"
    end

    test "/session rename with too-long name returns error", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "long_rename_project")
      {:session_action, {:add_session, session}} = create_session_via_command(project_path)

      model = build_model_with_sessions([session])

      long_name = String.duplicate("a", 51)
      result = Commands.execute_session({:rename, long_name}, model)

      assert {:error, message} = result
      assert message =~ "too long"

      # Cleanup
      SessionSupervisor.stop_session(session.id)
    end
  end

  # ============================================================================
  # 5.8.6 Command-TUI Flow Integration Tests
  # ============================================================================

  describe "5.8.6 Command-TUI Flow Integration" do
    test "Commands.execute parses and returns session commands", %{tmp_base: _tmp_base} do
      # Test that execute properly parses session commands
      result = Commands.execute("/session", %{})
      assert {:session, :help} = result

      result = Commands.execute("/session list", %{})
      assert {:session, :list} = result

      result = Commands.execute("/session new", %{})
      assert {:session, {:new, _opts}} = result

      result = Commands.execute("/session unknown", %{})
      assert {:session, :help} = result
    end

    test "session actions have correct structure for TUI handling", %{tmp_base: tmp_base} do
      # Verify action structures match what TUI expects
      project_path = create_test_dir(tmp_base, "tui_flow_project")

      # Test add_session action
      result = create_session_via_command(project_path)
      assert {:session_action, {:add_session, %{id: _, name: _, project_path: _}}} = result

      {:session_action, {:add_session, session}} = result

      model = build_model_with_sessions([session])

      # Test switch_session action
      result = Commands.execute_session({:switch, "1"}, model)
      assert {:session_action, {:switch_session, _session_id}} = result

      # Test close_session action
      result = Commands.execute_session({:close, nil}, model)
      assert {:session_action, {:close_session, _session_id, _name}} = result

      # Test rename_session action
      result = Commands.execute_session({:rename, "Renamed"}, model)
      assert {:session_action, {:rename_session, _session_id, "Renamed"}} = result

      # Cleanup
      SessionSupervisor.stop_session(session.id)
    end
  end
end

defmodule JidoCode.Integration.SessionPhase2Test do
  @moduledoc """
  Integration tests for Phase 2 (Per-Session Manager and Security) components.

  These tests verify that all Phase 2 components work together correctly:
  - Session.Manager for security sandbox and file operations
  - Session.State for conversation and UI state
  - Session.Settings for per-project configuration
  - HandlerHelpers for session-aware path resolution

  Tests use the application's infrastructure (already running) and clean up
  after themselves.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias JidoCode.Session
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor
  alias JidoCode.Tools.HandlerHelpers

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    # Ensure the application is started
    {:ok, _} = Application.ensure_all_started(:jido_code)

    # Suppress deprecation warnings for tests
    Application.put_env(:jido_code, :suppress_global_manager_warnings, true)

    # Wait for SessionSupervisor to be available
    wait_for_supervisor()

    # Clear any existing test sessions from Registry
    SessionRegistry.clear()

    # Stop any running sessions under SessionSupervisor
    for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(SessionSupervisor) do
      DynamicSupervisor.terminate_child(SessionSupervisor, pid)
    end

    # Create temp base directory for test sessions
    tmp_base = Path.join(System.tmp_dir!(), "phase2_integration_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_base)

    on_exit(fn ->
      # Restore deprecation warnings
      Application.delete_env(:jido_code, :suppress_global_manager_warnings)

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

  defp create_settings_file(project_path, settings) do
    settings_dir = Path.join(project_path, ".jido_code")
    File.mkdir_p!(settings_dir)
    settings_path = Path.join(settings_dir, "settings.json")
    File.write!(settings_path, Jason.encode!(settings))
    settings_path
  end

  # ============================================================================
  # 2.5.1 Manager-State Integration Tests
  # ============================================================================

  describe "2.5.1 manager-state integration" do
    test "create session -> Manager and State both start -> both accessible via helpers",
         %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "manager_state_both")

      # Create session
      {:ok, session} = SessionSupervisor.create_session(project_path: path)

      # Verify Manager is accessible
      assert {:ok, manager_pid} = Session.Supervisor.get_manager(session.id)
      assert Process.alive?(manager_pid)

      # Verify State is accessible
      assert {:ok, state_pid} = Session.Supervisor.get_state(session.id)
      assert Process.alive?(state_pid)

      # Verify Manager provides project_root
      assert {:ok, ^path} = Session.Manager.project_root(session.id)

      # Verify State provides empty initial state
      assert {:ok, state} = Session.State.get_state(session.id)
      assert state.session_id == session.id
      assert state.messages == []
      assert state.is_streaming == false
    end

    test "Manager validates path -> can be used with State tracking", %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "validate_and_track")

      {:ok, session} = SessionSupervisor.create_session(project_path: path)

      # Validate a path via Manager
      {:ok, resolved_path} = Session.Manager.validate_path(session.id, "test.txt")
      assert resolved_path == Path.join(path, "test.txt")

      # Track a tool call in State
      tool_call = %{
        id: "tc_#{:rand.uniform(100_000)}",
        name: "validate_path",
        args: %{"path" => "test.txt"},
        status: :completed,
        result: resolved_path,
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      }

      assert {:ok, _state} = Session.State.add_tool_call(session.id, tool_call)

      # Verify tool call was tracked
      {:ok, state} = Session.State.get_state(session.id)
      assert length(state.tool_calls) == 1
      assert hd(state.tool_calls).name == "validate_path"
    end

    test "Manager Lua execution -> State tracks tool call", %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "lua_and_state")

      {:ok, session} = SessionSupervisor.create_session(project_path: path)

      # Execute Lua via Manager
      {:ok, result} = Session.Manager.run_lua(session.id, "return 1 + 2")
      assert result == [3.0]

      # Track as tool call in State
      tool_call = %{
        id: "tc_lua_#{:rand.uniform(100_000)}",
        name: "run_lua",
        args: %{"script" => "return 1 + 2"},
        status: :completed,
        result: result,
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      }

      assert {:ok, _state} = Session.State.add_tool_call(session.id, tool_call)

      {:ok, state} = Session.State.get_state(session.id)
      assert length(state.tool_calls) == 1
      lua_call = hd(state.tool_calls)
      assert lua_call.name == "run_lua"
      assert lua_call.result == [3.0]
    end

    test "session restart -> Manager and State both restart with correct context",
         %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "restart_both")

      {:ok, session} = SessionSupervisor.create_session(project_path: path)

      # Get original pids
      {:ok, original_manager} = Session.Supervisor.get_manager(session.id)
      {:ok, original_state} = Session.Supervisor.get_state(session.id)

      # Add some state before restart
      message = %{
        id: "msg_#{:rand.uniform(100_000)}",
        role: :user,
        content: "test message",
        timestamp: DateTime.utc_now()
      }

      {:ok, _state} = Session.State.append_message(session.id, message)

      # Kill Manager to trigger restart (one_for_all strategy)
      Process.exit(original_manager, :kill)
      Process.sleep(100)

      # Verify new processes started
      {:ok, new_manager} = Session.Supervisor.get_manager(session.id)
      {:ok, new_state} = Session.Supervisor.get_state(session.id)

      assert new_manager != original_manager
      assert new_state != original_state
      assert Process.alive?(new_manager)
      assert Process.alive?(new_state)

      # Verify Manager still has correct project_root
      assert {:ok, ^path} = Session.Manager.project_root(session.id)

      # Note: State is reset after restart (messages lost)
      # This is expected behavior for :one_for_all strategy
      {:ok, state} = Session.State.get_state(session.id)
      assert state.session_id == session.id
    end

    test "HandlerHelpers.get_project_root uses session context", %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "helpers_session")

      {:ok, session} = SessionSupervisor.create_session(project_path: path)

      # Use session_id in context
      context = %{session_id: session.id}
      assert {:ok, ^path} = HandlerHelpers.get_project_root(context)
    end

    test "HandlerHelpers.validate_path uses session context", %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "helpers_validate")

      {:ok, session} = SessionSupervisor.create_session(project_path: path)

      # Use session_id in context
      context = %{session_id: session.id}
      {:ok, resolved} = HandlerHelpers.validate_path("src/file.ex", context)
      assert resolved == Path.join(path, "src/file.ex")

      # Path traversal should be rejected
      assert {:error, :path_escapes_boundary} =
               HandlerHelpers.validate_path("../../../etc/passwd", context)
    end
  end

  # ============================================================================
  # 2.5.2 Settings Integration Tests
  # ============================================================================

  describe "2.5.2 settings integration" do
    test "create session -> Settings loaded from project path", %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "settings_load")

      # Create local settings
      local_settings = %{
        "provider" => "openai",
        "model" => "gpt-4o",
        "custom_key" => "local_value"
      }

      create_settings_file(path, local_settings)

      # Load settings using Session.Settings
      loaded = Session.Settings.load(path)

      assert loaded["provider"] == "openai"
      assert loaded["model"] == "gpt-4o"
      assert loaded["custom_key"] == "local_value"
    end

    test "local settings override global settings", %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "settings_override")

      # Create local settings that override global
      local_settings = %{"provider" => "local_provider", "temperature" => 0.9}
      create_settings_file(path, local_settings)

      # Load merged settings
      loaded = Session.Settings.load(path)

      # Local values should override global
      assert loaded["provider"] == "local_provider"
      assert loaded["temperature"] == 0.9
    end

    test "missing local settings -> falls back to global only", %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "settings_fallback")

      # No local settings file created

      # Load settings - should only have global settings
      loaded = Session.Settings.load(path)

      # Should still return a map (possibly empty if no global either)
      assert is_map(loaded)
    end

    test "save settings -> reload -> settings persisted", %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "settings_persist")

      # Save settings
      settings_to_save = %{"provider" => "saved_provider", "model" => "saved_model"}
      assert :ok = Session.Settings.save(path, settings_to_save)

      # Reload settings
      loaded = Session.Settings.load(path)

      assert loaded["provider"] == "saved_provider"
      assert loaded["model"] == "saved_model"
    end

    test "session can use settings for configuration", %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "settings_session_config")

      # Create local settings
      local_settings = %{"provider" => "test_provider", "model" => "test_model"}
      create_settings_file(path, local_settings)

      # Load settings
      config = Session.Settings.load(path)

      # Create session with loaded config
      {:ok, session} = SessionSupervisor.create_session(project_path: path, config: config)

      assert session.config["provider"] == "test_provider"
      assert session.config["model"] == "test_model"
    end
  end

  # ============================================================================
  # 2.5.3 Multi-Session Isolation Tests
  # ============================================================================

  describe "2.5.3 multi-session isolation" do
    test "2 sessions -> each has own Manager with different project_root", %{tmp_base: tmp_base} do
      path1 = create_test_dir(tmp_base, "isolation_1")
      path2 = create_test_dir(tmp_base, "isolation_2")

      {:ok, session1} = SessionSupervisor.create_session(project_path: path1)
      {:ok, session2} = SessionSupervisor.create_session(project_path: path2)

      # Verify different project roots
      assert {:ok, ^path1} = Session.Manager.project_root(session1.id)
      assert {:ok, ^path2} = Session.Manager.project_root(session2.id)

      # Verify different manager pids
      {:ok, manager1} = Session.Supervisor.get_manager(session1.id)
      {:ok, manager2} = Session.Supervisor.get_manager(session2.id)
      assert manager1 != manager2
    end

    test "2 sessions -> each has own State with independent messages", %{tmp_base: tmp_base} do
      path1 = create_test_dir(tmp_base, "messages_1")
      path2 = create_test_dir(tmp_base, "messages_2")

      {:ok, session1} = SessionSupervisor.create_session(project_path: path1)
      {:ok, session2} = SessionSupervisor.create_session(project_path: path2)

      # Add message to session1
      message1 = %{
        id: "msg_1",
        role: :user,
        content: "message for session 1",
        timestamp: DateTime.utc_now()
      }

      {:ok, _} = Session.State.append_message(session1.id, message1)

      # Add different message to session2
      message2 = %{
        id: "msg_2",
        role: :user,
        content: "message for session 2",
        timestamp: DateTime.utc_now()
      }

      {:ok, _} = Session.State.append_message(session2.id, message2)

      # Verify isolation
      {:ok, state1} = Session.State.get_state(session1.id)
      {:ok, state2} = Session.State.get_state(session2.id)

      assert length(state1.messages) == 1
      assert length(state2.messages) == 1
      assert hd(state1.messages).content == "message for session 1"
      assert hd(state2.messages).content == "message for session 2"
    end

    test "2 sessions -> each has own Lua sandbox (isolated state)", %{tmp_base: tmp_base} do
      path1 = create_test_dir(tmp_base, "lua_1")
      path2 = create_test_dir(tmp_base, "lua_2")

      {:ok, session1} = SessionSupervisor.create_session(project_path: path1)
      {:ok, session2} = SessionSupervisor.create_session(project_path: path2)

      # Set variable in session1's Lua
      {:ok, _} = Session.Manager.run_lua(session1.id, "session_var = 'session1_value'")

      # Set different variable in session2's Lua
      {:ok, _} = Session.Manager.run_lua(session2.id, "session_var = 'session2_value'")

      # Read from session1 - should have session1's value
      {:ok, [result1]} = Session.Manager.run_lua(session1.id, "return session_var")
      assert result1 == "session1_value"

      # Read from session2 - should have session2's value
      {:ok, [result2]} = Session.Manager.run_lua(session2.id, "return session_var")
      assert result2 == "session2_value"
    end

    test "streaming in session A -> session B State unaffected", %{tmp_base: tmp_base} do
      path1 = create_test_dir(tmp_base, "streaming_1")
      path2 = create_test_dir(tmp_base, "streaming_2")

      {:ok, session1} = SessionSupervisor.create_session(project_path: path1)
      {:ok, session2} = SessionSupervisor.create_session(project_path: path2)

      # Start streaming in session1
      {:ok, _} = Session.State.start_streaming(session1.id, "stream_msg_1")
      # update_streaming returns :ok (cast)
      :ok = Session.State.update_streaming(session1.id, "chunk1")
      :ok = Session.State.update_streaming(session1.id, "chunk2")
      # Small delay to allow cast to process
      Process.sleep(10)

      # Verify session1 is streaming
      {:ok, state1} = Session.State.get_state(session1.id)
      assert state1.is_streaming == true
      assert state1.streaming_message == "chunk1chunk2"

      # Verify session2 is NOT streaming
      {:ok, state2} = Session.State.get_state(session2.id)
      assert state2.is_streaming == false
      assert state2.streaming_message == nil

      # End streaming in session1
      {:ok, _message} = Session.State.end_streaming(session1.id)

      {:ok, state1_after} = Session.State.get_state(session1.id)
      assert state1_after.is_streaming == false
      assert length(state1_after.messages) == 1
    end

    test "path validation in session A -> uses session A's project_root only",
         %{tmp_base: tmp_base} do
      path1 = create_test_dir(tmp_base, "validate_1")
      path2 = create_test_dir(tmp_base, "validate_2")

      {:ok, session1} = SessionSupervisor.create_session(project_path: path1)
      {:ok, session2} = SessionSupervisor.create_session(project_path: path2)

      # Validate path in session1
      {:ok, resolved1} = Session.Manager.validate_path(session1.id, "file.txt")
      assert resolved1 == Path.join(path1, "file.txt")

      # Validate same relative path in session2
      {:ok, resolved2} = Session.Manager.validate_path(session2.id, "file.txt")
      assert resolved2 == Path.join(path2, "file.txt")

      # Paths should be different
      assert resolved1 != resolved2
    end

    test "file operations isolated between sessions", %{tmp_base: tmp_base} do
      path1 = create_test_dir(tmp_base, "files_1")
      path2 = create_test_dir(tmp_base, "files_2")

      {:ok, session1} = SessionSupervisor.create_session(project_path: path1)
      {:ok, session2} = SessionSupervisor.create_session(project_path: path2)

      # Write file in session1
      :ok = Session.Manager.write_file(session1.id, "test.txt", "session1 content")

      # Write same filename in session2
      :ok = Session.Manager.write_file(session2.id, "test.txt", "session2 content")

      # Read from session1 - should have session1's content
      {:ok, content1} = Session.Manager.read_file(session1.id, "test.txt")
      assert content1 == "session1 content"

      # Read from session2 - should have session2's content
      {:ok, content2} = Session.Manager.read_file(session2.id, "test.txt")
      assert content2 == "session2 content"
    end
  end

  # ============================================================================
  # 2.5.4 Backwards Compatibility Tests
  # ============================================================================

  describe "2.5.4 backwards compatibility" do
    test "HandlerHelpers.get_project_root with session_id -> uses Session.Manager",
         %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "compat_session")

      {:ok, session} = SessionSupervisor.create_session(project_path: path)

      # With session_id, should use Session.Manager
      context = %{session_id: session.id}
      {:ok, result} = HandlerHelpers.get_project_root(context)
      assert result == path
    end

    test "HandlerHelpers.get_project_root without session_id -> uses global manager" do
      # Without session_id, should fall back to global manager
      context = %{}

      # Should return some path (global manager's project root)
      {:ok, result} = HandlerHelpers.get_project_root(context)
      assert is_binary(result)
    end

    test "HandlerHelpers.get_project_root prefers session_id over project_root",
         %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "compat_prefer")

      {:ok, session} = SessionSupervisor.create_session(project_path: path)

      # Context has both session_id and project_root
      context = %{session_id: session.id, project_root: "/different/path"}

      # Should use session_id (returns path from session)
      {:ok, result} = HandlerHelpers.get_project_root(context)
      assert result == path
    end

    test "HandlerHelpers.validate_path with session_id -> uses Session.Manager",
         %{tmp_base: tmp_base} do
      path = create_test_dir(tmp_base, "compat_validate")

      {:ok, session} = SessionSupervisor.create_session(project_path: path)

      context = %{session_id: session.id}
      {:ok, resolved} = HandlerHelpers.validate_path("src/file.ex", context)
      assert resolved == Path.join(path, "src/file.ex")
    end

    test "HandlerHelpers.validate_path without session_id -> uses global manager" do
      context = %{}

      # Should use global manager's validate_path
      {:ok, result} = HandlerHelpers.validate_path("test.txt", context)
      assert is_binary(result)
    end

    test "invalid session_id returns :invalid_session_id error" do
      context = %{session_id: "not-a-uuid"}

      assert {:error, :invalid_session_id} = HandlerHelpers.get_project_root(context)
      assert {:error, :invalid_session_id} = HandlerHelpers.validate_path("file.txt", context)
    end

    test "unknown session_id (valid UUID) returns :not_found error" do
      context = %{session_id: "550e8400-e29b-41d4-a716-446655440000"}

      assert {:error, :not_found} = HandlerHelpers.get_project_root(context)
      assert {:error, :not_found} = HandlerHelpers.validate_path("file.txt", context)
    end

    test "deprecation warning logged when using global fallback" do
      # Enable deprecation warnings temporarily
      Application.put_env(:jido_code, :suppress_global_manager_warnings, false)

      log =
        capture_log(fn ->
          HandlerHelpers.get_project_root(%{})
        end)

      assert log =~ "global Tools.Manager"

      # Re-suppress
      Application.put_env(:jido_code, :suppress_global_manager_warnings, true)
    end
  end
end

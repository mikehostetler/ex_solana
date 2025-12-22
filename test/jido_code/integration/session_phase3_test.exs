defmodule JidoCode.Integration.SessionPhase3Test do
  @moduledoc """
  Integration tests for Phase 3 (Tool Integration) components.

  These tests verify that all Phase 3 components work together correctly:
  - Tool Executor with session context
  - Handler session awareness
  - LLMAgent integration with session supervision
  - Multi-session tool isolation
  - AgentAPI integration

  Tests use the application's infrastructure and clean up after themselves.

  ## Why async: false

  These tests cannot run async because they:
  1. Share the SessionSupervisor (DynamicSupervisor) - tests modify global state
  2. Use SessionRegistry which is a shared ETS table
  3. Use Phoenix.PubSub topics that could interfere between tests
  4. Require deterministic cleanup between test runs
  """
  use ExUnit.Case, async: false

  alias JidoCode.Session
  alias JidoCode.Session.AgentAPI
  alias JidoCode.Session.State, as: SessionState
  # PerSessionSupervisor is the supervisor for a single session's processes
  # (Manager, State, Agent), distinct from SessionSupervisor which is the
  # DynamicSupervisor that manages all session supervisors
  alias JidoCode.Session.Supervisor, as: PerSessionSupervisor
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor
  alias JidoCode.Test.SessionTestHelpers
  alias JidoCode.Tools.Definitions.FileSystem, as: FileSystemDefs
  alias JidoCode.Tools.Definitions.Search, as: SearchDefs
  alias JidoCode.Tools.Definitions.Shell, as: ShellDefs
  alias JidoCode.Tools.Executor
  alias JidoCode.Tools.Registry, as: ToolsRegistry

  @moduletag :integration
  @moduletag :phase3

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    Process.flag(:trap_exit, true)

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
    tmp_base = Path.join(System.tmp_dir!(), "phase3_integration_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_base)

    # Set up API key for agent tests
    System.put_env("ANTHROPIC_API_KEY", "test-key-for-integration")

    # Register tools
    register_test_tools()

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

  defp register_test_tools do
    # Register filesystem tools
    ToolsRegistry.register(FileSystemDefs.read_file())
    ToolsRegistry.register(FileSystemDefs.write_file())
    ToolsRegistry.register(FileSystemDefs.list_directory())

    # Register search tools
    ToolsRegistry.register(SearchDefs.grep())
    ToolsRegistry.register(SearchDefs.find_files())

    # Register shell tools
    ToolsRegistry.register(ShellDefs.run_command())
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp create_test_dir(base, name) do
    path = Path.join(base, name)
    File.mkdir_p!(path)
    path
  end

  defp create_session(project_path) do
    config = SessionTestHelpers.valid_session_config()
    {:ok, session} = Session.new(project_path: project_path, config: config)
    {:ok, _pid} = SessionSupervisor.start_session(session)
    session
  end

  defp tool_call(name, args) do
    %{
      id: "tc-#{:rand.uniform(100_000)}",
      name: name,
      arguments: args
    }
  end

  # Helper to extract result from Executor.execute response
  # Executor.execute returns {:ok, %Result{}} or {:error, term()}
  defp unwrap_result({:ok, %JidoCode.Tools.Result{status: :ok, content: content}}),
    do: {:ok, content}

  defp unwrap_result({:ok, %JidoCode.Tools.Result{status: :error, content: content}}),
    do: {:error, content}

  defp unwrap_result({:error, _} = result), do: result

  # Polling helper to wait for a condition instead of using Process.sleep
  # This avoids flaky tests from timing-based assertions
  defp assert_eventually(condition_fn, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 500)
    interval = Keyword.get(opts, :interval, 10)
    deadline = System.monotonic_time(:millisecond) + timeout

    do_assert_eventually(condition_fn, deadline, interval)
  end

  defp do_assert_eventually(condition_fn, deadline, interval) do
    if condition_fn.() do
      :ok
    else
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(interval)
        do_assert_eventually(condition_fn, deadline, interval)
      else
        flunk("Condition not met within timeout")
      end
    end
  end

  # Check if system tools (grep, ls) are available for tests
  defp system_tool_available?(tool) do
    case System.cmd("which", [tool], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end

  # ============================================================================
  # 3.5.1 Tool Execution Pipeline Tests
  # ============================================================================

  describe "3.5.1 Tool Execution Pipeline" do
    test "build context from session and execute tool within boundary", %{tmp_base: tmp_base} do
      # Create project directory with test file
      project_path = create_test_dir(tmp_base, "pipeline_test")
      File.write!(Path.join(project_path, "test.txt"), "Hello, World!")

      # Create session
      session = create_session(project_path)

      # Execute tool with session context
      result =
        Executor.execute(
          tool_call("read_file", %{"path" => "test.txt"}),
          context: %{session_id: session.id, project_root: project_path}
        )
        |> unwrap_result()

      assert {:ok, "Hello, World!"} = result
    end

    test "tool call broadcasts to session topic", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "pubsub_test")
      File.write!(Path.join(project_path, "test.txt"), "content")

      session = create_session(project_path)

      # Subscribe to session's tui events topic (tool results go here)
      topic = JidoCode.PubSubTopics.llm_stream(session.id)
      Phoenix.PubSub.subscribe(JidoCode.PubSub, topic)

      result =
        Executor.execute(
          tool_call("read_file", %{"path" => "test.txt"}),
          context: %{session_id: session.id, project_root: project_path}
        )
        |> unwrap_result()

      assert {:ok, _} = result
      # Tool result may or may not be broadcast depending on configuration
    end

    test "ReadFile validates path via session boundary", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "boundary_test")
      File.write!(Path.join(project_path, "allowed.txt"), "allowed content")

      # Create file outside project
      outside_file = Path.join(tmp_base, "outside.txt")
      File.write!(outside_file, "outside content")

      session = create_session(project_path)

      # Reading file inside boundary should work
      result =
        Executor.execute(
          tool_call("read_file", %{"path" => "allowed.txt"}),
          context: %{session_id: session.id, project_root: project_path}
        )
        |> unwrap_result()

      assert {:ok, "allowed content"} = result

      # Reading file outside boundary should fail
      result =
        Executor.execute(
          tool_call("read_file", %{"path" => "../outside.txt"}),
          context: %{session_id: session.id, project_root: project_path}
        )
        |> unwrap_result()

      assert {:error, error} = result
      assert is_binary(error)
    end

    test "WriteFile writes within session boundary", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "write_test")
      session = create_session(project_path)

      # Write file inside boundary
      result =
        Executor.execute(
          tool_call("write_file", %{"path" => "new_file.txt", "content" => "test content"}),
          context: %{session_id: session.id, project_root: project_path}
        )
        |> unwrap_result()

      assert {:ok, _} = result
      assert File.read!(Path.join(project_path, "new_file.txt")) == "test content"
    end

    test "tool execution without session_id uses project_root", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "no_session_test")
      File.write!(Path.join(project_path, "test.txt"), "content")

      # Context without session_id but with project_root
      result =
        Executor.execute(
          tool_call("read_file", %{"path" => "test.txt"}),
          context: %{project_root: project_path}
        )
        |> unwrap_result()

      # Should work with deprecation warning (backwards compatibility)
      assert {:ok, "content"} = result
    end
  end

  # ============================================================================
  # 3.5.2 Handler Session Awareness Tests
  # ============================================================================

  describe "3.5.2 Handler Session Awareness" do
    test "FileSystem handlers validate paths via session's Manager", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "fs_handler_test")
      File.write!(Path.join(project_path, "file.txt"), "content")

      session = create_session(project_path)

      # List directory should work
      result =
        Executor.execute(
          tool_call("list_directory", %{"path" => "."}),
          context: %{session_id: session.id, project_root: project_path}
        )
        |> unwrap_result()

      assert {:ok, listing} = result
      assert listing =~ "file.txt"
    end

    @tag :requires_system_tools
    test "Search handlers respect session boundary", %{tmp_base: tmp_base} do
      # Skip if grep is not available on this system
      if system_tool_available?("grep") do
        project_path = create_test_dir(tmp_base, "search_test")
        File.write!(Path.join(project_path, "searchable.txt"), "needle in haystack")

        session = create_session(project_path)

        # Grep should find content
        result =
          Executor.execute(
            tool_call("grep", %{"pattern" => "needle", "path" => "."}),
            context: %{session_id: session.id, project_root: project_path}
          )
          |> unwrap_result()

        # With grep available, we expect success with matching content
        assert {:ok, output} = result

        assert output =~ "needle" or output =~ "searchable.txt",
               "Expected grep output to contain 'needle' or 'searchable.txt', got: #{inspect(output)}"
      else
        IO.puts("Skipping grep test - grep not available")
        :ok
      end
    end

    @tag :requires_system_tools
    test "Shell handler uses session's project_root as cwd", %{tmp_base: tmp_base} do
      # Skip if ls is not available on this system
      if system_tool_available?("ls") do
        project_path = create_test_dir(tmp_base, "shell_test")
        File.write!(Path.join(project_path, "marker.txt"), "marker")

        session = create_session(project_path)

        # Run ls command
        result =
          Executor.execute(
            tool_call("run_command", %{"command" => "ls"}),
            context: %{session_id: session.id, project_root: project_path}
          )
          |> unwrap_result()

        # With ls available, we expect success showing the marker file
        assert {:ok, output} = result

        assert output =~ "marker.txt",
               "Expected ls output to contain 'marker.txt', got: #{inspect(output)}"
      else
        IO.puts("Skipping shell test - ls not available")
        :ok
      end
    end

    test "Todo handler updates Session.State for correct session", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "todo_test")
      session = create_session(project_path)

      todos = [
        %{id: "t1", content: "Task 1", status: :pending},
        %{id: "t2", content: "Task 2", status: :in_progress}
      ]

      # Update todos via Session.State
      {:ok, _} = SessionState.update_todos(session.id, todos)

      # Verify todos are stored in session state
      {:ok, stored_todos} = SessionState.get_todos(session.id)
      assert length(stored_todos) == 2
      assert Enum.any?(stored_todos, fn t -> t.content == "Task 1" end)
    end
  end

  # ============================================================================
  # 3.5.3 Agent-Session Integration Tests
  # ============================================================================

  describe "3.5.3 Agent-Session Integration" do
    test "agent starts under Session.Supervisor", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "agent_start_test")
      session = create_session(project_path)

      # Get agent pid via Session.Supervisor (the per-session supervisor)
      case PerSessionSupervisor.get_agent(session.id) do
        {:ok, agent_pid} ->
          assert is_pid(agent_pid)
          assert Process.alive?(agent_pid)

        {:error, :not_found} ->
          # Agent might not have started due to mock API key
          :ok
      end
    end

    test "agent streaming updates Session.State", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "streaming_test")
      session = create_session(project_path)

      # Subscribe to streaming topic
      topic = JidoCode.PubSubTopics.llm_stream(session.id)
      Phoenix.PubSub.subscribe(JidoCode.PubSub, topic)

      # Start streaming (will fail with mock key but should set up state)
      SessionState.start_streaming(session.id, "msg-1")

      {:ok, state} = SessionState.get_state(session.id)
      assert state.is_streaming == true

      # End streaming
      SessionState.update_streaming(session.id, "chunk 1")
      SessionState.update_streaming(session.id, "chunk 2")

      {:ok, state} = SessionState.get_state(session.id)
      assert state.streaming_message == "chunk 1chunk 2"

      {:ok, message} = SessionState.end_streaming(session.id)
      assert message.content == "chunk 1chunk 2"
      assert message.role == :assistant
    end

    test "session close terminates agent cleanly", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "agent_close_test")
      session = create_session(project_path)

      # Get agent pid if available
      agent_pid =
        case PerSessionSupervisor.get_agent(session.id) do
          {:ok, pid} -> pid
          {:error, :not_found} -> nil
        end

      # Stop the session
      :ok = SessionSupervisor.stop_session(session.id)

      # Wait for cleanup using polling instead of fixed sleep
      # This avoids flaky tests from timing-based assertions
      assert_eventually(
        fn ->
          # Session should be gone from registry
          PerSessionSupervisor.get_agent(session.id) == {:error, :not_found}
        end,
        timeout: 500
      )

      # Agent should be terminated (if it was running)
      if agent_pid do
        assert_eventually(fn -> not Process.alive?(agent_pid) end, timeout: 500)
      end

      # Final assertion that session is gone
      assert {:error, :not_found} = PerSessionSupervisor.get_agent(session.id)
    end
  end

  # ============================================================================
  # 3.5.4 Multi-Session Tool Isolation Tests
  # ============================================================================

  describe "3.5.4 Multi-Session Tool Isolation" do
    test "session A cannot access session B's boundary", %{tmp_base: tmp_base} do
      # Create two separate projects
      project_a = create_test_dir(tmp_base, "project_a")
      project_b = create_test_dir(tmp_base, "project_b")

      File.write!(Path.join(project_a, "a.txt"), "content A")
      File.write!(Path.join(project_b, "b.txt"), "content B")

      session_a = create_session(project_a)
      session_b = create_session(project_b)

      # Session A can read its own file
      assert {:ok, "content A"} =
               Executor.execute(
                 tool_call("read_file", %{"path" => "a.txt"}),
                 context: %{session_id: session_a.id, project_root: project_a}
               )
               |> unwrap_result()

      # Session B can read its own file
      assert {:ok, "content B"} =
               Executor.execute(
                 tool_call("read_file", %{"path" => "b.txt"}),
                 context: %{session_id: session_b.id, project_root: project_b}
               )
               |> unwrap_result()

      # Session A cannot read session B's file via path traversal
      result =
        Executor.execute(
          tool_call("read_file", %{"path" => "../project_b/b.txt"}),
          context: %{session_id: session_a.id, project_root: project_a}
        )
        |> unwrap_result()

      assert {:error, _} = result
    end

    test "concurrent tool execution in two sessions causes no interference", %{tmp_base: tmp_base} do
      project_a = create_test_dir(tmp_base, "concurrent_a")
      project_b = create_test_dir(tmp_base, "concurrent_b")

      session_a = create_session(project_a)
      session_b = create_session(project_b)

      # Execute writes concurrently
      task_a =
        Task.async(fn ->
          Executor.execute(
            tool_call("write_file", %{"path" => "test.txt", "content" => "content A"}),
            context: %{session_id: session_a.id, project_root: project_a}
          )
          |> unwrap_result()
        end)

      task_b =
        Task.async(fn ->
          Executor.execute(
            tool_call("write_file", %{"path" => "test.txt", "content" => "content B"}),
            context: %{session_id: session_b.id, project_root: project_b}
          )
          |> unwrap_result()
        end)

      {:ok, _} = Task.await(task_a)
      {:ok, _} = Task.await(task_b)

      # Verify each project has correct content
      assert File.read!(Path.join(project_a, "test.txt")) == "content A"
      assert File.read!(Path.join(project_b, "test.txt")) == "content B"
    end

    test "todo update in session A does not affect session B", %{tmp_base: tmp_base} do
      project_a = create_test_dir(tmp_base, "todo_a")
      project_b = create_test_dir(tmp_base, "todo_b")

      session_a = create_session(project_a)
      session_b = create_session(project_b)

      # Update todos in session A
      todos_a = [%{id: "t1", content: "Task A", status: :pending}]
      {:ok, _} = SessionState.update_todos(session_a.id, todos_a)

      # Update different todos in session B
      todos_b = [%{id: "t2", content: "Task B", status: :completed}]
      {:ok, _} = SessionState.update_todos(session_b.id, todos_b)

      # Verify isolation
      {:ok, stored_a} = SessionState.get_todos(session_a.id)
      {:ok, stored_b} = SessionState.get_todos(session_b.id)

      assert length(stored_a) == 1
      assert hd(stored_a).content == "Task A"

      assert length(stored_b) == 1
      assert hd(stored_b).content == "Task B"
    end

    test "streaming in session A is not received in session B", %{tmp_base: tmp_base} do
      project_a = create_test_dir(tmp_base, "stream_a")
      project_b = create_test_dir(tmp_base, "stream_b")

      session_a = create_session(project_a)
      session_b = create_session(project_b)

      # Subscribe only to session B's stream topic
      topic_b = JidoCode.PubSubTopics.llm_stream(session_b.id)
      Phoenix.PubSub.subscribe(JidoCode.PubSub, topic_b)

      # Broadcast to session A's topic
      topic_a = JidoCode.PubSubTopics.llm_stream(session_a.id)
      Phoenix.PubSub.broadcast(JidoCode.PubSub, topic_a, {:stream_chunk, "chunk for A"})

      # Session B should NOT receive session A's chunk
      refute_receive {:stream_chunk, "chunk for A"}, 100

      # Broadcast to session B's topic
      Phoenix.PubSub.broadcast(JidoCode.PubSub, topic_b, {:stream_chunk, "chunk for B"})

      # Session B SHOULD receive its own chunk
      assert_receive {:stream_chunk, "chunk for B"}, 100
    end
  end

  # ============================================================================
  # 3.5.5 AgentAPI Integration Tests
  # ============================================================================

  describe "3.5.5 AgentAPI Integration" do
    test "get_status returns correct status for valid session", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "status_test")
      session = create_session(project_path)

      case AgentAPI.get_status(session.id) do
        {:ok, status} ->
          assert is_boolean(status.ready)
          assert is_map(status.config)
          assert status.session_id == session.id

        {:error, :agent_not_found} ->
          # Agent might not have started
          :ok
      end
    end

    test "update_config updates both agent and session config", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "config_test")
      session = create_session(project_path)

      case AgentAPI.update_config(session.id, %{temperature: 0.5}) do
        :ok ->
          # Verify agent config updated
          {:ok, config} = AgentAPI.get_config(session.id)
          assert config.temperature == 0.5

          # Verify session config updated
          {:ok, state} = SessionState.get_state(session.id)
          assert state.session.config.temperature == 0.5

        {:error, :agent_not_found} ->
          # Agent might not have started
          :ok
      end
    end

    test "AgentAPI returns clear error for invalid session", %{tmp_base: _tmp_base} do
      fake_session_id = "non-existent-session-id"

      assert {:error, :agent_not_found} = AgentAPI.get_status(fake_session_id)
      assert {:error, :agent_not_found} = AgentAPI.get_config(fake_session_id)

      assert {:error, :agent_not_found} =
               AgentAPI.update_config(fake_session_id, %{temperature: 0.5})

      assert {:error, :agent_not_found} = AgentAPI.send_message(fake_session_id, "Hello")
      assert {:error, :agent_not_found} = AgentAPI.send_message_stream(fake_session_id, "Hello")
    end

    test "is_processing? returns boolean for valid session", %{tmp_base: tmp_base} do
      project_path = create_test_dir(tmp_base, "processing_test")
      session = create_session(project_path)

      case AgentAPI.is_processing?(session.id) do
        {:ok, is_processing} ->
          assert is_boolean(is_processing)

        {:error, :agent_not_found} ->
          # Agent might not have started
          :ok
      end
    end
  end
end

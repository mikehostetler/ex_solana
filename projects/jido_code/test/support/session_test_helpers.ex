defmodule JidoCode.Test.SessionTestHelpers do
  @moduledoc """
  Shared test setup helpers for session-related tests.

  Extracts common setup code to reduce duplication across test files.

  ## Available Setup Functions

  - `setup_session_registry/1` - Lightweight setup for unit tests (Registry + tmp_dir)
  - `setup_session_supervisor/1` - Full setup with SessionSupervisor for integration tests
  - `valid_session_config/0` - Returns a valid LLM config for tests

  ## Tool Testing Helpers

  - `tool_call/2` - Create a properly formatted tool call map
  - `unwrap_result/1` - Extract content from Executor.execute result
  - `assert_eventually/2` - Polling helper to replace Process.sleep
  """

  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor

  @registry JidoCode.SessionProcessRegistry

  @doc """
  Returns a valid LLM configuration for tests.

  This config uses actual model names that will pass validation.
  Use this when creating sessions for tests that need LLMAgent.
  """
  @spec valid_session_config() :: map()
  def valid_session_config do
    %{
      provider: "anthropic",
      model: "claude-3-5-haiku-20241022",
      temperature: 0.7,
      max_tokens: 4096
    }
  end

  # ============================================================================
  # Lightweight Setup (for unit tests)
  # ============================================================================

  @doc """
  Sets up the session registry test environment for unit tests.

  This is a lightweight setup that only starts the SessionProcessRegistry
  and creates a temporary directory. Use this for testing individual
  session modules (Manager, State, Session.Supervisor) in isolation.

  Returns a map with:
  - `:tmp_dir` - Path to temporary directory for test files

  ## Usage

      setup do
        JidoCode.Test.SessionTestHelpers.setup_session_registry()
      end

  Or with a custom suffix:

      setup do
        JidoCode.Test.SessionTestHelpers.setup_session_registry("manager_test")
      end
  """
  @spec setup_session_registry(String.t()) :: {:ok, map()}
  def setup_session_registry(suffix \\ "test") do
    # Ensure core infrastructure is running
    ensure_infrastructure()

    # Ensure registry is available - either use existing or start new
    case Process.whereis(@registry) do
      nil ->
        # No registry, start one
        {:ok, _} = Registry.start_link(keys: :unique, name: @registry)

      pid when is_pid(pid) ->
        # Registry exists, use it (application.ex starts it)
        :ok
    end

    # Create a temp directory for sessions
    tmp_dir = Path.join(System.tmp_dir!(), "session_#{suffix}_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)

    ExUnit.Callbacks.on_exit(fn ->
      cleanup_session_registry(tmp_dir)
    end)

    {:ok, %{tmp_dir: tmp_dir}}
  end

  @doc """
  Cleans up session registry test resources.

  Called automatically via on_exit when using setup_session_registry/1.
  """
  @spec cleanup_session_registry(String.t()) :: :ok
  def cleanup_session_registry(tmp_dir) do
    # Only clean up temp directory, don't stop the registry
    # The registry is shared across all tests
    File.rm_rf!(tmp_dir)
    :ok
  end

  # ============================================================================
  # Full Setup (for integration tests)
  # ============================================================================

  @doc """
  Sets up the session supervisor test environment.

  Starts SessionProcessRegistry, SessionSupervisor, creates SessionRegistry table,
  and creates a temporary directory for test projects.

  Returns a map with:
  - `:sup_pid` - The SessionSupervisor pid
  - `:tmp_dir` - Path to temporary directory for test files

  ## Usage

      setup do
        JidoCode.Test.SessionTestHelpers.setup_session_supervisor()
      end

  Or with a custom suffix for the temp directory:

      setup do
        JidoCode.Test.SessionTestHelpers.setup_session_supervisor("my_test")
      end
  """
  @spec setup_session_supervisor(String.t()) :: {:ok, map()}
  def setup_session_supervisor(suffix \\ "test") do
    # Ensure core infrastructure is running
    ensure_infrastructure()

    # Use the existing SessionSupervisor from application.ex if available,
    # or start a new one if not running
    sup_pid =
      case Process.whereis(SessionSupervisor) do
        nil ->
          {:ok, pid} = SessionSupervisor.start_link([])
          pid

        pid ->
          pid
      end

    # Ensure SessionRegistry table exists and is clear
    SessionRegistry.create_table()
    SessionRegistry.clear()

    # Ensure Persistence lock tables exist
    JidoCode.Session.Persistence.init()

    # Create a temp directory for sessions
    tmp_dir = Path.join(System.tmp_dir!(), "session_#{suffix}_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)

    ExUnit.Callbacks.on_exit(fn ->
      cleanup_session_supervisor(sup_pid, tmp_dir)
    end)

    {:ok, %{sup_pid: sup_pid, tmp_dir: tmp_dir}}
  end

  @doc """
  Ensures all core infrastructure is running.

  Call this at the start of tests that depend on global infrastructure
  like PubSub, registries, and supervisors. This handles cases where
  previous tests may have stopped the infrastructure.
  """
  @spec ensure_infrastructure() :: :ok
  def ensure_infrastructure do
    # If the main application supervisor is not running, restart the whole application
    case Process.whereis(JidoCode.Supervisor) do
      nil ->
        # Application was stopped, restart it
        {:ok, _} = Application.ensure_all_started(:jido_code)
        :ok

      _pid ->
        # Application is running, just ensure individual components
        ensure_components()
    end
  end

  defp ensure_components do
    # Ensure PubSub is running
    case Process.whereis(JidoCode.PubSub) do
      nil ->
        {:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: JidoCode.PubSub)

      _pid ->
        :ok
    end

    # Ensure SessionProcessRegistry is running
    case Process.whereis(JidoCode.SessionProcessRegistry) do
      nil ->
        {:ok, _} = Registry.start_link(keys: :unique, name: JidoCode.SessionProcessRegistry)

      _pid ->
        :ok
    end

    # Ensure AgentRegistry is running
    case Process.whereis(JidoCode.AgentRegistry) do
      nil ->
        {:ok, _} = Registry.start_link(keys: :unique, name: JidoCode.AgentRegistry)

      _pid ->
        :ok
    end

    # Ensure AgentSupervisor is running
    case Process.whereis(JidoCode.AgentSupervisor) do
      nil ->
        {:ok, _} = JidoCode.AgentSupervisor.start_link([])

      _pid ->
        :ok
    end

    # Ensure SessionSupervisor is running
    case Process.whereis(JidoCode.SessionSupervisor) do
      nil ->
        {:ok, _} = JidoCode.SessionSupervisor.start_link([])

      _pid ->
        :ok
    end

    :ok
  end

  @doc """
  Cleans up session supervisor test resources.

  Called automatically via on_exit when using setup_session_supervisor/1,
  but can be called manually if needed.
  """
  @spec cleanup_session_supervisor(pid(), String.t()) :: :ok
  def cleanup_session_supervisor(_sup_pid, tmp_dir) do
    # Only clear sessions, don't stop registries or supervisors
    # These are shared across all tests and should remain running
    SessionRegistry.clear()
    File.rm_rf!(tmp_dir)
    :ok
  end

  @doc """
  Stops all running sessions for test isolation.

  This ensures tests start with a clean slate by stopping all session
  processes under the SessionSupervisor.
  """
  @spec stop_all_sessions() :: :ok
  def stop_all_sessions do
    # Get all sessions from the registry
    sessions = SessionRegistry.list_all()

    # Stop each session
    Enum.each(sessions, fn session ->
      try do
        SessionSupervisor.stop_session(session.id)
      catch
        :exit, _ -> :ok
      end
    end)

    # Also stop any orphan session processes not in the registry
    if pid = Process.whereis(SessionSupervisor) do
      children = DynamicSupervisor.which_children(pid)

      Enum.each(children, fn {_, child_pid, _, _} ->
        try do
          DynamicSupervisor.terminate_child(pid, child_pid)
        catch
          :exit, _ -> :ok
        end
      end)
    end

    # Clear the registry
    SessionRegistry.clear()

    :ok
  end

  @doc """
  Waits for a process to terminate using process monitoring.

  This is preferred over `:timer.sleep/1` as it's deterministic and
  doesn't cause flaky tests on slow CI systems.

  ## Parameters

  - `pid` - The process to wait for
  - `timeout` - Maximum time to wait in milliseconds (default: 100)

  ## Returns

  - `:ok` - Process terminated
  - `:timeout` - Process didn't terminate within timeout

  ## Examples

      {:ok, pid} = start_some_process()
      Process.exit(pid, :normal)
      :ok = wait_for_process_death(pid)
  """
  @spec wait_for_process_death(pid(), non_neg_integer()) :: :ok | :timeout
  def wait_for_process_death(pid, timeout \\ 100) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        :timeout
    end
  end

  @doc """
  Waits for a Registry entry to be removed.

  Polls the Registry until the key is no longer present or timeout is reached.
  This is useful when testing process cleanup, as Registry entries may persist
  briefly after process termination.

  ## Parameters

  - `registry` - The Registry module name
  - `key` - The Registry key to check
  - `timeout` - Maximum time to wait in milliseconds (default: 100)

  ## Returns

  - `:ok` - Entry was removed
  - `:timeout` - Entry still exists after timeout

  ## Examples

      :ok = wait_for_registry_cleanup(MyRegistry, {:session, session_id})
  """
  @spec wait_for_registry_cleanup(atom(), term(), non_neg_integer()) :: :ok | :timeout
  def wait_for_registry_cleanup(registry, key, timeout \\ 100) do
    deadline = System.monotonic_time(:millisecond) + timeout
    poll_registry(registry, key, deadline)
  end

  defp poll_registry(registry, key, deadline) do
    case Registry.lookup(registry, key) do
      [] ->
        :ok

      _ ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(5)
          poll_registry(registry, key, deadline)
        else
          :timeout
        end
    end
  end

  # ============================================================================
  # Session Persistence Test Helpers
  # ============================================================================

  @doc """
  Generates a deterministic valid UUID v4 for testing.

  Creates UUID v4 format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  where the version digit is 4 and the variant digit is one of [8, 9, A, B].

  ## Parameters

  - `index` - Integer index to generate unique UUIDs (default: 0)

  ## Examples

      iex> test_uuid(0)
      "00010000-0000-4000-8000-000000000000"

      iex> test_uuid(42)
      "00010042-0000-4000-8000-004200000000"
  """
  @spec test_uuid(non_neg_integer()) :: String.t()
  def test_uuid(index \\ 0) do
    # Generate valid UUID v4 format
    # Version 4 UUID: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
    # where y is one of [8, 9, A, B]
    base_id = 10000 + index
    id_str = Integer.to_string(base_id) |> String.pad_leading(12, "0")
    "#{String.slice(id_str, 0..7)}-0000-4000-8000-#{String.slice(id_str, 8..11)}00000000"
  end

  @doc """
  Creates a test Session struct with sensible defaults.

  ## Parameters

  - `id` - Session ID (UUID string)
  - `name` - Session name
  - `project_path` - Project directory path
  - `opts` - Optional keyword list to override defaults

  ## Examples

      iex> session = create_test_session("123", "Test Session", "/tmp/test")
      iex> session.name
      "Test Session"
  """
  @spec create_test_session(String.t(), String.t(), String.t(), keyword()) :: JidoCode.Session.t()
  def create_test_session(id, name, project_path, opts \\ []) do
    %JidoCode.Session{
      id: id,
      name: name,
      project_path: project_path,
      config: valid_session_config(),
      created_at: Keyword.get(opts, :created_at, DateTime.utc_now()),
      updated_at: Keyword.get(opts, :updated_at, DateTime.utc_now())
    }
  end

  @doc """
  Creates a persisted session map (JSON-serializable format).

  Returns a map matching the structure expected by the persistence layer,
  with string keys and ISO8601 timestamp strings.

  ## Parameters

  - `id` - Session ID (UUID string)
  - `name` - Session name
  - `project_path` - Project directory path
  - `opts` - Optional keyword list to override defaults

  ## Examples

      iex> persisted = create_persisted_session("123", "Test", "/tmp/test")
      iex> persisted["version"]
      1
  """
  @spec create_persisted_session(String.t(), String.t(), String.t(), keyword()) :: map()
  def create_persisted_session(id, name, project_path, opts \\ []) do
    now = Keyword.get(opts, :timestamp, DateTime.utc_now())
    timestamp = DateTime.to_iso8601(now)

    config =
      Keyword.get(opts, :config, %{
        "provider" => "anthropic",
        "model" => "claude-3-5-haiku-20241022",
        "temperature" => 0.7,
        "max_tokens" => 4096
      })

    conversation =
      Keyword.get(opts, :conversation, [
        %{
          "id" => "msg-1",
          "role" => "user",
          "content" => "Hello",
          "timestamp" => timestamp
        },
        %{
          "id" => "msg-2",
          "role" => "assistant",
          "content" => "Hi there!",
          "timestamp" => timestamp
        }
      ])

    todos =
      Keyword.get(opts, :todos, [
        %{
          "content" => "Test task",
          "status" => "pending",
          "active_form" => "Testing task"
        }
      ])

    %{
      version: 1,
      id: id,
      name: name,
      project_path: project_path,
      config: config,
      created_at: timestamp,
      updated_at: timestamp,
      closed_at: timestamp,
      conversation: conversation,
      todos: todos
    }
  end

  # ============================================================================
  # Tool Testing Helpers
  # ============================================================================

  @doc """
  Creates a properly formatted tool call map for Executor.execute.

  This standardizes tool call creation across tests and ensures the
  correct format is used consistently.

  ## Parameters

  - `name` - Tool name as a string
  - `args` - Map of arguments for the tool

  ## Examples

      iex> tool_call("read_file", %{"path" => "lib/app.ex"})
      %{"name" => "read_file", "arguments" => %{"path" => "lib/app.ex"}}

      iex> tool_call("grep", %{"pattern" => "TODO", "path" => "."})
      %{"name" => "grep", "arguments" => %{"pattern" => "TODO", "path" => "."}}
  """
  @spec tool_call(String.t(), map()) :: map()
  def tool_call(name, args) when is_binary(name) and is_map(args) do
    %{"name" => name, "arguments" => args}
  end

  @doc """
  Extracts the content from an Executor.execute result.

  Handles both success and error cases, returning the content string
  or the error tuple for further assertion.

  ## Examples

      # Success case
      iex> unwrap_result({:ok, %{content: "file contents"}})
      {:ok, "file contents"}

      # Error case (passes through)
      iex> unwrap_result({:error, "not found"})
      {:error, "not found"}
  """
  @spec unwrap_result({:ok, map()} | {:error, term()}) :: {:ok, String.t()} | {:error, term()}
  def unwrap_result({:ok, %{content: content}}), do: {:ok, content}
  def unwrap_result({:error, _} = error), do: error

  @doc """
  Polls a condition function until it returns true or timeout is reached.

  This is preferred over `Process.sleep/1` as it doesn't introduce
  unnecessary delays and is more deterministic on slow CI systems.

  ## Parameters

  - `condition_fn` - Zero-arity function that returns a boolean
  - `opts` - Keyword list of options:
    - `:timeout` - Maximum time to wait in milliseconds (default: 500)
    - `:interval` - Polling interval in milliseconds (default: 10)

  ## Returns

  - `true` - Condition was satisfied
  - `false` - Timeout reached before condition was satisfied

  ## Examples

      # Wait for a process to be registered
      assert_eventually(fn -> Process.whereis(:my_process) != nil end)

      # Wait with custom timeout
      assert_eventually(fn -> check_something() end, timeout: 1000)

      # Use in tests
      assert assert_eventually(fn -> File.exists?(path) end)
  """
  @spec assert_eventually((-> boolean()), keyword()) :: boolean()
  def assert_eventually(condition_fn, opts \\ []) when is_function(condition_fn, 0) do
    timeout = Keyword.get(opts, :timeout, 500)
    interval = Keyword.get(opts, :interval, 10)
    deadline = System.monotonic_time(:millisecond) + timeout
    do_assert_eventually(condition_fn, deadline, interval)
  end

  defp do_assert_eventually(condition_fn, deadline, interval) do
    if condition_fn.() do
      true
    else
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(interval)
        do_assert_eventually(condition_fn, deadline, interval)
      else
        false
      end
    end
  end
end

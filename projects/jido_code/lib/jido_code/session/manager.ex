defmodule JidoCode.Session.Manager do
  @moduledoc """
  Per-session security sandbox manager.

  This GenServer handles:
  - Session-scoped Lua sandbox execution
  - Project boundary enforcement for file operations
  - Session-specific security validation

  ## Registry

  Each Manager registers in `JidoCode.SessionProcessRegistry` with the key
  `{:manager, session_id}` for O(1) lookup.

  ## State

  The manager maintains the following state:

  - `session_id` - Unique identifier for the session
  - `project_root` - Root directory for file operation boundary
  - `lua_state` - Luerl sandbox state (initialized in Task 2.1.2)

  ## Lua Execution Timeout Limitation

  **Important**: The timeout parameter in `run_lua/3` applies only to the
  `GenServer.call/3` timeout, not to the Luerl execution itself. If a Lua
  script contains an infinite loop, the GenServer call will timeout, but the
  Lua execution may continue in the background until the GenServer terminates.

  For production use with untrusted scripts, consider:
  - Wrapping Lua execution in a Task with kill-on-timeout
  - Implementing Lua-level instruction counting (not supported by Luerl)
  - Using session timeouts to terminate long-running sessions

  ## Resource Considerations for Long-Lived Sessions

  For sessions that run for extended periods:

  - **Lua State Size**: The Lua state grows as variables are defined. Consider
    periodic state resets for very long sessions.
  - **Memory Monitoring**: Monitor session process memory via `:erlang.process_info/2`
  - **State Cleanup**: Use `run_lua/2` with cleanup scripts to nil out unused tables

  ## Usage

  Typically started as a child of Session.Supervisor:

      # In Session.Supervisor.init/1
      children = [
        {JidoCode.Session.Manager, session: session},
        # ...
      ]

  Direct lookup:

      [{pid, _}] = Registry.lookup(SessionProcessRegistry, {:manager, session_id})

  Access session's project root:

      {:ok, path} = Session.Manager.project_root(session_id)
  """

  use GenServer

  require Logger

  alias JidoCode.ErrorFormatter
  alias JidoCode.Session
  alias JidoCode.Session.ProcessRegistry
  alias JidoCode.Tools.Bridge
  alias JidoCode.Tools.Security

  @typedoc """
  Session Manager state.

  - `session_id` - The unique session identifier
  - `project_root` - The root directory for file operation boundary enforcement
  - `lua_state` - The Luerl sandbox state (nil until initialized)
  """
  @type state :: %{
          session_id: String.t(),
          project_root: String.t(),
          lua_state: :luerl.luerl_state() | nil
        }

  @doc """
  Starts the Session Manager.

  ## Options

  - `:session` - (required) The `Session` struct for this session

  ## Returns

  - `{:ok, pid}` - Manager started successfully
  - `{:error, reason}` - Failed to start
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    session = Keyword.fetch!(opts, :session)
    GenServer.start_link(__MODULE__, session, name: ProcessRegistry.via(:manager, session.id))
  end

  @doc """
  Returns the child specification for this GenServer.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    session = Keyword.fetch!(opts, :session)

    %{
      id: {:session_manager, session.id},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  # Client API

  @doc """
  Gets the project root path for a session.

  ## Parameters

  - `session_id` - The session identifier

  ## Returns

  - `{:ok, path}` - The project root path
  - `{:error, :not_found}` - Session manager not found

  ## Examples

      iex> {:ok, path} = Manager.project_root("session_123")
      {:ok, "/path/to/project"}
  """
  @spec project_root(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def project_root(session_id) do
    call_manager(session_id, :project_root)
  end

  @doc """
  Gets the session ID from a manager.

  ## Parameters

  - `session_id` - The session identifier

  ## Returns

  - `{:ok, session_id}` - The session ID
  - `{:error, :not_found}` - Session manager not found

  ## Examples

      iex> {:ok, id} = Manager.session_id("session_123")
      {:ok, "session_123"}
  """
  @spec session_id(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def session_id(session_id) do
    call_manager(session_id, :session_id)
  end

  @doc """
  Validates a path is within the session's project boundary.

  ## Parameters

  - `session_id` - The session identifier
  - `path` - The path to validate (relative or absolute)

  ## Returns

  - `{:ok, resolved_path}` - Path is valid and within boundary
  - `{:error, :not_found}` - Session manager not found
  - `{:error, reason}` - Path validation failed (see `JidoCode.Tools.Security`)

  ## Examples

      iex> {:ok, path} = Manager.validate_path("session_123", "src/file.ex")
      {:ok, "/project/src/file.ex"}

      iex> {:error, :path_escapes_boundary} = Manager.validate_path("session_123", "../../../etc/passwd")
  """
  @spec validate_path(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :not_found | Security.validation_error()}
  def validate_path(session_id, path) do
    call_manager(session_id, {:validate_path, path})
  end

  @doc """
  Reads a file within the session's project boundary.

  Uses atomic read with TOCTOU protection via `Security.atomic_read/3`.

  ## Parameters

  - `session_id` - The session identifier
  - `path` - The path to read (relative or absolute)

  ## Returns

  - `{:ok, content}` - File contents as binary
  - `{:error, :not_found}` - Session manager not found
  - `{:error, reason}` - Read failed (path validation or file error)

  ## Examples

      iex> {:ok, content} = Manager.read_file("session_123", "src/file.ex")
  """
  @spec read_file(String.t(), String.t()) ::
          {:ok, binary()} | {:error, :not_found | atom()}
  def read_file(session_id, path) do
    call_manager(session_id, {:read_file, path})
  end

  @doc """
  Writes content to a file within the session's project boundary.

  Uses atomic write with TOCTOU protection via `Security.atomic_write/4`.
  Creates parent directories if they don't exist.

  ## Parameters

  - `session_id` - The session identifier
  - `path` - The path to write (relative or absolute)
  - `content` - The content to write

  ## Returns

  - `:ok` - Write successful
  - `{:error, :not_found}` - Session manager not found
  - `{:error, reason}` - Write failed (path validation or file error)

  ## Examples

      iex> :ok = Manager.write_file("session_123", "src/new_file.ex", "defmodule New do\\nend")
  """
  @spec write_file(String.t(), String.t(), binary()) ::
          :ok | {:error, :not_found | atom()}
  def write_file(session_id, path, content) do
    call_manager(session_id, {:write_file, path, content})
  end

  @doc """
  Lists directory contents within the session's project boundary.

  ## Parameters

  - `session_id` - The session identifier
  - `path` - The directory path (relative or absolute)

  ## Returns

  - `{:ok, entries}` - List of file/directory names
  - `{:error, :not_found}` - Session manager not found
  - `{:error, reason}` - List failed (path validation or directory error)

  ## Examples

      iex> {:ok, entries} = Manager.list_dir("session_123", "src")
      {:ok, ["file1.ex", "file2.ex"]}
  """
  @spec list_dir(String.t(), String.t()) ::
          {:ok, [String.t()]} | {:error, :not_found | atom()}
  def list_dir(session_id, path) do
    call_manager(session_id, {:list_dir, path})
  end

  @doc """
  Executes a Lua script in the session's sandbox.

  The Lua state is updated after successful execution, so state persists
  between calls (e.g., variables defined in one call are available in the next).

  ## Timeout Behavior

  The timeout applies to the GenServer call, not to the Luerl execution itself.
  See the module documentation for details on timeout limitations.

  ## Parameters

  - `session_id` - The session identifier
  - `script` - The Lua script to execute
  - `timeout` - Timeout in milliseconds (default: 30000)

  ## Returns

  - `{:ok, result}` - Script executed successfully, result is list of return values
  - `{:error, :not_found}` - Session manager not found
  - `{:error, reason}` - Script execution failed

  ## Examples

      iex> {:ok, [42]} = Manager.run_lua("session_123", "return 21 + 21")
      iex> {:ok, ["hello"]} = Manager.run_lua("session_123", "return jido.read_file('test.txt')")
  """
  @spec run_lua(String.t(), String.t(), timeout()) ::
          {:ok, list()} | {:error, :not_found | term()}
  def run_lua(session_id, script, timeout \\ 30_000) do
    call_manager(session_id, {:run_lua, script}, timeout)
  end

  @doc """
  Gets the session struct for this manager.

  ## Deprecation Warning

  This function is deprecated and will be removed in a future version.
  Use `project_root/1` or `session_id/1` instead.

  **Warning**: The returned session struct contains synthetic data:
  - `created_at` and `updated_at` are set to the current time (not actual timestamps)
  - `config` is always empty `%{}`
  - `name` is derived from the project path basename

  ## Examples

      iex> {:ok, session} = Manager.get_session(pid)
  """
  @deprecated "Use project_root/1 or session_id/1 instead"
  @spec get_session(GenServer.server()) :: {:ok, Session.t()}
  def get_session(server) do
    GenServer.call(server, :get_session)
  end

  # Server callbacks

  @impl true
  def init(%Session{} = session) do
    Logger.info("Starting Session.Manager for session #{session.id}")
    Logger.debug("  project_root: #{session.project_path}")

    case initialize_lua_sandbox(session.project_path) do
      {:ok, lua_state} ->
        Logger.debug("  Lua sandbox initialized successfully")

        state = %{
          session_id: session.id,
          project_root: session.project_path,
          lua_state: lua_state
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error(
          "Failed to initialize Lua sandbox for session #{session.id}: #{inspect(reason)}"
        )

        {:stop, {:lua_init_failed, reason}}
    end
  end

  @impl true
  def handle_call(:project_root, _from, state) do
    {:reply, {:ok, state.project_root}, state}
  end

  @impl true
  def handle_call(:session_id, _from, state) do
    {:reply, {:ok, state.session_id}, state}
  end

  @impl true
  def handle_call({:validate_path, path}, _from, state) do
    result = Security.validate_path(path, state.project_root, log_violations: true)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:read_file, path}, _from, state) do
    result = Security.atomic_read(path, state.project_root, log_violations: true)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:write_file, path, content}, _from, state) do
    result = Security.atomic_write(path, content, state.project_root, log_violations: true)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:list_dir, path}, _from, state) do
    case Security.validate_path(path, state.project_root, log_violations: true) do
      {:ok, safe_path} -> {:reply, File.ls(safe_path), state}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:run_lua, script}, _from, state) do
    case :luerl.do(script, state.lua_state) do
      {:ok, result, new_lua_state} ->
        {:reply, {:ok, result}, %{state | lua_state: new_lua_state}}

      {:error, reason, _lua_state} ->
        {:reply, {:error, ErrorFormatter.format(reason)}, state}
    end
  rescue
    e ->
      {:reply, {:error, {:exception, Exception.message(e)}}, state}
  catch
    kind, reason ->
      {:reply, {:error, {kind, reason}}, state}
  end

  @impl true
  def handle_call(:get_session, _from, state) do
    # For backwards compatibility, reconstruct a minimal session-like map
    # WARNING: Timestamps are synthetic, config is empty
    session = %Session{
      id: state.session_id,
      project_path: state.project_root,
      name: Path.basename(state.project_root),
      config: %{},
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    {:reply, {:ok, session}, state}
  end

  # Private helpers

  # Calls a manager process by session_id with the given message.
  # Returns {:error, :not_found} if no manager exists for this session.
  @spec call_manager(String.t(), term(), timeout()) :: term()
  defp call_manager(session_id, message, timeout \\ 5000) do
    case ProcessRegistry.lookup(:manager, session_id) do
      {:ok, pid} -> GenServer.call(pid, message, timeout)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc false
  defp initialize_lua_sandbox(project_root) do
    # Initialize Luerl state and register bridge functions
    lua_state = :luerl.init()
    lua_state = Bridge.register(lua_state, project_root)
    {:ok, lua_state}
  rescue
    e ->
      {:error, {:exception, Exception.message(e)}}
  catch
    kind, reason ->
      {:error, {kind, reason}}
  end
end

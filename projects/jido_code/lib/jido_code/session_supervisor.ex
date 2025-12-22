defmodule JidoCode.SessionSupervisor do
  @moduledoc """
  DynamicSupervisor for managing per-session supervision trees.

  The SessionSupervisor is the entry point for starting and stopping session
  processes. Each session gets its own supervision subtree managed by this
  supervisor.

  ## Architecture

  ```
  SessionSupervisor (DynamicSupervisor, :one_for_one)
  ├── Session.Supervisor for session_1
  │   ├── Session.Manager
  │   └── Session.State
  ├── Session.Supervisor for session_2
  │   ├── Session.Manager
  │   └── Session.State
  └── ...
  ```

  ## Usage

  The supervisor is typically started as part of the application supervision tree:

      children = [
        # ... other children ...
        JidoCode.SessionSupervisor
      ]

  Session lifecycle is managed via functions in this module (implemented in Task 1.3.2):

      # Start a new session
      {:ok, pid} = SessionSupervisor.start_session(session)

      # Stop a session
      :ok = SessionSupervisor.stop_session(session_id)

  ## Strategy

  Uses `:one_for_one` strategy because sessions are independent - if one
  session's processes crash, other sessions should continue unaffected.
  """

  use DynamicSupervisor

  require Logger

  alias JidoCode.Session
  alias JidoCode.Session.Persistence
  alias JidoCode.SessionRegistry

  @registry JidoCode.SessionProcessRegistry

  @doc """
  Starts the SessionSupervisor.

  Called by the application supervision tree during startup.

  ## Options

  Currently accepts no meaningful options but follows the standard
  DynamicSupervisor interface for future extensibility.

  ## Examples

      iex> {:ok, pid} = JidoCode.SessionSupervisor.start_link([])
      iex> is_pid(pid)
      true
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # ============================================================================
  # Session Lifecycle (Task 1.3.2)
  # ============================================================================

  @doc """
  Starts a new session under this supervisor.

  Performs the following steps:
  1. Registers the session in SessionRegistry (validates limits/duplicates)
  2. Starts a per-session supervisor as a child of this DynamicSupervisor
  3. On failure, cleans up the registry entry

  ## Parameters

  - `session` - A valid `Session` struct
  - `opts` - Optional keyword list:
    - `:supervisor_module` - Module to use as per-session supervisor
      (default: `JidoCode.Session.Supervisor`)

  ## Returns

  - `{:ok, pid}` - Session started successfully, returns supervisor pid
  - `{:error, :session_limit_reached}` - Maximum sessions already registered
  - `{:error, :session_exists}` - Session with this ID already exists
  - `{:error, :project_already_open}` - Session for this project path exists

  ## Examples

      iex> {:ok, session} = Session.new(project_path: "/tmp/project")
      iex> {:ok, pid} = SessionSupervisor.start_session(session)
      iex> is_pid(pid)
      true
  """
  @spec start_session(Session.t(), keyword()) ::
          {:ok, pid()} | {:error, SessionRegistry.error_reason()}
  def start_session(%Session{} = session, opts \\ []) do
    supervisor_module = Keyword.get(opts, :supervisor_module, JidoCode.Session.Supervisor)

    with {:ok, session} <- SessionRegistry.register(session) do
      spec = {supervisor_module, session: session}

      case DynamicSupervisor.start_child(__MODULE__, spec) do
        {:ok, pid} ->
          {:ok, pid}

        {:ok, pid, _info} ->
          {:ok, pid}

        {:error, reason} ->
          # Cleanup on failure - unregister from SessionRegistry
          SessionRegistry.unregister(session.id)
          {:error, reason}
      end
    end
  end

  @doc """
  Stops a session by its ID.

  Performs the following steps:
  1. Finds the session's supervisor pid via Registry lookup
  2. Terminates the supervisor child
  3. Unregisters the session from SessionRegistry

  ## Parameters

  - `session_id` - The session's unique ID

  ## Returns

  - `:ok` - Session stopped successfully
  - `{:error, :not_found}` - No session with this ID exists

  ## Note on Registry Cleanup

  The session is unregistered from SessionRegistry synchronously, but the
  SessionProcessRegistry entry persists until the process fully terminates.
  Use `session_running?/1` if you need to verify the process is alive.

  ## Examples

      iex> :ok = SessionSupervisor.stop_session("session-id")
  """
  @spec stop_session(String.t()) :: :ok | {:error, :not_found}
  def stop_session(session_id) do
    # Save session before stopping (best effort - doesn't block close)
    save_session_before_close(session_id)

    # Then stop processes
    with {:ok, pid} <- find_session_pid(session_id),
         :ok <- DynamicSupervisor.terminate_child(__MODULE__, pid) do
      SessionRegistry.unregister(session_id)
      :ok
    end
  end

  # Saves session state before closing. Best-effort - failures are logged but
  # don't prevent the session from being closed.
  defp save_session_before_close(session_id) do
    case Persistence.save(session_id) do
      {:ok, path} ->
        Logger.info("Session #{session_id} saved to #{path}")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to save session #{session_id}: #{inspect(reason)}")
        :error
    end
  end

  # ============================================================================
  # Session Process Lookup (Task 1.3.3)
  # ============================================================================

  @doc """
  Finds the pid of a session's supervisor by session ID.

  Uses Registry lookup with `{:session, session_id}` key for O(1) performance.

  ## Parameters

  - `session_id` - The session's unique ID

  ## Returns

  - `{:ok, pid}` - Session supervisor found
  - `{:error, :not_found}` - No session with this ID exists

  ## Examples

      iex> {:ok, pid} = SessionSupervisor.find_session_pid("session-id")
      iex> is_pid(pid)
      true

      iex> SessionSupervisor.find_session_pid("unknown")
      {:error, :not_found}
  """
  @spec find_session_pid(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def find_session_pid(session_id) do
    case Registry.lookup(@registry, {:session, session_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Returns a list of all running session supervisor pids.

  Uses `DynamicSupervisor.which_children/1` to enumerate all child processes.

  ## Returns

  A list of pids for all running session supervisors. Returns an empty list
  if no sessions are running.

  ## Examples

      iex> SessionSupervisor.list_session_pids()
      []

      iex> {:ok, _} = SessionSupervisor.start_session(session)
      iex> pids = SessionSupervisor.list_session_pids()
      iex> length(pids)
      1
  """
  @spec list_session_pids() :: [pid()]
  def list_session_pids do
    for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(__MODULE__),
        is_pid(pid),
        do: pid
  end

  @doc """
  Checks if a session's processes are running.

  Combines Registry lookup with process liveness check.

  ## Parameters

  - `session_id` - The session's unique ID

  ## Returns

  - `true` - Session supervisor is registered and alive
  - `false` - Session not found or process is dead

  ## Examples

      iex> {:ok, _} = SessionSupervisor.start_session(session)
      iex> SessionSupervisor.session_running?(session.id)
      true

      iex> SessionSupervisor.session_running?("unknown")
      false
  """
  @spec session_running?(String.t()) :: boolean()
  def session_running?(session_id) do
    case find_session_pid(session_id) do
      {:ok, pid} -> Process.alive?(pid)
      {:error, :not_found} -> false
    end
  end

  # ============================================================================
  # Session Creation Convenience (Task 1.3.4)
  # ============================================================================

  @doc """
  Creates and starts a new session in one step.

  Convenience function that combines `Session.new/1` and `start_session/1`.
  This is the recommended way to create sessions as it handles both creation
  and startup in a single call.

  ## Parameters

  - `opts` - Keyword options passed to `Session.new/1`:
    - `:project_path` (required) - Absolute path to the project directory
    - `:name` (optional) - Display name, defaults to folder name
    - `:config` (optional) - LLM config, defaults to global settings
    - `:supervisor_module` (optional) - Module for per-session supervisor
      (default: `JidoCode.Session.Supervisor`, used for testing)

  ## Returns

  - `{:ok, session}` - Session created and started successfully
  - `{:error, reason}` - Creation or startup failed

  ## Error Reasons

  From `Session.new/1`:
  - `{:error, :path_not_found}` - Project path doesn't exist
  - `{:error, :path_not_directory}` - Path exists but is not a directory

  From `start_session/1`:
  - `{:error, :session_limit_reached}` - Maximum sessions already registered
  - `{:error, :session_exists}` - Session with this ID already exists
  - `{:error, :project_already_open}` - Session for this project path exists

  ## Examples

      iex> {:ok, session} = SessionSupervisor.create_session(project_path: "/tmp/project")
      iex> session.name
      "project"

      iex> {:ok, session} = SessionSupervisor.create_session(
      ...>   project_path: "/tmp/project",
      ...>   name: "my-project"
      ...> )
      iex> session.name
      "my-project"
  """
  @spec create_session(keyword()) :: {:ok, Session.t()} | {:error, term()}
  def create_session(opts) do
    supervisor_module = Keyword.get(opts, :supervisor_module, JidoCode.Session.Supervisor)
    session_opts = Keyword.delete(opts, :supervisor_module)

    with {:ok, session} <- Session.new(session_opts),
         {:ok, _pid} <- start_session(session, supervisor_module: supervisor_module) do
      {:ok, session}
    end
  end
end

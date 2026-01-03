defmodule JidoCode.Session.Supervisor do
  @moduledoc """
  Per-session supervisor that manages session-specific processes.

  Each session gets its own supervisor that manages child processes like
  Session.Manager and Session.State. This supervisor is started as a child
  of the main SessionSupervisor (DynamicSupervisor).

  ## Architecture

  ```
  SessionSupervisor (DynamicSupervisor)
  └── Session.Supervisor (this module)
      ├── Session.Manager
      ├── Session.State
      └── LLMAgent (registered as {:agent, session_id})
  ```

  ## Registry

  Each Session.Supervisor registers in `JidoCode.SessionProcessRegistry` with
  the key `{:session, session_id}`. This allows O(1) lookup of session
  supervisors by session ID.

  ## Strategy

  Uses `:one_for_all` strategy because session children are tightly coupled:
  - If Manager crashes, State should restart to ensure consistency
  - If State crashes, Manager needs fresh state
  - All children share the same session context

  ## Usage

  Typically started via SessionSupervisor.start_session/1:

      {:ok, session} = Session.new(project_path: "/tmp/project")
      {:ok, pid} = SessionSupervisor.start_session(session)

  Direct usage (for testing):

      {:ok, pid} = Session.Supervisor.start_link(session: session)
  """

  use Supervisor

  require Logger

  alias JidoCode.Agents.LLMAgent
  alias JidoCode.Session
  alias JidoCode.Session.ProcessRegistry

  @doc """
  Starts a per-session supervisor.

  ## Options

  - `:session` - (required) The `Session` struct for this session

  ## Returns

  - `{:ok, pid}` - Supervisor started successfully
  - `{:error, reason}` - Failed to start

  ## Examples

      iex> {:ok, session} = Session.new(project_path: "/tmp/project")
      iex> {:ok, pid} = Session.Supervisor.start_link(session: session)
      iex> is_pid(pid)
      true
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    session = Keyword.fetch!(opts, :session)
    Supervisor.start_link(__MODULE__, session, name: ProcessRegistry.via(:session, session.id))
  end

  @doc """
  Returns the child specification for this supervisor.

  This is used by DynamicSupervisor.start_child/2 when starting session
  supervisors from SessionSupervisor.

  ## Options

  - `:session` - (required) The `Session` struct

  ## Returns

  A child spec map with:
  - `id`: `{:session_supervisor, session_id}`
  - `start`: Module, function, and args for starting
  - `type`: `:supervisor`
  - `restart`: `:temporary` (sessions don't auto-restart)
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    session = Keyword.fetch!(opts, :session)

    %{
      id: {:session_supervisor, session.id},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :temporary
    }
  end

  @doc false
  @impl true
  def init(%Session{} = session) do
    # Session children - all register in SessionProcessRegistry for lookup
    # Manager: handles session coordination and lifecycle
    # State: manages conversation history, tool context, settings
    #
    # NOTE: LLMAgent is NOT started here - it's started lazily via start_agent/1
    # when credentials are available. This allows sessions to exist without
    # a working LLM connection.
    #
    # Strategy: :one_for_one because Manager and State are independent.
    # LLMAgent will be added dynamically later.
    children = [
      {JidoCode.Session.Manager, session: session},
      {JidoCode.Session.State, session: session}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Build child spec for LLMAgent from session config
  # The agent is started with session_id for registry naming and LLM config
  defp agent_child_spec(%Session{} = session) do
    config = session.config

    # Convert string provider to atom for LLMAgent
    # Session stores provider as string, LLMAgent expects atom
    # Using to_atom since provider names come from a known set (anthropic, openai, ollama, etc.)
    provider =
      cond do
        is_atom(config.provider) -> config.provider
        is_binary(config.provider) -> String.to_atom(config.provider)
        true -> :anthropic
      end

    opts = [
      session_id: session.id,
      provider: provider,
      model: config.model,
      temperature: config.temperature,
      max_tokens: config.max_tokens,
      name: LLMAgent.via(session.id)
    ]

    {LLMAgent, opts}
  end

  # ============================================================================
  # LLM Agent Lifecycle (Lazy Start)
  # ============================================================================

  @doc """
  Starts the LLM agent for a session.

  The agent is started as a child of the session's supervisor. This allows
  sessions to exist without an LLM agent and start it later when credentials
  are available.

  ## Parameters

  - `session` - The Session struct with config

  ## Returns

  - `{:ok, pid}` - Agent started successfully
  - `{:error, :already_started}` - Agent is already running
  - `{:error, reason}` - Failed to start agent

  ## Examples

      iex> {:ok, pid} = Session.Supervisor.start_agent(session)
      iex> is_pid(pid)
      true
  """
  @spec start_agent(Session.t()) :: {:ok, pid()} | {:error, term()}
  def start_agent(%Session{} = session) do
    case ProcessRegistry.lookup(:session, session.id) do
      {:ok, supervisor_pid} ->
        if agent_running?(session.id) do
          {:error, :already_started}
        else
          spec = agent_child_spec(session)

          case Supervisor.start_child(supervisor_pid, spec) do
            {:ok, pid} -> {:ok, pid}
            {:ok, pid, _info} -> {:ok, pid}
            {:error, {:already_started, pid}} -> {:ok, pid}
            {:error, reason} -> {:error, reason}
          end
        end

      {:error, :not_found} ->
        {:error, :session_not_found}
    end
  end

  @doc """
  Stops the LLM agent for a session.

  ## Parameters

  - `session_id` - The session's unique ID

  ## Returns

  - `:ok` - Agent stopped successfully
  - `{:error, :not_running}` - Agent was not running
  - `{:error, :session_not_found}` - Session doesn't exist
  """
  @spec stop_agent(String.t()) :: :ok | {:error, term()}
  def stop_agent(session_id) when is_binary(session_id) do
    case ProcessRegistry.lookup(:session, session_id) do
      {:ok, supervisor_pid} ->
        case ProcessRegistry.lookup(:agent, session_id) do
          {:ok, _agent_pid} ->
            # Terminate the agent child
            Supervisor.terminate_child(supervisor_pid, LLMAgent)
            Supervisor.delete_child(supervisor_pid, LLMAgent)
            :ok

          {:error, :not_found} ->
            {:error, :not_running}
        end

      {:error, :not_found} ->
        {:error, :session_not_found}
    end
  end

  @doc """
  Checks if the LLM agent is running for a session.

  ## Parameters

  - `session_id` - The session's unique ID

  ## Returns

  - `true` if agent is running
  - `false` if agent is not running or session doesn't exist

  ## Examples

      iex> Session.Supervisor.agent_running?(session.id)
      true
  """
  @spec agent_running?(String.t()) :: boolean()
  def agent_running?(session_id) when is_binary(session_id) do
    case ProcessRegistry.lookup(:agent, session_id) do
      {:ok, pid} -> Process.alive?(pid)
      {:error, :not_found} -> false
    end
  end

  # ============================================================================
  # Session Process Access (Task 1.4.3)
  # ============================================================================

  @doc """
  Gets the Manager pid for a session.

  Uses Registry lookup with `{:manager, session_id}` key for O(1) performance.

  ## Parameters

  - `session_id` - The session's unique ID

  ## Returns

  - `{:ok, pid}` - Manager found
  - `{:error, :not_found}` - No Manager for this session

  ## Examples

      iex> {:ok, pid} = Session.Supervisor.get_manager(session.id)
      iex> is_pid(pid)
      true

      iex> Session.Supervisor.get_manager("unknown")
      {:error, :not_found}
  """
  @spec get_manager(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def get_manager(session_id) when is_binary(session_id) do
    ProcessRegistry.lookup(:manager, session_id)
  end

  @doc """
  Gets the State pid for a session.

  Uses Registry lookup with `{:state, session_id}` key for O(1) performance.

  ## Parameters

  - `session_id` - The session's unique ID

  ## Returns

  - `{:ok, pid}` - State found
  - `{:error, :not_found}` - No State for this session

  ## Examples

      iex> {:ok, pid} = Session.Supervisor.get_state(session.id)
      iex> is_pid(pid)
      true

      iex> Session.Supervisor.get_state("unknown")
      {:error, :not_found}
  """
  @spec get_state(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def get_state(session_id) when is_binary(session_id) do
    ProcessRegistry.lookup(:state, session_id)
  end

  @doc """
  Gets the LLMAgent pid for a session.

  Uses Registry lookup with `{:agent, session_id}` key for O(1) performance.
  The agent must be started with `name: LLMAgent.via(session_id)` to be
  found via this lookup.

  ## Parameters

  - `session_id` - The session's unique ID

  ## Returns

  - `{:ok, pid}` - Agent found
  - `{:error, :not_found}` - No Agent for this session

  ## Examples

      iex> {:ok, pid} = Session.Supervisor.get_agent(session.id)
      iex> is_pid(pid)
      true

      iex> Session.Supervisor.get_agent("unknown")
      {:error, :not_found}
  """
  @spec get_agent(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def get_agent(session_id) when is_binary(session_id) do
    ProcessRegistry.lookup(:agent, session_id)
  end
end

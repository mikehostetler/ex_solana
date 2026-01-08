defmodule JidoFlame.Owner do
  @moduledoc """
  GenServer that owns the FLAME link to a remote child process.

  The Owner pattern decouples Jido agent lifetime from remote work lifetime.
  When a parent agent restarts, the Owner continues to maintain the FLAME
  link to the remote child. The agent can reconnect to its children via
  the AgentRegistry and ChildRegistry.

  ## Lifecycle

  1. Started by `start_child/5` under JidoFlame.OwnerSupervisor
  2. Calls `FLAME.place_child/3` to spawn the remote process
  3. Monitors the remote child and forwards signals to the parent
  4. Terminates when the remote child exits or when explicitly stopped

  ## Signal Flow

  Remote children can send signals to their parent via:

      send(owner_pid, {:remote_child_signal, signal_data})

  The Owner looks up the parent in AgentRegistry and forwards the signal.
  """

  use GenServer
  require Logger

  alias JidoFlame.{AgentRegistry, ChildRegistry}

  defstruct [
    :logical_agent_id,
    :tag,
    :pool,
    :flame_opts,
    :child_spec,
    :child_pid,
    :child_ref,
    :node,
    :meta,
    :started_at
  ]

  @type t :: %__MODULE__{
          logical_agent_id: term(),
          tag: term(),
          pool: atom(),
          flame_opts: keyword(),
          child_spec: term(),
          child_pid: pid() | nil,
          child_ref: reference() | nil,
          node: node() | nil,
          meta: map(),
          started_at: DateTime.t() | nil
        }

  # Client API

  @doc """
  Starts an Owner process that will spawn a remote child via FLAME.

  ## Parameters

  - `logical_agent_id` - The logical ID of the parent agent
  - `tag` - Unique tag for this child under the parent
  - `child_spec` - Child specification for the remote process
  - `pool` - FLAME pool name
  - `opts` - Options including:
    - `:flame_opts` - Options passed to FLAME.place_child/3
    - `:meta` - Metadata to include
    - `:supervisor` - Owner supervisor name (default: JidoFlame.OwnerSupervisor)

  ## Returns

  - `{:ok, owner_pid, child_pid}` on success
  - `{:error, reason}` on failure
  """
  @spec start_child(term(), term(), term(), atom(), keyword()) ::
          {:ok, pid(), pid()} | {:error, term()}
  def start_child(logical_agent_id, tag, child_spec, pool, opts \\ []) do
    supervisor = Keyword.get(opts, :supervisor, JidoFlame.OwnerSupervisor)

    init_args = %{
      logical_agent_id: logical_agent_id,
      tag: tag,
      child_spec: child_spec,
      pool: pool,
      flame_opts: Keyword.get(opts, :flame_opts, []),
      meta: Keyword.get(opts, :meta, %{})
    }

    case DynamicSupervisor.start_child(supervisor, {__MODULE__, init_args}) do
      {:ok, owner_pid} ->
        case get_child_pid(owner_pid) do
          {:ok, child_pid} -> {:ok, owner_pid, child_pid}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the remote child PID from an Owner.
  """
  @spec get_child_pid(pid()) :: {:ok, pid()} | {:error, term()}
  def get_child_pid(owner_pid, timeout \\ 30_000) do
    GenServer.call(owner_pid, :get_child_pid, timeout)
  end

  @doc """
  Gets the current state of an Owner.
  """
  @spec get_state(pid()) :: t()
  def get_state(owner_pid) do
    GenServer.call(owner_pid, :get_state)
  end

  @doc """
  Stops the Owner and its remote child.
  """
  @spec stop(pid(), term()) :: :ok
  def stop(owner_pid, reason \\ :normal) do
    GenServer.stop(owner_pid, reason)
  end

  @doc """
  Stops a remote child by agent ID and tag.
  """
  @spec stop_child(term(), term(), term()) :: :ok | {:error, :not_found}
  def stop_child(logical_agent_id, tag, reason \\ :normal) do
    case ChildRegistry.lookup_child(logical_agent_id, tag) do
      {:ok, owner_pid} -> stop(owner_pid, reason)
      :error -> {:error, :not_found}
    end
  end

  @doc "Child spec for supervision"
  def child_spec(init_args) do
    %{
      id: {__MODULE__, init_args.logical_agent_id, init_args.tag},
      start: {__MODULE__, :start_link, [init_args]},
      type: :worker,
      restart: :temporary
    }
  end

  @doc false
  def start_link(init_args) do
    GenServer.start_link(__MODULE__, init_args)
  end

  # Server Callbacks

  @impl true
  def init(args) do
    state = %__MODULE__{
      logical_agent_id: args.logical_agent_id,
      tag: args.tag,
      pool: args.pool,
      flame_opts: args.flame_opts,
      child_spec: args.child_spec,
      meta: args.meta,
      started_at: DateTime.utc_now()
    }

    case ChildRegistry.register_child(state.logical_agent_id, state.tag, self()) do
      :ok ->
        send(self(), :place_child)
        {:ok, state}

      {:error, :already_registered} ->
        {:stop, {:error, :already_registered}}
    end
  end

  @impl true
  def handle_info(:place_child, state) do
    case place_remote_child(state) do
      {:ok, child_pid} ->
        ref = Process.monitor(child_pid)
        node = node(child_pid)

        Logger.debug(
          "[JidoFlame.Owner] Placed child #{inspect(child_pid)} on #{node} " <>
            "for agent #{inspect(state.logical_agent_id)}, tag #{inspect(state.tag)}"
        )

        new_state = %{state | child_pid: child_pid, child_ref: ref, node: node}
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error(
          "[JidoFlame.Owner] Failed to place child for agent #{inspect(state.logical_agent_id)}: #{inspect(reason)}"
        )

        {:stop, {:placement_failed, reason}, state}
    end
  end

  @impl true
  def handle_info({:remote_child_signal, signal_data}, state) do
    case AgentRegistry.lookup(state.logical_agent_id) do
      {:ok, agent_pid} ->
        send(agent_pid, {:remote_child_signal, state.tag, signal_data})

      :error ->
        Logger.warning("[JidoFlame.Owner] Cannot forward signal - agent #{inspect(state.logical_agent_id)} not found")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, %{child_ref: ref, child_pid: pid} = state) do
    Logger.info(
      "[JidoFlame.Owner] Remote child #{inspect(pid)} for agent #{inspect(state.logical_agent_id)} " <>
        "exited with reason: #{inspect(reason)}"
    )

    case AgentRegistry.lookup(state.logical_agent_id) do
      {:ok, agent_pid} ->
        send(agent_pid, {:remote_child_down, state.tag, reason})

      :error ->
        :ok
    end

    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_child_pid, _from, %{child_pid: nil} = state) do
    {:reply, {:error, :not_ready}, state}
  end

  @impl true
  def handle_call(:get_child_pid, _from, state) do
    {:reply, {:ok, state.child_pid}, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug(
      "[JidoFlame.Owner] Terminating for agent #{inspect(state.logical_agent_id)}, " <>
        "tag #{inspect(state.tag)}, reason: #{inspect(reason)}"
    )

    ChildRegistry.unregister_child(state.logical_agent_id, state.tag)

    :ok
  end

  # Private Functions

  defp place_remote_child(state) do
    pool = state.pool
    child_spec = state.child_spec
    opts = state.flame_opts

    try do
      FLAME.place_child(pool, child_spec, opts)
    rescue
      e ->
        {:error, Exception.message(e)}
    catch
      :exit, reason ->
        {:error, {:exit, reason}}
    end
  end
end

defmodule JidoFlame.AgentRegistry do
  @moduledoc """
  Registry that maps logical agent IDs to their process PIDs.

  This registry enables remote children to find their logical parent
  agent even if the parent has restarted and has a new PID.

  ## Usage

  Jido agents should register themselves on init:

      JidoFlame.AgentRegistry.register("agent-123")

  Remote children can then look up their parent:

      {:ok, pid} = JidoFlame.AgentRegistry.lookup("agent-123")
  """

  use GenServer

  @registry_name __MODULE__

  # Client API

  @doc "Starts the AgentRegistry"
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @registry_name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers the calling process under the given logical agent ID.

  Only one process can be registered per agent ID. If the agent ID
  is already registered, returns an error.

  ## Examples

      iex> AgentRegistry.register("agent-123")
      :ok

      iex> AgentRegistry.register("agent-123")
      {:error, :already_registered}
  """
  @spec register(term(), pid()) :: :ok | {:error, :already_registered}
  def register(logical_agent_id, pid \\ self(), name \\ @registry_name) do
    GenServer.call(name, {:register, logical_agent_id, pid})
  end

  @doc """
  Looks up the PID for a logical agent ID.

  ## Examples

      iex> AgentRegistry.lookup("agent-123")
      {:ok, #PID<0.123.0>}

      iex> AgentRegistry.lookup("unknown")
      :error
  """
  @spec lookup(term()) :: {:ok, pid()} | :error
  def lookup(logical_agent_id, name \\ @registry_name) do
    GenServer.call(name, {:lookup, logical_agent_id})
  end

  @doc """
  Unregisters a logical agent ID.

  ## Examples

      iex> AgentRegistry.unregister("agent-123")
      :ok
  """
  @spec unregister(term()) :: :ok
  def unregister(logical_agent_id, name \\ @registry_name) do
    GenServer.call(name, {:unregister, logical_agent_id})
  end

  @doc """
  Lists all registered agent IDs with their PIDs.
  """
  @spec list_all() :: [{term(), pid()}]
  def list_all(name \\ @registry_name) do
    GenServer.call(name, :list_all)
  end

  @doc "Returns a child spec for supervision"
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Use ETS for efficient lookups
    table = :ets.new(:agent_registry, [:set, :protected])
    # Map of ref -> agent_id for monitoring
    refs = %{}
    {:ok, %{table: table, refs: refs}}
  end

  @impl true
  def handle_call({:register, agent_id, pid}, _from, state) do
    case :ets.lookup(state.table, agent_id) do
      [] ->
        ref = Process.monitor(pid)
        :ets.insert(state.table, {agent_id, pid, ref})
        refs = Map.put(state.refs, ref, agent_id)
        {:reply, :ok, %{state | refs: refs}}

      [{^agent_id, existing_pid, _ref}] when existing_pid == pid ->
        {:reply, :ok, state}

      _ ->
        {:reply, {:error, :already_registered}, state}
    end
  end

  @impl true
  def handle_call({:lookup, agent_id}, _from, state) do
    result =
      case :ets.lookup(state.table, agent_id) do
        [{^agent_id, pid, _ref}] -> {:ok, pid}
        [] -> :error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:unregister, agent_id}, _from, state) do
    case :ets.lookup(state.table, agent_id) do
      [{^agent_id, _pid, ref}] ->
        Process.demonitor(ref, [:flush])
        :ets.delete(state.table, agent_id)
        refs = Map.delete(state.refs, ref)
        {:reply, :ok, %{state | refs: refs}}

      [] ->
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:list_all, _from, state) do
    entries = :ets.tab2list(state.table) |> Enum.map(fn {id, pid, _ref} -> {id, pid} end)
    {:reply, entries, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.get(state.refs, ref) do
      nil ->
        {:noreply, state}

      agent_id ->
        :ets.delete(state.table, agent_id)
        refs = Map.delete(state.refs, ref)
        {:noreply, %{state | refs: refs}}
    end
  end
end

defmodule JidoFlame.ChildRegistry do
  @moduledoc """
  Registry that maps {logical_agent_id, tag} pairs to Owner process PIDs.

  This enables looking up which Owner is responsible for a specific remote child,
  and listing all remote children for a given parent agent.

  ## Usage

      # Owner registers itself
      ChildRegistry.register_child("agent-123", :worker_1, owner_pid)

      # Look up owner for a specific child
      {:ok, owner_pid} = ChildRegistry.lookup_child("agent-123", :worker_1)

      # List all owners for an agent's children
      owners = ChildRegistry.children("agent-123")
  """

  use GenServer

  @registry_name __MODULE__

  # Client API

  @doc "Starts the ChildRegistry"
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @registry_name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers an Owner for a child with the given agent ID and tag.

  ## Examples

      iex> ChildRegistry.register_child("agent-123", :worker_1, self())
      :ok
  """
  @spec register_child(term(), term(), pid()) :: :ok | {:error, :already_registered}
  def register_child(agent_id, tag, owner_pid \\ self(), name \\ @registry_name) do
    GenServer.call(name, {:register, agent_id, tag, owner_pid})
  end

  @doc """
  Looks up the Owner PID for a specific child.

  ## Examples

      iex> ChildRegistry.lookup_child("agent-123", :worker_1)
      {:ok, #PID<0.456.0>}

      iex> ChildRegistry.lookup_child("agent-123", :unknown)
      :error
  """
  @spec lookup_child(term(), term()) :: {:ok, pid()} | :error
  def lookup_child(agent_id, tag, name \\ @registry_name) do
    GenServer.call(name, {:lookup, agent_id, tag})
  end

  @doc """
  Returns all Owner PIDs for children of a given agent.

  ## Examples

      iex> ChildRegistry.children("agent-123")
      [#PID<0.456.0>, #PID<0.789.0>]
  """
  @spec children(term()) :: [pid()]
  def children(agent_id, name \\ @registry_name) do
    GenServer.call(name, {:children, agent_id})
  end

  @doc """
  Returns all {tag, owner_pid} pairs for a given agent.
  """
  @spec children_with_tags(term()) :: [{term(), pid()}]
  def children_with_tags(agent_id, name \\ @registry_name) do
    GenServer.call(name, {:children_with_tags, agent_id})
  end

  @doc """
  Unregisters a child.

  ## Examples

      iex> ChildRegistry.unregister_child("agent-123", :worker_1)
      :ok
  """
  @spec unregister_child(term(), term()) :: :ok
  def unregister_child(agent_id, tag, name \\ @registry_name) do
    GenServer.call(name, {:unregister, agent_id, tag})
  end

  @doc """
  Unregisters all children for an agent.
  """
  @spec unregister_all(term()) :: :ok
  def unregister_all(agent_id, name \\ @registry_name) do
    GenServer.call(name, {:unregister_all, agent_id})
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
    # Key: {agent_id, tag}, Value: {owner_pid, ref}
    table = :ets.new(:child_registry, [:set, :protected])
    # Map of ref -> {agent_id, tag} for monitoring
    refs = %{}
    {:ok, %{table: table, refs: refs}}
  end

  @impl true
  def handle_call({:register, agent_id, tag, owner_pid}, _from, state) do
    key = {agent_id, tag}

    case :ets.lookup(state.table, key) do
      [] ->
        ref = Process.monitor(owner_pid)
        :ets.insert(state.table, {key, owner_pid, ref})
        refs = Map.put(state.refs, ref, key)
        {:reply, :ok, %{state | refs: refs}}

      [{^key, ^owner_pid, _ref}] ->
        {:reply, :ok, state}

      _ ->
        {:reply, {:error, :already_registered}, state}
    end
  end

  @impl true
  def handle_call({:lookup, agent_id, tag}, _from, state) do
    key = {agent_id, tag}

    result =
      case :ets.lookup(state.table, key) do
        [{^key, owner_pid, _ref}] -> {:ok, owner_pid}
        [] -> :error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:children, agent_id}, _from, state) do
    # Match all entries where the first element of the key is agent_id
    pattern = {{agent_id, :_}, :"$1", :_}
    owners = :ets.match(state.table, pattern) |> List.flatten()
    {:reply, owners, state}
  end

  @impl true
  def handle_call({:children_with_tags, agent_id}, _from, state) do
    # Match and return both tag and owner_pid
    pattern = {{agent_id, :"$1"}, :"$2", :_}
    results = :ets.match(state.table, pattern) |> Enum.map(fn [tag, pid] -> {tag, pid} end)
    {:reply, results, state}
  end

  @impl true
  def handle_call({:unregister, agent_id, tag}, _from, state) do
    key = {agent_id, tag}

    case :ets.lookup(state.table, key) do
      [{^key, _pid, ref}] ->
        Process.demonitor(ref, [:flush])
        :ets.delete(state.table, key)
        refs = Map.delete(state.refs, ref)
        {:reply, :ok, %{state | refs: refs}}

      [] ->
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:unregister_all, agent_id}, _from, state) do
    # Find all children for this agent
    pattern = {{agent_id, :_}, :_, :"$1"}
    refs_to_remove = :ets.match(state.table, pattern) |> List.flatten()

    # Demonitor and delete
    Enum.each(refs_to_remove, fn ref ->
      Process.demonitor(ref, [:flush])
    end)

    # Delete from table using match_delete
    :ets.match_delete(state.table, {{agent_id, :_}, :_, :_})

    # Clean up refs map
    refs = Enum.reduce(refs_to_remove, state.refs, fn ref, acc -> Map.delete(acc, ref) end)

    {:reply, :ok, %{state | refs: refs}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.get(state.refs, ref) do
      nil ->
        {:noreply, state}

      key ->
        :ets.delete(state.table, key)
        refs = Map.delete(state.refs, ref)
        {:noreply, %{state | refs: refs}}
    end
  end
end

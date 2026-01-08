defmodule JidoFlame.TestAgent do
  @moduledoc """
  A simple test agent for verifying remote spawning and communication.

  This agent is used by `mix jido.flame.doctor` and in integration tests
  to verify that remote agent spawning and parent-child communication works.

  ## Usage

  The TestAgent is designed to be spawned remotely via FLAME:

      child_spec = {JidoFlame.TestAgent, %{
        parent_ref: %{
          logical_agent_id: "agent-123",
          owner_pid: owner_pid,
          meta: %{test: true}
        }
      }}

      {:ok, pid} = FLAME.place_child(MyPool, child_spec)

  ## Signals to Parent

  The TestAgent can send signals to its parent:

      JidoFlame.TestAgent.emit_to_parent(pid, "test.completed", %{result: :success})

  ## State

  The agent maintains simple state for testing:

      JidoFlame.TestAgent.get_state(pid)
      #=> %{parent_ref: %{...}, started_at: ~U[...], data: %{}}
  """

  use GenServer
  require Logger

  defstruct [:parent_ref, :started_at, :data]

  @type t :: %__MODULE__{
          parent_ref: map() | nil,
          started_at: DateTime.t(),
          data: map()
        }

  # Client API

  @doc "Starts the TestAgent"
  def start_link(opts) when is_map(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def start_link(opts) when is_list(opts) do
    start_link(Map.new(opts))
  end

  @doc "Returns a child spec for supervision/FLAME placement"
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :temporary
    }
  end

  @doc """
  Gets the current state of the TestAgent.
  """
  @spec get_state(pid()) :: t()
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Updates the data map in the agent's state.
  """
  @spec put_data(pid(), term(), term()) :: :ok
  def put_data(pid, key, value) do
    GenServer.call(pid, {:put_data, key, value})
  end

  @doc """
  Gets a value from the data map.
  """
  @spec get_data(pid(), term()) :: term()
  def get_data(pid, key) do
    GenServer.call(pid, {:get_data, key})
  end

  @doc """
  Sends a signal to the parent agent via the Owner.

  ## Parameters

  - `pid` - The TestAgent process
  - `type` - Signal type (e.g., "test.completed")
  - `data` - Signal data map

  ## Example

      emit_to_parent(pid, "test.completed", %{result: :success})
  """
  @spec emit_to_parent(pid(), String.t(), map()) :: :ok
  def emit_to_parent(pid, type, data) do
    GenServer.cast(pid, {:emit_to_parent, type, data})
  end

  @doc """
  Ping the agent to verify it's alive.
  """
  @spec ping(pid()) :: :pong
  def ping(pid) do
    GenServer.call(pid, :ping)
  end

  @doc """
  Returns info about the current node and process.
  """
  @spec node_info(pid()) :: map()
  def node_info(pid) do
    GenServer.call(pid, :node_info)
  end

  @doc """
  Executes a function and returns the result.
  Useful for testing remote execution.
  """
  @spec execute(pid(), (-> term())) :: term()
  def execute(pid, fun) when is_function(fun, 0) do
    GenServer.call(pid, {:execute, fun})
  end

  @doc """
  Stops the TestAgent with the given reason.
  """
  @spec stop(pid(), term()) :: :ok
  def stop(pid, reason \\ :normal) do
    GenServer.stop(pid, reason)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    parent_ref = Map.get(opts, :parent_ref)

    state = %__MODULE__{
      parent_ref: parent_ref,
      started_at: DateTime.utc_now(),
      data: Map.get(opts, :initial_data, %{})
    }

    Logger.debug("[JidoFlame.TestAgent] Started on #{node()}, parent: #{inspect(parent_ref)}")

    if parent_ref && parent_ref[:owner_pid] do
      signal = %{
        type: "jido.flame.test_agent.started",
        source: inspect(self()),
        data: %{
          node: node(),
          pid: self(),
          started_at: state.started_at
        }
      }

      send(parent_ref.owner_pid, {:remote_child_signal, signal})
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:put_data, key, value}, _from, state) do
    new_data = Map.put(state.data, key, value)
    {:reply, :ok, %{state | data: new_data}}
  end

  @impl true
  def handle_call({:get_data, key}, _from, state) do
    {:reply, Map.get(state.data, key), state}
  end

  @impl true
  def handle_call(:ping, _from, state) do
    {:reply, :pong, state}
  end

  @impl true
  def handle_call(:node_info, _from, state) do
    info = %{
      node: node(),
      pid: self(),
      uptime_ms: DateTime.diff(DateTime.utc_now(), state.started_at, :millisecond),
      parent_ref: state.parent_ref,
      flame_parent: FLAME.Parent.get()
    }

    {:reply, info, state}
  end

  @impl true
  def handle_call({:execute, fun}, _from, state) do
    result = fun.()
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:emit_to_parent, type, data}, state) do
    if state.parent_ref && state.parent_ref[:owner_pid] do
      signal = %{
        type: type,
        source: inspect(self()),
        data: data
      }

      send(state.parent_ref.owner_pid, {:remote_child_signal, signal})
    else
      Logger.warning("[JidoFlame.TestAgent] No owner_pid to emit to")
    end

    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("[JidoFlame.TestAgent] Terminating with reason: #{inspect(reason)}")

    if state.parent_ref && state.parent_ref[:owner_pid] do
      signal = %{
        type: "jido.flame.test_agent.stopped",
        source: inspect(self()),
        data: %{
          node: node(),
          reason: reason
        }
      }

      send(state.parent_ref.owner_pid, {:remote_child_signal, signal})
    end

    :ok
  end
end

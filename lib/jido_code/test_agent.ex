defmodule JidoCode.TestAgent do
  @moduledoc """
  A simple GenServer agent for testing AgentSupervisor lifecycle management.

  This agent supports basic operations for testing:
  - Normal operation and state management
  - Crash simulation for restart testing
  - Graceful shutdown

  ## Usage

      # Start via AgentSupervisor
      {:ok, pid} = JidoCode.AgentSupervisor.start_agent(%{
        name: :test_agent,
        module: JidoCode.TestAgent,
        args: []
      })

      # Get state
      JidoCode.TestAgent.get_state(pid)

      # Simulate crash (for testing restart behavior)
      JidoCode.TestAgent.crash(pid)
  """

  use GenServer

  # Client API

  @doc """
  Starts the TestAgent with the given options.

  Options:
  - `:name` - Optional name for registration (handled by AgentSupervisor)
  - `:initial_state` - Initial state value (default: %{})
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    initial_state = Keyword.get(opts, :initial_state, %{started_at: DateTime.utc_now()})
    name = Keyword.get(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, initial_state, name: name)
    else
      GenServer.start_link(__MODULE__, initial_state)
    end
  end

  @doc """
  Returns the current state of the agent.
  """
  @spec get_state(GenServer.server()) :: term()
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Updates the agent state with the given value.
  """
  @spec set_state(GenServer.server(), term()) :: :ok
  def set_state(pid, new_state) do
    GenServer.call(pid, {:set_state, new_state})
  end

  @doc """
  Causes the agent to crash. Used for testing restart behavior.
  """
  @spec crash(GenServer.server()) :: :ok
  def crash(pid) do
    GenServer.cast(pid, :crash)
  end

  @doc """
  Requests a normal shutdown. Agent will exit with :normal reason.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(pid) do
    GenServer.stop(pid, :normal)
  end

  # Server Callbacks

  @impl true
  def init(initial_state) do
    {:ok, initial_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:set_state, new_state}, _from, _state) do
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast(:crash, _state) do
    raise "Intentional crash for testing"
  end
end

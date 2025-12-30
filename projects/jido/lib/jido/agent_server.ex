defmodule Jido.AgentServer do
  @moduledoc """
  GenServer runtime wrapper around a pure `Jido.Agent` struct.

  AgentServer is the "Act" side of the Jido framework: while Agents "think" 
  (pure decision logic via `handle_signal/2` or `cmd/2`), AgentServer "acts"
  by executing the directives they emit.

  ## Responsibilities

  - Hold a `%Jido.Agent{}` struct as process state
  - Accept `Jido.Signal.t()` as the message envelope via `handle_signal/2`
  - Delegate pure logic to the Agent module
  - Interpret and execute `Jido.Agent.Directive` side effects

  ## Usage

      # Start an agent server
      {:ok, pid} = Jido.AgentServer.start_link(MyAgent, name: :my_agent)

      # Send a signal to the agent
      signal = Jido.Signal.new!("user.action", %{action: "click"}, source: "/ui")
      Jido.AgentServer.handle_signal(pid, signal)

      # Get current agent state
      agent = Jido.AgentServer.get_agent(pid)

  ## Signal Flow

  ```
  Signal → AgentServer.handle_signal/2 
        → Agent.handle_signal/2 (or cmd/2)
        → {agent, directives}
        → AgentServer executes directives
  ```

  ## Directives

  AgentServer interprets these built-in directives:

  - `%Directive.Emit{}` - Dispatch a signal via `Jido.Signal.Dispatch`
  - `%Directive.Error{}` - Log/handle an error
  - `%Directive.Spawn{}` - Spawn a child process
  - `%Directive.Schedule{}` - Schedule a delayed message
  - `%Directive.Stop{}` - Stop the agent process

  Custom directives are logged and ignored by default.
  """

  use GenServer

  require Logger

  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.Signal

  @type agent_module :: module()

  @type start_opts :: [
          name: GenServer.name(),
          agent: Agent.t(),
          agent_opts: keyword() | map(),
          default_dispatch: term(),
          children_supervisor: pid(),
          spawn_fun: (term() -> term())
        ]

  @type state :: %{
          agent_module: agent_module(),
          agent: Agent.t(),
          default_dispatch: term(),
          children_supervisor: pid() | nil,
          spawn_fun: (term() -> term()) | nil
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts an AgentServer linked to the current process.

  ## Options

  - `:name` - GenServer name registration
  - `:agent` - Pre-built `%Jido.Agent{}` struct (optional)
  - `:agent_opts` - Options passed to `agent_module.new/1` if `:agent` not provided
  - `:default_dispatch` - Default dispatch config for `%Emit{}` directives
  - `:children_supervisor` - DynamicSupervisor for `%Spawn{}` directives
  - `:spawn_fun` - Custom function for spawning (fn child_spec -> result)

  ## Examples

      {:ok, pid} = Jido.AgentServer.start_link(MyAgent)
      {:ok, pid} = Jido.AgentServer.start_link(MyAgent, name: :my_agent)
      {:ok, pid} = Jido.AgentServer.start_link(MyAgent, agent_opts: [id: "custom-123"])
  """
  @spec start_link(agent_module(), start_opts()) :: GenServer.on_start()
  def start_link(agent_module, opts \\ []) when is_atom(agent_module) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, {agent_module, opts}, name: name)
  end

  @doc """
  Asynchronously deliver a Signal to the agent process.

  This is the main entrypoint for agent interaction. Signals are processed
  asynchronously - the caller does not wait for processing to complete.

  ## Examples

      signal = Jido.Signal.new!("user.created", %{id: 123}, source: "/auth")
      :ok = Jido.AgentServer.handle_signal(pid, signal)
  """
  @spec handle_signal(GenServer.server(), Signal.t()) :: :ok
  def handle_signal(server, %Signal{} = signal) do
    GenServer.cast(server, {:signal, signal})
  end

  @doc """
  Synchronously deliver a Signal and wait for processing to complete.

  Returns the updated agent struct after the signal has been processed.
  Useful for testing or when you need confirmation of processing.

  ## Examples

      {:ok, agent} = Jido.AgentServer.handle_signal_sync(pid, signal)
      {:ok, agent} = Jido.AgentServer.handle_signal_sync(pid, signal, 10_000)
  """
  @spec handle_signal_sync(GenServer.server(), Signal.t(), timeout()) ::
          {:ok, Agent.t()} | {:error, term()}
  def handle_signal_sync(server, %Signal{} = signal, timeout \\ 5_000) do
    GenServer.call(server, {:signal, signal}, timeout)
  end

  @doc """
  Get a read-only snapshot of the current agent struct.

  ## Examples

      agent = Jido.AgentServer.get_agent(pid)
      IO.inspect(agent.state)
  """
  @spec get_agent(GenServer.server()) :: Agent.t()
  def get_agent(server) do
    GenServer.call(server, :get_agent)
  end

  @doc """
  Check if the agent server process is alive.
  """
  @spec alive?(GenServer.server()) :: boolean()
  def alive?(server) when is_pid(server), do: Process.alive?(server)
  def alive?(server), do: GenServer.whereis(server) != nil

  # ---------------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init({agent_module, opts}) do
    agent =
      case Keyword.fetch(opts, :agent) do
        {:ok, %{__struct__: _} = agent} ->
          agent

        :error ->
          init_opts = Keyword.get(opts, :agent_opts, [])
          agent_module.new(init_opts)
      end

    state = %{
      agent_module: agent_module,
      agent: agent,
      default_dispatch: Keyword.get(opts, :default_dispatch),
      children_supervisor: Keyword.get(opts, :children_supervisor),
      spawn_fun: Keyword.get(opts, :spawn_fun)
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:signal, %Signal{} = signal}, state) do
    {new_state, stop_reason} = process_signal(signal, state)

    case stop_reason do
      nil -> {:noreply, new_state}
      reason -> {:stop, reason, new_state}
    end
  end

  @impl true
  def handle_call({:signal, %Signal{} = signal}, _from, state) do
    {new_state, stop_reason} = process_signal(signal, state)
    reply = {:ok, new_state.agent}

    case stop_reason do
      nil -> {:reply, reply, new_state}
      reason -> {:stop, reason, reply, new_state}
    end
  end

  def handle_call(:get_agent, _from, state) do
    {:reply, state.agent, state}
  end

  @impl true
  def handle_info({:jido_schedule, %Signal{} = signal}, state) do
    {new_state, stop_reason} = process_signal(signal, state)

    case stop_reason do
      nil -> {:noreply, new_state}
      reason -> {:stop, reason, new_state}
    end
  end

  def handle_info({:jido_schedule, message}, state) do
    {new_state, stop_reason} = process_action(message, state)

    case stop_reason do
      nil -> {:noreply, new_state}
      reason -> {:stop, reason, new_state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("Jido.AgentServer ignoring unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Internal: Signal Processing
  # ---------------------------------------------------------------------------

  defp process_signal(%Signal{} = signal, state) do
    {agent, directives} = delegate_to_agent(state.agent_module, state.agent, signal)
    state = %{state | agent: agent}
    execute_directives(directives, state)
  end

  defp process_action(action, state) do
    {agent, directives} = state.agent_module.cmd(state.agent, action)
    state = %{state | agent: agent}
    execute_directives(directives, state)
  end

  defp delegate_to_agent(agent_module, agent, %Signal{} = signal) do
    if function_exported?(agent_module, :handle_signal, 2) do
      agent_module.handle_signal(agent, signal)
    else
      agent_module.cmd(agent, signal)
    end
  end

  # ---------------------------------------------------------------------------
  # Internal: Directive Execution
  # ---------------------------------------------------------------------------

  defp execute_directives(directives, state) when is_list(directives) do
    Enum.reduce_while(directives, {state, nil}, fn directive, {acc_state, _} ->
      case execute_directive(directive, acc_state) do
        {:ok, new_state} ->
          {:cont, {new_state, nil}}

        {:stop, reason, new_state} ->
          {:halt, {new_state, reason}}
      end
    end)
  end

  defp execute_directives(directive, state) do
    execute_directives([directive], state)
  end

  defp execute_directive(%Directive.Emit{} = emit, state) do
    dispatch_cfg = emit.dispatch || state.default_dispatch

    case dispatch_cfg do
      nil ->
        Logger.debug("Emit directive with no dispatch config: #{inspect(emit.signal)}")

      cfg ->
        if Code.ensure_loaded?(Jido.Signal.Dispatch) do
          Jido.Signal.Dispatch.dispatch(emit.signal, cfg)
        else
          Logger.warning("Jido.Signal.Dispatch not available, skipping emit")
        end
    end

    {:ok, state}
  end

  defp execute_directive(%Directive.Error{} = error, state) do
    Logger.error("""
    Agent error (context: #{inspect(error.context)}):
    #{inspect(error.error)}
    """)

    {:ok, state}
  end

  defp execute_directive(%Directive.Spawn{} = spawn_directive, state) do
    result =
      cond do
        is_function(state.spawn_fun, 1) ->
          state.spawn_fun.(spawn_directive.child_spec)

        state.children_supervisor != nil ->
          DynamicSupervisor.start_child(
            state.children_supervisor,
            spawn_directive.child_spec
          )

        true ->
          Logger.warning("""
          Spawn directive received but no :children_supervisor or :spawn_fun configured.
          child_spec: #{inspect(spawn_directive.child_spec)}
          """)

          :ignored
      end

    Logger.debug("Spawn directive result: #{inspect(result)}")
    {:ok, state}
  end

  defp execute_directive(%Directive.Schedule{} = schedule, state) do
    Process.send_after(self(), {:jido_schedule, schedule.message}, schedule.delay_ms)
    {:ok, state}
  end

  defp execute_directive(%Directive.Stop{} = stop, state) do
    {:stop, stop.reason, state}
  end

  defp execute_directive(directive, state) do
    Logger.debug("Ignoring unknown directive: #{inspect(directive)}")
    {:ok, state}
  end
end

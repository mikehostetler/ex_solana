defmodule Jido.AgentServer do
  @moduledoc """
  GenServer runtime for Jido agents.

  AgentServer is the "Act" side of the Jido framework: while Agents "think"
  (pure decision logic via `handle_signal/2` or `cmd/2`), AgentServer "acts"
  by executing the directives they emit.

  ## Architecture

  - Single GenServer per agent under `Jido.AgentSupervisor`
  - Internal directive queue with drain loop for non-blocking processing
  - Registry-based naming via `Jido.Registry`
  - Logical parent-child hierarchy via state tracking + monitors

  ## Public API

  - `start/1` - Start under DynamicSupervisor
  - `start_link/1` - Start linked to caller
  - `call/3` - Synchronous signal processing
  - `cast/2` - Asynchronous signal processing
  - `state/1` - Get full State struct
  - `whereis/2` - Registry lookup by ID

  ## Signal Flow

  ```
  Signal → AgentServer.call/cast
        → Agent.handle_signal/2 (or cmd/2)
        → {agent, directives}
        → Directives queued
        → Drain loop executes via DirectiveExec protocol
  ```

  ## Options

  - `:agent` - Agent module or struct (required)
  - `:id` - Instance ID (auto-generated if not provided)
  - `:initial_state` - Initial state map for agent
  - `:registry` - Registry module (default: `Jido.Registry`)
  - `:default_dispatch` - Default dispatch config for Emit directives
  - `:error_policy` - Error handling policy
  - `:max_queue_size` - Max directive queue size (default: 10_000)
  - `:parent` - Parent reference for hierarchy
  - `:on_parent_death` - Behavior when parent dies (`:stop`, `:continue`, `:emit_orphan`)
  - `:spawn_fun` - Custom function for spawning children

  ## Completion Detection

  Agents signal completion via **state**, not process death:

      # In your strategy/agent, set terminal status:
      agent = put_in(agent.state.status, :completed)
      agent = put_in(agent.state.last_answer, answer)

      # External code polls for completion:
      {:ok, state} = AgentServer.state(server)
      case state.agent.state.status do
        :completed -> state.agent.state.last_answer
        :failed -> {:error, state.agent.state.error}
        _ -> :still_running
      end

  This follows Elm/Redux semantics where completion is a state concern.
  The process stays alive until explicitly stopped or supervised.

  **Do NOT** use `{:stop, ...}` from DirectiveExec for normal completion—this
  causes race conditions with async work and skips lifecycle hooks.
  See `Jido.AgentServer.DirectiveExec` for details.
  """

  use GenServer

  require Logger

  alias Jido.AgentServer.{DirectiveExec, Options, ParentRef, State}
  alias Jido.AgentServer.Signal.{ChildExit, ChildStarted, Orphaned}
  alias Jido.Signal

  @type server :: pid() | atom() | {:via, module(), term()} | String.t()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts an AgentServer under `Jido.AgentSupervisor`.

  ## Examples

      {:ok, pid} = Jido.AgentServer.start(agent: MyAgent)
      {:ok, pid} = Jido.AgentServer.start(agent: MyAgent, id: "my-agent")
  """
  @spec start(keyword() | map()) :: DynamicSupervisor.on_start_child()
  def start(opts) do
    child_spec = {__MODULE__, opts}
    DynamicSupervisor.start_child(Jido.AgentSupervisor, child_spec)
  end

  @doc """
  Starts an AgentServer linked to the calling process.

  ## Options

  See module documentation for full list of options.

  ## Examples

      {:ok, pid} = Jido.AgentServer.start_link(agent: MyAgent)
      {:ok, pid} = Jido.AgentServer.start_link(agent: MyAgent, id: "custom-123")
  """
  @spec start_link(keyword() | map()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) or is_map(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Returns a child_spec for supervision.
  """
  @spec child_spec(keyword() | map()) :: Supervisor.child_spec()
  def child_spec(opts) do
    id = opts[:id] || __MODULE__

    %{
      id: id,
      start: {__MODULE__, :start_link, [opts]},
      shutdown: 5_000,
      restart: :permanent,
      type: :worker
    }
  end

  @doc """
  Synchronously sends a signal and waits for processing.

  Returns the updated agent struct after signal processing.
  Directives are still executed asynchronously via the drain loop.

  ## Examples

      {:ok, agent} = Jido.AgentServer.call(pid, signal)
      {:ok, agent} = Jido.AgentServer.call("agent-id", signal, 10_000)
  """
  @spec call(server(), Signal.t(), timeout()) :: {:ok, struct()} | {:error, term()}
  def call(server, %Signal{} = signal, timeout \\ 5_000) do
    with {:ok, pid} <- resolve_server(server) do
      GenServer.call(pid, {:signal, signal}, timeout)
    end
  end

  @doc """
  Asynchronously sends a signal for processing.

  Returns immediately. The signal is processed in the background.

  ## Examples

      :ok = Jido.AgentServer.cast(pid, signal)
      :ok = Jido.AgentServer.cast("agent-id", signal)
  """
  @spec cast(server(), Signal.t()) :: :ok | {:error, term()}
  def cast(server, %Signal{} = signal) do
    with {:ok, pid} <- resolve_server(server) do
      GenServer.cast(pid, {:signal, signal})
    end
  end

  @doc """
  Gets the full State struct for an agent.

  ## Examples

      {:ok, state} = Jido.AgentServer.state(pid)
      {:ok, state} = Jido.AgentServer.state("agent-id")
  """
  @spec state(server()) :: {:ok, State.t()} | {:error, term()}
  def state(server) do
    with {:ok, pid} <- resolve_server(server) do
      GenServer.call(pid, :get_state)
    end
  end

  @doc """
  Looks up an agent by ID in the registry.

  ## Examples

      pid = Jido.AgentServer.whereis("agent-id")
      pid = Jido.AgentServer.whereis("agent-id", MyRegistry)
  """
  @spec whereis(String.t(), module()) :: pid() | nil
  def whereis(id, registry \\ Jido.Registry) when is_binary(id) do
    case Registry.lookup(registry, id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Returns a via tuple for Registry-based naming.

  ## Examples

      name = Jido.AgentServer.via_tuple("agent-id")
      GenServer.call(name, :get_state)
  """
  @spec via_tuple(String.t(), module()) :: {:via, Registry, {module(), String.t()}}
  def via_tuple(id, registry \\ Jido.Registry) do
    {:via, Registry, {registry, id}}
  end

  @doc """
  Check if the agent server process is alive.
  """
  @spec alive?(server()) :: boolean()
  def alive?(server) when is_pid(server), do: Process.alive?(server)

  def alive?(server) do
    case resolve_server(server) do
      {:ok, pid} -> Process.alive?(pid)
      {:error, _} -> false
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(raw_opts) do
    opts = if is_map(raw_opts), do: Map.to_list(raw_opts), else: raw_opts

    with {:ok, options} <- Options.new(opts),
         {:ok, agent_module, agent} <- resolve_agent(options),
         {:ok, state} <- State.from_options(options, agent_module, agent) do
      # Register in Registry
      Registry.register(state.registry, state.id, %{})

      # Monitor parent if present
      state = maybe_monitor_parent(state)

      {:ok, state, {:continue, :post_init}}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:post_init, state) do
    agent_module = state.agent_module

    state =
      if function_exported?(agent_module, :strategy, 0) do
        strategy = agent_module.strategy()

        strategy_opts =
          if function_exported?(agent_module, :strategy_opts, 0),
            do: agent_module.strategy_opts(),
            else: []

        ctx = %{agent_module: agent_module, strategy_opts: strategy_opts}
        {agent, directives} = strategy.init(state.agent, ctx)

        state = State.update_agent(state, agent)

        case State.enqueue_all(state, init_signal(), List.wrap(directives)) do
          {:ok, enq_state} ->
            enq_state

          {:error, :queue_overflow} ->
            Logger.warning("AgentServer #{state.id} queue overflow during strategy init")
            state
        end
      else
        state
      end

    notify_parent_of_startup(state)

    state = start_drain_if_idle(state)

    Logger.debug("AgentServer #{state.id} initialized, status: idle")
    {:noreply, State.set_status(state, :idle)}
  end

  defp init_signal do
    Signal.new!("jido.strategy.init", %{}, source: "/agent/system")
  end

  @impl true
  def handle_call({:signal, %Signal{} = signal}, _from, state) do
    case process_signal(signal, state) do
      {:ok, new_state} ->
        {:reply, {:ok, new_state.agent}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(_msg, _from, state) do
    {:reply, {:error, :unknown_call}, state}
  end

  @impl true
  def handle_cast({:signal, %Signal{} = signal}, state) do
    case process_signal(signal, state) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, _reason, new_state} -> {:noreply, new_state}
    end
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:drain, state) do
    case State.dequeue(state) do
      {:empty, s} ->
        s = %{s | processing: false}
        s = State.set_status(s, :idle)
        {:noreply, s}

      {{:value, {signal, directive}}, s1} ->
        result = exec_directive_with_telemetry(directive, signal, s1)

        case result do
          {:ok, s2} ->
            continue_draining(s2)

          {:async, _ref, s2} ->
            continue_draining(s2)

          {:stop, reason, s2} ->
            warn_if_normal_stop(reason, directive, s2)
            {:stop, reason, State.set_status(s2, :stopping)}
        end
    end
  end

  def handle_info({:scheduled_signal, %Signal{} = signal}, state) do
    case process_signal(signal, state) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, _reason, new_state} -> {:noreply, new_state}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    cond do
      match?(%{parent: %ParentRef{pid: ^pid}}, state) ->
        handle_parent_down(state, pid, reason)

      true ->
        handle_child_down(state, pid, reason)
    end
  end

  def handle_info({:signal, %Signal{} = signal}, state) do
    case process_signal(signal, state) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, _reason, new_state} -> {:noreply, new_state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("AgentServer #{state.id} terminating: #{inspect(reason)}")
    :ok
  end

  # ---------------------------------------------------------------------------
  # Internal: Signal Processing
  # ---------------------------------------------------------------------------

  defp process_signal(%Signal{} = signal, %State{} = state) do
    start_time = System.monotonic_time()
    agent_module = state.agent_module

    metadata = %{
      agent_id: state.id,
      agent_module: agent_module,
      signal_type: signal.type
    }

    emit_telemetry(
      [:jido, :agent_server, :signal, :start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      {agent, directives} =
        if function_exported?(agent_module, :handle_signal, 2) do
          agent_module.handle_signal(state.agent, signal)
        else
          agent_module.cmd(state.agent, signal)
        end

      directives = List.wrap(directives)
      state = State.update_agent(state, agent)

      emit_telemetry(
        [:jido, :agent_server, :signal, :stop],
        %{duration: System.monotonic_time() - start_time},
        Map.merge(metadata, %{directive_count: length(directives)})
      )

      case State.enqueue_all(state, signal, directives) do
        {:ok, enq_state} ->
          {:ok, start_drain_if_idle(enq_state)}

        {:error, :queue_overflow} ->
          emit_telemetry(
            [:jido, :agent_server, :queue, :overflow],
            %{queue_size: state.max_queue_size},
            metadata
          )

          Logger.warning("AgentServer #{state.id} queue overflow, dropping directives")
          {:error, :queue_overflow, state}
      end
    catch
      kind, reason ->
        emit_telemetry(
          [:jido, :agent_server, :signal, :exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, %{kind: kind, error: reason})
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  # ---------------------------------------------------------------------------
  # Internal: Drain Loop
  # ---------------------------------------------------------------------------

  defp start_drain_if_idle(%State{processing: false} = state) do
    send(self(), :drain)
    %{state | processing: true, status: :processing}
  end

  defp start_drain_if_idle(%State{} = state), do: state

  defp continue_draining(state) do
    if State.queue_empty?(state) do
      {:noreply, %{state | processing: false} |> State.set_status(:idle)}
    else
      send(self(), :drain)
      {:noreply, %{state | processing: true, status: :processing}}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal: Agent Resolution
  # ---------------------------------------------------------------------------

  defp resolve_agent(%Options{
         agent: agent,
         agent_module: explicit_module,
         initial_state: init_state,
         id: id
       }) do
    cond do
      is_atom(agent) ->
        cond do
          function_exported?(agent, :new, 1) ->
            # new/1 accepts keyword options like [id: ..., state: ...]
            {:ok, agent, agent.new(id: id, state: init_state)}

          function_exported?(agent, :new, 0) ->
            {:ok, agent, agent.new()}

          true ->
            {:error, Jido.Error.validation_error("Agent module must implement new/0 or new/1")}
        end

      is_struct(agent) ->
        # For pre-built agents, use explicit agent_module if provided
        # Otherwise fall back to the struct module (may not work for Jido.Agent structs)
        agent_module = explicit_module || agent.__struct__
        {:ok, agent_module, agent}

      true ->
        {:error, Jido.Error.validation_error("Invalid agent")}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal: Server Resolution
  # ---------------------------------------------------------------------------

  defp resolve_server(pid) when is_pid(pid), do: {:ok, pid}

  defp resolve_server({:via, _, _} = via) do
    case GenServer.whereis(via) do
      nil -> {:error, :not_found}
      pid -> {:ok, pid}
    end
  end

  defp resolve_server(name) when is_atom(name) do
    case GenServer.whereis(name) do
      nil -> {:error, :not_found}
      pid -> {:ok, pid}
    end
  end

  defp resolve_server(id) when is_binary(id) do
    case whereis(id) do
      nil -> {:error, :not_found}
      pid -> {:ok, pid}
    end
  end

  defp resolve_server(_), do: {:error, :invalid_server}

  # ---------------------------------------------------------------------------
  # Internal: Hierarchy
  # ---------------------------------------------------------------------------

  defp maybe_monitor_parent(%State{parent: %ParentRef{pid: pid}} = state) when is_pid(pid) do
    Process.monitor(pid)
    state
  end

  defp maybe_monitor_parent(state), do: state

  defp notify_parent_of_startup(%State{parent: %ParentRef{} = parent} = state)
       when is_pid(parent.pid) do
    child_started =
      ChildStarted.new!(
        %{
          parent_id: parent.id,
          child_id: state.id,
          child_module: state.agent_module,
          tag: parent.tag,
          pid: self(),
          meta: parent.meta || %{}
        },
        source: "/agent/#{state.id}"
      )

    _ = cast(parent.pid, child_started)
    :ok
  end

  defp notify_parent_of_startup(_state), do: :ok

  defp handle_parent_down(%State{on_parent_death: :stop} = state, _pid, reason) do
    Logger.info("AgentServer #{state.id} stopping: parent died (#{inspect(reason)})")
    {:stop, {:parent_down, reason}, State.set_status(state, :stopping)}
  end

  defp handle_parent_down(%State{on_parent_death: :continue} = state, _pid, reason) do
    Logger.info("AgentServer #{state.id} continuing after parent death (#{inspect(reason)})")
    {:noreply, state}
  end

  defp handle_parent_down(%State{on_parent_death: :emit_orphan} = state, _pid, reason) do
    signal =
      Orphaned.new!(
        %{parent_id: state.parent.id, reason: reason},
        source: "/agent/#{state.id}"
      )

    case process_signal(signal, state) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, _reason, ns} -> {:noreply, ns}
    end
  end

  defp handle_child_down(%State{} = state, pid, reason) do
    {tag, state} = State.remove_child_by_pid(state, pid)

    if tag do
      Logger.debug("AgentServer #{state.id} child #{inspect(tag)} exited: #{inspect(reason)}")

      signal =
        ChildExit.new!(
          %{tag: tag, pid: pid, reason: reason},
          source: "/agent/#{state.id}"
        )

      case process_signal(signal, state) do
        {:ok, new_state} -> {:noreply, new_state}
        {:error, _reason, ns} -> {:noreply, ns}
      end
    else
      {:noreply, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal: Telemetry
  # ---------------------------------------------------------------------------

  defp exec_directive_with_telemetry(directive, signal, state) do
    start_time = System.monotonic_time()
    directive_type = directive.__struct__ |> Module.split() |> List.last()

    metadata = %{
      agent_id: state.id,
      agent_module: state.agent_module,
      directive_type: directive_type,
      signal_type: signal.type
    }

    emit_telemetry(
      [:jido, :agent_server, :directive, :start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      result = DirectiveExec.exec(directive, signal, state)

      emit_telemetry(
        [:jido, :agent_server, :directive, :stop],
        %{duration: System.monotonic_time() - start_time},
        Map.merge(metadata, %{result: result_type(result)})
      )

      result
    catch
      kind, reason ->
        emit_telemetry(
          [:jido, :agent_server, :directive, :exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, %{kind: kind, error: reason})
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp result_type({:ok, _}), do: :ok
  defp result_type({:async, _, _}), do: :async
  defp result_type({:stop, _, _}), do: :stop

  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(event, measurements, metadata)
  end

  # Warn when {:stop, ...} is used with normal-looking reasons.
  # This indicates likely misuse - normal completion should use state.status instead.
  defp warn_if_normal_stop(reason, directive, state) when reason in [:normal, :completed, :ok, :done, :success] do
    directive_type = directive.__struct__ |> Module.split() |> List.last()

    Logger.warning("""
    AgentServer #{state.id} received {:stop, #{inspect(reason)}, ...} from directive #{directive_type}.

    This is a HARD STOP: pending directives and async work will be lost, and on_after_cmd/3 will NOT run.

    For normal completion, set state.status to :completed/:failed instead and avoid returning {:stop, ...}.
    External code should poll AgentServer.state/1 and check status, not rely on process death.

    {:stop, ...} should only be used for abnormal/framework-level termination.
    """)
  end

  defp warn_if_normal_stop(_reason, _directive, _state), do: :ok
end

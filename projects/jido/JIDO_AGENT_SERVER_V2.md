# Jido AgentServer V2 Architecture

> A resilient, scalable, OTP-native runtime for hierarchical agent systems

**Version:** 2.0.0-draft  
**Last Updated:** December 2024

---

## Executive Summary

AgentServer V2 redesigns the agent runtime as a **per-instance OTP supervision tree** rather than a single GenServer. This architecture:

- **Decouples signal processing from effect execution** — eliminating the blocking bottleneck
- **Enables resilient hierarchical agents** — with proper parent-child lifecycle management
- **Provides production-grade error handling** — via configurable policies
- **Scales to hundreds of agent instances** — leveraging BEAM's process model
- **Remains extensible** — via protocols for directive execution and persistence hooks

The core principle remains: **Agents think, Servers act** — but now the "act" part is properly distributed across multiple cooperating processes.

---

## Table of Contents

1. [Design Goals](#1-design-goals)
2. [Architecture Overview](#2-architecture-overview)
3. [Global Runtime Infrastructure](#3-global-runtime-infrastructure)
4. [Per-Instance Process Hierarchy](#4-per-instance-process-hierarchy)
5. [Signal Processing Pipeline](#5-signal-processing-pipeline)
6. [Directive Execution System](#6-directive-execution-system)
7. [Hierarchical Agent Management](#7-hierarchical-agent-management)
8. [Error Handling & Policies](#8-error-handling--policies)
9. [Backpressure & Observability](#9-backpressure--observability)
10. [Event Sourcing & Persistence](#10-event-sourcing--persistence)
11. [Scaling Considerations](#11-scaling-considerations)
12. [API Reference](#12-api-reference)
13. [Migration from V1](#13-migration-from-v1)
14. [Implementation Roadmap](#14-implementation-roadmap)

---

## 1. Design Goals

### Primary Goals

| Goal | Description |
|------|-------------|
| **Non-blocking signal processing** | Signal handling must not be blocked by slow directive execution |
| **Hierarchical agents** | Parent-child relationships with lifecycle feedback and coordination |
| **Production-grade resilience** | Proper error policies, supervision, and recovery |
| **Horizontal scale** | Support 100s of agent instances per type |
| **Extensibility** | External packages can add directive executors without modifying core |

### Non-Goals (For Now)

- Cross-node clustering (future consideration)
- Exactly-once effect delivery (at-most-once is acceptable)
- Complex scheduling/prioritization across agents

### Key Constraints

1. **Sequential directive execution** — Directives for a single agent execute in order
2. **Pure agent logic** — `Jido.Agent` remains purely functional
3. **Signals as universal envelope** — All external communication via `Jido.Signal`
4. **OTP-native** — Leverage supervisors, dynamic supervisors, registries, and tasks

---

## 2. Architecture Overview

### High-Level View

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Jido.AgentRuntime                                  │
│                       (Application Supervisor)                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────┐  ┌────────────────────────┐  ┌─────────────────────┐  │
│  │  AgentRegistry   │  │ AgentInstanceSupervisor│  │ AgentTaskSupervisor │  │
│  │    (Registry)    │  │   (DynamicSupervisor)  │  │  (Task.Supervisor)  │  │
│  └──────────────────┘  └───────────┬────────────┘  └─────────────────────┘  │
│                                    │                                         │
│           ┌────────────────────────┼────────────────────────┐               │
│           │                        │                        │               │
│           ▼                        ▼                        ▼               │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐         │
│  │ AgentInstance1  │    │ AgentInstance2  │    │ AgentInstanceN  │         │
│  │   (Supervisor)  │    │   (Supervisor)  │    │   (Supervisor)  │         │
│  └────────┬────────┘    └────────┬────────┘    └────────┬────────┘         │
│           │                      │                      │                   │
└───────────┼──────────────────────┼──────────────────────┼───────────────────┘
            │                      │                      │
            ▼                      ▼                      ▼
   ┌─────────────────────────────────────────────────────────────────┐
   │              Per-Instance Process Hierarchy                      │
   │                                                                  │
   │  ┌────────────┐  ┌─────────────────┐  ┌───────────────────────┐ │
   │  │AgentServer │  │ EffectExecutor  │  │ ChildSupervisor (opt) │ │
   │  │ (GenServer)│  │   (GenServer)   │  │  (DynamicSupervisor)  │ │
   │  └────────────┘  └─────────────────┘  └───────────────────────┘ │
   └─────────────────────────────────────────────────────────────────┘
```

### Process Responsibilities

| Process | Responsibility |
|---------|----------------|
| **AgentServer** | Holds agent state, processes signals (pure), routes to runner, enqueues directives |
| **EffectExecutor** | Owns directive queue, executes directives sequentially, offloads heavy work to tasks |
| **ChildSupervisor** | Supervises spawned child agents/processes |
| **AgentTaskSupervisor** | Global pool for long-running effects (LLM calls, HTTP, etc.) |

---

## 3. Global Runtime Infrastructure

### Application Supervision Tree

```elixir
defmodule Jido.AgentRuntime do
  @moduledoc """
  Global supervision tree for the Jido agent runtime.
  
  Provides:
  - Registry for agent instance lookup
  - DynamicSupervisor for agent instances
  - Task.Supervisor for async effect execution
  """
  
  use Application

  def start(_type, _args) do
    children = [
      # Agent name registry (unique keys)
      {Registry, keys: :unique, name: Jido.AgentRegistry},
      
      # Dynamic supervisor for all agent instances
      {DynamicSupervisor, 
        name: Jido.AgentInstanceSupervisor, 
        strategy: :one_for_one,
        max_restarts: 1000,
        max_seconds: 5},
      
      # Shared task supervisor for async effects
      {Task.Supervisor, 
        name: Jido.AgentTaskSupervisor,
        max_children: 1000}
    ]

    opts = [strategy: :one_for_one, name: Jido.AgentRuntime.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Registry-Based Naming

Agents can be looked up by their instance ID:

```elixir
# Registration (automatic in AgentServer.init/1)
{:via, Registry, {Jido.AgentRegistry, agent_id}}

# Lookup
case Registry.lookup(Jido.AgentRegistry, agent_id) do
  [{pid, _meta}] -> {:ok, pid}
  [] -> {:error, :not_found}
end
```

---

## 4. Per-Instance Process Hierarchy

### Instance Supervisor

Each agent instance is a small supervision tree:

```elixir
defmodule Jido.AgentServer.InstanceSupervisor do
  @moduledoc """
  Supervises a single agent instance's processes.
  
  Uses :one_for_all strategy - if any child dies, all are restarted.
  This ensures consistent state between AgentServer and EffectExecutor.
  """
  
  use Supervisor

  def start_link({agent_module, opts}) do
    Supervisor.start_link(__MODULE__, {agent_module, opts})
  end

  @impl true
  def init({agent_module, opts}) do
    instance_id = opts[:id] || Jido.Util.generate_id()
    
    children = [
      # Child supervisor (started first, needed by EffectExecutor)
      {DynamicSupervisor, 
        name: child_sup_name(instance_id),
        strategy: :one_for_one},
      
      # Effect executor (started before AgentServer)
      {Jido.AgentServer.EffectExecutor,
        instance_id: instance_id,
        opts: opts},
      
      # Main agent server
      {Jido.AgentServer,
        agent_module: agent_module,
        instance_id: instance_id,
        opts: opts}
    ]

    Supervisor.init(children, strategy: :one_for_all, max_restarts: 3, max_seconds: 5)
  end
  
  defp child_sup_name(instance_id), do: {:via, Registry, {Jido.AgentRegistry, {instance_id, :children}}}
end
```

### Why `:one_for_all`?

| Scenario | Behavior |
|----------|----------|
| AgentServer crashes | Entire instance restarts, ensuring clean state |
| EffectExecutor crashes | Instance restarts; pending directives lost (at-most-once) |
| ChildSupervisor crashes | Instance restarts; child agents also restarted |

This provides strong consistency guarantees while leveraging OTP's built-in fault tolerance.

---

## 5. Signal Processing Pipeline

### AgentServer State

```elixir
defmodule Jido.AgentServer do
  use GenServer
  
  @type state :: %{
    # Identity
    instance_id: String.t(),
    agent_module: module(),
    
    # Pure agent data
    agent: Jido.Agent.t(),
    
    # Runtime configuration
    runner: module(),
    default_dispatch: term(),
    error_policy: error_policy(),
    max_queue: non_neg_integer() | :infinity,
    
    # Process references
    effect_executor: pid(),
    child_sup: pid(),
    
    # Hierarchy
    parent: parent_ref() | nil,
    children: %{term() => child_info()},
    
    # Persistence (optional)
    persistence: nil | {module(), keyword()},
    
    # Metrics
    stats: %{
      signals_processed: non_neg_integer(),
      last_signal_at: integer() | nil
    }
  }
  
  @type parent_ref :: %{pid: pid(), tag: term(), signal: Jido.Signal.t() | nil}
  @type child_info :: %{pid: pid(), ref: reference(), module: module(), meta: map()}
  @type error_policy :: :log_only | :stop_on_error | {:emit_signal, term()} | function()
end
```

### Canonical Signal Processing

**Key design decision: Action-first with generated signal translation**

```elixir
# In `use Jido.Agent` macro - generated for all agents
def handle_signal(agent, %Jido.Signal{} = signal) do
  action = signal_to_action(signal)
  cmd(agent, action)
end

# Default implementation (overridable)
def signal_to_action(%Jido.Signal{type: type, data: data}) do
  # Convention: signal.type maps to action
  {Jido.Actions.from_type(type), data}
end
```

This eliminates the runtime `function_exported?` check and provides a single, consistent entrypoint.

### Signal Flow

```
Signal arrives
      │
      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         AgentServer                                  │
│                                                                      │
│  1. Check backpressure (max_queue)                                  │
│  2. Run pure logic: runner.handle(agent_module, state, signal)      │
│  3. Update agent state                                              │
│  4. (Optional) Persistence hook                                      │
│  5. Enqueue directives → EffectExecutor                             │
│  6. Return immediately                                               │
│                                                                      │
└──────────────────────────────────┬──────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       EffectExecutor                                 │
│                                                                      │
│  1. Receive directives (cast, non-blocking)                         │
│  2. Add to FIFO queue                                               │
│  3. Drain queue sequentially                                         │
│  4. Execute via DirectiveExecutor protocol                          │
│  5. Offload heavy work to Task.Supervisor                           │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### AgentServer Implementation

```elixir
defmodule Jido.AgentServer do
  use GenServer
  require Logger

  # Public API
  
  @doc "Start an agent instance under the runtime supervisor."
  def start_link(agent_module, opts \\ []) do
    DynamicSupervisor.start_child(
      Jido.AgentInstanceSupervisor,
      {Jido.AgentServer.InstanceSupervisor, {agent_module, opts}}
    )
  end

  @doc "Send a signal asynchronously (non-blocking)."
  def handle_signal(server, %Jido.Signal{} = signal) do
    GenServer.cast(server, {:signal, signal})
  end

  @doc "Send a signal synchronously, wait for processing."
  def handle_signal_sync(server, %Jido.Signal{} = signal, timeout \\ 5_000) do
    GenServer.call(server, {:signal, signal}, timeout)
  end

  @doc "Get current agent snapshot."
  def get_agent(server) do
    GenServer.call(server, :get_agent)
  end
  
  @doc "Query children by tag or get all."
  def get_children(server, tag \\ nil) do
    GenServer.call(server, {:get_children, tag})
  end

  # GenServer callbacks
  
  @impl true
  def init(args) do
    agent_module = Keyword.fetch!(args, :agent_module)
    instance_id = Keyword.fetch!(args, :instance_id)
    opts = Keyword.get(args, :opts, [])
    
    # Build or inject agent
    agent = build_agent(agent_module, opts)
    
    # Look up sibling processes
    effect_executor = await_sibling(instance_id, :effect_executor)
    child_sup = await_sibling(instance_id, :children)
    
    # Configure effect executor with our pid
    GenServer.cast(effect_executor, {:set_agent_server, self()})
    
    state = %{
      instance_id: instance_id,
      agent_module: agent_module,
      agent: agent,
      runner: opts[:runner] || Jido.Agent.Runner.Simple,
      default_dispatch: opts[:default_dispatch],
      error_policy: opts[:error_policy] || :log_only,
      max_queue: opts[:max_queue] || :infinity,
      effect_executor: effect_executor,
      child_sup: child_sup,
      parent: opts[:parent],
      children: %{},
      persistence: opts[:persistence],
      stats: %{signals_processed: 0, last_signal_at: nil}
    }
    
    {:ok, state, {:continue, :post_init}}
  end
  
  @impl true
  def handle_continue(:post_init, state) do
    # Emit started event
    emit_lifecycle_event(:started, state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:signal, signal}, state) do
    case check_backpressure(state) do
      :ok ->
        {new_state, stop_reason} = process_signal(signal, state)
        handle_stop_reason(stop_reason, new_state)
        
      {:error, :overloaded} ->
        Logger.warning("Agent #{state.instance_id} overloaded, dropping signal")
        emit_overload_event(signal, state)
        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:signal, signal}, from, state) do
    {new_state, stop_reason, maybe_error} = process_signal_sync(signal, state)
    
    reply = case maybe_error do
      nil -> {:ok, new_state.agent}
      error -> {:error, error}
    end
    
    case stop_reason do
      nil -> {:reply, reply, new_state}
      reason -> {:stop, reason, reply, new_state}
    end
  end

  def handle_call(:get_agent, _from, state) do
    {:reply, state.agent, state}
  end
  
  def handle_call({:get_children, nil}, _from, state) do
    {:reply, state.children, state}
  end
  
  def handle_call({:get_children, tag}, _from, state) do
    {:reply, Map.get(state.children, tag), state}
  end

  @impl true
  def handle_info({:child_started, tag, pid, module, ref, meta}, state) do
    child_info = %{pid: pid, ref: ref, module: module, meta: meta}
    children = Map.put(state.children, tag || pid, child_info)
    
    # Emit child lifecycle signal for agent to process
    emit_child_event(:child_started, tag, child_info, state)
    
    {:noreply, %{state | children: children}}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case find_child_by_ref(state.children, ref) do
      {tag, child_info} ->
        new_children = Map.delete(state.children, tag)
        emit_child_event(:child_exit, tag, Map.put(child_info, :reason, reason), state)
        {:noreply, %{state | children: new_children}}
        
      nil ->
        {:noreply, state}
    end
  end
  
  def handle_info({:jido_schedule, message}, state) do
    # Convert scheduled message to signal if needed
    signal = ensure_signal(message, state)
    {new_state, stop_reason} = process_signal(signal, state)
    handle_stop_reason(stop_reason, new_state)
  end

  # Private functions
  
  defp process_signal(%Jido.Signal{} = signal, state) do
    old_agent = state.agent
    
    # Run pure agent/runner logic
    {agent, directives} = run_agent(signal, state)
    
    # Update state
    new_state = %{state | 
      agent: agent,
      stats: %{state.stats | 
        signals_processed: state.stats.signals_processed + 1,
        last_signal_at: System.monotonic_time(:millisecond)
      }
    }
    
    # Optional persistence hook (async)
    maybe_persist_transition(old_agent, signal, agent, directives, new_state)
    
    # Enqueue directives for execution (non-blocking)
    enqueue_directives(signal, directives, new_state)
    
    {new_state, nil}
  end
  
  defp process_signal_sync(signal, state) do
    {new_state, stop_reason} = process_signal(signal, state)
    
    # For sync calls, we check for Error directives that were just enqueued
    # This is best-effort since execution is async
    first_error = find_first_error(state.last_directives)
    
    {new_state, stop_reason, first_error}
  end
  
  defp run_agent(%Jido.Signal{} = signal, state) do
    runner = state.runner
    
    case runner.handle(state.agent_module, state.agent.state, signal) do
      {:ok, new_struct_state, effects} ->
        agent = %{state.agent | state: new_struct_state}
        directives = effects_to_directives(effects)
        {agent, directives}
        
      {:error, reason} ->
        error = Jido.Error.runtime_error("runner_error", %{reason: reason})
        {state.agent, [%Jido.Agent.Directive.Error{error: error, context: :runner}]}
    end
  end
  
  defp enqueue_directives(_signal, [], _state), do: :ok
  defp enqueue_directives(signal, directives, state) do
    GenServer.cast(state.effect_executor, {:enqueue, signal, directives})
  end
  
  defp check_backpressure(%{max_queue: :infinity}), do: :ok
  defp check_backpressure(state) do
    case Process.info(self(), :message_queue_len) do
      {:message_queue_len, len} when len > state.max_queue -> {:error, :overloaded}
      _ -> :ok
    end
  end
  
  defp handle_stop_reason(nil, state), do: {:noreply, state}
  defp handle_stop_reason(reason, state), do: {:stop, reason, state}
end
```

---

## 6. Directive Execution System

### DirectiveExecutor Protocol

External packages can implement custom directive execution:

```elixir
defprotocol Jido.AgentServer.DirectiveExecutor do
  @moduledoc """
  Protocol for executing directives.
  
  Implement this protocol for custom directive types to make them
  executable by the EffectExecutor.
  """
  
  @doc """
  Execute the directive.
  
  Returns:
  - `{:ok, exec_state}` - Continue to next directive
  - `{:stop, reason, exec_state}` - Stop the agent
  - `{:async, task_ref, exec_state}` - Directive spawned async work (informational)
  """
  @spec execute(struct(), Jido.Signal.t(), map()) ::
          {:ok, map()} 
          | {:stop, term(), map()}
          | {:async, reference(), map()}
  def execute(directive, signal, exec_state)
end
```

### Core Directive Implementations

```elixir
# Emit directive - dispatch a signal
defimpl Jido.AgentServer.DirectiveExecutor, for: Jido.Agent.Directive.Emit do
  def execute(%{signal: signal, dispatch: dispatch}, _trigger_signal, state) do
    cfg = dispatch || state.default_dispatch
    
    case cfg do
      nil ->
        Logger.debug("Emit without dispatch config: #{inspect(signal.type)}")
        
      cfg ->
        # Non-blocking dispatch
        case Jido.Signal.Dispatch.dispatch(signal, cfg) do
          :ok -> :ok
          {:ok, _} -> :ok
          {:error, reason} ->
            Logger.warning("Emit dispatch failed: #{inspect(reason)}")
        end
    end
    
    {:ok, state}
  end
end

# Schedule directive - send delayed message
defimpl Jido.AgentServer.DirectiveExecutor, for: Jido.Agent.Directive.Schedule do
  def execute(%{delay_ms: delay, message: message}, _signal, state) do
    Process.send_after(state.agent_server, {:jido_schedule, message}, delay)
    {:ok, state}
  end
end

# Stop directive - stop the agent
defimpl Jido.AgentServer.DirectiveExecutor, for: Jido.Agent.Directive.Stop do
  def execute(%{reason: reason}, _signal, state) do
    {:stop, reason, state}
  end
end

# Error directive - apply error policy
defimpl Jido.AgentServer.DirectiveExecutor, for: Jido.Agent.Directive.Error do
  def execute(%{error: error, context: context} = directive, _signal, state) do
    Jido.AgentServer.ErrorPolicy.handle(directive, state)
  end
end

# SpawnAgent directive - spawn a child agent
defimpl Jido.AgentServer.DirectiveExecutor, for: Jido.Agent.Directive.SpawnAgent do
  def execute(%{agent_module: mod, opts: opts, tag: tag, parent_meta: meta}, signal, state) do
    child_opts = [
      parent: %{pid: state.agent_server, tag: tag, signal: signal},
      meta: meta
    ] ++ Map.to_list(opts)
    
    spec = %{
      id: make_ref(),
      start: {Jido.AgentServer, :start_link_child, [mod, child_opts]},
      restart: :transient,
      type: :supervisor
    }
    
    case DynamicSupervisor.start_child(state.child_sup, spec) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        send(state.agent_server, {:child_started, tag, pid, mod, ref, meta})
        {:ok, state}
        
      {:error, reason} ->
        error = Jido.Error.runtime_error("spawn_failed", %{reason: reason, tag: tag})
        Jido.AgentServer.ErrorPolicy.handle(
          %Jido.Agent.Directive.Error{error: error, context: :spawn},
          state
        )
    end
  end
end
```

### EffectExecutor Implementation

```elixir
defmodule Jido.AgentServer.EffectExecutor do
  @moduledoc """
  Executes directives sequentially for an agent instance.
  
  Maintains a FIFO queue of directives and processes them one at a time.
  Heavy/async work is offloaded to Task.Supervisor.
  """
  
  use GenServer
  require Logger
  
  alias Jido.AgentServer.DirectiveExecutor

  @type state :: %{
    queue: :queue.queue({Jido.Signal.t(), term()}),
    agent_server: pid() | nil,
    task_sup: pid() | atom(),
    default_dispatch: term(),
    error_policy: term(),
    child_sup: pid() | nil,
    instance_id: String.t(),
    processing: boolean()
  }

  def start_link(opts) do
    instance_id = Keyword.fetch!(opts, :instance_id)
    name = {:via, Registry, {Jido.AgentRegistry, {instance_id, :effect_executor}}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    instance_id = Keyword.fetch!(opts, :instance_id)
    config_opts = Keyword.get(opts, :opts, [])
    
    state = %{
      queue: :queue.new(),
      agent_server: nil,  # Set later via cast
      task_sup: Jido.AgentTaskSupervisor,
      default_dispatch: config_opts[:default_dispatch],
      error_policy: config_opts[:error_policy] || :log_only,
      child_sup: nil,  # Set later
      instance_id: instance_id,
      processing: false
    }
    
    {:ok, state}
  end

  @impl true
  def handle_cast({:set_agent_server, pid}, state) do
    child_sup_name = {:via, Registry, {Jido.AgentRegistry, {state.instance_id, :children}}}
    child_sup = GenServer.whereis(child_sup_name)
    
    {:noreply, %{state | agent_server: pid, child_sup: child_sup}}
  end

  def handle_cast({:enqueue, signal, directives}, state) do
    # Add all directives to queue
    queue = Enum.reduce(directives, state.queue, fn d, q ->
      :queue.in({signal, d}, q)
    end)
    
    state = %{state | queue: queue}
    
    # Start processing if not already
    if not state.processing do
      send(self(), :drain)
    end
    
    {:noreply, %{state | processing: true}}
  end

  @impl true
  def handle_info(:drain, %{queue: queue} = state) do
    case :queue.out(queue) do
      {{:value, {signal, directive}}, rest} ->
        state = %{state | queue: rest}
        
        case execute_directive(directive, signal, state) do
          {:ok, new_state} ->
            send(self(), :drain)
            {:noreply, new_state}
            
          {:stop, reason, new_state} ->
            # Signal AgentServer to stop
            Process.exit(state.agent_server, reason)
            {:stop, reason, new_state}
            
          {:async, _ref, new_state} ->
            # Async work started, continue to next directive
            send(self(), :drain)
            {:noreply, new_state}
        end
        
      {:empty, _} ->
        {:noreply, %{state | processing: false}}
    end
  end

  def handle_info({ref, result}, state) when is_reference(ref) do
    # Task completion - could log or emit result signal
    Process.demonitor(ref, [:flush])
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Task failed
    Logger.warning("Async directive task failed: #{inspect(reason)}")
    {:noreply, state}
  end

  # Private
  
  defp execute_directive(directive, signal, state) do
    try do
      DirectiveExecutor.execute(directive, signal, state)
    rescue
      e ->
        Logger.error("Directive execution error: #{Exception.message(e)}")
        {:ok, state}  # Continue processing
    end
  end
end
```

---

## 7. Hierarchical Agent Management

### Enhanced SpawnAgent Directive

```elixir
defmodule Jido.Agent.Directive.SpawnAgent do
  @moduledoc """
  Spawn a child agent with parent-child relationship tracking.
  
  Unlike the generic %Spawn{} directive, this is specifically for
  spawning Jido agents with proper hierarchy semantics.
  """
  
  @enforce_keys [:agent_module]
  defstruct [
    :agent_module,
    opts: %{},
    tag: nil,
    parent_meta: %{},
    restart: :transient,
    inherit_dispatch: true
  ]
  
  @type t :: %__MODULE__{
    agent_module: module(),
    opts: map(),
    tag: term(),
    parent_meta: map(),
    restart: :permanent | :transient | :temporary,
    inherit_dispatch: boolean()
  }
end
```

### Parent-Child Communication

Child agents receive parent reference in their state:

```elixir
# In child agent's init
parent_ref = %{
  pid: opts[:parent][:pid],
  tag: opts[:parent][:tag],
  signal: opts[:parent][:signal]  # Signal that triggered spawn
}
```

Parents receive lifecycle signals:

```elixir
# Emitted when child starts
%Jido.Signal{
  type: "jido.agent.child.started",
  source: "/agent/#{parent_id}",
  data: %{
    tag: tag,
    pid: child_pid,
    module: child_module,
    meta: parent_meta
  }
}

# Emitted when child exits
%Jido.Signal{
  type: "jido.agent.child.exit",
  source: "/agent/#{parent_id}",
  data: %{
    tag: tag,
    pid: child_pid,
    module: child_module,
    reason: exit_reason,
    meta: parent_meta
  }
}
```

### Hierarchy Queries

```elixir
# Get all children
children = Jido.AgentServer.get_children(parent_pid)

# Get specific child by tag
child_info = Jido.AgentServer.get_children(parent_pid, :worker_1)

# Send signal to child
Jido.AgentServer.handle_signal(child_info.pid, signal)

# Send signal to all children
Enum.each(children, fn {_tag, info} ->
  Jido.AgentServer.handle_signal(info.pid, signal)
end)
```

### Hierarchy Example

```elixir
defmodule OrchestratorAgent do
  use Jido.Agent,
    name: "orchestrator",
    schema: [
      task_count: [type: :integer, default: 0]
    ]
    
  def cmd(agent, {:spawn_workers, count}) do
    directives = for i <- 1..count do
      %Directive.SpawnAgent{
        agent_module: WorkerAgent,
        tag: :"worker_#{i}",
        opts: %{worker_id: i},
        parent_meta: %{spawned_at: DateTime.utc_now()}
      }
    end
    
    agent = %{agent | state: %{agent.state | task_count: count}}
    {agent, directives}
  end
  
  def handle_signal(agent, %Signal{type: "jido.agent.child.exit"} = signal) do
    # React to child exit - maybe spawn replacement
    case signal.data.reason do
      :normal -> {agent, []}
      _abnormal -> 
        # Re-spawn the worker
        {agent, [
          %Directive.SpawnAgent{
            agent_module: WorkerAgent,
            tag: signal.data.tag,
            opts: signal.data.meta
          }
        ]}
    end
  end
end
```

---

## 8. Error Handling & Policies

### Error Policy Types

```elixir
@type error_policy ::
  :log_only                              # Log and continue (default)
  | :stop_on_error                       # Stop agent on any error
  | {:emit_signal, dispatch_config()}    # Emit error as signal
  | {:max_errors, count :: pos_integer()} # Stop after N errors
  | (Directive.Error.t(), state() -> {:ok, state()} | {:stop, reason, state()})
```

### Error Policy Module

```elixir
defmodule Jido.AgentServer.ErrorPolicy do
  @moduledoc """
  Handles error directives according to configured policy.
  """
  
  require Logger
  alias Jido.Agent.Directive.Error, as: ErrorDirective

  def handle(%ErrorDirective{error: error, context: context}, state) do
    case state.error_policy do
      :log_only ->
        Logger.error("Agent error [#{context}]: #{inspect(error)}")
        {:ok, state}
        
      :stop_on_error ->
        Logger.error("Agent stopping on error [#{context}]: #{inspect(error)}")
        {:stop, {:agent_error, error}, state}
        
      {:emit_signal, dispatch_cfg} ->
        signal = build_error_signal(error, context, state)
        Jido.Signal.Dispatch.dispatch(signal, dispatch_cfg)
        {:ok, state}
        
      {:max_errors, max} ->
        count = Map.get(state, :error_count, 0) + 1
        if count >= max do
          {:stop, {:max_errors_exceeded, count}, state}
        else
          Logger.error("Agent error #{count}/#{max} [#{context}]: #{inspect(error)}")
          {:ok, Map.put(state, :error_count, count)}
        end
        
      fun when is_function(fun, 2) ->
        fun.(%ErrorDirective{error: error, context: context}, state)
    end
  end
  
  defp build_error_signal(error, context, state) do
    Jido.Signal.new!(
      "jido.agent.error",
      %{error: error, context: context},
      source: "/agent/#{state.instance_id}"
    )
  end
end
```

### Sync Call Error Surfacing

For `handle_signal_sync/3`, errors are surfaced in the response:

```elixir
# Returns {:ok, agent} or {:error, first_error}
case Jido.AgentServer.handle_signal_sync(pid, signal) do
  {:ok, agent} -> 
    # Success
    
  {:error, %Jido.Agent.Directive.Error{error: error}} ->
    # Handle error
end
```

---

## 9. Backpressure & Observability

### Backpressure Mechanisms

```elixir
defmodule Jido.AgentServer do
  # Check if agent is overloaded
  @spec busy?(GenServer.server(), pos_integer()) :: boolean()
  def busy?(server, threshold \\ 100) do
    case Process.info(GenServer.whereis(server), :message_queue_len) do
      {:message_queue_len, len} -> len > threshold
      _ -> false
    end
  end
  
  # Get current queue length
  @spec queue_length(GenServer.server()) :: non_neg_integer()
  def queue_length(server) do
    GenServer.call(server, :queue_length)
  end
  
  # Submit signal with backpressure feedback
  @spec submit_signal(GenServer.server(), Jido.Signal.t(), keyword()) ::
          :ok | {:error, :overloaded}
  def submit_signal(server, signal, opts \\ []) do
    GenServer.call(server, {:submit_signal, signal, opts})
  end
end
```

### Observability

```elixir
# Get agent stats
def get_stats(server) do
  GenServer.call(server, :get_stats)
end

# Returns:
%{
  signals_processed: 1234,
  last_signal_at: 1703856000000,
  queue_length: 5,
  children_count: 3,
  uptime_ms: 60000
}
```

### Telemetry Events

```elixir
# Emitted events
:telemetry.execute(
  [:jido, :agent, :signal, :processed],
  %{duration: duration_ms},
  %{agent_id: instance_id, signal_type: signal.type}
)

:telemetry.execute(
  [:jido, :agent, :directive, :executed],
  %{duration: duration_ms},
  %{agent_id: instance_id, directive_type: directive.__struct__}
)

:telemetry.execute(
  [:jido, :agent, :overload],
  %{queue_length: len},
  %{agent_id: instance_id}
)
```

---

## 10. Event Sourcing & Persistence

### Persistence Behaviour

```elixir
defmodule Jido.AgentServer.Persistence do
  @moduledoc """
  Behaviour for persisting agent state transitions.
  
  Implementations can store events for:
  - Audit logging
  - Event sourcing / replay
  - State snapshots
  """
  
  @callback after_transition(
    old_agent :: Jido.Agent.t(),
    signal :: Jido.Signal.t(),
    new_agent :: Jido.Agent.t(),
    directives :: [term()],
    meta :: map()
  ) :: :ok | {:error, term()}
  
  @callback restore(instance_id :: String.t(), opts :: keyword()) ::
    {:ok, Jido.Agent.t()} | {:error, term()}
    
  @callback snapshot(agent :: Jido.Agent.t(), meta :: map()) ::
    :ok | {:error, term()}
    
  @optional_callbacks [restore: 2, snapshot: 2]
end
```

### Persistence Hook

```elixir
defp maybe_persist_transition(old_agent, signal, new_agent, directives, state) do
  case state.persistence do
    nil -> :ok
    
    {mod, opts} ->
      # Non-blocking persistence
      Task.Supervisor.start_child(Jido.AgentTaskSupervisor, fn ->
        meta = %{
          instance_id: state.instance_id,
          timestamp: DateTime.utc_now(),
          opts: opts
        }
        
        case mod.after_transition(old_agent, signal, new_agent, directives, meta) do
          :ok -> :ok
          {:error, reason} ->
            Logger.warning("Persistence failed: #{inspect(reason)}")
        end
      end)
  end
end
```

### Example: Simple Event Log

```elixir
defmodule MyApp.AgentEventLog do
  @behaviour Jido.AgentServer.Persistence
  
  @impl true
  def after_transition(old_agent, signal, new_agent, directives, meta) do
    event = %{
      instance_id: meta.instance_id,
      timestamp: meta.timestamp,
      signal_id: signal.id,
      signal_type: signal.type,
      old_state_hash: hash(old_agent.state),
      new_state_hash: hash(new_agent.state),
      directive_count: length(directives)
    }
    
    MyApp.Repo.insert(%AgentEvent{} |> Map.merge(event))
    :ok
  end
  
  defp hash(state), do: :erlang.phash2(state)
end
```

---

## 11. Scaling Considerations

### Process Overhead

| Agents | Processes | Memory (approx) |
|--------|-----------|-----------------|
| 100 | ~300 | ~30 MB |
| 500 | ~1,500 | ~150 MB |
| 1,000 | ~3,000 | ~300 MB |

This is well within BEAM's comfortable range (millions of processes possible).

### Strategies for High Scale

1. **Pooled Task Execution**
   - Use `poolboy` or `nimble_pool` for task supervision if many agents share expensive resources

2. **Partitioned Registries**
   - Use multiple registries partitioned by agent type or ID hash

3. **Rate Limiting per Agent Type**
   - Configure different `max_queue` limits based on agent workload

4. **Lazy Child Supervisor**
   - Only start ChildSupervisor when first child is spawned

```elixir
# Lazy child supervisor creation
defp ensure_child_sup(state) do
  case state.child_sup do
    nil ->
      {:ok, pid} = DynamicSupervisor.start_link(strategy: :one_for_one)
      %{state | child_sup: pid}
    _ ->
      state
  end
end
```

### Multi-Node Considerations (Future)

For distributed agents:

1. **Horde** - Distributed supervisor and registry
2. **libcluster** - Automatic cluster formation
3. **Delta CRDT** - Conflict-free replicated state

These are out of scope for V2 but the architecture supports future extension.

---

## 12. API Reference

### Starting Agents

```elixir
# Start with defaults
{:ok, pid} = Jido.AgentServer.start_link(MyAgent)

# Start with options
{:ok, pid} = Jido.AgentServer.start_link(MyAgent,
  id: "user-123-agent",
  agent_opts: [user_id: "123"],
  default_dispatch: {:pubsub, topic: "agent_events"},
  error_policy: {:max_errors, 5},
  max_queue: 1000,
  runner: Jido.Agent.Runner.ReAct,
  persistence: {MyApp.AgentEventLog, []}
)

# Start as child of another agent
{:ok, pid} = Jido.AgentServer.start_link(WorkerAgent,
  parent: %{pid: parent_pid, tag: :worker_1, signal: trigger_signal}
)
```

### Sending Signals

```elixir
# Async (fire-and-forget)
:ok = Jido.AgentServer.handle_signal(pid, signal)

# Sync (wait for processing)
{:ok, agent} = Jido.AgentServer.handle_signal_sync(pid, signal)
{:error, error} = Jido.AgentServer.handle_signal_sync(pid, bad_signal)

# With backpressure check
case Jido.AgentServer.submit_signal(pid, signal) do
  :ok -> :processed
  {:error, :overloaded} -> :retry_later
end
```

### Querying State

```elixir
# Get agent snapshot
agent = Jido.AgentServer.get_agent(pid)

# Get children
children = Jido.AgentServer.get_children(pid)
child = Jido.AgentServer.get_children(pid, :worker_1)

# Get stats
stats = Jido.AgentServer.get_stats(pid)

# Check health
busy? = Jido.AgentServer.busy?(pid, 100)
queue_len = Jido.AgentServer.queue_length(pid)
```

---

## 13. Migration from V1

### Breaking Changes

| V1 | V2 | Migration |
|----|-----|-----------|
| Single GenServer | Process tree | Transparent (API compatible) |
| `children_supervisor` option | Automatic `ChildSupervisor` | Remove option |
| `spawn_fun` option | `DirectiveExecutor` protocol | Implement protocol |
| Inline directive execution | Async via `EffectExecutor` | Transparent |

### Deprecated Options

```elixir
# V1 (deprecated)
Jido.AgentServer.start_link(MyAgent,
  children_supervisor: my_sup,  # Deprecated - ignored
  spawn_fun: &custom_spawn/1    # Deprecated - use protocol
)

# V2
Jido.AgentServer.start_link(MyAgent)
# Children automatically supervised
# Custom spawn via DirectiveExecutor protocol implementation
```

### New Required Setup

```elixir
# In application.ex
def start(_type, _args) do
  children = [
    Jido.AgentRuntime,  # NEW - must be started
    # ... your other children
  ]
  
  Supervisor.start_link(children, strategy: :one_for_one)
end
```

---

## 14. Implementation Roadmap

### Phase 1: Core Infrastructure (1-2 days)

- [ ] `Jido.AgentRuntime` application supervisor
- [ ] `Jido.AgentServer.InstanceSupervisor`
- [ ] `Jido.AgentServer` V2 (signal processing only)
- [ ] `Jido.AgentServer.EffectExecutor`
- [ ] `Jido.AgentServer.DirectiveExecutor` protocol
- [ ] Core directive implementations (Emit, Schedule, Stop, Error)

### Phase 2: Hierarchy & Error Handling (1 day)

- [ ] `SpawnAgent` directive
- [ ] Child tracking in AgentServer
- [ ] Child lifecycle signals
- [ ] `ErrorPolicy` module
- [ ] Sync call error surfacing

### Phase 3: Observability & Polish (0.5 days)

- [ ] Backpressure (`busy?`, `queue_length`, `submit_signal`)
- [ ] Stats/metrics
- [ ] Telemetry events
- [ ] Logging improvements

### Phase 4: Persistence (0.5 days)

- [ ] `Persistence` behaviour
- [ ] Hook integration
- [ ] Example implementation

### Phase 5: Testing & Documentation (1 day)

- [ ] Unit tests for each module
- [ ] Integration tests for hierarchy
- [ ] Property tests for lifecycle
- [ ] API documentation
- [ ] Migration guide

**Total Estimated Effort: 4-5 days**

---

## Appendix: Process Diagram

```
                              ┌─────────────────────────────────┐
                              │     External System / UI        │
                              └───────────────┬─────────────────┘
                                              │
                                     Jido.Signal.t()
                                              │
                                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Jido.AgentRuntime                                  │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    AgentInstanceSupervisor                            │   │
│  │                      (DynamicSupervisor)                              │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │  │                  AgentInstance (Supervisor)                      │ │   │
│  │  │                     :one_for_all                                 │ │   │
│  │  │  ┌─────────────────────────────────────────────────────────────┐│ │   │
│  │  │  │                                                              ││ │   │
│  │  │  │  ┌──────────────┐  ┌─────────────────┐  ┌────────────────┐  ││ │   │
│  │  │  │  │ AgentServer  │  │ EffectExecutor  │  │ ChildSupervisor│  ││ │   │
│  │  │  │  │              │  │                 │  │(DynamicSup)    │  ││ │   │
│  │  │  │  │ • agent      │  │ • queue         │  │                │  ││ │   │
│  │  │  │  │ • state      │──│ • directives    │  │ • Child agents │  ││ │   │
│  │  │  │  │ • children   │  │ • execution     │  │ • Child procs  │  ││ │   │
│  │  │  │  │ • runner     │  │                 │  │                │  ││ │   │
│  │  │  │  └──────────────┘  └────────┬────────┘  └───────┬────────┘  ││ │   │
│  │  │  │         │                   │                   │           ││ │   │
│  │  │  │         │     enqueue       │                   │           ││ │   │
│  │  │  │         └───────────────────┘                   │           ││ │   │
│  │  │  │                             │                   │           ││ │   │
│  │  │  │                      ┌──────┴──────┐            │           ││ │   │
│  │  │  │                      ▼             ▼            ▼           ││ │   │
│  │  │  │               ┌────────────┐ ┌──────────┐ ┌──────────┐     ││ │   │
│  │  │  │               │%Emit{}     │ │%Spawn{}  │ │Child     │     ││ │   │
│  │  │  │               │→ Dispatch  │ │→ Start   │ │Instance  │     ││ │   │
│  │  │  │               └────────────┘ └──────────┘ └──────────┘     ││ │   │
│  │  │  │                                                              ││ │   │
│  │  │  └──────────────────────────────────────────────────────────────┘│ │   │
│  │  └───────────────────────────────────────────────────────────────────┘ │   │
│  │                                                                        │   │
│  │  ┌───────────────────────────────────────────────────────────────────┐ │   │
│  │  │                 AgentInstance 2... N                               │ │   │
│  │  │                      (same structure)                              │ │   │
│  │  └───────────────────────────────────────────────────────────────────┘ │   │
│  └────────────────────────────────────────────────────────────────────────┘   │
│                                                                               │
│  ┌────────────────────────┐  ┌───────────────────────────────────────────┐   │
│  │    AgentRegistry       │  │         AgentTaskSupervisor               │   │
│  │    (Registry)          │  │         (Task.Supervisor)                 │   │
│  │                        │  │                                           │   │
│  │  • {id, :main} → pid   │  │  • LLM calls                              │   │
│  │  • {id, :exec} → pid   │  │  • HTTP requests                          │   │
│  │  • {id, :children}→pid │  │  • Persistence writes                     │   │
│  └────────────────────────┘  └───────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────────────────────┘
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0.0-draft | Dec 2024 | Initial V2 architecture specification |

---

*Specification Version: 2.0.0-draft*  
*Last Updated: December 2024*

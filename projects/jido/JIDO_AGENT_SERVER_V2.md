# Jido AgentServer V2 Architecture

> A simple, OTP-native runtime for hierarchical agent systems

**Version:** 2.0.0-draft  
**Last Updated:** December 2024

---

## Executive Summary

AgentServer V2 is a **simplified, OTP-idiomatic runtime** for Jido agents. It replaces the multi-process per-instance architecture with a **single GenServer per agent** under a shared supervision tree.

**Core Principles:**

1. **Agents think, Servers act** — Pure `Jido.Agent` logic produces directives; `AgentServer` executes effects
2. **One process per agent** — Simple, debuggable, leverages BEAM's strengths
3. **Flat OTP supervision** — All agents under one DynamicSupervisor; hierarchy is logical
4. **Non-blocking signal processing** — Internal directive queue with drain loop
5. **Extensible via protocols** — Custom directives without modifying core
6. **Zoi-validated types** — All data structures use Zoi for schema validation

---

## Table of Contents

1. [Design Goals](#1-design-goals)
2. [Architecture Overview](#2-architecture-overview)
3. [Global Supervision Tree](#3-global-supervision-tree)
4. [Data Types (Zoi Schemas)](#4-data-types-zoi-schemas)
5. [AgentServer GenServer](#5-agentserver-genserver)
6. [Public API](#6-public-api)
7. [Signal Processing Pipeline](#7-signal-processing-pipeline)
8. [Directive Execution Protocol](#8-directive-execution-protocol)
9. [Hierarchical Agent Management](#9-hierarchical-agent-management)
10. [Error Handling & Policies](#10-error-handling--policies)
11. [Backpressure & Observability](#11-backpressure--observability)
12. [Migration from V1](#12-migration-from-v1)

---

## 1. Design Goals

### Primary Goals

| Goal | How V2 Achieves It |
|------|---------------------|
| **Non-blocking signal processing** | Internal directive queue; signals enqueue fast, effects drain async |
| **Hierarchical agents** | Logical parent-child via state + lifecycle signals; flat OTP |
| **Production resilience** | Configurable error policies; standard OTP supervision |
| **Horizontal scale** | 1 process per agent; supports 1000s of concurrent instances |
| **Extensibility** | Protocol-based directive execution; plugins add new directive types |
| **Type safety** | Zoi schemas for all data structures with validation |

### Non-Goals (Explicit)

- Cross-node clustering (future consideration)
- Exactly-once effect delivery (at-most-once is acceptable)
- Complex scheduling/prioritization across agents
- Nested OTP supervision per agent (adds complexity without benefit)

### Key Invariants

1. **Sequential directive dispatch** — Directives for a single agent execute in order of enqueue
2. **Pure agent logic** — `Jido.Agent.cmd/2` remains purely functional
3. **Signals as universal envelope** — All external communication via `Jido.Signal`
4. **Single canonical entry point** — `cmd/2` is the pure interface; `handle_signal/2` is a generated adapter

---

## 2. Architecture Overview

### High-Level View

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Jido.Application                                   │
│                        (Application Supervisor)                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────┐  ┌────────────────────┐  ┌───────────────────────┐ │
│  │  Jido.TaskSupervisor│  │   Jido.Registry    │  │ Jido.AgentSupervisor  │ │
│  │  (Task.Supervisor)  │  │     (Registry)     │  │  (DynamicSupervisor)  │ │
│  └─────────────────────┘  └────────────────────┘  └───────────┬───────────┘ │
│                                                               │              │
│           Shared pool for                  Unique name        │              │
│           async effects                    lookup             │              │
│                                                               │              │
│                            ┌──────────────────────────────────┼──────┐      │
│                            │                                  │      │      │
│                            ▼                                  ▼      ▼      │
│                   ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│                   │  AgentServer 1  │  │  AgentServer 2  │  │ AgentServer │ │
│                   │   (GenServer)   │  │   (GenServer)   │  │     N       │ │
│                   └─────────────────┘  └─────────────────┘  └─────────────┘ │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Process Count

| Agents | Total Processes | Memory |
|--------|-----------------|--------|
| 1 | 4 (3 global + 1 agent) | ~400 KB |
| 100 | 103 | ~10 MB |
| 1,000 | 1,003 | ~100 MB |
| 10,000 | 10,003 | ~1 GB |

---

## 3. Global Supervision Tree

### Application Module

```elixir
defmodule Jido.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: Jido.TaskSupervisor, max_children: 1000},
      {Registry, keys: :unique, name: Jido.Registry},
      {DynamicSupervisor,
        name: Jido.AgentSupervisor,
        strategy: :one_for_one,
        max_restarts: 1000,
        max_seconds: 5}
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: Jido.Supervisor)
  end
end
```

---

## 4. Data Types (Zoi Schemas)

All AgentServer data structures are defined using Zoi for type safety and validation. Helper modules are `@moduledoc false` to keep the public API clean.

### Parent Reference

```elixir
defmodule Jido.Agent.Server.Types.ParentRef do
  @moduledoc false
  
  @schema Zoi.struct(
    __MODULE__,
    %{
      pid: Zoi.any(description: "Parent process PID"),
      id: Zoi.string(description: "Parent instance ID"),
      tag: Zoi.any(description: "Tag assigned by parent when spawning this child"),
      meta: Zoi.map(description: "Arbitrary metadata from parent") |> Zoi.default(%{})
    },
    coerce: true
  )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs), do: Zoi.parse(@schema, attrs)

  @spec new!(map()) :: t()
  def new!(attrs), do: Zoi.parse!(@schema, attrs)
end
```

### Child Info

```elixir
defmodule Jido.Agent.Server.Types.ChildInfo do
  @moduledoc false
  
  @schema Zoi.struct(
    __MODULE__,
    %{
      pid: Zoi.any(description: "Child process PID"),
      ref: Zoi.any(description: "Monitor reference"),
      module: Zoi.atom(description: "Child agent module"),
      meta: Zoi.map(description: "Metadata passed during spawn") |> Zoi.default(%{})
    },
    coerce: true
  )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs), do: Zoi.parse(@schema, attrs)

  @spec new!(map()) :: t()
  def new!(attrs), do: Zoi.parse!(@schema, attrs)
end
```

### Error Policy

```elixir
defmodule Jido.Agent.Server.Types.ErrorPolicy do
  @moduledoc false
  
  @type t ::
    :log_only
    | :stop_on_error
    | {:emit_signal, dispatch_cfg :: term()}
    | {:max_errors, pos_integer()}
    | (Jido.Agent.Directive.Error.t(), state :: map() -> 
        {:ok, map()} | {:stop, term(), map()})

  @spec validate(term()) :: {:ok, t()} | {:error, :invalid_error_policy}
  def validate(:log_only), do: {:ok, :log_only}
  def validate(:stop_on_error), do: {:ok, :stop_on_error}
  def validate({:emit_signal, _cfg} = policy), do: {:ok, policy}
  def validate({:max_errors, n} = policy) when is_integer(n) and n > 0, do: {:ok, policy}
  def validate(fun) when is_function(fun, 2), do: {:ok, fun}
  def validate(_), do: {:error, :invalid_error_policy}
end
```

### Server Options

```elixir
defmodule Jido.Agent.Server.Types.Options do
  @moduledoc false
  
  alias Jido.Agent.Server.Types.{ParentRef, ErrorPolicy}

  @schema Zoi.object(
    %{
      agent: Zoi.any(description: "Agent module (atom) or instantiated agent struct"),
      id: Zoi.string(description: "Instance ID (auto-generated if not provided)") |> Zoi.optional(),
      initial_state: Zoi.map(description: "Initial agent state") |> Zoi.default(%{}),
      registry: Zoi.atom(description: "Registry module") |> Zoi.default(Jido.Registry),
      default_dispatch: Zoi.any(description: "Default dispatch config for Emit") |> Zoi.optional(),
      error_policy: Zoi.any(description: "Error handling policy") |> Zoi.default(:log_only),
      max_queue_size: Zoi.integer(description: "Max directive queue size") 
        |> Zoi.min(1) 
        |> Zoi.default(10_000),
      parent: Zoi.any(description: "Parent reference for hierarchy") |> Zoi.optional(),
      on_parent_death: Zoi.atom(description: "Behavior when parent dies")
        |> Zoi.enum([:stop, :continue, :emit_orphan])
        |> Zoi.default(:stop)
    }
  )

  def schema, do: @schema

  @spec validate(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def validate(opts) when is_list(opts), do: validate(Map.new(opts))
  def validate(opts) when is_map(opts), do: Zoi.parse(@schema, opts)
end
```

### Server State

```elixir
defmodule Jido.Agent.Server.State do
  @moduledoc false
  
  alias Jido.Agent.Server.Types.{ParentRef, ChildInfo}

  @schema Zoi.struct(
    __MODULE__,
    %{
      # Identity
      id: Zoi.string(description: "Instance ID"),
      agent_module: Zoi.atom(description: "Agent behaviour module"),
      agent: Zoi.any(description: "Pure agent struct"),

      # Directive execution
      queue: Zoi.any(description: "Directive queue (:queue.queue())"),
      processing: Zoi.boolean(description: "Is drain loop active?") |> Zoi.default(false),

      # Hierarchy (logical, not OTP)
      parent: Zoi.any(description: "Parent reference") |> Zoi.optional(),
      children: Zoi.map(description: "Child agents by tag") |> Zoi.default(%{}),
      on_parent_death: Zoi.atom(description: "Behavior on parent death") |> Zoi.default(:stop),

      # Configuration
      registry: Zoi.atom(description: "Registry module") |> Zoi.default(Jido.Registry),
      default_dispatch: Zoi.any(description: "Default dispatch config") |> Zoi.optional(),
      error_policy: Zoi.any(description: "Error handling policy") |> Zoi.default(:log_only),
      max_queue_size: Zoi.integer(description: "Max queue size") |> Zoi.default(10_000),

      # Observability
      error_count: Zoi.integer(description: "Cumulative error count") |> Zoi.default(0)
    },
    coerce: true
  )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs), do: Zoi.parse(@schema, attrs)

  @spec new!(map()) :: t()
  def new!(attrs), do: Zoi.parse!(@schema, attrs)
end
```

---

## 5. AgentServer GenServer

### Module Structure

```elixir
defmodule Jido.Agent.Server do
  @moduledoc """
  GenServer runtime for Jido agents.
  
  Manages agent lifecycle, signal processing, and directive execution.
  Uses a single process per agent with an internal directive queue.
  """
  use GenServer
  require Logger

  alias Jido.Agent.Server.State
  alias Jido.Agent.Server.Types.{Options, ChildInfo, ParentRef}
  alias Jido.Signal

  # ============================================================================
  # Public API (Minimal: start, call, cast, state)
  # ============================================================================

  @doc """
  Starts an agent server under `Jido.AgentSupervisor`.
  
  ## Options
  
    * `:agent` - Required. Agent module (atom) or instantiated struct
    * `:id` - Instance ID. Auto-generated if not provided. If agent struct
      has an ID, it takes precedence.
    * `:initial_state` - Initial state map (default: `%{}`)
    * `:registry` - Registry module (default: `Jido.Registry`)
    * `:default_dispatch` - Default dispatch config for `%Emit{}` directives
    * `:error_policy` - Error handling policy (default: `:log_only`)
    * `:max_queue_size` - Max directive queue (default: `10_000`)
    * `:parent` - Parent reference for hierarchy
  
  ## Returns
  
    * `{:ok, pid}` - Successfully started
    * `{:error, reason}` - Failed to start
  """
  @spec start(keyword()) :: {:ok, pid()} | {:error, term()}
  def start(opts) do
    DynamicSupervisor.start_child(Jido.AgentSupervisor, {__MODULE__, opts})
  end

  @doc """
  Starts an agent server (linked to caller, for testing).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    with {:ok, validated} <- Options.validate(opts),
         {:ok, agent, id} <- resolve_agent(validated) do
      name = via_tuple(id, validated.registry)
      GenServer.start_link(__MODULE__, {agent, id, validated}, name: name)
    end
  end

  @doc """
  Sends a synchronous signal and waits for response.
  
  Returns the updated agent state (not effect results).
  """
  @spec call(GenServer.server(), Signal.t(), timeout()) :: {:ok, term()} | {:error, term()}
  def call(server, %Signal{} = signal, timeout \\ 5000) do
    GenServer.call(server, {:signal, signal}, timeout)
  end

  @doc """
  Sends an asynchronous signal (fire-and-forget).
  """
  @spec cast(GenServer.server(), Signal.t()) :: :ok
  def cast(server, %Signal{} = signal) do
    GenServer.cast(server, {:signal, signal})
  end

  @doc """
  Gets the current server state.
  """
  @spec state(GenServer.server()) :: {:ok, State.t()} | {:error, term()}
  def state(server) do
    GenServer.call(server, :get_state)
  end

  @doc """
  Looks up an agent by ID.
  """
  @spec whereis(String.t(), module()) :: {:ok, pid()} | {:error, :not_found}
  def whereis(id, registry \\ Jido.Registry) do
    case Registry.lookup(registry, id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init({agent, id, opts}) do
    # Monitor parent if provided
    if opts.parent, do: Process.monitor(opts.parent.pid)

    state = State.new!(%{
      id: id,
      agent_module: agent.__struct__,
      agent: agent,
      queue: :queue.new(),
      processing: false,
      parent: opts.parent,
      children: %{},
      on_parent_death: opts.on_parent_death,
      registry: opts.registry,
      default_dispatch: opts.default_dispatch,
      error_policy: opts.error_policy,
      max_queue_size: opts.max_queue_size,
      error_count: 0
    })

    # Use {:continue, :post_init} for async setup
    {:ok, state, {:continue, :post_init}}
  end

  @impl true
  def handle_continue(:post_init, state) do
    # Async initialization work (e.g., emit started signal, register callbacks)
    Logger.debug("AgentServer started: #{state.id}")
    {:noreply, state}
  end

  @impl true
  def handle_call({:signal, signal}, _from, state) do
    new_state = process_signal(signal, state)
    {:reply, {:ok, new_state.agent}, new_state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(:get_children, _from, state) do
    {:reply, {:ok, state.children}, state}
  end

  def handle_call({:get_child, tag}, _from, state) do
    {:reply, {:ok, Map.get(state.children, tag)}, state}
  end

  def handle_call(:queue_length, _from, state) do
    {:reply, {:ok, :queue.len(state.queue)}, state}
  end

  @impl true
  def handle_cast({:signal, signal}, state) do
    {:noreply, process_signal(signal, state)}
  end

  @impl true
  def handle_info(:drain, state) do
    {:noreply, drain_queue(state)}
  end

  def handle_info({:scheduled_signal, signal}, state) do
    {:noreply, process_signal(signal, state)}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    state
    |> handle_child_down(ref, pid, reason)
    |> handle_parent_down(pid, reason)
  end

  def handle_info({ref, _result}, state) when is_reference(ref) do
    # Task completion - flush monitor
    Process.demonitor(ref, [:flush])
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) when is_reference(ref) do
    # Task failure - already handled by Task.Supervisor
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("AgentServer #{state.id} terminating: #{inspect(reason)}")
    :ok
  end

  # ============================================================================
  # Private: Agent Resolution
  # ============================================================================

  defp resolve_agent(%{agent: agent} = opts) do
    cond do
      # Agent module passed - instantiate it
      is_atom(agent) ->
        resolve_agent_module(agent, opts)

      # Agent struct passed - use it directly
      is_struct(agent) ->
        resolve_agent_struct(agent, opts)

      true ->
        {:error, :invalid_agent}
    end
  end

  defp resolve_agent_module(module, opts) do
    case Code.ensure_loaded(module) do
      {:module, _} ->
        if function_exported?(module, :new, 2) do
          id = resolve_id(nil, opts.id)
          agent = module.new(id, opts.initial_state)
          {:ok, agent, id}
        else
          {:error, {:invalid_agent_module, module}}
        end

      {:error, reason} ->
        {:error, {:module_not_found, module, reason}}
    end
  end

  defp resolve_agent_struct(agent, opts) do
    agent_id = Map.get(agent, :id)
    provided_id = opts.id

    # Reconcile IDs: agent's ID takes precedence if non-empty
    id = resolve_id(agent_id, provided_id)

    # Warn if IDs conflict
    if non_empty?(provided_id) and non_empty?(agent_id) and provided_id != agent_id do
      Logger.warning(
        "ID mismatch: provided '#{provided_id}' superseded by agent's '#{agent_id}'"
      )
    end

    {:ok, agent, id}
  end

  defp resolve_id(agent_id, provided_id) do
    cond do
      non_empty?(agent_id) -> agent_id
      non_empty?(provided_id) -> normalize_id(provided_id)
      true -> Jido.Util.generate_id()
    end
  end

  defp normalize_id(id) when is_binary(id), do: id
  defp normalize_id(id) when is_atom(id), do: Atom.to_string(id)
  defp normalize_id(_), do: Jido.Util.generate_id()

  defp non_empty?(nil), do: false
  defp non_empty?(""), do: false
  defp non_empty?(s) when is_binary(s), do: true
  defp non_empty?(a) when is_atom(a), do: true
  defp non_empty?(_), do: false

  defp via_tuple(id, registry) do
    {:via, Registry, {registry, id}}
  end

  # ============================================================================
  # Private: Signal Processing
  # ============================================================================

  defp process_signal(signal, state) do
    # Delegate to pure agent logic
    {agent, directives} = state.agent_module.handle_signal(state.agent, signal)
    state = %{state | agent: agent}

    # Check queue capacity
    if queue_overflow?(state, directives) do
      Logger.warning("Queue overflow for #{state.id}, dropping #{length(directives)} directives")
      state
    else
      # Enqueue directives
      queue = Enum.reduce(directives, state.queue, fn dir, q ->
        :queue.in({signal, dir}, q)
      end)

      state = %{state | queue: queue}
      start_drain_if_idle(state)
    end
  end

  defp queue_overflow?(state, new_directives) do
    :queue.len(state.queue) + length(new_directives) > state.max_queue_size
  end

  defp start_drain_if_idle(%{processing: true} = state), do: state
  defp start_drain_if_idle(%{processing: false} = state) do
    send(self(), :drain)
    %{state | processing: true}
  end

  # ============================================================================
  # Private: Drain Loop
  # ============================================================================

  defp drain_queue(%{queue: queue} = state) do
    case :queue.out(queue) do
      {{:value, {signal, directive}}, rest} ->
        state = %{state | queue: rest}

        case Jido.Agent.Server.DirectiveExecutor.execute(directive, signal, state) do
          {:ok, new_state} ->
            send(self(), :drain)
            new_state

          {:async, _ref, new_state} ->
            send(self(), :drain)
            new_state

          {:stop, reason, new_state} ->
            # Let GenServer handle the stop
            throw({:stop, reason, new_state})
        end

      {:empty, _} ->
        %{state | processing: false}
    end
  catch
    {:stop, reason, final_state} ->
      {:stop, reason, final_state}
  end

  # ============================================================================
  # Private: Hierarchy Handling
  # ============================================================================

  defp handle_child_down(state, ref, pid, reason) do
    case find_child_by_ref(state.children, ref) do
      {tag, _info} ->
        children = Map.delete(state.children, tag)
        state = %{state | children: children}

        # Feed lifecycle signal back to agent
        signal = Signal.new!(%{
          type: "jido.agent.child.exit",
          source: "/agent/#{state.id}",
          data: %{tag: tag, pid: pid, reason: reason}
        })

        {:noreply, process_signal(signal, state)}

      nil ->
        state
    end
  end

  defp handle_parent_down(state, pid, reason) when is_map(state) do
    if state.parent && state.parent.pid == pid do
      case state.on_parent_death do
        :stop ->
          {:stop, :parent_died, state}

        :continue ->
          {:noreply, %{state | parent: nil}}

        :emit_orphan ->
          signal = Signal.new!(%{
            type: "jido.agent.orphaned",
            source: "/agent/#{state.id}",
            data: %{parent_id: state.parent.id, reason: reason}
          })
          {:noreply, process_signal(signal, %{state | parent: nil})}
      end
    else
      {:noreply, state}
    end
  end

  defp handle_parent_down({:noreply, state}, _pid, _reason), do: {:noreply, state}

  defp find_child_by_ref(children, ref) do
    Enum.find(children, fn {_tag, info} -> info.ref == ref end)
  end
end
```

---

## 6. Public API

The public API is intentionally minimal: **start, call, cast, state**.

### Summary

| Function | Type | Purpose |
|----------|------|---------|
| `start/1` | — | Start agent under supervisor |
| `start_link/1` | — | Start agent (linked, for testing) |
| `call/3` | sync | Send signal, wait for agent update |
| `cast/2` | async | Send signal, fire-and-forget |
| `state/1` | sync | Get current server state |
| `whereis/2` | — | Lookup agent by ID |

### Usage Examples

```elixir
# Start an agent (module)
{:ok, pid} = Jido.Agent.Server.start(agent: MyAgent, id: "user-123")

# Start an agent (pre-built struct)
agent = MyAgent.new("user-123", %{counter: 10})
{:ok, pid} = Jido.Agent.Server.start(agent: agent)

# Send sync signal
signal = Signal.new!(%{type: "user.action", data: %{action: :increment}})
{:ok, updated_agent} = Jido.Agent.Server.call(pid, signal)

# Send async signal
:ok = Jido.Agent.Server.cast(pid, signal)

# Get state
{:ok, state} = Jido.Agent.Server.state(pid)

# Lookup by ID
{:ok, pid} = Jido.Agent.Server.whereis("user-123")
```

---

## 7. Signal Processing Pipeline

### Flow Diagram

```
Signal arrives
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│                     handle_cast/call                            │
│  1. Translate signal → action (via handle_signal/2)             │
│  2. Run pure agent logic: cmd(agent, action) → {agent, dirs}    │
│  3. Update agent in state                                       │
│  4. Enqueue directives (fast, append to queue)                  │
│  5. Trigger drain loop if idle                                  │
└─────────────────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│                      :drain loop                                │
│  1. Pop directive from queue                                    │
│  2. Execute via DirectiveExecutor protocol                      │
│  3. Handle result: {:ok, state} | {:async, ref, state} | :stop  │
│  4. Continue draining until queue empty                         │
└─────────────────────────────────────────────────────────────────┘
```

### Signal → Action Translation

In `use Jido.Agent` macro, generate a default `handle_signal/2`:

```elixir
defmacro __using__(_opts) do
  quote do
    @doc "Default signal handler - translates to cmd/2"
    def handle_signal(agent, %Jido.Signal{} = signal) do
      action = signal_to_action(signal)
      cmd(agent, action)
    end

    @doc "Override to customize signal → action translation"
    def signal_to_action(%Jido.Signal{type: type, data: data}) do
      {type, data}
    end

    defoverridable [handle_signal: 2, signal_to_action: 1]
  end
end
```

---

## 8. Directive Execution Protocol

### Protocol Definition

```elixir
defprotocol Jido.Agent.Server.DirectiveExecutor do
  @moduledoc """
  Protocol for executing directives.
  
  Implement for custom directive types to extend AgentServer.
  """
  
  @spec execute(struct(), Jido.Signal.t(), Jido.Agent.Server.State.t()) ::
          {:ok, Jido.Agent.Server.State.t()}
          | {:async, reference() | nil, Jido.Agent.Server.State.t()}
          | {:stop, term(), Jido.Agent.Server.State.t()}
  def execute(directive, input_signal, state)
end
```

### Core Implementations

#### Emit (async)

```elixir
defimpl Jido.Agent.Server.DirectiveExecutor, for: Jido.Agent.Directive.Emit do
  def execute(%{signal: signal, dispatch: dispatch}, _input, state) do
    cfg = dispatch || state.default_dispatch

    Task.Supervisor.start_child(Jido.TaskSupervisor, fn ->
      Jido.Signal.Dispatch.dispatch(signal, cfg)
    end)

    {:async, nil, state}
  end
end
```

#### SpawnAgent (hierarchy)

```elixir
defmodule Jido.Agent.Directive.SpawnAgent do
  @moduledoc "Spawn a child agent with parent-child tracking."

  @schema Zoi.struct(
    __MODULE__,
    %{
      agent_module: Zoi.atom(description: "Agent module to spawn"),
      tag: Zoi.any(description: "Tag for tracking this child"),
      opts: Zoi.map(description: "Options for child agent") |> Zoi.default(%{}),
      parent_meta: Zoi.map(description: "Metadata to pass to child") |> Zoi.default(%{})
    },
    coerce: true
  )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema
end

defimpl Jido.Agent.Server.DirectiveExecutor, for: Jido.Agent.Directive.SpawnAgent do
  alias Jido.Agent.Server.Types.ChildInfo

  def execute(%{agent_module: mod, tag: tag, opts: opts, parent_meta: meta}, _sig, state) do
    child_id = opts[:id] || "#{state.id}/#{tag}"

    child_opts = [
      agent: mod,
      id: child_id,
      parent: %{
        pid: self(),
        id: state.id,
        tag: tag,
        meta: meta
      }
    ] ++ Map.to_list(opts)

    {:ok, pid} = Jido.Agent.Server.start(child_opts)
    ref = Process.monitor(pid)

    child_info = ChildInfo.new!(%{
      pid: pid,
      ref: ref,
      module: mod,
      meta: meta
    })

    children = Map.put(state.children, tag, child_info)
    {:ok, %{state | children: children}}
  end
end
```

#### Schedule (timer)

```elixir
defimpl Jido.Agent.Server.DirectiveExecutor, for: Jido.Agent.Directive.Schedule do
  def execute(%{delay_ms: delay, message: message}, _input, state) do
    # Wrap message in signal if not already
    signal = case message do
      %Jido.Signal{} = s -> s
      other -> Jido.Signal.new!(%{type: "scheduled", data: %{message: other}})
    end

    Process.send_after(self(), {:scheduled_signal, signal}, delay)
    {:ok, state}
  end
end
```

#### Stop

```elixir
defimpl Jido.Agent.Server.DirectiveExecutor, for: Jido.Agent.Directive.Stop do
  def execute(%{reason: reason}, _signal, state) do
    {:stop, reason, state}
  end
end
```

#### Error (policy-based)

```elixir
defimpl Jido.Agent.Server.DirectiveExecutor, for: Jido.Agent.Directive.Error do
  def execute(error_dir, _signal, state) do
    Jido.Agent.Server.ErrorPolicy.handle(error_dir, state)
  end
end
```

---

## 9. Hierarchical Agent Management

### Logical Hierarchy (Flat OTP)

All agents live under `Jido.AgentSupervisor`. Parent-child is tracked in state:

```
OTP Supervision (Flat):
────────────────────────
Jido.AgentSupervisor
├── AgentServer["orchestrator"]
├── AgentServer["orchestrator/worker_1"]
└── AgentServer["orchestrator/worker_2"]

Logical Hierarchy (In State):
─────────────────────────────
orchestrator (parent: nil)
├── worker_1 (parent: {pid, "orchestrator", :worker_1})
└── worker_2 (parent: {pid, "orchestrator", :worker_2})
```

### Lifecycle Signals

| Signal Type | When | Data |
|-------------|------|------|
| `jido.agent.child.exit` | Child dies | `%{tag, pid, reason}` |
| `jido.agent.orphaned` | Parent dies (if `:emit_orphan`) | `%{parent_id, reason}` |

---

## 10. Error Handling & Policies

### Error Policy Module

```elixir
defmodule Jido.Agent.Server.ErrorPolicy do
  @moduledoc false
  require Logger

  alias Jido.Agent.Directive.Error, as: ErrorDirective

  def handle(%ErrorDirective{error: error, context: context}, state) do
    case state.error_policy do
      :log_only ->
        Logger.error("Agent error [#{inspect(context)}]: #{inspect(error)}")
        {:ok, state}

      :stop_on_error ->
        Logger.error("Agent stopping: #{inspect(error)}")
        {:stop, {:agent_error, error}, state}

      {:emit_signal, dispatch_cfg} ->
        signal = build_error_signal(error, context, state)
        Jido.Signal.Dispatch.dispatch(signal, dispatch_cfg)
        {:ok, state}

      {:max_errors, max} ->
        count = state.error_count + 1
        state = %{state | error_count: count}

        if count >= max do
          {:stop, {:max_errors_exceeded, count}, state}
        else
          Logger.error("Agent error #{count}/#{max}: #{inspect(error)}")
          {:ok, state}
        end

      fun when is_function(fun, 2) ->
        try do
          fun.(%ErrorDirective{error: error, context: context}, state)
        rescue
          e ->
            Logger.error("Error policy crashed: #{Exception.message(e)}")
            {:ok, state}
        end
    end
  end

  defp build_error_signal(error, context, state) do
    Jido.Signal.new!(%{
      type: "jido.agent.error",
      source: "/agent/#{state.id}",
      data: %{error: error, context: context}
    })
  end
end
```

---

## 11. Backpressure & Observability

### Queue Metrics

```elixir
# Get queue length
{:ok, len} = Jido.Agent.Server.call(server, :queue_length)

# Check if busy (via state)
{:ok, state} = Jido.Agent.Server.state(server)
busy? = :queue.len(state.queue) > 1000
```

### Configuration

```elixir
Jido.Agent.Server.start(
  agent: MyAgent,
  max_queue_size: 5000,
  error_policy: {:max_errors, 10}
)
```

---

## 12. Migration from V1

### Key Changes

| V1 | V2 |
|----|-----|
| Multiple modules (ServerState, ServerRuntime, etc.) | Single module + helper types |
| Signal queue + pending signals | Single directive queue |
| `:auto`/`:step`/`:debug` modes | Removed |
| `handle_signal/2` vs `cmd/2` ambiguity | `cmd/2` canonical |
| Complex child supervisor | Flat OTP + logical hierarchy |
| Custom `call`/`cast` wrappers | Standard `call`/`cast` + minimal public API |

### Migration Steps

1. **Update agent modules** — Ensure `cmd/2` handles all actions
2. **Use new start API** — `Jido.Agent.Server.start(agent: MyAgent)`
3. **Replace signal handling** — Use `call/2` and `cast/2`
4. **Update hierarchy** — Use `SpawnAgent` directive

---

## Summary

| Component | Type | Count | Purpose |
|-----------|------|-------|---------|
| `Jido.Supervisor` | Supervisor | 1 | Application root |
| `Jido.TaskSupervisor` | Task.Supervisor | 1 | Async work pool |
| `Jido.Registry` | Registry | 1 | Name lookup |
| `Jido.AgentSupervisor` | DynamicSupervisor | 1 | Parent of all agents |
| `Jido.Agent.Server` | GenServer | N | Agent logic + state |

**Per-agent overhead:** 1 process (~100 KB)  
**Data validation:** Zoi schemas for all types  
**Public API:** `start`, `call`, `cast`, `state`, `whereis`  
**Extensibility:** `DirectiveExecutor` protocol

---

*Specification Version: 2.0.0-draft*  
*Last Updated: December 2024*

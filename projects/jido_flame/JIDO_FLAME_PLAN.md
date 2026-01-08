# JIDO_FLAME_PLAN.md

> **Status**: Draft  
> **Created**: January 2026  
> **Goal**: Enable Jido agents to spawn remote Fly.io machines via FLAME, run child agents on those remote machines, and return results while maintaining Erlang distribution connectivity.

---

## 1. TL;DR

`jido_flame` is a small integration layer that lets Jido v2 agents offload work to FLAME pools (local or Fly.io) using new FLAME-aware directives and actions.  

Remote child agents are started via `FLAME.place_child/3`, tracked in Jido's parent-child hierarchy, and coordinate with parents using the existing signal system across distributed Erlang nodes.

---

## 2. High-Level Design

### Critical Insight: FLAME Process Linking

**By default, `FLAME.place_child/3` links the caller to the remote child.** If the caller dies, the remote child is terminated. This is problematic for Jido agents that may restart due to supervision — a transient agent restart would kill all remote work.

**Solution:** The **Owner Proxy Pattern** — dedicated `JidoFlame.Owner` processes call `FLAME.place_child/3` and own the link. Jido agents communicate with Owners, not directly with remote children. This decouples agent lifetime from remote work lifetime.

### Architecture with Owner Pattern

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Main Node                                       │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ MyApp.Supervisor                                                          │
│  │  ├── Jido.Agent.Supervisor                                               ││
│  │  │    └── Jido Agent (may restart)                                       ││
│  │  │         └── logical_agent_id: "agent-123"                             ││
│  │  │                                                                       ││
│  │  ├── JidoFlame.OwnerSupervisor (DynamicSupervisor)                       ││
│  │  │    └── JidoFlame.Owner (per remote child)                             ││
│  │  │         ├── logical_agent_id: "agent-123"                             ││
│  │  │         ├── child_pid: <remote_child@runner>                          ││
│  │  │         └── ← LINK → remote child                                     ││
│  │  │                                                                       ││
│  │  ├── JidoFlame.AgentRegistry                                             ││
│  │  │    └── {"agent-123" => <agent_pid>}                                   ││
│  │  │                                                                       ││
│  │  ├── JidoFlame.ChildRegistry                                             ││
│  │  │    └── {"agent-123" => [<owner_pid_1>, <owner_pid_2>]}                ││
│  │  │                                                                       ││
│  │  └── FLAME.Pool (MyApp.FlamePool)                                        ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        │ Owner calls FLAME.place_child/3
                                        │ (Owner ← LINK → remote child)
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Remote FLAME Runner Node                            │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ Runner Supervisor                                                        ││
│  │  └── DynamicSupervisor (child_placement_sup)                             ││
│  │       └── Child Agent (restart: :temporary)                              ││
│  │            ├── logical_parent_id: "agent-123"                            ││
│  │            ├── owner_pid: <owner@main_node>                              ││
│  │            └── Signals → Owner → Agent (via registry lookup)             ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
```

### Signal Flow (Remote Child → Logical Parent)

```
Remote Child                     Owner                          Jido Agent
    │                              │                                 │
    │  emit_to_parent(signal)      │                                 │
    ├─────────────────────────────►│                                 │
    │                              │  lookup(logical_agent_id)       │
    │                              ├────────────────────────────────►│
    │                              │  (via AgentRegistry)            │
    │                              │                                 │
    │                              │  forward {:remote_child, ...}   │
    │                              ├────────────────────────────────►│
    │                              │                                 │
```

**Key Components:**

1. **Directives (data only)** — New FLAME-specific directives under `JidoFlame.Directive.*`:
   - `RemoteCall` → `FLAME.call/3`
   - `RemoteCast` → `FLAME.cast/3`
   - `PlaceRemoteChild` → `FLAME.place_child/3` (generic remote processes)
   - `SpawnRemoteAgent` → specialized for Jido agents with hierarchy tracking
   - `StopRemoteAgent` → coordinated shutdown of remote child agent

2. **Runtime Executor** — `JidoFlame.DirectiveExec` implements execution of the above directives

3. **Actions & Skill** — `JidoFlame.Skill` provides FLAME actions for easy agent composition

4. **Parent-child semantics** — Remote agents tracked like local children, with `remote?: true` metadata

5. **Supervision & Configuration** — FLAME pools alongside Jido in supervision tree

---

## 3. Directives

All directives live in `JidoFlame.Directive`. They are bare structs with Zoi schemas, matching the pattern in `Jido.Agent.Directive`.

### 3.1 `JidoFlame.Directive.RemoteCall`

**Purpose:** Declaratively describe a `FLAME.call/3` operation with optional result signaling.

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `pool` | atom | FLAME.Pool name or pid (required) |
| `fun` | function | 0-arity function/closure executed remotely (required) |
| `opts` | keyword | Options for FLAME.call/3 (default: []) |
| `result_type` | string | CloudEvents type for result signal (optional) |
| `result_dispatch` | term | Dispatch config for result signal (optional) |
| `tag` | term | Correlation tag (optional) |

**Semantics:**
- Runtime executes `FLAME.call(pool, fun, opts)`
- If `result_type` present, wrap result in a Signal and dispatch
- Errors become `%Directive.Error{}` plus optional failure signal

### 3.2 `JidoFlame.Directive.RemoteCast`

**Purpose:** Declaratively describe a `FLAME.cast/3` (fire-and-forget).

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `pool` | atom | FLAME.Pool name or pid (required) |
| `fun` | function | 0-arity function/closure (required) |
| `opts` | keyword | Options for FLAME.cast/3 (default: []) |
| `tag` | term | Correlation tag (optional) |

### 3.3 `JidoFlame.Directive.PlaceRemoteChild`

**Purpose:** Generic remote child placement via `FLAME.place_child/3`.

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `pool` | atom | FLAME.Pool name or pid (required) |
| `child_spec` | term | Supervisor child_spec (required) |
| `opts` | keyword | Options for FLAME.place_child/3 (default: []) |
| `tag` | term | Correlation/tracking tag (optional) |
| `track?` | boolean | Track in parent's children map (default: false) |

### 3.4 `JidoFlame.Directive.SpawnRemoteAgent`

**Purpose:** Start a child Jido agent on a remote FLAME runner with full hierarchy tracking.

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `pool` | atom | FLAME.Pool name (required) |
| `agent` | module/struct | Agent module or pre-built struct (required) |
| `tag` | term | Tracking tag in children map (required) |
| `opts` | map | Options passed to AgentServer (default: %{}) |
| `meta` | map | Metadata passed via ParentRef (default: %{}) |
| `jido` | atom | Jido instance name on remote node (optional) |
| `flame_opts` | keyword | Options for FLAME.place_child/3 (default: []) |

**Runtime Semantics:**

1. Build child_spec for remote node with `ParentRef` pointing to local parent
2. Execute `FLAME.place_child(pool, child_spec, flame_opts)`
3. On success:
   - Record child in parent's children map with `remote?: true`, `node`, `pool`
   - Emit `jido.flame.remote.agent.started` signal
4. On failure:
   - Emit `jido.flame.remote.agent.failed` signal
   - Return `%Directive.Error{}`

### 3.5 `JidoFlame.Directive.StopRemoteAgent`

**Purpose:** Coordinate shutdown of a remote child agent.

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `tag` | term | Child tag in parent's children map (required) |
| `reason` | term | Shutdown reason (default: :normal) |

---

## 4. Actions

Actions are convenience wrappers that build directives. They live under `JidoFlame.Actions.*`.

### 4.1 `JidoFlame.Actions.SpawnRemoteAgent`

**Name:** `"jido.flame.remote.agent.spawn"`

```elixir
defmodule JidoFlame.Actions.SpawnRemoteAgent do
  use Jido.Action,
    name: "jido.flame.remote.agent.spawn",
    description: "Spawn a child agent on a remote FLAME runner",
    schema: [
      pool: [type: :atom, required: true, doc: "FLAME pool name"],
      agent: [type: :atom, required: true, doc: "Agent module to spawn"],
      tag: [type: :any, required: true, doc: "Tracking tag"],
      opts: [type: :map, default: %{}, doc: "AgentServer options"],
      meta: [type: :map, default: %{}, doc: "Parent metadata"],
      flame_opts: [type: :keyword_list, default: [], doc: "FLAME options"]
    ]

  @impl true
  def run(params, _context) do
    directive = %JidoFlame.Directive.SpawnRemoteAgent{
      pool: params.pool,
      agent: params.agent,
      tag: params.tag,
      opts: Map.get(params, :opts, %{}),
      meta: Map.get(params, :meta, %{}),
      flame_opts: Map.get(params, :flame_opts, [])
    }
    {:ok, %{}, [directive]}
  end
end
```

### 4.2 `JidoFlame.Actions.RemoteCall`

**Name:** `"jido.flame.remote.call"`

Supports both MFA and raw function syntax:

```elixir
defmodule JidoFlame.Actions.RemoteCall do
  use Jido.Action,
    name: "jido.flame.remote.call",
    description: "Execute a function on a remote FLAME runner",
    schema: [
      pool: [type: :atom, required: true],
      mfa: [type: :map, doc: "Module/function/args map"],
      fun: [type: :any, doc: "0-arity function (alternative to mfa)"],
      timeout: [type: :integer, default: 30_000],
      result_type: [type: :string, doc: "Signal type for result"],
      tag: [type: :any]
    ]

  @impl true
  def run(params, _context) do
    fun = resolve_function(params)
    
    directive = %JidoFlame.Directive.RemoteCall{
      pool: params.pool,
      fun: fun,
      opts: [timeout: params[:timeout] || 30_000],
      result_type: params[:result_type],
      tag: params[:tag]
    }
    {:ok, %{}, [directive]}
  end

  defp resolve_function(%{fun: fun}) when is_function(fun, 0), do: fun
  defp resolve_function(%{mfa: %{module: m, function: f, args: a}}), 
    do: fn -> apply(m, f, a) end
end
```

---

## 5. Signals & Lifecycle Events

CloudEvents-compliant signals for all lifecycle events:

### Remote Agent Lifecycle

| Signal Type | When Emitted | Key Data Fields |
|-------------|--------------|-----------------|
| `jido.flame.remote.agent.started` | Spawn success | `tag`, `child.pid`, `child.node`, `pool` |
| `jido.flame.remote.agent.failed` | Spawn failure | `tag`, `reason`, `pool` |
| `jido.agent.child.exit` | Child exits | `tag`, `pid`, `node`, `reason`, `remote?: true` |

### Remote Call Lifecycle

| Signal Type | When Emitted | Key Data Fields |
|-------------|--------------|-----------------|
| `jido.flame.call.completed` | Call success | `tag`, `pool`, `result` |
| `jido.flame.call.failed` | Call failure | `tag`, `pool`, `error` |

---

## 6. Owner Process Pattern (Resilient Remote Children)

### The Problem

FLAME's default behavior links the caller of `FLAME.place_child/3` to the remote child. If the caller dies, the remote child is killed. Since Jido agents are supervised and may restart (transient failures, hot code upgrades, etc.), we cannot have agents directly call `place_child/3`.

### The Solution: JidoFlame.Owner

A dedicated GenServer per remote child that:
1. **Owns the FLAME link** — calls `FLAME.place_child/3` in its `init/1`
2. **Survives agent restarts** — lives under a separate `DynamicSupervisor`
3. **Bridges signals** — forwards remote child events to the current agent via registry lookup
4. **Enables clean shutdown** — killing the Owner kills the remote child (via link)

### 6.1 JidoFlame.Owner Implementation

```elixir
defmodule JidoFlame.Owner do
  @moduledoc """
  Owns the link to a remote FLAME child, decoupling agent lifetime from remote work.
  """
  use GenServer
  require Logger

  defstruct [:logical_agent_id, :tag, :pool, :child_pid, :child_ref, :runner_node]

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(%{logical_agent_id: agent_id, pool: pool, child_spec: spec, tag: tag} = args) do
    Process.flag(:trap_exit, true)

    case FLAME.place_child(pool, spec) do
      {:ok, child_pid} ->
        # Monitor the child for graceful handling (link handles crash propagation)
        child_ref = Process.monitor(child_pid)
        
        # Register in ChildRegistry for this agent
        JidoFlame.ChildRegistry.register(agent_id, tag, self())

        state = %__MODULE__{
          logical_agent_id: agent_id,
          tag: tag,
          pool: pool,
          child_pid: child_pid,
          child_ref: child_ref,
          runner_node: node(child_pid)
        }

        # Notify the agent of successful spawn
        notify_agent(state, {:remote_child_started, tag, child_pid, node(child_pid)})

        {:ok, state}

      {:error, reason} ->
        # Notify agent of failure, then exit
        notify_agent_by_id(agent_id, {:remote_child_failed, tag, reason})
        {:stop, {:spawn_failed, reason}}
    end
  end

  @impl true
  def handle_info({:EXIT, child_pid, reason}, %{child_pid: child_pid} = state) do
    Logger.debug("Remote child exited: #{inspect(reason)}")
    notify_agent(state, {:remote_child_exit, state.tag, child_pid, reason})
    JidoFlame.ChildRegistry.unregister(state.logical_agent_id, state.tag)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, %{child_ref: ref, child_pid: pid} = state) do
    # Child down via monitor (e.g., node disconnect)
    Logger.debug("Remote child DOWN: #{inspect(reason)}")
    notify_agent(state, {:remote_child_exit, state.tag, pid, reason})
    JidoFlame.ChildRegistry.unregister(state.logical_agent_id, state.tag)
    {:stop, :normal, state}
  end

  # Forward messages from remote child to logical parent
  @impl true
  def handle_info({:remote_child_signal, signal}, state) do
    notify_agent(state, {:remote_child_signal, state.tag, signal})
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Owner received: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    JidoFlame.ChildRegistry.unregister(state.logical_agent_id, state.tag)
    :ok
  end

  defp notify_agent(%{logical_agent_id: agent_id}, event) do
    notify_agent_by_id(agent_id, event)
  end

  defp notify_agent_by_id(agent_id, event) do
    case JidoFlame.AgentRegistry.lookup(agent_id) do
      {:ok, agent_pid} ->
        send(agent_pid, {:jido_flame, event})
      :error ->
        Logger.debug("No agent registered for #{agent_id}, event dropped: #{inspect(event)}")
    end
  end
end
```

### 6.2 Registry Modules

```elixir
defmodule JidoFlame.AgentRegistry do
  @moduledoc "Maps logical_agent_id → current agent pid"
  
  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: __MODULE__)
  end

  def register(logical_agent_id) do
    Registry.register(__MODULE__, logical_agent_id, nil)
  end

  def unregister(logical_agent_id) do
    Registry.unregister(__MODULE__, logical_agent_id)
  end

  def lookup(logical_agent_id) do
    case Registry.lookup(__MODULE__, logical_agent_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end
end

defmodule JidoFlame.ChildRegistry do
  @moduledoc "Maps {logical_agent_id, tag} → owner pid"
  
  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: __MODULE__)
  end

  def register(logical_agent_id, tag, owner_pid) do
    Registry.register(__MODULE__, {logical_agent_id, tag}, owner_pid)
  end

  def unregister(logical_agent_id, tag) do
    Registry.unregister(__MODULE__, {logical_agent_id, tag})
  end

  def lookup(logical_agent_id, tag) do
    case Registry.lookup(__MODULE__, {logical_agent_id, tag}) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  def list_children(logical_agent_id) do
    Registry.select(__MODULE__, [
      {{{logical_agent_id, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
  end
end
```

### 6.3 Agent Restart & Reattachment

When a Jido agent restarts with the same `logical_agent_id`:

1. **On init**: Register in `JidoFlame.AgentRegistry`
2. **Query existing children**: `JidoFlame.ChildRegistry.list_children(agent_id)`
3. **Reconstruct state**: Remote children continue running; new agent pid receives their signals

```elixir
# In agent's init or mount
def init_flame_children(agent) do
  children = JidoFlame.ChildRegistry.list_children(agent.logical_id)
  
  # Reconstruct children map from registry
  children_map = 
    for {tag, owner_pid} <- children, into: %{} do
      # Query owner for child details
      {:ok, info} = GenServer.call(owner_pid, :get_child_info)
      {tag, Map.put(info, :owner_pid, owner_pid)}
    end
  
  %{agent | state: Map.put(agent.state, :remote_children, children_map)}
end
```

### 6.4 Lifecycle Scenarios

**Scenario A: Agent restarts (transient failure)**
```
1. Agent crashes
2. Supervisor restarts agent with same logical_agent_id
3. Agent registers in AgentRegistry (replaces old entry)
4. Owners continue running, now route signals to new agent pid
5. Agent queries ChildRegistry to rebuild children map
```

**Scenario B: Agent intentionally stopped**
```
1. Agent's terminate/2 calls JidoFlame.stop_all_children(agent_id)
2. Each Owner receives stop → kills remote child via link
3. Owners exit normally
4. ChildRegistry entries cleaned up
```

**Scenario C: Remote child completes work**
```
1. Remote child exits normally
2. Owner receives EXIT, notifies agent
3. Owner unregisters from ChildRegistry and exits
4. Agent updates its children map
```

**Scenario D: Runner node dies**
```
1. Owner receives :DOWN with :noconnection
2. Owner notifies agent of child loss
3. Agent can decide to respawn on another runner
```

---

## 7. Parent-Child Hierarchy

`SpawnRemoteAgent` uses the Owner pattern while maintaining Jido's parent-child semantics:

### Tracking

```elixir
# Parent's children map entry for remote child
%{
  worker_1: %{
    pid: #PID<12345.678.0>,         # Remote child pid
    owner_pid: #PID<0.456.0>,       # Local owner pid
    node: :"myapp_flame_runner@10.0.0.5",
    agent: MyWorkerAgent,
    remote?: true,
    pool: MyApp.FlamePool,
    meta: %{assigned_task: "batch_42"}
  }
}
```

### Monitoring

- **Owner** monitors the remote child (handles :DOWN)
- Owner forwards exit events to agent as `{:jido_flame, {:remote_child_exit, tag, pid, reason}}`
- Agent emits standard `jido.agent.child.exit` signal with `remote?: true`

### Parent Communication

- Child's `__parent__` contains `ParentRef{pid: owner_pid, logical_id: agent_id}`
- `Directive.emit_to_parent/3` sends to Owner, which forwards to current agent pid

---

## 8. FLAME.Pool Integration

### Supervision Layout

```elixir
def start(_type, _args) do
  children =
    case FLAME.Parent.get() do
      nil ->
        # Main node: start pool + full Jido + Owner infrastructure
        [
          # Registries first
          JidoFlame.AgentRegistry,
          JidoFlame.ChildRegistry,
          
          # Owner supervisor
          {DynamicSupervisor, 
           name: JidoFlame.OwnerSupervisor, 
           strategy: :one_for_one},
          
          # Jido instance
          {Jido, name: MyApp.Jido},
          
          # FLAME pool
          {FLAME.Pool,
           name: MyApp.FlamePool,
           backend: Application.get_env(:flame, :backend, FLAME.LocalBackend),
           min: 0,
           max: 10,
           max_concurrency: 5,
           idle_shutdown_after: :timer.seconds(30)}
        ]

      _parent ->
        # FLAME runner node: lean stack, no pool, no Owner infrastructure
        [
          {Jido, name: MyApp.Jido}
          # Optionally: smaller DB pool, no web endpoint
        ]
    end

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

### Configuration

```elixir
# config/config.exs
config :jido_flame,
  default_pool: MyApp.FlamePool

# config/runtime.exs
config :flame,
  backend: 
    if System.get_env("FLY_APP_NAME") do
      {FLAME.FlyBackend, 
       token: System.get_env("FLY_API_TOKEN"),
       app: System.get_env("FLY_APP_NAME")}
    else
      FLAME.LocalBackend
    end
```

---

## 9. Mix Task: `mix jido.flame.doctor`

Diagnostic task to verify FLAME + Jido integration:

```bash
$ mix jido.flame.doctor

JidoFlame Doctor
================

Checking configuration...
✔ FLAME pool configured: MyApp.FlamePool
✔ Backend: FLAME.LocalBackend

Testing RemoteCall...
✔ RemoteCall succeeded
  - Executed on node: :"myapp@127.0.0.1"
  - Round-trip time: 12ms

Testing SpawnRemoteAgent...
✔ SpawnRemoteAgent succeeded
  - Child PID: #PID<0.245.0>
  - Child node: :"myapp@127.0.0.1"
  - Parent received signal: jido.flame.remote.agent.started
  - emit_to_parent verified

✔ All checks passed!

Fly.io Backend Status
---------------------
⚠ Fly backend not configured (set FLY_API_TOKEN to enable)
```

---

## 10. JidoFlame.Skill

Skill for easy agent composition:

```elixir
defmodule JidoFlame.Skill do
  use Jido.Skill,
    name: "flame",
    description: "FLAME remote execution capabilities",
    state_key: :flame,
    actions: [
      JidoFlame.Actions.SpawnRemoteAgent,
      JidoFlame.Actions.RemoteCall,
      JidoFlame.Actions.RemoteCast,
      JidoFlame.Actions.StopRemoteAgent
    ],
    schema: Zoi.object(%{
      default_pool: Zoi.atom() |> Zoi.optional()
    }),
    signal_patterns: ["jido.flame.**"]

  @impl true
  def mount(agent, config) do
    put_in(agent.state.flame, %{
      default_pool: config[:default_pool] || Application.get_env(:jido_flame, :default_pool)
    })
  end

  @impl true
  def router(_agent) do
    [
      {"jido.flame.remote.agent.spawn", JidoFlame.Actions.SpawnRemoteAgent},
      {"jido.flame.remote.call", JidoFlame.Actions.RemoteCall}
    ]
  end
end
```

---

## 11. Package Structure

```
projects/jido_flame/
├── lib/
│   ├── jido_flame.ex                      # Main module + public API
│   ├── jido_flame/
│   │   ├── owner.ex                       # Owner GenServer (FLAME link owner)
│   │   ├── agent_registry.ex              # Maps logical_agent_id → pid
│   │   ├── child_registry.ex              # Maps {agent_id, tag} → owner_pid
│   │   ├── directive/
│   │   │   ├── remote_call.ex
│   │   │   ├── remote_cast.ex
│   │   │   ├── place_remote_child.ex
│   │   │   ├── spawn_remote_agent.ex
│   │   │   └── stop_remote_agent.ex
│   │   ├── actions/
│   │   │   ├── spawn_remote_agent.ex
│   │   │   ├── remote_call.ex
│   │   │   ├── remote_cast.ex
│   │   │   └── stop_remote_agent.ex
│   │   ├── directive_exec.ex              # Directive execution logic
│   │   ├── skill.ex                       # JidoFlame.Skill
│   │   └── test_agent.ex                  # Simple agent for testing
│   └── mix/
│       └── tasks/
│           └── jido.flame.doctor.ex       # Diagnostic mix task
├── test/
│   ├── test_helper.exs
│   ├── directive_test.exs
│   ├── actions_test.exs
│   ├── owner_test.exs                     # Owner process tests
│   ├── registry_test.exs                  # Registry tests
│   └── integration_test.exs
├── config/
│   └── config.exs
├── mix.exs
├── README.md
└── JIDO_FLAME_PLAN.md                     # This file
```

---

## 12. Testing Strategy

### Local / CI (LocalBackend)

- Unit tests for directive schemas and validation
- Integration tests with `FLAME.LocalBackend`:
  - `RemoteCall` returns and signals correctly
  - `SpawnRemoteAgent` updates children map and monitors
  - `emit_to_parent/3` works (same node, but validates mechanics)
  - Lifecycle signals emitted correctly

### Fly.io (Optional Integration)

```elixir
@tag :flame_fly
test "remote agent on actual Fly machine" do
  # Only runs when FLY_API_TOKEN is set
end
```

---

## 13. Dependencies

```elixir
# mix.exs
defp deps do
  [
    {:flame, "~> 0.5"},
    {:jido, path: "../jido"},       # Local workspace dependency
    {:jido_signal, path: "../jido_signal"}
  ]
end
```

---

## 14. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Distributed Erlang misconfiguration | `mix jido.flame.doctor` validates connectivity |
| FLAME pool timeouts | Conservative defaults, configurable timeouts |
| Confusion between local/remote children | `remote?: true` flag in children map and signals |
| Closures not serializable | Document limitations, prefer MFA for complex cases |
| **Caller death kills remote child** | Owner pattern decouples agent lifetime from FLAME links |
| Registry inconsistency on agent restart | Agent re-registers on init; Owners use registry lookup |
| Orphaned Owners if agent never restarts | Implement TTL-based cleanup or require explicit stop |
| High fan-out (many remote children) | One Owner per child; consider batching for 10k+ scale |
| Signal ordering across Owner hops | Include sequence numbers if ordering matters |

---

## 15. Future Enhancements

1. **Full Remote Jido Instance** — Run `{Jido, name: X}` on FLAME runners for remote discovery
2. **Multi-node Orchestration** — Plans/DAGs that span multiple FLAME runners
3. **Custom Backends** — Kubernetes, EC2, etc.
4. **Remote Agent Pools** — Pre-warm pools of specific agent types
5. **Cost Tracking** — Integrate with Fly billing APIs for usage visibility
6. **Persistent Task Table** — Store Owner state in DB/Mnesia for cross-node recovery
7. **Distributed Owner Failover** — Use Horde/swarm for Owner process migration

---

## 16. Implementation Order

1. ✅ Create package structure and mix.exs
2. ⬜ Create AgentRegistry and ChildRegistry modules
3. ⬜ Create JidoFlame.Owner GenServer
4. ⬜ Create directives (data structs with Zoi schemas)
5. ⬜ Create actions (return directives, use Owner for SpawnRemoteAgent)
6. ⬜ Create JidoFlame.Skill
7. ⬜ Create DirectiveExec (execution logic)
8. ⬜ Create mix jido.flame.doctor task
9. ⬜ Write tests (Owner, registries, integration)
10. ⬜ Documentation

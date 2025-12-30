# Jido Process Hierarchy

> A guide to the OTP supervision structure for the Jido agent framework

**Version:** 2.0.0-draft  
**Last Updated:** December 2024

---

## Overview

Jido uses a simple, idiomatic OTP supervision tree optimized for:

- **Clarity** — Easy to understand and debug
- **Scale** — Support 1000s of concurrent agent instances
- **Resilience** — Proper fault isolation and recovery
- **Minimal overhead** — 1 process per agent instance

---

## 1. Global Supervision Tree

The `Jido.Application` starts three global infrastructure processes:

```
Jido.Application
└── Jido.Supervisor (Supervisor, :one_for_one)
    ├── Jido.TaskSupervisor       (Task.Supervisor)
    ├── Jido.Registry             (Registry, :unique)
    └── Jido.AgentSupervisor      (DynamicSupervisor)
        ├── Jido.AgentServer[agent_a]   (GenServer)
        ├── Jido.AgentServer[agent_b]   (GenServer)
        └── ... more agent instances ...
```

### Process Responsibilities

| Process | Type | Purpose |
|---------|------|---------|
| `Jido.Supervisor` | Supervisor | Top-level application supervisor |
| `Jido.TaskSupervisor` | Task.Supervisor | Shared pool for async work (LLM calls, HTTP, heavy directives) |
| `Jido.Registry` | Registry | Unique name registration for agent lookup |
| `Jido.AgentSupervisor` | DynamicSupervisor | Parent of all AgentServer processes |

### Application Module

```elixir
defmodule Jido.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      # Shared task supervisor for async directive/effect work
      {Task.Supervisor, name: Jido.TaskSupervisor},

      # Global registry for agent lookup by ID
      {Registry, keys: :unique, name: Jido.Registry},

      # Dynamic supervisor for all agent instances
      {DynamicSupervisor, 
        name: Jido.AgentSupervisor, 
        strategy: :one_for_one}
    ]

    Supervisor.start_link(children, 
      strategy: :one_for_one, 
      name: Jido.Supervisor)
  end
end
```

---

## 2. Agent Instances

Each agent instance is a **single GenServer** directly supervised by `Jido.AgentSupervisor`:

```
Jido.AgentSupervisor (DynamicSupervisor)
├── Jido.AgentServer["agent_a"] (GenServer)
├── Jido.AgentServer["agent_b"] (GenServer)
└── ...
```

### Why This Structure?

| Aspect | Design Choice | Rationale |
|--------|---------------|-----------|
| **No wrapper supervisor** | Direct GenServer supervision | Simpler, fewer processes, DynamicSupervisor already provides restart semantics |
| **Single process** | GenServer | Holds state, processes signals, manages directive queue |
| **No EffectExecutor process** | Queue inside AgentServer | Fewer processes, simpler coordination, same behavior |
| **Async work** | Via `Jido.TaskSupervisor` | Heavy effects offloaded to global task pool |

### Starting an Agent

```elixir
# Start an agent via DynamicSupervisor
{:ok, pid} = DynamicSupervisor.start_child(
  Jido.AgentSupervisor,
  {Jido.AgentServer, 
    agent_module: MyAgent, 
    id: "user-123-agent",
    default_dispatch: {:pubsub, topic: "events"}
  }
)

# Or via convenience function
{:ok, pid} = Jido.AgentServer.start_link(MyAgent, id: "user-123-agent")
```

---

## 3. AgentServer Internal Structure

The `Jido.AgentServer` GenServer handles everything:

```
┌─────────────────────────────────────────────────────────────────┐
│                      Jido.AgentServer                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  State:                                                          │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ • agent: %Jido.Agent{}        # Pure agent data            │ │
│  │ • agent_module: module()      # Agent behaviour module     │ │
│  │ • instance_id: String.t()     # Unique identifier          │ │
│  │ • runner: module()            # Signal processing strategy │ │
│  │ • queue: :queue.queue()       # Pending directives (FIFO)  │ │
│  │ • processing: boolean()       # Is drain loop running?     │ │
│  │ • children: %{tag => info}    # Tracked child agents       │ │
│  │ • parent: parent_ref | nil    # Parent agent reference     │ │
│  │ • config: map()               # Runtime configuration      │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  Signal Flow:                                                    │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                                                             │ │
│  │  Signal → run_agent (pure) → enqueue directives → drain    │ │
│  │                                     │                       │ │
│  │                                     ▼                       │ │
│  │                          ┌─────────────────────┐           │ │
│  │                          │  Directive Queue    │           │ │
│  │                          │  (in-memory FIFO)   │           │ │
│  │                          └──────────┬──────────┘           │ │
│  │                                     │                       │ │
│  │                          drain loop (sequential)            │ │
│  │                                     │                       │ │
│  │                    ┌────────────────┼────────────────┐     │ │
│  │                    ▼                ▼                ▼     │ │
│  │              %Emit{}          %SpawnAgent{}     %Schedule{}│ │
│  │                │                   │                │      │ │
│  │                ▼                   ▼                ▼      │ │
│  │           Dispatch           start_child      send_after   │ │
│  │         (may use Task)        (global sup)                 │ │
│  │                                                             │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Key Invariants

1. **One drain loop at a time** — The `processing` flag ensures only one `:drain` message is in flight
2. **Directives execute sequentially** — FIFO queue, one directive at a time
3. **Signals process fast** — Pure agent logic runs inline; effects are queued
4. **Heavy work is async** — Tasks spawned via `Jido.TaskSupervisor`

### Directive Queue Implementation

```elixir
# Simplified drain loop inside AgentServer
def handle_info(:drain, %{queue: queue, processing: true} = state) do
  case :queue.out(queue) do
    {{:value, {signal, directive}}, rest} ->
      state = %{state | queue: rest}
      
      case execute_directive(directive, signal, state) do
        {:ok, new_state} ->
          send(self(), :drain)
          {:noreply, new_state}
          
        {:async, _ref, new_state} ->
          # Async work spawned, continue draining
          send(self(), :drain)
          {:noreply, new_state}
          
        {:stop, reason, new_state} ->
          {:stop, reason, new_state}
      end
      
    {:empty, _} ->
      {:noreply, %{state | processing: false}}
  end
end

defp execute_directive(%Directive.Emit{} = emit, _signal, state) do
  # For potentially slow dispatches, use Task
  Task.Supervisor.start_child(Jido.TaskSupervisor, fn ->
    Jido.Signal.Dispatch.dispatch(emit.signal, emit.dispatch || state.config.default_dispatch)
  end)
  {:async, nil, state}
end

defp execute_directive(%Directive.Schedule{} = sched, _signal, state) do
  # Fast, inline
  Process.send_after(self(), {:jido_schedule, sched.message}, sched.delay_ms)
  {:ok, state}
end
```

---

## 4. Agent Hierarchy (Parent-Child)

Child agents are started under the **same global supervisor** (`Jido.AgentSupervisor`), not nested. Hierarchy is **logical**, tracked via:

- `parent_ref` in child's state
- `children` map in parent's state
- Lifecycle signals for coordination

### OTP Supervision Tree (Flat)

```
Jido.AgentSupervisor (DynamicSupervisor)
├── Jido.Agent.Instance["orchestrator"]     # Parent agent
│   └── Jido.AgentServer["orchestrator"]
├── Jido.Agent.Instance["worker_1"]         # Child of orchestrator
│   └── Jido.AgentServer["worker_1"]
└── Jido.Agent.Instance["worker_2"]         # Child of orchestrator
    └── Jido.AgentServer["worker_2"]
```

### Logical Hierarchy (In Agent State)

```
orchestrator (parent_ref: nil)
├── worker_1 (parent_ref: {pid, "orchestrator", :worker_1})
└── worker_2 (parent_ref: {pid, "orchestrator", :worker_2})
```

### Why Flat OTP + Logical Hierarchy?

| Benefit | Description |
|---------|-------------|
| **Simpler supervision** | All agents under one DynamicSupervisor |
| **Easier debugging** | `Jido.AgentSupervisor.which_children/1` shows everything |
| **Consistent restart** | All agents restart via same mechanism |
| **Flexible hierarchy** | Parent-child is a protocol, not hard OTP coupling |

### Parent-Child Communication

**Spawning a child:**

```elixir
# Parent emits SpawnAgent directive
%Directive.SpawnAgent{
  agent_module: WorkerAgent,
  tag: :worker_1,
  opts: %{task: "process_batch"},
  parent_meta: %{batch_id: "abc123"}
}

# Directive execution
DynamicSupervisor.start_child(
  Jido.AgentSupervisor,
  {Jido.Agent.Instance,
    agent_module: WorkerAgent,
    id: "orchestrator/worker_1",
    parent: %{
      pid: parent_pid,
      id: "orchestrator", 
      tag: :worker_1
    }}
)

# Parent tracks child
state.children = Map.put(state.children, :worker_1, %{
  pid: child_pid,
  ref: Process.monitor(child_pid),
  module: WorkerAgent,
  meta: %{batch_id: "abc123"}
})
```

**Lifecycle signals:**

```elixir
# Child started → signal to parent
%Signal{type: "jido.agent.child.started", data: %{tag: :worker_1, ...}}

# Child exited → signal to parent (from :DOWN monitor)
%Signal{type: "jido.agent.child.exit", data: %{tag: :worker_1, reason: :normal, ...}}

# Parent can react and respawn if needed
```

### Parent Death Handling

Since OTP supervision is flat, parent death doesn't automatically kill children. Options:

1. **Children monitor parent** — On `:DOWN`, child decides behavior (stop, continue, find new parent)
2. **Explicit shutdown** — Parent sends shutdown signals to children before stopping
3. **Orphan cleanup** — Background process periodically cleans orphaned agents

```elixir
# Child monitors parent in init
def init(opts) do
  if parent_ref = opts[:parent] do
    Process.monitor(parent_ref.pid)
  end
  # ...
end

# Child handles parent death
def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
  if state.parent && state.parent.pid == pid do
    # Parent died - decide what to do
    case state.config.on_parent_death do
      :stop -> {:stop, :parent_died, state}
      :continue -> {:noreply, %{state | parent: nil}}
      :orphan_signal -> 
        emit_signal("jido.agent.orphaned", state)
        {:noreply, state}
    end
  else
    {:noreply, state}
  end
end
```

---

## 5. Registry and Naming

Agents are registered in `Jido.Registry` by their instance ID:

```elixir
# Registration (in AgentServer.init)
name = {:via, Registry, {Jido.Registry, instance_id}}
GenServer.start_link(__MODULE__, args, name: name)

# Lookup
case Registry.lookup(Jido.Registry, "user-123-agent") do
  [{pid, _meta}] -> {:ok, pid}
  [] -> {:error, :not_found}
end

# Convenience
Jido.AgentServer.whereis("user-123-agent")
```

### Naming Conventions

| Pattern | Example | Use Case |
|---------|---------|----------|
| User-scoped | `"user-123-agent"` | Per-user agent instances |
| Hierarchical | `"orchestrator/worker_1"` | Parent/child relationship in ID |
| Typed | `"chatbot:session-abc"` | Agent type prefix |
| UUID | `"T-a38f981d-52da..."` | Anonymous/ephemeral agents |

---

## 6. Scaling Considerations

### Process Counts

| Agents | Processes | Overhead |
|--------|-----------|----------|
| 1 | 1 | ~100 KB |
| 100 | 100 | ~10 MB |
| 1,000 | 1,000 | ~100 MB |
| 10,000 | 10,000 | ~1 GB |

This is well within BEAM's comfortable range (millions of processes possible).

### Task Supervisor Limits

```elixir
# Configure in application.ex if needed
{Task.Supervisor, 
  name: Jido.TaskSupervisor,
  max_children: 1000}  # Limit concurrent tasks
```

### Per-Agent Backpressure

```elixir
# In AgentServer options
Jido.AgentServer.start_link(MyAgent,
  max_queue: 1000,        # Max pending directives
  max_signals: 5000       # Max pending signals (mailbox proxy)
)

# Check if agent is overloaded
Jido.AgentServer.busy?(pid, threshold: 100)
```

---

## 7. Complete Example

### Full Hierarchy Visualization

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Jido.Application                                │
└───────────────────────────────────┬─────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Jido.Supervisor (:one_for_one)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────┐                                                    │
│  │ Jido.TaskSupervisor │  ◄── Shared pool for async work                   │
│  │  (Task.Supervisor)  │      • LLM API calls                               │
│  │                     │      • HTTP requests                               │
│  │  [task] [task] ...  │      • Heavy directive execution                   │
│  └─────────────────────┘                                                    │
│                                                                              │
│  ┌─────────────────────┐                                                    │
│  │   Jido.Registry     │  ◄── Name lookup                                   │
│  │     (Registry)      │      • "user-123" → pid                            │
│  │                     │      • "orchestrator/worker_1" → pid               │
│  └─────────────────────┘                                                    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                 Jido.AgentSupervisor (DynamicSupervisor)             │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │                                                                      │   │
│  │  ┌───────────────────────────────────────────────────────────────┐  │   │
│  │  │         Jido.AgentServer["orchestrator"] (GenServer)          │  │   │
│  │  │                                                                │  │   │
│  │  │  agent: %OrchestratorAgent{}                                  │  │   │
│  │  │  children: %{worker_1: %{pid: ..}, worker_2: %{..}}           │  │   │
│  │  │  parent: nil                                                   │  │   │
│  │  │  queue: :queue.new()                                           │  │   │
│  │  └───────────────────────────────────────────────────────────────┘  │   │
│  │                                                                      │   │
│  │  ┌───────────────────────────────────────────────────────────────┐  │   │
│  │  │    Jido.AgentServer["orchestrator/worker_1"] (GenServer)      │  │   │
│  │  │                                                                │  │   │
│  │  │  agent: %WorkerAgent{}                                        │  │   │
│  │  │  children: %{}                                                 │  │   │
│  │  │  parent: %{pid: .., id: "orchestrator", tag: :worker_1}       │  │   │
│  │  └───────────────────────────────────────────────────────────────┘  │   │
│  │                                                                      │   │
│  │  ┌───────────────────────────────────────────────────────────────┐  │   │
│  │  │    Jido.AgentServer["orchestrator/worker_2"] (GenServer)      │  │   │
│  │  │                                                                │  │   │
│  │  │  agent: %WorkerAgent{}                                        │  │   │
│  │  │  children: %{}                                                 │  │   │
│  │  │  parent: %{pid: .., id: "orchestrator", tag: :worker_2}       │  │   │
│  │  └───────────────────────────────────────────────────────────────┘  │   │
│  │                                                                      │   │
│  │  ┌───────────────────────────────────────────────────────────────┐  │   │
│  │  │      Jido.AgentServer["user-456-chatbot"] (GenServer)         │  │   │
│  │  │                                                                │  │   │
│  │  │  agent: %ChatbotAgent{}                                       │  │   │
│  │  │  children: %{}                                                 │  │   │
│  │  │  parent: nil                                                   │  │   │
│  │  └───────────────────────────────────────────────────────────────┘  │   │
│  │                                                                      │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 8. Advanced: Nested OTP Hierarchy

If you need strict OTP parent-child semantics (parent death kills children automatically), you can lazily spawn a per-agent `ChildSupervisor`:

```
Jido.AgentSupervisor
└── Jido.AgentServer["orchestrator"]
    └── (lazily spawned) Jido.Agent.ChildSupervisor (DynamicSupervisor)
        ├── Jido.AgentServer["worker_1"]
        └── Jido.AgentServer["worker_2"]
```

This adds:
- **1 extra process per parent** (ChildSupervisor, only when first child is spawned)
- **Automatic child termination** when parent dies
- **More complex restart logic**

**Recommendation:** Start with the flat hierarchy. Add nested supervisors only when you have a proven need for automatic cascading termination.

---

## Summary

| Component | Type | Count | Purpose |
|-----------|------|-------|---------|
| `Jido.Supervisor` | Supervisor | 1 | Application root |
| `Jido.TaskSupervisor` | Task.Supervisor | 1 | Async work pool |
| `Jido.Registry` | Registry | 1 | Name lookup |
| `Jido.AgentSupervisor` | DynamicSupervisor | 1 | Parent of all AgentServers |
| `Jido.AgentServer` | GenServer | N | Agent logic + state |

**Per-agent overhead:** 1 process (~100 KB)  
**Hierarchy:** Flat OTP, logical parent-child via state  
**Async work:** Shared `Jido.TaskSupervisor`

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0.0-draft | Dec 2024 | Initial hierarchy specification |

---

*Specification Version: 2.0.0-draft*  
*Last Updated: December 2024*

# Jido 2.0 Overview

> **Status**: Alpha Implementation Complete  
> **Last Updated**: January 2026

This document provides a comprehensive overview of Jido 2.0, including architecture changes, new features, migration guidance, and a gap analysis compared to Jido 1.x.

---

## Table of Contents

1. [Blog Post Summary](#blog-post-summary)
2. [Architecture Evolution](#architecture-evolution)
3. [New Features in V2](#new-features-in-v2)
4. [Core Systems Deep Dive](#core-systems-deep-dive)
5. [Gap Analysis: V1 vs V2](#gap-analysis-v1-vs-v2)
6. [Migration Guide](#migration-guide)
7. [API Reference](#api-reference)

---

## Blog Post Summary

### Introducing Jido 2.0: Instance-Scoped, Functional Agents for the BEAM

Jido 2.0 is a major evolution of the Jido agent framework for Elixir. What started as a powerful toolkit for building autonomous agents has grown into a fully-fledged, instance-scoped runtime with a functional core, declarative side effects, and a modern event system.

**The Key Changes:**

1. **Instance-Scoped Architecture** — Instead of global singletons, you explicitly add `{Jido, name: MyApp.Jido}` to your supervision tree. Each Jido instance owns its own Registry, TaskSupervisor, AgentSupervisor, and Scheduler.

2. **Elm/Redux-Inspired Agents** — Agent logic is pure and deterministic. Given a state and an input, you get back a new state and a list of **directives** describing side effects. The runtime interprets those directives, keeping your business logic clean and testable.

3. **CloudEvents-Compliant Signals** — All agent communication and system events use structured, interoperable CloudEvents messages with trie-based routing for high-performance dispatch.

4. **DAG-Based Workflows** — A Plan/DAG workflow engine powered by `libgraph` enables complex, parallelizable workflows that are easy to visualize and reason about.

5. **First-Class Skills** — Composable capability modules that encapsulate state schemas, actions, and signal routing in reusable packages.

If you're building autonomous agents, multi-agent systems, or complex workflows on the BEAM, Jido 2.0 gives you a modern, functional, and observable foundation.

---

## Architecture Evolution

### From Global Singleton to Instance-Scoped Runtime

```
┌─────────────────────────────────────────────────────────────────┐
│              V1: Global Runtime                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Global Registry │ Global TaskSupervisor │ Global AgentSup  │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              ↓                                   │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                       │
│  │ Agent A  │  │ Agent B  │  │ Agent C  │  (flat, shared)       │
│  └──────────┘  └──────────┘  └──────────┘                       │
└─────────────────────────────────────────────────────────────────┘

                              ⬇️

┌─────────────────────────────────────────────────────────────────┐
│              V2: Instance-Scoped Runtime                         │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    Jido Instance (Supervisor)               │ │
│  │  ┌──────────────┐  ┌────────────┐  ┌────────────────────┐  │ │
│  │  │ TaskSupervisor│  │  Registry  │  │ AgentSupervisor    │  │ │
│  │  └──────────────┘  └────────────┘  │  (DynamicSupervisor)│  │ │
│  │                                     │    ┌────────────┐   │  │ │
│  │                                     │    │AgentServer │   │  │ │
│  │                                     │    │ ┌────────┐ │   │  │ │
│  │                                     │    │ │ Agent  │ │   │  │ │
│  │                                     │    │ │(struct)│ │   │  │ │
│  │                                     │    │ └────────┘ │   │  │ │
│  │                                     │    └────────────┘   │  │ │
│  │                                     └────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

**Benefits:**
- Multiple Jido instances per BEAM node (multi-tenant, testing, isolated subsystems)
- Better fault isolation and clearer ownership boundaries
- Per-test isolation with `JidoTest.Case`

### From Monolithic to Pure Functional Agents

**V1 Pattern:**
```elixir
# Agents were stateful GenServers with mixed concerns
defmodule MyAgent do
  use Jido.Agent
  
  def handle_call({:do_something, args}, _from, state) do
    # State mutation + side effects mixed
    new_state = update_state(state, args)
    spawn(fn -> send_notification() end)  # Side effect
    {:reply, :ok, new_state}
  end
end
```

**V2 Pattern (Elm/Redux-inspired):**
```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    schema: [...],
    skills: [MyApp.NotificationSkill]

  # Pure function: state + signal → {new_state, directives}
  def cmd(agent, signal) do
    agent = update_in(agent.state.counter, & &1 + 1)
    
    directives = [
      Directive.emit(
        Signal.new!("notification.send", %{message: "Updated"}),
        {:pubsub, topic: "notifications"}
      )
    ]
    
    {agent, directives}
  end
end
```

**Core Pattern:**
```
Signal → AgentServer.call/cast → route_signal → Agent.cmd/2
                                                     ↓
                                          {agent, directives}
                                                     ↓
                                         DirectiveExec.exec/3
```

---

## New Features in V2

### 1. Directive-Based Side Effects

Directives are **first-class effect descriptions** that the runtime interprets:

| Directive | Purpose | Example |
|-----------|---------|---------|
| `Emit` | Dispatch a signal | `Directive.emit(signal, {:pubsub, topic: "events"})` |
| `Error` | Signal an error | `Directive.error(:validation_failed, %{field: :email})` |
| `Spawn` | Spawn generic process | `Directive.spawn(child_spec)` |
| `SpawnAgent` | Spawn child agent | `Directive.spawn_agent(ChildAgent, :worker, opts: %{})` |
| `StopChild` | Stop tracked child | `Directive.stop_child(:worker, :normal)` |
| `Schedule` | Schedule delayed message | `Directive.schedule(5000, :check_status)` |
| `Stop` | Stop self | `Directive.stop(:normal)` |
| `Cron` | Recurring schedule | `Directive.cron("*/5 * * * *", :tick, "job-1")` |
| `CronCancel` | Cancel cron job | `Directive.cron_cancel("job-1")` |

### 2. CloudEvents-Compliant Signal System

Signals implement the **CloudEvents v1.0.2 specification**:

```elixir
%Jido.Signal{
  # Required CloudEvents fields
  id: "0195f6a8-...",           # UUID v7
  source: "/agents/calculator",  # Origin
  type: "calc.result.computed", # Hierarchical type
  specversion: "1.0.2",
  
  # Optional fields
  subject: "calculation-123",
  time: ~U[2026-01-01 00:00:00Z],
  data: %{result: 42},
  
  # Jido extensions
  jido_dispatch: {:pubsub, topic: "results"},
  extensions: %{}
}
```

**Trie-Based Routing:**
```elixir
# Router patterns
{"user.created", HandleUserCreated},           # Exact match
{"user.*.updated", HandleUserUpdate},          # Single wildcard
{"audit.**", AuditLogger, priority: 100},      # Multi-level wildcard
```

### 3. Skills System

Skills are **composable capability modules**:

```elixir
defmodule MyApp.ChatSkill do
  use Jido.Skill,
    name: "chat",
    state_key: :chat,
    actions: [SendMessage, ReceiveMessage],
    schema: Zoi.object(%{
      messages: Zoi.list(Zoi.any()) |> Zoi.default([]),
      unread_count: Zoi.integer() |> Zoi.default(0)
    }),
    signal_patterns: ["chat.*"]

  @impl true
  def mount(agent, config) do
    # Pure initialization - called during Agent.new/1
    put_in(agent.state.chat, %{messages: [], unread_count: 0})
  end

  @impl true
  def router(_agent) do
    [
      {"chat.message.received", ReceiveMessage},
      {"chat.message.send", SendMessage}
    ]
  end
end
```

**Skill Features:**
- Isolated state under `state_key`
- Automatic action registration
- Signal routing rules
- Lifecycle hooks: `mount/2`, `handle_signal/2`, `transform_result/3`
- Child process specs

### 4. Strategy Pattern

Strategies define **how agents execute actions**:

| Strategy | Behavior |
|----------|----------|
| `Direct` | Sequential, immediate execution (default) |
| `FSM` | Finite State Machine with transitions |
| Custom | Behavior trees, LLM chains, etc. |

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "fsm_agent",
    strategy: {Jido.Agent.Strategy.FSM,
      initial_state: "idle",
      transitions: %{
        "idle" => ["processing"],
        "processing" => ["idle", "completed", "failed"]
      }
    }
end
```

### 5. Parent-Child Agent Hierarchy

Agents form supervision trees:

```elixir
def cmd(agent, {:spawn_workers, count}) do
  directives = for i <- 1..count do
    Directive.spawn_agent(WorkerAgent, "worker-#{i}",
      opts: %{task_queue: agent.state.queue},
      meta: %{spawned_at: DateTime.utc_now()}
    )
  end
  
  {agent, directives}
end

# Parent receives child lifecycle signals
def cmd(agent, %Signal{type: "jido.agent.child.exit"} = signal) do
  child_tag = signal.data.tag
  # Handle child completion/failure
  {agent, []}
end
```

**Coordination APIs:**
```elixir
{:ok, state} = Jido.await(server, 30_000)        # Wait for terminal status
{:ok, child_state} = Jido.await_child(server, :worker, 10_000)
children = Jido.get_children(parent)
```

### 6. Plan/DAG Workflow System

Graph-based workflow execution:

```elixir
plan = Plan.new()
  |> Plan.add(:fetch_users, FetchUsersAction)
  |> Plan.add(:fetch_orders, FetchOrdersAction)
  |> Plan.add(:fetch_products, FetchProductsAction)
  |> Plan.add(:merge, MergeAction, 
       depends_on: [:fetch_users, :fetch_orders, :fetch_products])

# Get parallel execution phases
{:ok, phases} = Plan.execution_phases(plan)
# => [[:fetch_users, :fetch_orders, :fetch_products], [:merge]]
```

**As a meta-action:**
```elixir
defmodule MyWorkflow do
  use Jido.Tools.ActionPlan,
    name: "my_workflow"

  @impl Jido.Tools.ActionPlan
  def build(params, context) do
    Plan.new(context: context)
    |> Plan.add(:fetch, FetchAction, params)
    |> Plan.add(:validate, ValidateAction, depends_on: :fetch)
    |> Plan.add(:save, SaveAction, depends_on: :validate)
  end
end
```

### 7. Discovery System

Fast, read-optimized component catalog using `:persistent_term`:

```elixir
# List discovered components
Jido.list_actions(category: :utility, limit: 10)
Jido.list_skills()
Jido.list_sensors()
Jido.list_demos()

# Lookup by slug
Jido.get_action_by_slug("abc123de")

# Refresh catalog
Jido.refresh_discovery()
```

### 8. Enhanced Observability

Telemetry spans throughout the system:

```elixir
Jido.Observe.with_span([:jido, :agent, :action], %{agent_id: id}, fn ->
  # Work with automatic telemetry
end)

# Async spans
span_ctx = Jido.Observe.start_span([:jido, :async], metadata)
Jido.Observe.finish_span(span_ctx, %{extra: measurement})
```

---

## Core Systems Deep Dive

### Agent Struct

```elixir
%Jido.Agent{
  id: String.t(),           # Unique identifier
  name: String.t(),         # Agent name
  description: String.t(),  # Description
  category: String.t(),     # Category
  tags: [String.t()],       # Tags
  vsn: String.t(),          # Version
  schema: term(),           # NimbleOptions or Zoi schema
  state: map()              # Current state
}
```

### Action System

Actions are compile-time validated units of work:

```elixir
defmodule MyAction do
  use Jido.Action,
    name: "my_action",
    description: "Does something useful",
    schema: [
      value: [type: :integer, required: true]
    ],
    output_schema: [
      result: [type: :integer]
    ]
    
  @impl true
  def run(%{value: v}, _context) do
    {:ok, %{result: v * 2}}
  end
end
```

**Execution Flow:**
```
Jido.Exec.run(action, params, context, opts)
    ↓
┌──────────────────────────────────────────┐
│ 1. Normalize params/context              │
│ 2. Validate action module & params       │
│ 3. on_before_validate_params/1           │
│ 4. on_after_validate_params/1            │
├──────────────────────────────────────────┤
│ 5. run/2 with timeout                    │
├──────────────────────────────────────────┤
│ 6. Validate output                       │
│ 7. on_after_run/1                        │
│ 8. Retry on failure (if configured)      │
│ 9. Compensation on error (if enabled)    │
└──────────────────────────────────────────┘
    ↓
{:ok, result} | {:error, reason}
```

### Signal Bus

```
┌───────────────────────────────────────────────────────────────┐
│                        Signal Bus                              │
├───────────────────────────────────────────────────────────────┤
│  BusState                                                      │
│  ├── name: atom                                                │
│  ├── router: Router.t() (trie-based)                          │
│  ├── log: %{uuid => Signal.t()}                               │
│  ├── subscriptions: %{id => Subscriber.t()}                   │
│  ├── middleware: [{module, state}]                            │
│  └── journal_adapter: ETS | Mnesia | InMemory                 │
└───────────────────────────────────────────────────────────────┘
```

**Dispatch Adapters:**
- `:pid` - Direct delivery to process
- `:named` - Delivery to named process
- `:pubsub` - Phoenix.PubSub integration
- `:http` - HTTP requests
- `:webhook` - Webhook with signatures
- `:logger` / `:console` / `:noop`

---

## Gap Analysis: V1 vs V2

### Breaking Changes Summary

| Area | V1 | V2 | Migration Effort |
|------|----|----|------------------|
| **Runtime** | Global singleton | Instance-scoped supervisor | S (add to supervision tree) |
| **Agent Lifecycle** | `AgentServer.start/1` | `Jido.start_agent/3` | S-M |
| **Side Effects** | Mixed in callbacks | Directive-based | M (refactor to directives) |
| **Messaging** | `Jido.Instruction` | CloudEvents Signals | M-L |
| **Orchestration** | Runners (Simple/Chain) | Strategies + Plans | M |
| **Actions** | `Jido.Actions.*` | `Jido.Tools.*` | S (rename) |
| **Validation** | NimbleOptions | Zoi schemas | S-M |
| **Errors** | Ad hoc tuples | Splode structured errors | S-M |

### New in V2 (Not in V1)

1. Instance-scoped Jido Supervisor
2. Pure functional agents with directives
3. CloudEvents-compliant Signal system
4. Trie-based signal routing
5. Parent-child agent hierarchy
6. Plan/DAG workflow system
7. Skills system (elevated from basic to first-class)
8. Discovery via persistent_term
9. Zoi validation
10. Splode error handling
11. Comprehensive telemetry spans
12. Strategy pattern (Direct, FSM, extensible)

### Improved in V2

- **Performance**: Trie routing, persistent_term discovery, per-instance resources
- **Testability**: Pure functional agents, per-test isolation, optimized test suite (~40% faster)
- **Observability**: Telemetry spans throughout lifecycle
- **Developer Experience**: Clear separation of concerns, rich documentation

---

## Migration Guide

### Minimal Migration (Get Running)

**1. Add Jido to your supervision tree:**

```elixir
# application.ex
def start(_type, _args) do
  children = [
    {Jido, name: MyApp.Jido}
  ]
  
  Supervisor.start_link(children, strategy: :one_for_one)
end
```

**2. Update agent starts:**

```elixir
# Before (V1)
{:ok, pid} = MyAgent.start_link(id: "agent-1")

# After (V2)
{:ok, pid} = Jido.start_agent(MyApp.Jido, MyAgent, id: "agent-1")
# or
{:ok, pid} = MyAgent.start_link(id: "agent-1", jido: MyApp.Jido)
```

**3. Update lifecycle calls:**

```elixir
# Before
AgentServer.stop(pid)

# After
Jido.stop_agent(MyApp.Jido, "agent-1")
```

### Intermediate Migration (Embrace V2 Patterns)

**1. Migrate to Skills:**

```elixir
# Before: actions list
use Jido.Agent,
  actions: [ActionA, ActionB]

# After: skills with automatic action registration
use Jido.Agent,
  skills: [MySkill]  # MySkill.actions() returns [ActionA, ActionB]
```

**2. Adopt Directives:**

```elixir
# Before: ad hoc side effects
def handle_result(agent, result) do
  Phoenix.PubSub.broadcast(MyApp.PubSub, "events", result)
  agent
end

# After: declarative directives
def cmd(agent, _signal) do
  {agent, [
    Directive.emit(
      Signal.new!("result.computed", result),
      {:pubsub, topic: "events"}
    )
  ]}
end
```

**3. Use CloudEvents Signals:**

```elixir
# Before: ad hoc messages
send(pid, {:task_complete, %{id: 123}})

# After: structured signals
signal = Jido.Signal.new!("task.completed", %{id: 123}, 
  source: "/workers/processor"
)
Jido.Signal.Dispatch.dispatch(signal, {:pid, target: pid})
```

### Full V2 Adoption

For maximum benefit, refactor agents to the pure functional pattern:

1. **Pure `cmd/2` functions** — No side effects, only return `{agent, directives}`
2. **Zoi schemas** — Strong typing for state and inputs
3. **Strategy selection** — Choose Direct, FSM, or custom
4. **Skills composition** — Package related behavior into reusable skills
5. **Plan-based workflows** — Replace procedural orchestration with DAGs

---

## API Reference

### Jido Instance

```elixir
# Lifecycle
Jido.start_agent(jido, agent_module, opts)
Jido.stop_agent(jido, id_or_pid)
Jido.whereis(jido, id)
Jido.list_agents(jido)
Jido.agent_count(jido)

# Coordination
Jido.await(server, timeout, opts)
Jido.await_child(server, tag, timeout, opts)
Jido.await_all(servers, timeout, opts)
Jido.await_any(servers, timeout, opts)
Jido.get_children(parent)
Jido.get_child(parent, tag)
Jido.alive?(server)
Jido.cancel(server, opts)

# Discovery
Jido.list_actions(opts)
Jido.list_sensors(opts)
Jido.list_skills(opts)
Jido.list_demos(opts)
Jido.get_action_by_slug(slug)
Jido.refresh_discovery()
```

### Agent Definition

```elixir
use Jido.Agent,
  name: "my_agent",              # Required
  description: "...",            # Optional
  category: "...",               # Optional
  tags: ["tag1"],                # Default: []
  vsn: "1.0.0",                  # Optional
  schema: [...],                 # NimbleOptions or Zoi
  strategy: Jido.Agent.Strategy.Direct,  # Default
  skills: [MySkill]              # Default: []
```

### Directive Helpers

```elixir
Directive.emit(signal, dispatch)
Directive.error(type, context)
Directive.spawn(child_spec)
Directive.spawn_agent(module, tag, opts: %{}, meta: %{})
Directive.stop_child(tag, reason)
Directive.schedule(delay_ms, message)
Directive.stop(reason)
Directive.cron(cron_expr, message, job_id)
Directive.cron_cancel(job_id)
Directive.emit_to_pid(signal, pid)
Directive.emit_to_parent(agent, signal)
```

### Signal Creation

```elixir
Jido.Signal.new(type, data, opts)
Jido.Signal.new!(type, data, opts)

# Options: :source, :subject, :id, :time, :datacontenttype
```

---

## Appendix: Package Dependencies

```elixir
# Core packages
{:jido_action, "~> 1.3"}      # Action behavior
{:jido_signal, "~> 1.3"}      # Signal types & dispatch

# Validation & Errors
{:zoi, "~> 0.1"}              # Schema validation
{:splode, "~> 0.2"}           # Structured errors

# Infrastructure
{:phoenix_pubsub, "~> 2.0"}   # Signal dispatch
{:sched_ex, "~> 1.0"}         # Cron scheduling
{:fsmx, "~> 0.5"}             # FSM strategy
{:libgraph, "~> 0.16"}        # DAG workflows

# Optional
{:req_llm, "~> 0.1"}          # LLM integration (for ReAct)
```

---

## Conclusion

Jido 2.0 represents a significant architectural evolution:

- **Cleaner separation** between pure business logic and side effects
- **Stronger foundations** with CloudEvents, Zoi validation, and Splode errors
- **Better scalability** via instance scoping and trie-based routing
- **Enhanced composability** through Skills and DAG-based workflows
- **Improved testability** with pure functional agents and per-test isolation

The migration path is incremental — start with minimal changes to get running, then progressively adopt V2 patterns as you refactor or build new agents.

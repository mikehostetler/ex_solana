# Jido 2.0 - Architecture Overview

Jido's architecture consists of three main layers that work together to provide a complete agent system.

## Layer 1: Core Model Layer

These are the purely functional abstractions you build on. They don't do I/O, don't spawn processes, and don't talk to external systems directly.

### Jido.Agent

Immutable, schema-validated agent state with the `cmd/2` contract.

```elixir
defmodule MyApp.CounterAgent do
  use Jido.Agent,
    name: "counter",
    description: "A simple counter agent",
    schema: [
      count: [type: :integer, default: 0]
    ]
end
```

### Jido.Action (from jido_action)

Pure, validated units of work that transform agent state.

### Jido.Agent.Directive

Typed effect descriptions that tell the runtime what to do:
- `Emit` - Send signals
- `Spawn` / `SpawnAgent` - Create child processes
- `Schedule` / `Cron` - Schedule future work
- `Stop` / `StopChild` - Terminate processes

### Jido.Agent.Strategy

Pluggable execution strategies that determine how an agent runs actions:
- `Direct` - Sequential, immediate execution (default)
- `FSM` - Finite state machine with configurable transitions

Strategies act as **effect interpreters** in functional programming terms. They:
1. Execute instructions via `Jido.Exec.run/1`
2. Merge action results into agent state (pure `state → state` transitions)
3. Apply internal state operations (`Jido.Agent.Internal.*`) when needed
4. Collect external directives to return from `cmd/2`

This separation keeps the public contract pure while enabling rich internal state management.

### Jido.Skill

Composable capability modules that can be attached to agents, providing actions, state slices, signal routing, and lifecycle hooks.

## Layer 2: Runtime & Coordination Layer

This is where OTP and processes come in.

### Jido Instance (`use Jido`)

Defines a Jido instance as a supervisor tree:

```elixir
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app
end
```

Each instance provides:
- A `Task.Supervisor` for async work
- A `Registry` for agent lookup
- A `DynamicSupervisor` for agent processes
- Optional agent pools (`Jido.AgentPool`)

Public API:
- `start_agent/2,3` - Start an agent process
- `stop_agent/1` - Stop an agent
- `whereis/1` - Find an agent by ID
- `list_agents/0` - List all agents
- `agent_count/0` - Count running agents

### Jido.AgentServer

Per-agent GenServer runtime that:
- Wraps a single `Jido.Agent` struct
- Accepts signals and routes them to actions/strategies
- Calls `Agent.cmd/2` and executes resulting directives
- Manages parent-child agent hierarchy
- Handles error policies and directive processing

### Jido.Scheduler

Thin wrapper on `SchedEx` for per-agent cron jobs, integrated via `%Directive.Cron{}` and `%Directive.CronCancel{}`.

### Jido.Await

Synchronous waiting utilities for HTTP controllers, CLI tools, and tests. Waits based on **state**, not process death.

### Jido.Observe

Observability façade providing standardized telemetry and logging around spans of work (agent actions, workflows, async tasks).

### Jido.Discovery

Component catalog that scans loaded applications for components (Actions, Sensors, Agents, Skills, Demos) and stores metadata in `:persistent_term` for fast lookup.

## Layer 3: Integration & Ecosystem Layer

Jido integrates with the broader ecosystem and external systems.

### Jido Ecosystem Packages

- **jido_action** - Action definitions, validation, schemas, AI tool integration
- **jido_signal** - CloudEvents-style signals, routing, dispatch adapters
- **jido_ai** - AI/LLM powered behaviors
- **jido_chat** - Conversational agent behaviors
- **jido_memory** - Long-lived agent memory

### External Integrations

- **OTP Supervision Tree** - Standard Elixir/OTP integration
- **Web / APIs / CLI** - Via agent lookup and signal dispatch
- **Message Buses, PubSub, Webhooks** - Via signal dispatch adapters
- **Cron & Scheduling** - Via directive-based scheduling
- **Observability Stack** - Via telemetry events and tracer hooks

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    External Systems                              │
│  (Web APIs, CLI, Message Buses, PubSub, Webhooks, Cron)         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Integration Layer                              │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌────────────┐ │
│  │ jido_signal │ │  jido_ai    │ │ jido_chat   │ │jido_memory │ │
│  └─────────────┘ └─────────────┘ └─────────────┘ └────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Runtime Layer                                 │
│  ┌─────────────────┐ ┌──────────────┐ ┌─────────────────────┐   │
│  │ Jido Instance   │ │ AgentServer  │ │ Scheduler / Await   │   │
│  │ (Supervisor)    │ │ (GenServer)  │ │ Observe / Discovery │   │
│  └─────────────────┘ └──────────────┘ └─────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Core Model Layer                              │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌────────────┐ │
│  │   Agent     │ │   Action    │ │  Strategy   │ │   Skill    │ │
│  │  (Struct)   │ │   (Pure)    │ │ (Pluggable) │ │(Composable)│ │
│  └─────────────┘ └─────────────┘ └─────────────┘ └────────────┘ │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                     Directives                               ││
│  │  Emit | Spawn | SpawnAgent | Schedule | Cron | Stop | ...   ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## Key Architectural Decisions

1. **Separation of pure and effectful code** - Business logic is pure; effects are data
2. **Supervision-first design** - Everything runs under OTP supervisors
3. **Schema-driven validation** - State and parameters validated at boundaries
4. **Event-driven messaging** - Signals decouple components
5. **Pluggable strategies** - Execution behavior is swappable
6. **Composable skills** - Capabilities are modular and attachable

## Internal Architecture: Effects as Implementation Detail

From a pure functional programming perspective, Jido's essential contract is:

```elixir
{agent, directives} = MyAgent.cmd(agent, signal)  # Elm's (Model, Cmd) pattern
```

Under the hood, Strategies interpret an internal "effect algebra":

| Type | Module | Purpose | Crosses `cmd/2` boundary? |
|------|--------|---------|---------------------------|
| **State operations** | `Jido.Agent.Internal.*` | Update agent state (SetState, DeleteKeys, SetPath, etc.) | No |
| **External directives** | `Jido.Agent.Directive.*` | Runtime instructions (Emit, Spawn, Schedule, Stop) | Yes |

`Jido.Agent.Effects.apply_effects/2` is the interpreter that:
- Applies `Internal.*` structs as pure `state → state` transitions
- Collects `Directive.*` structs as outbound instructions

This separation is **not** a third conceptual pillar—it's an implementation choice that:
- Ensures internal state operations never leak to the runtime
- Provides a rich state-update DSL for advanced strategies (FSM, BehaviorTree, LLMChain)
- Keeps the public API simple: **Signals in → Agent → Directives out**

For most developers, only Signals and Directives matter. `Internal.*` is an advanced convenience for custom strategy authors.

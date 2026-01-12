# Jido 2.0 - Core Purpose & Philosophy

## What is Jido?

Jido is an OTP-based framework for building autonomous agent systems in Elixir. It formalizes patterns for multi-agent coordination, structured workflows, and observable execution.

## The Core Model

Jido's architecture rests on three foundational packages:

| Package | Role |
|---------|------|
| **jido_signal** | Message envelope for agent communication (CloudEvents-style) |
| **jido_action** | Command pattern for defining executable units of work |
| **jido** | Agent runtime that orchestrates signals, actions, and state |

The flow is simple:

```
Signal (input) → Router → Agent.cmd/2(action) → {Updated Agent, Directives}
                                                        ↓
                                              Emit Directive → Signal (output)
```

- **Signals** arrive at agents (from external systems, other agents, or sensors)
- **Router** maps signals to actions (via strategy routes, skills, or patterns)
- **Actions** execute via `cmd/2` and transform agent state
- **Directives** describe effects for the runtime to perform (including emitting new signals)

## Why Not Just Use GenServer?

OTP primitives are excellent. You can build agent systems with raw GenServer. But when building *multiple cooperating agents*, you'll reinvent:

| Raw OTP | Jido Formalizes |
|---------|-----------------|
| Ad-hoc message shapes per GenServer | Signals as standard envelope |
| Business logic mixed in callbacks | Actions as reusable command pattern |
| Implicit effects scattered in code | Directives as typed effect descriptions |
| Custom child tracking per server | Built-in parent/child hierarchy |
| Process exit = completion | State-based completion semantics |

Jido isn't "better GenServer" - it's a formalized agent pattern built *on* GenServer.

## Core Principles

### 1. Agents Are Immutable Structs

```elixir
{agent, directives} = MyAgent.cmd(agent, action)
```

Each `cmd/2` returns a new agent struct. State changes are explicit and traceable.

### 2. Signals In, Directives Out

**Signals** (`jido_signal`) are the input - typed messages that trigger agent behavior:

```elixir
signal = Jido.Signal.new!("order.placed", %{order_id: 123})
```

**Directives** are the output - data describing effects for the runtime:

```elixir
%Directive.Emit{signal: confirmation}      # Send a signal
%Directive.SpawnAgent{module: Worker}      # Spawn a child agent
%Directive.Schedule{delay: 5000, signal: s} # Schedule future work
```

Agents never execute directives - they only emit them. The runtime (`AgentServer`) interprets and executes.

### 3. Actions Define Work

**Actions** (`jido_action`) are the command pattern - schema-validated units of work:

```elixir
defmodule MyApp.Actions.ProcessOrder do
  use Jido.Action,
    name: "process_order",
    schema: [order_id: [type: :integer, required: true]]

  def run(%{order_id: id}, context) do
    # Can perform effects (HTTP, DB) or stay pure
    {:ok, %{status: :processed, order_id: id}}
  end
end
```

Actions can:
- **Transform state** (pure computation)
- **Perform effects** (HTTP calls, DB queries) when needed
- **Emit directives** for runtime-managed effects

### 4. Effects Are Explicit

Two mechanisms for side effects:

| Directives | Direct Effects in Actions |
|------------|---------------------------|
| Runtime executes them | Action executes them in `run/2` |
| For coordination (spawn, schedule, signal) | For data fetching (HTTP, DB) |
| Always observable at runtime boundary | Results flow back to state |

Both flow through `cmd/2`, keeping effects centralized and traceable.

> **Architectural Note:** From a pure functional programming perspective, the only essential boundary is `{agent, directives} = cmd(agent, input)`. This is Jido's Elm-style `(Model, Cmd)` contract. Internally, Strategies may use additional state-update operations (`Jido.Agent.Internal.*`), but these are implementation details—they never cross the `cmd/2` boundary and are not part of the public mental model.

### 5. AI is Optional

The core `jido` package is infrastructure only. AI capabilities live in companion packages like `jido_ai` for LLM-powered strategies and behaviors.

## Actions, Directives, and Effects: The Complete Picture

Understanding the distinction between actions, directives, and effects is essential to working with Jido effectively.

### What is an Action?

An **Action** is a module that defines a unit of work. It's the command pattern applied to agent behavior.

```elixir
defmodule MyApp.Actions.FetchWeather do
  use Jido.Action,
    name: "fetch_weather",
    schema: [city: [type: :string, required: true]]

  def run(%{city: city}, _context) do
    # This action performs a direct effect (HTTP call)
    {:ok, weather} = WeatherAPI.get(city)
    {:ok, %{weather: weather, fetched_at: DateTime.utc_now()}}
  end
end
```

**Actions are responsible for:**

| Responsibility | Description |
|----------------|-------------|
| **Parameter validation** | Schema defines required inputs with types |
| **Business logic** | The `run/2` callback contains the work |
| **State transformation** | Return value merges into agent state |
| **Effect decisions** | Choose between direct effects or directives |

**Actions are NOT:**
- Executed directly by application code (they go through `cmd/2`)
- Aware of the process runtime (no access to `self()` or process state)
- Required to be pure (they can perform I/O when appropriate)

### What is a Directive?

A **Directive** is a data structure that *describes* an effect without executing it. Think of it as a "request slip" that the agent hands to the runtime.

```elixir
# These are just structs - they don't DO anything on their own
%Directive.Emit{signal: my_signal}
%Directive.SpawnAgent{module: WorkerAgent, tag: :worker_1}
%Directive.Schedule{delay: 5000, signal: reminder}
%Directive.Stop{reason: :normal}
```

**Core directives:**

| Directive | Purpose |
|-----------|---------|
| `Emit` | Dispatch a signal via configured adapters |
| `SpawnAgent` | Start a child agent with parent/child tracking |
| `StopChild` | Gracefully stop a tracked child agent |
| `Spawn` | Spawn a generic BEAM process (fire-and-forget) |
| `Schedule` | Send a signal after a delay |
| `Cron` / `CronCancel` | Manage recurring scheduled work |
| `Stop` | Request the agent to stop itself |
| `Error` | Report a structured error from command processing |

**Directives are:**
- Pure data (structs with no behavior)
- Returned from `cmd/2` alongside the updated agent
- Executed exclusively by `AgentServer` after `cmd/2` completes
- Inspectable, filterable, and testable

**The key insight:** Agents *describe* what should happen; the runtime *makes* it happen.

### What is an Effect?

An **Effect** is any actual interaction with the world outside the agent struct. Effects are where things really happen.

Effects occur in two places:

#### 1. Runtime-Managed Effects (from Directives)

When `AgentServer` executes a directive, it produces an effect:

```
%Directive.SpawnAgent{...} → AgentServer starts a child process
%Directive.Emit{...}       → AgentServer dispatches signal via adapters
%Directive.Schedule{...}   → AgentServer schedules a timer
```

These effects are:
- Centralized in the runtime
- Automatically instrumented (telemetry, logging)
- Coordinated with process supervision

#### 2. Action-Local Effects (in `run/2`)

Actions can perform effects directly when fetching data or calling external services:

```elixir
def run(%{url: url}, _context) do
  # Direct effect: HTTP call happens here
  {:ok, response} = HttpClient.get(url)
  
  # Result flows back to agent state
  {:ok, %{response_body: response.body}}
end
```

These effects are:
- Self-contained within the action
- Appropriate for data fetching (HTTP, DB, file I/O)
- Results captured in state for observability

### When to Use Each

```
┌─────────────────────────────────────────────────────────────────┐
│                        Agent.cmd/2                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                      ACTION                              │    │
│  │                                                          │    │
│  │  ┌─────────────────┐    ┌─────────────────────────────┐ │    │
│  │  │  Pure Logic     │    │  Direct Effects             │ │    │
│  │  │                 │    │                             │ │    │
│  │  │  - Compute      │    │  - HTTP calls               │ │    │
│  │  │  - Transform    │    │  - DB queries               │ │    │
│  │  │  - Validate     │    │  - File I/O                 │ │    │
│  │  │                 │    │  - LLM calls                │ │    │
│  │  └─────────────────┘    └─────────────────────────────┘ │    │
│  │                                                          │    │
│  │  Output: {:ok, %{state_changes..., __directives__: [...]}}   │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│  Returns: {updated_agent, directives}                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      AgentServer                                 │
│                                                                  │
│  Executes directives → Runtime-Managed Effects                  │
│                                                                  │
│  - SpawnAgent  → Starts supervised child process                │
│  - Emit        → Dispatches signal via adapters                 │
│  - Schedule    → Sets up timer for future signal                │
│  - Stop        → Terminates agent process                       │
└─────────────────────────────────────────────────────────────────┘
```

**Decision guide:**

| Situation | Use |
|-----------|-----|
| Need to spawn a child agent | Directive (`SpawnAgent`) |
| Need to send a signal to another agent | Directive (`Emit`) |
| Need to schedule future work | Directive (`Schedule`, `Cron`) |
| Need to fetch data from an API | Direct effect in action |
| Need to query a database | Direct effect in action |
| Need to call an LLM | Direct effect in action |
| Pure computation on state | Action (no effects) |

### Example: Combining All Three

```elixir
defmodule MyApp.Actions.ProcessOrder do
  use Jido.Action,
    name: "process_order",
    schema: [order_id: [type: :integer, required: true]]

  def run(%{order_id: order_id}, _context) do
    # 1. Direct effect: fetch order from database
    {:ok, order} = OrderRepo.get(order_id)
    
    # 2. Pure logic: compute total
    total = Enum.sum(Enum.map(order.items, & &1.price))
    
    # 3. Direct effect: charge payment
    {:ok, charge} = PaymentGateway.charge(order.customer_id, total)
    
    # 4. Return state changes + directives for runtime effects
    {:ok, %{
      order_status: :paid,
      charge_id: charge.id,
      __directives__: [
        # Directive: notify customer (runtime handles dispatch)
        Directive.emit(Signal.new!("order.paid", %{order_id: order_id})),
        # Directive: spawn fulfillment worker (runtime handles supervision)
        %Directive.SpawnAgent{
          module: FulfillmentAgent,
          tag: {:fulfillment, order_id},
          args: %{order_id: order_id}
        }
      ]
    }}
  end
end
```

This action demonstrates:
- **Direct effects**: Database query, payment API call
- **Pure logic**: Computing the total
- **Directives**: Signal emission, child agent spawning

The action focuses on *what* needs to happen. The runtime handles *how* signals get dispatched and *how* child agents get supervised.

### Why This Separation Matters

| Benefit | How It's Achieved |
|---------|-------------------|
| **Testability** | Test actions with mock services; inspect returned directives without executing them |
| **Observability** | All runtime effects flow through AgentServer with telemetry |
| **Composability** | Actions are reusable; directives are data that can be filtered/transformed |
| **Separation of concerns** | Business logic in actions; process coordination in runtime |
| **Replay/Audit** | Directives can be logged and replayed; state changes are explicit |

### Design Decision: Why "Directives" (Not "Commands" or "Effects")

We evaluated renaming Directives to "Commands" (matching Elm's `Cmd` and CQRS patterns) but decided against it:

1. **Directive is accurate** - They are instructions for the runtime, not imperative commands
2. **Avoids confusion** - "Command" is overloaded in Elixir (GenServer calls, CQRS, CLI)
3. **Internal vs External** - The term "Effect" is reserved for prose describing actual side-effects; `Jido.Agent.Internal.*` provides state-update operations that Strategies use internally

The public mental model remains simple: **Signals (events in) → Agent → Directives (instructions out)**.

## The Contract

Every Jido agent follows:

1. **Define** agent with a validated state schema
2. **Receive** signals as input
3. **Execute** actions via `cmd/2`
4. **Emit** directives for runtime effects
5. **Return** updated state

## When to Use Jido

**Raw OTP is fine when:**
- Single server with narrow API
- No multi-agent coordination needed

**Use Jido when:**
- Multiple cooperating agents
- Structured workflows with scheduling and signaling
- Observable, testable agent behavior
- AI/LLM integration planned

## Summary

Jido provides:

- **jido_signal**: Standard message envelope for agent communication
- **jido_action**: Command pattern for defining work
- **jido**: Agent runtime with hierarchy, scheduling, and observability

It's the patterns you'd build yourself - formalized with consistent semantics.

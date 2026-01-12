# Jido 2.0 - Execution Model

This document describes the end-to-end flow of how Jido agents execute work.

## Overview

```
Signal Ingress → Routing → Pure Execution (cmd/2) → Directive Processing → Completion
```

## Step 1: Agent Definition & Initialization

### Define an Agent Module

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

### Create a Jido Instance

```elixir
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app
end
```

### Add to Supervision Tree

```elixir
# In your application.ex
children = [
  MyApp.Jido
]

Supervisor.start_link(children, strategy: :one_for_one)
```

### Start an Agent

```elixir
{:ok, pid} = MyApp.Jido.start_agent(MyApp.CounterAgent, id: "counter-1")
```

## Step 2: Signal Ingress

External systems, sensors, or application code create signals and deliver them to agents.

### Creating a Signal

```elixir
signal = Jido.Signal.new!("increment", %{amount: 10})
```

### Delivering to an Agent

```elixir
# Asynchronous (fire and forget)
Jido.AgentServer.cast(pid, signal)

# Synchronous (wait for result)
{:ok, result} = Jido.AgentServer.call(pid, signal)
```

### Alternative Delivery Methods

- **Emit directives** → `Jido.Signal.Dispatch` (pubsub, bus, http, etc.)
- **Sensor processes** → Emit signals on schedules or events
- **External services** → Send signals via HTTP, message queues, etc.

## Step 3: Routing to Strategy/Actions

Inside `Jido.AgentServer`, signals are routed to actions.

### Signal Router

The router uses multiple sources to determine what action(s) to run:

1. **Strategy `signal_routes/1`** - Strategy-defined mappings
2. **Skills' routers** - Each skill can provide signal routing
3. **Signal patterns** - Pattern matching on signal types
4. **Fallback mapping** - Default `{signal.type, signal.data}` → action

### Resulting Instructions

The router produces `Jido.Instruction` structs that specify:
- Which action to run
- With what parameters
- In what context

## Step 4: Pure Execution (`cmd/2`)

The AgentServer calls the agent's `cmd/2` function.

### Execution Flow

```elixir
# 1. Optional pre-processing hook
{agent, action} = MyAgent.on_before_cmd(agent, action)

# 2. Strategy executes the action(s)
#    - Jido.Exec.run/1 invokes Jido.Action.run/2
#    - Results are merged into agent.state
#    - External effects collected as directives
{agent, directives} = strategy.cmd(agent, instructions, context)

# 3. Optional post-processing hook
{agent, directives} = MyAgent.on_after_cmd(agent, action, directives)
```

### The Pure Contract

This entire phase is **pure**:
- No side effects
- No I/O
- Deterministic: same inputs → same outputs

The result is an updated `agent` struct plus a list of `directives`.

### Internal Effect Handling

Actions may return internal effects alongside their results:

```elixir
{:ok, %{result: value}, [
  %Internal.SetState{attrs: %{status: :processing}},
  %Directive.Emit{signal: notification}
]}
```

The Strategy (via `Jido.Agent.Effects.apply_effects/2`) separates these:
- **Internal effects** (`Internal.SetState`, `Internal.DeleteKeys`, etc.) → applied immediately as pure state transitions
- **External directives** (`Directive.Emit`, `Directive.Spawn`, etc.) → collected and returned from `cmd/2`

This is the "effect interpreter" pattern: internal state operations never leave the Strategy layer.

## Step 5: Directive Processing

The AgentServer processes directives through a drain loop.

### Directive Queue

Directives are enqueued and processed asynchronously:

```elixir
# Simplified flow
directives
|> Enum.each(fn directive ->
  DirectiveExec.execute(directive, context)
end)
```

### Directive Execution

| Directive | Execution |
|-----------|-----------|
| `%Emit{}` | `Jido.Signal.Dispatch` to PubSub, HTTP, bus, etc. |
| `%SpawnAgent{}` | Start new `Jido.AgentServer` + record parent/child |
| `%StopChild{}` | Shut down child agent gracefully |
| `%Schedule{}` | Schedule future signals via `Process.send_after` |
| `%Cron{}` | Schedule via `Jido.Scheduler` (SchedEx) |
| `%Stop{}` | Stop the agent's own process |

### Non-Blocking Processing

Directive processing is non-blocking with respect to the main `call/3` / `cast/2` flow. The agent can continue receiving signals while directives are being processed.

## Step 6: Completion & Coordination

### State-Based Completion

Agents report "done" via state changes, not process exit:

```elixir
agent =
  agent
  |> put_in([:state, :status], :completed)
  |> put_in([:state, :last_answer], answer)
```

### Waiting for Completion

External code (HTTP, CLI, tests) uses `Jido.Await`:

```elixir
{:ok, %{status: :completed, result: answer}} =
  Jido.Await.completion(pid, 10_000)
```

### Event-Driven Waiting

`Jido.Await` uses `AgentServer.await_completion/2`:
- Event-driven, no polling
- Waits on state conditions
- Configurable timeout

## Step 7: Observation & Telemetry

Throughout execution, `Jido.Observe` wraps work in telemetry spans.

### Telemetry Events

```elixir
[:jido, :agent, :cmd, :start]
[:jido, :agent, :cmd, :stop]
[:jido, :agent, :cmd, :exception]

[:jido, :action, :run, :start]
[:jido, :action, :run, :stop]
[:jido, :action, :run, :exception]
```

### Custom Tracers

Hook in custom tracer modules for:
- OpenTelemetry exporters
- Custom logging
- Metrics collection

## Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     External World                               │
│  (HTTP, CLI, Sensors, Message Queues, Other Agents)             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Signal
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    AgentServer (GenServer)                       │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ 1. Receive Signal                                           ││
│  │    call/3 or cast/2                                         ││
│  └─────────────────────────────────────────────────────────────┘│
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ 2. Route to Actions                                         ││
│  │    SignalRouter → Instruction(s)                            ││
│  └─────────────────────────────────────────────────────────────┘│
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ 3. Execute (Pure)                                           ││
│  │    on_before_cmd → Strategy.cmd → on_after_cmd              ││
│  │    Result: {agent, directives}                              ││
│  └─────────────────────────────────────────────────────────────┘│
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ 4. Process Directives                                       ││
│  │    DirectiveExec.execute/2                                  ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Emit, Spawn, Schedule, etc.
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     External World                               │
│  (PubSub, HTTP, Child Agents, Scheduler)                        │
└─────────────────────────────────────────────────────────────────┘
```

## Key Takeaways

1. **Signals in, signals out** - Agents communicate via signals
2. **Pure core** - `cmd/2` is deterministic and side-effect-free
3. **Effects as data** - Directives describe what to do, runtime does it
4. **State-based completion** - Check state, not process liveness
5. **Observable by default** - Telemetry throughout

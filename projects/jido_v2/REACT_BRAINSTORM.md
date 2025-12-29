# Signal Router & Runner Architecture

## Core Insight

**Runners and routers are orthogonal concerns:**

- **Router:** "Given `signal.type`, which handler function do I call?" (dispatch)
- **Runner:** "What's the pattern of signals, state, and effects?" (control semantics)

All runners (ReAct, CoT, BehaviorTree, StateMachine) compile down to the same thing:
```
(state, signal) → {:ok, new_state, effects}
```

The difference is:
- Which signal types they use
- How they structure internal state
- What effects they emit

---

## The Three-Layer Model

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 3: Flow Templates (optional batteries)               │
│  Jido.Runner.ReAct, Jido.Runner.CoT, Jido.Runner.BT         │
│  Pre-define signal families + helper macros                 │
├─────────────────────────────────────────────────────────────┤
│  Layer 2: SignalRouter (kernel)                             │
│  route "type" → handler                                     │
│  Compiles to pattern-matched dispatch                       │
├─────────────────────────────────────────────────────────────┤
│  Layer 1: Agent + handle_signal/2 (kernel)                  │
│  The core contract, always available                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Signal Families by Runner

### ReAct Pattern

```
External:  react.query                    # User input
Internal:  react.llm_result               # LLM returns {thought, action}
           react.tool_result              # Tool returns data
Control:   react.cancel                   # Abort
Output:    react.answer                   # Final response (via Effect.Reply)
```

Flow: `query → think → (tool → observe → think)* → answer`

```elixir
route "react.query",       :handle_query
route "react.llm_result",  :handle_llm_result
route "react.tool_result", :handle_tool_result
route "react.cancel",      :handle_cancel
```

### Chain of Thought

```
External:  cot.query                      # User input
Internal:  cot.step_result                # One reasoning step {step, done?}
Control:   cot.cancel
Output:    cot.answer
```

Flow: `query → step → step → ... → answer`

```elixir
route "cot.query",       :handle_query
route "cot.step_result", :handle_step
route "cot.cancel",      :handle_cancel
```

CoT is basically "ReAct without tools" - the only action is "think more" or "answer".

### Behavior Tree

```
External:  bt.start                       # Begin tree execution
Internal:  bt.tick                        # Drive next node evaluation
           bt.node_result                 # Async node completed {node_id, result}
Control:   bt.cancel
Output:    bt.done                        # Tree finished (success/failure)
```

Flow: `start → tick → (node_result → tick)* → done`

```elixir
route "bt.start",       :handle_start
route "bt.tick",        :handle_tick
route "bt.node_result", :handle_node_result
route "bt.cancel",      :handle_cancel
```

The BT runner manages tree traversal; signals just tell it when to step.

### State Machine

```
External:  [domain events]                # order.create, payment.capture, etc.
Internal:  [timeouts, callbacks]          # timeout.payment, shipment.confirmed
Control:   [domain cancels]               # order.cancel
Output:    [domain completions]           # order.completed, order.cancelled
```

No fixed signal vocabulary - it's domain-specific. The pattern is `(status, event) → new_status`.

```elixir
route "order.create",      :handle_order_create
route "payment.capture",   :handle_payment_capture
route "timeout.payment",   :handle_payment_timeout
route "order.cancel",      :handle_order_cancel
```

Status-based dispatch happens **inside handlers**, not in the router:

```elixir
def handle_payment_capture(%{status: :awaiting_payment} = state, signal) do
  # happy path
end
def handle_payment_capture(state, _signal) do
  {:ok, state, []}  # ignore if wrong state
end
```

---

## Key Design Decisions

### 1. Router stays dumb

Router only knows: `signal.type → handler_function`

It does NOT know:
- Current status/state
- Runner type
- Signal semantics
- Data structure

This keeps it simple and universal.

### 2. Runners are patterns, not router features

Each runner is a **convention** for:
- Signal vocabulary
- State structure
- Handler behavior

Runners can provide:
- Suggested signal families
- Helper macros
- Default handler implementations

But they compile to plain `handle_signal/2` + routes.

### 3. (status, type) dispatch is a runner concern

For state machines, `(status, event)` is the dispatch key. But this lives in:
- Handler pattern matching, OR
- A StateMachine DSL that generates appropriate clauses

NOT in the generic router.

### 4. External vs Internal signals

Distinguish in documentation:

| Signal Kind | Example | Stability |
|-------------|---------|-----------|
| **External** (public API) | `react.query`, `react.answer` | Stable |
| **Internal** (protocol) | `react.llm_result`, `bt.tick` | Volatile |

External signals are the "HTTP endpoints" of your agent.
Internal signals are implementation details.

---

## SignalRouter Design

### Basic API

```elixir
defmodule MyAgent do
  use Jido.Agent, name: "my", schema: %{...}
  use Jido.SignalRouter

  route "my.start", :handle_start
  route "my.step",  :handle_step
  route "my.done",  :handle_done

  def handle_start(state, signal), do: ...
  def handle_step(state, signal), do: ...
  def handle_done(state, signal), do: ...
end
```

### What it generates

```elixir
@impl true
def handle_signal(state, %Signal{type: "my.start"} = signal),
  do: handle_start(state, signal)
def handle_signal(state, %Signal{type: "my.step"} = signal),
  do: handle_step(state, signal)
def handle_signal(state, %Signal{type: "my.done"} = signal),
  do: handle_done(state, signal)
def handle_signal(state, _signal),
  do: {:ok, state, []}
```

Pattern matching, zero overhead, exactly what you'd write by hand.

### Introspection

```elixir
MyAgent.__routes__()
# => [
#   {"my.start", MyAgent, :handle_start},
#   {"my.step", MyAgent, :handle_step},
#   {"my.done", MyAgent, :handle_done}
# ]
```

---

## Flow Templates (Batteries)

For common patterns, provide templates that set up routes + helpers:

### ReAct Template

```elixir
defmodule MyReActAgent do
  use Jido.Agent, name: "my_react", schema: %{...}
  use Jido.Runner.ReAct,
    think_action: MyLLMThink,
    tools: [Search, Calculator]

  # Override hooks as needed
  def on_query(state, query), do: ...
  def on_tool_result(state, tool, result), do: ...
end
```

This would:
- Define routes for `react.*` signals
- Provide default loop implementation
- Let user override specific hooks

### StateMachine Template

```elixir
defmodule OrderAgent do
  use Jido.Agent, name: "order", schema: %{...}
  use Jido.Runner.StateMachine

  machine do
    state :pending do
      on "order.pay", to: :paid, run: :process_payment
    end
    state :paid do
      on "order.ship", to: :shipped, run: :ship_order
    end
    state :shipped, terminal: true
  end

  def process_payment(state, signal), do: ...
  def ship_order(state, signal), do: ...
end
```

Generates appropriate routes + pattern-matched handlers.

---

## The Full Picture

```
User defines:
  1. Schema (agent state)
  2. Routes (signal.type → handler)
  3. Handlers (business logic)

Optionally uses:
  - Runner template (pre-defined signal families)
  - Runner helpers (common patterns)

Everything compiles to:
  handle_signal(state, signal) → {:ok, new_state, effects}

AgentServer:
  - Receives signals
  - Calls handle_signal
  - Executes effects
  - Rinse, repeat
```

---

## What NOT to Do

| Don't | Why |
|-------|-----|
| Put runner logic in router | Couples dispatch to semantics |
| Make router status-aware | That's handler/runner concern |
| Add middleware in v1 | YAGNI - add later if needed |
| Pre-define all signal types | Let domain drive vocabulary |

---

## Implementation Plan

### Kernel (required)

1. `Jido.SignalRouter` - ~50 LOC macro
   - `route/2`, `route/3`
   - `__before_compile__` generates dispatch
   - `__routes__/0` for introspection

### Batteries (optional, later)

2. `Jido.Runner.ReAct` - ReAct template
3. `Jido.Runner.CoT` - Chain of Thought template  
4. `Jido.Runner.StateMachine` - FSM DSL
5. `Jido.Runner.BehaviorTree` - BT DSL

Each battery is independent and compiles to plain routing + handlers.

---

## Summary

| Concern | Solution | Layer |
|---------|----------|-------|
| Dispatch | SignalRouter (`type → handler`) | Kernel |
| Control flow | Runner conventions | Battery |
| State structure | Schema + handler logic | User |
| Effects | Handler returns | User |

**Router is dumb. Runners are patterns. Everything is signals.**

---

# Multi-Process Agent Architecture

## The Question

What if an agent is a **collection of processes** instead of just one?

- **Supervisor** - stateless, manages lifecycle
- **Gateway** - public API, handles external signals, owns state
- **Workers** - execute effects in background

This mirrors Phoenix LiveView's architecture.

---

## Phoenix LiveView Process Model

```
Endpoint.Supervisor
  ├─ PubSub.Supervisor
  ├─ ...
  └─ LiveView.DynamicSupervisor
       └─ LiveView process (owns assigns, renders)
           ↑
Phoenix.Socket/Channel (handles WebSocket protocol)
```

**Mapping to Jido:**

| Phoenix | Jido |
|---------|------|
| LiveView process | AgentGateway (owns state, calls handle_signal) |
| Channel | Transport adapter (HTTP, WS, NATS → Signal) |
| PubSub | Effect.Emit / Effect.Reply bus |
| Tasks | Effect.Run workers |

---

## Jido Multi-Process Tree

### Minimal Tree (per agent instance)

```
Jido.AgentInstance.Supervisor
  ├─ Jido.Agent.Gateway          # owns state, interprets effects
  └─ Jido.Agent.WorkerSupervisor # Task.Supervisor for Effect.Run
```

### Full Tree (with registry)

```
App.Supervisor
  ├─ Jido.PubSub
  └─ Jido.AgentRegistry.Supervisor
       └─ DynamicSupervisor
            └─ Jido.AgentInstance.Supervisor (per agent)
                 ├─ Jido.Agent.Gateway
                 └─ Jido.Agent.WorkerSupervisor
```

---

## How It Works

### Gateway Process

```elixir
defmodule Jido.Agent.Gateway do
  use GenServer

  def handle_cast({:signal, signal}, state) do
    case MyAgent.handle_signal(state.agent, signal) do
      {:ok, new_agent, effects} ->
        new_state = %{state | agent: new_agent}
        execute_effects(effects, new_state)
        {:noreply, new_state}
    end
  end

  def handle_info({:internal_signal, signal}, state) do
    # Internal signals handled exactly like external
    handle_cast({:signal, signal}, state)
  end
end
```

### Effect Execution

```elixir
defp execute_effect(%Effect.Run{} = eff, state) do
  Task.Supervisor.start_child(state.worker_sup, fn ->
    result = eff.action.run(eff.params)
    
    # Worker sends signal back to gateway
    internal = %Signal{
      type: "action.result",
      data: %{action: eff.action, result: result},
      meta: %{kind: :internal}
    }
    send(state.gateway_pid, {:internal_signal, internal})
  end)
end

defp execute_effect(%Effect.Timer{in: ms, signal: sig}, state) do
  Process.send_after(self(), {:internal_signal, sig}, ms)
end

defp execute_effect(%Effect.Reply{signal: sig}, state) do
  # Send to caller or PubSub
end
```

### Workers Communicate via Signals

Workers never call `handle_signal/2` directly. They:
1. Do their work (LLM call, tool execution, etc.)
2. Produce a `Signal` with the result
3. Send it to the gateway

This keeps the gateway as the **single source of truth** for state.

---

## Signal Routing: External vs Internal

### No Router Changes Needed

Router stays dumb: `signal.type → handler`

The **gateway** decides how signals arrive (cast vs info), but the agent module doesn't care.

### Optional: Annotate for Introspection

```elixir
defmodule MyAgent do
  use Jido.Agent, name: "my"
  use Jido.SignalRouter

  # Annotations for docs/telemetry, not behavior
  external "user.message",      :handle_user_message
  internal "react.tool_result", :handle_tool_result
  internal "react.llm_result",  :handle_llm_result
end

MyAgent.__routes__()
# => [
#   {:external, "user.message", MyAgent, :handle_user_message},
#   {:internal, "react.tool_result", MyAgent, :handle_tool_result},
#   ...
# ]
```

This feeds documentation and observability without changing dispatch.

---

## When Single vs Multi-Process?

### Single Process Sufficient

- Actions already async (Tasks/Oban)
- Modest throughput
- Simple request/response agents
- Prototypes

### Multi-Process Needed

| Trigger | Why |
|---------|-----|
| Heavy workloads | Separate pools for CPU vs I/O |
| Complex internal protocols | Long-running sagas, many internal signals |
| Transport decoupling | WebSocket lifetime ≠ agent lifetime |
| Fault isolation | Crashed tool kills only its worker |
| Resource control | Max N concurrent external calls |

---

## DSL Impact

### Kernel Stays Pure

```elixir
# Agent module - unchanged
defmodule MyAgent do
  use Jido.Agent, name: "my", schema: %{...}
  use Jido.SignalRouter

  route "my.query", :handle_query
  route "my.result", :handle_result

  def handle_query(state, signal), do: ...
  def handle_result(state, signal), do: ...
end
```

The agent knows nothing about processes. It's pure.

### Runtime Configuration (Battery)

```elixir
# Optional runtime layer
use Jido.Agent,
  name: "support",
  runner: :react,
  runtime: [
    layout: :gateway_with_workers,
    max_concurrency: 10,
    worker_pool: :react_tools
  ]
```

This generates:
- Supervisor spec
- Gateway with effect execution
- Worker pool configuration

But it's a **battery**, not kernel.

---

## The Full Picture

```
┌─────────────────────────────────────────────────────────────┐
│  External World (HTTP, WS, NATS, CLI)                       │
└─────────────────────────┬───────────────────────────────────┘
                          │ Signal
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  Gateway Process                                            │
│  - Receives signals (external + internal)                   │
│  - Owns agent state                                         │
│  - Calls handle_signal/2 (pure)                             │
│  - Interprets effects                                       │
└───────────┬─────────────────────────────────┬───────────────┘
            │ Effect.Run                      │ Effect.Timer
            ▼                                 ▼
┌───────────────────────┐           ┌─────────────────────────┐
│  Worker (Task)        │           │  Process.send_after     │
│  - Executes action    │           │  - Schedules signal     │
│  - Sends result signal│           │  - Back to gateway      │
└───────────────────────┘           └─────────────────────────┘
```

---

## Key Principles

1. **Agents are pure** - `handle_signal/2` knows nothing about processes
2. **Router is dumb** - `type → handler`, process-agnostic
3. **Gateway owns state** - single source of truth
4. **Workers produce signals** - never mutate state directly
5. **Effects describe intent** - gateway decides how to execute
6. **Everything is signals** - external and internal use same mechanism

---

## Summary

| Layer | Concern | Process? |
|-------|---------|----------|
| Agent module | Pure logic (`handle_signal/2`) | No |
| SignalRouter | Dispatch (`type → handler`) | No |
| Gateway | State ownership, effect execution | Yes |
| Workers | Async I/O, produce result signals | Yes |
| Supervisor | Lifecycle management | Yes |

**Agents think. Gateways act. Workers execute. Signals connect.**

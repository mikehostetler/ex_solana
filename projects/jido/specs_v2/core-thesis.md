# Jido 2.0 Core Thesis

> **Agents think. Servers act.**
>
> Agents **think** by running a pure function: `(state, signal) → {:ok, new_state, [Effect.t()]}`  
> AgentServer **acts** by taking those Effects and doing the real I/O.

---

## Executive Summary

Jido 2.0 is an agent framework built on one foundational insight: **agents should be as natural to define as Phoenix Controllers or LiveViews**, while providing the testability, introspection, and reliability that production systems demand.

The core thesis is simple:

1. **Agents think as pure functions** that transform state given signals
2. **Agents emit Effects** (pure data) describing what should happen
3. **AgentServer acts on Effects** and executes the actual I/O
4. **Testing is deterministic** because agents never touch the outside world

In practical terms: **agents think, servers act**. You write pure `handle_signal/2` functions that decide what should happen; Jido's `AgentServer` and Actions take care of actually doing it.

This is not a new process model. It is a **domain-specific workflow engine** that runs inside BEAM processes, similar to how Commanded, Sage, and Ash layer declarative patterns over OTP.

---

## Table of Contents

1. [The Core Contract](#1-the-core-contract)
2. [What This Solves](#2-what-this-solves)
3. [Layering: Jido Over BEAM](#3-layering-jido-over-beam)
4. [Effects: The Effect Language](#4-effects-the-effect-language)
5. [Runners: Decision Engines](#5-runners-decision-engines)
6. [Kernel vs Batteries](#6-kernel-vs-batteries)
7. [Design Guardrails](#7-design-guardrails)
8. [Comparison to Similar Patterns](#8-comparison-to-similar-patterns)
9. [Non-Goals](#9-non-goals)

---

## 1. The Core Contract

Every Jido Agent implements one callback:

```elixir
@callback handle_signal(state :: t(), signal :: Jido.Signal.t()) ::
  {:ok, new_state :: t(), effects :: [Jido.Agent.Effect.t()]}
  | {:error, term()}
```

This contract has three parts:

| Part | Type | Description |
|------|------|-------------|
| `state` | Agent struct | Zoi-validated struct owned by the Agent module |
| `signal` | `Jido.Signal.t()` | Universal message envelope—the only input |
| `effects` | `[Effect.t()]` | Pure data describing side effects and orchestration |

**Key principle:** Agents are data modules, not processes. They are structs plus pure logic—just like Ecto Schemas, but for decision-making.

### 1.1 The Think/Act Mental Model

Jido's core contract is easiest to understand as a **Think/Act** split:

**Think (Agent.handle_signal/2):**
- Runs inside your Agent module's `handle_signal/2` callback
- Takes current `state` and a `signal`
- Computes a **new state**
- Returns a list of **Effects** describing what should happen next
- **Never performs I/O**

**Act (AgentServer + Actions):**
- Runs inside `Jido.AgentServer`, which is "just a GenServer"
- Receives the Effects returned by `handle_signal/2`
- Interprets them:
  - `Effect.Run` → execute Actions (HTTP, DB, external APIs, etc.)
  - `Effect.Timer` → schedule future signals
  - `Effect.Emit` → publish signals/events
  - `Effect.Reply` → send responses
- Performs the **actual I/O** and process-level work

You can read the core flow as:

```elixir
# Think: pure decision
{:ok, new_state, effects} = MyAgent.handle_signal(state, signal)

# Act: effectful execution
:ok = AgentServer.execute_effects(effects)
```

When you implement `handle_signal/2`, you are defining **how your agent thinks**. When you configure or inspect `AgentServer`, you are deciding **how your system acts** on those thoughts.

If you're used to GenServers, you can think of this as:
- **Think:** the decision logic you used to embed inside `handle_call/3` or `handle_cast/2`
- **Act:** the GenServer and supervised processes that actually perform work

Jido makes that split explicit and testable.

### 1.2 Example

```elixir
defmodule MyApp.SupportAgent do
  use Jido.Agent,
    name: "support",
    schema: %{
      user_id: Zoi.integer(),
      history: Zoi.list(Zoi.any()) |> Zoi.default([]),
      status: Zoi.atom() |> Zoi.default(:idle)
    }

  @impl true
  def handle_signal(state, %Jido.Signal{type: :user_message, data: %{text: text}}) do
    new_history = [%{role: :user, content: text} | state.history]
    new_state = %{state | history: new_history, status: :thinking}
    
    effects = [
      %Effect.Run{action: LookupFAQ, params: %{query: text}}
    ]
    
    {:ok, new_state, effects}
  end
end
```

The agent:
- Receives a signal
- Computes new state (pure transformation)
- Returns effects describing what should happen next
- **Never performs I/O**

---

## 2. What This Solves

### 2.1 Deterministic, Process-Free Testing

```elixir
test "support agent transitions on user message" do
  # Create agent state directly for testing (no server needed)
  agent = %SupportAgent{id: "test-1", user_id: 42, history: [], status: :idle}
  signal = %Jido.Signal{type: :user_message, data: %{text: "Help!"}}
  
  {:ok, new_agent, effects} = SupportAgent.handle_signal(agent, signal)
  
  assert new_agent.status == :thinking
  assert length(new_agent.history) == 1
  assert %Effect.Run{action: LookupFAQ} = hd(effects)
end
```

No processes. No timeouts. No flakiness. For LLM orchestration where bugs hide in control flow, this is transformative.

### 2.2 Replay, Time-Travel, Offline Evaluation

Because agents never do I/O, you can:

- **Log every triplet:** `(state_before, signal, state_after, directives)`
- **Replay conversations** with different strategies or prompts
- **Evaluate LLM agent behavior offline** without calling real tools
- **Debug production issues** by replaying exact sequences

This is nearly impossible when logic is baked into a GenServer that freely calls external services.

### 2.3 Non-Blocking Orchestration as Hard Constraint

The rule "Agents never do I/O; all work is Effects" becomes a **framework-level constraint**:

- Prevents blocking in callbacks
- Simplifies backpressure reasoning
- Makes performance characteristics consistent
- Actions (the things that do I/O) are always async from the agent's perspective

### 2.4 Unified Introspection & Visualization

```elixir
SupportAgent.machine()
|> Jido.Agent.Machine.to_mermaid()
# => "stateDiagram-v2\n  [*] --> idle\n  idle --> thinking : user_message\n..."
```

Introspectable state machines, visualizable flows, Workbench UI showing current state and legal transitions. Much harder to achieve with ad-hoc GenServer pattern matching.

### 2.5 Pluggable Decision Engines (Runners)

Because the contract is `(state, signal) → (new_state, effects)`, you can swap StateMachine for ReAct or BehaviorTree without changing application wiring:

```elixir
# Deterministic workflow
use Jido.Agent, runner: :state_machine

# LLM-driven tool use
use Jido.Agent, runner: :react

# Complex AI decision tree
use Jido.Agent, runner: :behavior_tree
```

All runners obey the same pure contract. The difference is in how they decide.

---

## 3. Layering: Jido Over BEAM

Jido does not replace BEAM—it adds a layer of abstraction for agent workflows:

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Domain                        │
│         (Phoenix, Oban, LiveView, business logic)           │
├─────────────────────────────────────────────────────────────┤
│                          Jido                                │
│    THINK: Agents, Signals, Runners (pure handle_signal/2)   │
│    ACT:   AgentServer, Actions, routing, timers, children   │
├─────────────────────────────────────────────────────────────┤
│                       BEAM / OTP                             │
│    Processes, mailboxes, supervision, fault tolerance       │
└─────────────────────────────────────────────────────────────┘
```

Within the Jido layer, **Agents think** (pure decision logic) and **AgentServers act** (effectful I/O built on standard OTP processes).

### Conceptual Mapping

| Jido Concept | BEAM Equivalent | Think/Act | Relationship |
|--------------|-----------------|-----------|--------------|
| Signal | Message | Input | Signals are structured messages with metadata |
| Effect | Side effect request | Output | Effects describe what to do; BEAM does it |
| Agent | Process brain | **Think** | Pure "thinking" logic that would be in `handle_call/3` |
| AgentServer | GenServer | **Act** | Process that "acts" on Effects and executes I/O |
| Runner | Decision strategy | Think | Implements `handle_signal/2` in different ways |

**Critical distinction:** Jido doesn't reimplement scheduling, supervision, or mailboxes. AgentServer is "just a GenServer." We're building a workflow layer, not an alternative VM.

---

## 4. Effects: The Effect Language

Effects are the **only way agents express intent**. They are pure data—structs that describe what should happen.

### 4.1 The Effect Vocabulary

```elixir
@type effect ::
  Effect.Run.t()              # Execute an action
  | Effect.StateModification.t()  # Modify agent state at a path
  | Effect.RegisterAction.t()     # Add an action to agent's capability
  | Effect.DeregisterAction.t()   # Remove an action
  | Effect.Spawn.t()              # Start a child process
  | Effect.Kill.t()               # Terminate a child process
  | Effect.Emit.t()               # Publish signal to bus
  | Effect.AddRoute.t()           # Add a route
  | Effect.RemoveRoute.t()        # Remove a route
  | Effect.Reply.t()              # Send response (NEW in V2)
  | Effect.Timer.t()              # Schedule future signal (NEW in V2)
```

### 4.2 Effects as Testing Surface

Agents return effects. Tests assert on effects. Server executes effects.

```elixir
# In test: assert what the agent WANTS to do
{:ok, _, effects} = Agent.handle_signal(state, signal)
assert %Effect.Run{action: LookupFAQ, params: %{query: "password"}} in effects

# In production: AgentServer executes the effects
# Test never executes them—that's the point
```

### 4.3 What Effects Are NOT

Effects must stay **domain-level**. They describe what the application wants, not how BEAM should do it:

| ✅ Allowed (Domain-Level) | ❌ Not Allowed (Fights BEAM) |
|--------------------------|------------------------------|
| `%Run{action: LookupFAQ, ...}` | `{:spawn, m, f, a}` |
| `%Reply{signal: response}` | `{:send, pid, msg}` |
| `%Emit{type: "user.created", ...}` | `{:http_get, url}` |
| `%Timer{in: 5000, signal: reminder}` | `{:query, sql}` |

If you need raw HTTP, database queries, or arbitrary process management—that's what Actions are for. AgentServer dispatches Actions; Agents just request them via `Effect.Run`.

### 4.4 New Effects in V2

**Effect.Reply** (synchronous response):

```elixir
defmodule Jido.Agent.Effect.Reply do
  typedstruct do
    field :to, term()              # Target (defaults to signal source)
    field :signal, Jido.Signal.t() # The response signal
  end
end
```

**Effect.Timer** (scheduled signal):

```elixir
defmodule Jido.Agent.Effect.Timer do
  typedstruct do
    field :in, non_neg_integer(), enforce: true  # Milliseconds
    field :signal, Jido.Signal.t(), enforce: true
    field :key, term(), default: nil              # For cancellation
  end
end
```

---

## 5. Runners: Decision Engines

Runners implement **how** agents decide. They're pluggable strategies that all obey the same contract:

```elixir
defmodule Jido.Agent.Runner do
  @callback handle(
    agent_module :: module(),
    state :: struct(),
    signal :: Jido.Signal.t()
  ) ::
    {:ok, struct(), [Jido.Agent.Effect.t()]}
    | {:error, term()}
end
```

### 5.1 Built-in Runners

| Runner | Use Case | Kernel/Battery |
|--------|----------|----------------|
| `:state_machine` | Deterministic workflows with explicit states | Kernel |
| `:behavior_tree` | Complex decision trees | Battery |
| `:react` | LLM with tool use (ReAct pattern) | Battery |
| `:chain_of_thought` | Step-by-step reasoning | Battery |

### 5.2 Runner vs Manual Implementation

You can always implement `handle_signal/2` directly:

```elixir
defmodule SimpleAgent do
  use Jido.Agent, name: "simple"
  
  # No runner—manual implementation
  def handle_signal(state, %{type: :ping}) do
    {:ok, state, [%Effect.Reply{signal: %Signal{type: :pong}}]}
  end
end
```

Runners are a convenience for common patterns, not a requirement.

---

## 6. Kernel vs Batteries

### Kernel (Required in `jido` core)

**Types & Behaviours:**
- `Jido.Signal` — Universal message envelope
- `Jido.Agent` — Behaviour + `use` macro
- `Jido.Agent.Effect` — All effect structs
- `Jido.Instruction` — Action invocation data
- `Jido.Action` — Behaviour for work units
- `Jido.Agent.Runner` — Behaviour for decision engines
- `Jido.AgentServer` — GenServer that runs agents

**Validation:**
- Zoi schemas for Agent state and Action params

**Built-in Runner:**
- `Jido.Agent.Runner.StateMachine`

### Batteries (Optional, can be separate packages)

**Additional Runners:**
- `Jido.Agent.Runner.ReAct`
- `Jido.Agent.Runner.ChainOfThought`
- `Jido.Agent.Runner.BehaviorTree`

**DSL (Spark-powered):**
- `runner do ... end` blocks
- `state do ... end` blocks
- `signals do ... end` blocks

**Tooling:**
- Workbench UI
- Visualization (Mermaid export)
- Telemetry integrations

**Interop:**
- Python/JS tool bridges
- Remote action execution

**Principle:** If you can write and test an Agent without it, it's a battery.

---

## 7. Design Guardrails

These guardrails prevent Jido from becoming a "second BEAM":

### 7.1 Keep Effect Vocabulary Closed

Every new effect must justify why it can't be an Action. The vocabulary should stay small and domain-oriented.

**Review criteria:**
- Does this describe what the application wants? (Good)
- Does this describe how BEAM should do something? (Bad—use Action)

### 7.2 One Supervision Model

Use OTP supervision directly. AgentServer doesn't invent its own retry/restart semantics.

- Restarts → OTP Supervisor
- Backoff → Supervised process
- Healthchecks → Standard OTP patterns

### 7.3 AgentServer is "Just a GenServer"

No custom scheduling. No second mailbox. No magic.

AgentServer:
1. Receives signals
2. Calls `Agent.handle_signal/2`
3. Executes returned effects
4. That's it

### 7.4 DSL is Optional

The non-DSL path (`def handle_signal/2` + Zoi schemas) must always be first-class. DSL is sugar, not the foundation.

All kernel documentation uses plain Elixir. DSL examples are additive.

---

## 8. Comparison to Similar Patterns

Jido follows patterns proven by mature BEAM frameworks:

### Commanded (CQRS/Event Sourcing)

| Commanded | Jido |
|-----------|------|
| Aggregate | Agent |
| Command | Signal |
| Event | Effect |
| Aggregate Process | AgentServer |

Commanded aggregates are pure: `execute(agg, cmd) → events`. Jido agents are pure: `handle_signal(state, signal) → effects`.

### Sage (Orchestrated Transactions)

Sage defines sagas as step descriptions, not imperative code. A central engine interprets and executes.

Jido agents describe work via effects. AgentServer interprets and executes.

### Ash (Declarative Resources)

Ash resources are pure DSL + data. Runtime adapters do the work.

Jido agents are pure logic + schema. AgentServer does the work.

**All three demonstrate:** "Pure declarative core + effectful runtime" is a successful BEAM pattern.

---

## 9. Non-Goals

Jido 2.0 explicitly **does not** aim to:

### 9.1 Replace GenServer

Jido is for agent workflows. Use plain GenServer for:
- Caches
- Connection pools
- Job workers
- Rate limiters

### 9.2 Be a General-Purpose Effect System

Effects are domain-specific. For general-purpose effect handling, use standard Elixir patterns (with/do, Railway-oriented programming).

### 9.3 Replace Phoenix/Oban/Broadway

Jido integrates with these. It handles the "agent brain"—what to do given a message—not web requests, background jobs, or data pipelines.

### 9.4 Provide a New Process Model

BEAM already has an excellent process model. Jido uses it; doesn't replace it.

---

## Summary

The Jido 2.0 core thesis is:

> **Agents think. Servers act.**
>
> Define pure Agents. Return Effects as data. Let AgentServer handle the messy BEAM stuff. Get testability, replay, and introspection for free.

This is a deliberate move up a level of abstraction—from "how do I manage this GenServer's state" to "what should this agent do given this input."

When in doubt: **if it needs I/O, it's not part of `handle_signal/2`**. Let the Agent think; let `AgentServer` act.

The danger is over-growing the effect vocabulary or DSL. The safeguard is discipline: keep the kernel small, keep effects domain-level, and remember that AgentServer is "just a GenServer."

---

*Specification Version: 2.0.0-draft*  
*Last Updated: December 2024*

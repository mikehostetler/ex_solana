# Erlang/Elixir Bot Framework Research

> Pivoting Jido from LLM-driven agentic flows to deterministic bot framework using state machines for process orchestration.

---

## TL;DR

BEAM bot and workflow systems converge on the same pattern: **each conversation/workflow is an OTP process** (GenServer/gen_statem), events are plain messages, and the process runs a state machine returning new state + commands/effects.

Jido's `handle_signal(state, signal) -> {:ok, new_state, effects}` aligns perfectly with this pattern. The runtime handles process lifecycle, persistence, and effect execution.

---

## 1. Existing Frameworks

### Chat/Bot Frameworks (Elixir)

| Framework | Platform | Architecture |
|-----------|----------|--------------|
| **Hedwig** | Slack, IRC, XMPP | Pattern-matching responders, bot process + adapters |
| **ExGram** | Telegram | Routers, middleware, per-chat handling |
| **Nadia** | Telegram | Low-level API client, you build orchestration |
| **Nostrum** | Discord | Event callbacks (`handle_event/1`), GenServer wiring |
| **Alchemy** | Discord | Similar event-driven architecture |
| **Cog** | ChatOps (historical) | Chat adapters → router → command execution processes |

### Chat/Bot Frameworks (Erlang)

| Framework | Platform | Notes |
|-----------|----------|-------|
| **pe4kin** | Telegram | OTP processes + message passing |
| **erlang-irc-bot** | IRC | Classic OTP: connection process + handler processes |

### State Machine Libraries

| Library | Type | Description |
|---------|------|-------------|
| **:gen_statem** | OTP | Foundational generic state machine behaviour |
| **Fsmx** | Elixir | FSM on Ecto schemas, pure transition functions |
| **Machinery** | Elixir | Declarative FSM with callbacks |

### Workflow/Orchestration

| Library | Pattern | Description |
|---------|---------|-------------|
| **Commanded** | CQRS/ES | Process managers as state machines reacting to events, emitting commands |
| **Broadway/GenStage** | Dataflow | Pipeline processing, deterministic event handling |
| **Oban Pro** | Jobs | Declarative workflow DAGs, persisted state |
| **SERESYE** | Rules (Erlang) | Forward-chaining expert system |
| **Retex** | Rules (Elixir) | Forward-chaining rule engine |

---

## 2. Core Pattern: Process-Per-Conversation

Most BEAM bot/orchestration systems follow:

```
One long-lived process = One conversation/workflow/entity instance
```

### Implementation

- Process keyed by `{chat_id, user_id}`, `{workflow_id}`, or similar
- Implemented with GenServer or :gen_statem
- Supervised by DynamicSupervisor
- Registered via Registry or gproc

### State Machine Inside Process

```elixir
# State contains current phase + accumulated context
%{
  phase: :awaiting_name,
  context: %{user_id: 123, collected_data: %{}}
}
```

Transitions triggered by messages/events via:
- **Explicit FSM:** gen_statem, Machinery, Fsmx
- **Implicit FSM:** Pattern matching on `state.phase` in handle_info/2

---

## 3. Signal/Event Handling Patterns

### A. Events as Messages

Signals represented as tuples:
```elixir
{:user_message, %{chat_id: 123, text: "hello"}}
{:timer_expired, ref}
{:external_event, {:order_paid, order_id}}
```

Delivered via:
- Direct `GenServer.cast/2` or `send/2`
- Pub/sub (`Phoenix.PubSub`)
- Event store subscriptions (Commanded)

### B. GenServer Callback Style

```elixir
def handle_cast({:user_message, msg}, state) do
  # Compute new state, spawn Tasks for side effects
  {:noreply, new_state}
end

def handle_info({:timeout, ref}, state) do
  # Handle timer expiry
  {:noreply, new_state}
end
```

### C. gen_statem Style

```elixir
def handle_event(:cast, signal, state_name, data) do
  # Clear separation of EventType + content
  {:next_state, new_state_name, new_data, actions}
end
```

### D. Pattern-Matching Routers

```
Adapter → Normalize to Signal → Registry Lookup → Route to Process
                                      ↓
                              (not found? start new)
```

- Hedwig: "responders" with regex pattern matching
- ExGram: middleware modules in order

---

## 4. Sub-Process Orchestration

### A. Supervised Children for Subflows

```elixir
# Parent starts subflow
DynamicSupervisor.start_child(SubflowSupervisor, {Subflow, args})

# Parent monitors child, receives completion
def handle_info({:subflow_done, ref, result}, state) do
  # Transition based on subflow result
end
```

### B. Tasks for Short-Lived Effects

```elixir
Task.Supervisor.async_nolink(TaskSup, fn ->
  # Quick I/O
end)
```

### C. Job Queues for Durable Work

```elixir
# Instead of sub-processes, enqueue jobs
Oban.insert(%MyJob{args: ...})
```

Bot remains purely logical; job worker is the "server that acts."

### D. Commanded Process Managers

```elixir
# Process manager receives events, emits commands
def handle(event, state) do
  {new_state, [commands]}
end
```

Sub-workflows are separate process-manager modules listening to events.

---

## 5. Mapping to Jido's Contract

### Pure Agent Module (No OTP Behaviour)

```elixir
defmodule Jido.Agent.SomeFlow do
  @spec handle_signal(state, signal) :: {:ok, new_state, [effect]} | {:error, reason}
  def handle_signal(state, signal) do
    # Pattern match on {state.phase, signal.type}
    # Compute deterministic transitions
    # Return list of effects
  end
end
```

### Runtime Process Wrapper

GenServer that:
1. Holds `state` in memory (and/or persisted)
2. On incoming event: translates to signal
3. Calls `Agent.handle_signal(state, signal)`
4. Persists `new_state`
5. Enacts `effects`:
   - Send messages to chat (via adapter)
   - Enqueue jobs (Oban)
   - Start/stop sub-processes (DynamicSupervisor)
   - Emit domain events

### Process Registry Pattern

```
Jido.Session.Supervisor (DynamicSupervisor)
         ↓
Jido.Session.Registry (Registry)
         ↓
Router routes signals to PID by correlation key
```

### Sub-Process Orchestration as Effects

```elixir
# Effects for subprocess management
%Effect.StartSubflow{module: FlowModule, args: args}
%Effect.AwaitSubflow{ref: ref}
%Effect.CancelSubflow{ref: ref}

# Runtime interprets:
# - Starts child under separate supervisor
# - Propagates results back as signals: {:subflow_result, ref, result}
```

---

## 6. Commanded Comparison

| Commanded | Jido |
|-----------|------|
| Aggregate | Agent (pure state + logic) |
| Command | Signal (input) |
| Event | Effect (output) |
| Aggregate Process | AgentServer (runtime) |
| Process Manager | Agent with orchestration effects |

Commanded's `handle(event, state) -> {state, [commands]}` is semantically identical to `handle_signal(state, signal) -> {:ok, new_state, effects}`.

---

## 7. Key Architectural Insights

### What Works Well

1. **Pure core, effectful shell** - All successful BEAM frameworks use this
2. **Process-per-instance** - Natural fit for BEAM's actor model
3. **State machine as brain** - Clear, testable, introspectable
4. **Effects as data** - Declarative, testable, replayable

### Guardrails

| Risk | Mitigation |
|------|------------|
| Process explosion | Clear policies: when to create process vs. handle inline |
| State drift | Event-source or snapshot; persistence as source of truth |
| Effect vocabulary bloat | Small, well-typed set; single dispatcher |

### When to Go Advanced

Consider Commanded/ES patterns when you need:
- Auditing/replay of all transitions
- Versioned workflows with migration
- Cross-node distributed routing

---

## 8. Jido as Bot Framework

### Core Thesis Alignment

> **Agents think. Servers act.**

For bots, this means:
- **Think:** State machine logic in pure `handle_signal/2`
- **Act:** AgentServer executes effects (send messages, call APIs, orchestrate subflows)

### Proposed Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  External Adapters (Telegram, Discord, Slack, HTTP, etc.)  │
└─────────────────────────┬───────────────────────────────────┘
                          │ Raw events
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  Signal Router                                              │
│  - Normalize to Signal struct                               │
│  - Lookup/create session process by correlation key         │
└─────────────────────────┬───────────────────────────────────┘
                          │ Signal
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  AgentServer (per session/workflow)                         │
│  - Owns agent state                                         │
│  - Calls handle_signal/2 (pure)                             │
│  - Executes effects                                         │
└───────────┬─────────────────────────────────────────────────┘
            │ Effects
            ▼
┌───────────────────────────────────────────────────────────┐
│  Effect Executor                                           │
│  - Effect.Reply → send via adapter                        │
│  - Effect.Run → execute action or enqueue job             │
│  - Effect.Timer → schedule future signal                  │
│  - Effect.StartSubflow → DynamicSupervisor.start_child    │
└───────────────────────────────────────────────────────────┘
```

### State Machine DSL (Future)

```elixir
defmodule MyBot.RegistrationFlow do
  use Jido.Agent,
    name: "registration",
    runner: :state_machine

  state :awaiting_name do
    on "user.message", :validate_name
  end

  state :awaiting_email do
    on "user.message", :validate_email
  end

  state :confirming do
    on "user.confirm", :complete
    on "user.cancel", :cancelled
  end

  state :completed, terminal: true
  state :cancelled, terminal: true
end
```

---

## 9. Next Steps

1. **Implement SignalRouter** - Route signals to session processes
2. **Build AgentServer** - GenServer wrapper for pure agents
3. **Define Effect vocabulary** - Reply, Run, Timer, StartSubflow, etc.
4. **Add state machine runner** - :state_machine runner with transitions
5. **Platform adapters** - Telegram, Discord, HTTP webhook adapters

---

*Research compiled: December 2024*

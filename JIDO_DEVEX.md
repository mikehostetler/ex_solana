# Jido Developer Experience: Refined Model

## The Core Contract

```elixir
{agent, commands} = MyAgent.cmd(agent, signal)
```

That's it. Everything else is implementation detail.

---

## The Two Streams

Jido has two orthogonal data streams that cross the runtime boundary:

| Stream | Direction | Purpose | Examples |
|--------|-----------|---------|----------|
| **Signals** | In/Out | Events — "what happened" | `user.joined`, `order.placed`, `tool.responded` |
| **Commands** | Out | Instructions — "what to do" | `Spawn`, `Schedule`, `Emit`, `Stop` |

**Signals are observable events.** They describe facts. Anyone can listen.

**Commands are runtime instructions.** They tell the runtime what to do next.

### How Agents Emit Both

Agents return Commands from `cmd/2`. To emit a Signal, use `Command.emit/1`:

```elixir
{agent, [
  Command.emit("order.placed", %{order_id: 123}),
  Command.spawn_agent(FulfillmentAgent, %{order_id: 123})
]}
```

The runtime executes Commands → which may produce new Signals → which may arrive at other agents.

---

## The Refined Conceptual Model

```
┌─────────────────────────────────────────────────────────────────┐
│                         PUBLIC API                               │
│                                                                  │
│   Signal ────────► MyAgent.cmd/2 ────────► {state, commands}    │
│                                                                  │
│   • Signals = events (observable, descriptive)                  │
│   • Commands = instructions (imperative, runtime executes)      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      UNDER THE HOOD                              │
│                                                                  │
│   Signal ──► Strategy.cmd/3 ──► runs Actions ──► Commands       │
│                                                                  │
│   • Strategy = execution engine (HOW actions run)               │
│   • Actions = units of work (business logic)                    │
└─────────────────────────────────────────────────────────────────┘
```

**For most developers:** Only Signals and Commands matter.

**For framework users:** Strategy controls execution patterns; Actions organize logic.

---

## Where Strategy Fits

**Strategy is the execution engine.** It decides HOW `cmd/2` runs your Actions.

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    strategy: Jido.Agent.Strategy.Direct  # default
end
```

| Strategy | What it does |
|----------|--------------|
| `Direct` | Execute actions immediately, sequentially (default) |
| `FSM` | Finite state machine with explicit transitions |
| `BehaviorTree` | Hierarchical task decomposition |
| `LLMChain` | AI-powered chains of thought |

**Strategy is invisible until you need it.** The Direct strategy "just works" — your `cmd/2` runs your code. Advanced strategies enable complex patterns without changing the Signals + Commands boundary.

### Strategy and Signal Routing

Strategies can intercept Signals and route them to internal handlers:

```elixir
def signal_routes(_ctx) do
  [
    {"react.user_query", {:strategy_cmd, :react_start}},
    {"ai.llm_result", {:strategy_cmd, :react_llm_result}}
  ]
end
```

This enables multi-step workflows where:
1. External Signal arrives
2. Strategy routes to internal Action
3. Action runs, updates state
4. Strategy emits Commands (which may produce more Signals)

---

## Where Actions Fit

**Actions are how you organize business logic.** They're not a third pillar — they're implementation detail.

```elixir
defmodule ProcessOrderAction do
  use Jido.Action,
    name: "process_order",
    schema: [order_id: [type: :integer, required: true]]

  def run(%{order_id: id}, context) do
    # Business logic here
    {:ok, %{status: :processed}}
  end
end
```

**Rule of thumb:**
- **Actions** know business/domain details
- **Strategy** knows control flow
- **Signals** are what happened
- **Commands** are what to do

---

## Progressive Disclosure

### Layer 1: Signals + Commands (5 minutes)

For new developers. No Strategy, no Actions.

```elixir
def cmd(agent, signal) do
  case signal.type do
    "user.joined" ->
      agent = update_in(agent.state.users, &[signal.data.user_id | &1])
      {agent, []}

    "user.send_welcome" ->
      commands = [Command.emit("email.send", %{to: signal.data.email})]
      {agent, commands}
  end
end
```

**Teach:** Signal = event, Command = instruction, Runtime executes commands.

### Layer 2: Actions (15 minutes)

Introduce Actions as helpers — reusable, validated units of work.

```elixir
def cmd(agent, signal) do
  case signal.type do
    "order.place" ->
      MyAgent.cmd(agent, {ProcessOrderAction, signal.data})
  end
end
```

**Teach:** Actions organize logic. They're called from `cmd/2`, not invoked magically.

### Layer 3: Strategies (30 minutes)

Introduce Strategy configuration and patterns.

```elixir
use Jido.Agent,
  strategy: {Jido.Agent.Strategy.FSM,
    initial_state: "idle",
    transitions: %{
      "idle" => ["processing"],
      "processing" => ["completed", "failed"]
    }}
```

**Teach:** Strategy controls HOW actions execute. Direct is default. FSM, behavior trees, LLM chains are drop-in replacements.

### Layer 4: Observability Patterns (Advanced)

Signals as the event backbone:

```elixir
# Emit domain events for observability
commands = [
  Command.emit("order.placed", %{order_id: id, customer_id: cid}),
  Command.emit("metrics.order_count", %{delta: 1})
]

# Other agents/systems subscribe to these signals
def signal_routes(_ctx) do
  [
    {"order.placed", {:strategy_cmd, :start_fulfillment}},
    {"order.placed", {:strategy_cmd, :notify_warehouse}}
  ]
end
```

---

## Naming: Directive → Command

| Current | Proposed | Rationale |
|---------|----------|-----------|
| `Directive` | `Command` | Matches Elm `Cmd`, CQRS, GenServer patterns |
| `Effect` | *(demote to prose)* | Not a type, shouldn't be a concept |
| `Action` | Keep, reframe | "How you organize work" not "third pillar" |

---

## The Complete Picture

```
              Signals (events)                Commands (instructions)
                    │                                │
                    ▼                                │
┌─────────────────────────────────────────────────────────────────┐
│                        AgentServer                               │
│                                                                  │
│   receives Signal ──► MyAgent.cmd/2 ──► {state, commands} ──────┤
│                           │                                      │
│                           ▼                                      │
│                    Strategy.cmd/3                                │
│                           │                                      │
│                           ▼                                      │
│                   runs Action(s)                                 │
│                           │                                      │
│                           ▼                                      │
│              {updated_state, commands}                           │
└─────────────────────────────────────────────────────────────────┘
                                                     │
                                                     ▼
                                          Runtime executes Commands
                                                     │
                                                     ▼
                                    ┌────────────────┴────────────────┐
                                    │                                 │
                              Command.emit             Command.spawn_agent
                                    │                                 │
                                    ▼                                 ▼
                              New Signal               New Agent (receives Signals)
```

---

## Summary

| Concept | Role | Visibility |
|---------|------|------------|
| **Signal** | Events — "what happened" | Public API |
| **Command** | Instructions — "what to do" | Public API |
| **Strategy** | Execution engine — "how to run" | Framework config |
| **Action** | Units of work — "the logic" | Implementation detail |

**The elevator pitch:**

> Jido is Elm-like. Signals arrive at agents. Agents return `{state, commands}`. The runtime executes commands. That's it.
>
> Under the hood, Strategies control how actions execute. But you don't need to know that until you need behavior trees or LLM chains.

---

## Migration Path

1. **Rename in docs first** — call Directives "Commands" in all prose
2. **Add `Command` alias** — `alias Jido.Directive, as: Command`
3. **Deprecate `Directive`** — soft deprecation with clear migration
4. **Remove in next major** — `Jido.Command` becomes canonical

---

## Next Steps

- [ ] Finalize naming decision (Directive → Command)
- [ ] Update overview docs with new framing
- [ ] Create progressive disclosure doc structure
- [ ] Update examples to use Commands + Signals language
- [ ] Add "Observability Patterns" advanced guide

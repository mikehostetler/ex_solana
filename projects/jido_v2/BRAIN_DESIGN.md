# Agent Brain Design

> How `use Jido.Agent` supports multiple "thinking brain" types while maintaining a single pure contract.

---

## Core Insight

**One contract, many brains.**

All agents implement:
```elixir
handle_signal(state, signal) -> {:ok, new_state, effects} | {:error, term()}
```

Brain types are **compile-time macros** that generate this callback from a declarative DSL. The kernel never knows the details.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Brain Macros (compile-time code generation)               │
│  Jido.Agent.Brain.StateMachine                             │
│  Jido.Agent.Brain.BehaviorTree                             │
│  Jido.Agent.Brain.HTN                                      │
│  Jido.Agent.Brain.LlmFlow                                  │
├─────────────────────────────────────────────────────────────┤
│  Jido.Agent (kernel behaviour)                             │
│  handle_signal/2 callback                                  │
│  Zoi-backed state struct                                   │
├─────────────────────────────────────────────────────────────┤
│  Agent Module (user code)                                  │
│  use Jido.Agent + use Jido.Agent.Brain.X                   │
└─────────────────────────────────────────────────────────────┘
```

---

## The Four Brain Types

### 1. State Machine

**Use case:** Deterministic workflows with explicit states and transitions.

**Internal state:**
```elixir
%{
  node: :awaiting_email,      # current state
  history: [:awaiting_name],  # optional trace
  data: %{}                   # ephemeral per-state data
}
```

**Signal interpretation:**
- Dispatch on `{current_node, signal.type}`
- Transition fires function: `(state, signal) -> {new_state, effects}`
- Unknown signals are ignored (no transition)

**DSL example:**
```elixir
defmodule MyApp.RegistrationAgent do
  use Jido.Agent,
    name: "registration",
    schema: %{
      user_id: Zoi.integer(),
      brain: Zoi.any() |> Zoi.default(nil)
    }

  use Jido.Agent.Brain.StateMachine, initial: :awaiting_name do
    state :awaiting_name do
      on "user.message", :awaiting_email, &handle_name/2
    end

    state :awaiting_email do
      on "user.message", :confirming, &handle_email/2
    end

    state :confirming do
      on "user.confirm", :completed, &complete/2
      on "user.cancel", :cancelled, &cancel/2
    end

    terminal :completed
    terminal :cancelled
  end
end
```

---

### 2. Behavior Tree

**Use case:** Complex decision trees with tick-driven evaluation.

**Internal state:**
```elixir
%{
  status: :running,           # :idle | :running | :success | :failure
  cursor: [:root, :seq1, 0],  # current traversal path
  blackboard: %{}             # shared variables
}
```

**Signal interpretation:**
- `"system.tick"`: Run one BT tick (depth-first traversal)
- Domain signals: Update blackboard, optionally trigger re-evaluation
- Nodes are pure functions: `(state, blackboard, signal) -> {blackboard, node_status}`

**DSL example:**
```elixir
defmodule MyApp.BotAgent do
  use Jido.Agent,
    name: "bot",
    schema: %{brain: Zoi.any() |> Zoi.default(nil)}

  use Jido.Agent.Brain.BehaviorTree do
    tree :root do
      sequence do
        node :ensure_context, &ensure_context/3
        selector do
          node :handle_help, &handle_help/3
          node :handle_smalltalk, &handle_smalltalk/3
          node :fallback, &fallback/3
        end
      end
    end
  end
end
```

**Node types:**
| Node | Behavior |
|------|----------|
| `sequence` | Run children in order; fail on first failure |
| `selector` | Run children until one succeeds |
| `parallel` | Run all children; configurable success threshold |
| `node` | Leaf node with custom function |

---

### 3. Hierarchical Task Network (HTN)

**Use case:** Goal decomposition into primitive tasks.

**Internal state:**
```elixir
%{
  goal: :fulfill_order,       # current top-level goal
  plan: [:reserve, :charge],  # linearized primitive tasks
  stack: [],                  # decomposition stack
  status: :executing,         # :idle | :planning | :executing | :completed | :failed
  memory: %{}                 # world state / beliefs
}
```

**Signal interpretation:**
- `"goal.set"`: Set goal, trigger planning
- `"goal.cancel"`: Abort current goal
- `"task.completed"` / `"task.failed"`: Progress on plan
- Planning is pure decomposition of compound tasks into primitives

**DSL example:**
```elixir
defmodule MyApp.OrderAgent do
  use Jido.Agent,
    name: "order_flow",
    schema: %{
      order_id: Zoi.integer(),
      brain: Zoi.any() |> Zoi.default(nil)
    }

  use Jido.Agent.Brain.HTN do
    method :fulfill_order, when: &can_fulfill?/1 do
      decompose do
        task :reserve_inventory
        task :charge_payment
        task :schedule_shipping
      end
    end

    method :fulfill_order, when: &needs_backorder?/1 do
      decompose do
        task :create_backorder
        task :notify_customer
      end
    end

    primitive :reserve_inventory, action: InventoryActions.Reserve
    primitive :charge_payment, action: PaymentActions.Charge
    primitive :schedule_shipping, action: ShippingActions.Schedule
  end
end
```

**HTN loop:**
1. Goal set → decompose into plan (pure)
2. Execute head task → emit `Effect.Run`
3. `"task.completed"` → advance plan
4. `"task.failed"` → replan or fail goal

---

### 4. LLM Tool Call Flow (ReAct)

**Use case:** LLM-driven think/act/observe loops.

**Internal state:**
```elixir
%{
  phase: :thinking,           # :idle | :thinking | :waiting_tools | :observing | :done
  history: [message()],       # conversation with user + LLM + tools
  pending_tools: [],          # tool calls awaiting results
  last_request_id: nil        # for correlating LLM responses
}
```

**Signal interpretation:**
- `"user.message"`: Append to history, emit LLM call effect
- `"llm.result"`: Parse tool calls or final answer
- `"tool.result"`: Update history, check if all tools done
- All LLM/tool invocations are `Effect.Run` to Action modules

**DSL example:**
```elixir
defmodule MyApp.SupportAgent do
  use Jido.Agent,
    name: "support",
    schema: %{
      user_id: Zoi.integer(),
      brain: Zoi.any() |> Zoi.default(nil)
    }

  use Jido.Agent.Brain.LlmFlow,
    tools: [LookupFAQ, CreateTicket, SearchDocs],
    system_prompt: "You are a helpful support agent..." do

    on_user_message &preprocess_message/2
    on_final_answer &format_response/2
  end
end
```

**ReAct loop:**
```
user.message → thinking → llm.result
                    ↓
            [has tool calls?]
                /        \
              yes         no
               ↓           ↓
        waiting_tools   Effect.Reply (answer)
               ↓
        tool.result (each tool)
               ↓
        [all done?] → observing → llm.result → ...
```

---

## Internal State: The `brain` Field

All brains store their internal state in `state.brain`:

```elixir
@base_schema %{
  id: Zoi.string() |> Zoi.optional(),
  brain: Zoi.any() |> Zoi.default(nil)  # reserved for brain types
}
```

**Convention:**
- `state.brain` is owned by the brain macro
- All other fields are domain state (your business logic)
- Brain macros initialize `state.brain` appropriately

---

## Macro Implementation Pattern

All brain macros follow the same pattern:

```elixir
defmodule Jido.Agent.Brain.StateMachine do
  defmacro __using__(opts) do
    quote location: :keep do
      Module.put_attribute(__MODULE__, :brain_type, :state_machine)
      import Jido.Agent.Brain.StateMachine.DSL
      @before_compile Jido.Agent.Brain.StateMachine
    end
  end

  defmacro __before_compile__(env) do
    spec = Module.get_attribute(env.module, :__sm_spec__)

    quote do
      @impl Jido.Agent
      def handle_signal(state, signal) do
        Jido.Agent.Brain.StateMachine.run(state, signal, unquote(Macro.escape(spec)))
      end
    end
  end

  # Pure interpreter - no I/O
  @spec run(struct(), Jido.Signal.t(), term()) :: Jido.Agent.result(struct())
  def run(state, signal, spec) do
    # Pattern match on {state.brain.node, signal.type}
    # Execute transition function
    # Return {:ok, new_state, effects}
  end
end
```

**Key properties:**
- DSL collected at compile-time via module attributes
- `__before_compile__` generates the `handle_signal/2` implementation
- `run/3` is a pure interpreter that executes the compiled spec
- No runtime polymorphism needed

---

## Signal Type Conventions

Each brain has expected signal patterns:

| Brain | Key Signals |
|-------|-------------|
| **StateMachine** | Domain events matching transition triggers |
| **BehaviorTree** | `"system.tick"`, domain events for blackboard |
| **HTN** | `"goal.set"`, `"goal.cancel"`, `"task.completed"`, `"task.failed"` |
| **LlmFlow** | `"user.message"`, `"llm.result"`, `"tool.result"` |

All signals flow through the same `handle_signal/2` - the brain interprets them differently.

---

## Manual Implementation (No Brain)

You can always skip brain macros and implement directly:

```elixir
defmodule MyApp.SimpleAgent do
  use Jido.Agent,
    name: "simple",
    schema: %{count: Zoi.integer() |> Zoi.default(0)}

  @impl Jido.Agent
  def handle_signal(state, %{type: "increment"} = signal) do
    amount = signal.data["amount"] || 1
    {:ok, %{state | count: state.count + amount}, []}
  end

  def handle_signal(state, _signal), do: {:ok, state, []}
end
```

Brain macros are convenience, not requirement.

---

## Introspection (Optional)

For tooling/visualization, brain macros can expose metadata:

```elixir
defmodule Jido.Agent.Brain do
  @callback type() :: atom()
  @callback spec(module()) :: term()
end

# Usage
MyApp.RegistrationAgent.__brain_type__()  # => :state_machine
MyApp.RegistrationAgent.__brain_spec__()  # => %{states: [...], transitions: [...]}
```

This feeds documentation generators, visualizers, and debugging tools without affecting runtime.

---

## Comparison

| Aspect | StateMachine | BehaviorTree | HTN | LlmFlow |
|--------|--------------|--------------|-----|---------|
| **Determinism** | Fully deterministic | Deterministic | Deterministic planning | Non-deterministic (LLM) |
| **Control flow** | Event-driven transitions | Tick-driven traversal | Goal-driven decomposition | Request-response loops |
| **State shape** | `{node, history}` | `{cursor, blackboard}` | `{goal, plan, stack}` | `{phase, history, pending}` |
| **Best for** | Workflows, protocols | Game AI, decision trees | Planning, automation | Chat, assistants |

---

## Guardrails

1. **State field ownership:** `state.brain` is reserved for brain macros; domain fields are yours
2. **DSL simplicity:** Start minimal (StateMachine: just states/transitions; BT: sequence/selector only)
3. **Effect vocabulary:** Brains compose with existing effects (Run, Reply, Timer), don't invent new I/O types
4. **Kernel ignorance:** `Jido.Agent` never knows about specific brain types

---

## Summary

- **One contract:** `handle_signal(state, signal) -> {:ok, new_state, effects}`
- **Many brains:** StateMachine, BehaviorTree, HTN, LlmFlow
- **Compile-time:** Brain macros generate `handle_signal/2` from DSL
- **Pure:** All brains are pure interpreters; I/O happens via Effects
- **Optional:** Manual implementation always works; brains are convenience

**Agents think. The brain type determines *how* they think.**

---

*Design Version: 2.0.0-draft*
*Last Updated: December 2024*

# Jido 2.0 - Design Patterns

Jido employs and encourages several key design patterns that make agent systems robust, testable, and maintainable.

## Pattern 1: Elm/Redux-Style Update Loop

The core of Jido follows the Elm Architecture / Redux pattern.

### The Pattern

```
State + Action → New State + Effects
```

In Jido:

```elixir
{agent, directives} = MyAgent.cmd(agent, action)
```

### Characteristics

- **Single entry point** - All state changes flow through `cmd/2`
- **Immutable updates** - State is never mutated in place
- **Predictable** - Same inputs always produce same outputs
- **Effects as data** - Side effects are returned, not executed

### Benefits

- Easy to reason about state changes
- Time-travel debugging possible
- Straightforward testing
- Clear audit trail of what happened

## Pattern 2: State Transitions vs Runtime Instructions

Jido separates internal state changes from external runtime instructions.

### The Pattern

```
Actions transform state (internal)
Directives describe effects (external)
```

### In Practice

```elixir
def run(params, context) do
  # Command: Update internal state
  new_count = context.state[:count] + params.amount
  
  {:ok, %{
    count: new_count,
    # Directive: Describe external effect
    __directives__: [
      %Directive.Emit{signal: Jido.Signal.new!("count.updated", %{count: new_count})}
    ]
  }}
end
```

### Relationship to Elm/CQRS

- **Actions** → State changes (synchronous, validated)
- **Directives** → External effects (async, decoupled)

> **Note:** We use "Directive" rather than "Command" intentionally. In Elixir, "command" is overloaded (GenServer calls, CQRS, CLI). Directives are runtime instructions—data describing what the AgentServer should do.

## Pattern 3: Pure Core, Effectful Shell

All domain logic is pure and functional. Effects are centralized in the runtime.

### The Pattern

```
┌─────────────────────────────────────┐
│         Effectful Shell             │
│  (AgentServer, DirectiveExec, I/O)  │
│  ┌─────────────────────────────────┐│
│  │         Pure Core               ││
│  │  (Agents, Actions, Strategies)  ││
│  └─────────────────────────────────┘│
└─────────────────────────────────────┘
```

### Benefits

- **Testability** - Test business logic without mocking
- **Portability** - Pure core works anywhere
- **Observability** - All I/O in one place to instrument
- **Reliability** - Fewer places for side effects to fail

### Example

```elixir
# Pure - no mocking needed
test "increment action updates count" do
  agent = MyAgent.new!(%{count: 0})
  action = %MyActions.Increment{amount: 5}
  
  {updated_agent, _directives} = MyAgent.cmd(agent, action)
  
  assert updated_agent.state.count == 5
end
```

## Pattern 4: Strategy Pattern

Execution behavior is pluggable via strategies.

### The Pattern

```elixir
defmodule MyAgent do
  use Jido.Agent,
    strategy: MyCustomStrategy
end
```

### Built-in Strategies

| Strategy | Behavior |
|----------|----------|
| `Direct` | Execute immediately, sequentially |
| `FSM` | Finite state machine with transitions |

### When to Use

- **Direct** - Simple, immediate execution (default)
- **FSM** - When agent has distinct states and transitions
- **Custom** - Multi-step workflows, LLM loops, complex orchestration

### Creating a Custom Strategy

```elixir
defmodule MyApp.BatchStrategy do
  use Jido.Agent.Strategy

  @impl true
  def cmd(agent, instructions, ctx) do
    # Custom batching logic
    {agent, []}
  end
end
```

## Pattern 5: Composition via Skills

Capabilities are packaged as skills and attached declaratively.

### The Pattern

```elixir
defmodule MyAgent do
  use Jido.Agent,
    skills: [
      ChatSkill,
      {DatabaseSkill, %{pool_size: 5}},
      LoggingSkill
    ]
end
```

### Skill Characteristics

- **Self-contained** - Actions, state, routing bundled together
- **Configurable** - Optional config schema
- **Composable** - Multiple skills work together
- **Isolated** - Each skill has its own state slice

### Benefits

- Reuse capabilities across agents
- Mix and match features
- Test skills independently
- Clear capability boundaries

## Pattern 6: Schema-Driven Design

Validation at the boundaries ensures data integrity.

### The Pattern

```elixir
# Agent state schema
use Jido.Agent,
  schema: [
    count: [type: :integer, default: 0],
    name: [type: :string, required: true]
  ]

# Action parameter schema
use Jido.Action,
  schema: [
    amount: [type: :integer, default: 1]
  ]

# Skill config schema
use Jido.Skill,
  schema: Zoi.object(%{
    model: Zoi.string() |> Zoi.default("gpt-4")
  })
```

### Benefits

- **Fail fast** - Invalid data rejected at boundaries
- **Self-documenting** - Schemas describe expected data
- **Type safety** - Validated data throughout
- **Clear contracts** - Components define their requirements

## Pattern 7: Event-Driven Messaging

Signals provide loose coupling between components.

### The Pattern

```
Producer → Signal → Router → Consumer
```

### Signal Flow

1. Emit directive describes signal to send
2. Dispatch adapter delivers signal
3. Router determines target(s)
4. Consumer handles signal

### Dispatch Adapters

- `:pubsub` - Phoenix.PubSub
- `:bus` - In-cluster signal bus
- `:http` / `:webhook` - External HTTP endpoints
- `:pid` / `:named` - Direct process delivery

### Benefits

- **Decoupling** - Producers don't know consumers
- **Scalability** - Add consumers without changing producers
- **Flexibility** - Swap transports easily
- **Observability** - Signals are inspectable

## Pattern 8: Observability by Default

All major activities emit telemetry.

### The Pattern

```elixir
# Automatic telemetry for all cmd/2 calls
[:jido, :agent, :cmd, :start]
[:jido, :agent, :cmd, :stop]
[:jido, :agent, :cmd, :exception]
```

### Using Jido.Observe

```elixir
Jido.Observe.span(:my_operation, %{metadata: "value"}, fn ->
  # Automatically wrapped in telemetry span
  do_work()
end)
```

### Benefits

- **Consistent** - Same patterns everywhere
- **Automatic** - No manual instrumentation needed
- **Extensible** - Hook in custom tracers
- **Production-ready** - OpenTelemetry compatible

## Summary

| Pattern | Purpose |
|---------|---------|
| Elm/Redux Loop | Predictable state updates |
| State/Directive Separation | Separate state transitions from runtime effects |
| Pure Core | Testable business logic |
| Strategy (Effect Interpreter) | Pluggable execution behavior |
| Skills | Composable capabilities |
| Schema-Driven | Data validation at boundaries |
| Event-Driven | Loose coupling via signals |
| Observability | Built-in instrumentation |

These patterns work together to create agent systems that are:
- **Predictable** - Pure functions, clear data flow
- **Testable** - No mocking for business logic
- **Composable** - Skills and strategies mix and match
- **Observable** - Telemetry throughout
- **Maintainable** - Clear boundaries and contracts

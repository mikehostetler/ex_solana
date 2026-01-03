# Agents

Agents are immutable data structures that hold state and respond to actions. The core operation is `cmd/2`, which processes actions and returns an updated agent plus directives for external effects.

## Defining an Agent

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",                        # Required - alphanumeric + underscores
    description: "My custom agent",          # Optional
    category: "example",                     # Optional
    tags: ["demo"],                          # Default: []
    vsn: "1.0.0",                            # Optional
    schema: [                                # State schema (see below)
      status: [type: :atom, default: :idle],
      counter: [type: :integer, default: 0]
    ],
    strategy: Jido.Agent.Strategy.Direct,    # Default
    skills: [MySkill]                        # Default: []
end
```

## The `cmd/2` Contract

The fundamental operation:

```elixir
{agent, directives} = MyAgent.cmd(agent, action)
```

**Key invariants:**

- The returned `agent` is always complete—no "apply directives" step needed
- `directives` describe external effects only—they never modify agent state
- `cmd/2` is a pure function—given same inputs, always same outputs

**Action formats:**

```elixir
# Action module with no params
{agent, directives} = MyAgent.cmd(agent, MyAction)

# Action with params
{agent, directives} = MyAgent.cmd(agent, {MyAction, %{value: 42}})

# Full instruction struct
{agent, directives} = MyAgent.cmd(agent, %Instruction{action: MyAction, params: %{}})

# List of actions (processed in sequence)
{agent, directives} = MyAgent.cmd(agent, [Action1, {Action2, %{x: 1}}])
```

## State Management

### `set/2` — Update State

Deep-merges attributes into agent state:

```elixir
{:ok, agent} = MyAgent.set(agent, %{status: :running})
{:ok, agent} = MyAgent.set(agent, counter: 5)
```

### `validate/2` — Validate Against Schema

```elixir
# Validate state, keeping extra fields
{:ok, agent} = MyAgent.validate(agent)

# Strict mode: only schema-defined fields are kept
{:ok, agent} = MyAgent.validate(agent, strict: true)
```

## Lifecycle Hooks

Optional callbacks for pure transformations before/after command processing.

### `on_before_cmd/2`

Called before action processing. Transform agent or action:

```elixir
def on_before_cmd(agent, action) do
  # Example: log the action being processed
  {:ok, agent} = set(agent, %{last_action: inspect(action)})
  {:ok, agent, action}
end
```

Use cases:
- Mirror action params into agent state
- Add default params based on current state
- Enforce invariants before execution

### `on_after_cmd/3`

Called after action processing. Transform agent or directives:

```elixir
def on_after_cmd(agent, action, directives) do
  # Example: auto-validate after every command
  {:ok, agent} = validate(agent)
  {:ok, agent, directives}
end
```

Use cases:
- Auto-validate state after changes
- Derive computed fields
- Add invariant checks

## Schema Options

Agent state is validated against a schema. Two formats are supported:

### NimbleOptions (legacy, familiar)

```elixir
use Jido.Agent,
  name: "my_agent",
  schema: [
    status: [type: :atom, default: :idle],
    counter: [type: :integer, default: 0],
    config: [type: {:map, :atom, :string}, default: %{}]
  ]
```

### Zoi (recommended for new code)

```elixir
use Jido.Agent,
  name: "my_agent",
  schema: Zoi.object(%{
    status: Zoi.atom() |> Zoi.default(:idle),
    counter: Zoi.integer() |> Zoi.default(0),
    config: Zoi.map() |> Zoi.default(%{})
  })
```

Both are handled transparently by the Agent module.

## Creating Agents

```elixir
# Create with defaults
agent = MyAgent.new()

# Create with custom ID
agent = MyAgent.new(id: "custom-id")

# Create with initial state
agent = MyAgent.new(state: %{counter: 10})
```

## Further Reading

- `Jido.Agent` — Full module documentation
- `Jido.Agent.Directive` — Available directives
- `Jido.Agent.Strategy` — Execution strategies
- `Jido.Action` — Defining actions for agents

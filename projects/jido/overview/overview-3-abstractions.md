# Jido 2.0 - Main Abstractions

## Agents

Agents are the central abstraction in Jido - immutable, schema-validated state containers with a pure command interface.

### Defining an Agent

```elixir
defmodule MyApp.CounterAgent do
  use Jido.Agent,
    name: "counter",
    description: "A simple counter agent",
    schema: [
      count: [type: :integer, default: 0],
      last_updated: [type: {:or, [:nil, DateTime]}, default: nil]
    ]
end
```

### Agent Characteristics

- **Immutable struct** with schema-validated `state` (NimbleOptions or Zoi)
- **Core operations**:
  - `new/0,1` - Build an initialized agent struct
  - `set/2` - Validate and update state directly
  - `validate/2` - Validate agent state
  - `cmd/2` - Run actions and return `{agent, directives}`
- **Lifecycle hooks** (optional):
  - `on_before_cmd/2` - Pre-processing of `(agent, action)`
  - `on_after_cmd/3` - Post-processing of `(agent, directives)`

### The cmd/2 Contract

```elixir
{agent, directives} = MyAgent.cmd(agent, action)
```

This is the fundamental operation. It's pure: same inputs always produce the same outputs.

## Actions

Actions are pure, validated units of work that transform agent state. They come from `jido_action`.

### Defining an Action

```elixir
defmodule MyApp.Actions.Increment do
  use Jido.Action,
    name: "increment",
    description: "Increments the counter",
    schema: [amount: [type: :integer, default: 1]]

  def run(params, context) do
    current = context.state[:count] || 0
    {:ok, %{count: current + params.amount}}
  end
end
```

### Action Characteristics

- Always return tagged tuples: `{:ok, result}` or `{:error, reason}`
- Receive `params` (validated against schema) and a `context` map
- Context includes agent state, metadata, etc.
- Results are merged into agent state by the strategy

## Directives

Directives are bare structs describing external effects. The runtime interprets and executes them.

### Built-in Directives

| Directive | Purpose |
|-----------|---------|
| `%Directive.Emit{}` | Emit a `Jido.Signal` via adapters |
| `%Directive.Error{}` | Signal an error from command execution |
| `%Directive.Spawn{}` | Spawn an arbitrary BEAM child process |
| `%Directive.SpawnAgent{}` | Spawn a child Jido agent with parent tracking |
| `%Directive.StopChild{}` | Stop a tracked child |
| `%Directive.Schedule{}` | Schedule delayed messages |
| `%Directive.Stop{}` | Stop the current agent process |
| `%Directive.Cron{}` | Manage cron jobs via `Jido.Scheduler` |
| `%Directive.CronCancel{}` | Cancel scheduled cron jobs |

### Directive Flow

1. `cmd/2` returns directives alongside the updated agent
2. Directives are never fed back into the agent
3. The runtime (`AgentServer.DirectiveExec`) consumes and executes them

## Strategies

Strategies define **how** instructions are executed for an agent. In functional programming terms, they are **pure effect interpreters**.

### Strategy Callbacks

```elixir
@callback cmd(agent, instructions, ctx) :: {agent, directives}
@callback init(agent, ctx) :: {agent, directives}
@callback tick(agent, ctx) :: {agent, directives}
@callback snapshot(agent, ctx) :: Strategy.Snapshot.t()
@callback action_spec(action) :: map() | nil
@callback signal_routes(ctx) :: map()
```

### What Strategies Do

1. **Execute instructions** - Run actions via `Jido.Exec.run/1`
2. **Merge results** - Apply action results to agent state
3. **Handle internal effects** - Process `Jido.Agent.Internal.*` state operations
4. **Collect directives** - Pass through `Jido.Agent.Directive.*` for runtime execution

The strategy's `cmd/3` always returns `{updated_agent, external_directives}` — internal state operations are resolved before the function returns.

### Built-in Strategies

- **`Jido.Agent.Strategy.Direct`** - Default; executes instructions sequentially and immediately
- **`Jido.Agent.Strategy.FSM`** - Finite state machine with configurable transitions (idle → processing → completed/failed)

### Using a Custom Strategy

```elixir
defmodule MyApp.MyAgent do
  use Jido.Agent,
    name: "my_agent",
    strategy: {Jido.Agent.Strategy.FSM, 
      initial_state: "idle", 
      transitions: %{
        "idle" => ["processing"],
        "processing" => ["completed", "failed"]
      }
    }
end
```

## Skills

Skills are composable capability bundles that can be attached to agents.

### Skill Components

- **Actions** - Set of actions the skill provides
- **State slice** - Separate state under `state_key`
- **Config schema** - Optional configuration validation
- **Signal routing** - Patterns for routing signals to actions
- **Children** - Optional supervised child processes
- **Lifecycle hooks** - Mount, router, handle_signal, etc.

### Defining a Skill

```elixir
defmodule MyApp.ChatSkill do
  use Jido.Skill,
    name: "chat",
    state_key: :chat,
    actions: [MyApp.Actions.SendMessage],
    schema: Zoi.object(%{
      messages: Zoi.list(Zoi.any()) |> Zoi.default([]),
      model: Zoi.string() |> Zoi.default("gpt-4")
    }),
    signal_patterns: ["chat.*"]

  @impl Jido.Skill
  def mount(_agent, config) do
    {:ok, %{initialized_at: DateTime.utc_now(), model: config[:model] || "gpt-4"}}
  end
end
```

### Attaching Skills to Agents

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    skills: [
      MyApp.ChatSkill,
      {MyApp.DatabaseSkill, %{pool_size: 5}}
    ]
end
```

## Signals

Signals (from `jido_signal`) carry CloudEvents-style messages through the system.

### Signal Flow

1. External systems, sensors, or code create `Jido.Signal` structs
2. Signals are delivered to agents via `cast/2` or `call/3`
3. `SignalRouter` routes signals to actions using:
   - Strategy's `signal_routes/1`
   - Skills' routers and `signal_patterns`
   - Fallback mapping
4. Actions execute and produce directives
5. `%Directive.Emit{}` sends signals back out via dispatch adapters

## Sensors

Sensors (via `Jido.Sensor` in the ecosystem) are processes that emit signals on schedules or external events:

- Cron-based periodic signals
- Heartbeat signals
- External event monitoring

## Discovery

`Jido.Discovery` builds a catalog of available components from modules that expose metadata functions:

- `__action_metadata__/0`
- `__agent_metadata__/0`
- `__skill_metadata__/0`
- `__sensor_metadata__/0`
- `__demo_metadata__/0`

Used for runtime discovery, tooling, UIs, and workbenches.

## Abstraction Relationships

```
┌─────────────────────────────────────────────────────────┐
│                      Agent                               │
│  ┌─────────────────────────────────────────────────────┐│
│  │ State (schema-validated)                            ││
│  │  ├── Core state fields                              ││
│  │  └── Skill state slices                             ││
│  └─────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────┐│
│  │ Strategy (pluggable)                                ││
│  │  └── Determines how actions execute                 ││
│  └─────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────┐│
│  │ Skills (composable)                                 ││
│  │  ├── Actions                                        ││
│  │  ├── Signal routing                                 ││
│  │  └── Lifecycle hooks                                ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
                          │
                          │ cmd/2
                          ▼
┌─────────────────────────────────────────────────────────┐
│                     Actions                              │
│  Pure functions: (params, context) → {:ok, result}      │
└─────────────────────────────────────────────────────────┘
                          │
                          │ produces
                          ▼
┌─────────────────────────────────────────────────────────┐
│                    Directives                            │
│  Data describing effects: Emit, Spawn, Schedule, Stop   │
└─────────────────────────────────────────────────────────┘
                          │
                          │ executed by
                          ▼
┌─────────────────────────────────────────────────────────┐
│                     Runtime                              │
│  AgentServer → DirectiveExec → External Systems         │
└─────────────────────────────────────────────────────────┘
```

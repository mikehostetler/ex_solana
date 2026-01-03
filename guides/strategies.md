# Strategies

Strategies control **how agents execute actions** in `cmd/2`. They enable different execution patterns without changing agent logic.

## What Strategies Control

Strategies can implement:

- Sequential execution (Direct)
- State machines (FSM)
- Behavior trees
- LLM chains of thought
- Custom execution patterns

## Built-in Strategies

### Direct (Default)

Executes actions immediately and sequentially:

```elixir
use Jido.Agent,
  name: "my_agent",
  strategy: Jido.Agent.Strategy.Direct
```

### FSM

Finite state machine with explicit transitions:

```elixir
use Jido.Agent,
  name: "fsm_agent",
  strategy: {Jido.Agent.Strategy.FSM,
    initial_state: "idle",
    transitions: %{
      "idle" => ["processing"],
      "processing" => ["idle", "completed", "failed"],
      "completed" => ["idle"],
      "failed" => ["idle"]
    }
  }
```

## Snapshot Interface

Get a stable view of strategy state:

```elixir
snap = MyAgent.strategy_snapshot(agent)

snap.status   # :idle, :running, :waiting, :success, :failure
snap.done?    # true if terminal state
snap.result   # main output if any
snap.details  # additional metadata
```

## Implementing Custom Strategies

```elixir
defmodule MyCustomStrategy do
  use Jido.Agent.Strategy

  @impl true
  def cmd(agent, instructions, ctx) do
    # Custom execution logic
    # Must return {updated_agent, directives}
  end

  # Optional callbacks
  @impl true
  def init(agent, ctx), do: {agent, []}

  @impl true
  def tick(agent, ctx), do: {agent, []}

  @impl true
  def snapshot(agent, ctx), do: Jido.Agent.Strategy.default_snapshot(agent)
end
```

Strategy state lives in `agent.state.__strategy__`. Use `Jido.Agent.Strategy.State` helpers for manipulation.

## Signal Routes

Strategies define signal-to-action routing via `signal_routes/1`:

```elixir
@impl true
def signal_routes(_ctx) do
  [
    {"react.user_query", {:strategy_cmd, :react_start}},
    {"ai.llm_result", {:strategy_cmd, :react_llm_result}}
  ]
end
```

This enables strategies to intercept signals and route them to internal handlers.

---

See `Jido.Agent.Strategy` moduledoc for full API details.

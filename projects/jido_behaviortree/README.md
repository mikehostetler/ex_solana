# Jido Behavior Tree

> **EXPERIMENTAL**
>
> This library is experimental and under active development.
> - Public APIs may change without notice, including breaking changes
> - Documentation and features are still evolving
> - Not recommended for critical production systems yet

An Elixir behavior tree implementation designed for Jido agents with integrated action support and AI compatibility.

## Features

- **Complete Behavior Tree Engine** - Full implementation with composite, decorator, and leaf nodes
- **Stateful Execution** - GenServer-based agents with manual and automatic execution modes
- **Blackboard Pattern** - Shared state management between nodes
- **Jido Action Integration** - Execute Jido actions directly within behavior tree nodes
- **AI Tool Compatible** - Convert behavior trees to OpenAI-compatible tool definitions
- **Telemetry Support** - Built-in instrumentation for monitoring and debugging
- **Type Safety** - Full typing with Zoi schemas and @spec annotations

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:jido_behaviortree, "~> 1.0"}
  ]
end
```

## Quick Start

### Building a Tree with Actions

```elixir
alias Jido.BehaviorTree
alias Jido.BehaviorTree.Nodes.{Sequence, Action}

# Define your actions
defmodule MyApp.Actions.ValidateInput do
  use Jido.Action,
    name: "validate_input",
    description: "Validates user input"

  def run(params, _context) do
    if params[:input] && String.length(params[:input]) > 0 do
      {:ok, %{validated: true}}
    else
      {:error, "Input is required"}
    end
  end
end

defmodule MyApp.Actions.ProcessData do
  use Jido.Action,
    name: "process_data",
    description: "Processes validated data"

  def run(params, _context) do
    {:ok, %{processed: String.upcase(params[:input])}}
  end
end

# Build the tree
tree = BehaviorTree.new(
  Sequence.new([
    Action.new(MyApp.Actions.ValidateInput, %{input: "hello"}),
    Action.new(MyApp.Actions.ProcessData, %{input: "hello"})
  ])
)

# Execute
tick = BehaviorTree.tick()
{status, _updated_tree} = BehaviorTree.tick(tree, tick)
# => {:success, %BehaviorTree.Tree{...}}
```

### Agent-based Execution

For stateful execution across multiple ticks:

```elixir
{:ok, agent} = BehaviorTree.start_agent(
  tree: tree,
  blackboard: %{user_id: 123},
  mode: :manual
)

# Execute ticks
status = BehaviorTree.Agent.tick(agent)

# Access blackboard
BehaviorTree.Agent.put(agent, :result, "success")
value = BehaviorTree.Agent.get(agent, :result)

# Switch to auto mode for continuous execution
BehaviorTree.Agent.set_mode(agent, :auto)
```

## Node Types

### Composite Nodes

Control the execution flow of multiple children:

| Node | Behavior |
|------|----------|
| **Sequence** | Executes children in order. Fails if any child fails. |
| **Selector** | Tries children in order until one succeeds. |

### Decorator Nodes

Modify the behavior of a single child:

| Node | Behavior |
|------|----------|
| **Inverter** | Inverts success/failure of child |
| **Succeeder** | Always returns success when child completes |
| **Failer** | Always returns failure when child completes |
| **Repeat** | Repeats child N times |

### Leaf Nodes

Perform actual work:

| Node | Behavior |
|------|----------|
| **Action** | Executes a Jido Action |
| **Wait** | Waits for a specified duration |
| **SetBlackboard** | Sets values in the blackboard |

## The Blackboard

Shared data structure enabling communication between nodes:

```elixir
# Reference blackboard values in actions
action = Action.new(MyApp.Actions.ProcessData, %{
  data: {:from_blackboard, :input_data}
})

# Set values with SetBlackboard node
alias Jido.BehaviorTree.Nodes.SetBlackboard

SetBlackboard.new(:status, :ready)
SetBlackboard.new(%{status: :ready, count: 0})
```

## Node Status

Every node returns one of these statuses:

- `:success` - Node completed successfully
- `:failure` - Node failed to complete
- `:running` - Node is still executing (will be ticked again)

## Telemetry

The library emits telemetry events for monitoring:

- `[:jido_behaviortree, :node, :tick, :start]` - Node tick started
- `[:jido_behaviortree, :node, :tick, :stop]` - Node tick completed
- `[:jido_behaviortree, :agent, :tick, :start]` - Agent tick started
- `[:jido_behaviortree, :agent, :tick, :stop]` - Agent tick completed

## Guides

- [Getting Started](guides/getting-started.md) - Installation and basic usage
- [Node Reference](guides/nodes.md) - Complete node documentation
- [Creating Custom Nodes](guides/custom-nodes.md) - Build your own nodes with Zoi

## Development

```bash
# Run tests
mix test

# Run quality checks
mix quality

# Generate docs
mix docs
```

## Integration with Jido

This package integrates with the broader Jido ecosystem:

- **jido_action** - Execute Jido actions within behavior tree nodes
- **jido** - Main agent framework for autonomous systems
- **jido_signal** - Signal processing and event handling

## License

Apache 2.0 - See [LICENSE.md](LICENSE.md)

---

**Part of the [Jido](https://agentjido.xyz) ecosystem for building autonomous agent systems.**

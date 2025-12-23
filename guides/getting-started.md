# Getting Started

## Installation

Add `jido_behaviortree` to your `mix.exs`:

```elixir
def deps do
  [
    {:jido_behaviortree, "~> 1.0"}
  ]
end
```

## Quick Start

Create a simple behavior tree with a sequence of actions:

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

## Using the Agent

For stateful execution across multiple ticks:

```elixir
{:ok, agent} = BehaviorTree.start_agent(
  tree: tree,
  blackboard: %{user_id: 123},
  mode: :manual
)

status = BehaviorTree.Agent.tick(agent)
```

## Key Concepts

### The Blackboard

The blackboard is a shared data store that nodes can read from and write to:

```elixir
# Access blackboard data in actions
action = Action.new(MyApp.Actions.ProcessData, %{
  data: {:from_blackboard, :input_data}
})

# Set blackboard values with SetBlackboard node
alias Jido.BehaviorTree.Nodes.SetBlackboard

SetBlackboard.new(:status, :ready)
```

### Node Status

Every node returns one of these statuses:

- `:success` - Node completed successfully
- `:failure` - Node failed
- `:running` - Node is still executing (will be ticked again)

### Tick Context

The tick context tracks execution state:

```elixir
tick = BehaviorTree.tick()
# Contains: tree reference, blackboard, open nodes, tick count
```

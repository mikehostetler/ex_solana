# AGENT.md - Jido Behavior Tree Development Guide

## Build/Test/Lint Commands
- `mix test` - Run tests (excludes flaky tests)  
- `mix test path/to/specific_test.exs` - Run a single test file
- `mix test --include flaky` - Run all tests including flaky ones
- `mix quality` or `mix q` - Run full quality check (format, compile, dialyzer, credo)
- `mix format` - Auto-format code
- `mix dialyzer` - Type checking
- `mix credo` - Code analysis
- `mix coveralls` - Test coverage report
- `mix docs` - Generate documentation

## Architecture

This is an Elixir library for **Jido native Behavior Trees** with integrated action support:
- **Jido.BehaviorTree** - Main API for creating and managing behavior trees
- **Jido.BehaviorTree.Status** - Status enumeration (`:success`, `:failure`, `:running`, `{:error, term}`)
- **Jido.BehaviorTree.Blackboard** - Shared state management with get/put/update operations
- **Jido.BehaviorTree.Tick** - Execution context with timestamp and sequence tracking
- **Jido.BehaviorTree.Node** - Behavior protocol for all tree nodes with telemetry support
- **Jido.BehaviorTree.Tree** - Tree management and execution
- **Jido.BehaviorTree.Agent** - GenServer-based stateful execution engine
- **Jido.BehaviorTree.Skill** - AI-compatible skill wrapper for behavior trees

## Key Features

✅ **Core Foundation Complete**
- Full behavior tree execution engine
- Comprehensive test coverage
- Telemetry integration for monitoring and debugging
- Type safety with Zoi schemas and @spec annotations
- Blackboard pattern for shared state between nodes

✅ **Node Types Implemented**
- Composite: Sequence, Selector
- Decorators: Inverter, Succeeder, Failer, Repeat
- Leaf: Action, Wait, SetBlackboard

✅ **Agent & Skill Integration**
- GenServer-based Agent for stateful tree execution
- Manual and automatic execution modes
- AI-compatible Skill wrapper with OpenAI tool format conversion
- Parameter validation and output formatting

## Zoi Schema Pattern

All nodes use Zoi for type-safe struct definitions. Here's the standard pattern:

```elixir
defmodule Jido.BehaviorTree.Nodes.MyNode do
  @moduledoc "Description of the node"

  @schema Zoi.struct(
    __MODULE__,
    %{
      # Required field
      name: Zoi.string(description: "Node name"),
      
      # Optional field
      timeout: Zoi.integer(description: "Timeout in ms") |> Zoi.optional(),
      
      # Field with default
      retries: Zoi.integer(description: "Retry count") |> Zoi.default(3),
      
      # Child node reference
      child: Zoi.any(description: "Child node") |> Zoi.optional(),
      
      # List of children
      children: Zoi.list(Zoi.any(description: "Child node")) |> Zoi.default([])
    },
    coerce: true
  )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema

  @behaviour Jido.BehaviorTree.Node

  @impl true
  def tick(%__MODULE__{} = state, tick) do
    # Node logic here
    {:success, state}
  end

  @impl true
  def halt(%__MODULE__{} = state) do
    state
  end
end
```

### Zoi Type Reference

Common Zoi types used in nodes:

```elixir
# Basic types
Zoi.string()
Zoi.integer()
Zoi.boolean()
Zoi.atom()
Zoi.any()

# With constraints
Zoi.integer() |> Zoi.min(0)
Zoi.string() |> Zoi.min_length(1)

# Modifiers
Zoi.integer() |> Zoi.optional()      # Can be nil
Zoi.integer() |> Zoi.default(0)      # Default value

# Complex types
Zoi.list(Zoi.any())                  # List of items
Zoi.map(%{key: Zoi.string()})        # Typed map
```

## Code Style Guidelines

- Use `@moduledoc` for module documentation following existing patterns
- All structs use Zoi schemas with the pattern above
- TypeSpecs: Use `@type t :: unquote(Zoi.type_spec(@schema))`
- Nodes use `@behaviour Jido.BehaviorTree.Node` and implement `tick/2` and `halt/1` callbacks
- Error handling: Return `{:ok, result}` or `{:error, reason}` tuples consistently
- Module organization: Core types in `lib/jido_behaviortree/`, nodes in `lib/jido_behaviortree/nodes/`
- Testing: Use ExUnit with test support nodes in `test/support/test_nodes.ex`
- Naming: Snake_case for functions/variables, PascalCase for modules

## Testing Patterns

Use the pre-built test nodes for consistent testing:

```elixir
alias Jido.BehaviorTree.Test.Nodes.{SimpleNode, RunningNode, FailureNode, ErrorNode}

# Node that always succeeds
node = SimpleNode.new("test_data")

# Node that runs for N ticks then succeeds  
node = RunningNode.new(3)

# Node that always fails
node = FailureNode.new("test failure")

# Node that throws an error
node = ErrorNode.new("test error")
```

## Telemetry Events

The package emits telemetry events for monitoring:

- `[:jido_behaviortree, :node, :tick, :start]` - Node tick started
- `[:jido_behaviortree, :node, :tick, :stop]` - Node tick completed
- `[:jido_behaviortree, :node, :tick, :exception]` - Node tick threw exception
- `[:jido_behaviortree, :agent, :tick, :start]` - Agent tick started  
- `[:jido_behaviortree, :agent, :tick, :stop]` - Agent tick completed

## Integration with Jido Action

This package integrates with `jido_action` from the same monorepo:
- Action node executes Jido Actions directly
- Blackboard values can be passed as action parameters
- Compatible with Jido's execution and instruction systems
- Follows same code quality standards and testing approaches

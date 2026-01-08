# Research: Create Example - Behavior Tree as Jido Strategy

**Item ID**: 007
**Date**: 2025-01-07
**State**: Researched

---

## Overview

This item involves creating a minimal but realistic example demonstrating a behavior tree implemented as a Jido strategy. The example should showcase:
- How to define a tree with composites, decorators, and leaf tasks
- How the strategy ticks the tree over time
- How side effects are expressed via Jido effects (not direct IO)
- Best practices for behavior tree design
- Test coverage
- Narrative walkthrough explaining structure and control flow
- Integration with the existing Jido dev/test harness

This will serve as the canonical "hello world" for behavior-tree-as-strategy.

---

## Project Dependencies Discovered

### Core Dependencies (from mix.exs analysis)

**jido_behaviortree** (v1.0.0):
- `jido` (path dependency) - Core agent framework with strategy support
- `jido_action` (path dependency) - Action execution framework
- `jido_signal` (path dependency, v1.2.0) - CloudEvents-based signal system
- `telemetry` (~> 1.3) - Standard BEAM telemetry
- `zoi` (~> 0.14) - Schema validation and type safety
- `splode` (~> 0.2) - Error handling

**jido** (main framework):
- Strategy system with `Jido.Agent.Strategy` behavior
- Directive-based effect system (`Jido.Agent.Directive`)
- Agent state management (`Jido.Agent.State`)
- Effects application (`Jido.Agent.Effects`)
- Telemetry integration (`Jido.Telemetry`)

### Existing Example Infrastructure

The codebase already has:
- **Example file**: `projects/jido_behaviortree/examples/bt_agent.exs` - Basic BT agent demo
- **Test support**: `projects/jido_behaviortree/test/support/test_nodes.ex` - Test node implementations
- **Test patterns**: Comprehensive test suite in `test/jido_behaviortree/`

---

## Files Requiring Changes

### New Files to Create

| File | Purpose | 📖 Documentation |
|------|---------|------------------|
| `projects/jido_behaviortree/examples/hello_world.exs` | **PRIMARY**: Canonical "hello world" example with narrative | 📖 [Getting Started Guide](https://hexdocs.pm/jido_behaviortree/getting-started.html) |
| `projects/jido_behaviortree/examples/hello_world/README.md` | Narrative walkthrough explaining tree structure and control flow | 📖 [Example Documentation Pattern](https://github.com/elixir-lang/elixir/tree/main/lib/elixir/examples) |
| `projects/jido_behaviortree/examples/hello_world/actions.exs` | Example actions demonstrating effects and signals | 📖 [Jido.Action Guide](https://hexdocs.pm/jido_action/Jido.Action.html) |
| `projects/jido_behaviortree/examples/hello_world/tree.exs` | Tree definition with composites, decorators, and leaves | 📖 [Node Reference](https://hexdocs.pm/jido_behaviortree/nodes.html) |
| `projects/jido_behaviortree/examples/hello_world/agent.exs` | Agent definition using BehaviorTree strategy | 📖 [Strategy Guide](https://hexdocs.pm/jido/strategies.html) |
| `projects/jido_behaviortree/examples/hello_world_test.exs` | Test coverage for the example | 📖 [Testing Guide](https://hexdocs.pm/jido/testing.html) |
| `projects/jido_behaviortree/examples/hello_world/run.exs` | Executable runner script | N/A (executable) |

### Files to Modify

| File | Change Required | Location |
|------|-----------------|----------|
| `projects/jido_behaviortree/README.md` | Add link to hello_world example in Quick Start | Lines 27-72 |
| `projects/jido_behaviortree/guides/getting-started.md` | Reference hello_world example | Throughout |
| `projects/jido_behaviortree/mix.exs` | Ensure example files are included in package | Line 129 (files list) |

---

## Existing Patterns Found

### 1. Example Script Pattern (from bt_agent.exs)

**Location**: `projects/jido_behaviortree/examples/bt_agent.exs:1-178`

```elixir
#!/usr/bin/env elixir
# Run with: mix run examples/bt_agent.exs

Logger.configure(level: :warning)

# Define actions
defmodule IncrementAction do
  use Jido.Action,
    name: "increment",
    schema: [amount: [type: :integer, default: 1]]

  def run(%{amount: amount}, %{state: state}) do
    current = Map.get(state, :counter, 0)
    {:ok, %{counter: current + amount}}
  end
end

# Define agent with BT strategy
defmodule BTDemoAgent do
  alias Jido.BehaviorTree.Tree
  alias Jido.BehaviorTree.Nodes.{Sequence, Action}

  @tree Tree.new(
          Sequence.new([
            Action.new(IncrementAction, %{amount: 5}),
            Action.new(MultiplyAction, %{factor: 3})
          ])
        )

  use Jido.Agent,
    name: "bt_demo_agent",
    description: "Demonstrates BehaviorTree-based execution",
    strategy: {Jido.Agent.Strategy.BehaviorTree, tree: @tree},
    schema: [
      counter: [type: :integer, default: 0]
    ]
end

# Runner module
defmodule BTRunner do
  def run do
    agent = BTDemoAgent.new()
    {agent, _directives} = BTDemoAgent.cmd(agent, :tick)
    # Print results...
  end
end

BTRunner.run()
```

**Key Features**:
- Shebang for executable scripts
- Logger configuration
- Action definitions with Jido.Action
- Agent definition with BT strategy
- Tree definition as module attribute
- Runner module for execution
- State printing helpers

### 2. Test Pattern (from agent_test.exs)

**Location**: `projects/jido_behaviortree/test/jido_behaviortree/agent_test.exs:1-100`

```elixir
defmodule Jido.BehaviorTree.AgentTest do
  use ExUnit.Case, async: true

  alias Jido.BehaviorTree.{Agent, Tree, Blackboard}
  alias Jido.BehaviorTree.Test.Nodes.SimpleNode

  describe "Agent.start_link/1" do
    test "starts agent with simple tree" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      {:ok, agent} = Agent.start_link(tree: tree)

      assert is_pid(agent)
      assert Process.alive?(agent)

      GenServer.stop(agent)
    end
  end

  describe "Agent.tick/1" do
    test "executes tree tick and returns status" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      {:ok, agent} = Agent.start_link(tree: tree)

      status = Agent.tick(agent)
      assert status == :success

      GenServer.stop(agent)
    end
  end
end
```

**Key Features**:
- Async tests for isolation
- Describe blocks for organization
- Setup/teardown with GenServer.start_link/stop
- Assertions on status and state
- Use of test nodes from support module

### 3. BehaviorTree Strategy Integration Pattern

**Location**: `projects/jido_behaviortree/lib/jido_behaviortree/strategy/behavior_tree.ex:14-41`

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "bt_agent",
    strategy: {Jido.Agent.Strategy.BehaviorTree,
      tree: my_tree(),
      blackboard: %{initial: "data"}
    }
end

# Strategy options:
- :tree - A Jido.BehaviorTree.Tree.t() (required)
- :blackboard - Initial blackboard data (default: %{})
- :reset_on_completion - Reset tree when :success/:failure (default: false)
```

**Key Features**:
- Tree stored in strategy state
- Blackboard for shared node state
- One tick per cmd/3 call
- Snapshot interface for status inspection

### 4. Node Definition Pattern (from sequence.ex)

**Location**: `projects/jido_behaviortree/lib/jido_behaviortree/nodes/sequence.ex:1-134`

```elixir
defmodule Jido.BehaviorTree.Nodes.Sequence do
  @moduledoc """
  A composite node that executes children in sequence.
  """

  @schema Zoi.struct(
    __MODULE__,
    %{
      children: Zoi.list(Zoi.any()),
      current_index: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0)
    },
    coerce: true
  )

  @type t :: unquote(Zoi.type_spec(@schema))
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema

  @behaviour Jido.BehaviorTree.Node

  def new(children) when is_list(children) do
    %__MODULE__{children: children, current_index: 0}
  end

  def tick(state, tick) do
    # Execution logic...
  end

  def halt(state) do
    # Cleanup logic...
  end
end
```

**Key Features**:
- Zoi schema for validation
- Node behavior implementation
- new/1 constructor
- tick/2 for execution
- halt/1 for cleanup

### 5. Action Node with Effects Pattern

**Location**: `projects/jido_behaviortree/lib/jido_behaviortree/nodes/action.ex:107-185`

```elixir
def tick_with_context(
      %__MODULE__{action_module: action_module, params: params} = state,
      tick
    ) do
  resolved_params = resolve_params(params, tick)
  agent = tick.agent

  instruction = %Jido.Instruction{
    action: action_module,
    params: resolved_params,
    context: %{state: agent.state}
  }

  case Jido.Exec.run(instruction) do
    {:ok, result} ->
      # Apply effects to agent state
      updated_agent = Jido.Agent.Effects.apply_result(agent, result)

      tick =
        tick
        |> Tick.update_agent(updated_agent)
        |> Tick.put(:last_result, result)

      {:success, %{state | result: result}, tick}

    {:ok, result, effects} ->
      # Apply effects and accumulate directives
      updated_agent = Jido.Agent.Effects.apply_result(agent, result)
      {final_agent, directives} = Jido.Agent.Effects.apply_effects(updated_agent, effects)

      tick =
        tick
        |> Tick.update_agent(final_agent)
        |> Tick.append_directives(directives)
        |> Tick.put(:last_result, result)

      {:success, %{state | result: result}, tick}

    {:error, reason} ->
      tick = Tick.put(tick, :error, reason)
      {:failure, state, tick}
  end
end
```

**Key Features**:
- Resolve params from blackboard
- Build Jido.Instruction
- Execute via Jido.Exec.run/1
- Apply effects to agent state
- Accumulate directives on tick
- Update blackboard with results

---

## Integration Points

### 1. Jido Agent Strategy System

**Location**: `projects/jido/lib/jido/agent/strategy.ex`

The BehaviorTree strategy implements the `Jido.Agent.Strategy` behavior:
- `init/2` - Initialize strategy state
- `cmd/3` - Execute one tick
- `snapshot/2` - Get strategy status

**Integration flow**:
1. Agent initialized with BehaviorTree strategy
2. Strategy stores tree and blackboard in `agent.state.__strategy__`
3. Each cmd/3 call executes one tree tick
4. Directives accumulated during tick are returned to AgentServer
5. AgentServer executes directives (emit signals, spawn processes, etc.)

### 2. Effects System Integration

**Location**: `projects/jido/lib/jido/agent/effects.ex`

Behavior trees integrate with Jido effects via:
- **Internal Effects**: State mutations (SetState, ReplaceState, etc.)
- **Directives**: External effects (Emit, Error, Spawn, etc.)

**Pattern**:
```elixir
# Action returns effects
{:ok, result, [Directive.emit(signal), Directive.log("Done")]}

# Effects applied via Jido.Agent.Effects
{updated_agent, directives} = Jido.Agent.Effects.apply_effects(agent, effects)
```

### 3. Signal Integration (from items 005-006)

Behavior trees will emit signals via Directive.Emit:
- `jido.bt.node.entered` - Node tick started
- `jido.bt.node.completed` - Node tick completed
- `jido.bt.tree.started` - Tree tick started
- `jido.bt.tree.completed` - Tree tick completed

**Integration**:
```elixir
# In strategy or node
signal = NodeCompleted.new(%{
  node_id: "node-123",
  status: :success,
  timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
})

directives = [Directive.emit(signal)]
```

### 4. Telemetry Integration

**Location**: `projects/jido_behaviortree/lib/jido_behaviortree/telemetry.ex:23-121`

Existing telemetry events:
- `[:jido, :bt, :node, :tick, :start]` - Node tick started
- `[:jido, :bt, :node, :tick, :stop]` - Node tick completed
- `[:jido, :bt, :node, :tick, :exception]` - Node tick error

**Integration**:
- Wrapped in `Jido.Observe.start_span/2` for distributed tracing
- Metadata includes agent_id, node_module, tick_sequence
- Automatically emitted during tree execution

---

## Example Design Recommendations

### Example Requirements

Based on the item overview, the example should demonstrate:

1. **Tree Structure** - Composites, decorators, and leaves
2. **Ticking Over Time** - Multiple tick execution with state preservation
3. **Effects via Jido** - No direct IO, all effects through directive system
4. **Best Practices** - Clear structure, good naming, proper error handling
5. **Test Coverage** - Comprehensive tests
6. **Narrative Walkthrough** - Clear explanation of structure and control flow
7. **Dev/Test Harness Integration** - Runnable via mix run

### Recommended Example Scenario

**"Smart Coffee Maker"** - A realistic autonomous system example

**Scenario**: A coffee maker that:
1. Checks if water tank is empty
2. Checks if beans are available
3. Heats water to temperature
4. Grinds beans
5. Brews coffee
6. Notifies user when ready
7. Handles errors (no water, no beans, overheating)

**Why this scenario**:
- **Realistic**: Actual IoT/automation use case
- **Compositional**: Demonstrates Sequence, Selector, decorators
- **Stateful**: Shows multi-tick execution with state
- **Effectful**: Signals, logging, state mutations
- **Error handling**: Shows failure recovery
- **Observable**: Signals and telemetry for monitoring

### Tree Structure

```
Sequence (Make Coffee)
├─ Selector (Check Resources)
│  ├─ Sequence (Check Water)
│  │  ├─ Action (Check Water Level)
│  │  └─ Inverter (Action (Refill Water))
│  └─ Sequence (Check Beans)
│     ├─ Action (Check Bean Level)
│     └─ Inverter (Action (Refill Beans))
├─ Sequence (Brew)
│  ├─ Action (Heat Water)
│  ├─ Repeat (Action (Grind Beans), times: 3)
│  ├─ Action (Brew Coffee)
│  └─ Action (Notify User)
└─ Failer (Action (Log Error))
```

**Node Types Demonstrated**:
- **Sequence**: Execute steps in order
- **Selector**: Try alternatives until one succeeds
- **Action**: Execute Jido actions
- **Inverter**: Negate child result
- **Repeat**: Repeat child N times
- **Failer**: Always fail (error handling)

### Actions with Effects

```elixir
defmodule CheckWaterLevel do
  use Jido.Action,
    name: "check_water_level",
    schema: []

  def run(_params, %{state: state}) do
    level = Map.get(state, :water_level, 0)

    if level > 0 do
      {:ok, %{has_water: true},
       [Directive.emit(WaterLevelChecked.new!(%{level: level}))]}
    else
      {:error, :no_water,
       [Directive.emit(WaterEmpty.new!(%{}))]}
    end
  end
end

defmodule HeatWater do
  use Jido.Action,
    name: "heat_water",
    schema: [target_temp: [type: :integer, default: 90]]

  def run(%{target_temp: target}, %{state: state}) do
    current = Map.get(state, :water_temp, 20)

    if current >= target do
      {:ok, %{water_temp: target},
       [Directive.emit(WaterHeated.new!(%{temp: target}))]}
    else
      # Continue heating next tick
      {:ok, %{water_temp: current + 10},
       [Directive.emit(Heating.new!(%{temp: current + 10})),
        Directive.log("Heating water to #{target}°C")]}
    end
  end
end

defmodule NotifyUser do
  use Jido.Action,
    name: "notify_user",
    schema: [message: [type: :string, required: true]]

  def run(%{message: msg}, _context) do
    {:ok, %{notification_sent: true},
     [Directive.emit(UserNotified.new!(%{message: msg})),
      Directive.log("Notification: #{msg}")]}
  end
end
```

### Agent Definition

```elixir
defmodule CoffeeMakerAgent do
  @moduledoc """
  Smart coffee maker using BehaviorTree strategy.

  Demonstrates:
  - Resource checking with Selector fallback
  - Multi-tick execution with state
  - Effects via directives (signals, logs)
  - Error handling with decorators
  """

  alias Jido.BehaviorTree.Tree
  alias Jido.BehaviorTree.Nodes.{Sequence, Selector, Action, Inverter, Repeat, Failer}

  @tree Tree.new(
          Sequence.new([
            # Resource checking with fallback
            Selector.new([
              # Check and refill water if needed
              Sequence.new([
                Action.new(CheckWaterLevel, []),
                Inverter.new(Action.new(RefillWater, []))
              ]),
              # Check and refill beans if needed
              Sequence.new([
                Action.new(CheckBeanLevel, []),
                Inverter.new(Action.new(RefillBeans, []))
              ])
            ]),
            # Brew coffee
            Sequence.new([
              Action.new(HeatWater, [target_temp: 90]),
              Repeat.new(Action.new(GrindBeans, []), times: 3),
              Action.new(BrewCoffee, []),
              Action.new(NotifyUser, [message: "Coffee is ready!"])
            ])
          ])
        )

  use Jido.Agent,
    name: "coffee_maker",
    description: "Smart coffee maker with behavior tree control",
    strategy: {Jido.Agent.Strategy.BehaviorTree,
      tree: @tree,
      blackboard: %{water_level: 5, bean_level: 3, water_temp: 20}
    },
    schema: [
      water_level: [type: :integer, default: 0],
      bean_level: [type: :integer, default: 0],
      water_temp: [type: :integer, default: 20],
      notification_sent: [type: :boolean, default: false]
    ]
end
```

### Test Coverage

```elixir
defmodule HelloWorldTest do
  use ExUnit.Case, async: true

  alias Jido.BehaviorTree.Tree
  alias Jido.BehaviorTree.Nodes.{Sequence, Action}

  describe "Coffee Maker Behavior Tree" do
    test "completes full brew cycle" do
      agent = CoffeeMakerAgent.new()

      # Initial state
      assert agent.state.water_level == 5
      assert agent.state.bean_level == 3

      # Run tree to completion
      {agent, _directives} = CoffeeMakerAgent.cmd(agent, :tick)

      # Verify state changes
      assert agent.state.notification_sent == true
      assert agent.state.water_temp == 90

      # Check strategy snapshot
      snapshot = Jido.Agent.Strategy.BehaviorTree.snapshot(agent, %{})
      assert snapshot.status == :success
      assert snapshot.done? == true
    end

    test "handles no water scenario" do
      agent = CoffeeMakerAgent.new(%{water_level: 0})

      # First tick should detect no water
      {agent, directives} = CoffeeMakerAgent.cmd(agent, :tick)

      # Should have emitted water empty signal
      assert Enum.any?(directives, fn
        %Directive.Emit{signal: %WaterEmpty{}} -> true
        _ -> false
      end)

      # Second tick should refill and continue
      {agent, _directives} = CoffeeMakerAgent.cmd(agent, :tick)
      assert agent.state.water_level > 0
    end

    test "multi-tick execution with state preservation" do
      agent = CoffeeMakerAgent.new()

      # Tick 1: Check resources
      {agent, _} = CoffeeMakerAgent.cmd(agent, :tick)
      snapshot = Jido.Agent.Strategy.BehaviorTree.snapshot(agent, %{})
      assert snapshot.status in [:running, :success]

      # Tick 2: Continue execution
      {agent, _} = CoffeeMakerAgent.cmd(agent, :tick)

      # State preserved across ticks
      assert agent.state.water_level != nil
    end
  end
end
```

---

## Test Impact & Patterns

### Tests Requiring Updates

| File | Purpose |
|------|---------|
| `projects/jido_behaviortree/examples/hello_world_test.exs` | **NEW**: Comprehensive test coverage for example |
| `projects/jido_behaviortree/test/jido_behaviortree/strategy_test.exs` | **NEW**: Strategy integration tests (if not exists) |

### Testing Pattern (from existing tests)

**Async Tests with ExUnit**:
```elixir
defmodule HelloWorldExampleTest do
  use ExUnit.Case, async: true

  describe "Hello World Example" do
    test "runs complete tree" do
      # Setup
      agent = CoffeeMakerAgent.new()

      # Execute
      {agent, directives} = CoffeeMakerAgent.cmd(agent, :tick)

      # Assert
      assert agent.state.notification_sent == true
    end
  end
end
```

**Signal Assertion Pattern**:
```elixir
test "emits expected signals" do
  {agent, directives} = CoffeeMakerAgent.cmd(agent, :tick)

  assert Enum.any?(directives, fn
    %Directive.Emit{signal: %WaterHeated{}} -> true
    _ -> false
  end)
end
```

**Multi-Tick Testing**:
```elixir
test "executes across multiple ticks" do
  agent = CoffeeMakerAgent.new()

  # Run until complete
  {final_agent, _directives} =
    Stream.repeatedly(fn ->
      {agent, dirs} = CoffeeMakerAgent.cmd(agent, :tick)
      {agent, dirs}
    end)
    |> Enum.find(fn {agent, _} ->
      snapshot = Jido.Agent.Strategy.BehaviorTree.snapshot(agent, %{})
      snapshot.done?
    end)

  assert final_agent.state.notification_sent == true
end
```

---

## Configuration & Environment

### Config Files

No configuration changes required. Example runs standalone via `mix run`.

### Environment Variables

None required. Example uses hardcoded values for simplicity.

---

## Documentation Structure

### README.md (narrative walkthrough)

```markdown
# Hello World: Behavior Tree as Jido Strategy

## Overview

This example demonstrates how to implement a behavior tree as a Jido agent strategy.
It shows a smart coffee maker that autonomously brews coffee while handling resource
constraints and errors.

## What You'll Learn

- How to structure behavior trees with composites, decorators, and leaves
- How the BehaviorTree strategy ticks the tree over time
- How to express side effects via Jido effects (not direct IO)
- Best practices for behavior tree design
- How to test behavior tree agents

## Tree Structure

The coffee maker uses a behavior tree with these components:

[Diagram]

### Root: Sequence (Make Coffee)

1. **Selector (Check Resources)** - Tries alternatives until one succeeds
   - Check and refill water if needed
   - Check and refill beans if needed

2. **Sequence (Brew)** - Executes steps in order
   - Heat water to 90°C
   - Grind beans (repeat 3x)
   - Brew coffee
   - Notify user

## Control Flow

1. Agent starts with initial state
2. Each cmd/3 call executes one tree tick
3. Nodes return :success, :failure, or :running
4. State preserved across ticks
5. Effects emitted as directives
6. Tree completes when root returns :success or :failure

## Running the Example

\`\`\`bash
# Run the example
mix run examples/hello_world/run.exs

# Run tests
mix test examples/hello_world_test.exs
\`\`\`

## Expected Output

\`\`\`
Starting Coffee Maker...
Tick 1: Checking resources...
  - Water level: 5 (OK)
  - Bean level: 3 (OK)
Tick 2: Heating water...
  - Temperature: 30°C
Tick 3: Heating water...
  - Temperature: 60°C
Tick 4: Heating water...
  - Temperature: 90°C
Tick 5: Grinding beans...
  - Grind 1/3
Tick 6: Grinding beans...
  - Grind 2/3
Tick 7: Grinding beans...
  - Grind 3/3
Tick 8: Brewing coffee...
  - Brewing...
Tick 9: Notifying user...
  - Notification sent!
Tree completed with status: :success
\`\`\`

## Key Concepts

### Effects vs Direct IO

**WRONG**: Direct IO in actions
\`\`\`elixir
def run(_params, _context) do
  IO.puts("Brewing coffee...")  # Don't do this!
  {:ok, %{}}
end
\`\`\`

**CORRECT**: Effects via directives
\`\`\`elixir
def run(_params, _context) do
  {:ok, %{brewing: true},
   [Directive.log("Brewing coffee..."),
    Directive.emit(BrewingStarted.new!(%{}))]}
end
\`\`\`

### State Preservation

Agent state is preserved across ticks:
\`\`\`elixir
# Tick 1
agent = CoffeeMakerAgent.new()
{agent, _} = CoffeeMakerAgent.cmd(agent, :tick)
# agent.state.water_temp = 30

# Tick 2
{agent, _} = CoffeeMakerAgent.cmd(agent, :tick)
# agent.state.water_temp = 60 (preserved from tick 1)
\`\`\`

### Error Handling

Behavior trees handle errors via structure:
\`\`\`elixir
Selector.new([
  Sequence.new([
    Action.new(CheckWater, []),
    Inverter.new(Action.new(RefillWater, []))  # Fails if water is OK
  ]),
  Action.new(UseAlternative, [])  # Tried if first fails
])
\`\`\`

## Testing

See `hello_world_test.exs` for comprehensive tests.

Run tests:
\`\`\`bash
mix test examples/hello_world_test.exs
\`\`\`

## Next Steps

- Modify the tree structure
- Add new actions with effects
- Experiment with decorators
- Add signal subscribers
- Integrate with other Jido capabilities
\`\`\`

---

## Risk Assessment

### Breaking Changes

**Severity**: NONE

- Example is additive, no existing code changes
- Documentation updates only
- No API changes

### Performance Implications

**Severity**: NONE

- Example runs in isolation
- No performance impact on existing code
- Demonstrates best practices for efficiency

### Security Considerations

**Severity**: LOW

- Example uses hardcoded values (no secrets)
- Signals may expose state (document as internal)
- No external API calls

### Migration Complexity

**Severity**: NONE

- New files only
- No migration required
- Documentation updates only

---

## Key Implementation Considerations

### 1. Minimal but Realistic

**Balance**: Small enough to read, rich enough to illustrate concepts

**Approach**:
- 5-7 actions (not 20, not 2)
- 2-3 composites (Sequence, Selector)
- 2-3 decorators (Inverter, Repeat)
- Clear domain (coffee maker, not "foo/bar")

### 2. Effects Demonstration

**Show all effect types**:
- State mutations (Internal.SetState)
- Signal emission (Directive.Emit)
- Logging (Directive.log)
- Error handling (Directive.Error)

**Pattern**:
```elixir
def run(params, context) do
  case do_work(params) do
    {:ok, result} ->
      {:ok, result, [
        Directive.emit(WorkCompleted.new!(result)),
        Directive.log("Work completed successfully")
      ]}

    {:error, reason} ->
      {:error, reason, [
        Directive.emit(WorkFailed.new!(reason)),
        Directive.log("Work failed: #{reason}")
      ]}
  end
end
```

### 3. Multi-Tick Demonstration

**Show state preservation**:
- Action returns :running for multi-step work
- State updated across ticks
- Tree resumes from correct node

**Example**: Heating water over multiple ticks
```elixir
def run(%{target_temp: target}, %{state: state}) do
  current = Map.get(state, :water_temp, 20)

  if current >= target do
    {:ok, %{water_temp: target}}  # Done
  else
    {:ok, %{water_temp: current + 10},
     [Directive.log("Heating: #{current + 10}°C")]}
    # Will be ticked again
  end
end
```

### 4. Error Handling Demonstration

**Show graceful failure**:
- Selector tries alternatives
- Inverter negates failure
- Failer demonstrates error handling

**Pattern**:
```elixir
Selector.new([
  Sequence.new([
    Action.new(TryPrimary, []),
    Inverter.new(Action.new(Fallback, []))  # Only if primary fails
  ]),
  Action.new(TrySecondary, [])  # If sequence fails
])
```

### 5. Testability

**Make it testable**:
- Pure actions (no side effects)
- Explicit state transitions
- Clear success/failure conditions
- Signal emission for verification

**Pattern**:
```elixir
test "completes successfully" do
  agent = CoffeeMakerAgent.new()
  {agent, directives} = CoffeeMakerAgent.cmd(agent, :tick)

  # Assert state
  assert agent.state.notification_sent == true

  # Assert signals
  assert Enum.any?(directives, fn
    %Directive.Emit{signal: %CoffeeReady{}} -> true
    _ -> false
  end)
end
```

### 6. Runnable Demo

**Make it easy to run**:
- Single script: `mix run examples/hello_world/run.exs`
- Clear output with timestamps
- Progress indicators
- Final summary

**Pattern**:
```elixir
defmodule Runner do
  def run do
    IO.puts("\n=== Coffee Maker Demo ===\n")

    agent = CoffeeMakerAgent.new()
    run_ticks(agent, 0)
  end

  defp run_ticks(agent, tick_count) do
    {agent, directives} = CoffeeMakerAgent.cmd(agent, :tick)

    snapshot = Jido.Agent.Strategy.BehaviorTree.snapshot(agent, %{})
    IO.puts("Tick #{tick_count + 1}: #{snapshot.status}")

    if snapshot.done? do
      IO.puts("\n=== Complete ===\n")
    else
      run_ticks(agent, tick_count + 1)
    end
  end
end

Runner.run()
```

---

## Documentation References

| File | Description |
|------|-------------|
| `projects/jido_behaviortree/README.md` | Behavior tree overview |
| `projects/jido_behaviortree/guides/getting-started.md` | Getting started guide |
| `projects/jido_behaviortree/guides/nodes.md` | Node reference |
| `projects/jido_behaviortree/guides/custom-nodes.md` | Custom node creation |
| `projects/jido/guides/strategies.md` | Strategy system guide |
| `projects/jido/guides/directives.md` | Directive system guide |
| `projects/jido/guides/testing.md` | Testing patterns |
| `projects/jido_behaviortree/examples/bt_agent.exs` | Existing example (reference) |

---

## Files Identified: 8

### New Files (7)
- `projects/jido_behaviortree/examples/hello_world.exs` (main example)
- `projects/jido_behaviortree/examples/hello_world/README.md` (narrative)
- `projects/jido_behaviortree/examples/hello_world/actions.exs` (actions)
- `projects/jido_behaviortree/examples/hello_world/tree.exs` (tree)
- `projects/jido_behaviortree/examples/hello_world/agent.exs` (agent)
- `projects/jido_behaviortree/examples/hello_world/run.exs` (runner)
- `projects/jido_behaviortree/examples/hello_world_test.exs` (tests)

### Modified Files (1)
- `projects/jido_behaviortree/README.md` (add link to example)

---

## Summary

This task requires creating a comprehensive "hello world" example demonstrating behavior trees as Jido strategies. The example should:

1. **Demonstrate tree structure**: Sequence, Selector, decorators (Inverter, Repeat), actions
2. **Show multi-tick execution**: State preservation across ticks, running status
3. **Illustrate effects**: Signal emission, logging, state mutations via directives
4. **Follow best practices**: No direct IO, pure actions, clear structure
5. **Include tests**: Comprehensive test coverage with assertions on state and signals
6. **Provide narrative**: Clear walkthrough explaining structure, control flow, and key concepts
7. **Be runnable**: Single script execution via `mix run`

The "smart coffee maker" scenario is recommended as it's realistic, demonstrates all node types, shows stateful execution, handles errors gracefully, and emits signals for observability. The example should be small enough to read easily (~200 lines) but rich enough to illustrate best practices (~5-7 actions, ~10 nodes total).

Implementation involves creating 7 new files (example + tests + documentation) and updating 1 existing file (README). No breaking changes, no migration required, and full backward compatibility.

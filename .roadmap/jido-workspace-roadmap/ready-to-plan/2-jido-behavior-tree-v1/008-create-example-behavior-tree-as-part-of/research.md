# Research: Behavior Tree as Part of Larger Strategy

## Item Overview

**ID**: 008-create-example-behavior-tree-as-part-of
**Goal**: Create an example showing a behavior tree composed within a larger Jido strategy orchestration

## Key Findings

### 1. Existing Behavior Tree Implementation

**Location**: `projects/jido_behaviortree/`

**Key Modules**:
- **Strategy**: `lib/jido_behaviortree/strategy/behavior_tree.ex` - Implements Jido strategy behavior pattern
- **Core Tree**: `lib/jido_behaviortree/tree.ex` - Tree execution engine
- **Node Behavior**: `lib/jido_behaviortree/node.ex` - Node execution protocols
- **Test Nodes**: `test/support/test_nodes.ex` - Example node implementations

**Available Node Types**:
- **Composite**: Sequence, Selector, Parallel
- **Decorator**: Inverter, Succeeder, Failer, Repeat
- **Leaf**: Action, Wait, Condition, SetBlackboard

### 2. Jido Strategy Interface

The behavior tree implements the standard Jido strategy protocol:

```elixir
@impl true
def init(agent, ctx)          # Initialize strategy state
@impl true
def cmd(agent, instructions, ctx)  # Process commands, return directives
@impl true
def snapshot(agent, ctx)       # Return current status
```

State management uses `agent.state.__strategy__.` with Zoi schemas for type safety.

### 3. Integration Points

**Signals System** (`projects/jido_signal/`):
- Implements CloudEvents v1.0.2 specification
- Used for strategy transitions, error handling, coordination
- Pattern: Signals trigger higher-level strategy state changes

**Blackboard Pattern**:
- Shared state between nodes and strategies
- Key-value storage with type-safe access
- Persistent across execution ticks
- Used for cross-strategy data sharing

**Tick Context**: Threads agent state, directives, and execution context through tree execution

### 4. Related Planning Mechanisms

**HTN**: `projects/jido_htn/` - Hierarchical Task Network planner (currently has mostly commented core, needs modernization per roadmap items 009-014)

**Rule-Based Logic**: Can be implemented using:
- Condition nodes in behavior trees
- Signal-based rules in meta-strategy
- Direct pattern matching in strategy cmd/2

**Direct Actions**: Already supported via Action nodes

### 5. Suggested Example Structure

**Location**: `projects/jido_behaviortree/examples/composite_strategy_example/`

```
examples/composite_strategy_example/
├── README.md                           # Documentation
├── example_agent.ex                    # Example agent setup
├── behavior_tree_component.ex          # Reactive decision tree
├── rule_based_component.ex             # Constraint logic
├── htn_component.ex                    # Planning decomposition
├── meta_strategy.ex                    # Coordination layer
└── test/
    ├── integration_test.exs            # Full workflow tests
    └── component_test.exs              # Individual component tests
```

### 6. Implementation Patterns to Demonstrate

**Meta-Strategy Framework**:
```elixir
defmodule CompositeStrategy do
  use Jido.Strategy

  # Delegates to behavior tree, HTN, or rules based on context
  def cmd(agent, instructions, ctx) do
    case agent.state.phase do
      :reactive -> delegate_to_behavior_tree(agent, ctx)
      :planning -> delegate_to_htn(agent, ctx)
      :validation -> apply_rules(agent, ctx)
    end
  end
end
```

**Signal-Based Coordination**:
- Behavior tree emits signals on state changes
- Meta-strategy listens and transitions phases
- Error signals propagate to error handler

**Blackboard Sharing**:
```elixir
# Behavior tree writes results
%JidoBehaviortree.Node.Action{action: fn ctx ->
  put_blackboard(ctx, :target_acquired, true)
end}

# HTN reads and uses the data
# Rule-based component validates constraints
```

**Error Propagation**:
- Unified error handling across all strategies
- Signals of type `error.jido.behavior_tree`
- Meta-strategy can recover or fail gracefully

### 7. Example Scenario

A realistic composite strategy could be:
1. **Behavior Tree**: Handles reactive decisions (avoid obstacles, respond to threats)
2. **HTN**: Plans complex multi-step sequences (navigate to location, gather resources)
3. **Rule-Based**: Enforces constraints (don't enter dangerous areas, respect resource limits)
4. **Meta-Strategy**: Coordinates phases based on signals and blackboard state

### 8. Key Integration Points to Document

1. **Delegation Boundaries**: When and how meta-strategy delegates to components
2. **State Sharing**: Blackboard schema and access patterns
3. **Signal Coordination**: Signal types, propagation, and correlation IDs
4. **Error Handling**: Cross-strategy error propagation and recovery
5. **Composability**: How to make reusable strategy components

### 9. Dependencies on Other Roadmap Items

- **Item 005**: Define effects for behavior tree execution (needs this for clean integration)
- **Item 006**: Define signals for state transitions (critical for coordination)
- **Items 009-014**: HTN modernization (HTN component needs updated patterns)
- **Item 007**: Single behavior tree example (should be completed first)

### 10. Testing Strategy

Tests should cover:
- Meta-strategy phase transitions based on signals
- Blackboard data consistency across components
- Error propagation from any component
- Signal correlation and timing
- Full workflow scenarios

## Next Steps

1. Complete items 005, 006, 007 first (prerequisites)
2. Design the composite strategy schema (blackboard structure)
3. Define signal types for coordination
4. Implement individual components incrementally
5. Write integration tests demonstrating coordination
6. Document patterns for reuse in other projects

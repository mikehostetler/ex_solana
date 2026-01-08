# Research: Define Signals for Behavior Tree State Transitions/Events

**Item ID**: 006
**Date**: 2025-01-07
**State**: Researched

---

## Overview

This item involves designing a focused set of Jido signals that represent behavior tree lifecycle events and state transitions. The Jido ecosystem already has a robust signal system based on CloudEvents v1.0.2 (`jido_signal`), a directive-based effect system (`jido`), and existing telemetry for behavior trees. The task is to define signal schemas that align with Jido conventions, cover all behavior tree lifecycle events, integrate cleanly with effects, and distinguish between internal debugging events and public consumption signals.

---

## Project Dependencies Discovered

### Core Dependencies (from mix.exs analysis)

**jido_behaviortree** (v1.0.0):
- `jido` (path dependency) - Core agent framework
- `jido_action` (path dependency) - Action execution
- `jido_signal` (path dependency, v1.2.0) - CloudEvents-based signal system
- `telemetry` (~> 1.3) - Standard BEAM telemetry
- `zoi` (~> 0.14) - Schema validation and type safety

**jido_signal** (v1.2.0):
- `jason` (~> 1.4) - JSON serialization
- `phoenix_pubsub` (~> 2.1) - PubSub transport
- `telemetry` (~> 1.3) - Telemetry events
- `telemetry_metrics` (~> 1.1) - Metrics formatting
- `zoi` (~> 0.10) - Schema validation

### Existing Event Patterns

The project uses **three complementary event systems**:

1. **Telemetry Events** - Low-level execution tracing
   - Already implemented for behavior trees
   - Namespace: `[:jido, :bt, ...]`
   - Used for metrics, debugging, observability

2. **Jido Signals** - CloudEvents-based domain events
   - Structured, routable, serializable
   - Namespace: `"jido.bt.*"`
   - For cross-agent communication and external consumers

3. **Directives** - Effect descriptions for agent runtime
   - Emitted during execution, handled by AgentServer
   - Including `Directive.Emit` for dispatching signals

---

## Files Requiring Changes

### New Files to Create

| File | Purpose | 📖 Documentation |
|------|---------|------------------|
| `projects/jido_behaviortree/lib/jido_behaviortree/signals.ex` | Signal module definitions using `use Jido.Signal` | 📖 [Signal custom types](https://hexdocs.pm/jido_signal/Jido.Signal.html#module-custom-signal-types) |
| `projects/jido_behaviortree/lib/jido_behaviortree/signals/node.ex` | Node lifecycle signals (enter/exit, status changes) | 📖 [CloudEvents spec](https://cloudevents.io/) |
| `projects/jido_behaviortree/lib/jido_behaviortree/signals/tree.ex` | Tree lifecycle signals (start/stop, completion) | 📖 [jido_signal guides](https://hexdocs.pm/jido_signal/signals-and-dispatch.html) |
| `projects/jido_behaviortree/lib/jido_behaviortree/signals/blackboard.ex` | Blackboard change signals | 📖 [Signal type naming](https://hexdocs.pm/jido_signal/Jido.Signal.html#module-signal-types) |
| `projects/jido_behaviortree/test/jido_behaviortree/signals_test.exs` | Signal validation and serialization tests | 📖 [ExUnit docs](https://hexdocs.pm/ex_unit/) |

### Files to Modify

| File | Change Required | Location |
|------|-----------------|----------|
| `projects/jido_behaviortree/lib/jido_behaviortree/node.ex` | Add signal emission to `execute_tick/2` and `execute_halt/1` | Lines 175-194, 248-268 |
| `projects/jido_behaviortree/lib/jido_behaviortree/tree.ex` | Add signal emission to `tick/2`, `tick_with_context/2`, `halt/1` | Lines 79-107, 152-156 |
| `projects/jido_behaviortree/lib/jido_behaviortree/strategy/behavior_tree.ex` | Emit tree lifecycle signals via directives | Lines 119-176 |
| `projects/jido_behaviortree/lib/jido_behaviortree/nodes/sequence.ex` | Emit node enter/exit signals | Composite node execution |
| `projects/jido_behaviortree/lib/jido_behaviortree/nodes/selector.ex` | Emit node enter/exit signals | Composite node execution |
| `projects/jido_behaviortree/lib/jido_behaviortree/nodes/action.ex` | Emit action-specific signals | Lines 81-120 |
| `projects/jido_behaviortree/lib/jido_behaviortree/blackboard.ex` | Emit blackboard change signals | Read/write operations |
| `projects/jido_behaviortree/lib/jido_behaviortree/agent.ex` | Emit agent lifecycle signals | Lines 296-332 |
| `projects/jido_behaviortree/mix.exs` | Update documentation groups | Lines 89-123 |

---

## Existing Patterns Found

### 1. Signal Definition Pattern (from jido_signal)

**Location**: `projects/jido_signal/lib/jido_signal.ex:68-93`

```elixir
defmodule MySignal do
  use Jido.Signal,
    type: "my.custom.signal",
    default_source: "/my/service",
    datacontenttype: "application/json",
    schema: [
      user_id: [type: :string, required: true],
      message: [type: :string, required: true]
    ]

  # Creates validated signal instances
  {:ok, signal} = MySignal.new(%{user_id: "123", message: "Hello"})
end
```

**Key Features**:
- `use Jido.Signal` macro with configuration
- NimbleOptions schema for data validation
- Automatic `new/1`, `new!/1`, `validate_data/1` generation
- Default source and type specification

### 2. Directive.Emit Pattern (from jido)

**Location**: `projects/jido/lib/jido/agent/directive.ex:37-40, 386-395`

```elixir
# Emit a signal
%Directive.Emit{signal: my_signal}

# With dispatch config
%Directive.Emit{signal: my_signal, dispatch: {:pubsub, topic: "events"}}

# Helper constructors
Directive.emit(signal)
Directive.emit(signal, {:pubsub, topic: "events"})
```

**Key Features**:
- Directive.Emit describes signal dispatch (lazy execution)
- Dispatch config attached to signal or directive
- Multiple dispatch targets: `:pubsub`, `:pid`, `:http`, `:webhook`, `:logger`

### 3. Telemetry Event Pattern (from jido_behaviortree)

**Location**: `projects/jido_behaviortree/lib/jido_behaviortree/telemetry.ex:23-121`

```elixir
# Node tick events
[:jido, :bt, :node, :tick, :start]
[:jido, :bt, :node, :tick, :stop]
[:jido, :bt, :node, :tick, :exception]

# Metadata includes
%{
  node: node_module,
  sequence: tick.sequence,
  agent_id: metadata[:agent_id],
  agent_module: metadata[:agent_module],
  strategy: metadata[:strategy]
}
```

**Key Features**:
- Hierarchical event names
- Structured metadata
- Separate start/stop/exception events
- Integration with Jido.Observe for span tracking

### 4. Tick Context with Directive Accumulation

**Location**: `projects/jido_behaviortree/lib/jido_behaviortree/tick.ex:15-44, 241-266`

```elixir
# Tick structure
@schema Zoi.struct(
  __MODULE__,
  %{
    blackboard: Zoi.any(description: "The shared blackboard for the tick"),
    timestamp: Zoi.any(description: "The timestamp when the tick was created"),
    sequence: Zoi.integer(description: "The sequence number of the tick"),
    agent: Zoi.any(description: "The Jido agent") |> Zoi.optional(),
    directives: Zoi.list(Zoi.any()) |> Zoi.default([]),
    context: Zoi.any(description: "Execution context from strategy") |> Zoi.default(%{})
  }
)

# Helper for accumulating directives
def append_directives(%__MODULE__{directives: existing} = tick, new_directives) do
  %{tick | directives: existing ++ List.wrap(new_directives)}
end
```

**Key Features**:
- Directives accumulate during tree traversal
- Action nodes apply effects and emit directives
- Strategy returns accumulated directives to AgentServer

---

## Integration Points

### 1. BehaviorTree Strategy Signal Emission

**Location**: `projects/jido_behaviortree/lib/jido_behaviortree/strategy/behavior_tree.ex:119-176`

The strategy's `cmd/3` function is the integration point for tree-level signals:

```elixir
def cmd(%Agent{} = agent, instructions, ctx) when is_list(instructions) do
  # ... setup tick context ...

  # EMIT: Tree tick started signal
  {status, tree, tick} = Tree.tick_with_context(bt.tree, tick)

  # ... update agent state ...

  # EMIT: Tree tick completed signal
  # Return accumulated directives (including any signal emissions from nodes)
  {updated_agent, directives}
end
```

**Signal emission flow**:
1. Strategy creates tick context with agent metadata
2. Tree traversal accumulates directives on tick
3. Nodes emit Directive.Emit for their events
4. Strategy returns all directives to AgentServer
5. AgentServer executes directives, dispatching signals

### 2. Node Execution Signal Emission

**Location**: `projects/jido_behaviortree/lib/jido_behaviortree/node.ex:175-194`

The `execute_tick/2` wrapper is the integration point for node-level signals:

```elixir
def execute_tick(node_state, tick) do
  node_module = node_state.__struct__
  metadata = build_tick_metadata(node_module, tick)

  span_ctx = Observe.start_span([:jido, :bt, :node, :tick], metadata)

  try do
    # EMIT: Node entered signal

    {status, updated_node} = node_module.tick(node_state, tick)

    # EMIT: Node exited signal with status

    Observe.finish_span(span_ctx, %{status: status})
    {status, updated_node}
  rescue
    error ->
      # EMIT: Node error signal

      Observe.finish_span_error(span_ctx, :error, error, __STACKTRACE__)
      {{:error, Error.node_error(...)}, node_state}
  end
end
```

### 3. Blackboard Signal Emission

**Location**: `projects/jido_behaviortree/lib/jido_behaviortree/blackboard.ex`

Blackboard read/write operations should emit signals:

```elixir
def put(blackboard, key, value) do
  # EMIT: Blackboard write signal
  updated_map = Map.put(blackboard.map, key, value)
  %__MODULE__{blackboard | map: updated_map}
end

def get(blackboard, key, default \\ nil) do
  # EMIT: Blackboard read signal (optional, may be too verbose)
  Map.get(blackboard.map, key, default)
end
```

---

## Signal Schema Design

### Signal Type Naming Convention

Following Jido Signal patterns at `projects/jido_signal/lib/jido_signal.ex:93-110`:

```
<domain>.<entity>.<action>[.<qualifier>]

# Behavior tree signals:
jido.bt.node.entered          # Node tick started
jido.bt.node.completed         # Node tick completed
jido.bt.node.failed            # Node tick failed
jido.bt.tree.started           # Tree tick started
jido.bt.tree.completed         # Tree tick completed
jido.bt.blackboard.updated     # Blackboard value changed
jido.bt.action.executed        # Action node executed
jido.bt.agent.stopped          # Agent/tree halted
```

### Recommended Signal Definitions

#### 1. Node Lifecycle Signals

**File**: `projects/jido_behaviortree/lib/jido_behaviortree/signals/node.ex`

```elixir
defmodule Jido.BehaviorTree.Signals.NodeEntered do
  use Jido.Signal,
    type: "jido.bt.node.entered",
    default_source: "/jido/bt/node",
    schema: [
      node_id: [type: :string, required: true],
      node_type: [type: :atom, required: true],
      tree_id: [type: :string, required: true],
      agent_id: [type: :string, required: false],
      tick_sequence: [type: :integer, required: true],
      timestamp: [type: :string, required: true]
    ]
end

defmodule Jido.BehaviorTree.Signals.NodeCompleted do
  use Jido.Signal,
    type: "jido.bt.node.completed",
    default_source: "/jido/bt/node",
    schema: [
      node_id: [type: :string, required: true],
      node_type: [type: :atom, required: true],
      tree_id: [type: :string, required: true],
      agent_id: [type: :string, required: false],
      tick_sequence: [type: :integer, required: true],
      status: [type: :atom, required: true],  # :success, :failure, :running
      duration_us: [type: :integer, required: true],
      timestamp: [type: :string, required: true]
    ]
end

defmodule Jido.BehaviorTree.Signals.NodeFailed do
  use Jido.Signal,
    type: "jido.bt.node.failed",
    default_source: "/jido/bt/node",
    schema: [
      node_id: [type: :string, required: true],
      node_type: [type: :atom, required: true],
      tree_id: [type: :string, required: true],
      agent_id: [type: :string, required: false],
      tick_sequence: [type: :integer, required: true],
      error: [type: :string, required: true],
      duration_us: [type: :integer, required: true],
      timestamp: [type: :string, required: true]
    ]
end
```

#### 2. Tree Lifecycle Signals

**File**: `projects/jido_behaviortree/lib/jido_behaviortree/signals/tree.ex`

```elixir
defmodule Jido.BehaviorTree.Signals.TreeStarted do
  use Jido.Signal,
    type: "jido.bt.tree.started",
    default_source: "/jido/bt/tree",
    schema: [
      tree_id: [type: :string, required: true],
      agent_id: [type: :string, required: true],
      tick_count: [type: :integer, required: true],
      timestamp: [type: :string, required: true]
    ]
end

defmodule Jido.BehaviorTree.Signals.TreeCompleted do
  use Jido.Signal,
    type: "jido.bt.tree.completed",
    default_source: "/jido/bt/tree",
    schema: [
      tree_id: [type: :string, required: true],
      agent_id: [type: :string, required: true],
      tick_count: [type: :integer, required: true],
      final_status: [type: :atom, required: true],  # :success, :failure, :running
      duration_us: [type: :integer, required: true],
      timestamp: [type: :string, required: true]
    ]
end

defmodule Jido.BehaviorTree.Signals.TreeHalted do
  use Jido.Signal,
    type: "jido.bt.tree.halted",
    default_source: "/jido/bt/tree",
    schema: [
      tree_id: [type: :string, required: true],
      agent_id: [type: :string, required: false],
      reason: [type: :string, required: false],
      timestamp: [type: :string, required: true]
    ]
end
```

#### 3. Blackboard Signals

**File**: `projects/jido_behaviortree/lib/jido_behaviortree/signals/blackboard.ex`

```elixir
defmodule Jido.BehaviorTree.Signals.BlackboardUpdated do
  use Jido.Signal,
    type: "jido.bt.blackboard.updated",
    default_source: "/jido/bt/blackboard",
    schema: [
      tree_id: [type: :string, required: true],
      agent_id: [type: :string, required: false],
      key: [type: :any, required: true],
      operation: [type: :atom, required: true],  # :put, :delete, :update
      timestamp: [type: :string, required: true]
    ]
end
```

#### 4. Action-Specific Signals

**File**: `projects/jido_behaviortree/lib/jido_behaviortree/signals/action.ex`

```elixir
defmodule Jido.BehaviorTree.Signals.ActionExecuted do
  use Jido.Signal,
    type: "jido.bt.action.executed",
    default_source: "/jido/bt/action",
    schema: [
      action_module: [type: :atom, required: true],
      node_id: [type: :string, required: true],
      tree_id: [type: :string, required: true],
      agent_id: [type: :string, required: false],
      status: [type: :atom, required: true],  # :success, :error
      result: [type: :any, required: false],
      duration_us: [type: :integer, required: true],
      timestamp: [type: :string, required: true]
    ]
end
```

### Signal Context Data

All signals should include:
- **tree_id**: Unique identifier for the tree instance (can be agent ID or UUID)
- **agent_id**: Jido agent ID (when running as a strategy)
- **node_id**: Node identifier (module name + unique instance ID)
- **node_type**: Node module name for type-based routing
- **tick_sequence**: Sequence number for correlating events
- **timestamp**: ISO 8601 timestamp
- **duration_us**: Execution duration in microseconds (for completed events)
- **status**: Final status (:success, :failure, :running, {:error, reason})
- **error**: Error message for failed events

---

## Test Impact & Patterns

### Tests Requiring Updates

| File | Purpose |
|------|---------|
| `projects/jido_behaviortree/test/jido_behaviortree/signals_test.exs` | **NEW**: Signal schema validation, serialization tests |
| `projects/jido_behaviortree/test/jido_behaviortree/node_test.exs` | Update to expect Directive.Emit in results |
| `projects/jido_behaviortree/test/jido_behaviortree/tree_test.exs` | Update to check for tree lifecycle signals |
| `projects/jido_behaviortree/test/jido_behaviortree/agent_test.exs` | Update to verify signal emission during ticks |
| `projects/jido_behaviortree/test/jido_behaviortree/blackboard_test.exs` | Update to verify blackboard signals |

### Testing Pattern (from existing jido_signal tests)

**Location**: `projects/jido_signal/test/jido_signal_test.exs`

```elixir
describe "signal creation" do
  test "creates valid signal with schema validation" do
    {:ok, signal} = NodeCompleted.new(%{
      node_id: "node-123",
      node_type: Sequence,
      tree_id: "tree-456",
      agent_id: "agent-789",
      tick_sequence: 1,
      status: :success,
      duration_us: 1500,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    assert signal.type == "jido.bt.node.completed"
    assert signal.data.node_id == "node-123"
  end

  test "validates required fields" do
    assert {:error, _reason} = NodeCompleted.new(%{
      node_id: "node-123",
      # Missing required fields...
    })
  end
end

describe "signal serialization" do
  test "serializes to JSON" do
    {:ok, signal} = NodeCompleted.new(valid_data)
    {:ok, json} = Jason.encode(signal)
    assert {:ok, _decoded} = Jason.decode(json)
  end
end
```

### Mocking Strategy

Use `Mimic` (already in dev dependencies) to mock signal dispatch:

```elixir
import Mimic

test "node emits completed signal" do
  # Stub the Directive.emit to capture signal
  stub(Jido.Agent.Directive, :emit, fn signal ->
    send(self(), {:signal_emitted, signal})
    %Directive.Emit{signal: signal}
  end)

  # Execute node tick
  {status, _node} = Node.execute_tick(node, tick)

  # Assert signal was emitted
  assert_received {:signal_emitted, signal}
  assert signal.type == "jido.bt.node.completed"
end
```

---

## Configuration & Environment

### Config Files to Update

**File**: `projects/jido_behaviortree/config/config.exs`

No changes required for signal definitions (they're code-based), but may want:

```elixir
config :jido_behaviortree,
  # Enable/disable signal emission
  emit_signals: true,

  # Filter which signals to emit (reduce spam)
  signal_filter: [
    # Emit all signals by default
    :all
    # Or specific signal types:
    # [:node_entered, :node_completed, :tree_completed]
  ],

  # Blackboard signal filtering (can be very noisy)
  blackboard_signals: false

  # Signal dispatch configuration
  signal_dispatch: {:pubsub, topic: "jido_bt_events"}
```

### Environment Variables

None required for signal definitions (configuration is compile-time), but may want:

```elixir
# Runtime signal toggle (via Application config)
Application.put_env(:jido_behaviortree, :emit_signals, true)

# Or per-agent configuration
strategy: {BehaviorTree,
  tree: my_tree(),
  emit_signals: true  # Override default
}
```

---

## Risk Assessment

### Breaking Changes

**Severity**: LOW

- Signals are additive, don't change existing APIs
- Telemetry events remain unchanged
- Directive.Emit pattern is already established
- Existing tests should pass (signal emission is side-effect)

**Mitigation**:
- Make signal emission configurable (can disable)
- Provide feature flag for gradual rollout
- Ensure signals don't impact performance

### Performance Implications

**Severity**: MEDIUM

- Signal creation overhead per tick
- JSON serialization for dispatch
- Network I/O for remote dispatch
- Blackboard signals could be **extremely** noisy

**Bottlenecks**:
1. Hot path: `Node.execute_tick/2` called for every node
2. Blackboard reads/writes happen frequently
3. Signal dispatch is synchronous by default

**Mitigation**:
- Configurable signal filtering
- Async dispatch options
- Blackboard signals opt-in only
- Batch signal emission where possible

### Security Considerations

**Severity**: LOW

- Signals may expose sensitive blackboard data
- Agent IDs and tree structure are internal details
- Error messages may contain stack traces

**Mitigation**:
- Sanitize error data in signals
- Configurable data inclusion
- Consider encryption for sensitive signals
- Document which signals are public vs internal

### Migration Complexity

**Severity**: LOW

- No database schema changes
- No migration scripts needed
- Additive feature only

**Approach**:
1. Add signal definitions
2. Add emission points with feature flags
3. Update tests gradually
4. Document signal catalog
5. Release as minor version bump

---

## Signal Spam Prevention

### Problem

Behavior trees can execute thousands of ticks per second. Emitting a signal for every node tick event would flood the system.

### Solutions

#### 1. Hierarchical Filtering

Only emit signals for significant nodes:

```elixir
# Only emit for composite nodes and action nodes
# Skip decorator nodes (inverter, repeater, etc.)
def should_emit_signal?(node_module) do
  node_module in [Sequence, Selector, Action, Wait]
end
```

#### 2. Sampling

Emit every Nth tick:

```elixir
def emit_sampled(signal, tick_sequence, sample_rate \\ 10) do
  if rem(tick_sequence, sample_rate) == 0 do
    Directive.emit(signal)
  else
    nil
  end
end
```

#### 3. Completion-Only

Only emit completion signals, not "entered" signals:

```elixir
# Don't emit NodeEntered
# Only emit NodeCompleted and NodeFailed
```

#### 4. Configurable Verbosity

```elixir
config :jido_behaviortree,
  signal_verbosity: :normal  # :quiet, :normal, :verbose

# :quiet - Only tree-level signals
# :normal - Tree + action node signals
# :verbose - All node signals
```

#### 5. Blackboard Signal Filtering

Blackboard signals are the most dangerous for spam:

```elixir
config :jido_behaviortree,
  blackboard_signals: false  # Disabled by default

# Or opt-in per-key
blackboard_signal_keys: [:user_id, :session_id]  # Only emit for these keys
```

### Recommended Default Configuration

```elixir
# Default: Minimal signal spam
config :jido_behaviortree,
  emit_signals: true,
  signal_verbosity: :normal,
  blackboard_signals: false,
  emit_node_entered: false,  # Only emit completed/failed
  sample_rate: 1  # No sampling by default
```

---

## Documentation Requirements

### Signal Catalog Documentation

**File**: `projects/jido_behaviortree/guides/signals.md` (NEW)

Document all signals with:
- Signal type name
- Schema definition
- When it's emitted
- Example payload
- Use cases (debugging, telemetry, cross-agent coordination)
- Public vs internal designation

### Integration Guide

**File**: `projects/jido_behaviortree/guides/signal-integration.md` (NEW)

Document:
- How to subscribe to behavior tree signals
- Signal filtering and routing
- Performance considerations
- Example signal consumers (telemetry, logging, monitoring)

### API Documentation

Update `@moduledoc` for:
- `Jido.BehaviorTree` - Mention signal emission
- `Jido.BehaviorTree.Node` - Document signal emission in callbacks
- `Jido.BehaviorTree.Agent` - Document agent lifecycle signals
- `Jido.BehaviorTree.Tree` - Document tree lifecycle signals

---

## Key Implementation Considerations

### 1. Signal Emission via Directives

**Pattern**: Emit Directive.Emit, don't dispatch directly

```elixir
# CORRECT: Emit directive (lazy, accumulated)
def tick(node_state, tick) do
  # ... do work ...
  signal = NodeCompleted.new!(...)
  directives = [Directive.emit(signal)]
  {status, node_state, directives}
end

# WRONG: Dispatch directly (imperative, bypasses agent)
def tick(node_state, tick) do
  # ... do work ...
  signal = NodeCompleted.new!(...)
  Jido.Signal.Bus.dispatch(bus, signal)  # Don't do this
  {status, node_state}
end
```

**Why**:
- Directives are composable with other effects
- Agent controls when signals are dispatched
- Enables filtering and batching at agent level
- Aligns with Jido effect system architecture

### 2. Unique Node Identification

**Problem**: Nodes don't have unique IDs (just module names)

**Solution**: Generate node ID at tree construction or first tick

```elixir
# Option 1: Assign during tree construction
def build_tree(nodes) do
  Enum.map(nodes, fn node ->
    %{node | id: generate_node_id()}
  end)
end

# Option 2: Lazy assignment on first tick
def ensure_node_id(%{id: nil} = node) do
  %{node | id: generate_node_id()}
end
def ensure_node_id(node), do: node
```

### 3. Context Extraction

Extract agent context from Tick for signals:

```elixir
defp build_signal_metadata(tick) do
  %{
    tree_id: get_tree_id(tick),
    agent_id: get_agent_id(tick),
    tick_sequence: tick.sequence,
    timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
  }
end
```

### 4. Error Handling

Wrap signal creation in try/rescue to avoid breaking BT execution:

```elixir
def safe_emit_signal(signal_module, data) do
  try do
    case signal_module.new(data) do
      {:ok, signal} -> Directive.emit(signal)
      {:error, reason} ->
        Logger.warning("Failed to create signal: #{reason}")
        nil
    end
  rescue
    e ->
      Logger.error("Signal creation error: #{Exception.message(e)}")
      nil
  end
end
```

### 5. Telemetry Correlation

Include correlation IDs for linking signals to telemetry:

```elixir
# Get span context from Observe
defp get_correlation_id(tick) do
  case Jido.Observe.current_span_ctx() do
    %{span_id: span_id} -> span_id
    _ -> nil
  end
end

# Include in signal data
correlation_id: get_correlation_id(tick)
```

---

## Public vs Internal Signals

### Public Signals

For external consumption (other agents, monitoring systems, webhooks):

- `jido.bt.tree.completed` - Tree finished with status
- `jido.bt.action.executed` - Action nodes completed
- `jido.bt.tree.halted` - Tree was halted

**Characteristics**:
- Stable schema (semantic versioning applies)
- Well-documented
- Minimal noise
- Useful for cross-agent coordination

### Internal Signals

For debugging and observability:

- `jido.bt.node.entered` - Every node entry
- `jido.bt.node.completed` - Every node completion
- `jido.bt.blackboard.updated` - Every blackboard change

**Characteristics**:
- May change between versions
- Documented as "internal"
- Can be noisy
- Opt-in only

**Implementation**:

```elixir
defmodule Jido.BehaviorTree.Signals.NodeEntered do
  @moduledoc """
  Internal signal emitted when a behavior tree node is entered.

  **INTERNAL**: This signal is for debugging and observability only.
  The schema may change between minor versions.
  """
  use Jido.Signal,
    type: "jido.bt.node.entered",
    default_source: "/jido/bt/node/internal",
    schema: [...]
end
```

---

## Documentation References

| File | Description |
|------|-------------|
| `projects/jido_signal/README.md` | Signal system overview |
| `projects/jido_signal/guides/signals-and-dispatch.md` | Signal creation and dispatch guide |
| `projects/jido_signal/guides/signal-router.md` | Signal routing patterns |
| `projects/jido/guides/directives.md` | Directive system guide |
| `projects/jido_behaviortree/guides/getting-started.md` | Behavior tree usage guide |
| `projects/jido/guides/strategies.md` | Strategy implementation guide |

---

## Files Identified: 27

### New Files (5)
- `projects/jido_behaviortree/lib/jido_behaviortree/signals.ex`
- `projects/jido_behaviortree/lib/jido_behaviortree/signals/node.ex`
- `projects/jido_behaviortree/lib/jido_behaviortree/signals/tree.ex`
- `projects/jido_behaviortree/lib/jido_behaviortree/signals/blackboard.ex`
- `projects/jido_behaviortree/test/jido_behaviortree/signals_test.exs`

### Modified Files (22)
- `projects/jido_behaviortree/lib/jido_behaviortree/node.ex`
- `projects/jido_behaviortree/lib/jido_behaviortree/tree.ex`
- `projects/jido_behaviortree/lib/jido_behaviortree/strategy/behavior_tree.ex`
- `projects/jido_behaviortree/lib/jido_behaviortree/nodes/sequence.ex`
- `projects/jido_behaviortree/lib/jido_behaviortree/nodes/selector.ex`
- `projects/jido_behaviortree/lib/jido_behaviortree/nodes/action.ex`
- `projects/jido_behaviortree/lib/jido_behaviortree/nodes/wait.ex`
- `projects/jido_behaviortree/lib/jido_behaviortree/nodes/failer.ex`
- `projects/jido_behaviortree/lib/jido_behaviortree/nodes/succeeder.ex`
- `projects/jido_behaviortree/lib/jido_behaviortree/nodes/inverter.ex`
- `projects/jido_behaviortree/lib/jido_behaviortree/nodes/repeat.ex`
- `projects/jido_behaviortree/lib/jido_behaviortree/nodes/set_blackboard.ex`
- `projects/jido_behaviortree/lib/jido_behaviortree/blackboard.ex`
- `projects/jido_behaviortree/lib/jido_behaviortree/agent.ex`
- `projects/jido_behaviortree/mix.exs`
- `projects/jido_behaviortree/test/jido_behaviortree/node_test.exs`
- `projects/jido_behaviortree/test/jido_behaviortree/tree_test.exs`
- `projects/jido_behaviortree/test/jido_behaviortree/agent_test.exs`
- `projects/jido_behaviortree/test/jido_behaviortree/blackboard_test.exs`
- `projects/jido_behaviortree/test/jido_behaviortree/nodes/sequence_test.exs`
- `projects/jido_behaviortree/test/jido_behaviortree/nodes/selector_test.exs`
- `projects/jido_behaviortree/test/jido_behaviortree/nodes/action_test.exs`

---

## Summary

This task requires defining ~8-10 signal types covering behavior tree lifecycle events, emitting them via the Directive.Emit pattern at key integration points, and ensuring they don't cause signal spam. The implementation should follow existing Jido patterns from `jido_signal` and `jido`, use Zoi schemas for validation, integrate cleanly with the directive-based effect system, and distinguish between public and internal signals. The main risks are performance impact (mitigated via configurable filtering) and signal spam (mitigated via hierarchical filtering, sampling, and opt-in blackboard signals).

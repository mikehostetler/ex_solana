# Implementation Plan: Define Signals for Behavior Tree State Transitions/Events

**Item ID**: 006
**Status**: Planned
**Date**: 2025-01-07

---

## Executive Summary

This implementation introduces a comprehensive CloudEvents-based signal system for Jido Behavior Trees that enables cross-agent coordination, debugging, and telemetry. The signals will follow the existing `jido_signal` patterns, emit via the Directive.Emit effect system, and distinguish between public consumption signals (stable, minimal noise) and internal debugging signals (opt-in, verbose). Key architectural decisions include: (1) using Directive.Emit for lazy signal accumulation during tree traversal, (2) hierarchical filtering and sampling to prevent signal spam, (3) configurable verbosity levels (:quiet, :normal, :verbose), and (4) disabling blackboard signals by default. The implementation will add 8-10 signal definitions across node, tree, blackboard, and action lifecycles, integrate emission points into existing Node/Tree execution paths, and maintain backward compatibility (signals are additive, no API changes). Estimated effort: 3-4 days for core implementation plus 1-2 days for testing and documentation.

---

## Impact Analysis Summary

### Key Research Findings

From `research.md`:

1. **Existing Event Infrastructure**: The Jido ecosystem already has three complementary event systems:
   - Telemetry events (low-level tracing, already implemented for BT)
   - Jido Signals (CloudEvents-based, for domain events)
   - Directives (effect descriptions for AgentServer)

2. **Signal Definition Pattern**: Use `Jido.Signal` with Zoi schemas for validation (see `projects/jido_signal/lib/jido_signal.ex:68-93`)

3. **Emission Pattern**: Use `Directive.emit(signal)` to accumulate directives during tick, not direct dispatch (see `projects/jido/lib/jido/agent/directive.ex:386-395`)

4. **Integration Points**:
   - `Node.execute_tick/2` (lines 175-194) - Node lifecycle signals
   - `Tree.tick_with_context/2` (lines 79-107) - Tree lifecycle signals
   - `Strategy.BehaviorTree.cmd/3` (lines 119-176) - Agent lifecycle signals
   - Blackboard read/write operations - Change signals

### Files Requiring Changes (by Phase)

**Phase 1 - Foundation**:
- `lib/jido_behaviortree/signals.ex` (NEW)
- `lib/jido_behaviortree/signals/node.ex` (NEW)
- `lib/jido_behaviortree/signals/tree.ex` (NEW)
- `lib/jido_behaviortree/signals/blackboard.ex` (NEW)
- `lib/jido_behaviortree/signals/action.ex` (NEW)
- `config/config.exs` (MODIFY - add signal configuration)

**Phase 2 - Core Implementation**:
- `lib/jido_behaviortree/node.ex` (MODIFY - add emission to execute_tick/2)
- `lib/jido_behaviortree/tree.ex` (MODIFY - add emission to tick/2, halt/1)
- `lib/jido_behaviortree/blackboard.ex` (MODIFY - add emission to put/3, delete/2)
- `lib/jido_behaviortree/nodes/action.ex` (MODIFY - add action-specific signals)
- `test/jido_behaviortree/signals_test.exs` (NEW)

**Phase 3 - Integration**:
- `lib/jido_behaviortree/strategy/behavior_tree.ex` (MODIFY - accumulate directives)
- `lib/jido_behaviortree/agent.ex` (MODIFY - agent lifecycle signals)
- `test/jido_behaviortree/node_test.exs` (UPDATE)
- `test/jido_behaviortree/tree_test.exs` (UPDATE)
- `test/jido_behaviortree/agent_test.exs` (UPDATE)

**Phase 4 - Documentation**:
- `guides/signals.md` (NEW)
- `guides/signal-integration.md` (NEW)
- `mix.exs` (UPDATE - docs groups)
- Various `@moduledoc` updates

### Existing Patterns to Follow

1. **Signal Definition**: `use Jido.Signal` with type, default_source, schema
2. **Directive Emission**: `Directive.emit(signal)` for lazy accumulation
3. **Telemetry Integration**: Include correlation_id from Observe span context
4. **Error Handling**: Safe signal creation (try/rescue) to avoid breaking BT execution

---

## Feature Specification

### User Stories

**US1: Telemetry Integration**
> As a system operator, I want to receive behavior tree completion signals so that I can track agent execution metrics and monitor system health.

**Acceptance Criteria**:
- `jido.bt.tree.completed` signal emitted on tree completion
- Contains final_status, duration_us, agent_id, tree_id
- Integrates with existing telemetry events via correlation_id

**US2: Cross-Agent Coordination**
> As an agent developer, I want to subscribe to action execution signals so that my agent can react when specific actions are performed by other agents.

**Acceptance Criteria**:
- `jido.bt.action.executed` signal contains action_module, status, result
- Can filter by action_module type
- Public API (stable schema)

**US3: Debugging Support**
> As a developer, I want to enable verbose node-level signals so that I can trace behavior tree execution during development.

**Acceptance Criteria**:
- `jido.bt.node.entered` and `jido.bt.node.completed` signals
- Configurable via signal_verbosity: :verbose
- Disabled by default to avoid spam

**US4: Signal Spam Prevention**
> As a system operator, I want to configure signal filtering so that my system is not overwhelmed by high-frequency events.

**Acceptance Criteria**:
- Configurable verbosity levels (:quiet, :normal, :verbose)
- Sampling option (emit every Nth tick)
- Blackboard signals disabled by default
- Can disable all signals via emit_signals: false

### API Contracts

#### Signal Module API

```elixir
# Public signals (stable schema)
Jido.BehaviorTree.Signals.TreeCompleted
Jido.BehaviorTree.Signals.TreeHalted
Jido.BehaviorTree.Signals.ActionExecuted

# Internal signals (may change)
Jido.BehaviorTree.Signals.NodeEntered
Jido.BehaviorTree.Signals.NodeCompleted
Jido.BehaviorTree.Signals.NodeFailed
Jido.BehaviorTree.Signals.BlackboardUpdated

# All signals implement
{:ok, signal} = SignalModule.new(data)
signal = SignalModule.new!(data)
{:ok, signal} = SignalModule.validate(data)
```

#### Configuration API

```elixir
# config/config.exs
config :jido_behaviortree,
  # Master switch
  emit_signals: true,

  # Verbosity level
  signal_verbosity: :normal,  # :quiet | :normal | :verbose

  # Specific signal toggles
  emit_node_entered: false,
  blackboard_signals: false,

  # Sampling (emit every Nth tick)
  sample_rate: 1,

  # Default dispatch
  signal_dispatch: {:pubsub, topic: "jido_bt_events"}
```

#### Directive Integration API

```elixir
# Node tick callback (existing API, enhanced)
def tick(node_state, tick) do
  # ... do work ...
  {status, updated_node, directives}  # directives may include Directive.Emit
end

# Tree execution (existing API, enhanced)
{status, tree, tick} = Tree.tick_with_context(tree, tick)
# tick.directives now includes accumulated signal emissions
```

### Data Flow

```
1. AgentServer calls BehaviorTree strategy
2. Strategy creates Tick with empty directives list
3. Tree traversal begins:
   a. Node.execute_tick wraps node.tick
   b. Node tick returns {status, node, directives}
   c. Directives accumulated on Tick via Tick.append_directives/2
4. Node modules emit Directive.emit(signal) in their directives list
5. Strategy returns {updated_agent, all_directives} to AgentServer
6. AgentServer executes Directive.Emit directives
7. Signals dispatched via configured transport (PubSub, HTTP, etc.)
```

### State Management Requirements

No new state required. Signals are ephemeral events emitted during execution.

### Error Handling Approach

- **Signal creation failures**: Log warning, continue execution (don't break BT)
- **Validation errors**: Return {:error, reason}, log, skip emission
- **Dispatch failures**: Handle in AgentServer (existing error handling)
- **Invalid signal data**: Use Zoi validation, reject at creation time

---

## Technical Design

### Data Model Changes

No data model changes. Signals are CloudEvents following existing `jido_signal` pattern:

```elixir
%Jido.Signal{
  id: "uuid-v4",
  source: "/jido/bt/node",
  type: "jido.bt.node.completed",
  datacontenttype: "application/json",
  data: %{
    node_id: "node-123",
    node_type: Sequence,
    tree_id: "tree-456",
    agent_id: "agent-789",
    status: :success,
    duration_us: 1500,
    timestamp: "2025-01-07T12:00:00Z"
  }
}
```

### Module Organization

```
projects/jido_behaviortree/lib/jido_behaviortree/
├── signals.ex                  # Signal catalog and helpers
├── signals/
│   ├── node.ex                # Node lifecycle signals
│   ├── tree.ex                # Tree lifecycle signals
│   ├── blackboard.ex          # Blackboard change signals
│   └── action.ex              # Action execution signals
├── node.ex                    # Modified: add emission points
├── tree.ex                    # Modified: add emission points
├── blackboard.ex              # Modified: add emission points
└── strategy/
    └── behavior_tree.ex       # Modified: accumulate directives

test/jido_behaviortree/
├── signals_test.exs           # NEW: signal validation tests
├── node_test.exs              # UPDATE: verify signal emission
├── tree_test.exs              # UPDATE: verify signal emission
└── agent_test.exs             # UPDATE: verify signal emission
```

### Third-Party Integrations

- **jido_signal** (v1.2.0): Already a dependency, use `use Jido.Signal`
- **jido** (path dependency): Directive.Emit already available
- **phoenix_pubsub** (~> 2.1): Default signal transport
- **telemetry** (~> 1.3): Correlation with existing telemetry

No new dependencies required.

### Configuration/Environment Changes

```elixir
# config/config.exs - Add to existing config
config :jido_behaviortree,
  # Signal emission controls
  emit_signals: true,
  signal_verbosity: :normal,
  emit_node_entered: false,
  blackboard_signals: false,
  sample_rate: 1,
  signal_dispatch: {:pubsub, topic: "jido_bt_events"}

# Runtime overrides (optional)
# Application.put_env(:jido_behaviortree, :emit_signals, false)
```

---

## Implementation Phases

### Phase 1: Foundation

**Objective**: Define signal schemas and configuration infrastructure

**Success Criteria**:
- All signal modules compile without errors
- Signal validation works correctly
- Configuration options defined and documented

**Files to Create**:
1. `lib/jido_behaviortree/signals.ex`
2. `lib/jido_behaviortree/signals/node.ex`
3. `lib/jido_behaviortree/signals/tree.ex`
4. `lib/jido_behaviortree/signals/blackboard.ex`
5. `lib/jido_behaviortree/signals/action.ex`

**Files to Modify**:
1. `config/config.exs` - Add signal configuration section

**Tests to Add**:
1. `test/jido_behaviortree/signals_test.exs`
   - Signal creation with valid data
   - Signal validation (required fields)
   - Signal serialization to JSON
   - Signal type and source verification

**Dependencies**: None (foundation phase)

**Implementation Tasks**:
1. Create `signals.ex` with:
   - `@moduledoc` explaining signal system
   - Helper functions for building signal metadata
   - Configuration access helpers
   - Signal emission helpers (safe_emit, should_emit?)

2. Create `signals/node.ex` with:
   - `NodeEntered` signal (internal)
   - `NodeCompleted` signal (internal)
   - `NodeFailed` signal (internal)
   - All follow CloudEvents spec

3. Create `signals/tree.ex` with:
   - `TreeStarted` signal (public)
   - `TreeCompleted` signal (public)
   - `TreeHalted` signal (public)

4. Create `signals/blackboard.ex` with:
   - `BlackboardUpdated` signal (internal, opt-in)

5. Create `signals/action.ex` with:
   - `ActionExecuted` signal (public)

6. Add configuration to `config/config.exs` with:
   - Master switch (emit_signals)
   - Verbosity levels (signal_verbosity)
   - Per-signal toggles
   - Sampling configuration

**Acceptance Tests**:
```elixir
test "creates valid NodeCompleted signal" do
  {:ok, signal} = NodeCompleted.new(valid_data)
  assert signal.type == "jido.bt.node.completed"
  assert signal.data.node_id == "node-123"
end

test "validates required fields" do
  assert {:error, _reason} = NodeCompleted.new(%{node_id: "123"})
end

test "serializes to JSON" do
  {:ok, signal} = TreeCompleted.new(valid_data)
  {:ok, json} = Jason.encode(signal)
  assert {:ok, _decoded} = Jason.decode(json)
end
```

---

### Phase 2: Core Implementation

**Objective**: Add signal emission to core Node, Tree, and Blackboard execution paths

**Success Criteria**:
- Node lifecycle signals emitted during tick
- Tree lifecycle signals emitted during execution
- Blackboard signals emitted on writes (when enabled)
- All emissions use Directive.Emit pattern
- Signal emission doesn't break existing tests

**Files to Modify**:
1. `lib/jido_behaviortree/node.ex`
   - Add emission to `execute_tick/2` (lines 175-194)
   - Add emission to `execute_halt/1` (lines 248-268)
   - Add helper: `build_signal_metadata/1`

2. `lib/jido_behaviortree/tree.ex`
   - Add emission to `tick/2` (lines 79-107)
   - Add emission to `tick_with_context/2`
   - Add emission to `halt/1` (lines 152-156)

3. `lib/jido_behaviortree/blackboard.ex`
   - Add emission to `put/3`
   - Add emission to `delete/2`
   - Add emission to `update/4` (if exists)

4. `lib/jido_behaviortree/nodes/action.ex`
   - Add emission to `run_action/3` (lines 81-120)
   - Emit `ActionExecuted` signal

**Tests to Add**:
1. Update `test/jido_behaviortree/node_test.exs`
   - Verify NodeEntered emitted (when verbose)
   - Verify NodeCompleted emitted
   - Verify NodeFailed emitted on error

2. Update `test/jido_behaviortree/tree_test.exs`
   - Verify TreeStarted emitted
   - Verify TreeCompleted emitted
   - Verify TreeHalted emitted

3. Update `test/jido_behaviortree/blackboard_test.exs`
   - Verify BlackboardUpdated emitted (when enabled)

4. Create `test/jido_behaviortree/signals/integration_test.exs`
   - End-to-end signal flow test
   - Verify directive accumulation

**Dependencies**: Phase 1 complete

**Implementation Tasks**:

1. **Modify Node.execute_tick/2**:
```elixir
def execute_tick(node_state, tick) do
  # Emit NodeEntered (if verbose)
  entered_directive = maybe_emit_signal(NodeEntered, build_metadata(node_state, tick))

  try do
    {status, updated_node} = node_module.tick(node_state, tick)
    # Emit NodeCompleted
    completed_directive = emit_signal(NodeCompleted, build_metadata(status, duration))
    {status, updated_node, [entered_directive, completed_directive]}
  rescue
    error ->
      # Emit NodeFailed
      failed_directive = emit_signal(NodeFailed, build_metadata(error))
      {{:error, error}, node_state, [entered_directive, failed_directive]}
  end
end
```

2. **Modify Tree.tick_with_context/2**:
```elixir
def tick_with_context(tree, tick) do
  # Emit TreeStarted
  started_directive = emit_signal(TreeStarted, build_tree_metadata(tree, tick))

  # ... existing tree traversal logic ...

  # Emit TreeCompleted
  completed_directive = emit_signal(TreeCompleted, build_result_metadata(status, duration))

  # Accumulate directives on tick
  updated_tick = Tick.append_directives(tick, [started_directive, completed_directive])
  {status, tree, updated_tick}
end
```

3. **Add configuration helpers**:
```elixir
defp should_emit_signal?(signal_type) do
  verbosity = Application.get_env(:jido_behaviortree, :signal_verbosity, :normal)
  emit_enabled = Application.get_env(:jido_behaviortree, :emit_signals, true)

  emit_enabled and signal_allowed_by_verbosity?(signal_type, verbosity)
end
```

4. **Add safe emission helper**:
```elixir
defp safe_emit_signal(signal_module, data) do
  try do
    case signal_module.new(data) do
      {:ok, signal} -> Directive.emit(signal)
      {:error, reason} ->
        Logger.warning("Failed to create #{signal_module}: #{reason}")
        nil
    end
  rescue
    e -> Logger.error("Signal creation error: #{Exception.message(e)}"); nil
  end
end
```

**Acceptance Tests**:
```elixit
test "node emits completed signal via directive" do
  {status, node, directives} = Node.execute_tick(node, tick)
  assert [%Directive.Emit{}] = directives
  assert hd(directives).signal.type == "jido.bt.node.completed"
end

test "tree emits started and completed signals" do
  {status, tree, tick} = Tree.tick_with_context(tree, tick)
  assert [%Directive.Emit{type: "jido.bt.tree.started"}, %Directive.Emit{type: "jido.bt.tree.completed"}] =
    tick.directives
end
```

---

### Phase 3: Integration & Testing

**Objective**: Integrate with BehaviorTree strategy, update all node types, comprehensive testing

**Success Criteria**:
- BehaviorTree strategy accumulates signal directives
- All node types (Sequence, Selector, decorators) emit signals
- Agent lifecycle signals integrated
- All existing tests pass
- New signal tests pass
- Performance impact < 5% overhead

**Files to Modify**:
1. `lib/jido_behaviortree/strategy/behavior_tree.ex`
   - Ensure directives returned to AgentServer
   - Emit agent lifecycle signals

2. `lib/jido_behaviortree/agent.ex`
   - Add agent lifecycle signals (lines 296-332)

3. `lib/jido_behaviortree/nodes/sequence.ex`
   - Ensure directives passed through

4. `lib/jido_behaviortree/nodes/selector.ex`
   - Ensure directives passed through

5. `lib/jido_behaviortree/nodes/*.ex` (all decorator nodes)
   - Ensure directives passed through

**Tests to Update**:
1. `test/jido_behaviortree/agent_test.exs`
   - Verify agent lifecycle signals
   - Verify directives accumulated and executed

2. `test/jido_behaviortree/nodes/*_test.exs`
   - Verify signal emission for each node type

**Performance Tests**:
1. Benchmark tree execution with/without signals
2. Benchmark with different verbosity levels
3. Verify < 5% overhead with :normal verbosity

**Dependencies**: Phase 2 complete

**Implementation Tasks**:

1. **Verify directive accumulation in Strategy.BehaviorTree**:
```elixir
def cmd(%Agent{} = agent, instructions, ctx) when is_list(instructions) do
  tick = create_tick_context(agent, instructions)

  # Tree traversal accumulates directives on tick
  {status, tree, tick} = Tree.tick_with_context(bt.tree, tick)

  # Ensure directives returned to AgentServer
  {updated_agent, tick.directives}
end
```

2. **Add agent lifecycle signals**:
```elixir
defp maybe_emit_agent_lifecycle_signal(agent, event) do
  case event do
    :started -> emit_signal(AgentStarted, build_agent_metadata(agent))
    :stopped -> emit_signal(AgentStopped, build_agent_metadata(agent))
    _ -> nil
  end
end
```

3. **Update composite nodes to pass through directives**:
```elixir
def tick(%Sequence{children: children} = seq, tick) do
  # Accumulate directives from all children
  {status, updated_children, all_directives} =
    Enum.reduce_while(children, {:running, [], []}, fn child, {_status, acc_children, acc_dirs} ->
      {status, updated_child, child_dirs} = Node.execute_tick(child, tick)
      # ... continue traversal ...
    end)

  directives = tick.directives ++ all_directives
  {status, %{seq | children: updated_children}, directives}
end
```

4. **Add performance benchmarks**:
```elixir
defmodule Jido.BehaviorTree.Benchmarks do
  use Benchee

  bench "tree tick without signals", do: tree_tick(false)
  bench "tree tick with signals (quiet)", do: tree_tick(true, :quiet)
  bench "tree tick with signals (normal)", do: tree_tick(true, :normal)
  bench "tree tick with signals (verbose)", do: tree_tick(true, :verbose)
end
```

**Acceptance Tests**:
```elixir
test "agent executes and emits signals" do
  {:ok, agent} = Agent.start_link(strategy: {BehaviorTree, tree: my_tree()})
  Agent.execute(agent, [:tick])

  assert_received %Jido.Signal{type: "jido.bt.tree.started"}
  assert_received %Jido.Signal{type: "jido.bt.tree.completed"}
end

test "signal emission overhead < 5%" do
  {time_without, _} = :timer.tc(fn -> run_tree(false) end)
  {time_with, _} = :timer.tc(fn -> run_tree(true, :normal) end)
  overhead = (time_with - time_without) / time_without * 100
  assert overhead < 5.0
end
```

---

### Phase 4: Polish & Documentation

**Objective**: Write comprehensive documentation, examples, and finalize polish

**Success Criteria**:
- Signal catalog documentation complete
- Integration guide with examples
- All @moduledoc updated
- Mix docs groups updated
- Examples demonstrating signal consumption
- Performance characteristics documented

**Files to Create**:
1. `guides/signals.md` - Complete signal catalog
2. `guides/signal-integration.md` - How to integrate and consume signals
3. `examples/signal_consumer.exs` - Example signal consumer

**Files to Modify**:
1. `mix.exs` - Add signal modules to docs groups
2. `lib/jido_behaviortree.ex` - Update main moduledoc
3. `lib/jido_behaviortree/signals.ex` - Comprehensive moduledoc
4. `lib/jido_behaviortree/node.ex` - Document signal emission
5. `lib/jido_behaviortree/tree.ex` - Document signal emission
6. `lib/jido_behaviortree/agent.ex` - Document signal emission

**Documentation Tasks**:

1. **Create `guides/signals.md`**:
```markdown
# Behavior Tree Signals

## Overview
Behavior trees emit CloudEvents-based signals for lifecycle events...

## Public Signals (Stable API)

### TreeCompleted
Emitted when a behavior tree completes execution.

**Type**: `jido.bt.tree.completed`
**Stability**: Public (follows semantic versioning)

**Schema**:
- tree_id: string (required)
- agent_id: string (required)
- final_status: atom (:success | :failure | :running)
- duration_us: integer (microseconds)
- timestamp: ISO 8601 string

**Example**:
```json
{
  "type": "jido.bt.tree.completed",
  "source": "/jido/bt/tree",
  "data": {
    "tree_id": "tree-abc123",
    "agent_id": "agent-xyz789",
    "final_status": "success",
    "duration_us": 15432,
    "timestamp": "2025-01-07T12:00:00Z"
  }
}
```

## Internal Signals (Debugging Only)

### NodeEntered
Emitted when a node is entered during tree traversal.

**Type**: `jido.bt.node.entered`
**Stability**: Internal (may change between versions)

## Signal Filtering

Configure verbosity to reduce signal spam...

## Configuration

See `guides/signal-integration.md`
```

2. **Create `guides/signal-integration.md`**:
```markdown
# Signal Integration Guide

## Subscribing to Signals

### Via Phoenix PubSub
```elixir
# In your application
defmodule MySignalConsumer do
  def start_link do
    Phoenix.PubSub.subscribe(:jido_signals, "jido_bt_events")
  end

  def handle_info(%Jido.Signal{type: "jido.bt.tree.completed"} = signal) do
    IO.puts("Tree completed: #{signal.data.final_status}")
  end
end
```

### Via HTTP Webhook
```elixir
config :jido_behaviortree,
  signal_dispatch: {:webhook, url: "https://myapp.com/bt-events"}
```

## Filtering Signals

By verbosity:
```elixir
config :jido_behaviortree, signal_verbosity: :quiet
```

By node type:
```elixir
defp should_emit_signal?(node_type) do
  node_type in [Sequence, Action, Wait]
end
```

## Performance Considerations

- :quiet verbosity - ~1% overhead
- :normal verbosity - ~3% overhead
- :verbose verbosity - ~10% overhead
- Blackboard signals - Not recommended for production

## Debugging with Signals

Enable verbose logging:
```elixir
config :jido_behaviortree,
  signal_verbosity: :verbose,
  emit_node_entered: true
```
```

3. **Update `mix.exs` docs groups**:
```elixir
defp docs do
  [
    main: "Jido.BehaviorTree",
    extras: [
      "guides/signals.md",
      "guides/signal-integration.md"
    ],
    groups_for_modules: [
      "Signals": [
        Jido.BehaviorTree.Signals.NodeEntered,
        Jido.BehaviorTree.Signals.NodeCompleted,
        # ... all signal modules
      ]
    ]
  ]
end
```

4. **Create example consumer**:
```elixir
# examples/signal_consumer.exs
defmodule BTSignalLogger do
  @moduledoc """
  Example signal consumer that logs behavior tree events.
  """

  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    Phoenix.PubSub.subscribe(:jido_signals, "jido_bt_events")
    {:ok, %{}}
  end

  def handle_info(%Jido.Signal{} = signal, state) do
    log_signal(signal)
    {:noreply, state}
  end

  defp log_signal(%Jido.Signal{type: "jido.bt.tree.completed"} = s) do
    Logger.info("Tree #{s.data.tree_id} completed with status #{s.data.final_status}")
  end

  defp log_signal(%Jido.Signal{type: "jido.bt.action.executed"} = s) do
    Logger.info("Action #{s.data.action_module} executed: #{s.data.status}")
  end

  defp log_signal(_signal), do: :ok
end
```

**Acceptance**:
- `mix docs` generates complete documentation
- All signal modules documented with examples
- Integration guide has working examples
- Performance characteristics documented

---

## Quality & Testing Strategy

### Test Categories

**1. Unit Tests** (Phase 1, 2)
- Signal schema validation
- Signal creation with valid/invalid data
- Signal serialization/deserialization
- Configuration access helpers

**2. Integration Tests** (Phase 3)
- End-to-end signal flow
- Directive accumulation
- Signal dispatch via AgentServer
- Configuration toggle functionality

**3. Property-Based Tests** (Phase 3)
- Signal data generation (using StreamData)
- Serialization round-trips
- Schema validation coverage

**4. Performance Tests** (Phase 3)
- Benchmark tree execution with/without signals
- Memory allocation profiling
- Signal dispatch latency

### Coverage Targets

- **Signal modules**: 100% (critical infrastructure)
- **Node execution**: 90%+ (existing + new emission code)
- **Tree execution**: 90%+ (existing + new emission code)
- **Overall**: Maintain existing coverage (additive changes)

### Quality Gates

Before marking complete:
1. All tests pass (`mix test`)
2. No compiler warnings (`mix compile --force-warnings`)
3. Dialyzer passes (`mix dialyzer`)
3. Format check passes (`mix format --check-formatted`)
5. Documentation generates (`mix docs`)
6. Benchmarks show < 5% overhead with :normal verbosity
7. Manual testing with example signal consumer

---

## Risk Assessment

### Technical Risks

**Risk 1: Performance Degradation**
- **Severity**: Medium
- **Impact**: High-frequency signal emission could slow tree execution
- **Mitigation**:
  - Configurable verbosity levels
  - Sampling option (emit every Nth tick)
  - Blackboard signals disabled by default
  - Benchmark and optimize hot paths
  - Lazy directive accumulation (no immediate dispatch)

**Risk 2: Signal Spam**
- **Severity**: High
- **Impact**: System overwhelmed by high-frequency events
- **Mitigation**:
  - Hierarchical filtering (only emit for significant nodes)
  - Completion-only mode (skip "entered" signals)
  - Sampling (emit every Nth)
  - Per-key blackboard filtering
  - Default to :quiet/:normal verbosity

**Risk 3: Breaking Existing Behavior**
- **Severity**: Low
- **Impact**: Signal emission could break existing tests or behavior
- **Mitigation**:
  - Signals are additive (no API changes)
  - Feature flag to disable completely
  - Safe signal creation (try/rescue)
  - Comprehensive test coverage

**Risk 4: Memory Leaks**
- **Severity**: Low
- **Impact**: Accumulated directives could grow unbounded
- **Mitigation**:
  - Directives are transient (cleared after each tick)
  - Tree depth limits prevent unbounded growth
  - Profile memory usage during testing

### Dependency Risks

**Risk 5: jido_signal Changes**
- **Severity**: Low
- **Impact**: Upstream changes to signal system could break compatibility
- **Mitigation**:
  - jido_signal v1.2.0 is stable
  - CloudEvents is a stable spec
  - Minimal coupling to implementation details

**Risk 6: Directive System Changes**
- **Severity**: Low
- **Impact**: Changes to Directive.Emit could affect signal dispatch
- **Mitigation**:
  - Directive.Emit is core to Jido (stable)
  - Tests verify directive execution

### Timeline Risks

**Risk 7: Underestimated Complexity**
- **Severity**: Medium
- **Impact**: Signal emission integration more complex than anticipated
- **Mitigation**:
  - Incremental phases (can stop after any phase)
  - Research phase completed (known integration points)
  - Existing patterns to follow

---

## Success Criteria

### Measurable Outcomes

1. **Functionality**:
   - All 8-10 signal types defined and validated
   - Signals emitted at correct lifecycle points
   - Directive.Emit pattern used consistently
   - Configuration options work as documented

2. **Performance**:
   - < 5% overhead with :normal verbosity
   - < 1% overhead with :quiet verbosity
   - No memory leaks (stable memory over 10k ticks)

3. **Quality**:
   - 100% test coverage for signal modules
   - 90%+ coverage for modified execution paths
   - Zero compiler warnings
   - Dialyzer clean

4. **Documentation**:
   - Complete signal catalog
   - Integration guide with examples
   - All modules documented
   - Performance characteristics documented

### Definition of Done

Item is complete when:
1. All implementation phases finished
2. All tests passing (including new signal tests)
3. Performance benchmarks meet targets
4. Documentation complete (catalog + integration guide)
5. Example signal consumer provided
6. No regressions in existing tests
7. Code review approved
8. Changelog updated

### Acceptance Testing Approach

**Manual Testing**:
1. Start example signal consumer
2. Run behavior tree agent
3. Verify signals received and logged
4. Test configuration toggles
5. Test different verbosity levels
6. Test with complex tree (nested composites)

**Automated Testing**:
1. Unit tests for all signal modules
2. Integration tests for signal flow
3. Property-based tests for validation
4. Performance benchmarks
5. Regression tests for existing behavior

**Integration Testing**:
1. Test with real Jido agent
2. Test signal consumption via PubSub
3. Test signal consumption via HTTP webhook
4. Test with multiple agents (cross-agent coordination)

---

## Dependencies & Sequencing

### Prerequisites
- None (foundational work)

### Can Be Done In Parallel
- Signal definition (Phase 1) and research completion
- Different signal modules (node, tree, blackboard) within Phase 1

### Must Follow This Sequence
1. Phase 1 (Foundation) must complete before Phase 2
2. Phase 2 (Core) must complete before Phase 3
3. Phase 3 (Integration) must complete before Phase 4

### Blocks Other Work
This work enables:
- Item 007: Create example behavior tree as Jido strategy (can demonstrate signals)
- Item 008: Create example behavior tree (can demonstrate signals)
- Future: Cross-agent coordination features
- Future: Advanced debugging tools

---

## Post-Implementation Considerations

### Future Enhancements
1. Signal routing based on agent ID
2. Signal aggregation/reduction
3. Signal replay capabilities
4. Signal-based debugging UI
5. Custom signal transformers

### Monitoring
1. Track signal emission rates in production
2. Monitor signal dispatch latency
3. Alert on abnormal signal patterns
4. Correlate with telemetry events

### Maintenance
1. Keep public signal schemas stable (semantic versioning)
2. Document any internal signal changes in changelog
3. Review signal performance quarterly
4. Gather user feedback on signal usefulness

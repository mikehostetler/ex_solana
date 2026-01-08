# Research: Define Effects for Behavior Tree Execution

**Item ID**: 005
**Date**: 2025-01-07
**State**: Researched

---

## Overview

This item involves designing a first-class set of Jido effects for behavior tree execution. The Jido codebase already has a well-established effect system with **Internal Effects** (state mutations within strategies) and **Directives** (external effects for the runtime to execute). The behavior tree implementation exists as `jido_behaviortree` but currently lacks first-class effect integration with the Jido effect system.

---

## Key Files and Their Relevance

### Core Effect Infrastructure

| File | Relevance |
|------|-----------|
| `projects/jido/lib/jodo/agent/effects.ex` | Central effect application - handles Internal effects and passes through Directives |
| `projects/jido/lib/jido/agent/internal.ex` | Internal effect definitions (SetState, ReplaceState, DeleteKeys, SetPath, DeletePath) |
| `projects/jido/lib/jido/agent/directive.ex` | External directive definitions (Emit, Error, Spawn, SpawnAgent, StopChild, Schedule, Stop, Cron, CronCancel) |
| `projects/jido/lib/jido/agent/schema.ex` | Schema utilities for agent state merging with Zoi |

### Behavior Tree Implementation

| File | Relevance |
|------|-----------|
| `projects/jido_behaviortree/lib/jido_behaviortree/strategy/behavior_tree.ex` | Jido Agent strategy that wraps behavior tree execution |
| `projects/jido_behaviortree/lib/jido_behaviortree/tick.ex` | Tick context with blackboard, agent, directives accumulation |
| `projects/jido_behaviortree/lib/jido_behaviortree/nodes/action.ex` | Action node that executes Jido actions and applies effects |
| `projects/jido_behaviortree/lib/jido_behaviortree/telemetry.ex` | Existing telemetry events for behavior tree execution |
| `projects/jido_behaviortree/lib/jido_behaviortree/blackboard.ex` | Shared state between nodes |

### Signal and Telemetry Integration

| File | Relevance |
|------|-----------|
| `projects/jido/lib/jido/signal.ex` | CloudEvents-based signal structure |
| `projects/jido/lib/jido/telemetry.ex` | Agent and strategy telemetry event handlers |
| `projects/jido/lib/jido/observe.ex` | Observability façade with span tracking |

### HTN Reference (Similar Planning System)

| File | Relevance |
|------|-----------|
| `projects/jido_htn/lib/jido_htn/planner/effect_handler.ex` | HTN effect handler for world state mutations |

---

## Existing Effect Patterns to Follow

### 1. Internal Effects (State Mutations)

Located at `projects/jido/lib/jido/agent/internal.ex:1-210`

```elixir
# Available Internal Effects:
- Internal.SetState       # Deep merge attributes into state
- Internal.ReplaceState   # Replace state wholesale
- Internal.DeleteKeys     # Remove top-level keys
- Internal.SetPath        # Set value at nested path
- Internal.DeletePath     # Delete value at nested path
```

### 2. Directives (External Effects)

Located at `projects/jido/lib/jido/agent/directive.ex:1-587`

```elixir
# Core Directives:
- Directive.Emit        # Dispatch signals via Jido.Signal.Dispatch
- Directive.Error       # Signal an error
- Directive.Spawn       # Spawn generic BEAM child process
- Directive.SpawnAgent  # Spawn child Jido agent with hierarchy tracking
- Directive.StopChild   # Gracefully stop tracked child agent
- Directive.Schedule    # Schedule delayed message
- Directive.Stop        # Stop agent process
- Directive.Cron        # Recurring scheduled execution
- Directive.CronCancel  # Cancel cron job
```

### 3. Action Execution with Effects

Located at `projects/jido/lib/jido/agent/effects.ex:27-31`

```elixir
def apply_result(%Agent{} = agent, result) when is_map(result) do
  new_state = Jido.Agent.State.merge(agent.state, result)
  %{agent | state: new_state}
end
```

---

## Integration Points

### 1. BehaviorTree Strategy Integration

The behavior tree integrates with Jido agents via the strategy pattern at:

`projects/jido_behaviortree/lib/jido_behaviortree/strategy/behavior_tree.ex:99-116`

Strategy state is stored in `agent.state.__strategy__.bt` with:
- `tree` - The behavior tree
- `blackboard` - Shared state between nodes
- `status` - Current execution status (`:idle`, `:running`, `:success`, `:failure`)
- `tick_count` - Number of ticks executed
- `last_result` - Result from last tick
- `error` - Last error if any

### 2. Tick Context with Directive Accumulation

Located at `projects/jido_behaviortree/lib/jido_behaviortree/tick.ex:15-44`

The Tick structure already includes:
- `blackboard` - Shared state
- `agent` - The Jido agent
- `directives` - Accumulated directives (default: `[]`)
- `context` - Execution context from strategy
- `timestamp` - Tick creation time
- `sequence` - Tick sequence number

Helper methods at lines 241-266:
- `update_agent/2` - Updates agent in tick
- `append_directives/2` - Appends directives to tick's directive list
- `apply_agent_update/3` - Convenience for updating agent and appending directives

### 3. Action Node Effect Handling

Located at `projects/jido_behaviortree/lib/jido_behaviortree/nodes/action.ex:120-184`

The Action node already handles Jido effects:
1. Resolves params from blackboard
2. Builds Jido Instruction with agent state context
3. Executes via `Jido.Exec.run/1`
4. Applies results and effects via `Jido.Agent.Effects`
5. Accumulates directives on the tick
6. Updates blackboard with `last_result`

---

## Recommended Behavior Tree Effects

Based on existing patterns, behavior tree effects should include:

### Node-Level Effects
- **TickEffect** - Record node tick execution with status
- **NodeStatusEffect** - Track node status transitions
- **BlackboardReadEffect** - Blackboard read operations
- **BlackboardWriteEffect** - Blackboard write operations
- **NodeErrorEffect** - Node execution errors

### Tree-Level Effects
- **TreeTickEffect** - Tree-level tick lifecycle
- **TreeStatusEffect** - Tree status transitions
- **TreeCompletedEffect** - Tree completion with final status

### Integration Effects
- **EmitSignalEffect** - Emit signals for BT events
- **TelemetryEffect** - Emit telemetry events
- **DirectOutputEffect** - Pass directives to runtime

---

## Telemetry Events

### Existing Behavior Tree Telemetry

Located at `projects/jido_behaviortree/lib/jido_behaviortree/telemetry.ex:23-121`:

```elixir
# Node Events
[:jido, :bt, :node, :tick, :start]
[:jido, :bt, :node, :tick, :stop]
[:jido, :bt, :node, :tick, :exception]
[:jido, :bt, :node, :halt, :start]
[:jido, :bt, :node, :halt, :stop]
[:jido, :bt, :node, :halt, :exception]
```

### Jido Agent/Strategy Telemetry

Located at `projects/jido/lib/jido/telemetry.ex:10-44`:

```elixir
# Strategy Events
[:jido, :agent, :strategy, :init, :start/stop/exception]
[:jido, :agent, :strategy, :cmd, :start/stop/exception]
[:jido, :agent, :strategy, :tick, :start/stop/exception]
```

---

## Signal Type Naming Convention

Signals follow CloudEvents v1.0.2 specification at `projects/jido/lib/jido/signal.ex:1-462`:

```elixir
# Signal type naming convention:
<domain>.<entity>.<action>[.<qualifier>]

# Examples for behavior trees:
"jido.bt.node.tick.started"
"jido.bt.blackboard.updated"
"jido.bt.tree.completed"
"jido.bt.node.status.changed"
```

---

## Documentation References

| File | Description |
|------|-------------|
| `projects/jido/guides/directives.md` | Complete directive guide |
| `projects/jido/guides/strategies.md` | Strategy implementation guide |
| `projects/jido/README.md` | Jido core framework overview |
| `projects/jido_behaviortree/README.md` | Behavior tree package overview |

---

## Key Implementation Considerations

1. **Follow the Internal/Directive separation**: Internal effects modify strategy state; directives describe external effects

2. **Use Zoi schemas for type safety**: All effects should have Zoi schemas like existing directives

3. **Emit telemetry events**: Follow the existing pattern at `projects/jido/lib/jido/telemetry.ex`

4. **Accumulate directives on Tick**: The Tick already has directive accumulation - use it

5. **Apply effects via Jido.Agent.Effects**: Don't bypass the central effect handler

6. **Signal type naming**: Use `jido.bt.*` prefix for behavior tree signals

7. **Strategy state storage**: Strategy-specific state goes in `agent.state.__strategy__`

8. **Helper constructors**: Provide convenient constructors like `Directive.emit/2` for commonly used effects

---

## Files Identified: 18

- `projects/jido/lib/jido/agent/effects.ex`
- `projects/jido/lib/jido/agent/internal.ex`
- `projects/jido/lib/jido/agent/directive.ex`
- `projects/jido/lib/jido/agent/schema.ex`
- `projects/jido_behaviortree/lib/jido_behaviortree/strategy/behavior_tree.ex`
- `projects/jido_behaviortree/lib/jido_behaviortree/tick.ex`
- `projects/jido_behaviortree/lib/jido_behaviortree/nodes/action.ex`
- `projects/jido_behaviortree/lib/jido_behaviortree/telemetry.ex`
- `projects/jido_behaviortree/lib/jido_behaviortree/blackboard.ex`
- `projects/jido/lib/jido/signal.ex`
- `projects/jido/lib/jido/telemetry.ex`
- `projects/jido/lib/jido/observe.ex`
- `projects/jido_htn/lib/jido_htn/planner/effect_handler.ex`
- `projects/jido/guides/directives.md`
- `projects/jido/guides/strategies.md`
- `projects/jido/README.md`
- `projects/jido_behaviortree/README.md`
- `projects/jido/lib/jido/agent.ex`

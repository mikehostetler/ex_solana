# Research: Define Signals for Multi-Agent Coordination

## Overview

This item introduces HTN-specific signals for multi-agent coordination and higher-level orchestration. The goal is to expose meaningful events so that other agents or supervisors can observe, coordinate, and adjust behavior.

## Research Summary

### Current State of jido_htn

**No existing signal/event infrastructure** exists in jido_htn. The planner operates silently without emitting any events for external observation.

### Jido Ecosystem Signal Infrastructure

The Jido ecosystem has a **robust signal system** already in place:

1. **Jido.Signal** - CloudEvents v1.0.2 compliant signals (`projects/jido/lib/jido/signal.ex`)
2. **JidoSignal.Bus** - Message bus with pub/sub, persistence, and middleware (`projects/jido_signal/lib/jido_signal/bus.ex`)
3. **JidoSignal.Router** - Pattern-based signal routing with priorities (`projects/jido_signal/lib/jido_signal/router.ex`)
4. **AgentServer.SignalRouter** - Multi-agent signal coordination (`projects/jido/lib/jido/agent_server/signal_router.ex`)

### Signal Type Naming Convention

```
<domain>.<entity>.<action>[.<qualifier>]

Examples:
- "htn.plan.created"
- "htn.task.started"
- "htn.method.completed"
- "htn.primitive.executed"
```

## Proposed Signal Definitions

### Planning Lifecycle Signals

| Signal Type | Description | Data Payload |
|------------|-------------|--------------|
| `htn.plan.starting` | Plan generation initiated | `{domain, world_state, root_tasks}` |
| `htn.plan.created` | Plan successfully generated | `{plan, final_state, mtr}` |
| `htn.plan.failed` | Plan generation failed | `{reason, debug_tree}` |
| `htn.plan.timeout` | Planning timeout exceeded | `{timeout_ms, partial_tree}` |

### Task Processing Signals

| Signal Type | Description | Data Payload |
|------------|-------------|--------------|
| `htn.task.starting` | Task processing begins | `{task_name, world_state}` |
| `htn.task.completed` | Task completed successfully | `{task_name, result, new_state}` |
| `htn.task.failed` | Task execution failed | `{task_name, reason}` |
| `htn.task.decomposed` | Compound task decomposed | `{task_name, method_name, subtasks}` |

### Method Selection Signals

| Signal Type | Description | Data Payload |
|------------|-------------|--------------|
| `htn.method.evaluating` | Evaluating method conditions | `{task_name, method_name}` |
| `htn.method.selected` | Method chosen for execution | `{task_name, method_name, priority}` |
| `htn.method.precondition_failed` | Method precondition not met | `{task_name, method_name, condition}` |
| `htn.method.failed` | Method execution failed | `{task_name, method_name, reason}` |

### Error and Dead-end Signals

| Signal Type | Description | Data Payload |
|------------|-------------|--------------|
| `htn.dead_end.reached` | Planning path exhausted | `{path, reason, alternatives}` |
| `htn.replan.required` | Replanning needed | `{current_plan, failure_reason}` |
| `htn.recursion.limit` | Max recursion depth reached | `{current_depth, limit}` |

### Multi-Agent Coordination Signals

| Signal Type | Description | Data Payload |
|------------|-------------|--------------|
| `htn.agent.delegating` | Delegating task to another agent | `{task, target_agent, context}` |
| `htn.agent.assigned` | Task assigned by coordinator | `{task, assigned_by, priority}` |
| `htn.resource.requested` | Resource acquisition needed | `{resource_type, requested_by, purpose}` |
| `htn.resource.acquired` | Resource successfully acquired | `{resource_type, acquired_by}` |
| `htn.resource.released` | Resource released back to pool | `{resource_type, released_by}` |
| `htn.constraint.violation` | Global constraint violated | `{constraint, violated_by, severity}` |

## Files Requiring Changes

### 1. New Files to Create

| File | Purpose |
|------|---------|
| `lib/jido_htn/signals.ex` | Signal type definitions and constructors |
| `lib/jido_htn/signals/emitter.ex` | Signal emission logic for planner events |
| `lib/jido_htn/planner/signals.ex` | Signal hooks for planner integration |

### 2. Existing Files to Modify

| File | Changes Required |
|------|------------------|
| `lib/jido_htn/planner.ex:37` | Emit `htn.plan.starting` at do_plan/5 entry |
| `lib/jido_htn/planner.ex:131-141` | Emit `htn.plan.created` on success |
| `lib/jido_htn/planner.ex:143-150` | Emit `htn.plan.failed` on error |
| `lib/jido_htn/planner.ex:181` | Emit `htn.recursion.limit` on max depth |
| `lib/jido_htn/planner/task_decomposer.ex:55` | Emit `htn.task.failed` for unknown tasks |
| `lib/jido_htn/planner/task_decomposer.ex:90-93` | Emit `htn.method.precondition_failed` |
| `lib/jido_htn/planner/task_decomposer.ex:106-165` | Emit method selection signals |
| `lib/jido_htn/planner/task_decomposer.ex:141-147` | Emit `htn.task.completed` on success |
| `lib/jido_htn/planner/task_decomposer.ex:157-163` | Emit `htn.method.failed` on failure |

### 3. Configuration Files

| File | Changes Required |
|------|------------------|
| `mix.exs` | Add `jido_signal` as dependency |
| `lib/jido_htn/domain.ex` | Add signal configuration to Domain schema |
| `lib/jido_htn.ex` | Export signal modules |

## Integration Points

### 1. Planner Entry Points

**File: `lib/jido_htn/planner.ex`**

```elixir
# Line 17 - Main planning entry point
def plan(domain, world_state, opts \\ [])

# Line 37 - Plan initiation
defp do_plan(domain, world_state, debug, root_tasks, current_plan_mtr)

# Line 131-141 - Success path
{:ok, plan, final_state, mtr_list, tree}

# Line 143-150 - Failure path
{:error, reason, tree}
```

### 2. Task Decomposition

**File: `lib/jido_htn/planner/task_decomposer.ex`**

```elixir
# Line 198 - Task processing start
dbug("Processing task: #{inspect(task)}")

# Line 106-165 - Method selection logic
# Multiple candidate methods evaluated here

# Line 141-147 - Method success
{:ok, new_plan, new_world_state, new_mtr, subtree}

# Line 157-163 - Method failure
{:error, reason, subtree}
```

### 3. Error Handling Paths

- **Max recursion**: `planner.ex:181`
- **Unknown tasks**: `task_decomposer.ex:55`
- **Precondition failures**: `task_decomposer.ex:90-93`

## Dependencies

### Required Additions to mix.exs

```elixir
defp deps do
  [
    {:jido_signal, "~> 0.1"},  # Signal bus infrastructure
    {:jido, "~> 0.2"}          # Core signal schemas
  ]
end
```

### Optional Enhancements

- **Telemetry integration** for metrics collection
- **Persistence layer** for signal replay
- **Middleware support** for cross-cutting concerns

## Signal Priority Recommendations

Following Jido's priority system:

| Priority Range | Use Case |
|----------------|----------|
| 50-100 | Strategy-level coordination signals |
| -25 to 25 | Agent-to-agent coordination |
| -50 to -10 | Task-level execution signals |

Example priorities:
- `htn.plan.created`: 75 (high visibility for coordinators)
- `htn.resource.requested`: 50 (coordination critical)
- `htn.task.completed`: -25 (agent internal tracking)

## Multi-Agent Coordination Patterns

### 1. Parent-Child Coordination

```elixir
# Worker signals completion to parent
{"htn.task.completed", Jido.Actions.Lifecycle.NotifyParent}

# Parent delegates subtask to child worker
{"htn.task.delegate", Jido.Actions.Lifecycle.SpawnChild}
```

### 2. Resource Coordination

```elixir
# Pub-sub for resource availability
{"htn.resource.**", {:pubsub, topic: "htn_resources"}}

# Direct resource requests
{"htn.resource.requested", ResourceManager}
```

### 3. Collaborative Planning

```elixir
# Agent requests help from specialized planner
{"htn.plan.assist", fn signal ->
  signal.data.expertise == :planning
end, ExpertPlannerAgent}

# Broadcast replanning events
{"htn.replan.required", {:pubsub, topic: "coordinator"}}
```

## Implementation Considerations

### Noise Reduction

To avoid signal flood:

1. **Batch similar events** - Aggregate task completions
2. **Sampling for high-frequency events** - Only emit every Nth event
3. **Conditional emission** - Only emit on state changes
4. **Debug vs. production modes** - Verbose signals only when debugging

### Performance Impact

1. **Async emission** - Don't block planner on signal dispatch
2. **Signal bus optimization** - Use efficient routing
3. **Optional signal subscription** - Allow disabling signals

### Backward Compatibility

1. **Opt-in signal emission** - Disabled by default
2. **Configuration flag** - `signals: true` in planner opts
3. **No breaking changes** - Existing code continues to work

## Documentation References

- **Jido Signal Guide**: `projects/jido_ai/guides/developer/05_signals.md`
- **CloudEvents Spec**: https://github.com/cloudevents/spec
- **Signal Bus**: `projects/jido_signal/lib/jido_signal/bus.ex`
- **Signal Router**: `projects/jido_signal/lib/jido_signal/router.ex`

## Next Steps

1. **Create signal module** with type definitions
2. **Add emitter logic** to key planner points
3. **Add opt-in configuration** for signal emission
4. **Write tests** for signal emission patterns
5. **Document coordination patterns** for multi-agent scenarios
6. **Create examples** showing agent coordination via signals

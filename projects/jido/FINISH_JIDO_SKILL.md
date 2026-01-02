# Finish Jido Skills Implementation Plan

## Overview

Skills are meant to be **composable capability mixins** that can be packaged and shared (e.g., "ChatSkill", "PostgresSkill", "MonitoringSkill"). The core architecture is sound, but several callbacks are defined but never wired.

## Current State

### ✅ What's Working

| Feature | Location | Notes |
|---------|----------|-------|
| State schema merging | `Agent.new/1` | Skill schemas merged under `state_key` |
| Actions aggregation | `Agent.__using__/1` | `@skill_actions` collected at compile-time |
| `router/1` | `SignalRouter.build/1` | Calls `skill.router(config)` |
| `signal_patterns` | `SignalRouter.build/1` | Fallback pattern→action cartesian product |

### ❌ Dead Code (Defined but Never Called)

| Callback | Expected Purpose |
|----------|------------------|
| `mount/2` | Initialize skill state dynamically |
| `handle_signal/2` | Pre-process signals before routing |
| `transform_result/3` | Post-process cmd/2 results |
| `child_spec/1` | Spawn supervised child processes |

---

## Design Decisions

### D1: `mount/2` semantics

**Decision**: Returns `{:ok, skill_state}` (just the skill's state slice), not a full agent.

**Rationale**: 
- Preserves clean boundary—agents own overall state shape; skills own their state slice
- Avoids cross-skill coupling and complicated merge logic
- Matches existing callback signature in `Jido.Skill`

### D2: Where to call `mount/2`

**Decision**: Call in `Agent.new/1` (pure), not `AgentServer.init/1`.

**Rationale**:
- Keeps agent initialization purely functional and re-usable outside OTP
- Process-layer concerns belong in `child_spec/1` or directives
- `mount/2` should be deterministic with no external IO

### D3: `handle_signal/2` role

**Decision**: Pre-routing hook that can override which action runs.

**Return conventions**:
- `{:ok, nil}` or `{:ok, :continue}` → normal routing
- `{:ok, {:override, action_spec}}` → use this action instead
- `{:error, reason}` → abort signal processing with error

**Rationale**:
- Fits naturally with existing architecture
- Least invasive way to give skills a say in signal→action mapping
- Doesn't touch `cmd/2` or strategies

### D4: `transform_result/3` placement

**Decision**: Wrap `AgentServer.call/3` results, not strategy internals.

**Rationale**:
- Keeps `cmd/2` pure and unchanged
- Strategy execution untouched
- Clean separation: transformation happens at process API level

### D5: `child_spec/1` return type and supervision

**Decision**: 
- Return `nil`, single `Supervisor.child_spec()`, or list of specs
- Start as linked children from `AgentServer.init/1`
- Track via `State.children`

**Rationale**:
- Lightweight approach using existing infrastructure
- Full supervision trees can be added later if needed
- Children tied to AgentServer lifetime

---

## Implementation Tasks

### Task 1: Wire `mount/2` in `Agent.new/1`

**File**: `lib/jido/agent.ex`

**Location**: Inside `new/1` function in `__using__/1` macro, after building initial state and before strategy init.

**Changes**:

```elixir
# After building initial agent with schema defaults...

agent = %Agent{
  id: id,
  name: name(),
  # ... other fields ...
  state: initial_state
}

# NEW: Run skill mount hooks (pure)
agent =
  Enum.reduce(@skill_specs, agent, fn spec, agent_acc ->
    mod = spec.module
    config = spec.config || %{}

    case mod.mount(agent_acc, config) do
      {:ok, skill_state} when is_map(skill_state) ->
        # Deep merge into skill's state slice
        current_skill_state = Map.get(agent_acc.state, spec.state_key, %{})
        merged_skill_state = Map.merge(current_skill_state, skill_state)
        new_state = Map.put(agent_acc.state, spec.state_key, merged_skill_state)
        %{agent_acc | state: new_state}

      {:ok, nil} ->
        # No changes
        agent_acc

      {:error, reason} ->
        raise Jido.Error.runtime_error(
          "Skill mount failed for #{inspect(mod)}",
          %{skill: mod, reason: reason}
        )
    end
  end)

# Then run strategy init as before
ctx = %{agent_module: __MODULE__, strategy_opts: strategy_opts()}
{initialized_agent, _directives} = strategy().init(agent, ctx)
initialized_agent
```

**Tests**: `test/jido/skill_mount_test.exs`
- Skill with custom mount populates state
- Skill mount can see previously-mounted skill state
- Skill mount error raises with clear message
- Default mount (no override) works

---

### Task 2: Wire `handle_signal/2` in `AgentServer`

**File**: `lib/jido/agent_server.ex`

**Add helper function**:

```elixir
@doc false
defp run_skill_signal_hooks(%Signal{} = signal, %State{} = state) do
  agent_module = state.agent_module

  skill_specs =
    if function_exported?(agent_module, :skill_specs, 0),
      do: agent_module.skill_specs(),
      else: []

  Enum.reduce_while(skill_specs, :continue, fn spec, acc ->
    case acc do
      {:override, _} ->
        {:halt, acc}

      :continue ->
        context = %{
          agent: state.agent,
          agent_module: agent_module,
          skill: spec.module,
          skill_spec: spec,
          config: spec.config || %{}
        }

        case spec.module.handle_signal(signal, context) do
          {:ok, {:override, action_spec}} ->
            {:halt, {:override, action_spec}}

          {:ok, _} ->
            {:cont, :continue}

          {:error, reason} ->
            error = Jido.Error.runtime_error(
              "Skill handle_signal failed",
              %{skill: spec.module, reason: reason}
            )
            {:halt, {:error, error}}
        end
    end
  end)
end
```

**Modify `process_signal/2`**:

```elixir
defp process_signal(%Signal{} = signal, %State{signal_router: router} = state) do
  start_time = System.monotonic_time()
  agent_module = state.agent_module
  # ... telemetry setup ...

  try do
    # NEW: Run skill signal hooks first
    case run_skill_signal_hooks(signal, state) do
      {:error, error} ->
        error_directive = %Directive.Error{error: error, context: :skill_handle_signal}
        case State.enqueue_all(state, signal, [error_directive]) do
          {:ok, enq_state} -> {:error, error, start_drain_if_idle(enq_state)}
          {:error, :queue_overflow} -> {:error, error, state}
        end

      {:override, action_spec} ->
        # Skill provided explicit action, bypass router
        dispatch_action(signal, action_spec, state, start_time)

      :continue ->
        # Normal routing path (existing code)
        case route_to_actions(router, signal) do
          {:ok, actions} ->
            dispatch_action(signal, actions, state, start_time)

          {:error, reason} ->
            # ... existing error handling ...
        end
    end
  catch
    # ... existing catch block ...
  end
end

# Extract common dispatch logic
defp dispatch_action(signal, action_spec, state, start_time) do
  agent_module = state.agent_module
  
  action_arg =
    case action_spec do
      [single] -> single
      list when is_list(list) -> list
      other -> other
    end

  {agent, directives} = agent_module.cmd(state.agent, action_arg)
  directives = List.wrap(directives)
  state = State.update_agent(state, agent)
  state = maybe_notify_completion_waiters(state)

  # ... telemetry ...

  case State.enqueue_all(state, signal, directives) do
    {:ok, enq_state} -> {:ok, start_drain_if_idle(enq_state)}
    {:error, :queue_overflow} -> {:error, :queue_overflow, state}
  end
end
```

**Tests**: `test/jido/agent_server/skill_signal_hooks_test.exs`
- Skill can override routed action
- Multiple skills, first override wins
- Skill returning `:continue` falls through to router
- Skill error aborts signal processing

---

### Task 3: Wire `transform_result/3` in `AgentServer.call/3`

**File**: `lib/jido/agent_server.ex`

**Add helper function**:

```elixir
@doc false
defp apply_skill_result_transforms(action, result, %State{} = state) do
  agent_module = state.agent_module

  skill_specs =
    if function_exported?(agent_module, :skill_specs, 0),
      do: agent_module.skill_specs(),
      else: []

  Enum.reduce(skill_specs, result, fn spec, acc_result ->
    context = %{
      agent: state.agent,
      agent_module: agent_module,
      skill: spec.module,
      skill_spec: spec,
      config: spec.config || %{},
      action: action
    }

    spec.module.transform_result(action, acc_result, context)
  end)
end
```

**Modify `handle_call({:signal, ...}, ...)`**:

```elixir
def handle_call({:signal, %Signal{} = signal}, _from, state) do
  {traced_signal, _ctx} = TraceContext.ensure_from_signal(signal)

  try do
    case process_signal(traced_signal, state) do
      {:ok, new_state, dispatched_action} ->
        raw_result = new_state.agent
        
        # NEW: Apply skill transforms
        final_result = apply_skill_result_transforms(
          dispatched_action,
          raw_result,
          new_state
        )
        
        {:reply, {:ok, final_result}, new_state}

      {:ok, new_state} ->
        # Fallback for cases without tracked action
        {:reply, {:ok, new_state.agent}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  after
    TraceContext.clear()
  end
end
```

**Note**: Requires `process_signal/2` to return `{:ok, state, action}` tuple. This is a small refactor to track which action was dispatched.

**Tests**: `test/jido/agent_server/skill_transform_test.exs`
- Skill can transform result before reply
- Multiple skills chain transforms
- Default transform (no override) passes through

---

### Task 4: Wire `child_spec/1` in `AgentServer.init/1`

**File**: `lib/jido/agent_server.ex`

**Add helper functions**:

```elixir
@doc false
defp start_skill_children(%State{} = state) do
  agent_module = state.agent_module

  skill_specs =
    if function_exported?(agent_module, :skill_specs, 0),
      do: agent_module.skill_specs(),
      else: []

  Enum.reduce(skill_specs, state, fn spec, acc_state ->
    config = spec.config || %{}

    case spec.module.child_spec(config) do
      nil ->
        acc_state

      %{} = child_spec ->
        start_skill_child(acc_state, spec.module, child_spec)

      list when is_list(list) ->
        Enum.reduce(list, acc_state, fn cs, s ->
          start_skill_child(s, spec.module, cs)
        end)

      _other ->
        Logger.warning(
          "Invalid child_spec from skill #{inspect(spec.module)}"
        )
        acc_state
    end
  end)
end

defp start_skill_child(%State{} = state, skill_module, %{start: {m, f, a}} = spec) do
  case apply(m, f, a) do
    {:ok, pid} ->
      Process.link(pid)
      tag = {:skill, skill_module, spec[:id] || m}
      
      child_info = %ChildInfo{
        pid: pid,
        tag: tag,
        module: skill_module,
        started_at: DateTime.utc_now()
      }
      
      new_children = Map.put(state.children, tag, child_info)
      %{state | children: new_children}

    {:error, reason} ->
      Logger.error(
        "Failed to start skill child #{inspect(skill_module)}: #{inspect(reason)}"
      )
      state
  end
end

defp start_skill_child(%State{} = state, skill_module, spec) do
  Logger.warning(
    "Skill child_spec missing :start for #{inspect(skill_module)}: #{inspect(spec)}"
  )
  state
end
```

**Modify `handle_continue(:init_complete, ...)`**:

```elixir
def handle_continue(:init_complete, state) do
  # ... existing strategy init code ...

  signal_router = SignalRouter.build(state)
  state = %{state | signal_router: signal_router}

  # NEW: Start skill children
  state = start_skill_children(state)

  notify_parent_of_startup(state)
  state = start_drain_if_idle(state)

  Logger.debug("AgentServer #{state.id} initialized, status: idle")
  {:noreply, State.set_status(state, :idle)}
end
```

**Tests**: `test/jido/agent_server/skill_children_test.exs`
- Skill child started on AgentServer init
- Skill child tracked in state.children
- Skill child dies when AgentServer stops
- Multiple skill children supported

---

### Task 5: Update `Jido.Skill` Documentation

**File**: `lib/jido/skill.ex`

Update `@moduledoc` and callback docs to reflect actual behavior:

```elixir
@moduledoc """
A Skill is a composable capability that can be attached to an agent.

Skills encapsulate:
- A set of actions the agent can perform
- State schema for skill-specific data (nested under `state_key`)
- Configuration schema for per-agent customization
- Signal routing rules
- Optional lifecycle hooks and child processes

## Lifecycle

1. **Compile-time**: Skill is declared in agent's `skills:` option
2. **Agent.new/1**: `mount/2` is called to initialize skill state
3. **AgentServer.init/1**: `child_spec/1` processes are started
4. **Signal processing**: `handle_signal/2` runs before routing
5. **After cmd/2**: `transform_result/3` wraps results (call only)

## Example Skill

    defmodule MyApp.ChatSkill do
      use Jido.Skill,
        name: "chat",
        state_key: :chat,
        actions: [MyApp.Actions.SendMessage, MyApp.Actions.ListHistory],
        schema: Zoi.object(%{
          messages: Zoi.list(Zoi.any()) |> Zoi.default([]),
          model: Zoi.string() |> Zoi.default("gpt-4")
        }),
        signal_patterns: ["chat.*"]

      @impl Jido.Skill
      def mount(agent, config) do
        # Custom initialization beyond schema defaults
        {:ok, %{initialized_at: DateTime.utc_now()}}
      end

      @impl Jido.Skill
      def router(config) do
        [
          {"chat.send", MyApp.Actions.SendMessage},
          {"chat.history", MyApp.Actions.ListHistory}
        ]
      end
    end

## Using Skills

    defmodule MyAgent do
      use Jido.Agent,
        name: "my_agent",
        skills: [
          MyApp.ChatSkill,
          {MyApp.DatabaseSkill, %{pool_size: 5}}
        ]
    end
"""
```

---

### Task 6: Update Callback Return Types

**File**: `lib/jido/skill.ex`

Clarify `child_spec/1` return type:

```elixir
@doc """
Returns child specification(s) for supervised processes.

Called during `AgentServer.init/1`. Returned processes are linked
to the AgentServer and tracked in its state.

## Return Values

- `nil` - No child processes needed
- `Supervisor.child_spec()` - Single child process
- `[Supervisor.child_spec()]` - Multiple child processes

## Example

    def child_spec(config) do
      %{
        id: MyWorker,
        start: {MyWorker, :start_link, [config]}
      }
    end
"""
@callback child_spec(config :: map()) ::
  nil | Supervisor.child_spec() | [Supervisor.child_spec()]
```

---

## Test Plan

### Unit Tests

| Test File | Coverage |
|-----------|----------|
| `test/jido/skill_test.exs` | Existing + mount integration |
| `test/jido/agent_skill_integration_test.exs` | Full lifecycle tests |

### New Test Files

| Test File | Purpose |
|-----------|---------|
| `test/jido/skill_mount_test.exs` | mount/2 in Agent.new/1 |
| `test/jido/agent_server/skill_hooks_test.exs` | handle_signal, transform_result |
| `test/jido/agent_server/skill_children_test.exs` | child_spec lifecycle |

### Integration Test Scenarios

1. **Chat Skill**: mount initializes conversation, router handles chat.*, transform adds metadata
2. **Database Skill**: child_spec starts connection pool, mount validates config
3. **Monitoring Skill**: handle_signal intercepts all signals for logging

---

## Migration Notes

### Breaking Changes

None expected. All callbacks have default implementations that maintain current behavior:
- `mount/2` returns `{:ok, %{}}`
- `handle_signal/2` returns `{:ok, nil}` (continue)
- `transform_result/3` returns result unchanged
- `child_spec/1` returns `nil`

### Deprecations

None required.

---

## Future Enhancements (Not in Scope)

1. **Runtime skill attachment**: Dynamically add/remove skills after agent creation
2. **Skill dependencies**: Declare that SkillA requires SkillB
3. **Per-skill supervisors**: Full OTP supervision trees per skill
4. **Skill middleware**: Chain multiple handle_signal hooks with explicit ordering
5. **Skill discovery**: Registry for installed skills with introspection

---

## Effort Estimate

| Task | Effort |
|------|--------|
| Task 1: mount/2 | 2-3 hours |
| Task 2: handle_signal/2 | 3-4 hours |
| Task 3: transform_result/3 | 2-3 hours |
| Task 4: child_spec/1 | 2-3 hours |
| Task 5-6: Documentation | 1-2 hours |
| Testing | 4-6 hours |
| **Total** | **1.5-2 days** |

---

## Success Criteria

- [ ] All 4 callbacks are wired and functional
- [ ] Existing tests pass (no regressions)
- [ ] New tests cover all callback paths
- [ ] Documentation reflects actual behavior
- [ ] Example skill demonstrates full lifecycle
- [ ] `mix quality` passes

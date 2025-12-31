# Jido Agent Module - Production Readiness Review

**Date:** 2024-12-31  
**Scope:** `lib/jido/agent.ex` and `lib/jido/agent/*`

---

## Executive Summary

The Agent module architecture is **sound and production-ready** for the Direct strategy path. The core pattern (immutable Agent struct + `cmd/2` returning `{agent, directives}`) is well-designed and properly separated.

**Key findings:**
- ✅ Core architecture is clean and well-documented
- ⚠️ Code duplication between strategies needs extraction
- ⚠️ Deprecated `Strategy.Public` still referenced in public API
- ⚠️ Significant test coverage gaps in helper modules
- ⚠️ FSM strategy is untested (0% coverage) - decide: supported or experimental?

**Estimated cleanup effort:** 6-10 hours total

---

## 1. Deprecated Code Cleanup

### Issue: `Strategy.Public` still referenced in `agent.ex`

**Location:** `lib/jido/agent.ex` lines 520-526

```elixir
# Current (deprecated reference)
@doc """
Returns a `Jido.Agent.Strategy.Public` struct with:
...
"""
@spec strategy_snapshot(Agent.t()) :: Jido.Agent.Strategy.Public.t()
def strategy_snapshot(%Agent{} = agent) do
```

**Fix:**

```elixir
@doc """
Returns a stable, public view of the strategy's execution state.

Use this instead of inspecting `agent.state.__strategy__` directly.
Returns a `Jido.Agent.Strategy.Snapshot` struct with:
- `status` - Coarse execution status
- `done?` - Whether strategy reached terminal state
- `result` - Main output if any
- `details` - Additional strategy-specific metadata
"""
@spec strategy_snapshot(Agent.t()) :: Jido.Agent.Strategy.Snapshot.t()
def strategy_snapshot(%Agent{} = agent) do
```

**Effort:** S (<1h)

---

## 2. Code Duplication

### Issue: `apply_result/2` and `apply_effects/2` duplicated

**Locations:**
- `lib/jido/agent/strategy/direct.ex` lines 47-82
- `lib/jido/agent/strategy/fsm.ex` lines 130-151

**Problem:** The FSM implementation is missing `SetPath` and `DeletePath` handling, creating inconsistent behavior across strategies.

### Recommended Fix: Create `Jido.Agent.Effects` module

```elixir
defmodule Jido.Agent.Effects do
  @moduledoc """
  Centralized effect application for strategies.
  
  Separates internal effects (state mutations) from external directives.
  All strategies should use these helpers to ensure consistent behavior.
  """
  
  alias Jido.Agent
  alias Jido.Agent.Internal

  @spec apply_result(Agent.t(), map()) :: Agent.t()
  def apply_result(%Agent{} = agent, result) when is_map(result) do
    new_state = Jido.Agent.State.merge(agent.state, result)
    %{agent | state: new_state}
  end

  @spec apply_effects(Agent.t(), [struct()]) :: {Agent.t(), [struct()]}
  def apply_effects(%Agent{} = agent, effects) do
    Enum.reduce(effects, {agent, []}, fn
      %Internal.SetState{attrs: attrs}, {a, directives} ->
        new_state = Jido.Agent.State.merge(a.state, attrs)
        {%{a | state: new_state}, directives}

      %Internal.ReplaceState{state: new_state}, {a, directives} ->
        {%{a | state: new_state}, directives}

      %Internal.DeleteKeys{keys: keys}, {a, directives} ->
        new_state = Map.drop(a.state, keys)
        {%{a | state: new_state}, directives}

      %Internal.SetPath{path: path, value: value}, {a, directives} ->
        new_state = deep_put_in(a.state, path, value)
        {%{a | state: new_state}, directives}

      %Internal.DeletePath{path: path}, {a, directives} ->
        {_, new_state} = pop_in(a.state, path)
        {%{a | state: new_state}, directives}

      # Any other struct is an external directive
      %_{} = directive, {a, directives} ->
        {a, directives ++ [directive]}
    end)
  end

  defp deep_put_in(map, [key], value), do: Map.put(map, key, value)
  defp deep_put_in(map, [key | rest], value) do
    nested = Map.get(map, key, %{})
    Map.put(map, key, deep_put_in(nested, rest, value))
  end
end
```

**Effort:** M (1-3h)

---

## 3. Test Coverage Gaps

### Current Coverage (from `mix test test/jido/agent_test.exs --cover`)

| File | Coverage | Status |
|------|----------|--------|
| `lib/jido/agent.ex` | 100% | ✅ Good |
| `lib/jido/agent/strategy/direct.ex` | 100% | ✅ Good |
| `lib/jido/agent/state.ex` | 80% | ⚠️ Acceptable |
| `lib/jido/agent/strategy.ex` | 27.2% | ❌ Needs tests |
| `lib/jido/agent/schema.ex` | 12.8% | ❌ Needs tests |
| `lib/jido/agent/directive.ex` | 9.5% | ❌ Needs tests |
| `lib/jido/agent/internal.ex` | 0% | ❌ Needs tests |
| `lib/jido/agent/strategy/state.ex` | 0% | ❌ Needs tests |
| `lib/jido/agent/strategy/fsm.ex` | 0% | ❌ Decision needed |

### Recommended Tests to Add

#### 3.1 `test/jido/agent/strategy_state_test.exs` (new file)

```elixir
defmodule JidoTest.Agent.StrategyStateTest do
  use ExUnit.Case, async: true
  
  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState
  
  describe "key/0" do
    test "returns :__strategy__" do
      assert StratState.key() == :__strategy__
    end
  end
  
  describe "get/2" do
    test "returns default when no strategy state" do
      {:ok, agent} = Agent.new(%{id: "test"})
      assert StratState.get(agent) == %{}
      assert StratState.get(agent, %{foo: :bar}) == %{foo: :bar}
    end
    
    test "returns strategy state when present" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{__strategy__: %{status: :running}}})
      assert StratState.get(agent) == %{status: :running}
    end
  end
  
  describe "put/2" do
    test "writes under __strategy__ key" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{other: :value}})
      updated = StratState.put(agent, %{status: :running})
      assert updated.state.__strategy__ == %{status: :running}
      assert updated.state.other == :value
    end
  end
  
  describe "status/1" do
    test "returns :idle by default" do
      {:ok, agent} = Agent.new(%{id: "test"})
      assert StratState.status(agent) == :idle
    end
    
    test "returns stored status" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{__strategy__: %{status: :success}}})
      assert StratState.status(agent) == :success
    end
  end
  
  describe "terminal?/1" do
    test "returns true for :success and :failure" do
      {:ok, agent} = Agent.new(%{id: "test"})
      assert StratState.terminal?(StratState.set_status(agent, :success)) == true
      assert StratState.terminal?(StratState.set_status(agent, :failure)) == true
    end
    
    test "returns false for other statuses" do
      {:ok, agent} = Agent.new(%{id: "test"})
      assert StratState.terminal?(agent) == false
      assert StratState.terminal?(StratState.set_status(agent, :running)) == false
    end
  end
  
  describe "active?/1" do
    test "returns true for :running and :waiting" do
      {:ok, agent} = Agent.new(%{id: "test"})
      assert StratState.active?(StratState.set_status(agent, :running)) == true
      assert StratState.active?(StratState.set_status(agent, :waiting)) == true
    end
  end
  
  describe "clear/1" do
    test "resets strategy state to empty map" do
      {:ok, agent} = Agent.new(%{id: "test", state: %{__strategy__: %{status: :running}, other: :value}})
      cleared = StratState.clear(agent)
      assert cleared.state.__strategy__ == %{}
      assert cleared.state.other == :value
    end
  end
end
```

**Effort:** S (<1h)

#### 3.2 `test/jido/agent/directive_test.exs` (new file)

```elixir
defmodule JidoTest.Agent.DirectiveTest do
  use ExUnit.Case, async: true
  
  alias Jido.Agent.Directive
  
  describe "emit/2" do
    test "creates Emit directive without dispatch" do
      signal = %{type: "test"}
      directive = Directive.emit(signal)
      assert %Directive.Emit{signal: ^signal, dispatch: nil} = directive
    end
    
    test "creates Emit directive with dispatch config" do
      signal = %{type: "test"}
      directive = Directive.emit(signal, {:pubsub, topic: "events"})
      assert directive.dispatch == {:pubsub, topic: "events"}
    end
  end
  
  describe "error/2" do
    test "creates Error directive" do
      error = Jido.Error.validation_error("test")
      directive = Directive.error(error, :normalize)
      assert %Directive.Error{error: ^error, context: :normalize} = directive
    end
    
    test "context defaults to nil" do
      error = Jido.Error.validation_error("test")
      directive = Directive.error(error)
      assert directive.context == nil
    end
  end
  
  describe "spawn/2" do
    test "creates Spawn directive" do
      spec = {MyWorker, []}
      directive = Directive.spawn(spec, :worker_1)
      assert %Directive.Spawn{child_spec: ^spec, tag: :worker_1} = directive
    end
  end
  
  describe "spawn_agent/3" do
    test "creates SpawnAgent directive" do
      directive = Directive.spawn_agent(MyAgent, :child_1, opts: %{id: "custom"}, meta: %{role: :worker})
      assert %Directive.SpawnAgent{agent: MyAgent, tag: :child_1} = directive
      assert directive.opts == %{id: "custom"}
      assert directive.meta == %{role: :worker}
    end
  end
  
  describe "stop_child/2" do
    test "creates StopChild directive" do
      directive = Directive.stop_child(:child_1, :shutdown)
      assert %Directive.StopChild{tag: :child_1, reason: :shutdown} = directive
    end
  end
  
  describe "schedule/2" do
    test "creates Schedule directive" do
      directive = Directive.schedule(5000, :timeout)
      assert %Directive.Schedule{delay_ms: 5000, message: :timeout} = directive
    end
  end
  
  describe "stop/1" do
    test "creates Stop directive" do
      directive = Directive.stop(:shutdown)
      assert %Directive.Stop{reason: :shutdown} = directive
    end
    
    test "defaults to :normal reason" do
      directive = Directive.stop()
      assert directive.reason == :normal
    end
  end
  
  describe "emit_to_pid/3" do
    test "creates Emit directive with pid dispatch" do
      signal = %{type: "test"}
      pid = self()
      directive = Directive.emit_to_pid(signal, pid)
      assert %Directive.Emit{signal: ^signal} = directive
      assert {:pid, opts} = directive.dispatch
      assert opts[:target] == pid
    end
  end
  
  describe "emit_to_parent/3" do
    test "returns nil when no parent" do
      {:ok, agent} = Jido.Agent.new(%{id: "test"})
      assert Directive.emit_to_parent(agent, %{type: "test"}) == nil
    end
    
    test "creates Emit directive when parent exists" do
      parent_pid = self()
      parent_ref = %Jido.AgentServer.ParentRef{pid: parent_pid, id: "parent", tag: :child}
      {:ok, agent} = Jido.Agent.new(%{id: "test", state: %{__parent__: parent_ref}})
      signal = %{type: "test"}
      directive = Directive.emit_to_parent(agent, signal)
      assert %Directive.Emit{signal: ^signal} = directive
      assert {:pid, opts} = directive.dispatch
      assert opts[:target] == parent_pid
    end
  end
end
```

**Effort:** S-M (1-2h)

#### 3.3 `test/jido/agent/internal_test.exs` (new file)

```elixir
defmodule JidoTest.Agent.InternalTest do
  use ExUnit.Case, async: true
  
  alias Jido.Agent.Internal
  
  describe "set_state/1" do
    test "creates SetState effect" do
      effect = Internal.set_state(%{status: :running})
      assert %Internal.SetState{attrs: %{status: :running}} = effect
    end
  end
  
  describe "replace_state/1" do
    test "creates ReplaceState effect" do
      effect = Internal.replace_state(%{new: :state})
      assert %Internal.ReplaceState{state: %{new: :state}} = effect
    end
  end
  
  describe "delete_keys/1" do
    test "creates DeleteKeys effect" do
      effect = Internal.delete_keys([:temp, :cache])
      assert %Internal.DeleteKeys{keys: [:temp, :cache]} = effect
    end
  end
  
  describe "set_path/2" do
    test "creates SetPath effect" do
      effect = Internal.set_path([:config, :timeout], 5000)
      assert %Internal.SetPath{path: [:config, :timeout], value: 5000} = effect
    end
  end
  
  describe "delete_path/1" do
    test "creates DeletePath effect" do
      effect = Internal.delete_path([:temp, :cache])
      assert %Internal.DeletePath{path: [:temp, :cache]} = effect
    end
  end
end
```

**Effort:** S (<1h)

#### 3.4 `test/jido/agent/schema_test.exs` (new file)

```elixir
defmodule JidoTest.Agent.SchemaTest do
  use ExUnit.Case, async: true
  
  alias Jido.Agent.Schema
  
  describe "merge_with_skills/2" do
    test "nil base with no skills returns nil" do
      assert Schema.merge_with_skills(nil, []) == nil
    end
    
    test "base schema with no skills returns base" do
      base = Zoi.object(%{mode: Zoi.atom()})
      assert Schema.merge_with_skills(base, []) == base
    end
    
    test "nil base with skills returns skill fields only" do
      skill_spec = %Jido.Skill.Spec{
        module: MySkill,
        name: "my_skill",
        state_key: :my_skill,
        schema: Zoi.object(%{count: Zoi.integer()}),
        actions: [],
        config: %{}
      }
      result = Schema.merge_with_skills(nil, [skill_spec])
      assert result
    end
  end
  
  describe "known_keys/1" do
    test "returns empty list for nil" do
      assert Schema.known_keys(nil) == []
    end
    
    test "returns keys from Zoi object" do
      schema = Zoi.object(%{status: Zoi.atom(), count: Zoi.integer()})
      keys = Schema.known_keys(schema)
      assert :status in keys
      assert :count in keys
    end
  end
  
  describe "defaults_from_zoi_schema/1" do
    test "returns empty map for nil" do
      assert Schema.defaults_from_zoi_schema(nil) == %{}
    end
    
    test "extracts defaults from Zoi object" do
      schema = Zoi.object(%{
        status: Zoi.atom() |> Zoi.default(:idle),
        count: Zoi.integer()
      })
      defaults = Schema.defaults_from_zoi_schema(schema)
      assert defaults == %{status: :idle}
    end
  end
end
```

**Effort:** S-M (1-2h)

---

## 4. FSM Strategy Decision

### Current State
- 0% test coverage
- Marked as "demonstrates" in docs
- Missing `SetPath`/`DeletePath` handling (inconsistent with Direct)

### Options

#### Option A: Mark as Experimental (Recommended for 1.0)
Add explicit documentation:

```elixir
@moduledoc """
A finite state machine execution strategy using Fsmx.

> **⚠️ Experimental:** This strategy is provided as an example/demonstration.
> Its API may change in future versions. For production use, prefer
> `Jido.Agent.Strategy.Direct` or implement a custom strategy.
...
"""
```

**Effort:** S (<30m)

#### Option B: Promote to Supported
1. Add comprehensive tests
2. Fix effect handling to use shared `Jido.Agent.Effects`
3. Ensure snapshot/status mapping is complete

**Effort:** M-L (3-6h)

---

## 5. Minor API/Doc Fixes

### 5.1 Fix type spec for `Directive.error/2`

**Current:** `@spec error(term(), atom()) :: Error.t()`  
**Issue:** `context` defaults to `nil`, not an atom

**Fix:**
```elixir
@spec error(term(), atom() | nil) :: Error.t()
def error(error, context \\ nil) do
```

### 5.2 Clarify `spawn_agent/3` options in docs

The options parameter is a keyword list with `:opts` and `:meta` as map values. Clarify:

```elixir
@doc """
Creates a SpawnAgent directive for spawning child agents with hierarchy tracking.

## Options (keyword list)

- `:opts` - Map of options passed to child AgentServer
- `:meta` - Map of metadata passed to child via parent reference

## Examples

    Directive.spawn_agent(MyWorkerAgent, :worker_1)
    Directive.spawn_agent(MyWorkerAgent, :processor, opts: %{initial_state: %{batch_size: 100}})
"""
```

### 5.3 Document `Jido.Exec.run/1` return shape expectations

In `Jido.Agent.Strategy` moduledoc or Direct strategy docs, clarify:

```elixir
# Actions must return one of:
#   {:ok, result_map}
#   {:ok, result_map, effects}
#   {:error, reason}
```

---

## 6. Implementation Priority

### Phase 1: Critical (Before 1.0)
1. [ ] Fix `Strategy.Public` → `Strategy.Snapshot` references in agent.ex
2. [ ] Mark FSM as experimental OR add basic tests
3. [ ] Fix `Directive.error/2` type spec

### Phase 2: Important (Should do)
4. [ ] Create `Jido.Agent.Effects` module to centralize effect handling
5. [ ] Add tests for `Strategy.State` 
6. [ ] Add tests for `Directive` helpers
7. [ ] Add tests for `Internal` constructors

### Phase 3: Nice to Have
8. [ ] Add tests for `Agent.Schema` utilities
9. [ ] Improve doc clarity for `spawn_agent/3`
10. [ ] Add FSM comprehensive tests (if promoting to supported)

---

## 7. Files to Modify

| File | Changes |
|------|---------|
| `lib/jido/agent.ex` | Fix `strategy_snapshot` spec/docs (lines 520-526) |
| `lib/jido/agent/strategy.ex` | Keep `Public` as deprecated shim (no changes needed) |
| `lib/jido/agent/strategy/fsm.ex` | Add experimental warning to moduledoc |
| `lib/jido/agent/directive.ex` | Fix `error/2` typespec |
| `lib/jido/agent/effects.ex` | **NEW FILE** - centralized effect handling |

### New Test Files
| File | Coverage Target |
|------|-----------------|
| `test/jido/agent/strategy_state_test.exs` | `strategy/state.ex` |
| `test/jido/agent/directive_test.exs` | `directive.ex` |
| `test/jido/agent/internal_test.exs` | `internal.ex` |
| `test/jido/agent/schema_test.exs` | `schema.ex` |

---

## 8. Summary

The Jido Agent module is architecturally sound with a clean separation of concerns. The main cleanup items are:

1. **Deprecated reference cleanup** - Simple find/replace
2. **Code deduplication** - Extract shared effect handling
3. **Test coverage** - Add focused tests for helper modules
4. **Documentation** - Minor clarifications needed

**Total estimated effort: 6-10 hours**

The Direct strategy path is production-ready today. With the above cleanup, the entire Agent subsystem will be ready for 1.0 release.

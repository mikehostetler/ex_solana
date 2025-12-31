# Jido 2.0 Implementation Plan

## Overview

This plan refactors Jido from 1.x architecture (auto-started global singletons) to 2.0 architecture (user-owned, instance-scoped supervisors). Each step is atomic, implementable by a sub-agent, and must pass all tests and quality checks before proceeding.

**Verification after each step:**
```bash
mix test
mix quality  # format, credo, dialyzer
```

---

## Phase 0: Guardrails and Baseline

### Step 1: Establish CI Guardrails & Baseline
**Effort:** S (< 1 hour)

**Goal:** Ensure consistent verification commands and a clean starting point.

**Changes:**
1. Run `mix test --cover`, `mix quality` to establish baseline
2. Fix any pre-existing failures or warnings
3. Document the verification commands in this file

**Verification:**
```bash
mix test
mix quality
```

**Ripple Effects:** None

---

## Phase 1: Instance Concept & Supervisor Skeleton

### Step 2: Add Name Derivation Functions to Jido Module
**Effort:** S (< 1 hour)

**Goal:** Add helper functions for deriving per-instance process names without changing behavior.

**Changes:**
1. Add to `lib/jido.ex`:
   ```elixir
   @doc "Returns the Registry name for a Jido instance."
   def registry_name(name), do: Module.concat(name, Registry)

   @doc "Returns the AgentSupervisor name for a Jido instance."
   def agent_supervisor_name(name), do: Module.concat(name, AgentSupervisor)

   @doc "Returns the TaskSupervisor name for a Jido instance."
   def task_supervisor_name(name), do: Module.concat(name, TaskSupervisor)

   @doc "Returns the Scheduler name for a Jido instance."
   def scheduler_name(name), do: Module.concat(name, Scheduler)
   ```

**Verification:**
```bash
mix compile
mix test
mix quality
```

**Ripple Effects:** None - these are new unused functions

---

### Step 3: Add Default Instance Configuration Support
**Effort:** S (< 1 hour)

**Goal:** Allow configuration of a default Jido instance name.

**Changes:**
1. Add to `lib/jido.ex`:
   ```elixir
   @doc "Returns the configured default Jido instance."
   def default do
     Application.get_env(:jido, :default) ||
       raise ArgumentError, "Configure :jido, :default or pass instance name explicitly"
   end
   ```

2. Add to `config/config.exs` (optional, for dev/test):
   ```elixir
   config :jido, default: Jido.DefaultInstance
   ```

**Verification:**
```bash
mix compile
mix test
mix quality
```

**Ripple Effects:** None - function unused yet

---

### Step 4: Create Jido Instance Supervisor Module
**Effort:** M (1-2 hours)

**Goal:** Create `Jido` as a Supervisor that can host per-instance children.

**Changes:**
1. Modify `lib/jido.ex` to add Supervisor behavior:
   ```elixir
   use Supervisor

   def start_link(opts) do
     name = Keyword.fetch!(opts, :name)
     Supervisor.start_link(__MODULE__, opts, name: name)
   end

   def child_spec(opts) do
     name = Keyword.fetch!(opts, :name)
     %{
       id: name,
       start: {__MODULE__, :start_link, [opts]},
       type: :supervisor,
       restart: :permanent,
       shutdown: 10_000
     }
   end

   @impl true
   def init(opts) do
     name = Keyword.fetch!(opts, :name)
     # Empty children for now - will add components in later steps
     children = []
     Supervisor.init(children, strategy: :one_for_one)
   end
   ```

2. Add a simple test to verify supervisor starts:
   ```elixir
   # test/jido/supervisor_test.exs
   defmodule JidoTest.SupervisorTest do
     use ExUnit.Case, async: true

     test "starts a Jido instance supervisor" do
       name = :"test_jido_#{System.unique_integer([:positive])}"
       {:ok, pid} = Jido.start_link(name: name)
       assert is_pid(pid)
       assert Process.alive?(pid)
       Supervisor.stop(pid)
     end
   end
   ```

**Verification:**
```bash
mix test test/jido/supervisor_test.exs
mix test
mix quality
```

**Ripple Effects:** None - supervisor is standalone, not wired into application yet

---

### Step 5: Add TaskSupervisor as First Child
**Effort:** S (< 1 hour)

**Goal:** Add Task.Supervisor as the first child of Jido instance.

**Changes:**
1. Update `Jido.init/1` to include TaskSupervisor:
   ```elixir
   def init(opts) do
     name = Keyword.fetch!(opts, :name)

     children = [
       {Task.Supervisor,
        name: task_supervisor_name(name),
        max_children: Keyword.get(opts, :max_tasks, 1000)}
     ]

     Supervisor.init(children, strategy: :one_for_one)
   end
   ```

2. Add helper function:
   ```elixir
   def task_supervisor(name), do: task_supervisor_name(name)
   def task_supervisor, do: task_supervisor(default())
   ```

3. Update test to verify TaskSupervisor starts

**Verification:**
```bash
mix test test/jido/supervisor_test.exs
mix test
mix quality
```

**Ripple Effects:** None

---

### Step 6: Add Registry as Child
**Effort:** S (< 1 hour)

**Goal:** Add per-instance Registry for agent lookup.

**Changes:**
1. Update `Jido.init/1`:
   ```elixir
   children = [
     {Task.Supervisor,
      name: task_supervisor_name(name),
      max_children: Keyword.get(opts, :max_tasks, 1000)},
     {Registry, keys: :unique, name: registry_name(name)}
   ]
   ```

2. Add test verifying Registry starts and can register processes

**Verification:**
```bash
mix test test/jido/supervisor_test.exs
mix test
mix quality
```

**Ripple Effects:** None

---

### Step 7: Add DynamicSupervisor for Agents as Child
**Effort:** S (< 1 hour)

**Goal:** Add per-instance DynamicSupervisor for agent processes.

**Changes:**
1. Update `Jido.init/1`:
   ```elixir
   children = [
     {Task.Supervisor,
      name: task_supervisor_name(name),
      max_children: Keyword.get(opts, :max_tasks, 1000)},
     {Registry, keys: :unique, name: registry_name(name)},
     {DynamicSupervisor,
      name: agent_supervisor_name(name),
      strategy: :one_for_one,
      max_restarts: 1000,
      max_seconds: 5}
   ]
   ```

2. Add test verifying DynamicSupervisor is running

**Verification:**
```bash
mix test test/jido/supervisor_test.exs
mix test
mix quality
```

**Ripple Effects:** None

---

## Phase 2: Discovery as Global GenServer

### Step 8: Refactor Discovery to Supervised GenServer
**Effort:** M (2-3 hours)

**Goal:** Convert Discovery from Task-based initialization to a proper supervised GenServer.

**Changes:**
1. Update `lib/jido/discovery.ex`:
   - Convert to `use GenServer`
   - Implement `start_link/1`, `child_spec/1`
   - Move catalog building to `init/1`
   - Keep existing public API unchanged

2. Update any existing Discovery tests

**Verification:**
```bash
mix test test/jido/discovery_test.exs
mix test
mix quality
```

**Ripple Effects:** Discovery API remains the same, internal implementation changes

---

### Step 9: Update Jido.Application to Start Only Discovery
**Effort:** S (< 1 hour)

**Goal:** Simplify Jido.Application to only start the global Discovery GenServer.

**Changes:**
1. Update `lib/jido/application.ex`:
   ```elixir
   def start(_type, _args) do
     children = [
       Jido.Discovery
     ]

     Supervisor.start_link(children, 
       strategy: :one_for_one, 
       name: Jido.ApplicationSupervisor)
   end
   ```

2. Remove any other children that were previously started globally

**Verification:**
```bash
mix test
mix quality
```

**Ripple Effects:** May break tests that expect other global processes - identify and fix in next steps

---

## Phase 3: AgentServer Instance Awareness

### Step 10: Add `:jido` Option to AgentServer
**Effort:** M (2-3 hours)

**Goal:** Make AgentServer aware of which Jido instance it belongs to.

**Changes:**
1. Update `lib/jido/agent/server.ex`:
   - Add `:jido` to accepted options
   - Store `jido` instance name in server state
   - Register with instance-scoped Registry in `init/1`:
     ```elixir
     Registry.register(Jido.registry_name(jido), id, %{})
     ```

2. Keep existing behavior working when `:jido` not provided (use legacy path)

3. Update AgentServer tests to pass `:jido` option

**Verification:**
```bash
mix test test/jido/agent/server_test.exs
mix test
mix quality
```

**Ripple Effects:** Existing tests may need `:jido` option added

---

### Step 11: Add Instance-Aware Agent Lifecycle to Jido Module
**Effort:** M (2-3 hours)

**Goal:** Add `start_agent/3`, `stop_agent/2`, `whereis/2` functions to Jido.

**Changes:**
1. Add to `lib/jido.ex`:
   ```elixir
   def start_agent(name, agent, opts) when is_atom(name) do
     child_spec = {Jido.AgentServer, Keyword.merge(opts, agent: agent, jido: name)}
     DynamicSupervisor.start_child(agent_supervisor_name(name), child_spec)
   end

   def start_agent(agent, opts \\ []), do: start_agent(default(), agent, opts)

   def stop_agent(name, pid) when is_atom(name) and is_pid(pid) do
     DynamicSupervisor.terminate_child(agent_supervisor_name(name), pid)
   end

   def stop_agent(name, id) when is_atom(name) and is_binary(id) do
     case whereis(name, id) do
       nil -> {:error, :not_found}
       pid -> stop_agent(name, pid)
     end
   end

   def stop_agent(id_or_pid), do: stop_agent(default(), id_or_pid)

   def whereis(name, id) when is_atom(name) and is_binary(id) do
     case Registry.lookup(registry_name(name), id) do
       [{pid, _}] -> pid
       [] -> nil
     end
   end

   def whereis(id), do: whereis(default(), id)
   ```

2. Add tests for new functions

**Verification:**
```bash
mix test
mix quality
```

**Ripple Effects:** None - new API, existing code unchanged

---

### Step 12: Add list_agents/1 and agent_count/1 Functions
**Effort:** S (< 1 hour)

**Goal:** Add functions to list and count running agents per instance.

**Changes:**
1. Add to `lib/jido.ex`:
   ```elixir
   def list_agents(name) when is_atom(name) do
     Registry.select(
       registry_name(name),
       [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}]
     )
   end

   def list_agents, do: list_agents(default())

   def agent_count(name) when is_atom(name) do
     agent_supervisor_name(name)
     |> DynamicSupervisor.count_children()
     |> Map.get(:active, 0)
   end

   def agent_count, do: agent_count(default())
   ```

2. Add tests

**Verification:**
```bash
mix test
mix quality
```

**Ripple Effects:** None

---

### Step 13: Add Instance-Aware call/4 and cast/3 to Jido Module
**Effort:** M (1-2 hours)

**Goal:** Add signal sending functions that work with instance-scoped agents.

**Changes:**
1. Add to `lib/jido.ex`:
   ```elixir
   def call(name, server, signal, opts \\ []) when is_atom(name) do
     Jido.AgentServer.call(name, server, signal, opts)
   end

   def call(server, signal, opts \\ []) do
     Jido.AgentServer.call(server, signal, opts)
   end

   def cast(name, server, signal) when is_atom(name) do
     Jido.AgentServer.cast(name, server, signal)
   end

   def cast(server, signal), do: Jido.AgentServer.cast(server, signal)
   ```

2. Update AgentServer to handle instance-aware lookups:
   ```elixir
   def call(jido, id, signal, opts) when is_atom(jido) and is_binary(id) do
     case Registry.lookup(Jido.registry_name(jido), id) do
       [{pid, _}] -> call(pid, signal, opts)
       [] -> {:error, :not_found}
     end
   end
   ```

3. Add tests

**Verification:**
```bash
mix test
mix quality
```

**Ripple Effects:** None - new API alongside existing

---

### Step 14: Add state/1 and status/1 Delegates
**Effort:** S (< 1 hour)

**Goal:** Add convenience delegates for agent state inspection.

**Changes:**
1. Add to `lib/jido.ex`:
   ```elixir
   defdelegate state(server), to: Jido.AgentServer
   defdelegate status(server), to: Jido.AgentServer
   ```

2. Add tests

**Verification:**
```bash
mix test
mix quality
```

**Ripple Effects:** None

---

## Phase 4: Per-Instance Scheduler

### Step 15: Create Jido.Scheduler Module
**Effort:** M (2-3 hours)

**Goal:** Create a per-instance Quantum-based scheduler.

**Changes:**
1. Create `lib/jido/scheduler.ex`:
   ```elixir
   defmodule Jido.Scheduler do
     use Quantum, otp_app: :jido

     def child_spec(opts) do
       name = Keyword.fetch!(opts, :name)
       jobs = Keyword.get(opts, :jobs, [])

       %{
         id: name,
         start: {__MODULE__, :start_link, [[name: name, jobs: jobs]]},
         type: :supervisor,
         restart: :permanent
       }
     end
   end
   ```

2. Add tests for scheduler

**Verification:**
```bash
mix test
mix quality
```

**Ripple Effects:** None - new module

---

### Step 16: Add Scheduler to Jido Instance Children
**Effort:** S (< 1 hour)

**Goal:** Start Scheduler as part of each Jido instance.

**Changes:**
1. Update `Jido.init/1`:
   ```elixir
   children = [
     {Task.Supervisor, name: task_supervisor_name(name), ...},
     {Registry, keys: :unique, name: registry_name(name)},
     {DynamicSupervisor, name: agent_supervisor_name(name), ...},
     {Jido.Scheduler, name: scheduler_name(name), jobs: Keyword.get(opts, :scheduler_jobs, [])}
   ]
   ```

2. Add helper:
   ```elixir
   def scheduler(name), do: scheduler_name(name)
   def scheduler, do: scheduler(default())
   ```

3. Update tests

**Verification:**
```bash
mix test
mix quality
```

**Ripple Effects:** None

---

## Phase 5: Discovery API Integration

### Step 17: Add Discovery Delegates to Jido Module
**Effort:** S (< 1 hour)

**Goal:** Expose Discovery functions through the main Jido module.

**Changes:**
1. Add to `lib/jido.ex`:
   ```elixir
   defdelegate list_actions(opts \\ []), to: Jido.Discovery
   defdelegate list_discovered_agents(opts \\ []), to: Jido.Discovery, as: :list_agents
   defdelegate list_sensors(opts \\ []), to: Jido.Discovery
   defdelegate list_skills(opts \\ []), to: Jido.Discovery
   ```

2. Add tests

**Verification:**
```bash
mix test
mix quality
```

**Ripple Effects:** None

---

### Step 18: Add Utility Delegates
**Effort:** S (< 1 hour)

**Goal:** Add utility function delegates to Jido module.

**Changes:**
1. Add to `lib/jido.ex`:
   ```elixir
   defdelegate generate_id(), to: Jido.Util
   ```

2. Verify Jido.Util exists with generate_id function

**Verification:**
```bash
mix test
mix quality
```

**Ripple Effects:** None

---

## Phase 6: Test Isolation Patterns

### Step 19: Create Test Helper Module
**Effort:** M (1-2 hours)

**Goal:** Create test utilities for isolated Jido instances.

**Changes:**
1. Create `test/support/jido_test_helpers.ex`:
   ```elixir
   defmodule Jido.TestHelpers do
     import ExUnit.Callbacks, only: [start_supervised: 1]

     def start_test_jido(context \\ %{}) do
       jido = :"test_jido_#{System.unique_integer([:positive])}"
       {:ok, _pid} = start_supervised({Jido, name: jido})
       Map.put(context, :jido, jido)
     end

     def start_test_agent(agent_module, opts \\ []) do
       jido = :"test_jido_#{System.unique_integer([:positive])}"
       {:ok, _} = start_supervised({Jido, name: jido})
       {:ok, pid} = Jido.start_agent(jido, agent_module, opts)
       %{jido: jido, agent_pid: pid}
     end
   end
   ```

2. Ensure it's loaded in test_helper.exs

**Verification:**
```bash
mix test
mix quality
```

**Ripple Effects:** None

---

### Step 20: Create JidoCase Test Template
**Effort:** S (< 1 hour)

**Goal:** Create an ExUnit.CaseTemplate for isolated test instances.

**Changes:**
1. Create `test/support/jido_case.ex`:
   ```elixir
   defmodule JidoCase do
     use ExUnit.CaseTemplate

     using do
       quote do
         import Jido.TestHelpers
       end
     end

     setup do
       jido = :"test_jido_#{System.unique_integer([:positive])}"
       {:ok, pid} = start_supervised({Jido, name: jido})
       %{jido: jido, jido_pid: pid}
     end
   end
   ```

2. Add a sample test using the new case template

**Verification:**
```bash
mix test
mix quality
```

**Ripple Effects:** None

---

### Step 21: Migrate First Test File to Use JidoCase
**Effort:** S (< 1 hour)

**Goal:** Demonstrate test isolation by migrating one test file.

**Changes:**
1. Pick a simple AgentServer test file
2. Convert to use `use JidoCase`
3. Update test calls to use `context.jido`

**Verification:**
```bash
mix test path/to/migrated_test.exs
mix test
mix quality
```

**Ripple Effects:** Pattern for migrating remaining tests

---

## Phase 7: Update Existing Tests

### Step 22: Migrate AgentServer Tests
**Effort:** L (3-4 hours)

**Goal:** Update all AgentServer tests to use isolated instances.

**Changes:**
1. Update each test file in `test/jido/agent/` to use JidoCase or explicit instance
2. Pass `:jido` option to AgentServer starts
3. Use instance-aware API calls

**Verification:**
```bash
mix test test/jido/agent/
mix test
mix quality
```

**Ripple Effects:** None if done correctly

---

### Step 23: Migrate Directive Tests
**Effort:** M (2-3 hours)

**Goal:** Update directive tests to use isolated instances where needed.

**Changes:**
1. Review directive tests that interact with AgentServer
2. Update to use JidoCase pattern
3. Ensure directives work with instance-scoped agents

**Verification:**
```bash
mix test test/jido/agent/directive/
mix test
mix quality
```

**Ripple Effects:** None

---

### Step 24: Migrate Integration Tests
**Effort:** M (2-3 hours)

**Goal:** Update any integration or end-to-end tests.

**Changes:**
1. Identify integration tests
2. Update to use isolated Jido instances
3. Verify tests are truly isolated (can run async)

**Verification:**
```bash
mix test
mix quality
```

**Ripple Effects:** None

---

## Phase 8: AgentPool Implementation (Optional)

### Step 25: Create Jido.AgentPool Module
**Effort:** M (3-4 hours)

**Goal:** Implement reusable agent pool for expensive-to-start agents.

**Changes:**
1. Create `lib/jido/agent_pool.ex`:
   ```elixir
   defmodule Jido.AgentPool do
     use GenServer

     def start_link(opts) do
       # Implementation
     end

     def with_agent(pool, fun) do
       # Checkout, execute, checkin
     end
   end
   ```

2. Add comprehensive tests

**Verification:**
```bash
mix test test/jido/agent_pool_test.exs
mix test
mix quality
```

**Ripple Effects:** None - new feature

---

## Phase 9: Multi-Agent Coordination

### Step 26: Add await/2 and await_child/4 Delegates
**Effort:** S (< 1 hour)

**Goal:** Add multi-agent coordination functions to Jido module.

**Changes:**
1. Verify Jido.MultiAgent module exists with these functions
2. Add to `lib/jido.ex`:
   ```elixir
   defdelegate await(server, timeout_ms \\ 10_000, opts \\ []),
     to: Jido.MultiAgent, as: :await_completion

   defdelegate await_child(server, child_tag, timeout_ms \\ 30_000, opts \\ []),
     to: Jido.MultiAgent, as: :await_child_completion
   ```

**Verification:**
```bash
mix test
mix quality
```

**Ripple Effects:** None

---

## Phase 10: Documentation & Cleanup

### Step 27: Update Module Documentation
**Effort:** M (2-3 hours)

**Goal:** Update @moduledoc and @doc for all modified modules.

**Changes:**
1. Update `lib/jido.ex` with comprehensive moduledoc showing new usage
2. Update `lib/jido/agent/server.ex` docs
3. Update `lib/jido/discovery.ex` docs
4. Add deprecation notices if applicable

**Verification:**
```bash
mix docs
mix test
mix quality
```

**Ripple Effects:** None

---

### Step 28: Update Examples
**Effort:** M (2-3 hours)

**Goal:** Update example code to use 2.0 patterns.

**Changes:**
1. Update files in `examples/` directory
2. Use `{Jido, name: MyApp.Jido}` pattern
3. Demonstrate test isolation
4. Show Phoenix integration patterns

**Verification:**
```bash
# Run example if applicable
mix test
mix quality
```

**Ripple Effects:** None

---

### Step 29: Update README and Guides
**Effort:** M (2-3 hours)

**Goal:** Update user-facing documentation.

**Changes:**
1. Update README.md with new setup pattern
2. Update guides in `guides/` directory
3. Add migration section for 1.x users

**Verification:**
```bash
mix test
mix quality
```

**Ripple Effects:** None

---

### Step 30: Final Verification & Cleanup
**Effort:** S (1 hour)

**Goal:** Final pass to ensure everything works together.

**Changes:**
1. Run full test suite with coverage
2. Run all quality checks
3. Remove any dead code from migration
4. Update CHANGELOG.md

**Verification:**
```bash
mix test --cover
mix quality
mix docs
```

**Ripple Effects:** None

---

## Summary

| Phase | Steps | Estimated Effort |
|-------|-------|------------------|
| Phase 0: Guardrails | 1 | S |
| Phase 1: Instance Concept | 2-7 | 4-5 hours |
| Phase 2: Discovery | 8-9 | 3-4 hours |
| Phase 3: AgentServer | 10-14 | 6-8 hours |
| Phase 4: Scheduler | 15-16 | 3-4 hours |
| Phase 5: Discovery API | 17-18 | 1-2 hours |
| Phase 6: Test Isolation | 19-21 | 2-3 hours |
| Phase 7: Test Migration | 22-24 | 7-10 hours |
| Phase 8: AgentPool | 25 | 3-4 hours |
| Phase 9: Multi-Agent | 26 | 1 hour |
| Phase 10: Documentation | 27-30 | 7-9 hours |
| **Total** | **30 steps** | **~4-5 days** |

---

## Key Principles

1. **One change per step** - Each step focuses on a single concern
2. **Tests pass after each step** - Never leave the codebase in a broken state
3. **Quality maintained** - Run `mix quality` after each step
4. **Incremental migration** - New API alongside old, not replacing
5. **Sub-agent friendly** - Each step can be implemented independently

---

## Breaking Changes Summary

After all steps are complete:

| Before (1.x) | After (2.0) |
|--------------|-------------|
| Auto-start in `Jido.Application` | User adds `{Jido, name: MyApp.Jido}` |
| `Jido.Registry` (global) | `MyApp.Jido.Registry` (per-instance) |
| `Jido.AgentSupervisor` (global) | `MyApp.Jido.AgentSupervisor` (per-instance) |
| `Jido.TaskSupervisor` (global) | `MyApp.Jido.TaskSupervisor` (per-instance) |
| Global scheduler | `MyApp.Jido.Scheduler` (per-instance) |
| No test isolation | Unique Jido instance per test |

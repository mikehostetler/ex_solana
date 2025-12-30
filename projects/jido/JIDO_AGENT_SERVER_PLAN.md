# Jido AgentServer V2 Implementation Plan

> Step-by-step implementation of AgentServer V2 based on JIDO_AGENT_SERVER_V2.md

**Status:** Complete  
**Last Updated:** December 2024

---

## Completed Work

The following components have already been implemented:

### ✅ Infrastructure
- `Jido.Application` - Updated with Telemetry, TaskSupervisor, Registry, AgentSupervisor
- `Jido.Supervisor` - Public API: `start_agent/2`, `stop_agent/1`, `whereis/1`, `list_agents/0`, `agent_count/0`
- `Jido.Telemetry` - Telemetry handlers for agent/strategy events

### ✅ Data Types (Zoi Schemas)
- `Jido.AgentServer.ParentRef` - Parent reference for hierarchy
- `Jido.AgentServer.ChildInfo` - Child agent tracking
- `Jido.AgentServer.Options` - Startup options with validation
- `Jido.AgentServer.State` - GenServer state with queue operations

### ✅ Directives
- `Jido.Agent.Directive` - Core directives: Emit, Error, Spawn, Schedule, Stop

### ✅ Phase 1: DirectiveExec Protocol - COMPLETED
- Protocol with `exec/3` callback in `lib/jido/agent_server/directive_exec.ex`
- Core executors for Emit, Error, Spawn, Schedule, Stop in `lib/jido/agent_server/directive_executors.ex`
- Tests: `test/jido/agent_server/directive_exec_test.exs` (14 tests)

### ✅ Phase 2: ErrorPolicy Module - COMPLETED  
- Error policy handler in `lib/jido/agent_server/error_policy.ex`
- Policies: `:log_only`, `:stop_on_error`, `{:emit_signal, cfg}`, `{:max_errors, n}`, `fun/2`
- Tests: `test/jido/agent_server/error_policy_test.exs` (12 tests)

### ✅ Phase 3: AgentServer GenServer Rewrite - COMPLETED
- Full V2 API: `start/1`, `start_link/1`, `call/3`, `cast/2`, `state/1`, `whereis/2`, `via_tuple/2`
- Internal directive queue with drain loop (self-sent `:drain` messages)
- Registry-based naming via `{:via, Registry, {Jido.Registry, id}}`
- Hierarchy support: parent monitoring, child tracking, configurable `on_parent_death`
- Backward compatibility with deprecation warnings for old API
- Tests: `test/jido/agent_server_test.exs` (78 tests covering all functionality)
- Tests: `test/jido/agent_server/hierarchy_test.exs` (13 tests for parent-child)
- Tests: `test/jido/agent_server/options_test.exs` (41 tests for options validation)

---

## Remaining Work

### ✅ Phase 4: SpawnAgent Directive - COMPLETED

**4.1 SpawnAgent Directive** - COMPLETED

File: `lib/jido/agent/directive.ex`

Added `SpawnAgent` directive with fields:
- `agent` - Agent module (atom) or pre-built agent struct
- `tag` - Tag for tracking this child
- `opts` - Additional options for child AgentServer
- `meta` - Metadata to pass to child via parent reference

Helper: `Directive.spawn_agent(agent, tag, opts \\ [])`

**4.2 SpawnAgent Executor** - COMPLETED

File: `lib/jido/agent_server/directive_executors.ex`

- Starts child agent under AgentSupervisor via `AgentServer.start/1`
- Sets parent reference on child (pid, id, tag, meta)
- Monitors child process
- Tracks child in `state.children` map via `State.add_child/3`
- Generates child ID as `"#{parent_id}/#{tag}"` unless custom ID in opts

**Tests:** `test/jido/agent_server/hierarchy_test.exs` (6 new tests)
- ✅ Spawns child agent with parent-child relationship
- ✅ Spawns child with custom ID from opts
- ✅ Passes metadata to child via parent reference  
- ✅ Spawns multiple children with different tags
- ✅ Child exit notifies parent via ChildExit signal
- ✅ Child inherits default on_parent_death: :stop

---

### ✅ Phase 5: Telemetry Integration - COMPLETED

**5.1 Add AgentServer Telemetry Events** - COMPLETED

File: `lib/jido/agent_server.ex`

Events added:
- `[:jido, :agent_server, :signal, :start]` - Signal processing started
- `[:jido, :agent_server, :signal, :stop]` - Signal processing completed with directive count
- `[:jido, :agent_server, :signal, :exception]` - Signal processing failed
- `[:jido, :agent_server, :directive, :start]` - Directive execution started
- `[:jido, :agent_server, :directive, :stop]` - Directive execution completed with result type
- `[:jido, :agent_server, :directive, :exception]` - Directive execution failed
- `[:jido, :agent_server, :queue, :overflow]` - Queue overflow detected

**5.2 Update Telemetry Module** - COMPLETED

File: `lib/jido/telemetry.ex`

- Added metrics for signal processing (count, duration, exception count)
- Added metrics for directive execution (count, duration, exception count)
- Added queue overflow counter
- Added event handlers with Logger.debug/warning output

**Tests:** `test/jido/agent_server/telemetry_test.exs` (8 tests)
- ✅ Emits start and stop events for signal processing
- ✅ Includes directive count in stop event
- ✅ Emits start and stop events for directive execution
- ✅ Reports correct directive type
- ✅ Includes agent_id and agent_module in signal events
- ✅ Includes signal_type in directive events
- ✅ Duration is positive for signal processing
- ✅ Duration is positive for directive execution

---

### ✅ Phase 6: handle_signal/2 Generation in use Jido.Agent - COMPLETED

**6.1 Update Agent Macro** - COMPLETED

File: `lib/jido/agent.ex`

Added callbacks:
- `@callback handle_signal/2` - Handles incoming signal, returns `{agent, directives}`
- `@callback signal_to_action/1` - Translates signal to action for `cmd/2`

Default implementations in `__using__` macro:
- `handle_signal/2` - Translates signal via `signal_to_action/1` then delegates to `cmd/2`
- `signal_to_action/1` - Returns `{signal.type, signal.data}` as action tuple

Both callbacks are `defoverridable` for custom implementations.

**Tests:** `test/jido/agent/signal_handling_test.exs` (12 tests)
- ✅ Default signal_to_action translation
- ✅ handle_signal delegates to cmd with translated action
- ✅ Custom handle_signal override for increment/decrement/record signals
- ✅ emit_test signal returns Emit directive
- ✅ Unknown signals fall back to super
- ✅ Multiple signals processed in sequence
- ✅ Custom signal_to_action strips prefix
- ✅ Non-matching signals use super
- ✅ Integration with AgentServer.call

---

### Phase 7: Integration & Migration

**7.1 Update Jido.Supervisor Integration**

Ensure `Jido.Supervisor.start_agent/2` works with new API:

```elixir
def start_agent(agent, opts \\ []) do
  child_spec = {Jido.AgentServer, [{:agent, agent} | opts]}
  DynamicSupervisor.start_child(Jido.AgentSupervisor, child_spec)
end
```

**7.2 Backward Compatibility Layer**

Keep old API working during transition:
- `start_link(module, opts)` → `start_link([agent: module] ++ opts)`
- `handle_signal/2` → logs deprecation, calls `cast/2`
- `handle_signal_sync/3` → logs deprecation, calls `call/3`
- `get_agent/1` → logs deprecation, calls `state/1` and extracts agent

**7.3 Documentation**

- Update moduledoc with new API
- Add migration guide in docs/
- Add examples for common patterns

**Tests:** `test/jido/agent_server/migration_test.exs`
- Old API still works
- Deprecation warnings logged
- New API preferred

---

## Test Coverage Summary

| Test File | Focus Area | Status |
|-----------|------------|--------|
| `directive_exec_test.exs` | Protocol + core implementations | ✅ 14 tests |
| `error_policy_test.exs` | All error policy types | ✅ 12 tests |
| `agent_server_test.exs` | Main GenServer behavior | ✅ 68 tests |
| `hierarchy_test.exs` | Parent-child + SpawnAgent | ✅ 17 tests |
| `options_test.exs` | Options validation | ✅ 41 tests |
| `signals_test.exs` | Internal signal modules | ✅ 11 tests |
| `telemetry_test.exs` | Event emission | ✅ 8 tests |
| `signal_handling_test.exs` | Agent signal → action translation | ✅ 12 tests |

**Total Current Tests:** 183 AgentServer-related tests passing (397 total in jido project)

---

## Implementation Order

1. ✅ **Phase 1** - DirectiveExec protocol + implementations - COMPLETED
2. ✅ **Phase 2** - ErrorPolicy module - COMPLETED
3. ✅ **Phase 3** - Rewrite AgentServer GenServer (core) - COMPLETED
4. ✅ **Phase 4** - SpawnAgent directive + executor - COMPLETED
5. ✅ **Phase 5** - Telemetry integration - COMPLETED
6. ✅ **Phase 6** - handle_signal/2 in Agent macro - COMPLETED
7. 🔜 **Phase 7** - Integration, migration, docs (optional - API is stable)

---

## File Changes Summary

### Completed Files
- ✅ `lib/jido/agent_server/directive_exec.ex` - Protocol definition
- ✅ `lib/jido/agent_server/directive_executors.ex` - Core implementations
- ✅ `lib/jido/agent_server/error_policy.ex` - Error handling
- ✅ `lib/jido/agent_server/options.ex` - Options validation
- ✅ `lib/jido/agent_server/state.ex` - State struct with queue operations
- ✅ `lib/jido/agent_server/parent_ref.ex` - Parent reference for hierarchy
- ✅ `lib/jido/agent_server/child_info.ex` - Child tracking
- ✅ `lib/jido/agent_server.ex` - Main GenServer (rewritten with telemetry)
- ✅ `lib/jido/agent/directive.ex` - Core directives including SpawnAgent
- ✅ `lib/jido/agent.ex` - handle_signal/2 and signal_to_action/1 generation
- ✅ `lib/jido/telemetry.ex` - AgentServer event handlers added
- ✅ `test/jido/agent_server_test.exs` - Main test suite
- ✅ `test/jido/agent_server/directive_exec_test.exs`
- ✅ `test/jido/agent_server/error_policy_test.exs`
- ✅ `test/jido/agent_server/hierarchy_test.exs`
- ✅ `test/jido/agent_server/options_test.exs`
- ✅ `test/jido/agent_server/telemetry_test.exs`
- ✅ `test/jido/agent/signal_handling_test.exs`

### Optional Future Work
- Migration guide in docs/
- Additional examples for common patterns

---

## Key Design Decisions

1. **Module Path**: Use `Jido.AgentServer` (not `Jido.Agent.Server`) to match existing convention
2. **State Struct**: Internal `Jido.AgentServer.State` holds everything; `.agent` field for pure agent
3. **Registry Naming**: Use `{:via, Registry, {Jido.Registry, id}}` for unique names
4. **Drain Loop**: Self-send `:drain` message, not recursion (allows other messages)
5. **Hierarchy**: Flat OTP, logical parent-child via state tracking + monitors
6. **Backward Compat**: Old API works but logs deprecation warnings

---

*Plan Version: 1.0.0*  
*Based on: JIDO_AGENT_SERVER_V2.md*

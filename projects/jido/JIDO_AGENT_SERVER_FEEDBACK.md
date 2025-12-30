# Jido.AgentServer Architectural Critique

> A deep functional programming analysis of the AgentServer implementation

---

## Executive Summary

The core separation—pure `Jido.Agent` + effectful `Jido.AgentServer`—is solid and aligns well with functional/"Elm architecture" thinking. However, several architectural weaknesses need attention:

1. **All directives execute synchronously inside the GenServer** — single-process bottleneck and latency source
2. **Subagent/hierarchy semantics via `%Spawn{}` are underspecified** — effectively just "fire-and-forget child_spec"
3. **Error handling, backpressure, and directive extensibility are too thin** for a robust runtime
4. **The `handle_signal/2` vs `cmd/2` fallback muddies the abstraction boundary** between signals and actions

---

## 1. Core API Methods

### `start_link/2`

**Strengths**
- Clean boundary: `start_link(agent_module, opts)` keeps the server generic over agent modules
- `:agent` vs `:agent_opts` split allows injecting a pre-built pure agent or letting the module construct one
- Runtime configuration (`default_dispatch`, `children_supervisor`, `spawn_fun`) stays in server state, preserving agent purity

**Weaknesses**

| Issue | Impact | Recommendation |
|-------|--------|----------------|
| Type safety of `:agent` | The runtime check only verifies `%{__struct__: _}`, accepting any struct | Assert `Jido.Agent` struct explicitly or at minimum check for expected fields |
| `default_dispatch` coupling | Changing dispatch requires restarting the server | Consider centralized dispatch config in `Jido.Signal.Dispatch` |

### `handle_signal/2` and `handle_signal_sync/3`

**Strengths**
- Clear async `cast` vs sync `call` separation
- Both flow through single "core path" (`process_signal/2`)

**Weaknesses**

| Issue | Impact | Recommendation |
|-------|--------|----------------|
| Blocking semantics not obvious | GenServer is blocked during directive execution; no feedback if mailbox grows | Document clearly; consider async directive execution |
| `handle_signal_sync/3` spec mismatch | Spec says `{:ok, Agent.t()} \| {:error, term()}` but `{:error, _}` is never returned | Fix spec or surface `%Error{}` directives as errors |
| `%Error{}` not observable | Errors are logged but not returned to sync callers | Consider returning first error in sync response |

### `get_agent/1`

Simple and correct. Minor concern: under load, this blocks waiting for all pending signals to process.

---

## 2. Subagent Patterns and `%Spawn{}`

### Current Implementation

```elixir
defp execute_directive(%Directive.Spawn{} = spawn_directive, state) do
  result =
    cond do
      is_function(state.spawn_fun, 1) ->
        state.spawn_fun.(spawn_directive.child_spec)
      state.children_supervisor != nil ->
        DynamicSupervisor.start_child(state.children_supervisor, spawn_directive.child_spec)
      true ->
        Logger.warning("Spawn directive received but no :children_supervisor...")
        :ignored
    end
  {:ok, state}
end
```

### Problems

| Issue | Functional Impact |
|-------|-------------------|
| **No parent-child semantics** | No parent agent ID in child, no linkage beyond BEAM supervision, no lifecycle feedback |
| **`tag` is unused** | Directive carries tag but runtime ignores it—no correlation or registration |
| **State doesn't track hierarchy** | Children not recorded in agent state; users must manage manually |

### What's Missing for True Hierarchical Agents

```
Parent AgentServer
├── state.children :: %{tag => %{pid: pid, module: module, meta: map}}
├── receives child lifecycle signals (crash, terminate)
└── can query/manage children by tag
```

### Recommendations

1. **Enrich `%Spawn{}`** with optional `agent_module`, initial state, and `parent_ref`
2. **Track children in server state** keyed by `tag` or generated ID
3. **Feedback loop**: Translate child exits into `Jido.Signal`s back to parent's `handle_signal/2`

---

## 3. Process Blocking and Async Nature

### The Core Problem

All directive execution happens **inline in GenServer callbacks**:

```elixir
{new_state, stop_reason} = process_signal(signal, state)
# process_signal → delegate_to_agent (pure)
#               → execute_directives (EFFECTFUL, BLOCKING)
```

### Consequences

| Scenario | Impact |
|----------|--------|
| Slow `Jido.Signal.Dispatch.dispatch/2` | Blocks ALL signal processing |
| Heavy child init via `%Spawn{}` | Blocks signal processing |
| Multiple independent `%Emit{}` | Executed serially, no parallelism |
| High signal volume | Unbounded mailbox growth, latency explosion |

### This is the Single Biggest Architectural Weakness

**Current Model:**
```
Signal → GenServer → Agent.handle_signal (fast) → execute_directives (SLOW) → next signal
         ↑                                                                    ↓
         └────────────────── BLOCKED ──────────────────────────────────────────┘
```

**Better Model:**
```
Signal → GenServer → Agent.handle_signal (fast) → queue directives → next signal
                                                        ↓
                                          Task.Supervisor (async) → execute directives
```

### Recommendations

1. **Classify directives by cost**: `%Schedule{}`, `%Stop{}` are cheap; `%Emit{}`, `%Spawn{}` are potentially slow
2. **Offload slow directives**: Use `Task.Supervisor.async_nolink` for network/external effects
3. **Keep strict mode optional**: For tests or small deployments, current inline execution is fine
4. **Add `:async_directives?` option** or pluggable executor module

---

## 4. Functional Programming Purity Analysis

### Overall Assessment: Good Separation

- `Jido.Agent` is pure: `(agent, action) -> {agent, directives}`
- `AgentServer` replaces `state.agent` with new struct, never mutates in-place
- Directives are pure data structs, never fed back into agents

### Impurity "Leaks" and Design Smells

#### 4.1 `delegate_to_agent/3` Mixing Two Paradigms

```elixir
defp delegate_to_agent(agent_module, agent, %Signal{} = signal) do
  if function_exported?(agent_module, :handle_signal, 2) do
    agent_module.handle_signal(agent, signal)
  else
    agent_module.cmd(agent, signal)  # Signal as action?!
  end
end
```

**Problems:**
- Dynamic feature check blurs the abstraction
- `cmd/2` is typed for actions, not signals — implicit convention, not typed contract
- Some agents are "signal-native", others treat signals as generic actions
- No default `handle_signal/2` in macro leads to inconsistent patterns

#### 4.2 `%Schedule{}` Allows Bypassing Signal Path

```elixir
def handle_info({:jido_schedule, %Signal{} = signal}, state) do
  process_signal(signal, state)  # Signal path
end

def handle_info({:jido_schedule, message}, state) do
  process_action(message, state)  # Bypasses signal envelope!
end
```

You claim "Signals are the universal message envelope" but explicitly allow bypassing it.

#### 4.3 `Code.ensure_loaded?` Dynamic Check

```elixir
if Code.ensure_loaded?(Jido.Signal.Dispatch) do
  Jido.Signal.Dispatch.dispatch(emit.signal, cfg)
```

This couples AgentServer to a specific module name and makes testing harder.

### Recommendation: Pick One Canonical Entrypoint

**Option A: Signal-First**
- Agents always driven by signals
- `handle_signal/2` is canonical pure entrypoint
- `cmd/2` is secondary API for internal use

**Option B: Action-First (Recommended)**
- `cmd/2` is the only pure entrypoint
- `AgentServer` translates Signal → action via configurable translator
- Generate default `handle_signal/2` in macro that delegates to `cmd/2`

```elixir
# Generated in `use Jido.Agent`
def handle_signal(agent, %Signal{} = signal) do
  action = signal_to_action(signal)  # Configurable mapper
  cmd(agent, action)
end
```

---

## 5. Directive Execution Model

### Current: Sequential `reduce_while`

```elixir
defp execute_directives(directives, state) when is_list(directives) do
  Enum.reduce_while(directives, {state, nil}, fn directive, {acc_state, _} ->
    case execute_directive(directive, acc_state) do
      {:ok, new_state} -> {:cont, {new_state, nil}}
      {:stop, reason, new_state} -> {:halt, {new_state, reason}}
    end
  end)
end
```

**Strengths:**
- Simple and deterministic
- Order respected
- `%Stop{}` can short-circuit cleanly

### Limitations

| Issue | Impact |
|-------|--------|
| No directive-level failure handling | If `Dispatch.dispatch` fails/raises, GenServer may crash |
| No parallelism | Independent directives still execute serially |
| Unknown directives silently ignored | External libs can define structs but can't teach runtime to execute them |

### Recommendation: Directive Execution Protocol

```elixir
defprotocol Jido.AgentServer.Executor do
  @spec execute(struct(), Jido.AgentServer.state()) ::
    {:ok, Jido.AgentServer.state()} |
    {:stop, reason :: term(), Jido.AgentServer.state()}
end

# Implementations for core directives
defimpl Jido.AgentServer.Executor, for: Jido.Agent.Directive.Emit do
  def execute(emit, state), do: # ...
end
```

This enables:
- External libraries to add custom directive executors
- Pluggable execution strategies (concurrent, prioritized)
- Better separation of concerns

---

## 6. Error Handling

### Current Behavior

```elixir
defp execute_directive(%Directive.Error{} = error, state) do
  Logger.error("Agent error (context: #{inspect(error.context)}): ...")
  {:ok, state}  # No effect on anything!
end
```

### Problems

| Issue | Consequence |
|-------|-------------|
| Error-as-data philosophy undermined | Agents model errors explicitly, but runtime discards them |
| No policy enforcement | Can't implement "stop on N errors" or "emit alarm signal" |
| Supervision integration missing | Only `%Stop{}` affects lifecycle; errors have no supervision impact |
| `handle_signal_sync/3` blind to errors | Caller can't observe that processing produced errors |

### Recommendation: Error Policy

```elixir
@type error_policy ::
  :log_only                           # Current behavior
  | :stop_on_error                    # Stop server on any error
  | {:emit_signal, dispatch_cfg}      # Emit error as signal
  | (Directive.Error.t(), state() -> {:ok, state()} | {:stop, reason, state()})

# In start_link opts
Jido.AgentServer.start_link(MyAgent, error_policy: :stop_on_error)
```

Also consider: surfacing first `%Error{}` in `handle_signal_sync/3` as `{:error, error}`.

---

## 7. State Management: Event Sourcing Readiness

### Current State

- State lives only as `state.agent` in-memory
- Input (signals) and output (directives) not persisted
- No hooks for snapshots or replay

### You Already Have the Right Shape

```
Input: Signal (CloudEvents)
Transition: (agent, input) -> {agent', directives}  # PURE
Effects: directives executed separately
```

This is the classic event sourcing pattern!

### What's Missing

```elixir
defp process_signal(%Signal{} = signal, state) do
  {agent, directives} = delegate_to_agent(...)
  # MISSING: persistence hook here
  # persist(old_agent: state.agent, input: signal, new_agent: agent, directives: directives)
  state = %{state | agent: agent}
  execute_directives(directives, state)
end
```

### Recommendation: Pluggable Persistence

```elixir
@callback after_transition(
  old_agent :: Agent.t(),
  input :: Signal.t() | term(),
  new_agent :: Agent.t(),
  directives :: [Directive.t()],
  opts :: keyword()
) :: :ok | {:error, term()}

# Default: no-op
# Users can implement for event sourcing, snapshots, replay
```

---

## 8. Backpressure

### Current: None

```elixir
def handle_signal(server, %Signal{} = signal) do
  GenServer.cast(server, {:signal, signal})  # Fire-and-forget
end
```

Under load:
- Messages accumulate unbounded
- No admission control, prioritization, or queue limits
- Memory grows, latency explodes

### Recommendations

| Approach | Effort | Benefit |
|----------|--------|---------|
| Monitor mailbox size | Small | Visibility into backlog |
| Expose `busy?/1` API | Small | Callers can implement client-side backpressure |
| Configurable queue limit | Medium | Reject/drop when overloaded |
| Document limitations | Small | Set expectations |

Minimal implementation:

```elixir
def queue_length(server) do
  {:message_queue_len, len} = Process.info(GenServer.whereis(server), :message_queue_len)
  len
end
```

---

## 9. Composability with Skills, Runners, Sensors

### Strengths

- Agent-server separation means Skills operate purely at agent/state/actions level
- Runners and Sensors can live outside, sending Signals into AgentServer
- `%Emit{}` + `default_dispatch` allows communication without knowing concrete transports

### Friction Points

| Component | Issue |
|-----------|-------|
| **Skills** | Can define new directive types but can't teach runtime to execute them |
| **Runners** | No formal delegation directive; everything via `%Emit{}` + convention |
| **Sensors** | `%Schedule{}` is too primitive for polling/periodic patterns |

### Recommendations

1. **Directive extensibility protocol** (see section 5)
2. **Standard higher-level directives** for common patterns:
   - `%DelegateToRunner{runner: module, params: map}`
   - `%SpawnAgent{module: agent_module, opts: keyword}` (richer than `%Spawn{}`)
3. **Document that `%Schedule{}` is a local helper**, not the primary sensor mechanism

---

## 10. The `handle_signal/2` vs `cmd/2` Tension

### The Conceptual Conflict

**Stated Model:**
- "Agents think, Servers act"
- "Signals are the universal message envelope"
- `cmd/2` is core: actions in, directives out

**Actual Implementation:**
- Some agents implement `handle_signal/2` (signal-native)
- Some treat signals as actions via `cmd/2` fallback
- Dynamic `function_exported?` check decides at runtime

### Problems

1. **Two mental models for the same thing**
   - Authors don't know which to implement
   - Generic tooling must handle both

2. **Type mismatch**
   - `cmd/2` action type: `module | {module, map} | Instruction | [action]`
   - Passing `Signal` is an escape hatch not reflected in types

3. **Testing inconsistency**
   - Some agents tested via `handle_signal/2`
   - Others via `cmd/2`
   - Runners/meta-structures must know about both

### Strong Recommendation

**Pick one canonical pure entrypoint for agents.**

Recommended: **`cmd/2` as canonical**

```elixir
# In `use Jido.Agent` macro, generate:
def handle_signal(agent, %Jido.Signal{} = signal) do
  action = __MODULE__.signal_to_action(signal)
  __MODULE__.cmd(agent, action)
end

# Default signal_to_action extracts from signal.type/data
# Users can override for custom mapping
def signal_to_action(%Jido.Signal{type: type, data: data}) do
  # Convention: signal.type maps to action module
  # e.g., "user.create" -> {UserActions.Create, data}
end
```

This gives you:
- Clear separation: agents talk in domain actions; servers translate signals
- Single algebra of actions for middleware, logging, composition
- Consistent testing story

---

## Incremental Improvement Roadmap

| Priority | Task | Effort | Impact |
|----------|------|--------|--------|
| **1** | Clarify signal/action boundary: generate default `handle_signal/2` in macro | S-M | High |
| **2** | Add directive execution protocol | M | High |
| **3** | Async execution for heavy directives (`%Emit{}`, `%Spawn{}`) | M | High |
| **4** | Make `%Error{}` meaningful (error policy option) | M | Medium |
| **5** | Basic backpressure/observability (queue length) | S | Medium |
| **6** | Strengthen `%Spawn{}` semantics (track children by tag) | M-L | Medium |
| **7** | Optional persistence hook for event sourcing | M-L | Low (future-proofing) |

**Effort Key:** S = <1hr, M = 1-3hr, L = 1-2 days

---

## When to Consider Deeper Redesign

Revisit fundamentally if:

- **Very high throughput needed** (thousands of signals/sec/agent) → Consider partitioned processing or event streams
- **Full event sourcing required** → Treat AgentServer as projection, persist every signal
- **Distributed hierarchical agents** → Need cluster-aware coordination beyond single-process GenServer

---

## Summary

The `Jido.AgentServer` implementation provides a solid foundation for the "Agents think, Servers act" paradigm. The pure/effectful separation is clean. However, to become a robust production runtime, it needs:

1. **Clearer abstraction boundaries** (signal vs action entrypoint)
2. **Async directive execution** (don't block the GenServer)
3. **Extensible directive interpretation** (protocol-based)
4. **Meaningful error handling** (policy-driven)
5. **Richer subagent semantics** (not just fire-and-forget spawn)

These improvements are incremental and don't require redesigning the core Agent/Directive/Signal primitives.

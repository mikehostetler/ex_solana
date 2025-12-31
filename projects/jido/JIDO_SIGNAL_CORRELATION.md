# Jido Signal Correlation & Causation Analysis

## Executive Summary

Jido has foundational trace infrastructure (`Jido.Signal.Ext.Trace`) with fields for distributed tracing (trace_id, span_id, parent_span_id, causation_id), but **this infrastructure is not currently wired into the agent lifecycle**. Signals created via `SpawnAgent`, `emit_to_parent`, `emit_to_pid`, `Schedule`, and internal system signals do not automatically propagate correlation context.

**Gap vs. Industry Standards**: Compared to OpenTelemetry, Jaeger, Zipkin, and AWS X-Ray, Jido lacks:
- Automatic trace context propagation across agent boundaries
- Causality linking when one signal triggers another
- W3C Trace Context alignment for interoperability
- Parent-child span relationships in multi-agent hierarchies

**Impact**: Without correlation, debugging multi-agent workflows is difficult. You cannot trace a request from initial signal → spawned children → emitted replies → scheduled follow-ups.

**Effort to Fix**: 
- **Simple path** (basic propagation): 1-3 hours
- **Full OTEL alignment**: 1-2 days

---

## Current State

### What Exists in V2

1. **NO Trace Extension in V2** - exists only in v1 (main branch):
   - V1 has `Jido.Signal.Ext.Trace` in `jido_signal` dependency
   - V1 has `Jido.Signal.TraceContext` for process-dict context management
   - V1 has `Jido.Signal.Trace.Propagate` for automatic trace injection
   - **V2 has none of this** - need to port or rebuild

2. **Signal Structure** (CloudEvents 1.0.2 compliant via jido_signal v1.2.0):
   - Core fields: `id`, `source`, `type`, `time`, `data`
   - Extensions system available (used by v1, unused in v2)
   - Extension API: `put_extension/3`, `get_extension/2`, `delete_extension/2`

3. **Multi-Agent Directives**:
   - `SpawnAgent` - spawn child agents
   - `Emit` - dispatch signals (via `emit_to_parent`, `emit_to_pid`)
   - `Schedule` - delayed signal delivery
   - `StopChild` - stop child agents

4. **Custom Signal Types in V2** (using `use Jido.Signal`):
   - `Jido.AI.Signal.ReqLLMResult` - LLM streaming results
   - `Jido.AI.Signal.ReqLLMPartial` - LLM streaming tokens
   - `Jido.AI.Signal.ToolResult` - Tool execution results
   - `Jido.AgentServer.Signal.*` - System signals (ChildStarted, ChildExit, Orphaned, Scheduled, CronTick)

### What's Missing

**Zero trace/correlation infrastructure in V2:**
```bash
$ rg "trace_id|causation_id|parent_span_id|TraceContext|Propagate" lib/
# No results - V2 has no tracing
```

**Key gaps:**

1. **No automatic propagation in directives**:
   - `Emit.exec/3` ignores `_input_signal` argument (doesn't copy trace context)
   - `Schedule.exec/3` creates new signals without trace linkage
   - `SpawnAgent` doesn't propagate trace to child agents

2. **No root trace initialization**:
   - Signals entering `AgentServer.call/3` or `cast/2` don't get trace context
   - System signals (`jido.agent.child.started`, etc.) have no trace

3. **Multi-agent flows are untrackable**:
   ```elixir
   # Current example from multi_agent.exs (lines 84-150)
   # Coordinator → Worker → Coordinator
   
   # Step 1: Coordinator emits to worker
   work_signal = Signal.new!("worker.query", %{query: query}, source: "/coordinator")
   emit_directive = Directive.emit_to_pid(work_signal, worker_pid)
   # ❌ work_signal has no trace_id from parent context
   
   # Step 2: Worker replies to parent
   reply_signal = Signal.new!("worker.answer", %{answer: 42}, source: "/worker")
   emit_directive = Directive.emit_to_parent(agent, reply_signal)
   # ❌ reply_signal not linked to worker.query trace
   ```

4. **Async boundaries break correlation**:
   - Scheduled signals don't inherit trace context
   - Spawned processes start fresh (no parent trace)

---

## Industry Best Practices

### OpenTelemetry / W3C Trace Context Standard

**Core Concepts:**

1. **Trace ID**: 16-byte unique identifier for entire distributed workflow
2. **Span ID**: 8-byte unique identifier for single operation/signal
3. **Parent Span ID**: Links spans into a tree structure
4. **Trace Propagation**: Automatic context passing across boundaries (HTTP, messaging, processes)

**W3C Traceparent Header Format:**
```
traceparent: 00-<trace-id>-<span-id>-<flags>
```

**Key Principles:**

1. **Automatic Propagation**: Trace context flows automatically without developer intervention
2. **Causality Preservation**: Parent-child relationships maintained across async boundaries
3. **Sampling Control**: Decide which traces to record (e.g., 1% sampling)
4. **Span Attributes**: Rich metadata per operation (agent_id, directive_type, duration)
5. **Cross-System Compatibility**: W3C headers enable tracing across microservices

### Examples from Mature Systems

**AWS X-Ray:**
- Automatically injects `X-Amzn-Trace-Id` into Lambda/ECS containers
- Subsegments for each operation (DB call, HTTP request)
- Annotations for custom metadata

**Jaeger:**
- `uber-trace-id` header propagation
- Baggage items for cross-process metadata
- Sampling strategies (probabilistic, rate-limiting)

**Google Cloud Trace:**
- `X-Cloud-Trace-Context` header
- Automatic correlation for GCP services
- Trace visualization with flamegraphs

---

## Recommended Solution

### Decision: Port V1 Extension or Build New?

**Recommendation: Port V1's Trace extension with V2 adaptations**

**Why Port from V1:**
1. ✅ **Battle-tested** - V1 extension has comprehensive test coverage
2. ✅ **CloudEvents compliant** - Already uses proper extension protocol
3. ✅ **Upstream compatible** - Could be upstreamed to `jido_signal` later
4. ✅ **W3C aligned** - Trace/span IDs match OpenTelemetry patterns
5. ✅ **Simple** - Process dictionary approach is lightweight

**What to Adapt for V2:**
1. **Extension registration** - V1 registers at app startup, V2 needs similar
2. **Directive integration** - V2 has different directive executors
3. **No Instruction concept** - V2 doesn't have Instructions, uses directives directly
4. **Agent state structure** - V2 agents have different state shape

### Simple Path: Port V1 + Integrate with V2 DirectiveExec

**Goal**: Automatic correlation in multi-agent flows without API changes.

**Key Insight**: V2's directive executors already receive `_input_signal` - perfect hook for propagation.

### 1. Create Trace Extension (V2-specific, no upstream changes yet)

Since `Jido.Signal.Ext.Trace` lives in `jido_signal` (upstream), we'll create our own extension in V2 for now. It can be upstreamed later.

```elixir
# lib/jido/signal/ext/trace.ex
defmodule Jido.Signal.Ext.Trace do
  @moduledoc """
  Trace extension for distributed tracing and causation tracking.
  
  Provides W3C-compatible trace IDs and span IDs for correlating signals
  across agent boundaries, async operations, and scheduled work.
  
  ## Fields
  
  - `trace_id` - Constant identifier for entire workflow (16-byte hex)
  - `span_id` - Unique identifier for this signal (8-byte hex)
  - `parent_span_id` - Span ID of parent signal (optional)
  - `causation_id` - Signal ID that caused this signal (optional)
  
  ## CloudEvents Serialization
  
  Serializes to top-level CloudEvents attributes:
  - `trace_id` → `"trace_id"`
  - `span_id` → `"span_id"`
  - `parent_span_id` → `"parent_span_id"`
  - `causation_id` → `"causation_id"`
  
  ## Example
  
      # Create signal with trace
      {:ok, signal} = Signal.new("user.created", %{user_id: "123"})
      {:ok, traced} = Signal.put_extension(signal, "correlation", %{
        trace_id: "abc123...",
        span_id: "def456..."
      })
  """
  
  use Jido.Signal.Ext,
    namespace: "correlation",
    schema: [
      trace_id: [type: :string, required: true, doc: "W3C trace identifier"],
      span_id: [type: :string, required: true, doc: "W3C span identifier"],
      parent_span_id: [type: :string, doc: "Parent span identifier"],
      causation_id: [type: :string, doc: "Causing signal ID"]
    ]

  @impl true
  def to_attrs(%{trace_id: trace_id, span_id: span_id} = data) do
    %{
      "trace_id" => trace_id,
      "span_id" => span_id
    }
    |> maybe_put("parent_span_id", data[:parent_span_id])
    |> maybe_put("causation_id", data[:causation_id])
  end

  @impl true
  def from_attrs(attrs) do
    case Map.get(attrs, "trace_id") do
      nil -> nil
      trace_id ->
        %{
          trace_id: trace_id,
          span_id: Map.get(attrs, "span_id")
        }
        |> maybe_put_field(:parent_span_id, Map.get(attrs, "parent_span_id"))
        |> maybe_put_field(:causation_id, Map.get(attrs, "causation_id"))
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_field(map, _key, nil), do: map
  defp maybe_put_field(map, key, value), do: Map.put(map, key, value)
end
```

### 2. Create TraceContext Helper (Adapted from V1)

```elixir
# lib/jido/signal/trace_context.ex
defmodule Jido.Signal.TraceContext do
  @moduledoc """
  Process-dictionary-based trace context management.
  
  Stores current trace context in the process dictionary so it can be
  accessed when creating new signals without explicit passing.
  
  Ported from Jido v1 with v2 adaptations.
  """
  
  alias Jido.Signal
  alias Jido.Signal.Ext.Trace

  @trace_context_key :jido_trace_context

  @doc "Get current trace context from process dictionary"
  @spec current() :: map() | nil
  def current, do: Process.get(@trace_context_key)

  @doc "Set trace context in process dictionary"
  @spec set(map()) :: :ok
  def set(context) when is_map(context) do
    Process.put(@trace_context_key, context)
    :ok
  end

  @doc "Clear trace context from process dictionary"
  @spec clear() :: :ok
  def clear do
    Process.delete(@trace_context_key)
    :ok
  end

  @doc """
  Extract and set trace context from a signal.
  
  Used when processing incoming signals to make their trace context
  available for subsequent signal creation.
  """
  @spec set_from_signal(Signal.t()) :: :ok
  def set_from_signal(%Signal{} = signal) do
    case Signal.get_extension(signal, "correlation") do
      nil -> :ok
      trace_data when is_map(trace_data) -> 
        set(trace_data)
        :ok
    end
  end

  @doc """
  Generate new trace and span IDs (W3C format).
  
  Returns 16-byte trace_id and 8-byte span_id as lowercase hex strings.
  """
  @spec generate_ids() :: {String.t(), String.t()}
  def generate_ids do
    trace_id = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    span_id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    {trace_id, span_id}
  end
end
```

### 3. Create Propagate Helper (Simplified from V1)

```elixir
# lib/jido/signal/trace/propagate.ex
defmodule Jido.Signal.Trace.Propagate do
  @moduledoc """
  Automatic trace context propagation for signals.
  
  Enriches outgoing signals with trace context based on:
  1. Process dictionary context (current trace)
  2. Parent signal's trace extension
  3. New root trace (if no context exists)
  
  Ported from Jido v1 with v2 simplifications.
  """
  
  alias Jido.Signal
  alias Jido.Signal.TraceContext

  @doc """
  Enrich a signal with trace context.
  
  Decides propagation strategy based on available context:
  - If signal already has trace → preserve it
  - If process has trace context → continue trace with new span
  - If parent signal provided → extract from parent
  - Otherwise → create new root trace
  """
  @spec enrich(Signal.t(), Signal.t() | nil) :: Signal.t()
  def enrich(%Signal{} = signal, parent_signal \\ nil) do
    # Don't overwrite existing trace
    if Signal.get_extension(signal, "correlation") do
      signal
    else
      trace_data = build_trace_data(parent_signal)
      apply_trace(signal, trace_data)
    end
  end

  # Build trace data from available context
  defp build_trace_data(parent_signal) do
    cond do
      # 1. Use process dictionary context (from current signal processing)
      context = TraceContext.current() ->
        continue_trace(context, parent_signal)
      
      # 2. Extract from parent signal
      parent_signal && Signal.get_extension(parent_signal, "correlation") ->
        extract_from_parent(parent_signal)
      
      # 3. Create new root
      true ->
        create_root()
    end
  end

  # Continue existing trace with new span
  defp continue_trace(context, parent_signal) do
    {_trace_id, span_id} = TraceContext.generate_ids()
    
    %{
      trace_id: context.trace_id,
      span_id: span_id,
      parent_span_id: context.span_id,
      causation_id: parent_signal && parent_signal.id
    }
  end

  # Extract trace from parent signal
  defp extract_from_parent(%Signal{} = parent) do
    parent_trace = Signal.get_extension(parent, "correlation")
    {_trace_id, span_id} = TraceContext.generate_ids()
    
    %{
      trace_id: parent_trace.trace_id,
      span_id: span_id,
      parent_span_id: parent_trace.span_id,
      causation_id: parent.id
    }
  end

  # Create new root trace
  defp create_root do
    {trace_id, span_id} = TraceContext.generate_ids()
    
    %{
      trace_id: trace_id,
      span_id: span_id
    }
  end

  # Apply trace data to signal
  defp apply_trace(signal, trace_data) do
    # Filter out nil values
    trace_data = Enum.reject(trace_data, fn {_k, v} -> is_nil(v) end) |> Map.new()
    
    case Signal.put_extension(signal, "correlation", trace_data) do
      {:ok, traced_signal} -> traced_signal
      {:error, _reason} -> signal  # Preserve signal if trace fails
    end
  end
end
```

### 4. Wire Into DirectiveExec

**Emit Directive** (`lib/jido/agent_server/directive_executors.ex`):

```elixir
# BEFORE (line 6)
def exec(%{signal: signal, dispatch: dispatch}, _input_signal, state) do
  cfg = dispatch || state.default_dispatch
  
  case cfg do
    nil -> Logger.debug("Emit directive with no dispatch config")
    cfg ->
      if Code.ensure_loaded?(Jido.Signal.Dispatch) do
        Task.Supervisor.start_child(Jido.TaskSupervisor, fn ->
          Jido.Signal.Dispatch.dispatch(signal, cfg)
        end)
      end
  end
  
  {:async, nil, state}
end

# AFTER
def exec(%{signal: signal, dispatch: dispatch}, input_signal, state) do
  cfg = dispatch || state.default_dispatch
  
  # Enrich signal with trace from input_signal
  traced_signal = Jido.Signal.Trace.Propagate.enrich(signal, input_signal)
  
  case cfg do
    nil -> Logger.debug("Emit directive with no dispatch config")
    cfg ->
      if Code.ensure_loaded?(Jido.Signal.Dispatch) do
        Task.Supervisor.start_child(Jido.TaskSupervisor, fn ->
          Jido.Signal.Dispatch.dispatch(traced_signal, cfg)
        end)
      end
  end
  
  {:async, nil, state}
end
```

**Schedule Directive** (line 76):

```elixir
# BEFORE
def exec(%{delay_ms: delay, message: message}, _input_signal, state) do
  signal =
    case message do
      %Jido.Signal{} = s -> s
      other -> Scheduled.new!(%{message: other}, source: "/agent/#{state.id}")
    end

  Process.send_after(self(), {:scheduled_signal, signal}, delay)
  {:ok, state}
end

# AFTER
def exec(%{delay_ms: delay, message: message}, input_signal, state) do
  base_signal =
    case message do
      %Jido.Signal{} = s -> s
      other -> Scheduled.new!(%{message: other}, source: "/agent/#{state.id}")
    end

  # Enrich scheduled signal with trace
  traced_signal = Jido.Signal.Trace.Propagate.enrich(base_signal, input_signal)

  Process.send_after(self(), {:scheduled_signal, traced_signal}, delay)
  {:ok, state}
end
```

### 5. Root Incoming Signals at AgentServer Boundary

**In `agent_server.ex`**:

```elixir
# Add to handle_call for :signal (around line 462)
def handle_call({:signal, %Signal{} = signal}, _from, state) do
  # Extract trace context from incoming signal
  :ok = Jido.Signal.TraceContext.set_from_signal(signal)
  
  # Route signal (trace context now in process dict)
  result = process_signal(signal, state)
  
  # Clear context after processing
  :ok = Jido.Signal.TraceContext.clear()
  
  result
end

# Add to handle_cast for :signal (around line 481)  
def handle_cast({:signal, %Signal{} = signal}, state) do
  :ok = Jido.Signal.TraceContext.set_from_signal(signal)
  
  result = process_signal(signal, state)
  
  :ok = Jido.Signal.TraceContext.clear()
  
  result
end

# Add to handle_info for :signal (around line 534)
def handle_info({:signal, %Signal{} = signal}, state) do
  :ok = Jido.Signal.TraceContext.set_from_signal(signal)
  
  result = process_signal(signal, state)
  
  :ok = Jido.Signal.TraceContext.clear()
  
  result
end
```

**Why not "root" signals?** We extract trace from incoming signals rather than generating new roots. If a signal arrives without trace, `Propagate.enrich/2` will create a root when emitting new signals.

### 6. Register Extension at Application Startup

Add to `lib/jido/application.ex`:

```elixir
def start(_type, _args) do
  # Register trace extension
  Code.ensure_loaded(Jido.Signal.Ext.Trace)
  Jido.Signal.Ext.Registry.register(Jido.Signal.Ext.Trace)
  
  children = [
    # ... existing children
  ]
  
  Supervisor.start_link(children, strategy: :one_for_one, name: Jido.Supervisor)
end
```

---

## Impact After Implementation

### Before (Current State)

```
User Request → Coordinator Agent
  ❌ No trace_id
  
Coordinator → SpawnAgent(Worker)
  ❌ Worker starts with no parent trace
  
Coordinator → emit_to_pid(worker.query)
  ❌ worker.query has no correlation
  
Worker → emit_to_parent(worker.answer)
  ❌ worker.answer not linked to query
  
Coordinator → Schedule(followup, 5000ms)
  ❌ followup signal starts fresh trace
```

### After (With TraceContext)

```
User Request → Coordinator Agent
  ✅ trace_id: abc123, span_id: 001
  
Coordinator → emit_to_pid(worker.query)
  ✅ trace_id: abc123, span_id: 002, parent: 001, causation: signal_001
  
Worker → emit_to_parent(worker.answer)
  ✅ trace_id: abc123, span_id: 003, parent: 002, causation: signal_002
  
Coordinator → Schedule(followup, 5000ms)
  ✅ trace_id: abc123, span_id: 004, parent: 001, causation: signal_001
  
(5 seconds later) followup executes
  ✅ Still trace_id: abc123, with correct parent chain
```

### Observability Wins

1. **Query any signal by trace_id** - see entire workflow
2. **Reconstruct causality chain** - which signal caused which
3. **Measure latency** - time from root to leaf signals
4. **Debug multi-agent flows** - trace signals across agent boundaries
5. **Future OTEL export** - already W3C-compatible IDs

---

## Advanced Path (Future)

When you need full distributed tracing:

### 1. W3C Trace Context Integration

Add `traceparent` attribute support to Signal:

```elixir
defmodule Jido.Signal.Ext.TraceContext do
  @doc "Generates W3C traceparent header"
  def to_traceparent(%Trace{trace_id: tid, span_id: sid}) do
    # 00-<trace-id>-<span-id>-01
    "00-#{tid}-#{sid}-01"
  end
  
  @doc "Parses W3C traceparent header"
  def from_traceparent("00-" <> rest) do
    [trace_id, span_id, _flags] = String.split(rest, "-")
    %Trace{trace_id: trace_id, span_id: span_id}
  end
end
```

### 2. OpenTelemetry Export

Create OTEL spans from Jido signals:

```elixir
defmodule Jido.Signal.OTEL.Exporter do
  def export_span(signal) do
    trace = Signal.get_ext(signal, Trace)
    
    :otel_span.start_span(
      signal.type,
      %{
        trace_id: decode_hex(trace.trace_id),
        span_id: decode_hex(trace.span_id),
        parent_span_id: decode_hex(trace.parent_span_id)
      }
    )
    
    # Add attributes from signal.data
    :otel_span.set_attributes([
      {"signal.id", signal.id},
      {"signal.source", signal.source},
      {"agent.id", signal.data[:agent_id]}
    ])
    
    :otel_span.end_span()
  end
end
```

### 3. Sampling Configuration

```elixir
config :jido, :tracing,
  sampling_rate: 0.01,  # 1% of traces
  always_sample: ["critical_agent", "payment_agent"]
```

### 4. Multi-Causation Links

Extend for fan-in scenarios:

```elixir
defmodule Jido.Signal.Ext.Trace do
  schema: [
    # ...
    links: [
      type: {:list, :map},
      doc: "OTEL-style links to other spans",
      default: []
    ]
  ]
end
```

---

## Implementation Plan

### Phase 1: Basic Correlation (2-4 hours)

- [ ] Create `lib/jido/signal/ext/trace.ex` (port from v1)
- [ ] Create `lib/jido/signal/trace_context.ex` (port from v1)
- [ ] Create `lib/jido/signal/trace/propagate.ex` (simplified from v1)
- [ ] Register extension in `lib/jido/application.ex`
- [ ] Update `Emit.exec/3` to enrich with trace
- [ ] Update `Schedule.exec/3` to enrich with trace
- [ ] Add trace context extraction in `AgentServer` handlers
- [ ] Add tests for trace propagation
- [ ] Update `multi_agent.exs` example to demonstrate tracing

### Phase 2: Documentation & Tooling (2-4 hours)

- [ ] Document Trace extension semantics (W3C alignment)
- [ ] Add `mix jido.trace <trace_id>` task to query signals
- [ ] Create trace visualization example
- [ ] Add to AGENTS.md guidelines

### Phase 3: Upstream to jido_signal (optional, 1-2 hours)

- [ ] Submit PR to `jido_signal` with `Trace` extension
- [ ] Update V2 to use upstream extension once merged
- [ ] Remove local `lib/jido/signal/ext/trace.ex`

### Phase 4: Advanced (1-2 days, optional)

- [ ] W3C `traceparent` header support
- [ ] OTEL exporter (`:opentelemetry` integration)
- [ ] Sampling configuration
- [ ] Multi-link support for complex causality
- [ ] Jaeger/Zipkin UI integration example

---

## Testing Strategy

### Unit Tests

```elixir
defmodule Jido.Signal.TraceContextTest do
  test "root/1 creates new trace for signal without trace" do
    signal = Signal.new!("test", %{})
    rooted = TraceContext.root(signal)
    
    trace = Signal.get_ext(rooted, Trace)
    assert trace.trace_id
    assert trace.span_id
    refute trace.parent_span_id
  end
  
  test "child_of/2 inherits parent trace_id" do
    parent = Signal.new!("parent", %{}) |> TraceContext.root()
    child = Signal.new!("child", %{})
    
    child_traced = TraceContext.child_of(parent, child)
    
    parent_trace = Signal.get_ext(parent, Trace)
    child_trace = Signal.get_ext(child_traced, Trace)
    
    assert child_trace.trace_id == parent_trace.trace_id
    assert child_trace.parent_span_id == parent_trace.span_id
    assert child_trace.causation_id == parent.id
    assert child_trace.span_id != parent_trace.span_id
  end
end
```

### Integration Tests

```elixir
defmodule Jido.MultiAgentTraceTest do
  test "signals maintain trace across parent → child → parent flow" do
    # Start coordinator
    {:ok, coordinator} = AgentServer.start_link(CoordinatorAgent, [])
    
    # Send initial signal with trace
    initial_signal = Signal.new!("coordinator.start", %{})
                     |> TraceContext.root()
    
    AgentServer.cast(coordinator, initial_signal)
    
    # Capture all signals via test subscriber
    signals = capture_signals()
    
    # Verify trace continuity
    trace_ids = Enum.map(signals, fn s -> 
      Signal.get_ext(s, Trace).trace_id 
    end)
    
    assert Enum.uniq(trace_ids) |> length() == 1
  end
end
```

---

## Comparison to Industry Standards

| Feature | Jido (Current) | Jido (Proposed) | OpenTelemetry | AWS X-Ray |
|---------|---------------|-----------------|---------------|-----------|
| Trace ID propagation | ❌ None | ✅ Automatic | ✅ Automatic | ✅ Automatic |
| Parent-child spans | ❌ No | ✅ Yes | ✅ Yes | ✅ Yes |
| Causality tracking | ❌ No | ✅ causation_id | ✅ Links | ✅ Annotations |
| W3C compliance | ❌ No | ⚠️ Compatible IDs | ✅ Full | ⚠️ Partial |
| Cross-system traces | ❌ No | ⚠️ Via CloudEvents | ✅ Native | ✅ Native |
| Sampling | ❌ No | ❌ Not yet | ✅ Yes | ✅ Yes |
| Async boundary support | ❌ No | ✅ Schedule + Spawn | ✅ Context propagation | ✅ Subsegments |
| Multi-agent hierarchies | ❌ No | ✅ emit_to_parent | N/A | N/A |

---

## Security & Performance Considerations

### Performance

- **ID Generation**: `crypto.strong_rand_bytes` is fast (~1μs per ID)
- **Extension overhead**: Trace adds ~150 bytes per signal (negligible)
- **No blocking**: Trace propagation is pure data transformation

### Security

- **No PII in trace IDs**: Random bytes, not derived from data
- **Sampling prevents overload**: Future sampling limits trace volume
- **Extensions are validated**: Trace schema enforced by Zoi

### Operational

- **Storage**: Journal adapters should index by `trace_id` for queries
- **Retention**: Trace data can be pruned independently of signals
- **Backwards compat**: Signals without Trace extension still work

---

## Integration with Jido.Observe

### Overview

**Jido.Observe** (observability/telemetry) and **Signal Trace** (causality tracking) serve complementary purposes:

- **Signal Trace** = *Causality graph*: which signal caused which
- **Observe Spans** = *Performance segments*: how long operations took

**Integration Strategy: Shared IDs, Separate Graphs**

```
┌─────────────────────────────────────────────┐
│         Incoming Signal                     │
│  trace_id: abc123                          │
│  signal_id: sig_001                        │
└─────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────┐
│   AgentServer.handle_call(:signal)         │
│   1. Extract TraceContext from signal      │
│   2. Set in process dictionary             │
│   3. Start Observe span with trace IDs     │
└─────────────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
┌──────────────┐        ┌──────────────┐
│ Signal Trace │        │ Observe Span │
│ (Causality)  │        │ (Performance)│
├──────────────┤        ├──────────────┤
│ trace_id     │◄───────┤ metadata:    │
│ signal_id    │        │  jido_trace  │
│ parent_sig   │        │  jido_signal │
│ causation_id │        │  duration_ms │
└──────────────┘        └──────────────┘
```

### Metadata Bridge

Add helper to expose trace context to Observe:

```elixir
# lib/jido/signal/trace_context.ex

@doc """
Converts trace context to Observe span metadata.

Returns a map with standardized keys that Observe.Tracer 
implementations can use to link performance spans with causal traces.
"""
@spec to_observe_metadata(map() | nil) :: map()
def to_observe_metadata(nil), do: %{}
def to_observe_metadata(trace_ctx) do
  %{
    jido_trace_id: trace_ctx[:trace_id],
    jido_span_id: trace_ctx[:span_id],
    jido_parent_span_id: trace_ctx[:parent_span_id],
    jido_causation_id: trace_ctx[:causation_id]
  }
  |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  |> Map.new()
end
```

### AgentServer Integration Point

Wire both systems in signal handling:

```elixir
# lib/jido/agent_server.ex

def handle_call({:signal, %Signal{} = signal}, _from, state) do
  # Extract trace from signal, set in process dict
  :ok = Jido.Signal.TraceContext.set_from_signal(signal)
  trace_ctx = Jido.Signal.TraceContext.current()
  
  # Build metadata with trace context
  metadata = 
    %{
      agent_id: state.id,
      agent_module: state.agent_module,
      signal_type: signal.type
    }
    |> Map.merge(Jido.Signal.TraceContext.to_observe_metadata(trace_ctx))
  
  # Wrap signal processing in Observe span
  result = Jido.Observe.with_span(
    [:jido, :agent_server, :signal, :handle],
    metadata,
    fn ->
      process_signal(signal, state)
    end
  )
  
  # Clear trace context
  :ok = Jido.Signal.TraceContext.clear()
  
  # Return result
  case result do
    {:ok, new_state} -> {:reply, :ok, new_state}
    {:error, reason} -> {:reply, {:error, reason}, state}
  end
end
```

### Directive Execution Telemetry

Update `exec_directive_with_telemetry/3` to use Observe:

```elixir
# lib/jido/agent_server.ex

defp exec_directive_with_telemetry(directive, signal, state) do
  directive_type = # ... extract type as before
  
  trace_ctx = Jido.Signal.TraceContext.current()
  
  metadata =
    %{
      agent_id: state.id,
      agent_module: state.agent_module,
      directive_type: directive_type,
      signal_type: signal.type
    }
    |> Map.merge(Jido.Signal.TraceContext.to_observe_metadata(trace_ctx))
  
  Jido.Observe.with_span(
    [:jido, :agent_server, :directive, :exec],
    metadata,
    fn ->
      DirectiveExec.exec(directive, signal, state)
    end
  )
end
```

### Future: OpenTelemetry Integration

When implementing `Jido.Observe.OtelTracer`:

```elixir
defmodule Jido.Observe.OtelTracer do
  @behaviour Jido.Observe.Tracer

  def span_start(event_prefix, metadata) do
    # Extract Jido trace context
    trace_id = metadata[:jido_trace_id]
    parent_span_id = metadata[:jido_parent_span_id]
    
    # Build OTEL span context (reuse trace_id if present)
    otel_ctx = build_otel_context(trace_id, parent_span_id)
    
    # Start OTEL span with Jido trace IDs as attributes
    span = :otel_tracer.start_span(
      event_to_name(event_prefix),
      otel_ctx,
      attributes: [
        {"jido.trace_id", trace_id},
        {"jido.signal_id", metadata[:jido_span_id]},
        {"jido.causation_id", metadata[:jido_causation_id]},
        # ... other metadata
      ]
    )
    
    # Return OTEL span context
    span
  end
  
  def span_stop(otel_span, measurements) do
    # Add measurements as OTEL events/attributes
    :otel_span.add_event(otel_span, "completed", measurements)
    :otel_span.end_span(otel_span)
  end
  
  def span_exception(otel_span, kind, reason, stacktrace) do
    :otel_span.record_exception(otel_span, reason, stacktrace)
    :otel_span.set_status(otel_span, :error, inspect(reason))
    :otel_span.end_span(otel_span)
  end
end
```

### CloudEvents + W3C Trace Context

For cross-system tracing via HTTP/messaging:

**Ingress** (receiving CloudEvents):
```elixir
# Parse W3C traceparent from CloudEvent headers
traceparent = event["traceparent"]
{trace_id, parent_span_id, flags} = parse_traceparent(traceparent)

# Build Jido TraceContext
trace_ctx = %{
  trace_id: trace_id,
  span_id: generate_span_id(),
  parent_span_id: parent_span_id
}

# Set in process dict for signal processing
Jido.Signal.TraceContext.set(trace_ctx)

# Also restore OTEL context if using OtelTracer
:otel_ctx.attach(otel_from_traceparent(traceparent))
```

**Egress** (emitting CloudEvents):
```elixir
# Get current trace context
trace_ctx = Jido.Signal.TraceContext.current()

# Generate W3C traceparent
traceparent = format_traceparent(
  trace_ctx.trace_id,
  trace_ctx.span_id,
  flags: "01"
)

# Attach to outgoing CloudEvent
cloudevent = Map.put(signal, "traceparent", traceparent)
```

### Benefits

1. **Unified trace_id** - Same ID flows through Signal causality and Observe performance
2. **No coupling** - Observe.Tracer doesn't depend on Signal modules
3. **Rich context** - OTEL spans automatically tagged with causal signal IDs
4. **Standards-based** - W3C Trace Context for interop, CloudEvents for transport
5. **Simple adoption** - Existing Observe usage gains trace context automatically

### Non-Goals

- **1:1 span mapping** - One signal can produce many Observe spans (not a problem)
- **Unified context** - Keep TraceContext and OTEL context separate (linked via IDs)
- **Signal-aware tracers** - Tracers see metadata, not Signal structs

---

## Conclusion

Jido has the right primitives (`Trace` extension, directive system, CloudEvents compliance) but lacks the glue code to make correlation automatic. The proposed `TraceContext` helper + DirectiveExec integration provides:

1. **Zero API changes** - existing code gains tracing for free
2. **W3C-compatible** - future OTEL integration is straightforward
3. **Multi-agent native** - handles parent/child, async, scheduled flows
4. **Low effort** - ~200 LOC for basic implementation

This brings Jido to parity with industry-standard distributed tracing systems while maintaining its unique agent-oriented design.

---

## References

- [W3C Trace Context Spec](https://www.w3.org/TR/trace-context/)
- [OpenTelemetry Tracing](https://opentelemetry.io/docs/concepts/signals/traces/)
- [CloudEvents Distributed Tracing Extension](https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/extensions/distributed-tracing.md)
- [Jido Signal Extension System](deps/jido_signal/lib/jido_signal/ext.ex)
- [Current Multi-Agent Example](examples/multi_agent.exs)

# Jido Signal Correlation & Causation Implementation Plan

## Overview

This plan implements automatic trace context propagation and causation tracking across Jido agent boundaries, enabling end-to-end observability of multi-agent workflows.

**Design Principles:**
1. **Zero API changes** - existing code gains tracing automatically
2. **W3C Trace Context aligned** - future OTEL integration is straightforward  
3. **CloudEvents compliant** - uses distributed tracing extension (`traceparent`/`tracestate`)
4. **Multi-agent native** - handles parent/child, async, and scheduled flows
5. **Upstream-first** - generic functionality goes to `jido_signal`

**Architecture:**

```
┌─────────────────────────────────────────────────────────────┐
│                    jido_signal (upstream)                   │
├─────────────────────────────────────────────────────────────┤
│  Jido.Signal.Ext.Trace (existing)                          │
│  Jido.Signal.Trace (NEW - helpers for trace management)    │
│  Jido.Signal.TraceContext (NEW - process-dict context)     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      jido (V2)                              │
├─────────────────────────────────────────────────────────────┤
│  AgentServer integration (ingress/egress tracing)          │
│  DirectiveExec propagation (Emit, Schedule, SpawnAgent)    │
│  System signal tracing (ChildStarted, ChildExit, etc.)     │
│  Telemetry metadata enrichment                             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│               jido_otel (future package)                    │
├─────────────────────────────────────────────────────────────┤
│  Jido.Observe.OtelTracer - OTEL span exporter              │
│  W3C Trace Context HTTP propagation                        │
│  Trace sampling configuration                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Upstream Enhancements to jido_signal

**Goal:** Add generic trace management utilities that any system using `Jido.Signal` can leverage.

### Step 1.1: Add Jido.Signal.Trace Helper Module

**File:** `projects/jido_signal/lib/jido_signal/trace.ex`

**Purpose:** Provide ergonomic helpers for creating, propagating, and managing trace contexts. Works with the existing `Jido.Signal.Ext.Trace` extension.

```elixir
defmodule Jido.Signal.Trace do
  @moduledoc """
  Helper functions for distributed trace management.
  
  Provides utilities for creating and propagating trace contexts
  across signal boundaries. Uses the `correlation` extension 
  (Jido.Signal.Ext.Trace) for storage.
  
  ## Trace Hierarchy
  
  - `trace_id` - Constant across entire workflow (16-byte hex)
  - `span_id` - Unique per signal (8-byte hex)  
  - `parent_span_id` - Links child to parent signal
  - `causation_id` - Signal ID that triggered this signal
  
  ## W3C Trace Context Compatibility
  
  IDs are generated in W3C-compatible format:
  - trace_id: 32 hex chars (128-bit)
  - span_id: 16 hex chars (64-bit)
  
  ## Examples
  
      # Create a new root trace
      ctx = Jido.Signal.Trace.new_root()
      
      # Create child context for emitted signal
      child_ctx = Jido.Signal.Trace.child_of(parent_ctx, parent_signal.id)
      
      # Add trace to signal
      {:ok, traced_signal} = Jido.Signal.Trace.put(signal, ctx)
      
      # Get trace from signal
      ctx = Jido.Signal.Trace.get(signal)
      
      # Ensure signal has trace (add root if missing)
      {:ok, signal, ctx} = Jido.Signal.Trace.ensure(signal)
  """
  
  alias Jido.Signal
  
  @extension_namespace "correlation"
  
  @type trace_context :: %{
    trace_id: String.t(),
    span_id: String.t(),
    parent_span_id: String.t() | nil,
    causation_id: String.t() | nil,
    tracestate: String.t() | nil
  }
  
  @doc """
  Creates a new root trace context.
  
  ## Options
  
  - `:causation_id` - Optional causation reference
  - `:tracestate` - Optional W3C tracestate string
  
  ## Examples
  
      ctx = Trace.new_root()
      ctx = Trace.new_root(causation_id: "external-123")
  """
  @spec new_root(keyword()) :: trace_context()
  def new_root(opts \\ []) do
    %{
      trace_id: generate_trace_id(),
      span_id: generate_span_id(),
      parent_span_id: nil,
      causation_id: opts[:causation_id],
      tracestate: opts[:tracestate]
    }
  end
  
  @doc """
  Creates a child trace context that continues the parent's trace.
  
  The child:
  - Shares the parent's `trace_id`
  - Gets a new unique `span_id`
  - Sets `parent_span_id` to the parent's `span_id`
  - Sets `causation_id` to the causing signal's ID
  - Inherits `tracestate`
  
  ## Examples
  
      parent_ctx = Trace.get(parent_signal)
      child_ctx = Trace.child_of(parent_ctx, parent_signal.id)
  """
  @spec child_of(trace_context(), String.t() | nil) :: trace_context()
  def child_of(%{trace_id: tid, span_id: parent_sid} = parent, causation_id) do
    %{
      trace_id: tid,
      span_id: generate_span_id(),
      parent_span_id: parent_sid,
      causation_id: causation_id,
      tracestate: parent[:tracestate]
    }
  end
  
  @doc """
  Extracts trace context from a signal.
  
  Returns `nil` if the signal has no trace extension.
  """
  @spec get(Signal.t()) :: trace_context() | nil
  def get(%Signal{} = signal) do
    Signal.get_extension(signal, @extension_namespace)
  end
  
  @doc """
  Adds trace context to a signal.
  
  ## Examples
  
      ctx = Trace.new_root()
      {:ok, traced} = Trace.put(signal, ctx)
  """
  @spec put(Signal.t(), trace_context()) :: {:ok, Signal.t()} | {:error, term()}
  def put(%Signal{} = signal, %{} = ctx) do
    Signal.put_extension(signal, @extension_namespace, ctx)
  end
  
  @doc """
  Adds trace context to a signal, raising on error.
  """
  @spec put!(Signal.t(), trace_context()) :: Signal.t()
  def put!(%Signal{} = signal, %{} = ctx) do
    case put(signal, ctx) do
      {:ok, s} -> s
      {:error, reason} -> raise "Failed to add trace: #{inspect(reason)}"
    end
  end
  
  @doc """
  Ensures a signal has trace context.
  
  If the signal already has a trace, returns it unchanged.
  If not, creates a new root trace and adds it.
  
  Returns `{:ok, signal, trace_context}`.
  """
  @spec ensure(Signal.t(), keyword()) :: {:ok, Signal.t(), trace_context()}
  def ensure(%Signal{} = signal, opts \\ []) do
    case get(signal) do
      nil ->
        ctx = new_root(opts)
        {:ok, traced} = put(signal, ctx)
        {:ok, traced, ctx}
        
      ctx ->
        {:ok, signal, ctx}
    end
  end
  
  @doc """
  Formats trace context as W3C `traceparent` header value.
  
  Format: `{version}-{trace-id}-{span-id}-{flags}`
  
  ## Examples
  
      Trace.to_traceparent(ctx)
      #=> "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
  """
  @spec to_traceparent(trace_context()) :: String.t()
  def to_traceparent(%{trace_id: tid, span_id: sid}) do
    "00-#{tid}-#{sid}-01"
  end
  
  @doc """
  Parses a W3C `traceparent` header into trace context.
  
  Returns `nil` if parsing fails.
  
  ## Examples
  
      Trace.from_traceparent("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
      #=> %{trace_id: "4bf92f3577b34da6a3ce929d0e0e4736", span_id: "00f067aa0ba902b7", ...}
  """
  @spec from_traceparent(String.t()) :: trace_context() | nil
  def from_traceparent(traceparent) when is_binary(traceparent) do
    case String.split(traceparent, "-", trim: true) do
      [_version, trace_id, span_id, _flags]
        when byte_size(trace_id) == 32 and byte_size(span_id) == 16 ->
        %{
          trace_id: trace_id,
          span_id: span_id,
          parent_span_id: nil,
          causation_id: nil,
          tracestate: nil
        }
        
      _ ->
        nil
    end
  end
  
  # Generate W3C-compliant 128-bit trace ID (32 hex chars)
  defp generate_trace_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
  
  # Generate W3C-compliant 64-bit span ID (16 hex chars)
  defp generate_span_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
```

**Testing Requirements:**

- `new_root/0,1` generates valid W3C IDs (correct lengths, hex format)
- `child_of/2` shares `trace_id`, gets new `span_id`, sets `parent_span_id`
- `get/1` / `put/2` roundtrip through signal extensions
- `ensure/1,2` adds root trace only when missing
- `to_traceparent/1` / `from_traceparent/1` roundtrip W3C format
- Edge cases: nil parent context, empty tracestate

---

### Step 1.2: Add Jido.Signal.TraceContext (Process Dictionary Context)

**File:** `projects/jido_signal/lib/jido_signal/trace_context.ex`

**Purpose:** Manage trace context in the process dictionary for automatic propagation within a process. Ported and enhanced from V1.

```elixir
defmodule Jido.Signal.TraceContext do
  @moduledoc """
  Process-dictionary-based trace context management.
  
  Stores current trace context in the process dictionary so it can be
  accessed when creating new signals without explicit parameter passing.
  
  ## Usage Pattern
  
  1. **Ingress**: When receiving a signal, set context from the signal
  2. **Processing**: Access context when creating outbound signals
  3. **Egress**: Clear context when done
  
  ## Examples
  
      # At ingress point (e.g., AgentServer.handle_call)
      {signal, ctx} = TraceContext.ensure_from_signal(signal)
      
      # During processing - context available automatically
      ctx = TraceContext.current()
      
      # At egress
      TraceContext.clear()
  
  ## Thread Safety
  
  Process dictionary is per-process, so context is automatically isolated.
  For Task.async or spawn, context must be explicitly passed and restored.
  """
  
  alias Jido.Signal
  alias Jido.Signal.Trace
  
  @trace_context_key :jido_trace_context
  
  @doc """
  Gets the current trace context from the process dictionary.
  
  Returns `nil` if no context is set.
  """
  @spec current() :: Trace.trace_context() | nil
  def current do
    Process.get(@trace_context_key)
  end
  
  @doc """
  Sets the trace context in the process dictionary.
  """
  @spec set(Trace.trace_context()) :: :ok
  def set(context) when is_map(context) do
    Process.put(@trace_context_key, context)
    :ok
  end
  
  @doc """
  Clears the trace context from the process dictionary.
  """
  @spec clear() :: :ok
  def clear do
    Process.delete(@trace_context_key)
    :ok
  end
  
  @doc """
  Extracts trace context from a signal and sets it in the process dictionary.
  
  Returns `:ok` if context was set, `:error` if signal has no trace.
  """
  @spec set_from_signal(Signal.t()) :: :ok | :error
  def set_from_signal(%Signal{} = signal) do
    case Trace.get(signal) do
      nil -> :error
      ctx -> set(ctx)
    end
  end
  
  @doc """
  Ensures trace context is set from a signal.
  
  If the signal has trace context, uses it. Otherwise creates a new root
  trace, adds it to the signal, and sets it as current.
  
  Returns `{signal, trace_context}` where signal may be updated with trace.
  """
  @spec ensure_from_signal(Signal.t(), keyword()) :: {Signal.t(), Trace.trace_context()}
  def ensure_from_signal(%Signal{} = signal, opts \\ []) do
    {:ok, traced_signal, ctx} = Trace.ensure(signal, opts)
    set(ctx)
    {traced_signal, ctx}
  end
  
  @doc """
  Builds child context from current process context.
  
  If no current context exists, creates a new root.
  """
  @spec child_context(String.t() | nil) :: Trace.trace_context()
  def child_context(causation_id \\ nil) do
    case current() do
      nil -> Trace.new_root(causation_id: causation_id)
      parent -> Trace.child_of(parent, causation_id)
    end
  end
  
  @doc """
  Adds current trace context as child to an outbound signal.
  
  Creates child context (new span_id, parent_span_id = current span_id)
  and adds it to the signal.
  
  If no current context exists, creates a new root trace.
  """
  @spec propagate_to(Signal.t(), String.t() | nil) :: {:ok, Signal.t()} | {:error, term()}
  def propagate_to(%Signal{} = signal, causation_id \\ nil) do
    ctx = child_context(causation_id)
    Trace.put(signal, ctx)
  end
  
  @doc """
  Converts current trace context to metadata map for telemetry/observability.
  
  Returns a map with standardized keys prefixed with `jido_` for
  integration with telemetry handlers and Observe.Tracer implementations.
  """
  @spec to_telemetry_metadata() :: map()
  def to_telemetry_metadata do
    to_telemetry_metadata(current())
  end
  
  @spec to_telemetry_metadata(Trace.trace_context() | nil) :: map()
  def to_telemetry_metadata(nil), do: %{}
  def to_telemetry_metadata(ctx) do
    %{
      jido_trace_id: ctx[:trace_id],
      jido_span_id: ctx[:span_id],
      jido_parent_span_id: ctx[:parent_span_id],
      jido_causation_id: ctx[:causation_id]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
  
  @doc """
  Wraps a function with trace context preservation.
  
  Captures current context before the function runs, executes the function,
  then clears context. Useful for GenServer callbacks.
  
  ## Examples
  
      TraceContext.with_context(signal, fn ->
        # context is set from signal
        do_work()
      end)
      # context is cleared after
  """
  @spec with_context(Signal.t(), (-> result)) :: result when result: term()
  def with_context(%Signal{} = signal, fun) when is_function(fun, 0) do
    {_signal, _ctx} = ensure_from_signal(signal)
    try do
      fun.()
    after
      clear()
    end
  end
end
```

**Testing Requirements:**

- `set/1` / `current/0` / `clear/0` work correctly with process dictionary
- `set_from_signal/1` extracts trace from signal extensions
- `ensure_from_signal/1` adds root trace when missing
- `child_context/1` creates proper child with parent_span_id linkage
- `propagate_to/2` adds child trace to outbound signals
- `to_telemetry_metadata/1` returns compact map with `jido_*` prefix
- `with_context/2` properly sets and clears context around function execution
- Context isolation: spawned processes don't inherit context

---

### Step 1.3: Enhance Jido.Signal.Ext.Trace for W3C Compliance

**File:** `projects/jido_signal/lib/jido_signal/ext/trace.ex`

**Enhancement:** Add optional `traceparent` and `tracestate` serialization for full CloudEvents distributed tracing extension support.

```elixir
defmodule Jido.Signal.Ext.Trace do
  @moduledoc """
  Trace extension for Jido Signal correlation and debugging.

  Provides fields for tracking signal causation:
  * `trace_id` - constant for entire call chain (W3C 128-bit, 32 hex chars)
  * `span_id` - unique for this signal (W3C 64-bit, 16 hex chars)
  * `parent_span_id` - span that triggered this signal
  * `causation_id` - signal ID that caused this signal
  * `tracestate` - optional W3C tracestate for vendor-specific data

  ## CloudEvents Serialization

  Serializes to CloudEvents distributed tracing extension attributes:
  - `traceparent` - W3C trace context header format
  - `tracestate` - optional vendor state (if present)
  
  Also includes convenience attributes for non-HTTP consumers:
  - `trace_id`, `span_id`, `parent_span_id`, `causation_id`
  """

  use Jido.Signal.Ext,
    namespace: "correlation",
    schema: [
      trace_id: [type: :string, required: true, doc: "W3C trace identifier (32 hex chars)"],
      span_id: [type: :string, required: true, doc: "W3C span identifier (16 hex chars)"],
      parent_span_id: [type: :string, doc: "Parent span identifier"],
      causation_id: [type: :string, doc: "Causing signal ID"],
      tracestate: [type: :string, doc: "W3C tracestate string"]
    ]

  @w3c_version "00"
  @sampled_flag "01"

  @impl true
  def to_attrs(%{trace_id: trace_id, span_id: span_id} = data) do
    # Build W3C traceparent for CloudEvents distributed tracing
    traceparent = Enum.join([@w3c_version, trace_id, span_id, @sampled_flag], "-")
    
    %{
      # CloudEvents distributed tracing extension
      "traceparent" => traceparent,
      # Convenience attributes for direct access
      "trace_id" => trace_id,
      "span_id" => span_id
    }
    |> maybe_put("tracestate", data[:tracestate])
    |> maybe_put("parent_span_id", data[:parent_span_id])
    |> maybe_put("causation_id", data[:causation_id])
  end

  @impl true
  def from_attrs(attrs) do
    # Try traceparent first (CloudEvents distributed tracing)
    case parse_traceparent(attrs) do
      nil -> parse_legacy_attrs(attrs)
      ctx -> ctx
    end
  end
  
  # Parse W3C traceparent format: "00-{trace_id}-{span_id}-{flags}"
  defp parse_traceparent(%{"traceparent" => tp} = attrs) when is_binary(tp) do
    case String.split(tp, "-", trim: true) do
      [@w3c_version, trace_id, span_id, _flags]
        when byte_size(trace_id) == 32 and byte_size(span_id) == 16 ->
        %{
          trace_id: trace_id,
          span_id: span_id
        }
        |> maybe_put_field(:tracestate, attrs["tracestate"])
        |> maybe_put_field(:parent_span_id, attrs["parent_span_id"])
        |> maybe_put_field(:causation_id, attrs["causation_id"])
        
      _ ->
        nil
    end
  end
  defp parse_traceparent(_), do: nil
  
  # Fallback to direct attribute parsing
  defp parse_legacy_attrs(%{"trace_id" => trace_id, "span_id" => span_id} = attrs) do
    %{
      trace_id: trace_id,
      span_id: span_id
    }
    |> maybe_put_field(:tracestate, attrs["tracestate"])
    |> maybe_put_field(:parent_span_id, attrs["parent_span_id"])
    |> maybe_put_field(:causation_id, attrs["causation_id"])
  end
  defp parse_legacy_attrs(%{"trace_id" => trace_id} = attrs) do
    # Handle partial data (missing span_id)
    %{trace_id: trace_id, span_id: attrs["span_id"]}
    |> maybe_put_field(:tracestate, attrs["tracestate"])
    |> maybe_put_field(:parent_span_id, attrs["parent_span_id"])
    |> maybe_put_field(:causation_id, attrs["causation_id"])
  end
  defp parse_legacy_attrs(_), do: nil

  defp maybe_put_field(map, _key, nil), do: map
  defp maybe_put_field(map, key, value), do: Map.put(map, key, value)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
```

**Testing Requirements:**

- `to_attrs/1` generates valid `traceparent` in W3C format
- `from_attrs/1` parses `traceparent` correctly
- Roundtrip: `to_attrs` → JSON → `from_attrs` preserves all fields
- Backward compatibility: still works with direct `trace_id`/`span_id` attrs
- `tracestate` preserved through serialization
- Invalid traceparent falls back to legacy parsing

---

## Phase 2: Jido V2 AgentServer Integration

**Goal:** Wire tracing into AgentServer signal processing so all signals automatically get trace context.

### Step 2.1: Update AgentServer Signal Ingress

**File:** `projects/jido/lib/jido/agent_server.ex`

**Changes:**

1. Add `alias Jido.Signal.TraceContext` 
2. In `handle_call({:signal, signal}, ...)` and `handle_cast({:signal, signal}, ...)`:
   - Call `TraceContext.ensure_from_signal(signal)` to set context
   - Use the traced signal for processing
   - Clear context in an `after` block or via `with_context/2`

3. Enhance telemetry metadata with trace context

```elixir
# In handle_call
def handle_call({:signal, %Signal{} = signal}, _from, state) do
  # Ensure trace context is set and signal has trace
  {traced_signal, _ctx} = Jido.Signal.TraceContext.ensure_from_signal(signal)
  
  try do
    case process_signal(traced_signal, state) do
      {:ok, new_state} ->
        {:reply, {:ok, new_state.agent}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  after
    Jido.Signal.TraceContext.clear()
  end
end

# Same pattern for handle_cast
def handle_cast({:signal, %Signal{} = signal}, state) do
  {traced_signal, _ctx} = Jido.Signal.TraceContext.ensure_from_signal(signal)
  
  try do
    case process_signal(traced_signal, state) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, _reason, new_state} -> {:noreply, new_state}
    end
  after
    Jido.Signal.TraceContext.clear()
  end
end
```

**Telemetry Enhancement:**

```elixir
defp process_signal(%Signal{} = signal, %State{signal_router: router} = state) do
  start_time = System.monotonic_time()
  agent_module = state.agent_module

  # Include trace context in telemetry metadata
  trace_meta = Jido.Signal.TraceContext.to_telemetry_metadata()
  
  metadata = 
    %{
      agent_id: state.id,
      agent_module: agent_module,
      signal_type: signal.type
    }
    |> Map.merge(trace_meta)

  emit_telemetry(
    [:jido, :agent_server, :signal, :start],
    %{system_time: System.system_time()},
    metadata
  )
  # ... rest of processing
end

defp exec_directive_with_telemetry(directive, signal, state) do
  start_time = System.monotonic_time()

  directive_type = directive.__struct__ |> Module.split() |> List.last()

  # Include trace context in directive telemetry
  trace_meta = Jido.Signal.TraceContext.to_telemetry_metadata()

  metadata =
    %{
      agent_id: state.id,
      agent_module: state.agent_module,
      directive_type: directive_type,
      signal_type: signal.type
    }
    |> Map.merge(trace_meta)

  # ... rest unchanged
end
```

**Testing Requirements:**

- Signal without trace gets root trace added at ingress
- Signal with existing trace preserves it  
- TraceContext.current() returns context during cmd/2 execution
- Telemetry events include `jido_trace_id`, `jido_span_id` in metadata
- Context is cleared after processing (no leakage)

---

### Step 2.2: Update Emit Directive Executor

**File:** `projects/jido/lib/jido/agent_server/directive_executors.ex`

**Change:** Propagate trace context to emitted signals.

```elixir
defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.Emit do
  @moduledoc false

  require Logger
  alias Jido.Signal.TraceContext

  def exec(%{signal: signal, dispatch: dispatch}, input_signal, state) do
    # Propagate trace context: create child trace linked to input signal
    traced_signal = 
      case TraceContext.propagate_to(signal, input_signal.id) do
        {:ok, s} -> s
        {:error, _} -> signal  # Fallback: emit without trace if propagation fails
      end
    
    cfg = dispatch || state.default_dispatch

    case cfg do
      nil ->
        Logger.debug("Emit directive with no dispatch config, signal: #{traced_signal.type}")

      cfg ->
        if Code.ensure_loaded?(Jido.Signal.Dispatch) do
          task_sup =
            if state.jido, do: Jido.task_supervisor_name(state.jido), else: Jido.TaskSupervisor

          Task.Supervisor.start_child(task_sup, fn ->
            Jido.Signal.Dispatch.dispatch(traced_signal, cfg)
          end)
        else
          Logger.warning("Jido.Signal.Dispatch not available, skipping emit")
        end
    end

    {:async, nil, state}
  end
end
```

**Testing Requirements:**

- Emitted signal has new `span_id` (different from input)
- Emitted signal has `parent_span_id` = input signal's `span_id`
- Emitted signal has `causation_id` = input signal's `id`
- Emitted signal shares `trace_id` with input signal
- Works when input signal has no trace (creates root)

---

### Step 2.3: Update Schedule Directive Executor

**File:** `projects/jido/lib/jido/agent_server/directive_executors.ex`

**Change:** Propagate trace to scheduled signals.

```elixir
defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.Schedule do
  @moduledoc false

  alias Jido.AgentServer.Signal.Scheduled
  alias Jido.Signal.TraceContext

  def exec(%{delay_ms: delay, message: message}, input_signal, state) do
    signal =
      case message do
        %Jido.Signal{} = s ->
          s

        other ->
          Scheduled.new!(
            %{message: other},
            source: "/agent/#{state.id}"
          )
      end
    
    # Propagate trace context to scheduled signal
    traced_signal = 
      case TraceContext.propagate_to(signal, input_signal.id) do
        {:ok, s} -> s
        {:error, _} -> signal
      end

    Process.send_after(self(), {:scheduled_signal, traced_signal}, delay)
    {:ok, state}
  end
end
```

**Testing Requirements:**

- Scheduled signal inherits `trace_id` from input signal
- Scheduled signal has new `span_id`
- After firing, signal arrives with correct trace linkage

---

### Step 2.4: Update SpawnAgent Directive Executor

**File:** `projects/jido/lib/jido/agent_server/directive_executors.ex`

**Change:** No direct change needed since SpawnAgent doesn't emit signals directly. However, ensure that signals sent TO child agents (via Emit) and signals FROM child agents (ChildStarted) carry trace context.

The `notify_parent_of_startup` already creates a `ChildStarted` signal. Add trace propagation there:

**File:** `projects/jido/lib/jido/agent_server.ex`

```elixir
defp notify_parent_of_startup(%State{parent: %ParentRef{} = parent} = state)
     when is_pid(parent.pid) do
  child_started =
    ChildStarted.new!(
      %{
        parent_id: parent.id,
        child_id: state.id,
        child_module: state.agent_module,
        tag: parent.tag,
        pid: self(),
        meta: parent.meta || %{}
      },
      source: "/agent/#{state.id}"
    )

  # Create trace for child startup notification
  # This is a new trace root since child is starting fresh
  ctx = Jido.Signal.Trace.new_root()
  {:ok, traced_child_started} = Jido.Signal.Trace.put(child_started, ctx)

  _ = cast(parent.pid, traced_child_started)
  :ok
end
```

Similarly for `ChildExit` and `Orphaned` signals:

```elixir
defp handle_child_down(%State{} = state, pid, reason) do
  {tag, state} = State.remove_child_by_pid(state, pid)

  if tag do
    Logger.debug("AgentServer #{state.id} child #{inspect(tag)} exited: #{inspect(reason)}")

    signal =
      ChildExit.new!(
        %{tag: tag, pid: pid, reason: reason},
        source: "/agent/#{state.id}"
      )
    
    # Add trace - this is an event in the parent's context
    traced_signal = 
      case Jido.Signal.TraceContext.propagate_to(signal, nil) do
        {:ok, s} -> s
        {:error, _} -> signal
      end

    case process_signal(traced_signal, state) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, _reason, ns} -> {:noreply, ns}
    end
  else
    {:noreply, state}
  end
end
```

**Testing Requirements:**

- ChildStarted signal has trace context
- ChildExit signal has trace context  
- Orphaned signal has trace context
- Parent can correlate child signals via shared trace

---

## Phase 3: Multi-Agent Integration Testing

**Goal:** Verify end-to-end trace propagation across agent hierarchies.

### Step 3.1: Create Integration Test Suite

**File:** `projects/jido/test/jido/agent_server/trace_propagation_test.exs`

```elixir
defmodule Jido.AgentServer.TracePropagationTest do
  use ExUnit.Case, async: true
  
  alias Jido.Signal
  alias Jido.Signal.Trace
  alias Jido.AgentServer
  
  # Test agents defined in test support
  
  describe "single agent tracing" do
    test "signal without trace gets root trace at ingress" do
      {:ok, pid} = AgentServer.start(agent: TestEchoAgent)
      
      signal = Signal.new!("test.event", %{value: 1}, source: "/test")
      assert Trace.get(signal) == nil
      
      {:ok, _agent} = AgentServer.call(pid, signal)
      
      # Verify via telemetry or internal state that trace was added
    end
    
    test "signal with trace preserves existing trace_id" do
      {:ok, pid} = AgentServer.start(agent: TestEchoAgent)
      
      ctx = Trace.new_root()
      {:ok, traced_signal} = Signal.new!("test.event", %{value: 1}, source: "/test")
                              |> Trace.put(ctx)
      
      {:ok, _agent} = AgentServer.call(pid, traced_signal)
      
      # Verify trace_id preserved
    end
  end
  
  describe "emit directive propagation" do
    test "emitted signal has child trace context" do
      # Set up agent that emits a signal on command
      # Capture emitted signal and verify trace linkage
    end
    
    test "emitted signal causation_id is input signal id" do
      # Verify causation_id = input signal's id
    end
  end
  
  describe "parent-child agent tracing" do
    test "coordinator → worker → coordinator flow preserves trace_id" do
      # Spawn coordinator that spawns worker
      # Send command to coordinator
      # Worker processes and replies to parent
      # Verify entire flow shares same trace_id
    end
    
    test "child_started signal has trace context" do
      # Spawn child, capture ChildStarted signal
      # Verify it has trace
    end
  end
  
  describe "scheduled signal tracing" do
    test "scheduled signal preserves trace context" do
      # Send signal that causes Schedule directive
      # Wait for scheduled delivery
      # Verify trace_id preserved
    end
  end
  
  describe "telemetry integration" do
    test "telemetry events include trace metadata" do
      handler_id = :test_trace_telemetry
      
      :telemetry.attach(
        handler_id,
        [:jido, :agent_server, :signal, :start],
        fn _event, _measurements, metadata, _config ->
          send(self(), {:telemetry, metadata})
        end,
        nil
      )
      
      {:ok, pid} = AgentServer.start(agent: TestEchoAgent)
      signal = Signal.new!("test.event", %{}, source: "/test")
      AgentServer.call(pid, signal)
      
      assert_receive {:telemetry, metadata}
      assert is_binary(metadata[:jido_trace_id])
      assert is_binary(metadata[:jido_span_id])
      
      :telemetry.detach(handler_id)
    end
  end
end
```

**Testing Matrix:**

| Scenario | Expected Behavior |
|----------|------------------|
| Ingress: no trace | Create root trace, add to signal |
| Ingress: has trace | Preserve existing trace |
| Emit | Child span with parent_span_id linked |
| Schedule | Child span with parent_span_id linked |
| SpawnAgent | New root trace for child startup |
| ChildStarted | Has trace context |
| ChildExit | Has trace context |
| emit_to_parent | Child span back to parent |
| emit_to_pid | Child span to target |
| Telemetry | All events have trace metadata |

---

## Phase 4: Documentation and Examples

### Step 4.1: Update jido_signal README

Add section on distributed tracing with examples.

### Step 4.2: Update Jido README/Guides  

Add guide on observability including:
- How trace context flows through agents
- Viewing traces in telemetry
- Future OTEL integration path

### Step 4.3: Update Multi-Agent Example

Enhance `examples/multi_agent.exs` to demonstrate trace propagation.

---

## Phase 5: Future OTEL Integration Path (Design Only)

**Purpose:** Document how `jido_otel` package would integrate.

### Jido.Observe.Tracer Behaviour

```elixir
defmodule Jido.Observe.Tracer do
  @moduledoc """
  Behaviour for span-based tracing implementations.
  
  Implementations receive telemetry-style metadata that includes
  Jido trace context (jido_trace_id, jido_span_id, etc.).
  """
  
  @callback span_start(event :: [atom()], metadata :: map()) :: span :: term()
  @callback span_stop(span :: term(), measurements :: map()) :: :ok
  @callback span_exception(span :: term(), kind :: atom(), reason :: term(), stacktrace :: list()) :: :ok
end
```

### Jido.Observe Module

```elixir
defmodule Jido.Observe do
  @moduledoc """
  Observability wrapper for spans and metrics.
  """
  
  @tracer Application.compile_env(:jido, :tracer, Jido.Observe.NoopTracer)
  
  def with_span(event, metadata, fun) do
    span = @tracer.span_start(event, metadata)
    try do
      result = fun.()
      @tracer.span_stop(span, %{})
      result
    rescue
      e ->
        @tracer.span_exception(span, :error, e, __STACKTRACE__)
        reraise e, __STACKTRACE__
    end
  end
end
```

### jido_otel Package

```elixir
defmodule Jido.Observe.OtelTracer do
  @behaviour Jido.Observe.Tracer
  
  def span_start(event, metadata) do
    # Extract Jido trace context
    trace_id = metadata[:jido_trace_id]
    parent_span_id = metadata[:jido_parent_span_id]
    
    # Build OTEL context, reusing trace_id
    otel_ctx = build_otel_context(trace_id, parent_span_id)
    
    # Start OTEL span
    :otel_tracer.start_span(
      event_to_name(event),
      otel_ctx,
      attributes: Map.to_list(metadata)
    )
  end
  
  # ... span_stop, span_exception implementations
end
```

---

## Implementation Sequence

### Batch 1: Upstream jido_signal (Can be done in parallel by one subagent)

1. **Step 1.1**: Add `Jido.Signal.Trace` helper module
2. **Step 1.2**: Add `Jido.Signal.TraceContext` module  
3. **Step 1.3**: Enhance `Jido.Signal.Ext.Trace` for W3C compliance
4. **Tests**: Comprehensive unit tests for all three modules

**Verification:**
```bash
cd projects/jido_signal
mix test test/jido_signal/trace_test.exs
mix test test/jido_signal/trace_context_test.exs
mix test test/jido_signal/ext/trace_test.exs
mix quality
```

### Batch 2: Jido V2 AgentServer Integration (Depends on Batch 1)

5. **Step 2.1**: Update AgentServer signal ingress
6. **Step 2.2**: Update Emit directive executor  
7. **Step 2.3**: Update Schedule directive executor
8. **Step 2.4**: Update system signals (ChildStarted, ChildExit, Orphaned)

**Verification:**
```bash
cd projects/jido
mix test test/jido/agent_server_test.exs
mix quality
```

### Batch 3: Integration Testing (Depends on Batch 2)

9. **Step 3.1**: Create comprehensive integration test suite
10. **Run full test suite**

**Verification:**
```bash
cd projects/jido
mix test test/jido/agent_server/trace_propagation_test.exs
mix test
```

### Batch 4: Documentation (Can run in parallel with Batch 3)

11. **Step 4.1-4.3**: Update documentation and examples

---

## Testing Strategy

### Unit Tests (Per Module)

| Module | Test File | Key Scenarios |
|--------|-----------|---------------|
| `Jido.Signal.Trace` | `trace_test.exs` | ID generation, child_of, get/put, traceparent |
| `Jido.Signal.TraceContext` | `trace_context_test.exs` | PDict ops, propagation, telemetry metadata |
| `Jido.Signal.Ext.Trace` | `ext/trace_test.exs` | Serialization, W3C compliance |

### Integration Tests

| Test Suite | Scope |
|------------|-------|
| `trace_propagation_test.exs` | Full AgentServer trace flow |
| Multi-agent hierarchy | Parent/child trace correlation |
| Scheduled signals | Async trace preservation |
| Telemetry | Metadata enrichment |

### Property-Based Tests (Optional Enhancement)

- Trace ID generation uniqueness
- Child trace invariants (trace_id preserved, span_id unique)
- Serialization roundtrip

### Manual Verification

1. Run `examples/multi_agent.exs` with telemetry handler
2. Verify trace_id consistent across all signals in workflow
3. Verify parent_span_id chain is correct

---

## Success Criteria

1. **Zero API changes** - Existing code works unchanged
2. **Automatic tracing** - All signals processed by AgentServer get trace context
3. **Correct propagation** - Emitted/scheduled signals maintain trace hierarchy
4. **Telemetry enrichment** - All telemetry events include trace metadata
5. **W3C compatibility** - `traceparent` format correct for future OTEL
6. **Tests passing** - All unit and integration tests green
7. **Quality checks** - `mix quality` passes in both projects

---

## Estimated Effort

| Phase | Effort | Dependencies |
|-------|--------|--------------|
| Phase 1: Upstream | 3-4 hours | None |
| Phase 2: AgentServer | 2-3 hours | Phase 1 |
| Phase 3: Integration Tests | 2-3 hours | Phase 2 |
| Phase 4: Documentation | 1-2 hours | Phase 2 |
| **Total** | **8-12 hours** | |

---

## References

- [W3C Trace Context Spec](https://www.w3.org/TR/trace-context/)
- [CloudEvents Distributed Tracing Extension](https://github.com/cloudevents/spec/blob/main/cloudevents/extensions/distributed-tracing.md)
- [OpenTelemetry Elixir](https://github.com/open-telemetry/opentelemetry-erlang)
- Jido V1 `Jido.Signal.TraceContext` (projects/jido_v1)

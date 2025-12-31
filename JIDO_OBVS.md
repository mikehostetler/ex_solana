# JIDO_OBVS.md – Observability Plan for Jido Agents

## Executive Summary

This document outlines a comprehensive plan to bring Jido's observability for AI/LLM agents (especially ReAct) to parity with—and beyond—Mastra's TypeScript Agent SDK, using Elixir-native tools: `:telemetry`, `Logger`, and OpenTelemetry.

**Key Goals:**
- Add AI- and ReAct-specific telemetry (LLM calls, tool calls, reasoning steps)
- Integrate OpenTelemetry tracing with proper span hierarchies
- Provide structured logging with trace correlation
- Support external exporters (Langfuse, OpenTelemetry, Arize Phoenix)
- Implement sensitive data redaction for prompts/completions
- Make deep debugging easy to toggle via configuration and `cond_log/4`

---

## 1. Current State Analysis

### 1.1 What We Have

**`Jido.Telemetry` (lib/jido/telemetry.ex):**
- Telemetry events for agent commands, strategy lifecycle, AgentServer operations
- Helpers: `span_agent_cmd/3`, `span_strategy/4`
- Logger-based event handlers

**`Jido.Util.cond_log/4` (lib/jido/util.ex):**
- Conditional logging based on threshold vs. message level
- Enables runtime-configurable debug output

**`Jido.AI.Strategy.ReAct` (lib/jido/ai/strategy/react.ex):**
- Strategy adapter that converts instructions to machine messages
- Uses `Jido.AI.ReAct.Machine` for pure state transitions
- Emits directives: `ReqLLMStream`, `ToolExec`
- **No telemetry** for LLM calls, tool execution, or per-step metrics

**`Jido.AI.ReAct.Machine` (lib/jido/ai/react/machine.ex):**
- Pure state machine using Fsmx for state transitions
- States: `:idle` → `:awaiting_llm` → `:awaiting_tool` → `:completed` / `:error`
- Tracks: iteration, conversation, pending_tool_calls, streaming_text, streaming_thinking
- Returns directives: `{:call_llm_stream, id, context}`, `{:exec_tool, id, name, args}`

**`Jido.AI.Directive` (lib/jido/ai/directive.ex):**
- `ReqLLMStream` - Streams LLM response via ReqLLM, sends `reqllm.partial` and `reqllm.result` signals
- `ToolExec` - Executes Jido.Action as tool, sends `ai.tool_result` signal
- DirectiveExec implementations handle async execution with error catching

### 1.2 Key Gaps (vs. Mastra)

| Gap | Description |
|-----|-------------|
| **No AI-specific telemetry** | LLM calls (model, provider, tokens, latency), prompts/completions |
| **No ReAct observability** | Run/step lifecycle, failures, stopping reasons, reasoning traces |
| **No tool-call tracing** | Tool name, input/output, latency, errors |
| **No trace hierarchy** | Agents, strategies, ReAct loops, tools not connected via spans |
| **No trace ID correlation** | Logs and traces not linked |
| **No redaction pipeline** | Prompts/completions exposed in logs/exports |
| **No sampling strategy** | Heavy payloads always captured |

---

## 2. Feature Mapping: Mastra → Elixir/Jido

| Mastra Feature | Jido / Elixir Implementation |
|----------------|------------------------------|
| AI Tracing (LLM calls, tokens, latency) | `:telemetry` events + OpenTelemetry spans |
| Agent execution tracing | ReAct step/tool telemetry; spans per run/step/action |
| Workflow / step tracing | `[:jido, :ai, :react, :step, ...]` events + OTel spans |
| Structured logging w/ context | `Logger` with metadata (agent_id, trace_id, step_no) |
| Trace/span hierarchy | `OpenTelemetry.Tracer.with_span/2`, nested spans |
| Exporters (Langfuse, OTEL, etc.) | OTel exporters + thin `:telemetry` adapters |
| Span processors, redaction | Custom span processors + sanitizer module |
| Runtime context extraction | Standardized `context` map + Logger metadata |
| Trace IDs & distributed correlation | OTel context + `trace_id` in Logger |
| Sampling strategies | OTel sampler config + app-level payload sampling |

---

## 3. Proposed Telemetry Events

### 3.1 LLM Operations

```elixir
# Events
[:jido, :ai, :llm, :request, :start]
[:jido, :ai, :llm, :request, :stop]
[:jido, :ai, :llm, :request, :exception]
[:jido, :ai, :llm, :stream, :chunk]  # optional, for streaming
```

**Measurements:**
- `:system_time` (start)
- `:duration` (stop/exception)
- `:prompt_tokens`, `:completion_tokens`, `:total_tokens`
- `:input_bytes`, `:output_bytes`
- For streaming: `:chunk_index`, `:chunk_tokens`

**Metadata:**
- `:provider` (e.g., `:anthropic`, `:openai`)
- `:model` (e.g., `"claude-haiku"`)
- `:temperature`, `:max_tokens`, `:stream`
- `:agent_id`, `:strategy`, `:react_run_id`, `:react_step_number`
- `:prompt` (redacted/truncated)
- `:completion` / `:completion_preview` (redacted/truncated)
- `:trace_id`, `:span_id`
- `:error`, `:kind`, `:stacktrace` (for exceptions)

### 3.2 ReAct Loop

```elixir
# Run lifecycle
[:jido, :ai, :react, :run, :start]
[:jido, :ai, :react, :run, :stop]
[:jido, :ai, :react, :run, :exception]

# Per-step lifecycle
[:jido, :ai, :react, :step, :start]
[:jido, :ai, :react, :step, :stop]
[:jido, :ai, :react, :step, :exception]
```

**Measurements:**
- `:duration` per run and per step
- `:trajectory_length` at end of run

**Metadata:**
- `:react_run_id`, `:step_number`, `:max_steps`
- `:agent_id`, `:strategy`
- `:question` (truncated preview)
- `:reason` (`:answer_found`, `:max_steps_reached`, error atoms)
- `:tools_used` map
- `:thought`, `:action`, `:action_input`, `:observation` (redacted)
- `:final_answer` (when present)

### 3.3 Tool Calls

```elixir
[:jido, :ai, :tool, :invoke, :start]
[:jido, :ai, :tool, :invoke, :stop]
[:jido, :ai, :tool, :invoke, :exception]
```

**Measurements:**
- `:duration`
- `:input_bytes`, `:output_bytes`

**Metadata:**
- `:tool_name`, `:tool_module`
- `:action_input` (redacted/truncated)
- `:observation` preview
- `:react_run_id`, `:react_step_number`
- `:agent_id`, `:strategy`
- `:error`, `:kind`, `:stacktrace` (for exceptions)

---

## 4. Instrumentation Points

The ReAct architecture has clear instrumentation points:

### 4.1 DirectiveExec for ReqLLMStream (lib/jido/ai/directive.ex)

**Where:** `Jido.AgentServer.DirectiveExec.exec/3` for `ReqLLMStream`

```elixir
# BEFORE: stream_with_callbacks/8
# Add telemetry around the entire LLM streaming operation

def exec(directive, _input_signal, state) do
  # Emit [:jido, :ai, :llm, :request, :start] here
  
  Task.Supervisor.start_child(Jido.TaskSupervisor, fn ->
    result = stream_with_callbacks(...)  # Already sends partial signals
    
    # Emit [:jido, :ai, :llm, :request, :stop] or :exception here
    signal = Signal.ReqLLMResult.new!(...)
    Jido.AgentServer.cast(agent_pid, signal)
  end)
end
```

**Captures:**
- LLM call start/stop/duration
- Model, temperature, max_tokens
- Token counts from response
- Streaming chunk counts

### 4.2 DirectiveExec for ToolExec (lib/jido/ai/directive.ex)

**Where:** `Jido.AgentServer.DirectiveExec.exec/3` for `ToolExec`

```elixir
# BEFORE: Jido.Exec.run/3 call
# Add telemetry around tool execution

Task.Supervisor.start_child(Jido.TaskSupervisor, fn ->
  # Emit [:jido, :ai, :tool, :invoke, :start]
  result = Jido.Exec.run(action_module, normalized_args, context)
  # Emit [:jido, :ai, :tool, :invoke, :stop] or :exception
  
  signal = Signal.ToolResult.new!(...)
  Jido.AgentServer.cast(agent_pid, signal)
end)
```

**Captures:**
- Tool name, action module
- Execution duration
- Input/output sizes
- Success/failure

### 4.3 ReAct Machine State Transitions (lib/jido/ai/react/machine.ex)

**Where:** `Machine.update/3` returns `{machine, directives}`

The Machine is pure, so telemetry should be emitted by the **Strategy** when it calls `Machine.update/3`:

```elixir
# In Jido.AI.Strategy.ReAct.process_instruction/2

{machine, directives} = Machine.update(machine, msg, env)

# Emit telemetry based on state transition:
# - {:start, ...} → [:jido, :ai, :react, :run, :start]
# - status changed to :completed → [:jido, :ai, :react, :run, :stop]
# - directives include :call_llm_stream → [:jido, :ai, :react, :step, :start]
# - directives include :exec_tool → tool invocation about to happen
```

**Captures:**
- Run ID, iteration number
- State transitions (idle → awaiting_llm → awaiting_tool → completed)
- Termination reason
- Step-level timing

---

## 5. New Module: `Jido.AI.Telemetry`

```elixir
defmodule Jido.AI.Telemetry do
  @moduledoc """
  AI-specific telemetry for LLM calls, ReAct loops, and tool invocations.
  
  Complements `Jido.Telemetry` with AI-focused observability.
  """
  
  require Logger
  
  @doc """
  Wraps an LLM call with telemetry events and optional OTel span.
  
  ## Examples
  
      Jido.AI.Telemetry.span_llm_call(%{
        provider: :anthropic,
        model: "claude-haiku",
        agent_id: agent.id
      }, fn ->
        ReqLLM.chat(messages, opts)
      end)
  """
  @spec span_llm_call(map(), (-> result)) :: result when result: term()
  def span_llm_call(attrs, func) when is_function(func, 0) do
    start_time = System.monotonic_time()
    meta = build_llm_metadata(attrs)
    
    :telemetry.execute(
      [:jido, :ai, :llm, :request, :start],
      %{system_time: System.system_time()},
      meta
    )
    
    try do
      result = func.()
      measurements = Map.merge(
        %{duration: System.monotonic_time() - start_time},
        extract_token_measurements(result)
      )
      
      :telemetry.execute(
        [:jido, :ai, :llm, :request, :stop],
        measurements,
        enrich_with_completion(meta, result)
      )
      
      result
    catch
      kind, reason ->
        :telemetry.execute(
          [:jido, :ai, :llm, :request, :exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(meta, %{kind: kind, error: reason, stacktrace: __STACKTRACE__})
        )
        
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end
  
  @doc """
  Wraps a ReAct run with telemetry events.
  """
  @spec span_react_run(map(), (-> result)) :: result when result: term()
  def span_react_run(attrs, func) when is_function(func, 0) do
    run_id = Jido.Util.generate_id()
    start_time = System.monotonic_time()
    meta = Map.put(attrs, :react_run_id, run_id)
    
    :telemetry.execute(
      [:jido, :ai, :react, :run, :start],
      %{system_time: System.system_time()},
      meta
    )
    
    try do
      result = func.(run_id)
      
      :telemetry.execute(
        [:jido, :ai, :react, :run, :stop],
        %{duration: System.monotonic_time() - start_time},
        enrich_with_result(meta, result)
      )
      
      result
    catch
      kind, reason ->
        :telemetry.execute(
          [:jido, :ai, :react, :run, :exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(meta, %{kind: kind, error: reason, stacktrace: __STACKTRACE__})
        )
        
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end
  
  @doc """
  Wraps a ReAct step with telemetry events.
  """
  @spec span_react_step(map(), (-> result)) :: result when result: term()
  def span_react_step(attrs, func) when is_function(func, 0) do
    start_time = System.monotonic_time()
    
    :telemetry.execute(
      [:jido, :ai, :react, :step, :start],
      %{system_time: System.system_time()},
      attrs
    )
    
    try do
      result = func.()
      
      :telemetry.execute(
        [:jido, :ai, :react, :step, :stop],
        %{duration: System.monotonic_time() - start_time},
        enrich_step_metadata(attrs, result)
      )
      
      result
    catch
      kind, reason ->
        :telemetry.execute(
          [:jido, :ai, :react, :step, :exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(attrs, %{kind: kind, error: reason, stacktrace: __STACKTRACE__})
        )
        
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end
  
  @doc """
  Wraps a tool invocation with telemetry events.
  """
  @spec span_tool_invoke(String.t(), map(), (-> result)) :: result when result: term()
  def span_tool_invoke(tool_name, attrs, func) when is_function(func, 0) do
    start_time = System.monotonic_time()
    meta = Map.put(attrs, :tool_name, tool_name)
    
    :telemetry.execute(
      [:jido, :ai, :tool, :invoke, :start],
      %{system_time: System.system_time()},
      meta
    )
    
    try do
      result = func.()
      
      :telemetry.execute(
        [:jido, :ai, :tool, :invoke, :stop],
        %{duration: System.monotonic_time() - start_time},
        enrich_tool_metadata(meta, result)
      )
      
      result
    catch
      kind, reason ->
        :telemetry.execute(
          [:jido, :ai, :tool, :invoke, :exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(meta, %{kind: kind, error: reason, stacktrace: __STACKTRACE__})
        )
        
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end
  
  # Private helpers
  defp build_llm_metadata(attrs) do
    attrs
    |> Map.take([:provider, :model, :temperature, :max_tokens, :stream,
                 :agent_id, :strategy, :react_run_id, :react_step_number])
    |> Map.put(:system_time, System.system_time())
  end
  
  defp extract_token_measurements(result) do
    case result do
      %{usage: %{prompt_tokens: pt, completion_tokens: ct}} ->
        %{prompt_tokens: pt, completion_tokens: ct, total_tokens: pt + ct}
      _ ->
        %{}
    end
  end
  
  defp enrich_with_completion(meta, _result), do: meta
  defp enrich_with_result(meta, _result), do: meta
  defp enrich_step_metadata(meta, _result), do: meta
  defp enrich_tool_metadata(meta, _result), do: meta
end
```

---

## 6. Trace Context Propagation

### 6.1 OpenTelemetry Integration

Use OpenTelemetry's process-based context propagation:

```elixir
# In mix.exs dependencies
{:opentelemetry, "~> 1.4"},
{:opentelemetry_exporter, "~> 1.7"},
{:opentelemetry_logger_metadata, "~> 0.1"}
```

**Span wrapping in telemetry helpers:**

```elixir
def span_llm_call(attrs, func) do
  # ... existing telemetry code ...
  
  OpenTelemetry.Tracer.with_span "llm.#{attrs[:model]}" do
    try do
      result = func.()
      # ... 
    catch
      # ...
    end
  end
end
```

Because OTel keeps span context in the **process dictionary**, nested `with_span` calls automatically form a span hierarchy:

```
agent_command
  └── strategy_tick
        └── react_run
              ├── react_step_1
              │     ├── llm_request
              │     └── tool_invoke
              ├── react_step_2
              │     ├── llm_request
              │     └── tool_invoke
              └── react_step_3
                    └── llm_request (final answer)
```

### 6.2 Logger Correlation

```elixir
# In config.exs
config :opentelemetry, :logger_handler,
  filter_default: :log,
  config: %{handlers: [:default]}
```

This automatically injects `trace_id`/`span_id` into Logger metadata.

### 6.3 External Trace Linking

For HTTP entrypoints that receive trace context:

```elixir
def set_parent_trace_from_headers(headers) do
  ctx = :otel_propagator_text_map.extract(headers)
  OpenTelemetry.Ctx.attach(ctx)
end
```

---

## 7. Sensitive Data Redaction

### 7.1 Sanitizer Behaviour

```elixir
defmodule Jido.AI.Sanitizer do
  @moduledoc """
  Sanitizes sensitive data in prompts, completions, and observations.
  """
  
  @callback redact_prompt(prompt :: binary(), meta :: map()) :: {binary(), map()}
  @callback redact_completion(completion :: binary(), meta :: map()) :: {binary(), map()}
  @callback redact_observation(observation :: binary(), meta :: map()) :: {binary(), map()}
  
  def redact_prompt(prompt, meta \\ %{}) do
    impl().redact_prompt(prompt, meta)
  end
  
  def redact_completion(completion, meta \\ %{}) do
    impl().redact_completion(completion, meta)
  end
  
  def redact_observation(observation, meta \\ %{}) do
    impl().redact_observation(observation, meta)
  end
  
  defp impl do
    Application.get_env(:jido, __MODULE__, Jido.AI.Sanitizer.Default)
  end
end
```

### 7.2 Default Implementation

```elixir
defmodule Jido.AI.Sanitizer.Default do
  @behaviour Jido.AI.Sanitizer
  
  @max_length 1000
  @secret_patterns [
    ~r/(?i)(api[_-]?key|secret|password|token)\s*[:=]\s*\S+/,
    ~r/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/,
    ~r/\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/
  ]
  
  @impl true
  def redact_prompt(prompt, meta) do
    {redact(prompt), Map.put(meta, :redacted, true)}
  end
  
  @impl true
  def redact_completion(completion, meta) do
    {redact(completion), Map.put(meta, :redacted, true)}
  end
  
  @impl true
  def redact_observation(observation, meta) do
    {redact(observation), Map.put(meta, :redacted, true)}
  end
  
  defp redact(text) when is_binary(text) do
    text
    |> mask_secrets()
    |> truncate(@max_length)
  end
  
  defp redact(other), do: inspect(other) |> truncate(@max_length)
  
  defp mask_secrets(text) do
    Enum.reduce(@secret_patterns, text, fn pattern, acc ->
      Regex.replace(pattern, acc, "[REDACTED]")
    end)
  end
  
  defp truncate(text, max) when byte_size(text) > max do
    String.slice(text, 0, max) <> "...[truncated]"
  end
  defp truncate(text, _max), do: text
end
```

### 7.3 Configuration

```elixir
config :jido, Jido.AI.Sanitizer,
  max_length: 1000,
  redact_in_prod: true,
  patterns: [...]
```

---

## 8. Leveraging `cond_log/4` for Debug Observability

### 8.1 Observability Log Threshold

```elixir
defmodule Jido.Observability.Log do
  @moduledoc """
  Centralized observability logging configuration.
  """
  
  def threshold do
    Application.get_env(:jido, :observability, [])
    |> Keyword.get(:log_level, :info)
  end
  
  @doc """
  Conditionally log based on observability threshold.
  """
  def log(level, message, opts \\ []) do
    Jido.Util.cond_log(threshold(), level, message, opts)
  end
end
```

### 8.2 Usage in ReAct Strategy

```elixir
defmodule Jido.AI.Strategy.ReAct do
  alias Jido.Observability.Log
  alias Jido.AI.Sanitizer
  
  defp process_instruction(agent, instruction) do
    state = StratState.get(agent, %{})
    machine = Machine.from_map(state)
    
    # Rich debug logging before state transition
    Log.log(:debug, "[ReAct] Processing instruction",
      agent_id: agent.id,
      iteration: machine.iteration,
      status: machine.status
    )
    
    {machine, directives} = Machine.update(machine, msg, env)
    
    # Log state transition
    Log.log(:debug, "[ReAct] State transition",
      agent_id: agent.id,
      old_status: state[:status],
      new_status: Machine.to_map(machine)[:status],
      directive_count: length(directives)
    )
    
    # ... rest of implementation
  end
end
```

### 8.3 Configuration

```elixir
# Development: verbose
config :jido, :observability,
  log_level: :debug

# Production: minimal
config :jido, :observability,
  log_level: :info
```

---

## 9. Sampling Strategies

### 9.1 Trace Sampling (OpenTelemetry)

```elixir
# Development: sample everything
config :opentelemetry,
  sampler: :always_on

# Production: sample 10%
config :opentelemetry,
  sampler: {:parent_based, %{root: {:traceid_ratio_based, 0.1}}}
```

### 9.2 Payload Sampling (Prompts/Completions)

```elixir
defmodule Jido.AI.Telemetry do
  defp maybe_attach_prompt(meta, prompt) do
    case Application.get_env(:jido, :observability, [])[:prompt_sampling] do
      :none -> meta
      {:ratio, r} when :rand.uniform() < r ->
        {redacted, new_meta} = Jido.AI.Sanitizer.redact_prompt(prompt, meta)
        Map.put(new_meta, :prompt, redacted)
      :debug_only when Jido.Observability.Log.threshold() == :debug ->
        {redacted, new_meta} = Jido.AI.Sanitizer.redact_prompt(prompt, meta)
        Map.put(new_meta, :prompt, redacted)
      _ -> meta
    end
  end
end
```

**Configuration:**

```elixir
config :jido, :observability,
  prompt_sampling: {:ratio, 0.01},  # 1% in prod
  max_prompt_length: 500,
  max_observation_length: 500
```

---

## 10. Exporter Integrations

### 10.1 OpenTelemetry (Primary)

```elixir
# config/runtime.exs
config :opentelemetry, :resource, service: %{name: "jido-agent"}

config :opentelemetry, :processors,
  otel_batch_processor: %{
    exporter: {:opentelemetry_exporter, %{
      endpoints: [System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")]
    }}
  }
```

### 10.2 Langfuse (AI-Specific)

```elixir
defmodule Jido.AI.Exporters.Langfuse do
  @moduledoc """
  Exports AI telemetry to Langfuse for LLM-specific observability.
  """
  
  def attach do
    :telemetry.attach_many(
      "jido-langfuse-exporter",
      [
        [:jido, :ai, :llm, :request, :stop],
        [:jido, :ai, :react, :run, :stop]
      ],
      &handle_event/4,
      %{api_key: config()[:api_key]}
    )
  end
  
  defp handle_event([:jido, :ai, :llm, :request, :stop], measurements, metadata, config) do
    # Transform to Langfuse trace format and send
  end
  
  defp handle_event([:jido, :ai, :react, :run, :stop], measurements, metadata, config) do
    # Transform to Langfuse generation format and send
  end
  
  defp config do
    Application.get_env(:jido, __MODULE__, [])
  end
end
```

**Configuration:**

```elixir
config :jido, Jido.AI.Exporters.Langfuse,
  api_key: System.get_env("LANGFUSE_API_KEY"),
  host: "https://cloud.langfuse.com"
```

---

## 11. Implementation Roadmap

### Phase 0: Baseline (< 1 hour)
- [x] Add this document to repository
- [ ] Decide naming: `Jido.AI.Telemetry` vs `Jido.AI.Observability`

### Phase 1: Core Telemetry & Logging (1-3 hours)
- [ ] Create `Jido.AI.Telemetry` module with helpers
- [ ] Instrument `DirectiveExec` for `ReqLLMStream` and `ToolExec`
- [ ] Instrument `Jido.AI.Strategy.ReAct.process_instruction/2` for state transitions
- [ ] Create `Jido.Observability.Log` threshold helper
- [ ] Add debug logging to Machine state transitions via Strategy

**Success Criteria:** Per-step ReAct logs and tool calls visible in logs

### Phase 2: OpenTelemetry Tracing (1-2 days)
- [ ] Add OTel dependencies
- [ ] Configure sampler & OTLP exporter
- [ ] Augment `span_agent_cmd/3`, `span_strategy/4` with OTel spans
- [ ] Connect AI spans to form trace hierarchy
- [ ] Enable Logger correlation with trace_id/span_id

**Success Criteria:** Full trace trees visible in tracing UI (Jaeger, etc.)

### Phase 3: Redaction & Exporters (1-2 days)
- [ ] Implement `Jido.AI.Sanitizer` behaviour + default
- [ ] Hook sanitizer into LLM telemetry and ReAct logs
- [ ] Implement prompt/completion sampling
- [ ] Create Langfuse exporter adapter
- [ ] Add tests for PII non-leakage

**Success Criteria:** Safe production deployment with AI-specific observability

---

## 12. Future Considerations

- **Multi-agent workflows**: Higher-level workflow telemetry with workflow IDs
- **Per-user analytics**: Token usage and cost accounting per user/tenant
- **Policy enforcement**: Per-tenant retention/PII rules at redaction layer
- **Multiple LLM providers**: Unified provider abstraction with embedded telemetry
- **Offline analysis**: Persist serialized trajectories for auditing
- **Live dashboards**: Phoenix LiveView subscribing to telemetry for real-time visualization
- **Anomaly detection**: Automatic alerts on latency/token usage anomalies

---

## References

- [Mastra Observability Overview](https://mastra.ai/docs/observability/overview)
- [Mastra AI Tracing](https://mastra.ai/docs/observability/ai-tracing/overview)
- [OpenTelemetry for Elixir](https://hex.pm/packages/opentelemetry)
- [Erlang Telemetry](https://hex.pm/packages/telemetry)
- [Langfuse Documentation](https://langfuse.com/docs)

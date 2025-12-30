# ReAct Agent Implementation - Critical Analysis

Deep analysis of the Jido + ReqLLM integration via the ReAct strategy implementation.

**Last Updated:** December 30, 2024  
**Status:** ✅ Working - Architecture aligned with dependency tree

---

## Executive Summary

The ReAct implementation proves Jido can support multi-step LLM agents. The refactoring reduced the example from 13 files to 1 file by:
- Creating a generic `Jido.AI.Strategy.ReAct` module
- Using atoms instead of Zoi action structs for internal routing
- Reusing `Jido.Tools.*` from jido_action
- Inlining state machine into the strategy

**Target Dependency Tree:**
```
req_llm (no deps)
    ↓
jido_ai (depends on req_llm)  ← Jido.AI.* namespace lives in projects/jido for now
    ↓
jido (depends on jido_ai)
    ↓
jido_action, jido_signal (depend on jido)
    ↓
ReAct Example (end-to-end integration test)
```

**Current architecture:**
```
Jido.AI (in projects/jido)    ReAct Example
├── strategy/react.ex         └── agent.ex (1 file!)
├── directive.ex
├── directive_exec.ex
├── signal.ex
├── llm_backend.ex
├── llm_context.ex
└── tool_spec.ex              ← NEW: schema-only tools
```

**Key architectural decisions:**
1. **Single tool execution path** - All tools execute via `Directive.ToolExec` → `Jido.Exec.run/3`
2. **Schema-only tools** - `Jido.AI.ToolSpec` creates ReqLLM tools with `callback: nil`
3. **Argument normalization** - DirectiveExec normalizes LLM args using action schemas
4. **Deprecated callback path** - `Jido.Action.Tool.to_reqllm_tool/2` deprecated

---

## Resolved Issues (P0 Complete)

### ✅ Dual Tool Execution Paths → UNIFIED

**Before:** Two completely different paths for executing a Jido action as a tool:
- Path 1: ReqLLM callback (unused by ReAct)
- Path 2: Directive.ToolExec (used by ReAct)

**After:** Single execution path through `Directive.ToolExec`:
```elixir
# DirectiveExec.ToolExec now handles all tool execution
normalized_args = normalize_arguments(action_module, arguments)
Jido.Exec.run(action_module, normalized_args, context)
```

**Changes made:**
- Created `Jido.AI.ToolSpec` for schema-only tool generation
- Updated ReAct strategy to use `ToolSpec.from_actions/1`
- Added argument normalization to DirectiveExec
- Deprecated `Jido.Action.Tool.to_reqllm_tool/2`

### ✅ Bug in execute_action/3 → FIXED

**Before:** Partial error match crashed on non-exception errors.
```elixir
{:error, %_{} = error} when is_exception(error) -> ...  # ← missed {:error, :foo}
```

**After:** Added catch-all error clause.
```elixir
{:error, reason} ->
  {:error, Jason.encode!(%{error: inspect(reason)})}
```

### ✅ Silent Async Failures → ALREADY FIXED

DirectiveExec implementations already have try/rescue/catch blocks that ensure signals are always emitted.

### ✅ Implicit Param Normalization → FIXED

**Before:** Strategies manually handled string vs atom keys.

```elixir
defp handle_start(agent, params, _ctx) do
  query = params[:query] || params["query"]  # ← manual fallback everywhere
  ...
end
```

**After:** Strategies define `action_spec/1` with Zoi schemas, params are auto-normalized.

```elixir
# In Strategy - define schemas for internal actions
@impl true
def action_spec(:react_start) do
  %{schema: Zoi.object(%{query: Zoi.string()})}
end

# Params arrive already normalized - direct pattern match
defp handle_start(agent, %{query: query}, _ctx) do
  ...
end
```

**Changes made:**
- Added `action_spec/1` callback to Strategy behaviour
- Added `Strategy.normalize_instruction/3` helper (Zoi coercion + string→atom keys)
- Agent's `cmd/2` auto-normalizes instruction params before passing to strategy
- ReAct defines schemas for all 3 internal actions
- ReAct handlers now pattern match on atom keys directly

---

## Remaining Issues by Priority

### P1: Brittle Chunk Parsing (HIGH)

**Problem:** Jido parses ReqLLM's internal chunk format.

```elixir
defp extract_tool_calls(chunks) do
  chunks
  |> Enum.filter(&(&1.type == :tool_call))          # ← knows internal type
  |> Enum.map(fn chunk ->
    %{
      id: Map.get(chunk.metadata || %{}, :id),      # ← knows metadata shape
      ...
    }
  end)
end
```

**Impact:**
- Any ReqLLM streaming format change breaks Jido
- ~40 lines of fragile parsing logic in LLMBackend

**Recommended Fix (ReqLLM):**
```elixir
# ReqLLM should provide
ReqLLM.stream_text_and_classify(model, msgs, opts)
# Returns: {:ok, %{type: :tool_calls | :final_answer, text: String.t(), tool_calls: [...]}}
```

### ✅ Strategy State Leakage → FIXED

**Before:** Agents directly inspected strategy internals.

```elixir
# In agent.ex - reaching into strategy's private state
def on_after_cmd(agent, _action, directives) do
  strat = agent.state.__strategy__ || %{}
  status = strat[:status]           # ← knows internal field names
  ...
end
```

**After:** Added `Strategy.Public` struct and `snapshot/2` callback.

```elixir
# Strategy.Public struct provides stable interface
%Strategy.Public{status: :success, done?: true, result: "...", meta: %{}}

# Agents use strategy_snapshot/1 helper
def on_after_cmd(agent, _action, directives) do
  snap = strategy_snapshot(agent)
  if snap.done?, do: snap.result  # ← stable interface
end
```

**Changes made:**
- Added `Jido.Agent.Strategy.Public` struct
- Added `snapshot/2` callback to Strategy behaviour (with default impl)
- ReAct implements custom `snapshot/2` mapping internal state to public
- Added `strategy_snapshot/1` helper to Agent macro
- Updated ReAct example to use `strategy_snapshot(agent)` instead of `__strategy__`

### P2: Fake Streaming (MEDIUM)

**Problem:** `LLMStream` directive suggests streaming but actually batches.

```elixir
# In LLMBackend.stream/3
chunks = Enum.to_list(stream_response.stream)  # ← collects ALL chunks
{:ok, classify_chunks(chunks)}                  # ← returns once
```

**Recommended Fix:** Either:
- Rename to `LLMCall`/`LLMRequest` (honest naming)
- Actually stream by emitting partial signals

### P2: Inconsistent Error Encoding (MEDIUM)

**Problem:** Different JSON encoding conventions.

```elixir
# In LLMContext.tool_result_message/1
{:error, reason} -> "Error: #{inspect(reason)}"  # ← NOT JSON!

# In Jido.Action.Tool.execute_action/3
{:error, reason} -> {:error, Jason.encode!(%{error: inspect(reason)})}  # ← IS JSON
```

**Recommended Fix:** Single "tool result wire format":
```json
{"ok": true, "result": ...}
{"ok": false, "error": {"message": "...", "type": "..."}}
```

### ✅ Signal Routing Boilerplate → FIXED

**Before:** Every agent must manually route signals to strategy actions.

```elixir
def handle_signal(agent, %Signal{type: "react.user_query"} = s), do: cmd(agent, {ReActStrategy.start_action(), s.data})
def handle_signal(agent, %Signal{type: "ai.llm_result"} = s), do: cmd(agent, {ReActStrategy.llm_result_action(), s.data})
```

**After:** Strategies declare signal routes, Agent auto-routes.

```elixir
# In Strategy - declare routes once
@impl true
def signal_routes(_ctx) do
  [
    {"react.user_query", {:strategy_cmd, :react_start}},
    {"ai.llm_result", {:strategy_cmd, :react_llm_result}},
    {"ai.tool_result", {:strategy_cmd, :react_tool_result}}
  ]
end

# In Agent - no manual routing needed (default handle_signal auto-routes)
# Only override if you need custom pre-processing:
def handle_signal(agent, %Jido.Signal{type: "react.user_query"} = signal) do
  agent = %{agent | state: Map.put(agent.state, :last_query, signal.data.query)}
  super(agent, signal)  # ← auto-routing via super
end
```

**Changes made:**
- Added `signal_routes/1` callback to Strategy behaviour
- ReAct declares its 3 signal routes
- Agent's default `handle_signal/2` auto-routes using strategy's routes
- ReAct example agent reduced from 4 handle_signal clauses to 1 (custom pre-processing only)

### P2: Weak Typing at LLM Boundary (LOW)

**Problem:** Zoi schemas use `any()` everywhere.

```elixir
context: Zoi.any(description: "List of messages or ReqLLM.Context"),
tools: Zoi.list(Zoi.any(), description: "List of ReqLLM.Tool definitions")
```

**Recommended Fix:** Tighten schemas when ReqLLM provides typed structs.

---

## Priority Matrix (Updated)

| Issue | Package | Effort | Impact | Priority | Status |
|-------|---------|--------|--------|----------|--------|
| ~~Dual tool execution paths~~ | jido_action | L | Critical | ~~P0~~ | ✅ Fixed |
| ~~Silent async failures~~ | jido.ai | S | High | ~~P0~~ | ✅ Fixed |
| ~~Bug in execute_action/3~~ | jido_action | S | High | ~~P0~~ | ✅ Fixed |
| ~~Strategy state leakage~~ | jido | M | Medium | ~~P1~~ | ✅ Fixed |
| ~~Signal routing boilerplate~~ | jido | M | Medium | ~~P2~~ | ✅ Fixed |
| ~~Implicit param normalization~~ | jido | M | Medium | ~~P1~~ | ✅ Fixed |
| No classified stream result | req_llm | M | High | **P1** | Pending |
| Brittle chunk parsing | jido.ai | M | High | **P1** | Pending |
| Fake streaming naming | jido.ai | S | Medium | P2 | Pending |
| Inconsistent error encoding | jido.ai | S | Medium | P2 | Pending |
| Weak typing at LLM boundary | jido.ai | M | Medium | P2 | Pending |

---

## Current File Structure

**Jido.AI (7 files, reusable, in projects/jido):**
```
lib/jido/ai/
├── strategy/
│   └── react.ex          # Generic ReAct strategy (~270 lines)
├── directive.ex          # LLMStream, ToolExec directives
├── directive_exec.ex     # Protocol implementations with error handling
├── signal.ex             # llm_result/1, tool_result/1
├── llm_backend.ex        # Streaming + chunk classification
├── llm_context.ex        # Message/ToolCall construction
└── tool_spec.ex          # NEW: Schema-only tool generation
```

**ReAct Example (1 file, ~85 lines):**
```
lib/jido/examples/react/
└── agent.ex              # Minimal - signal routing auto-handled by strategy
```

**Strategy Behaviour (enhanced):**
```
lib/jido/agent/
├── strategy.ex           # Core behaviour with new callbacks:
│                         #   - snapshot/2 → public state view
│                         #   - action_spec/1 → param schemas
│                         #   - signal_routes/1 → declarative routing
└── strategy/
    └── state.ex          # Internal state helpers (for strategies only)
```

---

## Architecture Decision: Tool Execution Model

**Decision:** Jido owns tool execution, ReqLLM provides schemas.

```
┌─────────────────────────────────────────────────────────────┐
│ ReqLLM                                                      │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ stream_text(model, msgs, tools)                         │ │
│ │ tools = schema only (callback: nil)                     │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Jido.AI (in projects/jido)                                  │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ ToolSpec.from_actions([...]) → schema-only ReqLLM tools │ │
│ └─────────────────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ LLMBackend.stream/3 → calls ReqLLM, classifies chunks   │ │
│ └─────────────────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ Strategy.ReAct → reasoning loop, emits ToolExec         │ │
│ └─────────────────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ DirectiveExec[ToolExec] → normalize args, Jido.Exec.run │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

**This eliminates:**
- Dual execution paths ✅
- Callback generation in `Jido.Action.Tool` ✅ (deprecated)
- Confusion about who owns tool execution ✅

**Remaining to push to ReqLLM:**
- Chunk classification logic (stream_text_and_classify)
- Typed chunk structures

---

## Recommended Next Steps

### Short Term (P1 - ReqLLM work)

1. **Add ReqLLM.stream_text_and_classify/3** - Returns classified result
2. **Delete chunk parsing from LLMBackend** - Use ReqLLM's classifier

### Medium Term (P2)

3. **Rename LLMStream to LLMCall** - Honest naming
4. **Standardize tool result format** - Single JSON schema for success/error

---

## Conclusion

The tracer bullet succeeded and the architecture is now aligned with the dependency tree:

- **ReqLLM** is the single source of truth for LLM semantics
- **Jido.AI** (in jido) handles strategy, directives, and tool spec generation
- **Jido.Action** provides core action execution and schema utilities
- **jido_action** no longer couples to ReqLLM (deprecated functions only)

The single tool execution path through `Directive.ToolExec` with argument normalization provides consistent semantics. Schema-only tools from `Jido.AI.ToolSpec` cleanly separate "what the LLM sees" from "how Jido executes".

**Strategy behaviour now provides:**
- `snapshot/2` - Stable public state view (no more `__strategy__` leakage)
- `action_spec/1` - Schema-based param normalization (no more `params[:foo] || params["foo"]`)
- `signal_routes/1` - Declarative signal routing (no more boilerplate `handle_signal` clauses)

**Core remaining friction:** Chunk parsing in LLMBackend that should move to ReqLLM.

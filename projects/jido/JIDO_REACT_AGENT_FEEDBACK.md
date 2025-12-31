# ReAct Agent Plan - Critical Evaluation

**Document**: JIDO_REACT_AGENT_PLAN.md  
**Evaluation Date**: 2024-12-30  
**Overall Assessment**: Solid foundation with gaps to address before implementation

---

## Executive Summary

The plan correctly implements Jido's core architecture: strategies remain pure, directives are effect descriptions, and AgentServer owns all IO. However, there are inconsistencies in state management, incomplete error handling, testability gaps, and missing concurrency safeguards that need attention.

**Verdict**: Fix the issues below before implementation to avoid rework.

---

## Strengths ✅

### 1. Clear Separation of Concerns

- Agent + Strategy are pure functions; no IO leakage
- ReqLLM and tools only appear in DirectiveExec and Tools module
- Signals are the central coordination mechanism
- This is exactly the Elm/Redux pattern Jido is built on

### 2. Directive Design

- Custom directive structs (`LLMCall`, `ToolCall`) are plain data
- Side effects implemented via `DirectiveExec` protocol
- Use of `Task.Supervisor` and `AgentServer.cast/2` inside DirectiveExec is correct
- Aligns with `Jido.Agent.Directive`'s extensibility model

### 3. Strategy as State Machine

- Explicit `status` + `iteration` + `max_iterations` in `__strategy__`
- Clear separation: conversation history, pending tool calls, final answer
- Signal → `handle_signal/2` → `cmd/2` → Strategy is clean message-driven flow

### 4. Tools Design

- Pure callbacks (Abacus, stubbed weather)
- Keeps IO out of the agent layer

---

## Weaknesses & Required Fixes 🔴

### Issue A: Inconsistent State Keys (CRITICAL)

**Problem**: Strategy state uses `final_answer` but runner script reads `last_answer`:

```elixir
# Strategy defines:
agent.state.__strategy__.final_answer

# Runner reads:
state.agent.state.last_answer  # This key doesn't exist!
```

**Fix**: Use `on_after_cmd/3` to derive top-level state from `__strategy__`:

```elixir
@impl true
def on_after_cmd(agent, _action, directives) do
  strategy = agent.state.__strategy__ || %{}
  
  agent = case strategy do
    %{final_answer: answer} when is_binary(answer) ->
      %{agent | state: Map.put(agent.state, :last_answer, answer)}
    _ ->
      agent
  end

  {:ok, agent, directives}
end
```

---

### Issue B: Not Using Jido.Agent.Strategy.State Helpers

**Problem**: Plan mentions `strategy_state.ex` but doesn't wrap `Jido.Agent.Strategy.State`.

**Fix**: Build on core helpers rather than rolling custom map manipulation:

```elixir
alias Jido.Agent.Strategy.State, as: StrategyState

def get(agent), do: StrategyState.get(agent, default: @default_state)
def put(agent, state), do: StrategyState.put(agent, state)
```

---

### Issue C: Missing Strategy Configuration in Agent

**Problem**: Agent module doesn't explicitly configure the ReAct strategy.

**Fix**: Ensure the agent uses the custom strategy:

```elixir
defmodule Jido.Examples.ReAct.Agent do
  use Jido.Agent,
    name: "react_agent",
    strategy: {Jido.Examples.ReAct.Strategy, max_iterations: 8},  # REQUIRED
    schema: [...]
end
```

Without this, it falls back to `Direct` strategy and the state machine won't run.

---

### Issue D: Ignoring Directive Fields in DirectiveExec

**Problem**: `LLMCall` defines `tool_choice`, `max_tokens`, `temperature` but executor ignores them:

```elixir
# Directive has these fields:
defstruct [:id, :model, :context, tools: [], tool_choice: :auto, max_tokens: 1024, temperature: 0.2]

# Executor hard-codes:
opts = [tools: tools, tool_choice: :auto]  # Ignores other fields!
```

**Fix**: Pass through all directive fields:

```elixir
def exec(%{id: id, model: model, context: ctx, tools: tools, 
           tool_choice: tc, max_tokens: max_tok, temperature: temp} = _d, _signal, state) do
  opts = [
    tools: tools,
    tool_choice: tc,
    max_tokens: max_tok,
    temperature: temp
  ]
  result = ReqLLM.generate_text(model, ctx, opts)
  ...
end
```

---

### Issue E: Task.Supervisor Failure Not Handled

**Problem**: `Task.Supervisor.start_child/2` can fail but return value is ignored.

**Fix**: Handle supervisor failures:

```elixir
case Task.Supervisor.start_child(Jido.TaskSupervisor, fn -> ... end) do
  {:ok, _pid} ->
    {:async, nil, state}
    
  {:error, reason} ->
    Logger.error("Failed to start LLM task: #{inspect(reason)}")
    # Either return error directive or signal failure
    {:ok, state}  # or emit Directive.Error
end
```

---

### Issue F: `react.final_answer` Signal Not Actually Used

**Problem**: The plan defines a `react.final_answer` signal but the runner script polls state instead.

**Fix**: Actually emit and demonstrate the signal:

```elixir
# In Strategy, when completing:
defp complete(agent, query, answer, iterations) do
  final_signal = Signals.final_answer(%{
    query: query,
    answer: answer,
    iterations: iterations
  })

  directives = [
    Directive.emit(final_signal),
    Directive.stop(:normal)
  ]

  {agent, directives}
end
```

The runner script should demonstrate receiving this signal, not just polling.

---

### Issue G: No Terminal State Guards

**Problem**: What happens if `react.llm_result` arrives after `status: :completed`?

**Fix**: Guard all actions against terminal states:

```elixir
def cmd(agent, instructions, ctx) do
  state = StrategyState.get(agent)
  
  # Guard: ignore events in terminal states
  case state.status do
    :completed -> {agent, []}
    :error -> {agent, []}
    _ -> handle_instruction(agent, state, instructions, ctx)
  end
end
```

---

### Issue H: Concurrent Tool Calls Race Condition

**Problem**: `pending_tool_calls` is a list, but behavior when tools complete out-of-order is undefined.

**Fix**: Use a map keyed by `call_id` and track completion:

```elixir
pending_tool_calls: %{
  "call-123" => %{name: "calculator", arguments: %{...}, result: nil},
  "call-456" => %{name: "weather", arguments: %{...}, result: nil}
}
```

When tool result arrives:
1. Check if `call_id` exists (drop stale results)
2. Store result
3. When ALL pending have results → transition to `:awaiting_llm`

---

### Issue I: Hardcoded ReqLLM Makes Testing Difficult

**Problem**: DirectiveExec directly calls `ReqLLM.generate_text/3`, making mocking hard.

**Fix**: Introduce a behaviour for testability:

```elixir
defmodule Jido.Examples.ReAct.LLMClient do
  @callback generate_text(model :: String.t(), ctx :: term(), opts :: keyword()) ::
              {:ok, term()} | {:error, term()}
  @callback execute_tool(tool :: term(), args :: map()) ::
              {:ok, term()} | {:error, term()}
end

defmodule Jido.Examples.ReAct.LLMClient.ReqLLM do
  @behaviour Jido.Examples.ReAct.LLMClient
  def generate_text(model, ctx, opts), do: ReqLLM.generate_text(model, ctx, opts)
  def execute_tool(tool, args), do: ReqLLM.Tool.execute(tool, args)
end
```

In DirectiveExec:
```elixir
@client Application.compile_env(:jido, :react_llm_client, Jido.Examples.ReAct.LLMClient.ReqLLM)
result = @client.generate_text(model, ctx, opts)
```

Tests can then inject a mock client.

---

## Missing Considerations 🟡

### 1. Error Model Not Specified

Need explicit handling for:
- **LLM errors**: timeout, 4xx/5xx, parse failure
- **Tool errors**: callback exceptions, invalid results
- **Infrastructure errors**: Task.Supervisor failures

Recommendation: All map to `result: {:error, term()}` in signals, Strategy sets `status: :error`.

### 2. `eventually/1` Test Helper Not Defined

The testing section references `eventually/1` but doesn't provide it:

```elixir
def eventually(fun, attempts \\ 50, interval \\ 100) do
  try do
    fun.()
  rescue
    error in [ExUnit.AssertionError] ->
      if attempts > 0 do
        Process.sleep(interval)
        eventually(fun, attempts - 1, interval)
      else
        reraise error, __STACKTRACE__
      end
  end
end
```

### 3. Max Iterations Termination Reason

When hitting `max_iterations`, the agent should indicate WHY it stopped:

```elixir
%{
  status: :completed,
  termination_reason: :max_iterations | :final_answer | :error,
  final_answer: "..." | nil
}
```

### 4. Single Outstanding LLM Call Invariant

Not explicitly stated but implied: should there be only one LLM call in flight at a time? If yes, enforce it. If no, handle concurrent LLM responses.

---

## Elm/Redux Pattern Adherence 📐

| Principle | Status | Notes |
|-----------|--------|-------|
| Agent is pure data | ✅ | No IO in Agent module |
| Strategy is pure function | ✅ | `cmd/3` returns `{agent, directives}` |
| Directives are effect descriptions | ✅ | Structs only, no execution |
| AgentServer owns side effects | ✅ | DirectiveExec does all IO |
| Message-driven updates | ✅ | Signals → handle_signal → cmd |
| Immutable state | ⚠️ | State consistency issue (A) |
| Single source of truth | ⚠️ | `__strategy__` vs top-level keys (A) |

**Overall**: 85% adherent. Fix Issue A for full compliance.

---

## Revised Implementation Checklist

### Phase 1: Directives (add error handling)
- [ ] Create `LLMCall` struct with all fields documented
- [ ] Create `ToolCall` struct
- [ ] Implement `DirectiveExec` for `LLMCall` **with Task.Supervisor error handling**
- [ ] Implement `DirectiveExec` for `ToolCall` **with error handling**
- [ ] Create `LLMClient` behaviour for testability

### Phase 2: Strategy (add guards)
- [ ] Create `StrategyState` helper **using Jido.Agent.Strategy.State**
- [ ] Create `Strategy` with state machine
- [ ] **Add terminal state guards (completed/error)**
- [ ] Implement LLM response parsing
- [ ] **Handle concurrent tool calls via map-based tracking**
- [ ] **Add termination_reason field**

### Phase 3: Agent & Tools
- [ ] Create `Agent` module **with explicit strategy config**
- [ ] **Add on_after_cmd/3 to sync __strategy__ → top-level state**
- [ ] Create `Tools` module
- [ ] Create `Signals` module

### Phase 4: Integration
- [ ] Create runner script
- [ ] **Demonstrate signal-based completion (not just polling)**
- [ ] **Add eventually/1 helper**
- [ ] Test with mock client
- [ ] Test with real Claude Haiku

---

## Recommendation

**Do not start implementation until these issues are addressed in the plan.** The plan is 80% there, but the remaining 20% involves correctness issues that will cause debugging pain if discovered during implementation.

Priority order:
1. Fix state consistency (Issue A) - blocks everything
2. Add terminal state guards (Issue G) - prevents race conditions
3. Add testability layer (Issue I) - enables safe iteration
4. Handle concurrent tools properly (Issue H) - correctness
5. Emit final_answer signal (Issue F) - demonstrates architecture

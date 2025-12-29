# Jido Core Functional Pattern

**Decision**: Use **Elm/Redux-style update** as the foundational pattern.

```elixir
update(agent, msg) :: {agent, [directive]}
```

---

## The Pattern

### Core Contract

```elixir
@type msg       :: term()           # instruction, command, event, signal
@type directive :: term()           # effect description (interpreted by runtime)
@type t         :: %Agent{}         # immutable agent struct

@spec update(t(), msg()) :: {t(), [directive()]}
```

### Key Invariants

1. **Agent is always complete** — The returned `agent` fully reflects all state changes. No "apply directives" step required.

2. **Directives are external only** — Directives describe effects for the *outside world* (send message, call LLM, spawn process). They never modify agent state.

3. **Pure function** — `update/2` has no side effects. Given same inputs, always same outputs.

---

## Why This Pattern

### Comparison Matrix

| Pattern | Directive Leak | OTP Fit | Brain Agnostic | API Simplicity | Testability |
|---------|---------------|---------|----------------|----------------|-------------|
| **Elm/Redux** | ✅ Solved | ✅ Native | ✅ Yes | ✅ Simple | ✅ Trivial |
| Event Sourcing | ✅ Solved | ⚠️ Heavy | ✅ Yes | ⚠️ Complex | ✅ Good |
| Free Monad | ✅ Solved | ❌ Alien | ✅ Yes | ❌ Complex | ✅ Good |
| Current Jido | ❌ Leaks | ✅ Native | ✅ Yes | ⚠️ Many hooks | ⚠️ Harder |

### The Directive Leak Problem (Current State)

```elixir
# Current: cmd/3 returns agent + directives, but agent isn't fully updated
{:ok, agent, directives} = MyAgent.cmd(agent, SomeAction)
# ❌ Caller must "apply directives" to get correct state
# ❌ Two sources of truth: agent + unapplied directives
```

### The Solution

```elixir
# New: update/2 returns fully-updated agent
{agent, directives} = MyAgent.update(agent, msg)
# ✅ agent IS the complete next state
# ✅ directives are ONLY for external effects (send, spawn, call_llm)
```

---

## Architecture

### Layer Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    IMPERATIVE SHELL                         │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              GenServer / Runtime                     │   │
│  │  • Receives messages                                 │   │
│  │  • Calls update/2                                    │   │
│  │  • Interprets directives (side effects)             │   │
│  │  • Sends replies                                     │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    FUNCTIONAL CORE                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Agent.update/2                          │   │
│  │  • Pure function                                     │   │
│  │  • (agent, msg) -> {agent, directives}              │   │
│  │  • All state changes happen here                     │   │
│  │  • No side effects                                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                            │                                │
│              ┌─────────────┴─────────────┐                 │
│              ▼                           ▼                 │
│  ┌───────────────────┐       ┌───────────────────┐        │
│  │   Brain Adapters   │       │   Action Runner   │        │
│  │  • Behavior Tree   │       │  • Execute action │        │
│  │  • FSM             │       │  • Return result  │        │
│  │  • LLM/ReAct       │       │                   │        │
│  │  • Rules Engine    │       │                   │        │
│  └───────────────────┘       └───────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

### Directive Algebra

Define a small, explicit set of directives:

```elixir
@type directive ::
  # Process communication
  | {:send, pid(), term()}
  | {:cast, GenServer.server(), term()}
  | {:call, GenServer.server(), term(), timeout()}
  
  # Spawning
  | {:spawn, Supervisor.child_spec()}
  | {:spawn_task, (-> term())}
  
  # Scheduling
  | {:schedule, ms :: non_neg_integer(), msg()}
  | {:cancel_timer, reference()}
  
  # LLM / AI
  | {:call_llm, prompt :: term(), tag :: term()}
  | {:call_tool, tool :: module(), args :: map(), tag :: term()}
  
  # Events / Observability
  | {:emit, event :: term()}
  | {:log, level :: atom(), message :: term()}
  
  # Control flow
  | {:stop, reason :: term()}
  | {:hibernate}
```

**Rule**: If it changes agent state → goes in `update/2` return value.  
**Rule**: If it affects the outside world → goes in directives.

---

## Strategy Integration

Strategies are **message producers**. They don't touch agent state directly.
Think of them like Plug — they implement `init/1` and `tick/3`.

### Strategy Behaviour

```elixir
defmodule Jido.Agent2.Strategy do
  @type strategy_state :: term()
  @type tick_result :: {strategy_state(), [msg()]}
  
  @callback init(opts :: keyword()) :: {:ok, strategy_state()}
  @callback tick(agent :: Agent.t(), strategy_state(), context :: map()) :: tick_result()
  @callback handle_signal(strategy_state(), signal :: term()) :: {strategy_state(), [msg()]}
  
  @optional_callbacks [handle_signal: 2]
end
```

### Behavior Tree Strategy

```elixir
defmodule MyBehaviorTreeStrategy do
  @behaviour Jido.Agent2.Strategy
  
  def init(opts) do
    {:ok, %{tree: build_tree(opts), status: :ready}}
  end
  
  def tick(agent, strategy_state, _context) do
    {new_tree, actions} = BehaviorTree.tick(strategy_state.tree, agent.state)
    
    # Convert BT actions to agent messages
    msgs = Enum.map(actions, fn
      {:run_action, module, params} -> {:instruction, module, params}
      {:set_state, key, value} -> {:state_update, %{key => value}}
    end)
    
    {%{strategy_state | tree: new_tree}, msgs}
  end
end
```

### LLM/ReAct Strategy

```elixir
defmodule MyReActStrategy do
  @behaviour Jido.Agent2.Strategy
  
  def init(_opts) do
    {:ok, %{phase: :think, history: []}}
  end
  
  def tick(_agent, %{phase: :think} = state, _context) do
    # Request LLM call; response comes back via handle_signal
    msgs = [{:request_llm, build_prompt(state.history)}]
    {state, msgs}
  end
  
  def tick(_agent, %{phase: :act, pending_action: action} = state, _context) do
    msgs = [{:instruction, action.module, action.params}]
    {%{state | phase: :observe}, msgs}
  end
  
  def tick(_agent, %{phase: :observe} = state, _context) do
    {state, []}  # Wait for tool result signal
  end
  
  def handle_signal(state, {:llm_response, response}) do
    case parse_response(response) do
      {:tool_call, tool, args} ->
        {%{state | phase: :act, pending_action: %{module: tool, params: args}}, []}
      {:final_answer, answer} ->
        {%{state | phase: :done}, [{:state_update, %{answer: answer}}]}
    end
  end
  
  def handle_signal(state, {:tool_result, result}) do
    {%{state | phase: :think, history: state.history ++ [result]}, []}
  end
end
```

### Integration with AgentServer

```elixir
defmodule MyAgentServer do
  use GenServer
  alias Jido.Agent2.Strategy
  
  def init(opts) do
    agent = MyAgent.new(opts)
    {:ok, strategy_state} = MyStrategy.init(opts[:strategy_opts] || [])
    {:ok, %{agent: agent, strategy: MyStrategy, strategy_state: strategy_state}}
  end
  
  def handle_info(:tick, state) do
    {agent, strategy_state, directives} = Strategy.run_tick(
      state.agent, state.strategy, state.strategy_state, %{}
    )
    interpret_directives(directives)
    {:noreply, %{state | agent: agent, strategy_state: strategy_state}}
  end
  
  def handle_info({:llm_response, response}, state) do
    {strategy_state, msgs} = state.strategy.handle_signal(
      state.strategy_state, {:llm_response, response}
    )
    {agent, directives} = process_messages(state.agent, msgs)
    interpret_directives(directives)
    {:noreply, %{state | agent: agent, strategy_state: strategy_state}}
  end
end
```

---

## Implementation Guide

### Refactored Agent2

```elixir
defmodule Jido.Agent2 do
  @type t :: %__MODULE__{...}
  @type msg :: instruction() | {:state_update, map()} | term()
  @type directive :: term()
  
  @doc """
  Pure update function. The heart of the agent.
  
  Returns fully-updated agent and external directives.
  """
  @spec update(t(), msg()) :: {t(), [directive()]}
  def update(%__MODULE__{} = agent, msg) do
    case msg do
      {:instruction, module, params} ->
        run_instruction(agent, module, params)
      
      {:state_update, attrs} ->
        {%{agent | state: Map.merge(agent.state, attrs)}, []}
      
      {:batch, msgs} ->
        Enum.reduce(msgs, {agent, []}, fn m, {a, ds} ->
          {a2, ds2} = update(a, m)
          {a2, ds ++ ds2}
        end)
      
      other ->
        handle_custom_msg(agent, other)
    end
  end
  
  defp run_instruction(agent, module, params) do
    case module.run(params, agent.state) do
      {:ok, result} ->
        agent = %{agent | state: Map.merge(agent.state, result), result: result}
        {agent, []}
      
      {:ok, result, directives} ->
        agent = %{agent | state: Map.merge(agent.state, result), result: result}
        # Separate internal from external
        {internal, external} = split_directives(directives)
        agent = apply_internal(agent, internal)
        {agent, external}
      
      {:error, reason} ->
        {%{agent | result: {:error, reason}}, [{:emit, {:error, reason}}]}
    end
  end
  
  defp split_directives(directives) do
    Enum.split_with(directives, fn
      {:set_state, _} -> true
      {:set_result, _} -> true
      _ -> false
    end)
  end
  
  defp apply_internal(agent, directives) do
    Enum.reduce(directives, agent, fn
      {:set_state, attrs}, a -> %{a | state: Map.merge(a.state, attrs)}
      {:set_result, r}, a -> %{a | result: r}
    end)
  end
  
  @doc """
  Convenience wrapper for multiple instructions.
  """
  @spec cmd(t(), instructions(), keyword()) :: {:ok, t(), [directive()]} | {:error, term()}
  def cmd(agent, instructions, opts \\ []) do
    context = Keyword.get(opts, :context, %{})
    
    with {:ok, normalized} <- Instruction.normalize(instructions, context) do
      {agent, directives} = 
        Enum.reduce(normalized, {agent, []}, fn instr, {a, ds} ->
          {a2, ds2} = update(a, {:instruction, instr.action, instr.params})
          {a2, ds ++ ds2}
        end)
      
      {:ok, agent, directives}
    end
  end
end
```

### GenServer Integration

```elixir
defmodule Jido.AgentServer do
  use GenServer
  
  def handle_call({:cmd, instructions, opts}, _from, agent) do
    case Agent.cmd(agent, instructions, opts) do
      {:ok, agent, directives} ->
        agent = interpret_directives(agent, directives)
        {:reply, {:ok, agent}, agent}
      
      {:error, reason} ->
        {:reply, {:error, reason}, agent}
    end
  end
  
  def handle_info({:llm_response, tag, response}, agent) do
    {agent, directives} = Agent.update(agent, {:llm_response, tag, response})
    agent = interpret_directives(agent, directives)
    {:noreply, agent}
  end
  
  defp interpret_directives(agent, directives) do
    Enum.reduce(directives, agent, fn
      {:send, pid, msg}, a ->
        send(pid, msg)
        a
      
      {:call_llm, prompt, tag}, a ->
        Task.start(fn ->
          response = LLMClient.complete(prompt)
          send(self(), {:llm_response, tag, response})
        end)
        a
      
      {:schedule, ms, msg}, a ->
        Process.send_after(self(), msg, ms)
        a
      
      {:emit, event}, a ->
        Phoenix.PubSub.broadcast(Jido.PubSub, "agent:#{a.id}", event)
        a
      
      _, a -> a
    end)
  end
end
```

---

## Testing

The pattern makes testing trivial:

```elixir
defmodule MyAgentTest do
  use ExUnit.Case
  
  test "update returns correct state and directives" do
    agent = MyAgent.new()
    
    {agent2, directives} = MyAgent.update(agent, {:instruction, SomeAction, %{value: 42}})
    
    # State assertions
    assert agent2.state.value == 42
    assert agent2.result == %{value: 42}
    
    # Directive assertions (no interpretation needed)
    assert {:emit, {:action_completed, _}} in directives
  end
  
  test "brain produces expected messages" do
    agent = MyAgent.new(state: %{health: 100, threat_nearby: true})
    brain_state = MyBrain.init([])
    
    {_brain_state, msgs} = MyBrain.tick(agent, brain_state, %{})
    
    assert {:instruction, AttackAction, _} in msgs
  end
  
  # Property-based testing
  property "update is deterministic" do
    check all agent <- agent_generator(),
              msg <- msg_generator() do
      {a1, d1} = MyAgent.update(agent, msg)
      {a2, d2} = MyAgent.update(agent, msg)
      
      assert a1 == a2
      assert d1 == d2
    end
  end
end
```

---

## Migration Path

### Phase 1: Fix Directive Leak (1-2 days)
- Refactor `Runner.run/3` to separate internal events from external directives
- Add `evolve/2` or inline equivalent in `cmd/3`
- Remove `apply_directives?` option
- Ensure `cmd/3` always returns fully-updated agent

### Phase 2: Expose update/2 (1 day)
- Add `update/2` as the canonical primitive
- Make `cmd/3` a convenience wrapper
- Update docs and examples

### Phase 3: Brain Behaviour (2-3 days)
- Define `Jido.Brain` behaviour
- Implement reference brains (simple FSM, basic BT)
- Integration with AgentServer tick loop

### Phase 4: Deprecate Old Patterns (ongoing)
- Mark `register_action/deregister_action` as deprecated
- Simplify lifecycle hooks
- Consolidate `agent.ex` and `agent2.ex`

---

## Observability

### The Challenge

Agents have two execution modes with different observability needs:

| Mode | Example | Replay | Recording Need |
|------|---------|--------|----------------|
| **Deterministic** | Behavior tree, FSM | Trivial (same inputs → same outputs) | Minimal (just messages) |
| **Non-deterministic** | LLM calls, external APIs | Requires captured responses | Full (request + response) |

### Design Principle

**Keep `update/2` pure and oblivious to observability.**

All tracing/recording happens at **runtime boundaries**:
1. Around calls to `update/2`
2. When interpreting non-deterministic directives

```
┌─────────────────────────────────────────────────────────────┐
│                    RUNTIME BOUNDARY                         │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           Observability.around_update/3              │   │
│  │  • Records: msg, directives, timing                  │   │
│  └─────────────────────────────────────────────────────┘   │
│                            │                                │
│                            ▼                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Agent.update/2 (PURE)                   │   │
│  │  • No observability imports                          │   │
│  │  • No tracing calls                                  │   │
│  └─────────────────────────────────────────────────────┘   │
│                            │                                │
│                            ▼                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           Observability.around_effect/3              │   │
│  │  • Records: request payload, response, timing        │   │
│  │  • Only for non-deterministic directives             │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Event Model

```elixir
defmodule Jido.Trace.Event do
  @type kind :: :msg_in | :effect_request | :effect_result
  
  @type t :: %__MODULE__{
    seq: non_neg_integer(),         # Ordering within agent
    ts: integer(),                  # Timestamp
    agent_id: term(),
    kind: kind(),
    trace_id: term() | nil,         # For distributed tracing
    span_id: term() | nil,
    msg: term() | nil,              # For :msg_in
    directives: [term()] | nil,     # For :msg_in
    effect: term() | nil,           # For :effect_*
    result: term() | nil,           # For :effect_result
    meta: map()                     # Duration, tags, etc.
  }
end
```

### Recorder Behaviour

```elixir
defmodule Jido.Trace.Recorder do
  @callback record(Jido.Trace.Event.t()) :: :ok
  @callback log(agent_id :: term()) :: [Jido.Trace.Event.t()]
end

# Implementations
Jido.Trace.Recorder.Null      # No-op (production default for deterministic)
Jido.Trace.Recorder.InMemory  # ETS-backed (debugging, tests)
Jido.Trace.Recorder.Logger    # Structured logging
Jido.Trace.Recorder.OpenTelemetry  # Spans + traces
```

### Recording Levels

Configure per-environment:

```elixir
# Deterministic paths: cheap
config :jido, :recorder, {Jido.Trace.Recorder.Null, []}

# Development: full visibility
config :jido, :recorder, {Jido.Trace.Recorder.InMemory, level: :full}

# Production with LLM: effects only
config :jido, :recorder, {Jido.Trace.Recorder.Logger, level: :effects_only}
```

| Level | `:msg_in` | `:effect_request` | `:effect_result` |
|-------|-----------|-------------------|------------------|
| `:off` | ❌ | ❌ | ❌ |
| `:errors_only` | ❌ | ❌ | ✅ (errors) |
| `:effects_only` | ❌ | ✅ | ✅ |
| `:full` | ✅ | ✅ | ✅ |

### Replay Strategy

**Deterministic replay** (behavior tree, FSM):
```elixir
def replay(agent, events) do
  events
  |> Enum.filter(&(&1.kind == :msg_in))
  |> Enum.reduce(agent, fn event, a ->
    {a2, _directives} = Agent.update(a, event.msg)
    a2
  end)
end
```

**Non-deterministic replay** (LLM, external APIs):
```elixir
def replay_with_effects(agent, events) do
  # Build a map of effect responses from the log
  effect_responses = 
    events
    |> Enum.filter(&(&1.kind == :effect_result))
    |> Map.new(fn e -> {e.effect, e.result} end)
  
  # Replay messages, injecting recorded responses instead of calling external
  events
  |> Enum.filter(&(&1.kind == :msg_in))
  |> Enum.reduce(agent, fn event, a ->
    {a2, directives} = Agent.update(a, event.msg)
    # Directives that would call LLM are skipped;
    # their responses are already in the :msg_in stream
    a2
  end)
end
```

**Key insight**: Non-deterministic responses (LLM, HTTP) come back as messages into `update/2`. So the `:msg_in` stream already contains `{:llm_response, tag, response}`. For replay, you just skip the directives and let the recorded response messages drive the state.

### Integration with AgentServer

```elixir
defmodule Jido.AgentServer do
  alias Jido.Trace.Observability
  
  def handle_call({:cmd, instructions, opts}, _from, agent) do
    # Wrap update in observability
    {agent, directives} = 
      Observability.around_update(agent, {:cmd, instructions}, fn ->
        Agent.cmd(agent, instructions, opts)
      end)
    
    # Interpret directives with effect tracing
    agent = interpret_directives(agent, directives)
    {:reply, {:ok, agent}, agent}
  end
  
  defp interpret_directives(agent, directives) do
    Enum.reduce(directives, agent, fn
      {:call_llm, prompt, tag} = directive, a ->
        # Record the request
        Observability.record_effect_request(a, directive)
        
        # Execute with response tracing
        Task.start(fn ->
          {response, _meta} = 
            Observability.around_effect(a, directive, fn ->
              LLMClient.complete(prompt)
            end)
          
          # Response comes back as a message → recorded by around_update
          send(self(), {:llm_response, tag, response})
        end)
        a
      
      other, a ->
        interpret_other(a, other)
    end)
  end
end
```

### What You Get

| Capability | Deterministic Brain | Non-Deterministic Brain |
|------------|---------------------|-------------------------|
| State replay | ✅ From `:msg_in` log | ✅ From `:msg_in` log (includes responses) |
| Debug "what happened" | ✅ Message sequence | ✅ Message + effect logs |
| Audit external calls | N/A | ✅ Request + response captured |
| Performance overhead | ~0 (`:off` mode) | Moderate (serialization) |
| Production monitoring | Optional | Recommended |

---

## Future: Event Sourcing Layer

If you later need replay/audit, layer it without changing the public API:

```elixir
@spec decide(t(), msg()) :: {[event()], [directive()]}
@spec evolve(t(), [event()]) :: t()

def update(agent, msg) do
  {events, directives} = decide(agent, msg)
  {evolve(agent, events), directives}
end
```

Users still call `update/2`; you gain:
- Event persistence
- State reconstruction from event log
- Time-travel debugging
- Multiple projections

---

## Summary

| Aspect | Decision |
|--------|----------|
| **Core pattern** | Elm/Redux: `update(agent, msg) -> {agent, directives}` |
| **State ownership** | Agent struct is sole source of truth |
| **Directives** | External effects only (send, spawn, call_llm) |
| **Brains** | Message producers via `Brain.tick/3` behaviour |
| **OTP integration** | GenServer interprets directives |
| **Testing** | Pure function assertions, no mocking |

This is the foundation. Everything else builds on this.

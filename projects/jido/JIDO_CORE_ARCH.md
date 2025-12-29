# Jido Core Architecture: Reconciling Agent2 with Core Thesis

## The Tension

**Core Thesis says:**
> Agents think by running a pure function: `(state, signal) → {:ok, new_state, [Effect.t()]}`

**But this conflates two things:**
1. The Agent as a **data structure** (what Agent2 is)
2. The Agent as a **process** that handles signals (what AgentServer does)

**Key corrections:**
- Actions are NOT pure - they perform I/O (HTTP calls, DB queries, etc.)
- `handle_signal/2` is a **process-level concern**, not a data structure concern
- The core thesis requires a bigger architectural change than Agent2 provides

---

## Current Reality: Agent2

Agent2 is a **pure data structure** with operations:

```elixir
%Agent2{
  id: "agent-123",
  state: %{status: :idle, counter: 0},
  actions: [Action1, Action2],
  result: nil
}

# Pure operations on the data structure
agent = MyAgent.new()
{:ok, agent} = MyAgent.set(agent, %{status: :running})
{:ok, agent} = MyAgent.validate(agent)
{:ok, agent, directives} = MyAgent.cmd(agent, SomeAction, opts)
```

**What `cmd/3` does:**
1. Normalizes instructions
2. Validates actions are allowed
3. Executes actions via `Jido.Exec` (performs I/O!)
4. Actions return `{:ok, result}` or `{:ok, result, directives}`
5. Directives applied to modify agent state
6. Returns updated agent + remaining directives

**The friction:** Actions modify agent state indirectly via directives. This works but feels indirect.

---

## Core Thesis Vision: handle_signal

The thesis proposes `handle_signal/2` as the core callback:

```elixir
def handle_signal(state, %Signal{type: :user_message, data: %{text: text}}) do
  new_state = %{state | 
    history: [%{role: :user, content: text} | state.history],
    status: :thinking
  }
  
  effects = [%Effect.Run{action: LookupFAQ, params: %{query: text}}]
  
  {:ok, new_state, effects}
end
```

**Key insight:** This is describing what happens in **AgentServer**, not Agent2.

The thesis flow:
```
Signal arrives at AgentServer
  → AgentServer calls Agent.handle_signal(state, signal)
  → Agent returns new_state + effects
  → AgentServer updates its internal state
  → AgentServer executes effects (runs actions, sets timers, etc.)
  → Action results come back as new signals
  → Loop
```

---

## The Layering

```
┌─────────────────────────────────────────────────────────────┐
│                     AgentServer (GenServer)                  │
│  - Owns the process                                          │
│  - Receives signals (messages)                               │
│  - Calls handle_signal/2 to decide what to do               │
│  - Executes effects (runs actions, timers, etc.)            │
│  - Updates internal state                                    │
├─────────────────────────────────────────────────────────────┤
│                     Agent2 (Data Structure)                  │
│  - Pure data: id, state, actions, schema, result            │
│  - Pure operations: new/1, set/2, validate/2                │
│  - cmd/3 is a convenience that actually does I/O            │
└─────────────────────────────────────────────────────────────┘
```

**Realization:** Agent2's `cmd/3` is doing what AgentServer should do. It's a shortcut that bypasses the signal/effect model.

---

## Can We Iterate from Agent2 Toward Core Thesis?

### Option 1: Keep Agent2 as-is, build AgentServer on top

Agent2 remains the data structure. AgentServer wraps it:

```elixir
defmodule Jido.AgentServer do
  use GenServer
  
  defstruct [:agent, :module]
  
  def handle_info({:signal, signal}, state) do
    # Call the module's handle_signal callback
    case state.module.handle_signal(state.agent, signal) do
      {:ok, new_agent, effects} ->
        # Execute effects
        execute_effects(effects, state)
        {:noreply, %{state | agent: new_agent}}
      {:error, reason} ->
        # Handle error
    end
  end
end
```

**Problem:** Agent2 has `cmd/3` which bypasses signals entirely. Two ways to execute actions.

### Option 2: Agent2 becomes pure, cmd/3 removed

Agent2 only has pure operations:
- `new/1` - create
- `set/2` - update state  
- `validate/2` - validate state
- `apply_result/2` - apply action result to state

No `cmd/3`. Action execution moves entirely to AgentServer:

```elixir
# In AgentServer
def handle_signal(agent, signal) do
  # Decide what to do based on signal
  case signal.type do
    :run_action ->
      effects = [%Effect.Run{action: signal.data.action, params: signal.data.params}]
      {:ok, agent, effects}
    
    :action_result ->
      # Agent decides how to incorporate result
      new_agent = apply_action_result(agent, signal.data)
      {:ok, new_agent, []}
  end
end
```

**Problem:** Requires rewriting how actions work. Big change.

### Option 3: Gradual - Add handle_signal as optional callback

Keep Agent2's `cmd/3` for direct execution. Add optional `handle_signal/2` for signal-driven mode:

```elixir
defmodule MyAgent do
  use Jido.Agent2, 
    name: "my_agent",
    schema: [status: [type: :atom, default: :idle]]
  
  # Optional: signal-driven mode
  def handle_signal(agent, %Signal{type: :user_message} = signal) do
    new_state = Map.put(agent.state, :last_message, signal.data.text)
    effects = [%Effect.Run{action: ProcessMessage, params: signal.data}]
    {:ok, %{agent | state: new_state}, effects}
  end
  
  # Direct mode still works
  # {:ok, agent, directives} = MyAgent.cmd(agent, SomeAction)
end
```

**AgentServer uses handle_signal when available, falls back to cmd/3.**

---

## The Core Question

**Is `cmd/3` the right primitive for Agent2?**

Current `cmd/3`:
- Executes actions immediately (I/O)
- Actions return directives that modify state
- Convenient but impure

Alternative - keep Agent2 pure:
- Agent2 only has data operations
- `cmd/3` moves to a separate executor or AgentServer
- Agent2 is truly just a data structure

---

## Recommendation: Incremental Path

### Phase 1: Keep Agent2 as-is
- `cmd/3` remains for direct action execution
- Works for simple use cases
- No breaking changes

### Phase 2: Add Effect types
```elixir
defmodule Jido.Agent.Effect do
  defmodule Run do
    defstruct [:action, :params, :opts]
  end
  
  defmodule Timer do
    defstruct [:in, :signal, :key]
  end
  
  defmodule Emit do
    defstruct [:type, :data, :target]
  end
end
```

### Phase 3: Add handle_signal callback (optional)
```elixir
@callback handle_signal(agent :: t(), signal :: Signal.t()) ::
  {:ok, t(), [Effect.t()]} | {:error, term()}

@optional_callbacks [handle_signal: 2]
```

### Phase 4: Build AgentServer
- Uses `handle_signal/2` when defined
- Falls back to `cmd/3` pattern otherwise
- Executes effects
- Routes action results back as signals

### Phase 5: Deprecate cmd/3 (eventually)
- Signal-driven becomes the primary mode
- `cmd/3` remains for testing/scripting but not production use

---

## State Modification: Directives vs Direct

### Current (Directives)
```elixir
# Action returns directive
def run(params, context) do
  {:ok, %{result: "done"}, [
    %StateModification{op: :set, path: [:status], value: :complete}
  ]}
end
```

### Core Thesis (Direct in handle_signal)
```elixir
def handle_signal(agent, %Signal{type: :action_complete, data: result}) do
  # Agent directly computes new state
  new_state = %{agent.state | status: :complete, last_result: result}
  {:ok, %{agent | state: new_state}, []}
end
```

### Hybrid Approach
- Actions return **results**, not state modifications
- `handle_signal/2` receives action results and decides how to update state
- Directives remain for **server-level concerns** (Spawn, Kill, Emit)

```elixir
# Action returns pure result
def run(params, context) do
  {:ok, %{faq_results: FAQ.search(params.query)}}
end

# Agent's handle_signal incorporates result
def handle_signal(agent, %Signal{type: "action.complete", data: %{action: LookupFAQ, result: result}}) do
  new_state = %{agent.state | 
    faq_cache: result.faq_results,
    status: :ready
  }
  {:ok, %{agent | state: new_state}, []}
end
```

This separates:
- **Action concern:** Do work, return result
- **Agent concern:** Decide how result affects state
- **Server concern:** Execute effects, route signals

---

## Summary

| Aspect | Agent2 Now | Core Thesis | Incremental Path |
|--------|-----------|-------------|------------------|
| Agent | Data + cmd/3 | Pure data | Data + optional handle_signal |
| Actions | Return directives | Return via signals | Return results |
| State changes | Via directives | In handle_signal | Agent decides in handle_signal |
| Execution | cmd/3 (immediate) | Effects (deferred) | Both supported |

**The core thesis isn't wrong - it's just describing a higher layer (AgentServer) than what Agent2 is.**

Agent2 is the data structure. The thesis describes how that data structure is used within a process. We can iterate toward the thesis by:
1. Adding `handle_signal/2` as an optional callback
2. Building AgentServer that uses it
3. Gradually migrating from `cmd/3` to signal-driven

---

*Document Version: 1.1.0*  
*Created: December 2024*

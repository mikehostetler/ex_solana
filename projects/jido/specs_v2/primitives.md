# Jido 2.0 Primitives Reference

> A complete reference for all core nouns: what they are, how they relate, and their contracts.

---

## Overview

Jido 2.0 is built on a small set of well-defined primitives. This document serves as the authoritative reference for each.

At a high level: **Agents think. Servers act.** Agents run pure `handle_signal/2` functions; AgentServers execute the resulting Effects via Actions and OTP processes.

### Data Flow

```
             THINK (pure)                         ACT (effectful)
┌────────────────────────────────┐      ┌─────────────────────────────┐
│                                │      │                             │
Signal ──→ Agent.handle_signal/2 ──→ [Effect] ──→ AgentServer ──→ Action execution
          (Agent "thinks")                       (Server "acts")
                                                        │
                                                        └──→ Emit, Reply, Timer, etc.
```

The **Think** side is just Elixir functions and data; the **Act** side is GenServers, Actions, and real-world I/O.

### Conventions

- `t()` denotes the main struct type for each module
- `id :: String.t()` for logical identifiers
- `ms :: non_neg_integer()` for milliseconds
- All code examples assume `alias Jido.Agent.Effect`

---

## Quick Reference

| Primitive | Kind | Layer | Think/Act | Role |
|-----------|------|-------|-----------|------|
| **Action** | Module (behaviour) | Kernel | Act | Executable unit of work with validated I/O |
| **Directive** | Struct | Kernel | Act | Action output—requests changes to agent behavior |
| **Instruction** | Struct | Kernel | — | Concrete invocation of an Action |
| **Plan** | Struct | Battery | — | Structured collection of Instructions |
| **Tool** | Struct | Battery | — | LLM-facing description of an Action |
| **Signal** | Struct | Kernel | Input | Universal message envelope |
| **Agent** | Module (behaviour) | Kernel | **Think** | Pure decision kernel over state and signals |
| **Effect** | Struct | Kernel | Output | Agent output—describes orchestration intent |
| **Runner** | Module (behaviour) | Kernel | Think | Decision engine that produces effects |
| **AgentServer** | Process (GenServer) | Kernel | **Act** | Hosts Agent, interprets Effects, executes I/O |
| **Skill** | Struct | Battery | — | Bundled tools and instructions for LLMs |

---

## Effect vs Directive

Jido distinguishes between two vocabularies for describing change:

| Aspect | Effect | Directive |
|--------|--------|-----------|
| **Source** | Agent (thinking) | Action (working) |
| **When** | Before action execution | After action execution |
| **Authority** | Agent decides its fate | Action requests changes |
| **Semantics** | "Do this next" | "I changed this" |
| **Flow** | Agent → AgentServer | Action → Agent → AgentServer |

```
Signal → Agent.handle_signal/2 → [Effect.t()]
                                      ↓
                              AgentServer executes
                                      ↓
                              Effect.Run → Action.run/2 → {:ok, result, [Directive.t()]}
                                                                ↓
                                                    Directives become Signals
                                                                ↓
                                                    Agent processes them
```

**Effects** are the Agent's orchestration vocabulary—"I've thought about this, here's what should happen."

**Directives** are the Action's request vocabulary—"I did my work, here's how I'd like to modify the agent."

This separation provides:
- **Clear authority model**: Agents decide, Actions request
- **Validation boundaries**: Restrict what Actions can request vs what Agents can decide
- **Composability**: Directives flow back through Agent's decision loop
- **Testability**: Test Agent thinking separately from Action results

---

## 1. Action

### Responsibility

The **unit of work** in Jido. Actions are the only mechanism for agents to cause side effects. They encapsulate I/O, external API calls, database queries, and any other effectful operations.

### Kind

Behaviour + `use Jido.Action` macro.

### Contract

```elixir
defmodule Jido.Action do
  @doc "Zoi schema defining valid input parameters"
  @callback schema() :: Zoi.t()
  
  @doc "Execute the action with validated params and context"
  @callback run(params :: map(), context :: map()) ::
    {:ok, result :: map()}
    | {:ok, result :: map(), directives :: [Jido.Directive.t()]}
    | {:error, reason :: term()}
end
```

Actions may optionally return Directives—requests to modify agent behavior. See [Directive](#2-directive) for details.

### Type

```elixir
# Action modules are atoms (module references)
@type action_module :: module()
```

### Example

```elixir
defmodule MyApp.Actions.LookupFAQ do
  use Jido.Action,
    name: "lookup_faq",
    description: "Searches FAQ database for answers"

  @impl true
  def schema do
    %{
      query: Zoi.string() |> Zoi.min_length(1),
      limit: Zoi.integer() |> Zoi.default(5)
    }
  end

  @impl true
  def run(%{query: query, limit: limit}, _context) do
    results = MyApp.FAQ.search(query, limit: limit)
    {:ok, %{answers: results, count: length(results)}}
  end
end
```

### Properties

| Property | Description |
|----------|-------------|
| **Self-describing** | Name, description, schema for LLM tool calling |
| **Validated** | Zoi schema ensures valid inputs |
| **Pure interface** | Takes params + context, returns result or error |
| **Effectful implementation** | May perform I/O internally |

### Relationships

- **Instruction** references an Action module + params
- **Effect.Run** schedules an Instruction for execution
- **Tool** wraps an Action for LLM consumption
- **AgentServer** executes Actions when processing Run effects

### Kernel vs Battery

- **Kernel:** Behaviour, schema via Zoi, execution contract
- **Battery:** Generators, remote implementations (Python/JS), MCP bridges

---

## 2. Directive

### Responsibility

**Action output** that requests changes to agent behavior. Directives are returned by Actions after execution and represent "I did my work, here's what I'd like to change."

Unlike Effects (which Agents emit to describe orchestration), Directives are **requests** from Actions that flow back through the Agent's decision loop.

### Kind

Union of structs under `Jido.Directive`.

### Type

```elixir
@type t ::
  Directive.Enqueue.t()           # Request to queue another action
  | Directive.StateModification.t()   # Request to modify agent state
  | Directive.RegisterAction.t()      # Request to add capability
  | Directive.DeregisterAction.t()    # Request to remove capability
  | Directive.Emit.t()                # Request to publish a signal
```

### Directive Catalog

#### Directive.Enqueue

Request to queue a follow-up action.

```elixir
defmodule Directive.Enqueue do
  typedstruct do
    field :action, atom(), enforce: true
    field :params, map(), default: %{}
    field :context, map(), default: %{}
  end
end
```

#### Directive.StateModification

Request to modify agent state.

```elixir
defmodule Directive.StateModification do
  typedstruct do
    field :op, :set | :update | :merge, enforce: true
    field :path, list(atom()) | atom()
    field :value, any()
  end
end
```

#### Directive.Emit

Request to publish a signal.

```elixir
defmodule Directive.Emit do
  typedstruct do
    field :type, String.t(), enforce: true
    field :data, map(), default: %{}
  end
end
```

#### Directive.RegisterAction / DeregisterAction

Request to modify agent capabilities.

```elixir
defmodule Directive.RegisterAction do
  typedstruct do
    field :action_module, module(), enforce: true
  end
end
```

### Example Usage

```elixir
defmodule MyApp.Actions.ProcessOrder do
  use Jido.Action, name: "process_order"

  def run(%{order_id: id}, _context) do
    # Do the work...
    {:ok, %{status: :processed}, [
      %Directive.StateModification{op: :set, path: [:last_order], value: id},
      %Directive.Enqueue{action: SendConfirmation, params: %{order_id: id}}
    ]}
  end
end
```

### Directive vs Effect

| Directive | Effect |
|-----------|--------|
| `Directive.Enqueue` | `Effect.Run` |
| `Directive.StateModification` | `Effect.StateModification` |
| `Directive.Emit` | `Effect.Emit` |
| `Directive.RegisterAction` | `Effect.RegisterAction` |

The vocabularies overlap because they describe similar operations, but with different authority and flow:
- **Effect**: Agent decides → AgentServer executes immediately
- **Directive**: Action requests → becomes Signal → Agent decides whether to honor

### Processing Flow

```
Action.run/2 returns {:ok, result, [Directive.t()]}
                              ↓
              AgentServer wraps in :action_result signal
                              ↓
              Agent.handle_signal/2 sees result + directives
                              ↓
              Agent decides: honor, modify, or reject directives
                              ↓
              Agent returns [Effect.t()] based on decision
```

### Kernel vs Battery

**Kernel:** Core directive types (Enqueue, StateModification, Emit, Register/Deregister).

---

## 3. Instruction

### Responsibility

A **concrete invocation** of an Action. Instructions represent "call this action with these parameters."

### Kind

Struct (data).

### Type

```elixir
defmodule Jido.Instruction do
  @type t :: %__MODULE__{
    action: module(),        # The Action module to execute
    params: map(),           # Validated parameters
    context: map(),          # Execution context (user_id, request_id, etc.)
    opts: keyword()          # Execution options (timeout, retries, etc.)
  }
end
```

### Example

```elixir
%Jido.Instruction{
  action: MyApp.Actions.LookupFAQ,
  params: %{query: "password reset", limit: 3},
  context: %{user_id: 42, conversation_id: "conv_123"},
  opts: [timeout: 5_000]
}
```

### Relationships

- Created from `{Action, params}` tuples via `Instruction.normalize/2`
- **Effect.Run** wraps an Instruction
- Agents queue Instructions via `pending_instructions`
- AgentServer dequeues and executes Instructions

### Kernel vs Battery

**Kernel:** This is the fundamental unit of queued work.

---

## 4. Plan

### Responsibility

A **Directed Acyclic Graph (DAG) of Instructions** with dependencies and metadata. Plans represent multi-step workflows produced by Runners or LLM reasoning. The DAG structure enables parallel execution of independent steps while respecting dependencies.

### Kind

Struct (data). Optional construct for complex orchestration.

### Type

```elixir
defmodule Jido.Plan do
  @type step :: %{
    id: term(),
    instruction: Jido.Instruction.t(),
    deps: [term()],           # IDs of prerequisite steps (DAG edges)
    status: :pending | :running | :completed | :failed,
    result: term() | nil      # Populated after execution
  }

  @type t :: %__MODULE__{
    id: term(),
    steps: [step()],          # Nodes in the DAG
    metadata: map(),
    created_at: DateTime.t()
  }
end
```

### DAG Properties

- **Nodes**: Each step is a node containing an Instruction
- **Edges**: `deps` field defines directed edges (step → dependency)
- **Acyclic**: No circular dependencies allowed (validated on creation)
- **Parallel execution**: Steps with satisfied dependencies can run concurrently
- **Topological ordering**: Execution respects dependency order

### Example

```elixir
# DAG structure:
#
#     ┌─────────┐     ┌─────────┐
#     │ search  │     │ fetch   │
#     └────┬────┘     └────┬────┘
#          │               │
#          └───────┬───────┘
#                  ▼
#            ┌──────────┐
#            │   read   │
#            └────┬─────┘
#                 │
#                 ▼
#           ┌───────────┐
#           │ summarize │
#           └───────────┘

%Jido.Plan{
  id: "plan_research_123",
  steps: [
    %{id: :search, instruction: %Instruction{action: WebSearch, ...}, deps: []},
    %{id: :fetch, instruction: %Instruction{action: FetchContext, ...}, deps: []},
    %{id: :read, instruction: %Instruction{action: ReadPage, ...}, deps: [:search, :fetch]},
    %{id: :summarize, instruction: %Instruction{action: Summarize, ...}, deps: [:read]}
  ],
  metadata: %{strategy: :react, model: "gpt-4"}
}
```

### API

```elixir
defmodule Jido.Plan do
  @doc "Create a new plan, validating DAG structure"
  @spec new(steps :: [step()], metadata :: map()) :: {:ok, t()} | {:error, :cycle_detected}

  @doc "Get steps ready for execution (all deps satisfied)"
  @spec ready_steps(t()) :: [step()]

  @doc "Mark a step as completed with result"
  @spec complete_step(t(), step_id :: term(), result :: term()) :: t()

  @doc "Check if plan is fully executed"
  @spec completed?(t()) :: boolean()

  @doc "Validate no cycles exist"
  @spec validate_dag(t()) :: :ok | {:error, :cycle_detected}
end
```

### Relationships

- ReAct/CoT/HTN runners produce and modify Plans
- Plans decompose into `Effect.Run` lists for execution
- Plans provide visibility into multi-step reasoning
- DAG structure enables parallel action execution

### Kernel vs Battery

**Battery:** Only needed for multi-step LLM workflows. Simple agents don't need Plans.

---

## 5. Tool

### Responsibility

An **LLM-facing description** of an Action. Tools serialize Action metadata into formats LLMs understand (OpenAI function calling, Anthropic tool use, etc.).

### Kind

Struct (data).

### Type

```elixir
defmodule Jido.Tool do
  @type t :: %__MODULE__{
    name: String.t(),
    description: String.t(),
    schema: map(),              # JSON Schema-compatible
    action: module(),           # Source Action module
    metadata: map()
  }
end
```

### Example

```elixir
%Jido.Tool{
  name: "lookup_faq",
  description: "Searches FAQ database for relevant answers",
  schema: %{
    "type" => "object",
    "properties" => %{
      "query" => %{"type" => "string", "description" => "Search query"},
      "limit" => %{"type" => "integer", "default" => 5}
    },
    "required" => ["query"]
  },
  action: MyApp.Actions.LookupFAQ
}
```

### Generation

```elixir
# Convert Action to Tool
{:ok, tool} = Jido.Action.to_tool(LookupFAQ)

# Convert all agent actions to tools
tools = Jido.Agent.tools(MyAgent)
```

### Relationships

- Generated from Actions via `Jido.Action.to_tool/1`
- Used by LLM Runners (ReAct, CoT) in prompts
- Bundled into Skills for capability grouping

### Kernel vs Battery

- **Kernel:** `Jido.Action.to_tool/1` conversion
- **Battery:** Advanced formatting, prompt integration, provider-specific adapters

---

## 6. Signal

### Responsibility

The **universal message envelope** in Jido. All communication between agents, servers, and external systems uses Signals.

### Kind

Struct.

### Type

```elixir
defmodule Jido.Signal do
  @type t :: %__MODULE__{
    id: String.t(),                    # Unique identifier
    type: atom(),                      # Signal type (e.g., :user_message, :action_result)
    source: term() | nil,              # Origin identifier
    target: term() | nil,              # Destination identifier (optional)
    correlation_id: term() | nil,      # For request/response correlation
    data: map(),                       # Payload
    timestamp: DateTime.t()
  }
end
```

### Standard Signal Types

| Type | Description |
|------|-------------|
| `:user_message` | Input from users |
| `:action_result` | Result from Action execution |
| `:action_error` | Error from Action execution |
| `:timer` | Scheduled/delayed trigger |
| `:system` | Internal control signals |
| `:cmd` | Command signals (set, validate, etc.) |

### Example

```elixir
%Jido.Signal{
  id: "sig_abc123",
  type: :user_message,
  source: "chat_ui",
  data: %{text: "How do I reset my password?"},
  correlation_id: "conv_xyz",
  timestamp: ~U[2024-12-26 10:00:00Z]
}
```

### Relationships

- **Input** to `Agent.handle_signal/2`
- **Payload** for `Effect.Emit` and `Effect.Reply`
- **Scheduled** via `Effect.Timer`
- Carry trace context for observability

### Kernel vs Battery

**Kernel:** Core struct and factory functions.

---

## 7. Agent

### Responsibility

The **pure decision kernel**. Agents own state shape, handle signals, and emit effects. They are data modules, not processes.

### Kind

Behaviour + `use Jido.Agent` macro.

### Callbacks

Jido agents use a minimal callback set inspired by Phoenix LiveView. All callbacks are optional except `handle_signal/2`.

```elixir
defmodule Jido.Agent do
  # ─────────────────────────────────────────────────────────────
  # Lifecycle
  # ─────────────────────────────────────────────────────────────

  @doc """
  Called when the agent is mounted in a server.
  Use for initial state setup, loading data, subscribing to events.
  """
  @callback mount(state :: t(), opts :: keyword()) ::
    {:ok, new_state :: t()}
    | {:ok, new_state :: t(), effects :: [Effect.t()]}
    | {:error, term()}

  @doc """
  Called when the agent is shutting down.
  Use for cleanup, saving state, unsubscribing.
  """
  @callback terminate(reason :: term(), state :: t()) :: :ok

  # ─────────────────────────────────────────────────────────────
  # Signal Handling (required)
  # ─────────────────────────────────────────────────────────────

  @doc """
  Handle incoming signal. This is the core "thinking" function.
  Pattern match on signal type to handle different messages.
  """
  @callback handle_signal(state :: t(), signal :: Jido.Signal.t()) ::
    {:ok, new_state :: t(), effects :: [Effect.t()]}
    | {:error, term()}

  # ─────────────────────────────────────────────────────────────
  # Introspection (auto-generated, overridable)
  # ─────────────────────────────────────────────────────────────

  @doc "Return state schema (Zoi)"
  @callback schema() :: Zoi.t()

  @doc "Return registered actions"
  @callback actions() :: [module()]
end
```

### Callback Summary

| Callback | Required | When Called | Returns |
|----------|----------|-------------|---------|
| `mount/2` | No | AgentServer starts | `{:ok, state}` or `{:ok, state, effects}` |
| `handle_signal/2` | **Yes** | Signal received | `{:ok, state, effects}` |
| `terminate/2` | No | AgentServer stopping | `:ok` |
| `schema/0` | No | Compile-time | `Zoi.t()` |
| `actions/0` | No | Compile-time | `[module()]` |

### Pattern Matching in handle_signal

Use pattern matching to differentiate signal types—like LiveView's `handle_event`:

```elixir
defmodule MyApp.SupportAgent do
  use Jido.Agent,
    name: "support",
    schema: %{
      user_id: Zoi.integer(),
      history: Zoi.list(Zoi.any()) |> Zoi.default([]),
      status: Zoi.atom() |> Zoi.default(:idle)
    }

  # Handle user messages
  def handle_signal(state, %{type: :user_message, data: %{text: text}}) do
    new_state = %{state | history: [text | state.history]}
    {:ok, new_state, [%Effect.Run{action: LookupFAQ, params: %{query: text}}]}
  end

  # Handle action results
  def handle_signal(state, %{type: :action_result, data: %{result: result}}) do
    {:ok, state, [%Effect.Reply{signal: build_response(result)}]}
  end

  # Handle action results with directives
  def handle_signal(state, %{type: :action_result, data: %{directives: directives}}) do
    # Agent decides whether to honor directives from Actions
    effects = process_directives(directives)
    {:ok, state, effects}
  end

  # Catch-all
  def handle_signal(state, _signal) do
    {:ok, state, []}
  end
end
```

### Lifecycle Example

```elixir
defmodule MyApp.StatefulAgent do
  use Jido.Agent, name: "stateful"

  @impl true
  def mount(state, opts) do
    # Load persisted state, subscribe to events
    loaded = MyApp.Repo.load_agent_state(state.id)
    {:ok, Map.merge(state, loaded), [
      %Effect.Subscribe{topic: "updates:#{state.id}"}
    ]}
  end

  @impl true
  def handle_signal(state, signal) do
    # ... handle signals
    {:ok, state, []}
  end

  @impl true
  def terminate(_reason, state) do
    # Persist state on shutdown
    MyApp.Repo.save_agent_state(state.id, state)
    :ok
  end
end
```

### Default Implementations

The `use Jido.Agent` macro provides sensible defaults:

```elixir
def mount(state, _opts), do: {:ok, state}
def terminate(_reason, _state), do: :ok
def schema(), do: %{}
def actions(), do: []
```

### Properties

| Property | Description |
|----------|-------------|
| **Pure** | `handle_signal/2` has no side effects |
| **Stateful** | Owns and transforms state |
| **Declarative** | Emits effects, doesn't execute them |
| **Testable** | Call directly without processes |

### Relationships

- **AgentServer** hosts and runs an Agent, calls lifecycle callbacks
- **Runners** implement `handle_signal/2` for common patterns
- **Actions** are registered capabilities
- **Effects** are the output vocabulary

### Kernel vs Battery

**Kernel:** Behaviour, macro, base struct fields, Zoi integration.

---

## 8. Effect

### Responsibility

The **Agent's orchestration vocabulary**. Effects are pure data describing what should happen. Agents emit them; AgentServer executes them.

> **Note:** Effects are distinct from [Directives](#2-directive). Effects come from Agents (thinking); Directives come from Actions (working). See [Effect vs Directive](#effect-vs-directive).

### Kind

Union of structs under `Jido.Agent.Effect`.

### Type

```elixir
@type t ::
  Effect.Run.t()
  | Effect.StateModification.t()
  | Effect.RegisterAction.t()
  | Effect.DeregisterAction.t()
  | Effect.Spawn.t()
  | Effect.Kill.t()
  | Effect.Emit.t()
  | Effect.AddRoute.t()
  | Effect.RemoveRoute.t()
  | Effect.Reply.t()
  | Effect.Timer.t()
```

### Effect Catalog

#### Effect.Run

Execute an action. This is the primary way agents cause work to happen.

```elixir
defmodule Effect.Run do
  typedstruct do
    field :action, module(), enforce: true  # Action module to execute
    field :params, map(), default: %{}       # Action parameters
    field :context, map(), default: %{}      # Execution context
    field :opts, keyword(), default: []      # Options (timeout, etc.)
  end
end
```

#### Effect.StateModification

Modify agent state at a path.

```elixir
defmodule Effect.StateModification do
  typedstruct do
    field :op, :set | :update | :delete | :reset | :replace, enforce: true
    field :path, list(atom()) | atom()
    field :value, any()
  end
end
```

#### Effect.Emit

Publish a signal to a signal bus.

```elixir
defmodule Effect.Emit do
  typedstruct do
    field :type, String.t(), enforce: true
    field :data, map(), default: %{}
    field :source, String.t()
    field :bus, atom(), default: :default
    field :stream, String.t()
  end
end
```

#### Effect.Reply (New in V2)

Send a response signal.

```elixir
defmodule Effect.Reply do
  typedstruct do
    field :to, term()                    # Target (defaults to signal source)
    field :signal, Jido.Signal.t()       # Response signal
  end
end
```

#### Effect.Timer (New in V2)

Schedule a future signal.

```elixir
defmodule Effect.Timer do
  typedstruct do
    field :in, non_neg_integer(), enforce: true  # Milliseconds
    field :signal, Jido.Signal.t(), enforce: true
    field :key, term(), default: nil              # For cancellation/dedup
  end
end
```

#### Effect.Spawn

Start a child process.

```elixir
defmodule Effect.Spawn do
  typedstruct do
    field :module, module(), enforce: true
    field :args, term(), enforce: true
  end
end
```

#### Effect.Kill

Terminate a child process.

```elixir
defmodule Effect.Kill do
  typedstruct do
    field :pid, pid(), enforce: true
  end
end
```

#### Effect.RegisterAction / DeregisterAction

Add or remove actions from agent's capability set.

```elixir
defmodule Effect.RegisterAction do
  typedstruct do
    field :action_module, module(), enforce: true
  end
end
```

#### Effect.AddRoute / RemoveRoute

Manage agent's router.

```elixir
defmodule Effect.AddRoute do
  typedstruct do
    field :path, String.t(), enforce: true
    field :target, term(), enforce: true
  end
end
```

### Execution Layer

| Effect | Executor | Side Effect |
|-----------|----------|-------------|
| Run | AgentServer | Executes Action, sends result signal back |
| StateModification | Agent (pure) | Updates agent state |
| Emit | AgentServer | Publishes to signal bus |
| Reply | AgentServer | Sends response to caller |
| Timer | AgentServer | Schedules `Process.send_after/3` |
| Spawn | AgentServer | Starts supervised child |
| Kill | AgentServer | Terminates child process |
| Register/Deregister | Agent (pure) | Modifies action list |
| Add/RemoveRoute | AgentServer | Updates router |

### Kernel vs Battery

**Kernel:** All effect types listed above.

---

## 9. Runner

### Responsibility

**Decision engine** that implements `handle_signal/2` using a specific strategy. Runners are pluggable—swap FSM for ReAct without changing your agent's structure.

### Kind

Behaviour + optional `use Jido.Agent.Runner.*` macros.

### Contract

```elixir
defmodule Jido.Agent.Runner do
  @callback handle(
    agent_module :: module(),
    state :: struct(),
    signal :: Jido.Signal.t()
  ) ::
    {:ok, new_state :: struct(), effects :: [Jido.Agent.Effect.t()]}
    | {:error, term()}

  @doc "Return Spark DSL extension for this runner (optional)"
  @callback dsl_extension() :: module() | nil
end
```

### Built-in Runners

| Runner | Atom | Description | Layer |
|--------|------|-------------|-------|
| StateMachine | `:state_machine` | Deterministic FSM transitions | Kernel |
| BehaviorTree | `:behavior_tree` | Complex decision trees | Battery |
| ReAct | `:react` | LLM reasoning + tool use | Battery |
| ChainOfThought | `:chain_of_thought` | Step-by-step reasoning | Battery |

### Usage

```elixir
# Via use macro
use Jido.Agent,
  name: "support",
  runner: :state_machine

# Via runtime configuration
Jido.AgentServer.start_link(MyAgent, runner: Jido.Agent.Runner.ReAct)
```

### Runner vs Manual

You can skip runners entirely:

```elixir
defmodule SimpleAgent do
  use Jido.Agent, name: "simple"
  
  # Direct implementation, no runner
  def handle_signal(state, signal) do
    # Your logic here
    {:ok, state, []}
  end
end
```

### Kernel vs Battery

- **Kernel:** `Runner` behaviour, `:state_machine` implementation
- **Battery:** `:behavior_tree`, `:react`, `:chain_of_thought`, DSL extensions

---

## 10. AgentServer

### Responsibility

The **process host** for Agents. AgentServer is a GenServer that:

1. Holds agent state
2. Calls Agent lifecycle callbacks (`mount`, `terminate`)
3. Receives signals and calls `Agent.handle_signal/2`
4. Executes returned effects
5. Manages timers, children, routing

### Kind

GenServer implementation.

### API

```elixir
defmodule Jido.AgentServer do
  @doc "Start a new agent server"
  @spec start_link(module(), term(), keyword()) :: GenServer.on_start()
  def start_link(agent_module, id, opts \\ [])

  @doc "Send a signal to the agent"
  @spec send_signal(server_ref(), Jido.Signal.t()) :: 
    :ok | {:ok, result} | {:error, term()}
  def send_signal(server, signal)

  @doc "Get current agent state"
  @spec get_state(server_ref()) :: {:ok, struct()} | {:error, term()}
  def get_state(server)

  @doc "Synchronous signal with reply"
  @spec call_signal(server_ref(), Jido.Signal.t(), timeout()) ::
    {:ok, Jido.Signal.t()} | {:error, term()}
  def call_signal(server, signal, timeout \\ 5_000)
end
```

### Lifecycle

```
start_link(AgentModule, id, opts)
    │
    ▼
┌──────────────────────────────┐
│  GenServer init              │
│  - Create initial state      │
│  - Call Agent.mount/2        │
│  - Execute mount effects     │
└──────────────────────────────┘
    │
    ▼
┌──────────────────────────────┐
│  Receive Signal              │◄──────────┐
│                              │           │
│  THINK:                      │           │
│    - Call Agent.handle_signal/2          │
│    - Get new_state + effects │           │
│                              │           │
│  ACT:                        │           │
│    - Execute effects         │───────────┘
│      - Run → execute Action  │
│      - Reply → send response │
│      - Timer → schedule      │
│      - Emit → publish        │
└──────────────────────────────┘
    │
    ▼ (on shutdown)
┌──────────────────────────────┐
│  Call Agent.terminate/2      │
│  - Cleanup, persist state    │
└──────────────────────────────┘
```

The AgentServer lifecycle is: **think once (pure), then act on the resulting Effects (effectful).**

### Properties

| Property | Description |
|----------|-------------|
| **Generic** | One implementation for all Agent types |
| **Supervised** | Standard OTP supervision |
| **Effect interpreter** | All I/O happens here |
| **Stateless logic** | Delegates decision-making to Agent |

### Kernel vs Battery

**Kernel:** Core GenServer implementation, effect execution.

---

## 11. Skill

### Responsibility

A **named bundle** of tools and instructions for LLMs. Skills group related capabilities and provide context for how/when to use them.

### Kind

Struct (data).

### Type

```elixir
defmodule Jido.Skill do
  @type t :: %__MODULE__{
    name: String.t(),
    description: String.t(),
    tools: [Jido.Tool.t()],
    prompt: String.t() | nil,        # Usage instructions for LLM
    examples: [map()],               # Example invocations
    metadata: map()
  }
end
```

### Example

```elixir
%Jido.Skill{
  name: "customer_support",
  description: "Tools for handling customer inquiries",
  tools: [
    Jido.Action.to_tool(LookupFAQ),
    Jido.Action.to_tool(CreateTicket),
    Jido.Action.to_tool(EscalateToHuman)
  ],
  prompt: """
  You are a customer support agent. Use these tools to help customers:
  - lookup_faq: Search for answers to common questions
  - create_ticket: Create a support ticket for complex issues
  - escalate_to_human: Hand off to a human agent when needed
  """,
  examples: [
    %{input: "I forgot my password", tool: "lookup_faq", params: %{query: "password reset"}}
  ]
}
```

### Relationships

- Contains multiple Tools
- Used by ReAct/CoT runners for capability discovery
- Can be loaded dynamically based on context

### Kernel vs Battery

**Battery:** Only needed for LLM-driven agents with dynamic capability loading.

---

## Relationship Diagram

```
                           ┌─────────────┐
                           │    Skill    │ (Battery)
                           │  bundles    │
                           └──────┬──────┘
                                  │
                           ┌──────▼──────┐
                           │    Tool     │ (Battery)
                           │  LLM-facing │
                           └──────┬──────┘
                                  │
┌──────────────────────────────────────────────────────────────────┐
│                            KERNEL                                 │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌────────┐    ┌───────────────┐    ┌───────────┐                │
│  │ Action │◄───│  Instruction  │◄───│   Plan    │ (Battery)      │
│  │  work  │    │  invocation   │    │  steps    │                │
│  └────┬───┘    └───────────────┘    └───────────┘                │
│       │                                                           │
│       │ returns                                                   │
│       ▼                                                           │
│  ┌────────────┐                                                   │
│  │ Directive  │ ─── requests ───┐                                │
│  │ (requests) │                 │                                │
│  └────────────┘                 │                                │
│                                 ▼                                 │
│  ┌────────┐    ┌───────────────┐    ┌───────────┐                │
│  │ Signal │───►│     Agent     │───►│  Effect   │                │
│  │ input  │    │ THINK (pure)  │    │ (decides) │                │
│  └────────┘    └───────┬───────┘    └─────┬─────┘                │
│                        │                  │                       │
│                        │                  ▼                       │
│                 ┌──────▼──────┐   ┌──────────────┐               │
│                 │   Runner    │   │ AgentServer  │               │
│                 │  strategy   │   │  ACT (I/O)   │               │
│                 └─────────────┘   └──────────────┘               │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0.0-draft | Dec 2024 | Initial V2 specification |
| 2.0.0-draft.2 | Dec 2024 | Added Directive (distinct from Effect), LiveView-style callbacks (mount, handle_signal, terminate), renamed Effect.Enqueue → Effect.Run |

---

*Specification Version: 2.0.0-draft.2*  
*Last Updated: December 2024*

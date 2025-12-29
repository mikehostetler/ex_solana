# JIDO_AGENT_V2 Simplification Plan

## 0. TL;DR

Jido.Agent v2 should be a small, pure, Zoi-based data structure with a minimal functional API (`new/1`, `set_state/2`, `validate/2`, `execute/3`). All GenServer/OTP integration, queues, and directive application move into separate modules. Lifecycle hooks shrink to at most 2–3 well‑defined callbacks. The existing macro-heavy API (`set/3`, `plan/3`, `run/2`, `cmd/4`, server callbacks) is preserved temporarily via thin shims, then deprecated.

---

## 1. Goals & Scope

### Goals

1. **Migrate from TypedStruct + NimbleOptions to Zoi** for the Agent struct and compile-time configuration.
2. **Radically simplify the API** to the pure functional essence:
   - Agent = immutable state holder
   - Execution = `agent + instructions + context/opts -> {:ok, agent, directives} | {:error, error}`
3. **Minimize lifecycle hooks** to a small, coherent set.
4. **Separate concerns**:
   - Core Agent data + pure functions
   - Execution/runner logic
   - GenServer/OTP integration
   - Directive handling
5. **Clarify the conceptual "essence"** of an agent and reflect it in code structure.

### Non-goals (for v2 baseline)

- No attempt to solve all future scalability/feature needs; focus on clarity and maintainability.
- No hard requirement for strict backward compatibility; a deprecation shim layer is acceptable.
- No complete migration of all state schemas from NimbleOptions to Zoi yet; we allow both similarly to `Jido.Action`.

---

## 2. Current State: Problems & Complexity Hotspots

From `Jido.Agent` today (≈1400 LOC):

### Struct definition & config
- Uses `TypedStruct` for the core Agent struct.
- Uses `NimbleOptions` for both compile-time agent configuration and runtime state validation.
- Struct includes both core state and execution machinery (`pending_instructions`, `dirty_state?`).

### Macro-heavy API
- `use Jido.Agent`:
  - Validates options via NimbleOptions.
  - Defines per-agent struct fields and default values.
  - Injects a large amount of logic (new/set/validate/plan/run/cmd/reset/pending?/server facing functions).
- API surface is large and multi-phase: `set/3`, `validate/2`, `plan/3`, `run/2`, `cmd/4`, plus registration helpers.

### Lifecycle hooks overload
- Agent-level hooks: `on_before_validate_state/1`, `on_after_validate_state/1`, `on_before_plan/3`, `on_before_run/1`, `on_after_run/3`, `on_error/2`.
- Server-level hooks mixed into same behaviour: `mount/2`, `code_change/3`, `shutdown/2`, `handle_signal/2`, `transform_result/3`.

### Concern mixing
- Data structure definition, execution pipeline (plan/run/cmd), directive application, and GenServer integration are all in the same module/macro.
- The Agent struct carries execution concerns (`pending_instructions`, `dirty_state?`) that are really runner/server concerns.

### Queue-centric model
- `pending_instructions` queue and separate `plan/3` + `run/2` phases.
- `cmd/4` is a complex "do everything" wrapper: validate, plan, execute, handle errors.

All of this makes Agent harder to reason about, to compose, and to test as a pure value.

---

## 3. Target Design: Jido.Agent v2

### 3.1 Core Data Model (Zoi struct)

**Essence**: an Agent is just **metadata + state + allowed actions**. No queues, no server concerns.

Define a Zoi struct, following the `Jido.Instruction` pattern:

```elixir
defmodule Jido.Agent do
  @moduledoc """
  Core Agent data structure and pure functional operations.

  This module is *instance-level* only: it knows nothing about GenServer/OTP.
  """

  alias Jido.Agent

  @schema Zoi.struct(
            __MODULE__,
            %{
              id:
                Zoi.string(description: "Unique agent identifier")
                |> Zoi.optional(),
              name:
                Zoi.string(description: "Agent name")
                |> Zoi.optional(),
              description: Zoi.string(description: "Agent description") |> Zoi.optional(),
              category: Zoi.string(description: "Agent category") |> Zoi.optional(),
              tags: Zoi.list(Zoi.string(), description: "Tags") |> Zoi.default([]),
              vsn: Zoi.string(description: "Version") |> Zoi.optional(),
              state_schema:
                Zoi.any(
                  description:
                    "NimbleOptions or Zoi schema for validating the Agent's state"
                )
                |> Zoi.default([]),
              actions:
                Zoi.list(Zoi.atom(), description: "Allowed action modules")
                |> Zoi.default([]),
              state: Zoi.map(description: "Current state") |> Zoi.default(%{}),
              result: Zoi.any(description: "Last execution result") |> Zoi.default(nil)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Agent."
  def schema, do: @schema
end
```

Notes:

- No `pending_instructions`, no `dirty_state?` in the core struct.
- `state_schema` uses `Zoi.any/1` so it can hold either a NimbleOptions schema or a Zoi schema (matching `Jido.Action` approach).
- All "instance-level" logic (construction, state updates, validation, execution) lives in this module or submodules that operate on `%Jido.Agent{}`.

#### Compile-time config for `use Jido.Agent`

We also define a **config schema** (similar to `Jido.Action.@action_config_schema`):

```elixir
@agent_config_schema Zoi.object(%{
  name:
    Zoi.string(
      description: "The name of the Agent. Must contain only letters, numbers, and underscores."
    )
    |> Zoi.refine({Jido.Util, :validate_name, []}),
  description:
    Zoi.string(description: "A description of what the Agent does.")
    |> Zoi.optional(),
  category:
    Zoi.string(description: "The category of the Agent.")
    |> Zoi.optional(),
  tags:
    Zoi.list(Zoi.string(), description: "Tags")
    |> Zoi.default([]),
  vsn:
    Zoi.string(description: "Version")
    |> Zoi.optional(),
  actions:
    Zoi.list(Zoi.atom(), description: "Action modules allowed for this agent")
    |> Zoi.default([]),
  state_schema:
    Zoi.any(
      description:
        "NimbleOptions or Zoi schema for validating the Agent's state."
    )
    |> Zoi.default([])
})
```

`use Jido.Agent, ...` then:

- Validates config against `@agent_config_schema` using Zoi.
- Stores validated config in module attributes.
- Provides lightweight helpers (`name/0`, `state_schema/0`, `actions/0`, etc.).
- Optionally defines a small set of overrideable callbacks (see 3.3).

This replaces the NimbleOptions-based `@agent_compiletime_options_schema` and `TypedStruct` definition.

**Effort**: L (1–2 days) – new Zoi struct + config schema + migration of `__using__/1` to Zoi.

---

### 3.2 Pure Functional API (Core operations)

The v2 functional API should be small and composable. Suggested core functions:

#### 1. Construction

```elixir
@spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
def new(attrs \\ %{}) do
  # Use Zoi to validate/coerce attrs into %Jido.Agent{}
end
```

Typical user-level modules can also expose convenience builders:

```elixir
defmodule MyAgent do
  use Jido.Agent, name: "my_agent", state_schema: [...]

  @spec new(keyword() | map()) :: {:ok, Jido.Agent.t()} | {:error, term()}
  def new(attrs \\ %{}) do
    Jido.Agent.new(
      Map.merge(
        %{name: name(), state_schema: state_schema(), actions: actions()},
        Map.new(attrs)
      )
    )
  end
end
```

#### 2. State updates

```elixir
@spec set_state(Agent.t(), map() | keyword(), keyword()) ::
        {:ok, Agent.t()} | {:error, term()}
def set_state(%Agent{} = agent, attrs, opts \\ []) do
  # Deep-merge (or simple merge, depending on desired semantics)
  # then optionally validate via validate_state/2
end
```

Implementation can reuse existing `DeepMerge` logic but move it to a small helper (`Jido.Agent.State`).

#### 3. State validation

```elixir
@spec validate_state(Agent.t(), keyword()) ::
        {:ok, Agent.t()} | {:error, term()}
def validate_state(%Agent{state_schema: schema} = agent, opts \\ []) do
  # Similar to current validate/2 but:
  # - uses Jido.Action.Schema-style helper that can handle NimbleOptions or Zoi
  # - does not rely on callbacks for pre/post unless explicitly requested
end
```

Ideally, we reuse `Jido.Action.Schema`-style helpers or factor out a shared `Jido.Schema` module.

#### 4. Execution

The core execution primitive should be **single-phase**, not `plan + run`:

```elixir
@type execute_opts :: [
        context: map(),
        apply_directives?: boolean(),
        # optionally: strict_validation: boolean(), timeout: non_neg_integer(), etc.
      ]

@spec execute(Agent.t(), Instruction.instruction() | [Instruction.instruction()], execute_opts()) ::
        {:ok, Agent.t(), [Jido.Agent.Directive.t()]} | {:error, term()}
def execute(%Agent{} = agent, instructions, opts \\ []) do
  # 1) normalize instructions (Instruction.normalize/3)
  # 2) optionally validate allowed actions
  # 3) run them through Jido.Exec (one-by-one or via a new "run_many")
  # 4) apply directives to agent.state via Jido.Agent.Directive
end
```

Key simplifications:

- **No internal queue** in the Agent struct.
- **No separate `plan/3` and `run/2` in the core**; just `execute/3`.
- If "planning" semantics are still desirable, they become a thin convenience layer around `execute/3` or live in a separate module (e.g., `Jido.Agent.Workflow`).

**Effort**: M–L (1–2 days) – but isolated; can be implemented while legacy `plan/run/cmd` still exist.

---

### 3.3 Lifecycle Hooks v2: Minimal Set

Current hooks (6+ Agent callbacks + server callbacks) are too many. For the **core agent**, we should decide on the minimal hooks that are really needed to customize behaviour **without** mixing server concerns.

Proposed core hooks:

#### 1. before_execute/3 – pre-execution adjustment / gating:

```elixir
@callback before_execute(agent :: Agent.t(), instructions :: [Instruction.t()], context :: map()) ::
            {:ok, Agent.t(), [Instruction.t()], map()}
            | {:error, term()}
```

#### 2. after_execute/4 – post-execution processing:

```elixir
@callback after_execute(
            agent :: Agent.t(),
            result :: term(),
            directives :: [Jido.Agent.Directive.t()],
            context :: map()
          ) :: {:ok, Agent.t()} | {:error, term()}
```

#### 3. on_error/4 – central error hook:

```elixir
@callback on_error(
            agent :: Agent.t(),
            error :: term(),
            phase :: :validate | :execute | :directives,
            context :: map()
          ) :: {:ok, Agent.t()} | {:error, term()}
```

Everything else can be derived by user code **outside** the Agent (e.g., by composing around `execute/3`). These hooks can be provided by the `use Jido.Agent` macro with default no-op implementations:

```elixir
def before_execute(agent, instructions, context),
  do: {:ok, agent, instructions, context}

def after_execute(agent, result, directives, _context),
  do: {:ok, %{agent | result: result}}

def on_error(agent, error, _phase, _context),
  do: {:error, error}
```

Server-level hooks (`mount`, `shutdown`, `handle_signal`, `transform_result`, `code_change`) belong exclusively in `Jido.Agent.Server` (or a new behaviour like `Jido.Agent.ServerBehaviour`), not in the core Agent behaviour.

**Effort**: M (1–3h) – defining & wiring basic hooks.

---

### 3.4 Separation of Concerns: Module Layout

Suggested module split:

#### 1. Core data & FP API

- `Jido.Agent`  
  - Zoi struct & type (`@schema`, `t`, `schema/0`).
  - `new/1`, `set_state/3`, `validate_state/2`, `execute/3`.
- `Jido.Agent.State` (optional small helper)
  - Deep merge, strict vs non-strict validation, etc.

#### 2. Compile-time configuration and hooks

- `Jido.Agent.Definition` (or keep in `Jido.Agent` as `__using__/1` but keep it small)
  - `@agent_config_schema` (Zoi.object).
  - `__using__/1` that:
    - Validates options via Zoi.
    - Exposes helper functions: `name/0`, `description/0`, `category/0`, `tags/0`, `vsn/0`, `state_schema/0`, `actions/0`.
    - Defines behaviour & default implementations for `before_execute/3`, `after_execute/4`, `on_error/4`.
    - Optionally defines `new/1` convenience wrapper that builds `%Jido.Agent{}`.

#### 3. Execution / Runner logic

- `Jido.Agent.Runner` (or `Jido.Agent.Execution`)
  - Orchestrates `Instruction.normalize`, `Instruction.validate_allowed_actions`, `Jido.Exec` calls, directive application.
  - Works **only** with `%Jido.Agent{}` and lists of `%Instruction{}`.
  - No GenServer or server IDs—pure functions.

`Jido.Agent.execute/3` can be a thin wrapper over `Jido.Agent.Runner.execute/4`.

#### 4. Directive handling

- Keep `Jido.Agent.Directive` as-is but ensure it only depends on `%Jido.Agent{}` and not on agent modules or server state.
- Potentially add small helpers for applying directives to the new struct.

#### 5. OTP / GenServer integration

- `Jido.Agent.Server` remains the process wrapper.
- Introduce or refine a **separate behaviour** for server lifecycle:
  - e.g., `Jido.Agent.ServerBehaviour` with `mount/2`, `shutdown/2`, `handle_signal/2`, `transform_result/3`, `code_change/3`.
- Server state struct (`Jido.Agent.Server.State`) encapsulates:
  - `%Jido.Agent{}` value
  - Pending instruction queue (if you decide to keep queue semantics **at server level**)
  - Any server-only flags.
- `Jido.Agent` (core) no longer knows about `Jido.Agent.Server.*`.

**Effort**: L (1–2 days) – mostly mechanical extractions plus some wiring.

---

### 3.5 Essence of an Agent in v2

Conceptually:

- **State holder**: `%Jido.Agent{state: ..., result: ..., actions: ...}`.
- **Executor**:
  ```elixir
  execute(agent, instructions, opts) :: {:ok, new_agent, directives} | {:error, error}
  ```
  where `new_agent` is purely derived from:
  - the initial agent
  - the Actions executed
  - the Directives produced

No queues, no servers, no side effects in the core representation.

If higher-level orchestration is needed (multi-step workflows, concurrency, dynamic planning), it is built **on top of** this core, e.g.:

- `Jido.Agent.Workflow` for multi-step execution plans.
- `Jido.Agent.Server` for process-based, long-lived agents.

---

## 4. Migration Plan from Current Jido.Agent

### 4.1 API Mapping: Old -> New

| Current                        | v2 Core Equivalent                                  | Notes |
|--------------------------------|-----------------------------------------------------|-------|
| `use Jido.Agent, ...`         | `use Jido.Agent, ...` (rewritten to use Zoi)       | Config schema changes but options mostly same. |
| `typedstruct` Agent fields    | Zoi `@schema` in `Jido.Agent`                      | Fields trimmed to essence (no queue, etc.). |
| `new/0,1,2`                   | `Jido.Agent.new/1` + module-specific wrapper       | Provide `MyAgent.new/1` to preserve ergonomics. |
| `set/3`                       | `Jido.Agent.set_state/3`                           | Keep name `set/3` as wrapper in `use` macro for compatibility. |
| `validate/2`                  | `Jido.Agent.validate_state/2`                      | Under the hood, use shared schema helpers. |
| `plan/3`                      | **Deprecated**; replaced by `execute/3` or `Workflow` | Optionally keep as alias that just calls `execute/3`. |
| `run/2`                       | **Deprecated**; `execute/3` with previously planned steps | In v2, single-phase `execute/3` is primary. |
| `cmd/4`                       | `execute/3` + explicit `set_state/3` in user code  | Provide a thin compatibility wrapper initially. |
| `pending_instructions` field  | Move to `Jido.Agent.Server.State` only             | Not present in core struct. |
| `dirty_state?`                | Optional; can be dropped or tracked by caller      | If absolutely needed, keep as a flag in core struct. |
| Lifecycle hooks (on_before_*) | `before_execute/3`, `after_execute/4`, `on_error/4` | All others removed or emulated via these. |
| Server lifecycle hooks        | New `Jido.Agent.ServerBehaviour` only              | Not part of core Agent behaviour. |

### 4.2 Refactor Phases

#### Phase 1: Introduce Core Zoi Struct & Config (no functional change)

**Scope**: L (1–2 days)

Steps:

1. Create `Jido.Agent` Zoi struct as in 3.1 (can initially still include `pending_instructions`/`dirty_state?` to ease migration).
2. Replace `TypedStruct` in current agent module with the Zoi pattern:
   - Add `@schema`, `@type t`, `@enforce_keys`, `defstruct`, `schema/0`.
   - Adjust any code that referenced the old `typedstruct` macros if needed.
3. Introduce `@agent_config_schema` (Zoi.object) and update `__using__/1` to:
   - Use `Zoi.validate/2` (or helper) instead of NimbleOptions.validate for compile-time options.
   - Keep **runtime** state validation unchanged for now (still NimbleOptions) to reduce risk.

**Result**: Struct & config are Zoi-based, but behaviour and APIs are still essentially v1.

#### Phase 2: Extract Pure Functions & Runner

**Scope**: L (1–2 days)

Steps:

1. Create `Jido.Agent.Runner` module:
   - Move logic from `plan/3`, `run_single_instruction/2`, `execute_instruction/2`, `handle_directive_result/4` into pure functions that:
     - Take `%Jido.Agent{}` and `[%Instruction{}]`,
     - Call `Jido.Exec.run/1`,
     - Apply directives via `Jido.Agent.Directive`.
2. Introduce `Jido.Agent.execute/3`:
   - Around `Jido.Agent.Runner.execute/4`.
   - For now, `execute/3` can internally simulate the old queue semantics while we still have `pending_instructions` in the struct.

3. Update macro-generated `plan/3`, `run/2`, `cmd/4` to delegate through the new `execute/3` where possible:
   - `cmd/4` becomes boilerplate:
     ```elixir
     def cmd(agent, instructions, attrs, opts) do
       with {:ok, agent} <- set(agent, attrs, strict_validation: strict?),
            {:ok, agent, directives} <- Jido.Agent.execute(agent, instructions, opts) do
         {:ok, agent, directives}
       else
         {:error, reason} -> on_error(agent, reason)
       end
     end
     ```
   - `plan/3` and `run/2` can be expressed as special cases or temporarily left as-is but marked for deprecation.

**Result**: Execution semantics are centralized and can be reasoned about independently of GenServer.

#### Phase 3: Separate OTP & Server Concerns

**Scope**: L (1–2 days)

Steps:

1. Identify all references to `Jido.Agent.Server`, `ServerSignal`, `ServerState`, and `GenServer` in the current `__using__/1` body.
2. Move these into:
   - `Jido.Agent.ServerBehaviour` (for lifecycle hooks).
   - `Jido.Agent.Server` (implementation) using `%Jido.Agent{}` values as its payload.
   - Ensure server state struct owns:
     - Queue of pending instructions (if kept).
     - Any server-only flags.
3. Update `use Jido.Agent` macro to:
   - Not `use GenServer` directly.
   - Optionally provide a `child_spec/1` & `start_link/1` in a **dedicated** server wrapper module rather than on the agent module itself.
   - Or keep a `use Jido.Agent.Server, agent: __MODULE__` pattern for those who want process-based agents.

**Result**: Core Agent modules are plain data and pure functions; OTP/GenServer aspects are clearly separated.

#### Phase 4: Simplify Lifecycle Hooks

**Scope**: M (1–3h)

Steps:

1. Replace existing Agent callbacks with the minimal v2 set:
   - `before_execute/3`
   - `after_execute/4`
   - `on_error/4`
2. Provide default implementations in `use Jido.Agent`.
3. Mark old hooks (`on_before_validate_state`, `on_after_validate_state`, `on_before_plan`, `on_before_run`, `on_after_run`, `on_error/2`) as **deprecated** and internally forward them to the new hooks where feasible:
   - E.g., `on_before_run/1` can be proxied from `before_execute/3` when `instructions` is non-empty.
4. For server hooks, move them into `Jido.Agent.ServerBehaviour` and remove them from the core Agent behaviour.

**Result**: A small, consistent surface for customization.

#### Phase 5: Deprecate Queue-centric API & Introduce v2 API

**Scope**: M–L (1–2 days depending on appetite for breaking changes)

Steps:

1. Officially document v2 API as:
   - `new/1`
   - `set_state/3`
   - `validate_state/2`
   - `execute/3`
2. Mark `plan/3`, `run/2`, and `cmd/4` as deprecated in docs and via `@deprecated` attributes, pointing to `execute/3` + explicit state management.
3. Optionally introduce a small `Jido.Agent.Workflow` helper for those who really want explicit "planning":
   - But implemented purely as `Jido.Agent.execute/3` over sequences, not as an internal queue.

**Result**: Users are guided to the simpler FP core, while legacy APIs continue to work for a transition period.

---

## 5. Risks and Guardrails

### Key Risks

1. **Breaking changes for existing agents**
   - Macro semantics, callbacks, and struct fields will change.
   - Mitigation: keep a deprecation shim layer and phased migration; keep `pending_instructions`/`dirty_state?` in core struct until late in the migration.

2. **Subtle execution semantics changes**
   - Transition from queue-based `plan/run` to list-based `execute` might alter ordering or error-handling semantics.
   - Mitigation: write regression tests around existing behaviour beforehand (especially directives + errors) and ensure `execute/3` faithfully reproduces them in v2.

3. **Interop with Jido.Exec & Directives**
   - `Jido.Exec.run/1` signature and expected return types must be honoured.
   - Mitigation: centralize all usage of `Jido.Exec` in `Jido.Agent.Runner` and maintain tight tests.

4. **Migration of NimbleOptions to Zoi at runtime**
   - Attempting to replace all state schemas with Zoi immediately could be noisy.
   - Mitigation: keep `state_schema` as `Zoi.any/1` and support both NimbleOptions & Zoi via a helper (mirroring `Jido.Action.Schema`).

### Guardrails

- Keep **v1 behaviour** intact until all v2 pieces exist and are well-tested.
- Introduce v2 modules (`Jido.Agent.Runner`, `Jido.Agent.ServerBehaviour`, etc.) **before** deleting any v1 logic.
- Add explicit `@deprecated` annotations with clear messages and doc examples.
- Add property/behavioural tests for:
  - Execution order
  - Error propagation
  - Directive application semantics.

---

## 6. When to Consider the Advanced Path

You should revisit the design and consider a more advanced architecture if:

1. **Agents need multi-step, dynamic workflows with branching and compensation** that are too complex for simple `execute/3` compositions.
2. **You want built-in distributed orchestration** (agents spanning nodes, durable queues, backpressure).
3. **You need pluggable persistence of agent state** (e.g., snapshots in DB, event sourcing).
4. **You want first-class AI agent functionality** (e.g., tight integration with tool-calling Actions, planning loops, observability).

At those points, you might introduce:

- A higher-level `Jido.Agent.Orchestrator` or `Jido.Workflow` engine on top of v2 core.
- Persistent runner implementations (`Jido.Agent.DBServer`).
- Richer monitoring and tracing hooks.

---

## 7. Optional Advanced Path (Outline Only)

If/when you outgrow the simple v2 core:

### Workflow DSL

A separate `Jido.Workflow` defining declarative plans (`steps`, `conditions`, `retries`) referencing Actions and Agents. Agents become simple executors of workflow steps.

### Persistent Agents

Introduce a `Jido.Agent.Store` behaviour for plugging in storage backends (ETS, DB, Redis). `Jido.Agent.Server` persists `%Jido.Agent{}` via that behaviour.

### AI Tooling Integration

Leverage `Jido.Action.to_tool/0` and agent metadata to auto-generate tool schemas for LLM agents. Keep this layer entirely outside the v2 core (pure consumer of `Jido.Agent` and `Jido.Action`).

These advanced pieces should always build on top of the **simple, pure FP core** defined in this plan.

---

## 8. Effort Summary

| Phase | Description | Effort |
|-------|-------------|--------|
| Phase 1 | Zoi struct & config | L (1–2 days) |
| Phase 2 | Runner + execute/3 | L (1–2 days) |
| Phase 3 | OTP separation | L (1–2 days) |
| Phase 4 | Hooks simplification | M (1–3h) |
| Phase 5 | API deprecation & docs | M–L (0.5–1d) |

This is a manageable refactor spread over a few focused iterations, leading to a much clearer and more functional Jido.Agent core.

---

## 9. Quick Reference: v2 Core API

```elixir
# Core struct
%Jido.Agent2{
  id: "agent_123",
  name: "my_agent",
  schema: [...],  # NimbleOptions or Zoi
  actions: [Action1, Action2],
  state: %{},
  result: nil
}

# Construction
agent = MyAgent.new()
agent = MyAgent.new(id: "custom-id", state: %{counter: 10})

# State updates
{:ok, agent} = MyAgent.set(agent, %{key: "value"})

# Validation
{:ok, agent} = MyAgent.validate(agent)
{:ok, agent} = MyAgent.validate(agent, strict: true)

# Execution (the core primitive)
{:ok, agent, directives} = MyAgent.cmd(agent, MyAction)
{:ok, agent, directives} = MyAgent.cmd(agent, {MyAction, %{param: 1}})
{:ok, agent, directives} = MyAgent.cmd(agent, [Action1, Action2], context: %{user_id: 1})

# Callbacks (minimal set)
@callback before_cmd(agent, instructions, context) :: {:ok, agent, instructions, context} | {:error, term()}
@callback after_cmd(agent, result, directives, context) :: {:ok, agent} | {:error, term()}
@callback on_error(agent, error, phase, context) :: {:ok, agent} | {:error, term()}
```

---

## 10. Implementation Notes (Completed)

The v2 implementation is now available as `Jido.Agent2` for comparison with the original `Jido.Agent`.

### Files Created

| File | Purpose |
|------|---------|
| `lib/jido/agent2.ex` | Core Agent2 module with Zoi struct and `use` macro |
| `lib/jido/agent2/state.ex` | Internal state management helper (hidden) |
| `lib/jido/runner.ex` | Pure functional execution engine |
| `test/jido/agent2_test.exs` | Comprehensive test suite (27 tests) |

### Key Differences from v1

| Aspect | v1 (`Jido.Agent`) | v2 (`Jido.Agent2`) |
|--------|-------------------|---------------------|
| Struct definition | TypedStruct + NimbleOptions | Zoi.struct |
| Config validation | NimbleOptions | Zoi.object |
| Core API | `set/3`, `plan/3`, `run/2`, `cmd/4` | `new/1`, `set/2`, `validate/2`, `cmd/3` |
| Lifecycle hooks | 6+ callbacks | 3 callbacks |
| Instruction queue | Built into struct | Not present |
| GenServer | Mixed into agent module | Separate (`Jido.AgentServer`) |
| Lines of code | ~1400 | ~350 |

### Usage Example

```elixir
defmodule MyAgent do
  use Jido.Agent2,
    name: "my_agent",
    description: "Example agent",
    actions: [MyAction1, MyAction2],
    schema: [
      counter: [type: :integer, default: 0],
      status: [type: :atom, default: :idle]
    ]

  # Optional: customize hooks
  def before_cmd(agent, instructions, context) do
    IO.puts("About to execute #{length(instructions)} instructions")
    {:ok, agent, instructions, context}
  end
end

# Usage
agent = MyAgent.new()
{:ok, agent} = MyAgent.set(agent, %{counter: 5})
{:ok, agent, _directives} = MyAgent.cmd(agent, {MyAction1, %{value: 42}})
```

### Migration Path

To migrate from `Jido.Agent` to `Jido.Agent2`:

1. Change `use Jido.Agent` to `use Jido.Agent2`
2. Keep `schema:` option (same name as before)
3. Replace `set/3` calls with `set/2` (remove opts argument)
4. Replace `plan/3` + `run/2` with single `cmd/3` call
5. Update lifecycle hooks to new signatures
6. Remove any references to `pending_instructions` or `dirty_state?`

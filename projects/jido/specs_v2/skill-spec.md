# Jido 2.0 Skills Specification

> Skills are pluggable, pure, capability bundles for agents.
> They package Actions, optional signal handlers, and LLM tools into a reusable unit.

---

## 1. Overview

Skills are Jido's **plugin system**.

A Skill is a **named, versioned bundle of Actions and instructions** that can be mounted on any Agent to extend its capabilities. Skills are:

- **Pure and declarative**: a Skill module declares metadata, Zoi schemas, and pure helper functions
- **Action-centric**: Skills expose capabilities exclusively via `Jido.Action` modules
- **Effect-driven**: Mounting/unmounting a Skill is expressed as Effects (`Effect.RegisterAction` / `Effect.DeregisterAction`)
- **LLM-ready**: Skills generate LLM Tool descriptions for all bundled Actions
- **Pluggable**: Agents can dynamically mount/dismount Skills at runtime using Effects

Conceptually:

- **Agents think:** decide *which Skills should be active* and *when to delegate signals to them*
- **Skills describe capabilities:** which Actions, tools, and default signal handling they provide
- **AgentServer acts:** interprets Effects emitted by Agents and Skills, registering/deregistering actions and executing work

---

## 2. Goals & Non-Goals

### 2.1 Goals

| Goal | Description |
|------|-------------|
| Plugin abstraction | First-class mechanism for grouping related Actions into reusable units |
| Dynamic capabilities | Agents can gain/lose Skills at runtime via Effects |
| Default signal handling | Skills can package signal handlers for common patterns |
| Pure and testable | Skills never perform I/O directly |
| Clean integration | Works with Zoi validation, Effect orchestration, Tool generation, and existing Runners |

### 2.2 Non-Goals

| Non-Goal | Rationale |
|----------|-----------|
| New processes/supervisors | Skills are data modules, not runtime entities |
| Bypass Effect system | All work is expressed via Effects |
| Replace Agents/Runners | Skills are capability plugins, not decision engines |

---

## 3. Core Concepts

### 3.1 What is a Skill?

A **Skill** is a module implementing the `Jido.Skill` behaviour:

- Identified by an `id/0` (typically an atom)
- Described by `name/0`, `description/0`, `vsn/0`
- Bundles a list of **Action modules** via `actions/0`
- Optionally provides:
  - A **per-agent skill state schema** via `schema/0` (Zoi)
  - An **initial state** via `initial_state/0`
  - **Default signal handling** via `handle_signal/3`
  - **LLM instructions and tool descriptors** via `instructions/0` and `tools/0`
  - **Dependencies** on other Skills via `requires/0`

Skills are **agent-agnostic**. They can be mounted on any Agent whose runner chooses to use them.

### 3.2 Skill State

Each Agent instance may hold per-skill state, stored under a conventionally reserved field:

```elixir
%MyAgent{
  # Domain state...
  status: :idle,
  
  # Per-skill state
  skills: %{
    :arithmetic => %{},
    :search     => %{api_key: "...", last_query: nil}
  }
}
```

- Each skill's state is validated by the Skill's own Zoi schema
- All skill state lives **inside the Agent's state struct**—no hidden process state

### 3.3 Mounting a Skill

Mounting a Skill on an Agent instance is a **pure operation** that:

1. Validates/initializes per-skill state
2. Returns a **new agent state** with the Skill described in `state.skills`
3. Emits Effects (primarily `Effect.RegisterAction`) for each bundled Action

The Agent (via its runner) decides *when* to mount/unmount a Skill; AgentServer executes the resulting Effects.

---

## 4. Type Definitions

### 4.1 Skill Struct

```elixir
defmodule Jido.Skill do
  @type id :: atom() | String.t()

  @typedoc "Opaque per-skill state stored under agent.state.skills[id]"
  @type state :: map()

  @typedoc "LLM-facing tool description (OpenAI-style JSON)"
  @type tool_description :: map()

  @typedoc "Static metadata about a Skill"
  @type spec :: %{
    id: id(),
    name: String.t(),
    description: String.t(),
    vsn: String.t(),
    category: String.t() | nil,
    tags: [String.t()],
    actions: [module()],
    instructions: String.t() | nil,
    dependencies: [id()]
  }
end
```

### 4.2 Skill Behaviour

```elixir
defmodule Jido.Skill do
  @moduledoc "Behaviour for Jido Skills (capability plugins)."

  # ─────────────────────────────────────────────────────────────
  # Required Callbacks
  # ─────────────────────────────────────────────────────────────

  @doc "Unique identifier for this Skill"
  @callback id() :: id()

  @doc "Human-readable name"
  @callback name() :: String.t()

  @doc "Description of what this Skill provides"
  @callback description() :: String.t()

  @doc "Semantic version string"
  @callback vsn() :: String.t()

  @doc """
  List of Action modules this Skill provides.
  All modules MUST implement `Jido.Action`.
  """
  @callback actions() :: [module()]

  @doc """
  Zoi schema for per-agent skill state.
  Defines what is stored under `agent.state.skills[id]`.
  """
  @callback schema() :: Zoi.schema()

  @doc """
  Initial skill state for a freshly-mounted skill.
  Called with optional mount options (e.g. config overrides).
  """
  @callback initial_state(opts :: map()) :: state()

  # ─────────────────────────────────────────────────────────────
  # Optional Callbacks
  # ─────────────────────────────────────────────────────────────

  @doc "Category for UI/organization (e.g. \"math\", \"search\")"
  @callback category() :: String.t() | nil

  @doc "Tags for search/filtering (e.g. [\"llm\", \"math\"])"
  @callback tags() :: [String.t()]

  @doc "Documentation/instructions for LLMs and UIs"
  @callback instructions() :: String.t()

  @doc "Required Skill IDs that MUST be mounted before this Skill"
  @callback requires() :: [id()]

  @doc """
  LLM tool descriptions; default derives from Actions.
  Each tool is a JSON-serializable map.
  """
  @callback tools() :: [tool_description()]

  @doc """
  Optional default signal handler for this Skill.

  - `skill_state` is current value under agent.state.skills[id]
  - `signal` is any Jido.Signal
  - `context` is a pure data map with keys:
    * :agent_module - agent module
    * :agent_id     - agent instance id
    * :skill_id     - this skill's id

  Returns:
  - `{:ok, new_skill_state, effects}` if handled
  - `:ignore` if Skill does not handle this signal
  """
  @callback handle_signal(
    skill_state :: state(),
    signal :: Jido.Signal.t(),
    context :: map()
  ) ::
    {:ok, new_skill_state :: state(), [Jido.Agent.Effect.t()]}
    | :ignore

  @optional_callbacks [
    category: 0,
    tags: 0,
    instructions: 0,
    requires: 0,
    tools: 0,
    handle_signal: 3
  ]
end
```

---

## 5. Skill Helper API

The `Jido.Skill` module exposes pure helper functions for mounting/unmounting skills.

### 5.1 Mount

```elixir
@doc """
Mount a Skill on an Agent instance.

- Validates or initializes per-skill state
- Ensures required Skills are already mounted
- Returns new agent state and Effects to register Actions

Pure: safe to call from inside Agent.handle_signal/2.
"""
@spec mount(
  agent_state :: struct(),
  skill_module :: module(),
  opts :: map()
) ::
  {:ok, new_agent_state :: struct(), effects :: [Effect.t()]}
  | {:error, term()}
```

**Mount semantics:**

1. Check if skill is already mounted → idempotently succeed with no-op Effects
2. If not mounted:
   - Check dependencies from `skill.requires/0` are satisfied
   - Compute skill state:
     - If existing state under `state.skills[id]`, validate against `schema/0`
     - Otherwise, call `initial_state(opts)` and validate
   - Insert into `agent_state.skills`
   - Generate `Effect.RegisterAction` per action in `actions/0`:

```elixir
%Effect.RegisterAction{
  action: MySkill.Add,
  meta: %Effect.Meta{tags: [:skill], skill: skill_module.id()}
}
```

3. Return `{:ok, new_agent_state, register_effects}`

### 5.2 Unmount

```elixir
@doc """
Unmount a Skill from an Agent instance.

- Removes per-skill state from agent.state.skills[id]
- Emits Effects to deregister the Skill's Actions

Pure: safe to call from inside Agent.handle_signal/2.
"""
@spec unmount(
  agent_state :: struct(),
  skill_module :: module()
) ::
  {:ok, new_agent_state :: struct(), effects :: [Effect.t()]}
  | {:error, term()}
```

**Unmount semantics:**

1. If not mounted → return `{:ok, agent_state, []}`
2. Remove `state.skills[id]`
3. Emit `Effect.DeregisterAction` per `actions/0`
4. Return `{:ok, new_agent_state, deregister_effects}`

### 5.3 Tool Aggregation

```elixir
@doc """
Aggregate tools for all currently-mounted Skills on an agent.
Uses Skill.tools/0 or derives tools from actions().
"""
@spec tools_for_agent(agent_state :: struct()) :: [tool_description()]
```

**Usage:** LLM runners call `tools_for_agent/1` to build the `tools` list for LLM Actions.

### 5.4 Introspection

```elixir
@doc "Get metadata for a mounted Skill"
@spec get_spec(skill_module :: module()) :: spec()

@doc "List all mounted Skills on an agent"
@spec mounted_skills(agent_state :: struct()) :: [id()]

@doc "Check if a specific Skill is mounted"
@spec mounted?(agent_state :: struct(), skill_id :: id()) :: boolean()
```

---

## 6. Agent Integration

### 6.1 Agent State Shape

Agents using Skills should reserve a `skills` map:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    runner: :react,
    schema: %{
      # Domain state
      status: Zoi.atom() |> Zoi.default(:idle),
      
      # Reserved: skill-local state
      skills: Zoi.map() |> Zoi.default(%{}),
      
      # Runner state
      runner: Zoi.map() |> Zoi.default(%{})
    }
end
```

### 6.2 Mounting Skills in Agents

Agents mount Skills inside `handle_signal/2`:

```elixir
def handle_signal(state, %Jido.Signal{type: :init}) do
  with {:ok, state1, effects} <- Jido.Skill.mount(state, Jido.Skills.Arithmetic, %{}) do
    {:ok, state1, effects}
  end
end
```

AgentServer interprets the returned Effects and registers all Skill Actions.

### 6.3 Dynamic Enable/Disable

```elixir
def handle_signal(state, %Signal{type: :enable_skill, data: %{skill: skill_mod}}) do
  Jido.Skill.mount(state, skill_mod, %{})
end

def handle_signal(state, %Signal{type: :disable_skill, data: %{skill: skill_mod}}) do
  Jido.Skill.unmount(state, skill_mod)
end
```

### 6.4 Delegating Signals to Skills

Agents or Runners may delegate signals to Skills with `handle_signal/3`:

```elixir
defp delegate_to_skills(agent_module, state, signal) do
  Enum.reduce_while(state.skills, {:ok, state, []}, fn {skill_id, skill_state},
                                                        {:ok, acc_state, acc_effects} ->
    skill_mod = Jido.SkillRegistry.fetch!(skill_id)

    case skill_mod.handle_signal(skill_state, signal, %{
           agent_module: agent_module,
           agent_id: acc_state.id,
           skill_id: skill_id
         }) do
      :ignore ->
        {:cont, {:ok, acc_state, acc_effects}}

      {:ok, new_skill_state, skill_effects} ->
        new_state = put_in(acc_state.skills[skill_id], new_skill_state)
        {:halt, {:ok, new_state, acc_effects ++ skill_effects}}
    end
  end)
end
```

**Notes:**

- Delegation is **opt-in**: runners decide which signals to pass to which Skills
- Skills stay pure: they see `skill_state`, `signal`, and a pure `context` map

### 6.5 LLM Tool Integration

LLM runners use `tools_for_agent/1` for their toolset:

```elixir
tools = Jido.Skill.tools_for_agent(state)

effects = [
  %Effect.Run{
    action: Jido.Actions.LLM.Chat,
    params: %{
      model: "gpt-4",
      messages: transcript,
      tools: tools
    }
  }
]
```

---

## 7. Effect Semantics

Skills participate in the Effect system indirectly—they do not define new Effect types.

### 7.1 Register/Deregister Actions

Mounting/unmounting results in:

```elixir
# Mount
%Effect.RegisterAction{
  action: MySkill.Add,
  meta: %Effect.Meta{tags: [:skill], skill: :arithmetic}
}

# Unmount
%Effect.DeregisterAction{
  action: MySkill.Add,
  meta: %Effect.Meta{tags: [:skill], skill: :arithmetic}
}
```

### 7.2 Running Actions

When a Skill's `handle_signal/3` wants to perform work:

```elixir
%Effect.Run{
  action: Jido.Skills.Arithmetic.Add,
  params: %{a: 1, b: 2},
  meta: %Effect.Meta{skill: :arithmetic}
}
```

### 7.3 No New Core Effects

The kernel does **not** introduce `Effect.RegisterSkill` or `Effect.DeregisterSkill`:

- **Mounting** = update agent state + emit `RegisterAction` effects
- **Unmounting** = update agent state + emit `DeregisterAction` effects

This keeps the Effect vocabulary small and action-focused.

---

## 8. Skill Lifecycle

### 8.1 Package-Level

| Phase | Description |
|-------|-------------|
| Install | Add Skill library to codebase/deps |
| Uninstall | Remove dependency |

No runtime semantics—Skills are just modules.

### 8.2 Per-Agent Lifecycle

```
┌─────────────┐     mount/3     ┌────────────┐
│   Inactive  │ ──────────────► │   Active   │
│ (not mounted)│                │  (mounted) │
└─────────────┘ ◄────────────── └────────────┘
                   unmount/2
```

| State | Description |
|-------|-------------|
| **Inactive** | No per-skill state in `skills[id]`, no actions registered |
| **Active** | Skill state present, Actions registered, `handle_signal/3` eligible |

**Transitions are pure:**

- `mount/3` → Inactive → Active (+ `RegisterAction` Effects)
- `unmount/2` → Active → Inactive (+ `DeregisterAction` Effects)

---

## 9. Skill Dependencies

Skills declare dependencies via `requires/0`:

```elixir
@impl true
def requires do
  [:http_client, :auth]
end
```

**Semantics:**

- `mount/3` checks that all required skills are already mounted
- If missing: `{:error, {:missing_dependency, required_id}}`
- Runners may implement auto-resolution (topological sort) as a battery

---

## 10. Canonical Example: Arithmetic Skill

### 10.1 Actions

```elixir
defmodule Jido.Skills.Arithmetic.Add do
  use Jido.Action,
    name: "add",
    description: "Add two numbers"

  def schema do
    %{
      a: Zoi.number(),
      b: Zoi.number()
    }
  end

  def run(%{a: a, b: b}, _ctx) do
    {:ok, %{result: a + b}}
  end
end

defmodule Jido.Skills.Arithmetic.Subtract do
  use Jido.Action,
    name: "subtract",
    description: "Subtract two numbers (a - b)"

  def schema do
    %{a: Zoi.number(), b: Zoi.number()}
  end

  def run(%{a: a, b: b}, _ctx) do
    {:ok, %{result: a - b}}
  end
end

defmodule Jido.Skills.Arithmetic.Multiply do
  use Jido.Action,
    name: "multiply",
    description: "Multiply two numbers"

  def schema do
    %{a: Zoi.number(), b: Zoi.number()}
  end

  def run(%{a: a, b: b}, _ctx) do
    {:ok, %{result: a * b}}
  end
end

defmodule Jido.Skills.Arithmetic.Divide do
  use Jido.Action,
    name: "divide",
    description: "Divide two numbers (a / b)"

  def schema do
    %{a: Zoi.number(), b: Zoi.number()}
  end

  def run(%{a: a, b: b}, _ctx) do
    if b == 0 do
      {:error, :division_by_zero}
    else
      {:ok, %{result: a / b}}
    end
  end
end
```

### 10.2 Skill Module

```elixir
defmodule Jido.Skills.Arithmetic do
  @behaviour Jido.Skill

  alias Jido.Agent.Effect
  alias Jido.Signal

  # ─────────────────────────────────────────────────────────────
  # Required Callbacks
  # ─────────────────────────────────────────────────────────────

  @impl true
  def id, do: :arithmetic

  @impl true
  def name, do: "Arithmetic"

  @impl true
  def description do
    "Basic arithmetic operations: add, subtract, multiply, divide."
  end

  @impl true
  def vsn, do: "1.0.0"

  @impl true
  def actions do
    [
      Jido.Skills.Arithmetic.Add,
      Jido.Skills.Arithmetic.Subtract,
      Jido.Skills.Arithmetic.Multiply,
      Jido.Skills.Arithmetic.Divide
    ]
  end

  @impl true
  def schema, do: %{}

  @impl true
  def initial_state(_opts), do: %{}

  # ─────────────────────────────────────────────────────────────
  # Optional Callbacks
  # ─────────────────────────────────────────────────────────────

  @impl true
  def category, do: "math"

  @impl true
  def tags, do: ["math", "arithmetic", "numeric"]

  @impl true
  def requires, do: []

  @impl true
  def instructions do
    """
    The Arithmetic skill provides tools for basic numeric operations:

    - add(a, b):      returns a + b
    - subtract(a, b): returns a - b
    - multiply(a, b): returns a * b
    - divide(a, b):   returns a / b (b must not be 0)

    Use these tools whenever you need to compute numeric results.
    Prefer exact arithmetic over approximate reasoning.
    """
  end

  @impl true
  def tools do
    actions()
    |> Enum.map(&Jido.Tool.from_action/1)
  end

  @impl true
  def handle_signal(skill_state, %Signal{type: :calculate, data: data}, _ctx) do
    with {:ok, action_mod} <- resolve_action(data[:op]),
         params <- Map.take(data, [:a, :b]) do
      effects = [
        %Effect.Run{
          action: action_mod,
          params: params,
          meta: %Effect.Meta{tags: [:skill], skill: :arithmetic}
        }
      ]

      {:ok, skill_state, effects}
    else
      :error -> :ignore
    end
  end

  def handle_signal(_skill_state, _signal, _ctx), do: :ignore

  # ─────────────────────────────────────────────────────────────
  # Private Helpers
  # ─────────────────────────────────────────────────────────────

  defp resolve_action(op) do
    case op do
      :add -> {:ok, Jido.Skills.Arithmetic.Add}
      :subtract -> {:ok, Jido.Skills.Arithmetic.Subtract}
      :multiply -> {:ok, Jido.Skills.Arithmetic.Multiply}
      :divide -> {:ok, Jido.Skills.Arithmetic.Divide}
      _ -> :error
    end
  end
end
```

### 10.3 Agent Using the Skill

```elixir
defmodule CalculatorAgent do
  use Jido.Agent,
    name: "calculator",
    runner: :react,
    schema: %{
      skills: Zoi.map() |> Zoi.default(%{}),
      runner: Zoi.map() |> Zoi.default(%{mode: :idle, transcript: []})
    }

  @impl true
  def handle_signal(state, %Jido.Signal{type: :init}) do
    # Mount Arithmetic skill on init
    Jido.Skill.mount(state, Jido.Skills.Arithmetic, %{})
  end

  @impl true
  def handle_signal(state, %Jido.Signal{type: :calculate} = signal) do
    # Delegate to Arithmetic skill
    case Jido.Skills.Arithmetic.handle_signal(
           state.skills[:arithmetic] || %{},
           signal,
           %{agent_module: __MODULE__, agent_id: state.id, skill_id: :arithmetic}
         ) do
      :ignore ->
        {:ok, state, []}

      {:ok, new_skill_state, effects} ->
        new_state = put_in(state.skills[:arithmetic], new_skill_state)
        {:ok, new_state, effects}
    end
  end
end
```

---

## 11. Testing Skills

### 11.1 Unit Testing Signal Handling

```elixir
test "Arithmetic skill emits Add action on :calculate add" do
  skill_state = %{}
  signal = %Jido.Signal{type: :calculate, data: %{op: :add, a: 1, b: 2}}

  {:ok, new_state, effects} =
    Jido.Skills.Arithmetic.handle_signal(skill_state, signal, %{})

  assert new_state == %{}
  assert [%Effect.Run{action: Jido.Skills.Arithmetic.Add, params: %{a: 1, b: 2}}] = effects
end

test "Arithmetic skill ignores unknown operations" do
  signal = %Jido.Signal{type: :calculate, data: %{op: :modulo, a: 5, b: 3}}

  assert :ignore = Jido.Skills.Arithmetic.handle_signal(%{}, signal, %{})
end
```

### 11.2 Testing Mount/Unmount

```elixir
test "mounting Arithmetic registers its actions" do
  state = %CalculatorAgent{id: "test-1", skills: %{}}

  {:ok, new_state, effects} = Jido.Skill.mount(state, Jido.Skills.Arithmetic, %{})

  assert Map.has_key?(new_state.skills, :arithmetic)
  assert length(effects) == 4  # 4 actions
  assert Enum.all?(effects, &match?(%Effect.RegisterAction{}, &1))
end

test "unmounting Arithmetic deregisters its actions" do
  state = %CalculatorAgent{id: "test-1", skills: %{arithmetic: %{}}}

  {:ok, new_state, effects} = Jido.Skill.unmount(state, Jido.Skills.Arithmetic)

  refute Map.has_key?(new_state.skills, :arithmetic)
  assert Enum.all?(effects, &match?(%Effect.DeregisterAction{}, &1))
end

test "mounting already-mounted skill is idempotent" do
  state = %CalculatorAgent{id: "test-1", skills: %{arithmetic: %{}}}

  {:ok, ^state, []} = Jido.Skill.mount(state, Jido.Skills.Arithmetic, %{})
end
```

### 11.3 Testing Action Execution

```elixir
test "Add action computes sum" do
  {:ok, result} = Jido.Skills.Arithmetic.Add.run(%{a: 2, b: 3}, %{})
  assert result == %{result: 5}
end

test "Divide action rejects division by zero" do
  {:error, :division_by_zero} = Jido.Skills.Arithmetic.Divide.run(%{a: 10, b: 0}, %{})
end
```

---

## 12. Advanced Patterns

### 12.1 Skill with Internal State

```elixir
defmodule Jido.Skills.Counter do
  @behaviour Jido.Skill

  @impl true
  def id, do: :counter

  @impl true
  def schema do
    %{
      count: Zoi.integer() |> Zoi.default(0),
      step: Zoi.integer() |> Zoi.default(1)
    }
  end

  @impl true
  def initial_state(opts) do
    %{
      count: Map.get(opts, :initial, 0),
      step: Map.get(opts, :step, 1)
    }
  end

  @impl true
  def handle_signal(skill_state, %Signal{type: :increment}, _ctx) do
    new_count = skill_state.count + skill_state.step
    {:ok, %{skill_state | count: new_count}, []}
  end

  def handle_signal(skill_state, %Signal{type: :get_count}, ctx) do
    effects = [
      %Effect.Reply{
        to: ctx[:reply_to],
        signal: %Signal{type: :count_value, data: %{count: skill_state.count}}
      }
    ]
    {:ok, skill_state, effects}
  end

  def handle_signal(_skill_state, _signal, _ctx), do: :ignore

  # ... other callbacks
end
```

### 12.2 Skill with Dependencies

```elixir
defmodule Jido.Skills.AuthenticatedSearch do
  @behaviour Jido.Skill

  @impl true
  def requires, do: [:auth, :http_client]

  @impl true
  def actions do
    [Jido.Skills.AuthenticatedSearch.Query]
  end

  # ... other callbacks
end

# Usage: mount will fail if :auth or :http_client not already mounted
{:error, {:missing_dependency, :auth}} =
  Jido.Skill.mount(state, Jido.Skills.AuthenticatedSearch, %{})
```

### 12.3 Composing Multiple Skills

```elixir
def handle_signal(state, %Signal{type: :init}) do
  with {:ok, state1, eff1} <- Jido.Skill.mount(state, Jido.Skills.Arithmetic, %{}),
       {:ok, state2, eff2} <- Jido.Skill.mount(state1, Jido.Skills.DateTime, %{}),
       {:ok, state3, eff3} <- Jido.Skill.mount(state2, Jido.Skills.FileSystem, %{}) do
    {:ok, state3, eff1 ++ eff2 ++ eff3}
  end
end
```

---

## 13. `use Jido.Skill` Macro

For convenience, Skills can use a macro that provides defaults:

```elixir
defmodule Jido.Skills.Arithmetic do
  use Jido.Skill,
    id: :arithmetic,
    name: "Arithmetic",
    description: "Basic arithmetic operations",
    vsn: "1.0.0",
    category: "math",
    tags: ["math", "arithmetic"],
    actions: [
      Jido.Skills.Arithmetic.Add,
      Jido.Skills.Arithmetic.Subtract,
      Jido.Skills.Arithmetic.Multiply,
      Jido.Skills.Arithmetic.Divide
    ]

  # Override only what's needed
  @impl true
  def instructions do
    "Use add, subtract, multiply, divide for numeric operations."
  end

  @impl true
  def handle_signal(skill_state, signal, ctx) do
    # Custom signal handling
  end
end
```

The macro generates:
- Default implementations of all required callbacks
- `tools/0` that derives from `actions/0`
- Empty `schema/0` and `initial_state/1`
- `nil` for optional callbacks not provided

---

## 14. Kernel vs Battery

### Kernel

- `Jido.Skill` behaviour definition
- `mount/3`, `unmount/2` pure helpers
- `tools_for_agent/1` aggregation
- Basic validation integration

### Battery

- `use Jido.Skill` macro
- Skill registry for runtime lookup
- Dependency auto-resolution
- Workbench UI integration
- Skill versioning/hot-swap

---

## 15. Future Considerations

These extensions are **not in V2.0 scope** but inform the design:

| Extension | Description |
|-----------|-------------|
| Cross-agent Skills | Shared skill instances across agents |
| Remote Skills | Actions execute on other nodes/languages |
| Version negotiation | Hot-swap Skills with compatibility checks |
| Skill policies | Quotas, auth, rate limiting per skill |

The current design supports these as additive layers.

---

## 16. Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0.0-draft | Dec 2024 | Initial Skills specification |

---

*Specification Version: 2.0.0-draft*  
*Last Updated: December 2024*

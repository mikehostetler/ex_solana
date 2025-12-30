# Jido Skills v2 Design

> Compile-time, purely functional skill system for Jido Agents

## Overview

Skills bundle **pure metadata for the Agent** (actions, state schema, state_key) and **optional runtime hooks for AgentServer** (routing, lifecycle). The pure Agent API (`new/1`, `cmd/2`, `set/2`, `validate/2`) never depends on routes or signals.

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "math_agent",
    skills: [
      Jido.Skill.Calculator,
      {Jido.Skill.Stats, %{window: 100}}
    ]
end
```

## Design Principles

1. **Compile-time composition** — Skills are resolved when the agent module compiles
2. **Pure functional core** — `cmd/2` is unaffected by routes or signals
3. **State isolation** — Each skill gets its own namespace in agent state via `state_key`
4. **Hex-distributable** — Skills can live in external packages
5. **Zoi-only schemas** — All skill schemas use Zoi (no NimbleOptions)

---

## Layers and Separation of Concerns

Jido has two distinct layers:

### Pure Layer (compile-time + data only)

**Modules**: `Jido.Agent`, agent modules (`use Jido.Agent`), skill modules (`use Jido.Skill`)

**Responsibilities**:
- Define schemas (agent + skills)
- Define actions and `cmd/2` semantics
- Define skill metadata: `name`, `state_key`, `actions`, `schema`, `config_schema`
- Produce `Jido.Skill.Spec` structs at compile-time

**Key invariant**: No processes, no signals, no routing. `cmd/2` is pure and takes instructions/actions only.

### Process Layer (runtime + OTP integration)

**Modules**: `Jido.AgentServer`, runtimes built on it

**Responsibilities**:
- Own the Agent process and lifecycle
- Handle `Signal` ingress/egress
- Build routers from skills
- Invoke process-only skill callbacks: `mount/2`, `router/1`, `handle_signal/2`, `transform_result/3`, `child_spec/1`

**Key invariant**: This layer may deal with signals, routes, and processes; it never changes the semantics of `cmd/2`.

---

## What a Skill Bundles

| Component | Required | Layer | Description |
|-----------|----------|-------|-------------|
| `name` | ✓ | Pure | Machine-readable identifier (e.g., `"calculator"`) |
| `state_key` | ✓ | Pure | Atom key for isolated state namespace (e.g., `:calculator`) |
| `actions` | ✓ | Pure | List of action modules this skill provides |
| `schema` | | Pure | Zoi schema for skill's isolated state |
| `config_schema` | | Pure | Zoi schema for per-agent skill configuration |
| `description` | | Pure | Human description for docs/LLM tooling |
| `category` | | Pure | Skill category |
| `vsn` | | Pure | Semantic version string |
| `tags` | | Pure | Categorization tags |
| `signal_patterns` | | Process | Glob patterns for AgentServer signal matching |

---

## Core Data Structures

### Jido.Skill.Spec

The normalized representation of a skill attached to an agent:

```elixir
defmodule Jido.Skill.Spec do
  @type t :: %__MODULE__{
    module: module(),
    name: String.t(),
    state_key: atom(),
    description: String.t() | nil,
    category: String.t() | nil,
    vsn: String.t() | nil,
    schema: Zoi.t() | nil,
    config_schema: Zoi.t() | nil,
    config: map(),
    signal_patterns: [String.t()],
    tags: [String.t()],
    actions: [module()]
  }

  @enforce_keys [:module, :name, :state_key, :actions]
  defstruct [
    :module,
    :name,
    :state_key,
    :description,
    :category,
    :vsn,
    :schema,
    :config_schema,
    config: %{},
    signal_patterns: [],
    tags: [],
    actions: []
  ]
end
```

---

## Jido.Skill Behaviour & Callbacks

### Callback Placement

**Pure layer (used by Jido.Agent at compile-time / construction)**:
- `skill_spec/1` — Returns the skill's metadata and configuration

**Process layer (used only by Jido.AgentServer at runtime)**:
- `mount/2` — Transform/initialize Agent state for this process
- `router/1` — Define `Signal` → `Instruction` routes
- `handle_signal/2` — Pre-process incoming signals
- `transform_result/3` — Post-process action results into signals/output
- `child_spec/1` — Declare supervised children required by the skill

> **Important**: Pure code and `cmd/2` MUST NOT call the process callbacks.

### Behaviour Definition

```elixir
defmodule Jido.Skill do
  @moduledoc """
  A Skill has:

    * **Pure, compile-time spec** used by `Jido.Agent`:
      - `skill_spec/1` (required)

    * **Process-only callbacks** used by runtimes like `Jido.AgentServer`:
      - `mount/2`, `router/1`, `handle_signal/2`, `transform_result/3`, `child_spec/1`

  Pure Agents never call the process callbacks.
  """

  # Pure (compile-time / data only)
  @callback skill_spec(config :: map()) :: Jido.Skill.Spec.t()

  # Process-only (AgentServer / runtime)
  @callback mount(Agent.t(), map()) :: {:ok, Agent.t()} | {:error, term()}
  @callback router(map()) :: [Jido.Signal.Router.Route.t()]
  @callback handle_signal(Signal.t(), map()) :: {:ok, Signal.t()} | {:error, term()}
  @callback transform_result(Signal.t(), term(), map()) :: {:ok, term()} | {:error, term()}
  @callback child_spec(map()) :: [Supervisor.child_spec()]

  @optional_callbacks [mount: 2, router: 1, handle_signal: 2, transform_result: 3, child_spec: 1]
end
```

---

## Using the Macro

### Skill Definition

```elixir
defmodule Jido.Skill.Calculator do
  use Jido.Skill,
    name: "calculator",
    state_key: :calculator,
    description: "Basic arithmetic operations",
    category: "math",
    vsn: "0.1.0",
    schema: Zoi.object(%{
      precision: Zoi.integer() |> Zoi.default(2),
      last_result: Zoi.float() |> Zoi.default(0.0)
    }),
    config_schema: Zoi.object(%{
      max_value: Zoi.integer() |> Zoi.default(1_000_000)
    }),
    signal_patterns: ["calculator.*"],
    actions: [
      Jido.Skill.Calculator.Add,
      Jido.Skill.Calculator.Subtract,
      Jido.Skill.Calculator.Multiply
    ],
    tags: ["math", "utility"]

  # Process-only callbacks (used by AgentServer, not pure Agent)

  @impl true
  def router(_config) do
    [
      %Jido.Signal.Router.Route{
        path: "calculator.add",
        target: %Instruction{action: Jido.Skill.Calculator.Add}
      },
      %Jido.Signal.Router.Route{
        path: "calculator.subtract",
        target: %Instruction{action: Jido.Skill.Calculator.Subtract}
      }
    ]
  end

  @impl true
  def handle_signal(%Signal{} = signal, _config) do
    operation = signal.type |> String.split(".") |> List.last() |> String.to_atom()
    {:ok, %{signal | data: Map.put(signal.data, :operation, operation)}}
  end

  @impl true
  def transform_result(%Signal{} = signal, {:ok, result}, _config) do
    {:ok, %Signal{
      id: Jido.Util.generate_id(),
      source: signal.source,
      type: "calculator.result",
      data: result
    }}
  end
end
```

### Macro Implementation

```elixir
defmodule Jido.Skill do
  @skill_config_schema Zoi.object(%{
    name: Zoi.string() |> Zoi.refine({Jido.Util, :validate_name, []}),
    state_key: Zoi.atom(),
    description: Zoi.string() |> Zoi.optional(),
    category: Zoi.string() |> Zoi.optional(),
    vsn: Zoi.string() |> Zoi.optional(),
    schema: Zoi.any() |> Zoi.optional(),
    config_schema: Zoi.any() |> Zoi.optional(),
    signal_patterns: Zoi.list(Zoi.string()) |> Zoi.default([]),
    actions: Zoi.list(Zoi.any()),
    tags: Zoi.list(Zoi.string()) |> Zoi.default([])
  }, coerce: true)

  def config_schema, do: @skill_config_schema

  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Jido.Skill

      alias Jido.Skill.Spec
      alias Jido.Signal
      alias Jido.Instruction

      @skill_opts (case Zoi.parse(Jido.Skill.config_schema(), Map.new(unquote(opts))) do
                     {:ok, validated} -> validated
                     {:error, errors} ->
                       raise CompileError,
                         description: "Invalid Skill configuration: #{inspect(errors)}",
                         file: __ENV__.file,
                         line: __ENV__.line
                   end)

      # Validate actions exist at compile time
      for action <- @skill_opts.actions do
        unless Code.ensure_compiled?(action) do
          raise CompileError,
            description: "Action #{inspect(action)} not compiled",
            file: __ENV__.file,
            line: __ENV__.line
        end
      end

      @impl true
      def skill_spec(config_overrides \\ %{}) do
        config = validate_config(@skill_opts, config_overrides)

        %Spec{
          module: __MODULE__,
          name: @skill_opts.name,
          state_key: @skill_opts.state_key,
          description: @skill_opts[:description],
          category: @skill_opts[:category],
          vsn: @skill_opts[:vsn],
          schema: @skill_opts[:schema],
          config_schema: @skill_opts[:config_schema],
          config: config,
          signal_patterns: @skill_opts[:signal_patterns] || [],
          tags: @skill_opts[:tags] || [],
          actions: @skill_opts.actions
        }
      end

      # Metadata accessors (pure)
      def name, do: @skill_opts.name
      def state_key, do: @skill_opts.state_key
      def description, do: @skill_opts[:description]
      def category, do: @skill_opts[:category]
      def vsn, do: @skill_opts[:vsn]
      def schema, do: @skill_opts[:schema]
      def signal_patterns, do: @skill_opts[:signal_patterns] || []
      def actions, do: @skill_opts.actions
      def tags, do: @skill_opts[:tags] || []

      # Default process callback implementations
      def mount(agent, _config), do: {:ok, agent}
      def router(_config), do: []
      def handle_signal(signal, _config), do: {:ok, signal}
      def transform_result(_signal, result, _config), do: {:ok, result}
      def child_spec(_config), do: []

      defoverridable [
        skill_spec: 1,
        mount: 2,
        router: 1,
        handle_signal: 2,
        transform_result: 3,
        child_spec: 1
      ]

      defp validate_config(skill_opts, overrides) do
        case skill_opts[:config_schema] do
          nil -> overrides
          schema ->
            case Zoi.parse(schema, overrides) do
              {:ok, validated} -> validated
              {:error, errors} ->
                raise ArgumentError, "Invalid skill config: #{inspect(errors)}"
            end
        end
      end
    end
  end
end
```

---

## State Isolation via `state_key`

Each skill gets its own namespace in agent state:

```elixir
# After mounting Calculator and Stats skills:
agent.state = %{
  calculator: %{precision: 2, last_result: 0.0},
  stats: %{window: 100, samples: []}
}
```

### State Key Invariants

- No two skills may use the same `state_key`
- The agent's own top-level schema keys must not collide with any skill `state_key`
- These invariants are enforced at compile-time by `use Jido.Agent`

### Schema Composition

Agent's merged schema nests skill schemas under their state keys:

```elixir
# Agent base schema
Zoi.object(%{
  mode: Zoi.atom() |> Zoi.default(:interactive)
})

# + Calculator skill schema (nested under :calculator)
# + Stats skill schema (nested under :stats)

# = Merged schema
Zoi.object(%{
  mode: Zoi.atom() |> Zoi.default(:interactive),
  calculator: Zoi.object(%{
    precision: Zoi.integer() |> Zoi.default(2),
    last_result: Zoi.float() |> Zoi.default(0.0)
  }),
  stats: Zoi.object(%{
    window: Zoi.integer() |> Zoi.default(50),
    samples: Zoi.list(Zoi.float()) |> Zoi.default([])
  })
})
```

No conflicts possible because each skill is isolated under its unique key.

---

## Agent Integration

### Extended Config Schema

```elixir
@agent_config_schema Zoi.object(%{
  name: ...,
  description: ...,
  category: ...,
  tags: ...,
  vsn: ...,
  schema: ...,
  strategy: ...,

  skills:
    Zoi.list(Zoi.any())
    |> Zoi.default([])
    |> Zoi.description("Skill modules or {module, config} tuples")
}, coerce: true)
```

### Compile-Time Resolution in `__using__/1`

```elixir
defmacro __using__(opts) do
  quote location: :keep do
    @behaviour Jido.Agent

    # ... existing validation ...

    # Normalize skills: Module or {Module, config}
    @skills_config Enum.map(@validated_opts[:skills] || [], fn
                     mod when is_atom(mod) -> {mod, %{}}
                     {mod, opts} -> {mod, Map.new(opts)}
                   end)

    # Validate skills implement behaviour
    for {mod, _} <- @skills_config do
      unless function_exported?(mod, :skill_spec, 1) do
        raise CompileError,
          description: "#{inspect(mod)} does not implement Jido.Skill"
      end
    end

    # Build skill specs at compile time
    @skill_specs Enum.map(@skills_config, fn {mod, config} ->
                   mod.skill_spec(config)
                 end)

    # Validate unique state_keys
    state_keys = Enum.map(@skill_specs, & &1.state_key)
    duplicates = state_keys -- Enum.uniq(state_keys)
    unless duplicates == [] do
      raise CompileError,
        description: "Duplicate skill state_keys: #{inspect(duplicates)}"
    end

    # Validate no collision with base schema keys
    base_keys = Jido.Agent.Schema.known_keys(@validated_opts[:schema])
    collisions = Enum.filter(state_keys, &(&1 in base_keys))
    unless collisions == [] do
      raise CompileError,
        description: "Skill state_keys collide with agent schema: #{inspect(collisions)}"
    end

    # Merge schemas: base schema + nested skill schemas
    @merged_schema Jido.Agent.Schema.merge_with_skills(
                     @validated_opts[:schema],
                     @skill_specs
                   )

    # Aggregate actions from skills
    @skill_actions @skill_specs |> Enum.flat_map(& &1.actions) |> Enum.uniq()

    # Override schema to return merged version
    def schema, do: @merged_schema

    # Introspection APIs (pure layer only)
    def skills, do: @skill_specs
    def skill_specs, do: @skill_specs
    def actions, do: @skill_actions

    def skill_config(skill_mod) do
      case Enum.find(@skill_specs, &(&1.module == skill_mod)) do
        nil -> nil
        spec -> spec.config
      end
    end

    def skill_state(agent, skill_mod) do
      case Enum.find(@skill_specs, &(&1.module == skill_mod)) do
        nil -> nil
        spec -> Map.get(agent.state, spec.state_key)
      end
    end

    defoverridable schema: 0, skills: 0, skill_specs: 0, actions: 0,
                   skill_config: 1, skill_state: 2
  end
end
```

### Schema Merging with Nesting

```elixir
defmodule Jido.Agent.Schema do
  @moduledoc "Utilities for merging agent and skill schemas."

  def merge_with_skills(base_schema, skill_specs) do
    skill_fields =
      skill_specs
      |> Enum.filter(& &1.schema)
      |> Enum.map(fn spec -> {spec.state_key, spec.schema} end)
      |> Map.new()

    case base_schema do
      nil ->
        Zoi.object(skill_fields)

      base ->
        base_fields = extract_fields(base)
        Zoi.object(Map.merge(base_fields, skill_fields))
    end
  end

  def known_keys(nil), do: []
  def known_keys(schema), do: Map.keys(extract_fields(schema))

  defp extract_fields(%Zoi.Schema{type: :object, fields: fields}), do: fields
  defp extract_fields(_), do: %{}
end
```

---

## Usage Examples

### Defining a Skill (Third-Party Package)

```elixir
# lib/jido_skill/calculator.ex
defmodule Jido.Skill.Calculator do
  use Jido.Skill,
    name: "calculator",
    state_key: :calculator,
    description: "Basic arithmetic operations",
    category: "math",
    vsn: "0.1.0",
    schema: Zoi.object(%{
      precision: Zoi.integer() |> Zoi.default(2),
      last_result: Zoi.float() |> Zoi.default(0.0)
    }),
    config_schema: Zoi.object(%{
      max_value: Zoi.integer() |> Zoi.default(1_000_000)
    }),
    signal_patterns: ["calculator.*"],
    actions: [
      Jido.Skill.Calculator.Add,
      Jido.Skill.Calculator.Multiply
    ]

  # Process-only: used by AgentServer
  @impl true
  def router(config) do
    [
      %Jido.Signal.Router.Route{
        path: "calculator.add",
        target: %Instruction{action: Jido.Skill.Calculator.Add}
      }
    ]
  end
end

# lib/jido_skill/calculator/add.ex
defmodule Jido.Skill.Calculator.Add do
  use Jido.Action,
    name: "add",
    description: "Add two numbers",
    schema: Zoi.object(%{
      a: Zoi.float(),
      b: Zoi.float()
    })

  def run(agent, %{a: a, b: b}, _ctx) do
    precision = agent.state[:calculator][:precision] || 2
    result = Float.round(a + b, precision)

    new_state = put_in(agent.state[:calculator][:last_result], result)

    {:ok, %{agent | state: new_state}, []}
  end
end
```

### Using Skills in an Agent

```elixir
defmodule MyApp.MathAgent do
  use Jido.Agent,
    name: "math_agent",
    description: "Agent with calculation abilities",
    schema: Zoi.object(%{
      mode: Zoi.atom() |> Zoi.default(:interactive)
    }),
    skills: [
      Jido.Skill.Calculator,
      {Jido.Skill.Stats, %{window: 100}}
    ]
end

# Usage (pure layer)
agent = MyApp.MathAgent.new()
# agent.state = %{
#   mode: :interactive,
#   calculator: %{precision: 2, last_result: 0.0},
#   stats: %{window: 100, samples: []}
# }

{agent, directives} = MyApp.MathAgent.cmd(agent, {Jido.Skill.Calculator.Add, %{a: 1.5, b: 2.5}})

# Introspection (pure layer)
MyApp.MathAgent.skills()           # => [%Skill.Spec{name: "calculator", ...}, ...]
MyApp.MathAgent.actions()          # => [Jido.Skill.Calculator.Add, ...]
MyApp.MathAgent.skill_config(Jido.Skill.Calculator)  # => %{max_value: 1_000_000}
MyApp.MathAgent.skill_state(agent, Jido.Skill.Calculator)  # => %{precision: 2, last_result: 4.0}
```

---

## Introspection APIs (Pure Layer)

| Function | Returns | Description |
|----------|---------|-------------|
| `skills/0` | `[Skill.Spec.t()]` | All attached skill specs |
| `skill_specs/0` | `[Skill.Spec.t()]` | Alias for `skills/0` |
| `actions/0` | `[module()]` | All available action modules |
| `skill_config/1` | `map() \| nil` | Config for a specific skill module |
| `skill_state/2` | `map() \| nil` | Current state for a skill (from agent) |
| `schema/0` | `Zoi.t()` | Merged schema (base + nested skills) |

> Note: There is no `routes/0` at the Agent level. Routes are an AgentServer concern.

---

## AgentServer Integration (Process Layer)

`Jido.AgentServer` consumes skill metadata at runtime. Neither `router/1` nor `signal_patterns` affect `cmd/2` or any pure Agent operations.

### Callback Flow (AgentServer)

```
Signal arrives at AgentServer
    ↓
Find matching skills via signal_patterns
    ↓
For each matching skill: skill.handle_signal/2
    ↓
Router matches signal → Instructions (via skill router/1)
    ↓
Execute Instructions via agent_module.cmd/2 (pure)
    ↓
For each matching skill: skill.transform_result/3
    ↓
AgentServer emits resulting Signals / directives
```

### Example AgentServer Implementation

```elixir
defmodule Jido.AgentServer do
  def init({agent_module, opts}) do
    agent = agent_module.new(opts)

    # Mount each skill (runtime hook)
    agent =
      Enum.reduce(agent_module.skill_specs(), agent, fn spec, acc ->
        if function_exported?(spec.module, :mount, 2) do
          {:ok, mounted} = spec.module.mount(acc, spec.config)
          mounted
        else
          acc
        end
      end)

    # Build router from skill routes (AgentServer-only concern)
    routes =
      agent_module.skill_specs()
      |> Enum.flat_map(fn spec ->
        if function_exported?(spec.module, :router, 1) do
          spec.module.router(spec.config)
        else
          []
        end
      end)

    router = Jido.Signal.Router.new(routes)

    # Collect child specs for supervision
    child_specs =
      agent_module.skill_specs()
      |> Enum.flat_map(fn spec ->
        if function_exported?(spec.module, :child_spec, 1) do
          spec.module.child_spec(spec.config)
        else
          []
        end
      end)

    {:ok, %{agent: agent, agent_module: agent_module, router: router},
     {:continue, {:start_children, child_specs}}}
  end
end
```

---

## Signal Patterns (Process Layer)

Skills declare what signals they handle via glob patterns:

```elixir
signal_patterns: ["calculator.*"]      # Matches calculator.add, calculator.multiply
signal_patterns: ["user.**"]           # Matches user.created, user.profile.updated
```

Pattern matching uses `Jido.Signal.Router.matches?/2`:
- `*` — Single segment wildcard
- `**` — Multi-segment wildcard (any depth)

> These patterns are metadata only in v2.0. AgentServer uses them for signal dispatch.

---

## Package Structure

A typical skill package (e.g., `jido_calculator`):

```
lib/
  jido_skill/
    calculator.ex           # Skill definition
    calculator/
      add.ex                # Action modules
      multiply.ex
      divide.ex
mix.exs
README.md
```

---

## Migration from v1

| v1 | v2 |
|----|-----|
| `opts_key` | `state_key` |
| `opts_schema` (NimbleOptions) | `schema` (Zoi) |
| Validated at server init | Validated at compile time |
| Process-coupled | Pure functional core |

---

## Implementation Phases

### Phase 1: Core (v2.0)
- [ ] `Jido.Skill` behaviour with `skill_spec/1`
- [ ] `Jido.Skill.Spec` struct
- [ ] `skills:` option in `use Jido.Agent`
- [ ] Schema merging with nesting under `state_key`
- [ ] State key collision detection
- [ ] Zoi defaults extraction for skill schemas
- [ ] Introspection APIs: `skills/0`, `actions/0`, `skill_config/1`, `skill_state/2`

> Note: Process callbacks exist in the behaviour but are not wired up in Phase 1.

### Phase 2: Routing (v2.1)
- [ ] `router/1` callback integration in AgentServer
- [ ] Signal pattern matching
- [ ] `handle_signal/2` pipeline

### Phase 3: Lifecycle (v2.2)
- [ ] `mount/2` callback in AgentServer
- [ ] `transform_result/3` pipeline
- [ ] `child_spec/1` for supervised processes

---

## Summary

Skills v2 provides:

- **For skill authors**: `use Jido.Skill` with Zoi schemas and rich callbacks
- **For agent authors**: `skills: [...]` with isolated state per skill
- **For runtimes**: Full routing and lifecycle hooks via AgentServer
- **For everyone**: Pure functional core, compile-time safety, Hex-distributable

The key separation: **Pure layer** (Agent + Skills) handles actions, state, and schemas. **Process layer** (AgentServer) handles signals, routing, and lifecycle.

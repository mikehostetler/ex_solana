# Jido 2.0 - Configuration & Extensibility

This document covers how to configure Jido and extend its core abstractions.

## Instance Configuration

### Defining a Jido Instance

```elixir
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app
end
```

### Application Configuration

In `config/config.exs`:

```elixir
config :my_app, MyApp.Jido,
  max_tasks: 1000,
  agent_pools: []
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:max_tasks` | integer | 1000 | Maximum concurrent tasks for Task.Supervisor |
| `:agent_pools` | list | [] | Agent pool configurations |

### Generated API

The instance module provides these functions:

```elixir
# Agent lifecycle
MyApp.Jido.start_agent(MyAgent, id: "agent-1")
MyApp.Jido.start_agent(MyAgent, id: "agent-1", initial_state: %{count: 10})
MyApp.Jido.stop_agent("agent-1")

# Lookup
MyApp.Jido.whereis("agent-1")  # Returns pid or nil
MyApp.Jido.list_agents()       # Returns list of {id, pid}
MyApp.Jido.agent_count()       # Returns integer

# Infrastructure names
MyApp.Jido.registry_name()
MyApp.Jido.agent_supervisor_name()
MyApp.Jido.task_supervisor_name()
```

## Extending Agents

### Schema Definition

Define agent state with NimbleOptions or Zoi:

```elixir
defmodule MyApp.Agent do
  use Jido.Agent,
    name: "my_agent",
    schema: [
      # NimbleOptions style
      count: [type: :integer, default: 0],
      name: [type: :string, required: true],
      config: [
        type: :keyword_list,
        keys: [
          timeout: [type: :pos_integer, default: 5000],
          retries: [type: :non_neg_integer, default: 3]
        ]
      ]
    ]
end
```

### Custom Strategy

Swap the default strategy:

```elixir
defmodule MyApp.Agent do
  use Jido.Agent,
    name: "my_agent",
    strategy: Jido.Agent.Strategy.FSM

  # Or with options
  use Jido.Agent,
    strategy: {Jido.Agent.Strategy.FSM,
      initial_state: "idle",
      transitions: %{
        "idle" => ["processing"],
        "processing" => ["completed", "failed"],
        "completed" => ["idle"],
        "failed" => ["idle"]
      }
    }
end
```

### Attaching Skills

```elixir
defmodule MyApp.Agent do
  use Jido.Agent,
    name: "my_agent",
    skills: [
      # Simple skill (no config)
      MyApp.ChatSkill,
      
      # Skill with configuration
      {MyApp.DatabaseSkill, %{pool_size: 5}},
      
      # Multiple skills work together
      MyApp.LoggingSkill,
      MyApp.MetricsSkill
    ]
end
```

### Lifecycle Hooks

Override hooks for cross-cutting concerns:

```elixir
defmodule MyApp.Agent do
  use Jido.Agent, name: "my_agent"

  @impl Jido.Agent
  def on_before_cmd(agent, action) do
    # Pre-processing before any command
    Logger.info("Running action: #{inspect(action)}")
    {agent, action}
  end

  @impl Jido.Agent
  def on_after_cmd(agent, action, directives) do
    # Post-processing after any command
    Logger.info("Completed action: #{inspect(action)}")
    {agent, directives}
  end
end
```

## Extending Strategies

### Creating a Custom Strategy

```elixir
defmodule MyApp.BatchStrategy do
  use Jido.Agent.Strategy

  @impl true
  def init(agent, ctx) do
    # Initialize strategy state
    agent = put_in(agent, [:state, :__strategy__], %{
      batch: [],
      batch_size: ctx[:batch_size] || 10
    })
    {agent, []}
  end

  @impl true
  def cmd(agent, instructions, ctx) do
    strategy_state = agent.state.__strategy__
    batch = strategy_state.batch ++ instructions
    
    if length(batch) >= strategy_state.batch_size do
      # Execute the batch
      {agent, directives} = execute_batch(agent, batch, ctx)
      agent = put_in(agent, [:state, :__strategy__, :batch], [])
      {agent, directives}
    else
      # Accumulate
      agent = put_in(agent, [:state, :__strategy__, :batch], batch)
      {agent, []}
    end
  end

  @impl true
  def tick(agent, ctx) do
    # Force flush on tick
    batch = agent.state.__strategy__.batch
    if batch != [] do
      {agent, directives} = execute_batch(agent, batch, ctx)
      agent = put_in(agent, [:state, :__strategy__, :batch], [])
      {agent, directives}
    else
      {agent, []}
    end
  end

  @impl true
  def snapshot(agent, _ctx) do
    %Jido.Agent.Strategy.Snapshot{
      status: :running,
      done?: false,
      result: nil,
      details: %{pending_batch: length(agent.state.__strategy__.batch)}
    }
  end

  defp execute_batch(agent, instructions, ctx) do
    # Execute all instructions
    Enum.reduce(instructions, {agent, []}, fn instruction, {agent, directives} ->
      {agent, new_directives} = Jido.Exec.run(agent, instruction, ctx)
      {agent, directives ++ new_directives}
    end)
  end
end
```

### Using the Custom Strategy

```elixir
defmodule MyApp.BatchAgent do
  use Jido.Agent,
    name: "batch_agent",
    strategy: {MyApp.BatchStrategy, batch_size: 5}
end
```

## Extending Skills

### Full Skill Implementation

```elixir
defmodule MyApp.CacheSkill do
  use Jido.Skill,
    name: "cache",
    description: "Provides caching capabilities",
    state_key: :cache,
    actions: [
      MyApp.Actions.CacheGet,
      MyApp.Actions.CacheSet,
      MyApp.Actions.CacheInvalidate
    ],
    schema: Zoi.object(%{
      entries: Zoi.map(Zoi.string(), Zoi.any()) |> Zoi.default(%{}),
      max_size: Zoi.integer() |> Zoi.default(1000),
      ttl_ms: Zoi.integer() |> Zoi.default(60_000)
    }),
    signal_patterns: ["cache.*"]

  @impl Jido.Skill
  def skill_spec(config) do
    # Return full spec with computed values
    %Jido.Skill.Spec{
      name: "cache",
      state_key: :cache,
      actions: [
        MyApp.Actions.CacheGet,
        MyApp.Actions.CacheSet,
        MyApp.Actions.CacheInvalidate
      ],
      config: Map.merge(%{max_size: 1000, ttl_ms: 60_000}, config)
    }
  end

  @impl Jido.Skill
  def mount(_agent, config) do
    # Initialize skill state
    {:ok, %{
      entries: %{},
      max_size: config[:max_size] || 1000,
      ttl_ms: config[:ttl_ms] || 60_000,
      initialized_at: DateTime.utc_now()
    }}
  end

  @impl Jido.Skill
  def router(_config) do
    # Define signal routing
    %{
      "cache.get" => MyApp.Actions.CacheGet,
      "cache.set" => MyApp.Actions.CacheSet,
      "cache.invalidate" => MyApp.Actions.CacheInvalidate
    }
  end

  @impl Jido.Skill
  def handle_signal(signal, _config) do
    # Pre-routing hook
    Logger.debug("Cache skill handling: #{signal.type}")
    {:ok, signal}
  end

  @impl Jido.Skill
  def transform_result(agent, _action, result) do
    # Post-action hook
    # Could emit metrics, etc.
    {agent, result, []}
  end

  @impl Jido.Skill
  def child_spec(_config) do
    # Return child specs for supervised processes
    # e.g., a background cleanup process
    []
  end
end
```

### Skill Callbacks Reference

| Callback | Purpose |
|----------|---------|
| `skill_spec/1` | Return full skill specification |
| `mount/2` | Initialize skill state on agent creation |
| `router/1` | Signal type → action mapping |
| `handle_signal/2` | Pre-routing signal hook |
| `transform_result/3` | Post-action result hook |
| `child_spec/1` | Supervised child processes |

## Extending Directives

### Custom Directive

Define a new directive struct:

```elixir
defmodule MyApp.Directive.CallLLM do
  defstruct [:model, :prompt, :callback_signal, :tag]
end
```

### Custom Directive Executor

Extend directive processing (via protocol or pattern matching in your runtime):

```elixir
defmodule MyApp.DirectiveExec do
  def execute(%MyApp.Directive.CallLLM{} = directive, context) do
    # Call the LLM
    {:ok, response} = MyApp.LLM.call(directive.model, directive.prompt)
    
    # Emit callback signal if specified
    if directive.callback_signal do
      signal = Jido.Signal.new!(
        directive.callback_signal,
        %{response: response, tag: directive.tag}
      )
      Jido.Signal.Dispatch.dispatch(signal, context.dispatch_adapters)
    end
    
    :ok
  end
end
```

## Extending Discovery

### Exposing Component Metadata

Add metadata functions to your modules:

```elixir
defmodule MyApp.Actions.CustomAction do
  use Jido.Action,
    name: "custom_action",
    description: "Does something custom"

  # Automatically generated by `use Jido.Action`
  # def __action_metadata__ do
  #   %{name: "custom_action", description: "Does something custom", ...}
  # end
end

defmodule MyApp.CustomSensor do
  # Manual metadata for custom components
  def __sensor_metadata__ do
    %{
      name: "custom_sensor",
      description: "Monitors custom events",
      config_schema: [...],
      signals: ["custom.event"]
    }
  end
end
```

### Querying Discovery

```elixir
# List all discovered components
Jido.Discovery.list_actions()
Jido.Discovery.list_agents()
Jido.Discovery.list_skills()
Jido.Discovery.list_sensors()
Jido.Discovery.list_demos()

# Filter by criteria
Jido.Discovery.list_actions(category: :ai)

# Get by slug
Jido.Discovery.get_action_by_slug("increment")
```

## Runtime Configuration

### Environment-Based Config

```elixir
# config/runtime.exs
config :my_app, MyApp.Jido,
  max_tasks: System.get_env("JIDO_MAX_TASKS", "1000") |> String.to_integer()
```

### Per-Agent Configuration

```elixir
MyApp.Jido.start_agent(MyApp.Agent, 
  id: "agent-1",
  initial_state: %{count: 0},
  strategy_opts: %{batch_size: 20},
  skill_configs: %{
    cache: %{max_size: 5000},
    logging: %{level: :debug}
  }
)
```

## Summary

Jido is designed for extensibility:

| Extension Point | Mechanism |
|-----------------|-----------|
| Instance Config | `use Jido, otp_app: :my_app` + application config |
| Agent Behavior | Schema, strategy, skills, lifecycle hooks |
| Execution Model | Custom strategies implementing callbacks |
| Capabilities | Custom skills with actions, routing, hooks |
| Effects | Custom directive structs + executors |
| Discovery | Metadata functions on modules |

The key principle: **Extend via composition, not modification**. Define new strategies, skills, and directives rather than modifying core behavior.

# Skills

Skills are composable capability modules that extend an agent's functionality. They encapsulate actions, state, configuration, and signal routing into reusable units.

## When to Use Skills

Use skills when you want to:
- Package related actions together with their state
- Reuse capabilities across multiple agents
- Isolate state for a specific domain (e.g., chat, database, metrics)
- Define signal routing rules for a group of actions

## Defining a Skill

```elixir
defmodule MyApp.ChatSkill do
  use Jido.Skill,
    name: "chat",
    state_key: :chat,
    actions: [MyApp.Actions.SendMessage, MyApp.Actions.ListHistory],
    schema: Zoi.object(%{
      messages: Zoi.list(Zoi.any()) |> Zoi.default([]),
      model: Zoi.string() |> Zoi.default("gpt-4")
    }),
    signal_patterns: ["chat.*"]
end
```

### Required Options

| Option | Description |
|--------|-------------|
| `name` | Skill name (letters, numbers, underscores only) |
| `state_key` | Atom key for skill state in agent's state map |
| `actions` | List of action modules the skill provides |

### Optional Options

| Option | Description |
|--------|-------------|
| `description` | Human-readable description |
| `schema` | Zoi schema for skill state defaults |
| `config_schema` | Zoi schema for per-agent configuration |
| `signal_patterns` | List of signal patterns for routing |
| `category`, `vsn`, `tags` | Metadata for organization |

## Using Skills

Attach skills to agents via the `skills:` option:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    skills: [
      MyApp.ChatSkill,
      {MyApp.DatabaseSkill, %{pool_size: 5}}  # With config
    ]
end
```

Skills are mounted during `new/1`. Each skill's state is initialized under its `state_key`.

## State Isolation

Skill state is nested under the skill's `state_key`:

```elixir
# ChatSkill with state_key: :chat
agent.state = %{
  chat: %{messages: [], model: "gpt-4"},  # ChatSkill state
  database: %{pool_size: 5}               # DatabaseSkill state
}

# Access skill state
chat_state = MyAgent.skill_state(agent, :chat)
```

This prevents skills from interfering with each other's state.

## Lifecycle Callbacks

All callbacks are optional with sensible defaults.

### mount/2

Called during `new/1` to initialize skill state. Pure function—no side effects.

```elixir
@impl Jido.Skill
def mount(agent, config) do
  {:ok, %{initialized_at: DateTime.utc_now(), api_key: config[:api_key]}}
end
```

Returns `{:ok, map}` to merge into skill state, or `{:error, reason}` to abort agent creation.

### router/1

Defines signal-to-action routing rules.

```elixir
@impl Jido.Skill
def router(_config) do
  [
    {"chat.send", MyApp.Actions.SendMessage},
    {"chat.history", MyApp.Actions.ListHistory}
  ]
end
```

### handle_signal/2

Pre-routing hook called before signal routing. Can override or abort processing.

```elixir
@impl Jido.Skill
def handle_signal(signal, context) do
  cond do
    signal.type == "admin.override" ->
      {:ok, {:override, MyApp.AdminAction}}
    blocked?(signal) ->
      {:error, :blocked}
    true ->
      {:ok, :continue}
  end
end
```

The `context` map contains `:agent`, `:agent_module`, `:skill`, `:skill_spec`, and `:config`.

### transform_result/3

Transforms the agent returned from `AgentServer.call/3` (synchronous path only).

```elixir
@impl Jido.Skill
def transform_result(_action, agent, _context) do
  new_state = Map.put(agent.state, :last_call_at, DateTime.utc_now())
  %{agent | state: new_state}
end
```

### child_spec/1

Returns child process specifications started during `AgentServer.init/1`.

```elixir
@impl Jido.Skill
def child_spec(config) do
  %{id: MyWorker, start: {MyWorker, :start_link, [config]}}
end
```

Return `nil` for no children, a single spec, or a list of specs.

## Composing Multiple Skills

Agents can use multiple skills with isolated state:

```elixir
defmodule MyAssistant do
  use Jido.Agent,
    name: "assistant",
    skills: [
      MyApp.ChatSkill,
      MyApp.MemorySkill,
      {MyApp.ToolsSkill, %{enabled_tools: [:search, :calculator]}}
    ]
end
```

Each skill maintains its own state slice and routing rules. Skills are mounted in order, so later skills can depend on state from earlier ones.

## See Also

See `Jido.Skill` moduledoc for complete API reference and advanced patterns.

# Jido Claude Usage Rules

## Package Overview
Jido Claude provides Claude Code integration for the Jido Agent framework, enabling AI-powered code sessions within your agent workflows.

## Prerequisites

Claude Code CLI must be installed and authenticated:
```bash
npm install -g @anthropic-ai/claude-code
claude  # authenticate via browser
```

## Core Components

### ClaudeSessionAgent
A Jido agent that manages a single Claude Code session:

```elixir
alias JidoClaude.ClaudeSessionAgent
alias JidoClaude.Actions.StartSession

# Start a session agent
{:ok, pid} = Jido.Agent.Server.start_link(
  agent: ClaudeSessionAgent,
  name: {:via, Registry, {MyRegistry, "claude-1"}}
)

# Run a prompt
Jido.Agent.Server.cmd(pid, {StartSession, %{
  prompt: "Analyze this codebase",
  model: "sonnet",
  max_turns: 25
}})
```

### Actions

**StartSession** - Start a Claude session:
```elixir
{:ok, result} = JidoClaude.Actions.StartSession.run(%{
  prompt: "Review this code for security issues",
  model: "sonnet",           # "haiku", "sonnet", or "opus"
  max_turns: 25,             # Maximum agentic iterations
  allowed_tools: ["Read", "Glob", "Grep", "Bash"],
  cwd: "/path/to/project",   # Working directory
  system_prompt: nil,        # Optional custom system prompt
  sdk_timeout_ms: 600_000    # 10 minute timeout
}, context)
```

**HandleMessage** - Handle incoming messages:
```elixir
{:ok, result} = JidoClaude.Actions.HandleMessage.run(%{
  message: "Continue with the next step"
}, context)
```

**CancelSession** - Cancel an active session:
```elixir
{:ok, result} = JidoClaude.Actions.CancelSession.run(%{}, context)
```

## Parent Agent Pattern

For managing multiple concurrent Claude sessions:

```elixir
defmodule MyOrchestrator do
  use Jido.Agent,
    name: "orchestrator",
    schema: [
      sessions: [type: :map, default: %{}]
    ]

  alias JidoClaude.Parent.{SpawnSession, HandleSessionEvent, CancelSession}

  def signal_routes do
    [
      {"claude.session.started", {HandleSessionEvent, &extract_params/1}},
      {"claude.session.success", {HandleSessionEvent, &extract_params/1}},
      {"claude.session.error", {HandleSessionEvent, &extract_params/1}}
    ]
  end

  defp extract_params(signal) do
    %{
      session_id: signal.data.session_id,
      event_type: signal.type,
      data: signal.data
    }
  end

  def actions do
    [SpawnSession, CancelSession]
  end
end
```

### Spawning Sessions
```elixir
# Spawn with explicit session_id
{agent, _} = MyOrchestrator.cmd(agent, {SpawnSession, %{
  session_id: "review-pr-123",
  prompt: "Review PR #123 for security issues"
}})

# Spawn with auto-generated session_id
{agent, _} = MyOrchestrator.cmd(agent, {SpawnSession, %{
  prompt: "Analyze dependencies"
}})

# Check status
agent.state.sessions
# => %{
#   "review-pr-123" => %{status: :running, turns: 3, ...},
#   "claude-a1b2c3d4" => %{status: :running, turns: 1, ...}
# }
```

### Cancelling Sessions
```elixir
{agent, _} = MyOrchestrator.cmd(agent, {CancelSession, %{
  session_id: "review-pr-123"
}})
```

## Signal Types

| Signal | Description |
|--------|-------------|
| `claude.session.started` | Session initialized with model info |
| `claude.turn.text` | Claude's text response |
| `claude.turn.tool_use` | Claude is calling a tool |
| `claude.turn.tool_result` | Tool execution result |
| `claude.session.success` | Session completed successfully |
| `claude.session.error` | Session failed |

## Configuration Options

### StartSession / SpawnSession Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `prompt` | string | required | The prompt to send to Claude |
| `model` | string | "sonnet" | Model: "haiku", "sonnet", or "opus" |
| `max_turns` | integer | 25 | Maximum agentic loop iterations |
| `allowed_tools` | list | ["Read", "Glob", "Grep", "Bash"] | Tools Claude can use |
| `cwd` | string | current dir | Working directory for tools |
| `system_prompt` | string | nil | Custom system prompt |
| `sdk_timeout_ms` | integer | 600_000 | SDK-level timeout (10 min) |
| `meta` | map | %{} | Custom metadata (SpawnSession only) |

## Error Handling

Jido Claude uses Splode for structured errors:

```elixir
case JidoClaude.Actions.StartSession.run(params, context) do
  {:ok, result} -> 
    # Handle success
  {:error, %JidoClaude.Error{} = error} ->
    # Handle structured error
    Logger.error("Session failed: #{error.message}")
end
```

## Testing

```elixir
defmodule MySessionTest do
  use ExUnit.Case
  
  alias JidoClaude.Actions.StartSession

  test "validates required parameters" do
    {:error, error} = StartSession.run(%{}, %{})
    assert error.type == :invalid_input_error
  end

  test "validates model option" do
    {:error, error} = StartSession.run(%{
      prompt: "test",
      model: "invalid"
    }, %{})
    assert error.message =~ "model"
  end
end
```

## Common Patterns

### Session with Custom Tools
```elixir
{:ok, _} = StartSession.run(%{
  prompt: "Only read files, don't execute anything",
  allowed_tools: ["Read", "Glob", "Grep"]
}, context)
```

### Session with Timeout
```elixir
{:ok, _} = StartSession.run(%{
  prompt: "Quick analysis",
  max_turns: 5,
  sdk_timeout_ms: 60_000  # 1 minute
}, context)
```

### Tracking Session Progress
```elixir
def handle_signal(%{type: "claude.turn.text"} = signal, agent) do
  Logger.info("Claude says: #{signal.data.text}")
  {:ok, agent}
end

def handle_signal(%{type: "claude.turn.tool_use"} = signal, agent) do
  Logger.info("Claude using tool: #{signal.data.tool_name}")
  {:ok, agent}
end
```

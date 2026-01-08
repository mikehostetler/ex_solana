# Jido Claude

Claude Code integration for the Jido Agent framework.

## Installation

Add `jido_claude` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido_claude, "~> 0.1.0"}
  ]
end
```

## Prerequisites

1. **Claude Code CLI** must be installed and authenticated:
   ```bash
   npm install -g @anthropic-ai/claude-code
   claude  # authenticate via browser
   ```

2. The SDK uses the CLI's stored authentication - no API keys needed in your Elixir app.

## Architecture

JidoClaude provides a two-agent pattern for running Claude Code sessions:

```
┌─────────────────────────────────────────┐
│  Parent Agent (Orchestrator)            │
│  - Spawns ClaudeSessionAgent children   │
│  - Receives signals from all sessions   │
│  - Tracks status in sessions registry   │
└─────────────────────────────────────────┘
          │ SpawnAgent
          ▼
┌─────────────────────────────────────────┐
│  ClaudeSessionAgent                     │
│  - Owns single Claude session           │
│  - Runs SDK in background Task          │
│  - Emits turn signals to parent         │
└─────────────────────────────────────────┘
          │ Task
          ▼
┌─────────────────────────────────────────┐
│  StreamRunner                           │
│  - Calls ClaudeAgentSDK.query/3         │
│  - Dispatches messages as signals       │
└─────────────────────────────────────────┘
```

## Usage

### Single Session

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

### Multi-Session (Parent Agent)

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

# Spawn multiple concurrent sessions
{agent, _} = MyOrchestrator.cmd(agent, {SpawnSession, %{
  session_id: "review-pr-123",
  prompt: "Review PR #123 for security issues"
}})

{agent, _} = MyOrchestrator.cmd(agent, {SpawnSession, %{
  prompt: "Analyze dependencies"  # auto-generates session_id
}})

# Check status
agent.state.sessions
# => %{
#   "review-pr-123" => %{status: :running, turns: 3, ...},
#   "claude-a1b2c3d4" => %{status: :running, turns: 1, ...}
# }

# Cancel a session
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

### StartSession / SpawnSession

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

## License

Apache 2.0

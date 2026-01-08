# Claude Code SDK for Elixir

This document covers integration with Claude Code CLI from Elixir using the `claude_agent_sdk` package.

## Package

```elixir
# mix.exs
{:claude_agent_sdk, "~> 0.7"}
```

Hex: https://hex.pm/packages/claude_agent_sdk
Docs: https://hexdocs.pm/claude_agent_sdk

## Prerequisites

1. **Claude Code CLI** must be installed and authenticated:
   ```bash
   npm install -g @anthropic-ai/claude-code
   claude  # authenticate via browser
   ```

2. The SDK uses the CLI's stored authentication - no API keys needed in your Elixir app.

---

## Core API: `ClaudeAgentSDK.query/3`

The main function for interacting with Claude Code. Returns a **Stream** of `Message` structs.

```elixir
alias ClaudeAgentSDK.{Options, Message}

options = %Options{
  model: "sonnet",           # "haiku", "sonnet", or "opus"
  max_turns: 10,             # max agentic loop iterations
  allowed_tools: ["Read", "Glob", "Grep", "Bash"],
  cwd: File.cwd!()           # working directory for tools
}

"Tell me about this project"
|> ClaudeAgentSDK.query(options)
|> Stream.each(fn message -> 
  IO.inspect(message.type)
end)
|> Stream.run()
```

### Key Insight: Streaming Messages

The `query/3` function returns a **lazy Stream** that yields messages as they arrive from the CLI. This means:

- Messages appear in real-time, not after completion
- Long-running prompts (3+ minutes) show progress incrementally
- You can display tool calls, text responses, and results as they happen

---

## Message Types

The stream yields `ClaudeAgentSDK.Message` structs with these types:

| Type | Subtype | Description |
|------|---------|-------------|
| `:system` | `:init` | Session started - contains model, tools, session_id |
| `:assistant` | - | Claude's response - may contain text and/or tool calls |
| `:user` | - | Tool results returned to Claude |
| `:result` | `:success` | Final result with cost, duration, turns |
| `:result` | `:error_*` | Error during execution |

### Message Structure

```elixir
%ClaudeAgentSDK.Message{
  type: :assistant,           # :system, :assistant, :user, :result
  subtype: nil,               # :init, :success, :error_*, etc.
  data: %{...},               # type-specific data
  raw: %{...}                 # original JSON from CLI
}
```

### Extracting Content Blocks

For `:assistant` messages, use `Message.content_blocks/1` to get text and tool calls:

```elixir
defp handle_assistant(%Message{type: :assistant} = msg) do
  msg
  |> Message.content_blocks()
  |> Enum.each(fn
    %{type: :text, text: text} ->
      IO.puts("Claude says: #{text}")

    %{type: :tool_use, name: name, input: input} ->
      IO.puts("Using tool: #{name}")

    _ -> :ok
  end)
end
```

**Note:** Content blocks use **atom keys** (`%{type: :text}`), not string keys.

---

## Complete Example: Mix Task with Progress

```elixir
defmodule Mix.Tasks.Claude.Test do
  use Mix.Task
  alias ClaudeAgentSDK.{Options, Message}

  def run(args) do
    Application.ensure_all_started(:claude_agent_sdk)

    prompt = Enum.join(args, " ")

    options = %Options{
      model: "sonnet",
      max_turns: 10,
      allowed_tools: ["Read", "Glob", "Grep", "Bash"],
      cwd: File.cwd!()
    }

    prompt
    |> ClaudeAgentSDK.query(options)
    |> Stream.each(&handle_message/1)
    |> Stream.run()
  end

  defp handle_message(%Message{type: :system, data: data}) do
    IO.puts("⚙ Session started (#{data.model})")
  end

  defp handle_message(%Message{type: :assistant} = msg) do
    msg
    |> Message.content_blocks()
    |> Enum.each(fn
      %{type: :tool_use, name: name, input: input} ->
        IO.puts("🔧 #{name}: #{inspect(input)}")
      _ -> :ok
    end)
  end

  defp handle_message(%Message{type: :result, data: data}) do
    IO.puts("\n#{data.result}")
    IO.puts("✓ Turns: #{data.num_turns} | Cost: $#{data.total_cost_usd}")
  end

  defp handle_message(_), do: :ok
end
```

---

## Options Reference

```elixir
%ClaudeAgentSDK.Options{
  # Model selection
  model: "sonnet",              # "haiku", "sonnet", "opus"
  
  # Agentic loop
  max_turns: 10,                # max tool use iterations
  
  # Tool permissions
  allowed_tools: ["Read", "Bash", "Glob", "Grep", "Edit", "Write"],
  disallowed_tools: [],
  
  # Context
  system_prompt: "...",         # custom system prompt
  append_system_prompt: "...",  # additional instructions
  cwd: "/path/to/dir",          # working directory
  
  # Timeouts
  timeout_ms: 300_000,          # 5 minutes default
  
  # Advanced
  permission_mode: :default,    # :default, :acceptEdits, :bypassPermissions
  verbose: true,                # enable debug output
}
```

---

## Streaming API (Single-Turn)

For simple prompts without tools, the Streaming API provides character-by-character output:

```elixir
alias ClaudeAgentSDK.{Options, Streaming}

options = %Options{
  model: "sonnet",
  include_partial_messages: true
}

{:ok, session} = Streaming.start_session(options)

try do
  session
  |> Streaming.send_message("What is Elixir?")
  |> Stream.each(fn
    %{type: :text_delta, text: text} -> IO.write(text)
    %{type: :message_stop} -> IO.puts("\n✓ Done")
    _ -> :ok
  end)
  |> Stream.run()
after
  Streaming.close_session(session)
end
```

### Streaming Limitations

The Streaming API does **not** support multi-turn tool execution:

- When Claude calls a tool, you receive `%{type: :message_delta, stop_reason: "tool_use"}`
- The stream ends because the CLI expects tool execution to happen internally
- For agentic workflows with tools, use `query/3` instead

---

## Architecture Notes

### How `query/3` Works

1. Spawns Claude CLI subprocess with `--print --output-format stream-json`
2. Sends prompt via CLI arguments (or stdin for streaming input)
3. CLI runs the agentic loop internally (tool calls + results)
4. Each message (system, assistant, user, result) is streamed to stdout as JSON
5. SDK parses JSON lines into `Message` structs and yields them via Stream

### Transport Selection

The SDK automatically selects the appropriate transport:

- **CLI-only** (default): Fast, simple, handles tools internally
- **Control Client**: For hooks, MCP servers, custom permissions

```elixir
# Automatic selection based on options
ClaudeAgentSDK.query("prompt", options)

# Force control client for advanced features
options = %Options{
  hooks: [...],           # triggers control client
  mcp_servers: %{...},    # triggers control client
}
```

---

## Troubleshooting

### "Claude CLI not found"

```bash
npm install -g @anthropic-ai/claude-code
which claude  # verify installation
```

### "Authentication required"

```bash
claude  # opens browser for auth
```

### No output / timeout

- Check `max_turns` is sufficient for the task
- Verify `allowed_tools` includes needed tools
- Increase `timeout_ms` for long operations

### Messages not appearing in real-time

Make sure you're using `Stream.each` + `Stream.run()`, not `Enum.to_list()`:

```elixir
# ✓ Correct - streams in real-time
query |> Stream.each(&handle/1) |> Stream.run()

# ✗ Wrong - waits for all messages
query |> Enum.to_list()
```

---

## See Also

- [claude_agent_sdk on Hex](https://hex.pm/packages/claude_agent_sdk)
- [Mix Task Chat Example](https://hexdocs.pm/claude_agent_sdk/mix-task-chat-example.html)
- [Streaming Guide](https://hexdocs.pm/claude_agent_sdk/streaming.html)
- Example implementation: `lib/mix/tasks/claude_test.ex`

---

## Example Task Usage

```bash
# Simple prompt (15 turns default)
mix claude.test "Tell me about this project"

# Verbose mode - show text responses too
mix claude.test -v "Summarize the README"

# Complex tasks need more turns
mix claude.test -t 25 "Analyze the codebase"

# Combine flags
mix claude.test -v -t 30 "Review the architecture and suggest improvements"
```

### Understanding `max_turns`

Each "turn" is a tool call → tool result cycle. Complex prompts like "analyze the codebase" may require 20+ turns as Claude:

1. Lists directories
2. Reads multiple files
3. Explores project structure
4. Reads configuration
5. Synthesizes findings

If you see "⚠ Hit max_turns limit", increase with `-t N`.

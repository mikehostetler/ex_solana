# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

JidoCode is an **Agentic Coding Assistant TUI** built in Elixir. It provides an interactive terminal interface for AI-assisted coding, featuring:

- **LLM Agent** - Jido-based agent with Chain-of-Thought reasoning
- **TUI Interface** - Elm Architecture terminal UI via TermUI
- **Tool System** - File system, search, and shell tools with security sandbox
- **Settings Management** - Two-level JSON configuration (global + local)
- **Knowledge Graph** - RDF infrastructure for semantic code understanding (foundation)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          TUI Layer                               │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ JidoCode.TUI (Elm Architecture: init/update/view)           │ │
│  │   - Input handling, message display, status bar             │ │
│  │   - Keyboard shortcuts (Ctrl+R for reasoning panel)         │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                              │ PubSub                            │
├─────────────────────────────┼────────────────────────────────────┤
│                          Agent Layer                             │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ JidoCode.Agents.LLMAgent (Jido.AI.Agent)                    │ │
│  │   - Message validation & streaming                          │ │
│  │   - Chain-of-Thought reasoning modes                        │ │
│  │   - Model configuration (provider/model switching)          │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                              │                                   │
├─────────────────────────────┼────────────────────────────────────┤
│                          Tools Layer                             │
│  ┌─────────────┐ ┌─────────────┐ ┌───────────────────────────┐  │
│  │ Registry    │ │ Executor    │ │ Security/Manager          │  │
│  │ (tool defs) │ │ (dispatch)  │ │ (path validation, Lua)    │  │
│  └─────────────┘ └─────────────┘ └───────────────────────────┘  │
│                              │                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ Tool Handlers: FileSystem, Search, Shell                    │ │
│  │   - read_file, write_file, grep, find_files, run_command   │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Key Modules

| Module | Purpose |
|--------|---------|
| `JidoCode.TUI` | Terminal UI with Elm Architecture pattern |
| `JidoCode.Agents.LLMAgent` | AI agent with streaming and CoT reasoning |
| `JidoCode.Config` | LLM provider configuration with validation |
| `JidoCode.Settings` | Two-level JSON settings (global/local merge) |
| `JidoCode.Commands` | Slash command parsing (/help, /model, etc.) |
| `JidoCode.Tools.Registry` | Tool registration and lookup (ETS-backed) |
| `JidoCode.Tools.Executor` | Tool call parsing and execution with timeout |
| `JidoCode.Tools.Security` | Path validation and boundary enforcement |
| `JidoCode.Tools.Manager` | Lua sandbox for secure script execution |
| `JidoCode.Reasoning.*` | QueryClassifier, Formatter, ChainOfThought |

## Configuration

### Environment Variables

```bash
# LLM Provider (overrides config)
JIDO_CODE_PROVIDER=anthropic
JIDO_CODE_MODEL=claude-3-5-sonnet-20241022

# API Keys (managed by JidoAI Keyring)
ANTHROPIC_API_KEY=sk-...
OPENAI_API_KEY=sk-...
```

### Application Config (config/runtime.exs)

```elixir
config :jido_code, :llm,
  provider: :anthropic,
  model: "claude-3-5-sonnet-20241022",
  temperature: 0.7,
  max_tokens: 4096
```

### Settings Files

- **Global**: `~/.jido_code/settings.json`
- **Local**: `./jido_code/settings.json` (project-specific, overrides global)

```json
{
  "version": 1,
  "provider": "anthropic",
  "model": "claude-3-5-sonnet-20241022"
}
```

## Dependencies

```elixir
# Core
{:jido, "~> 1.2"}
{:jido_ai, "~> 0.5"}
{:term_ui, "~> 0.1"}

# Communication
{:phoenix_pubsub, "~> 2.1"}

# Knowledge Graph (foundation)
{:rdf, "~> 2.0"}
{:libgraph, "~> 0.16"}

# Security
{:luerl, "~> 1.2"}  # Lua sandbox
```

## Local Development Dependencies

These sibling repositories can be modified if needed:

- `../jido_ai` - JidoAI library (agents, CoT runner, provider integration)
- `../term_ui` - TermUI library (Elm Architecture TUI framework, widgets)

## Commands & Build

```bash
# Development
mix deps.get
mix compile
mix test                    # Run all tests
mix test --trace           # Verbose test output
mix coveralls.html         # Coverage report

# Run the TUI
iex -S mix
JidoCode.TUI.run()

# Quality
mix credo --strict
mix dialyzer
```

## Test Structure

- `test/jido_code/` - Unit tests for all modules
- `test/jido_code/integration_test.exs` - End-to-end flow tests
- Test coverage: 80%+ (currently ~80.23%)
- Total tests: 998 (44 integration tests)

## Security Model

The tool system enforces security through multiple layers:

1. **Path Validation** - All paths validated against project boundary
2. **Command Allowlist** - Only approved commands (mix, git, npm, etc.)
3. **Shell Blocking** - Shell interpreters (bash, sh) are blocked
4. **Lua Sandbox** - Restricted Lua environment (no os.execute, io.popen)
5. **Symlink Following** - Symlinks validated to prevent escape

## PubSub Topics

```elixir
# TUI Events
"tui.events"                    # Global tool execution events
"tui.events.#{session_id}"      # Session-specific events

# Message Types
{:stream_chunk, content}        # Streaming response chunk
{:stream_end, full_content}     # Stream complete
{:tool_call, name, args, id}    # Tool execution started
{:tool_result, %Result{}}       # Tool execution complete
{:config_changed, old, new}     # Configuration updated
```

## Code Patterns

### Adding a New Tool

```elixir
# 1. Create handler in lib/jido_code/tools/handlers/
defmodule JidoCode.Tools.Handlers.MyTool do
  def execute(args, context) do
    # Validate args, perform action
    {:ok, "result"}  # or {:error, "reason"}
  end
end

# 2. Create definition in lib/jido_code/tools/definitions/
def my_tool do
  Tool.new!(%{
    name: "my_tool",
    description: "Does something useful",
    handler: Handlers.MyTool,
    parameters: [%{name: "arg", type: :string, required: true}]
  })
end

# 3. Register in application.ex or at runtime
Registry.register(Definitions.MyModule.my_tool())
```

### TUI State Updates

The TUI follows Elm Architecture - all state changes go through `update/2`:

```elixir
def update({:key_input, char}, model) do
  %{model | input_buffer: model.input_buffer <> char}
end

def update({:stream_chunk, content}, model) do
  %{model | streaming_message: (model.streaming_message || "") <> content}
end
```

## Research Documents

- `notes/research/1.00-architecture/` - Multi-agent TUI architecture design
- `notes/research/1.01-knowledge-base/` - Knowledge graph memory design
- `notes/planning/proof-of-concept/` - Implementation phases and tasks

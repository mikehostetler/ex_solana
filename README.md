# JidoCode

An Agentic Coding Assistant TUI built in Elixir, powered by [Jido](https://github.com/agentjido/jido) and [JidoAI](https://github.com/agentjido/jido_ai).

## Features

- **Interactive TUI** - Terminal user interface with Elm Architecture pattern
- **LLM Integration** - Support for Anthropic, OpenAI, and other providers via JidoAI
- **Chain-of-Thought Reasoning** - Multiple reasoning modes (zero-shot, few-shot, structured)
- **Tool System** - File operations, search, and shell commands with security sandbox
- **Streaming Responses** - Real-time response streaming with progress indicators
- **Two-Level Settings** - Global and project-specific configuration

## Prerequisites

- Elixir 1.15+
- Erlang/OTP 26+
- An API key for your chosen LLM provider

## Installation

1. Clone the repository:
```bash
git clone https://github.com/agentjido/jido_code.git
cd jido_code
```

2. Install dependencies:
```bash
mix deps.get
```

3. Set up your API key:
```bash
export ANTHROPIC_API_KEY="your-api-key"
# Or for OpenAI:
export OPENAI_API_KEY="your-api-key"
```

4. Configure the LLM provider (required):
```bash
export JIDO_CODE_PROVIDER="anthropic"
export JIDO_CODE_MODEL="claude-3-5-sonnet-20241022"
```

## Quick Start

Start the TUI:
```bash
iex -S mix
```

Then in IEx:
```elixir
JidoCode.TUI.run()
```

Type your message and press Enter. Use `/help` for available commands.

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `JIDO_CODE_PROVIDER` | LLM provider name (required) | - |
| `JIDO_CODE_MODEL` | Model identifier (required) | - |
| `ANTHROPIC_API_KEY` | Anthropic API key | - |
| `OPENAI_API_KEY` | OpenAI API key | - |

### Application Config

In `config/runtime.exs`:

```elixir
config :jido_code, :llm,
  provider: :anthropic,
  model: "claude-3-5-sonnet-20241022",
  temperature: 0.7,
  max_tokens: 4096
```

### Settings Files

JidoCode uses a two-level settings system:

- **Global**: `~/.jido_code/settings.json` - Applies to all projects
- **Local**: `./jido_code/settings.json` - Project-specific overrides

```json
{
  "version": 1,
  "provider": "anthropic",
  "model": "claude-3-5-sonnet-20241022",
  "providers": ["anthropic", "openai"],
  "models": {
    "anthropic": ["claude-3-5-sonnet-20241022", "claude-3-opus-20240229"],
    "openai": ["gpt-4o", "gpt-4-turbo"]
  }
}
```

Local settings override global settings. Environment variables override both.

## TUI Commands

### Slash Commands

| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/config` | Display current configuration |
| `/provider <name>` | Set LLM provider (clears model) |
| `/model <provider>:<model>` | Set both provider and model |
| `/model <model>` | Set model for current provider |
| `/models` | List models for current provider |
| `/models <provider>` | List models for specific provider |
| `/providers` | List available providers |

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Enter` | Submit message |
| `Ctrl+C` | Quit TUI |
| `Ctrl+R` | Toggle reasoning panel |
| `Up/Down` | Scroll conversation |

### Status Indicators

| Status | Meaning |
|--------|---------|
| `idle` | Ready for input |
| `processing` | Agent is working |
| `error` | An error occurred |
| `unconfigured` | Missing provider/API key |

## Available Tools

The agent can use these tools to interact with your codebase:

### File System Tools

| Tool | Description | Parameters |
|------|-------------|------------|
| `read_file` | Read file contents | `path` (required) |
| `write_file` | Write/create file | `path`, `content` (required) |
| `list_directory` | List directory contents | `path` (required), `recursive` (optional) |
| `file_info` | Get file metadata | `path` (required) |
| `create_directory` | Create directory | `path` (required) |
| `delete_file` | Delete file | `path`, `confirm=true` (required) |

### Search Tools

| Tool | Description | Parameters |
|------|-------------|------------|
| `grep` | Search file contents | `pattern`, `path` (required), `recursive`, `max_results` (optional) |
| `find_files` | Find files by pattern | `pattern` (required), `path`, `max_results` (optional) |

### Shell Tools

| Tool | Description | Parameters |
|------|-------------|------------|
| `run_command` | Execute shell command | `command` (required), `args`, `timeout` (optional) |

Allowed commands: `mix`, `elixir`, `iex`, `git`, `npm`, `npx`, `yarn`, `node`, `cargo`, `go`, `python`, `pip`, `ls`, `cat`, `grep`, `find`, `make`, `curl`, `wget`, and more.

## Security Model

JidoCode enforces multiple security layers:

### Path Validation
- All file operations validated against project boundary
- Path traversal attempts (`../`) are blocked
- Absolute paths outside project root are rejected
- Symlinks are followed and validated

### Shell Command Security
- Command allowlist - only approved commands can run
- Shell interpreters blocked - no `bash`, `sh`, `zsh` execution
- Arguments validated - no path traversal in arguments
- Timeout enforcement - commands killed after 25s default
- Output truncation - max 1MB output to prevent memory exhaustion

### Lua Sandbox
The tool manager uses Luerl with restrictions:
- `os.execute`, `os.exit` - blocked
- `io.popen`, `io.open` - blocked
- `loadfile`, `dofile`, `require` - blocked
- `package` - blocked

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          TUI Layer                               │
│  JidoCode.TUI - Elm Architecture (init → update → view)         │
│    ├── Input handling                                            │
│    ├── Message display                                           │
│    └── Status bar                                                │
├─────────────────────────────────────────────────────────────────┤
│                          Agent Layer                             │
│  JidoCode.Agents.LLMAgent (Jido.AI.Agent)                       │
│    ├── Message validation                                        │
│    ├── Streaming responses                                       │
│    └── Chain-of-Thought reasoning                                │
├─────────────────────────────────────────────────────────────────┤
│                          Tools Layer                             │
│  Registry → Executor → Handlers                                  │
│    ├── FileSystem (read, write, list, delete)                   │
│    ├── Search (grep, find)                                       │
│    └── Shell (run_command with allowlist)                       │
├─────────────────────────────────────────────────────────────────┤
│                          Security Layer                          │
│  Security (path validation) + Manager (Lua sandbox)             │
└─────────────────────────────────────────────────────────────────┘
```

### Supervision Tree

```
JidoCode.Supervisor
├── JidoCode.Settings.Cache (GenServer)
├── Phoenix.PubSub.Supervisor
├── JidoCode.AgentRegistry (Registry)
├── JidoCode.Tools.Registry (GenServer + ETS)
├── JidoCode.Tools.Manager (GenServer + Luerl)
└── JidoCode.AgentSupervisor (DynamicSupervisor)
    └── JidoCode.Agents.LLMAgent (dynamic children)
```

## Troubleshooting

### "No LLM provider configured"

Set the provider via environment variable:
```bash
export JIDO_CODE_PROVIDER="anthropic"
```

Or create a settings file:
```bash
mkdir -p ~/.jido_code
echo '{"provider": "anthropic", "model": "claude-3-5-sonnet-20241022"}' > ~/.jido_code/settings.json
```

### "API key not found"

Set the appropriate API key:
```bash
# For Anthropic
export ANTHROPIC_API_KEY="sk-ant-..."

# For OpenAI
export OPENAI_API_KEY="sk-..."
```

### "Provider not found"

Ensure you're using a valid provider name. List available providers:
```elixir
Jido.AI.Model.Registry.list_providers()
```

### "Model not found for provider"

The model must be registered with your provider. List available models:
```elixir
Jido.AI.Model.Registry.list_models(:anthropic)
```

### Tests Failing

Run tests with verbose output:
```bash
mix test --trace
```

For a specific test file:
```bash
mix test test/jido_code/integration_test.exs
```

### Path Traversal Blocked

If you see "path_escapes_boundary" errors, ensure your file paths:
- Are relative to the project root
- Don't contain `../` that would escape the project
- Aren't absolute paths outside the project

### Command Not Allowed

The shell tool only allows specific commands. See the [Shell Tools](#shell-tools) section for the allowlist.

## Development

### Running Tests

```bash
# All tests
mix test

# With coverage
mix coveralls.html

# Integration tests only
mix test test/jido_code/integration_test.exs
```

### Code Quality

```bash
mix credo --strict
mix dialyzer
```

### Test Coverage

Current coverage: ~80.23% (998 tests, 0 failures)

## License

MIT License - see [LICENSE](LICENSE) for details.

## Related Projects

- [Jido](https://github.com/agentjido/jido) - Autonomous agent framework for BEAM
- [JidoAI](https://github.com/agentjido/jido_ai) - AI integration library
- [TermUI](https://github.com/agentjido/term_ui) - Elm Architecture TUI framework

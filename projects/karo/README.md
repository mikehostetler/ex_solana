# Karo

[![Hex.pm](https://img.shields.io/hexpm/v/karo.svg)](https://hex.pm/packages/karo)
[![Documentation](https://img.shields.io/badge/docs-hexpm-blue.svg)](https://hexdocs.pm/karo)

A persistent AI agent for Elixir applications with Discord integration, conversation memory, and scheduled actions.

Karo maintains memory across sessions, integrates with the [Jido](https://github.com/agentjido/jido) ecosystem, and can be accessed via TUI, Discord, or embedded in Phoenix apps.

## Features

- **Persistent Conversations**: SQLite-backed conversation history via Ash Framework
- **Discord Integration**: Full Discord bot support with channel/thread isolation
- **Character System**: Customizable AI persona via `jido_character`
- **Scheduled Actions**: CRON-based scheduled tasks via `jido_cron`
- **Process-per-Conversation**: Fault-isolated chat sessions with automatic cleanup
- **TUI Mode**: Local terminal interface for development and testing

## Installation

Add `karo` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:karo, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Send a message to a conversation
{:ok, response} = Karo.send_message("channel_123", "user_456", "Hello!")

# With Discord guild context
{:ok, response} = Karo.send_message("channel_123", "user_456", "Hello!",
  guild_id: "guild_789")
```

## Configuration

```elixir
# config/config.exs
config :karo, Karo.Repo,
  database: "priv/karo.sqlite3"

config :karo,
  llm: [
    provider: :openai,
    model: "gpt-4o-mini",
    api_key: System.fetch_env!("OPENAI_API_KEY")
  ],
  chat_session: [
    idle_timeout_ms: :timer.minutes(15),
    max_context_messages: 50
  ]

# Discord bot configuration
config :nostrum,
  token: System.fetch_env!("DISCORD_BOT_TOKEN"),
  gateway_intents: [:guilds, :guild_messages, :direct_messages, :message_content]
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Karo.Supervisor                            │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌─────────────────┐  │
│  │ Karo.Repo │ │  Registry │ │ Jido.Cron │ │ Discord.Gateway │  │
│  └───────────┘ └───────────┘ └───────────┘ └─────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    Karo.Governor                         │   │
│  │  - Routes messages to chat sessions                      │   │
│  │  - Manages chat lifecycle (spawn/cleanup)                │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                  │
│  ┌───────────────────────────┴──────────────────────────────┐   │
│  │              Karo.ChatSupervisor (DynamicSupervisor)     │   │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐         │   │
│  │  │ ChatSession │ │ ChatSession │ │ ChatSession │  ...    │   │
│  │  └─────────────┘ └─────────────┘ └─────────────┘         │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Development

```bash
# Setup
mix deps.get
mix setup

# Run quality checks
mix quality

# Run tests
mix test

# Generate docs
mix docs
```

## License

Apache License 2.0 - see [LICENSE](LICENSE) for details.

## Links

- [Documentation](https://hexdocs.pm/karo)
- [GitHub](https://github.com/agentjido/karo)
- [Changelog](CHANGELOG.md)
- [Discord](https://agentjido.xyz/discord)

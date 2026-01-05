# AGENTS.md - Karo Development Guide

## Project Overview

Karo is a persistent AI agent for Elixir/Phoenix applications. It maintains memory across sessions, integrates with the Jido ecosystem, and can be accessed via TUI, Discord, or embedded in Phoenix apps.

## Common Commands

```bash
# Development
mix compile          # Compile the project
mix format           # Format code
mix test             # Run tests
mix coveralls        # Run tests with coverage

# Quality
mix quality          # Run full quality suite
mix q                # Alias for quality

# Database
mix ash.gen.migration <name>  # Generate Ash migration
mix ash.migrate               # Run migrations

# Documentation
mix docs             # Generate documentation
```

## Project Structure

```
lib/
├── karo.ex                    # Public API facade
├── karo/
│   ├── application.ex         # OTP application
│   ├── governor.ex            # Central router/lifecycle manager
│   ├── chat_session.ex        # Per-conversation GenServer
│   ├── character.ex           # jido_character integration
│   ├── llm.ex                 # req_llm wrapper
│   ├── cron.ex                # Jido CRON job definitions
│   ├── repo.ex                # Ash SQLite repo
│   ├── chat_domain.ex         # Ash domain
│   ├── resources/
│   │   ├── conversation.ex    # Ash resource
│   │   ├── message.ex         # Ash resource
│   │   └── scheduled_action.ex # Ash resource
│   ├── discord/
│   │   ├── gateway.ex         # Discord connection
│   │   └── handler.ex         # Event handling
│   └── transports/
│       └── tui.ex             # term_ui for testing
```

## Key Modules

| Module | Purpose |
|--------|---------|
| `Karo` | Main API facade |
| `Karo.Governor` | Routes messages, manages chat lifecycle |
| `Karo.ChatSession` | Per-conversation state and LLM logic |
| `Karo.ChatDomain` | Ash domain for persistence |
| `Karo.Discord.Gateway` | Nostrum consumer for Discord events |

## Architecture

- **Governor**: Single process that routes messages to ChatSessions
- **ChatSession**: One GenServer per conversation (channel/thread)
- **Registry**: O(1) lookup for chat sessions
- **DynamicSupervisor**: Fault isolation for chat processes

## Testing Patterns

```elixir
# Mock LLM for testing
Mimic.stub(ReqLLM, :chat, fn _, _ -> {:ok, "Mocked response"} end)

# Test chat session
test "handles user message" do
  {:ok, session} = Karo.ChatSession.start_link(conversation_id: "test")
  {:ok, response} = Karo.ChatSession.send_message(session, "Hello")
  assert response =~ "Hello"
end
```

## Dependencies

- `jido` - Core agent framework
- `jido_character` - Character/persona definitions
- `jido_cron` - Scheduled actions
- `req_llm` - LLM API client
- `ash` + `ash_sqlite` - Persistence
- `nostrum` - Discord library

## Code Style

- Use `@moduledoc` and `@doc` for all public modules/functions
- Prefer pattern matching over conditionals
- Use `{:ok, value}` / `{:error, reason}` tuples consistently
- Keep GenServer callbacks thin, delegate to helper functions

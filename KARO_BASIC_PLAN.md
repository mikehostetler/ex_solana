# Karo - Persistent AI Agent Package

A persistent AI agent for Elixir/Phoenix applications. Karo maintains memory across sessions, integrates with the Jido ecosystem, and can be accessed via TUI, Discord, or embedded in Phoenix apps.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      Karo.Supervisor                            │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌─────────────────┐  │
│  │ Karo.Repo │ │  Registry │ │ Jido.Cron │ │ Discord.Gateway │  │
│  │ (Ash+SQL) │ │           │ │           │ │                 │  │
│  └───────────┘ └───────────┘ └───────────┘ └─────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    Karo.Governor                         │   │
│  │  - Routes messages to chat sessions                      │   │
│  │  - Manages chat lifecycle (spawn/cleanup)                │   │
│  │  - Handles CRON scheduled events                         │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                  │
│  ┌───────────────────────────┴──────────────────────────────┐   │
│  │              Karo.ChatSupervisor (DynamicSupervisor)     │   │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐         │   │
│  │  │ ChatSession │ │ ChatSession │ │ ChatSession │  ...    │   │
│  │  │ (channel A) │ │ (channel B) │ │ (thread C)  │         │   │
│  │  └─────────────┘ └─────────────┘ └─────────────┘         │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Process Tree Design

### Supervision Tree

```elixir
# Karo.Application.start/2
children = [
  Karo.Repo,                                                    # Ash + SQLite
  {Registry, keys: :unique, name: Karo.ChatRegistry},           # Chat lookup
  {DynamicSupervisor, strategy: :one_for_one, name: Karo.ChatSupervisor},
  {Karo.Governor, []},                                          # Central router
  {Karo.Discord.Gateway, []},                                   # Discord transport
  {Jido.Cron, jobs: Karo.Cron.jobs()}                          # Scheduled actions
]

Supervisor.start_link(children, strategy: :one_for_one, name: Karo.Supervisor)
```

### Governor Responsibilities

| Responsibility | Description |
|----------------|-------------|
| **Routing** | Look up/start ChatSession for incoming messages |
| **Lifecycle** | Spawn chat processes via DynamicSupervisor |
| **Registry** | Maintain 1:1 mapping: conversation_key → ChatSession |
| **CRON Events** | Receive scheduled actions, route to correct chat |
| **Cleanup** | Handle Discord thread closed/archived events |

**NOT responsible for:** LLM logic, conversation memory, message persistence (that's ChatSession)

### ChatSession Responsibilities

| Responsibility | Description |
|----------------|-------------|
| **Conversation State** | In-memory recent messages buffer |
| **LLM Integration** | jido + jido_character + req_llm |
| **Persistence** | Save/load messages via Ash |
| **Discord Reply** | Send responses back via Discord.Gateway |
| **Idle Timeout** | Self-terminate after inactivity (15-30 min) |

### Conversation Key Mapping

```elixir
# One ChatSession per Discord conversation
conversation_key = {guild_id | nil, channel_id, thread_id | nil}

# Examples:
{nil, "dm_channel_123", nil}           # DM conversation
{"guild_1", "channel_456", nil}        # Guild channel
{"guild_1", "channel_456", "thread_7"} # Thread in channel
```

---

## Module Structure

```
lib/
├── karo.ex                          # Public API facade
├── karo/
│   ├── application.ex               # OTP application
│   ├── governor.ex                  # Central router/lifecycle manager
│   ├── chat_session.ex              # Per-conversation GenServer
│   ├── character.ex                 # jido_character integration
│   ├── llm.ex                       # req_llm wrapper
│   ├── cron.ex                      # Jido CRON job definitions
│   │
│   ├── repo.ex                      # Ash SQLite repo
│   ├── chat_domain.ex               # Ash domain
│   ├── resources/
│   │   ├── conversation.ex          # Ash resource
│   │   ├── message.ex               # Ash resource
│   │   └── scheduled_action.ex      # Ash resource
│   │
│   ├── discord/
│   │   ├── gateway.ex               # Discord connection
│   │   └── handler.ex               # Event handling
│   │
│   └── transports/
│       └── tui.ex                   # term_ui for testing
```

---

## Ash Framework Data Model

### Domain

```elixir
defmodule Karo.ChatDomain do
  use Ash.Domain

  resources do
    resource Karo.Resources.Conversation
    resource Karo.Resources.Message
    resource Karo.Resources.ScheduledAction
  end
end
```

### Resources

**Conversation**
```elixir
attributes do
  uuid_primary_key :id
  attribute :discord_guild_id, :string, allow_nil?: true
  attribute :discord_channel_id, :string
  attribute :discord_thread_id, :string, allow_nil?: true
  attribute :title, :string, allow_nil?: true
  attribute :status, :atom, default: :open  # :open | :closed | :archived
  attribute :last_activity_at, :utc_datetime
  timestamps()
end
```

**Message**
```elixir
attributes do
  uuid_primary_key :id
  attribute :role, :atom  # :user | :assistant | :system | :tool
  attribute :content, :string
  attribute :discord_user_id, :string, allow_nil?: true
  attribute :metadata, :map, default: %{}
  timestamps()
end

relationships do
  belongs_to :conversation, Karo.Resources.Conversation
end
```

**ScheduledAction**
```elixir
attributes do
  uuid_primary_key :id
  attribute :kind, :atom  # :reminder | :summary | :checkin
  attribute :run_at, :utc_datetime
  attribute :payload, :map, default: %{}
  attribute :status, :atom, default: :scheduled  # :scheduled | :running | :completed | :failed
  timestamps()
end

relationships do
  belongs_to :conversation, Karo.Resources.Conversation
end
```

---

## Implementation Phases

### Phase 1: Project Setup & Core Structure
**Effort: S (2-4 hours)**

- [ ] Create project skeleton following GENERIC_PACKAGE_QA.md
- [ ] Add core dependencies
  ```elixir
  # Runtime
  {:jido, path: "../jido"},
  {:jido_character, path: "../jido_character"},
  {:jido_cron, path: "../jido_cron"},
  {:req_llm, path: "../req_llm"},
  {:ash, "~> 3.0"},
  {:ash_sqlite, "~> 0.2"},
  {:nostrum, "~> 0.10"},  # Discord library
  {:jason, "~> 1.4"},
  
  # Dev/Test
  {:term_ui, "~> 0.1"},
  {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
  {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
  {:ex_doc, "~> 0.31", only: :dev, runtime: false},
  {:excoveralls, "~> 0.18", only: [:dev, :test]},
  {:mimic, "~> 2.0", only: :test}
  ```
- [ ] Set up basic supervision tree (empty Governor, no transports yet)
- [ ] Configure `mix quality` alias

### Phase 2: Ash Persistence Layer
**Effort: M (4-8 hours)**

- [ ] Set up `Karo.Repo` with SQLite
- [ ] Create `Karo.ChatDomain`
- [ ] Implement Ash resources:
  - `Karo.Resources.Conversation`
  - `Karo.Resources.Message`
  - `Karo.Resources.ScheduledAction`
- [ ] Create migrations
- [ ] Add domain helper functions:
  ```elixir
  Karo.ChatDomain.get_or_create_conversation(conversation_key, attrs)
  Karo.ChatDomain.create_message(conversation_id, role, content, meta)
  Karo.ChatDomain.list_recent_messages(conversation_id, limit: 50)
  Karo.ChatDomain.close_conversation(conversation_id)
  ```
- [ ] Write persistence tests

### Phase 3: Governor & ChatSession
**Effort: M (4-8 hours)**

- [ ] Implement `Karo.Governor`
  - Registry lookup for chat sessions
  - Start chat via DynamicSupervisor
  - Route incoming messages
  - Handle CRON events
  - Cleanup on thread close
- [ ] Implement `Karo.ChatSession`
  - Init with conversation_id, conversation_key
  - Handle user messages → LLM → response
  - Persist messages via Ash
  - Idle timeout (configurable, default 15 min)
  - Graceful shutdown
- [ ] Implement `Karo.Character` - jido_character integration
- [ ] Implement `Karo.LLM` - req_llm wrapper
- [ ] Write Governor/ChatSession tests (mocked LLM)

### Phase 4: Discord Transport
**Effort: M (4-8 hours)**

- [ ] Implement `Karo.Discord.Gateway`
  - Nostrum consumer setup
  - Handle MESSAGE_CREATE events
  - Build conversation_key from event
  - Route to Governor
- [ ] Implement `Karo.Discord.Handler`
  - Message sending
  - Thread/channel event handling
- [ ] Add Discord configuration
  ```elixir
  config :nostrum,
    token: System.fetch_env!("DISCORD_BOT_TOKEN"),
    gateway_intents: [:guilds, :guild_messages, :direct_messages, :message_content]
  ```
- [ ] Document Discord bot setup in README
- [ ] Write Discord adapter tests (mocked API)

### Phase 5: Jido CRON Integration
**Effort: S (2-4 hours)**

- [ ] Implement `Karo.Cron`
  - Define scheduled jobs
  - Daily summary job example
  - Per-conversation action runner
- [ ] Governor CRON event handling
  - Resolve conversation from ScheduledAction
  - Route to ChatSession
- [ ] ChatSession scheduled action handling
- [ ] Write CRON integration tests

### Phase 6: TUI Transport
**Effort: S (2-4 hours)**

- [ ] Implement `Karo.Transports.Tui`
  - term_ui chat interface
  - Local "tui_user" conversation
  - Debug info display
- [ ] Create `mix karo.tui` task
- [ ] Write TUI tests

### Phase 7: Polish & Release Prep
**Effort: S (2-4 hours)**

- [ ] Run `mix quality` and fix all issues
- [ ] Achieve >90% test coverage
- [ ] Complete documentation
- [ ] Set up GitHub Actions
- [ ] Initial CHANGELOG entry

---

## Key Design Decisions

### Process-per-Conversation
- One `ChatSession` GenServer per Discord channel/thread
- DynamicSupervisor for fault isolation
- Registry for O(1) lookup
- Idle timeout for resource cleanup

### Governor as Router (Not Supervisor)
- Thin routing layer, not a supervisor itself
- Delegates lifecycle to DynamicSupervisor
- Single point for CRON event injection
- Clean separation of concerns

### Ash Framework for Persistence
- Declarative resources, not raw Ecto
- SQLite for easy local dev
- Swappable to Postgres via config
- Rich query/action capabilities

### Discord over Telegram
- Better thread/channel model for conversations
- Rich presence and interaction options
- Good Elixir library support (Nostrum)

---

## Configuration Examples

### Minimal (Local Dev)
```elixir
config :karo, Karo.Repo,
  database: "priv/karo.sqlite3"

config :karo,
  llm: [api_key: System.get_env("OPENAI_API_KEY")]

config :nostrum,
  token: System.get_env("DISCORD_BOT_TOKEN")
```

### Full (Production)
```elixir
config :karo, Karo.Repo,
  database: System.get_env("KARO_DB_PATH", "priv/karo.sqlite3"),
  pool_size: 5

config :karo,
  llm: [
    provider: :openai,
    model: "gpt-4o-mini",
    api_key: System.fetch_env!("OPENAI_API_KEY")
  ],
  chat_session: [
    idle_timeout_ms: :timer.minutes(30),
    max_context_messages: 50
  ],
  tui: [enabled: Mix.env() == :dev]

config :nostrum,
  token: System.fetch_env!("DISCORD_BOT_TOKEN"),
  gateway_intents: [:guilds, :guild_messages, :direct_messages, :message_content]
```

---

## Dependencies

### Runtime
```elixir
{:jido, path: "../jido"},
{:jido_character, path: "../jido_character"},
{:jido_cron, path: "../jido_cron"},
{:req_llm, path: "../req_llm"},
{:ash, "~> 3.0"},
{:ash_sqlite, "~> 0.2"},
{:nostrum, "~> 0.10"},
{:jason, "~> 1.4"}
```

### Dev/Test
```elixir
{:term_ui, "~> 0.1"},
{:credo, "~> 1.7", only: [:dev, :test], runtime: false},
{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
{:ex_doc, "~> 0.31", only: :dev, runtime: false},
{:excoveralls, "~> 0.18", only: [:dev, :test]},
{:mimic, "~> 2.0", only: :test}
```

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Too many active ChatSessions | Idle timeout + optional per-guild cap |
| Discord ID mapping bugs | Centralize key building, unique index in Ash |
| CRON race conditions | ScheduledAction status state machine |
| Context growth | Configurable message limit, future summarization |
| SQLite concurrency | Document Postgres for high-traffic production |

---

## Future Enhancements (Not in v1)

- [ ] Vector-based memory (embeddings for semantic recall)
- [ ] Conversation summarization for context compression
- [ ] Phoenix LiveView chat component
- [ ] Tool/function calling via jido
- [ ] Multi-agent orchestration
- [ ] Cross-conversation reasoning / global agent brain

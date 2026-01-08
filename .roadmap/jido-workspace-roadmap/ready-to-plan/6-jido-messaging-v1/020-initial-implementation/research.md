# Research: jido_messaging v1 Initial Implementation

**Item ID**: `jido-workspace-roadmap/ready-to-plan/6-jido-messaging-v1/020-initial-implementation`
**Research Date**: 2026-01-07
**Status**: Complete

---

## Executive Summary

This item delivers the first working version of `jido_messaging` based on the architecture defined in item 019. The implementation must provide a minimal but usable library that can replace `jido_chat` in small integrations, with core primitives for message handling, agent communication, and simple persistence.

**Key Finding**: `jido_messaging` project already exists as a skeleton project with only a stub module. The implementation must build on this foundation while following the comprehensive vision documented in `JIDO_MESSAGING_VISION.md`.

---

## 1. Current State Analysis

### Existing jido_messaging Project

**Location**: `/projects/jido_messaging/`

**Current State**: Skeleton project with minimal implementation

**Existing Files**:
- `lib/jido_messaging.ex` - Only contains module docstring
- `lib/jido_messaging/application.ex` - Application module (needs inspection)
- `mix.exs` - Project configuration with Zoi 0.14, Jason dependencies
- `JIDO_MESSAGING_VISION.md` - Comprehensive 585-line vision document

**Current Dependencies** (from mix.exs):
```elixir
{:jason, "~> 1.4"}
{:zoi, "~> 0.14"}
```

**Missing Dependencies** (needed for implementation):
- `jido_signal` - For signal-based messaging
- `jido` - For agent integration
- `jido_action` - For action framework integration

---

## 2. jido_chat Implementation Analysis

### Core Components to Migrate/Replace

**Location**: `/projects/jido_chat/`

**Key Modules**:

1. **`Jido.Chat`** (`lib/jido_chat.ex:1-94`)
   - High-level API for chat operations
   - Functions: `create_room/2`, `send_message/4`, `join_room/3`, `leave_room/3`
   - Uses `Jido.Signal.Bus` for message delivery

2. **`Jido.Chat.Message`** (`lib/jido_chat/message.ex:1-378`)
   - Message struct with TypedStruct
   - Signal creation/conversion helpers
   - Message type hierarchy (chat, system, room events)
   - `Jido.AI.Promptable` implementation for LLM integration

3. **`Jido.Chat.Room`** (`lib/jido_chat/room.ex:1-426`)
   - GenServer managing room state
   - Participant management
   - Message history storage (in-memory list)
   - Strategy pattern for turn management (free_form, round_robin)
   - Signal subscription via `Jido.Signal.Bus.subscribe/2`

**Strengths to Preserve**:
- OTP-based supervision (GenServer per room)
- Signal-based communication via `Jido.Signal.Bus`
- Strategy pattern for room behavior
- Basic mention parsing support

**Pain Points to Address** (from item 019 research):
- Limited signal integration (custom event system)
- No streaming support
- Single supervisor for all rooms
- No multi-tenancy
- No channel abstraction

---

## 3. Jido Agent Integration Patterns

### Signal Router Architecture

**Location**: `/projects/jido/lib/jido/agent_server/signal_router.ex:1-155`

**Priority Levels**:
- Strategy: 50 (range 50-100)
- Agent: 0 (range -25 to 25)
- Skill: -10 (range -50 to -10)

**Signal Flow**:
```
Agent receives signal
  → SignalRouter matches path
    → Routes to handler
      → Agent.cmd/2 processes
        → Directive queue executes
```

**Integration Pattern**:
```elixir
# Define signal routes in agent
def signal_routes do
  [
    {"messaging.message.received", &handle_message/1},
    {"messaging.agent.request", &handle_agent_request/1}
  ]
end
```

### Agent Communication

**Key Files**:
- `/projects/jido/lib/jido/agent_server.ex` - Main agent runtime
- `/projects/jido_signal/lib/jido_signal/dispatch/bus.ex` - Signal bus (commented out, using alternative)

**Message Flow to Agent**:
1. User sends message via channel
2. Message wrapped in signal
3. Signal published to bus
4. Agent's signal router matches pattern
5. Agent processes and responds
6. Response streamed back as signals

---

## 4. Streaming Support (ReqLLM Patterns)

**Location**: `/projects/req_llm/lib/req_llm/response/stream.ex:1-238`

**Streaming Pattern**:
```elixir
# Stream chunks accumulated
def summarize(chunks) do
  # Accumulate: text, thinking, tool_calls, finish_reason, usage
  # Returns map with consolidated data
end

# Join stream into response
def join(stream, response) do
  chunks = Enum.to_list(stream)
  content_text = build_content_text(chunks)
  # Build complete message from chunks
end
```

**Stream Chunk Types**:
- `:content` - Text content
- `:thinking` - Reasoning content
- `:tool_call` - Tool invocation
- `:meta` - Metadata (usage, finish_reason)

**Application to jido_messaging**:
- Stream LLM responses via signals
- Each chunk emitted as `messaging.streaming.chunk` signal
- Final signal with `finish_reason` marks completion

---

## 5. Persistence Patterns

### Journal-based Persistence

**Location**: `/projects/jido_signal/lib/jido_signal/journal/persistence.ex:1-57`

**Adapter Behaviour**:
```elixir
@callback put_signal(Signal.t(), pid() | nil) :: :ok | error()
@callback get_signal(signal_id(), pid() | nil) :: {:ok, Signal.t()} | error()
@callback put_conversation(conversation_id(), signal_id(), pid() | nil) :: :ok
@callback get_conversation(conversation_id(), pid() | nil) :: {:ok, MapSet.t()}
```

**Available Adapters** (from file listing):
- Mnesia - `lib/jido_signal/journal/adapters/mnesia.ex`
- ETS - `lib/jido_signal/journal/adapters/ets.ex`
- In-memory - `lib/jido_signal/journal/adapters/in_memory.ex`

**Recommended Approach for v1**:
- Use ETS adapter for in-memory persistence
- Design adapter interface to support PostgreSQL later
- Journal all messaging signals for replay/debugging

---

## 6. Domain Model (From Vision Document)

### Core Entities

**Message** (LLM-native structure):
```elixir
%Message{
  id: "msg_uuid",
  room_id: "room_uuid",
  thread_id: nil | "thread_uuid",  # For sub-threads
  sender_id: "participant_uuid",
  role: :user | :assistant | :system | :tool,
  content: [
    %TextContent{text: "Hello"},
    %ImageContent{url: "..."},
    %ToolUse{id: "call_123", name: "search", input: %{...}},
    %ToolResult{tool_use_id: "call_123", content: "..."}
  ],
  reply_to_id: nil | "msg_uuid",
  mentions: ["participant_uuid"],
  reactions: [{emoji, participant_id, timestamp}],
  status: :sending | :sent | :delivered | :read | :failed,
  metadata: %{model: "claude-3-5-sonnet", tokens: %{...}},
  sent_at: DateTime,
  edited_at: DateTime | nil,
  deleted_at: DateTime | nil
}
```

**Room** (Conversation container):
```elixir
%Room{
  id: "room_uuid",
  type: :direct | :group | :channel | :thread,
  parent_room_id: nil | "parent_uuid",
  name: "General Chat",
  topic: "Discuss anything",
  permissions: %RoomPermissions{
    default_role: :member,
    roles: %{admin: [...], moderator: [...], member: [...]}
  },
  moderation: %ModerationConfig{
    auto_moderate: true,
    moderator_agent_id: "agent_uuid"
  },
  instance_bindings: ["instance_id"],
  metadata: %{
    created_at: DateTime,
    last_message_at: DateTime,
    message_count: 0
  }
}
```

**Participant** (User or agent):
```elixir
%Participant{
  id: "participant_uuid",
  type: :human | :agent | :system,
  identity: %{
    name: "Alice",
    avatar_url: "...",
    agent_id: "agent_uuid",  # For agents
    character_id: "char_uuid",  # From jido_character
    capabilities: [:text, :tool_use, :vision]
  },
  external_ids: [
    %{provider: :whatsapp, external_id: "+1234567890"}
  ],
  presence: :online | :away | :busy | :offline,
  metadata: %{
    last_seen_at: DateTime,
    session_state: %{}
  }
}
```

**Instance** (Platform connection):
```elixir
%Instance{
  id: "instance_uuid",
  name: "whatsapp_main",
  channel_type: :whatsapp | :discord | :slack | :internal,
  status: :connected | :disconnected | :connecting | :error,
  credentials: %{...},  # Platform-specific, encrypted
  settings: %{
    auto_split: true,
    webhook_url: "https://..."
  }
}
```

---

## 7. Implementation Phases

### Phase 1: Core Domain Models (Week 1)

**Files to Create**:
```
lib/jido_messaging/
├── message.ex                  # Message struct with Zoi
├── message/
│   ├── content.ex             # Content types (Text, Image, ToolUse, etc.)
│   └── content/
│       ├── text.ex
│       ├── image.ex
│       ├── tool_use.ex
│       └── tool_result.ex
├── room.ex                    # Room struct with Zoi
├── participant.ex             # Participant struct with Zoi
└── instance.ex                # Instance struct with Zoi
```

**Schema Definitions** (using Zoi 0.14):
- All structs use `use Zoi.Struct`
- Define `@schema Zoi.struct(...)`
- Constructors return `{:ok, t()} | {:error, term()}`

### Phase 2: Signal Definitions (Week 1)

**Files to Create**:
```
lib/jido_messaging/signals/
├── message.ex                # Message signals
├── room.ex                   # Room signals
├── participant.ex            # Participant signals
└── streaming.ex              # Streaming signals
```

**Signal Types**:
```elixir
defmodule JidoMessaging.Signals do
  def message_received, do: "messaging.message.received"
  def message_sent, do: "messaging.message.sent"
  def message_delivered, do: "messaging.message.delivered"
  def streaming_chunk, do: "messaging.streaming.chunk"
  def agent_request, do: "messaging.agent.request"
  def agent_response, do: "messaging.agent.response"
end
```

### Phase 3: Room Management (Week 2)

**Files to Create**:
```
lib/jido_messaging/
├── room_supervisor.ex        # DynamicSupervisor for rooms
├── room_server.ex            # GenServer per room
└── registry.ex               # Registry for room lookups
```

**Room Server Responsibilities**:
- Store message history (bounded, in-memory)
- Manage participant list
- Handle permissions
- Subscribe to messaging signals
- Emit signals on state changes

### Phase 4: Agent Integration (Week 2)

**Files to Create**:
```
lib/jido_messaging/agent/
├── gateway.ex                # Agent gateway GenServer
├── context_builder.ex        # Build ReqLLM context from room
└── streaming.ex              # Handle streaming responses
```

**Agent Gateway Pattern**:
```elixir
defmodule JidoMessaging.Agent.Gateway do
  use GenServer

  def process_message(message, room_id) do
    # Build context from room history
    context = build_context(room_id, message)

    # Emit agent request signal
    Jido.Signal.Bus.publish([
      %Jido.Signal{
        type: "messaging.agent.request",
        data: %{context: context, message: message}
      }
    ])

    # Subscribe to response signals
    Jido.Signal.Bus.subscribe("messaging.agent.response.*")
  end
end
```

### Phase 5: Persistence Adapter (Week 3)

**Files to Create**:
```
lib/jido_messaging/adapters/
├── behaviour.ex              # Adapter behaviour definition
└── ets.ex                    # ETS-based adapter
```

**Adapter Behaviour**:
```elixir
defmodule JidoMessaging.Adapters.Behaviour do
  @callback init(opts :: keyword()) :: {:ok, state} | {:error, reason}
  @callback save_message(Message.t()) :: {:ok, Message.t()} | {:error, reason}
  @callback get_messages(room_id, opts) :: {:ok, [Message.t()]} | {:error, reason}
  @callback save_room(Room.t()) :: {:ok, Room.t()} | {:error, reason}
  @callback get_room(room_id) :: {:ok, Room.t()} | {:error, :not_found}
  @callback save_participant(Participant.t()) :: {:ok, Participant.t()} | {:error, reason}
  @callback get_participant(id) :: {:ok, Participant.t()} | {:error, :not_found}
end
```

### Phase 6: Public API (Week 3)

**Files to Create**:
```
lib/jido_messaging/
├── api.ex                    # High-level API
└── commands/                 # Jido.Action implementations
    ├── send_message.ex
    ├── create_room.ex
    └── join_room.ex
```

**Public API**:
```elixir
defmodule JidoMessaging do
  # Room management
  def create_room(name, opts \\ [])
  def get_room(room_id)
  def list_rooms(opts \\ [])

  # Messaging
  def send_message(room_id, sender_id, content, opts \\ [])
  def get_messages(room_id, opts \\ [])

  # Participants
  def add_participant(room_id, participant)
  def remove_participant(room_id, participant_id)
  def get_participants(room_id)

  # Agents
  def add_agent_to_room(room_id, agent_opts)
  def remove_agent_from_room(room_id, agent_id)
end
```

---

## 8. File Structure for Initial Implementation

```
projects/jido_messaging/
├── lib/
│   ├── jido_messaging.ex                 # Public API (update from stub)
│   ├── jido_messaging/
│   │   ├── application.ex                # Application supervisor
│   │   ├── message.ex                    # Message domain model
│   │   ├── message/
│   │   │   ├── content.ex                # Content behaviours/structs
│   │   │   └── content/
│   │   │       ├── text.ex
│   │   │       ├── image.ex
│   │   │       ├── tool_use.ex
│   │   │       └── tool_result.ex
│   │   ├── room.ex                       # Room domain model
│   │   ├── room_server.ex                # Room GenServer
│   │   ├── room_supervisor.ex            # Dynamic supervisor
│   │   ├── participant.ex                # Participant domain model
│   │   ├── instance.ex                   # Instance domain model
│   │   ├── signals.ex                    # Signal type definitions
│   │   ├── signals/
│   │   │   ├── message.ex
│   │   │   ├── room.ex
│   │   │   ├── participant.ex
│   │   │   └── streaming.ex
│   │   ├── agent/
│   │   │   ├── gateway.ex
│   │   │   ├── context_builder.ex
│   │   │   └── streaming.ex
│   │   ├── adapters/
│   │   │   ├── behaviour.ex
│   │   │   └── ets.ex
│   │   ├── registry.ex                   # Process registry
│   │   └── util.ex                       # Utilities
│   └── jido_messaging_web/               # (Optional, future)
│       └── ...
├── test/
│   ├── jido_messaging_test.ex
│   ├── message_test.ex
│   ├── room_server_test.ex
│   └── support/
│       └── case.ex
├── mix.exs                              # Update dependencies
└── README.md                            # Update with usage examples
```

---

## 9. Dependencies to Add

**Update mix.exs**:
```elixir
defp deps do
  [
    # Runtime dependencies
    {:jason, "~> 1.4"},
    {:zoi, "~> 0.14"},

    # Jido ecosystem
    {:jido_signal, "~> 0.1"},           # Signal bus
    {:jido, "~> 0.2"},                  # Agent framework
    {:jido_action, "~> 0.1"},           # Action framework (optional)

    # Dev/Test dependencies
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:ex_doc, "~> 0.31", only: :dev, runtime: false},
    {:excoveralls, "~> 0.18", only: [:dev, :test]},
    {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
    {:git_ops, "~> 2.9", only: [:dev, :test]}
  ]
end
```

---

## 10. Integration Points

### With jido_chat (Migration Path)

**Current Usage**:
```elixir
# jido_chat API
Jido.Chat.create_room("General")
Jido.Chat.send_message(room_id, "user1", "Hello!")
```

**New API** (backward compatible wrapper):
```elixir
# jido_messaging API
JidoMessaging.create_room("General")
JidoMessaging.send_message(room_id, sender_id, [%{type: :text, text: "Hello!"}])
```

**Migration Strategy**:
1. Implement jido_messaging core
2. Add compatibility layer in jido_chat that delegates to jido_messaging
3. Gradually migrate integrations
4. Deprecate jido_chat

### With jido_signal

**Signal Subscription**:
```elixir
# Subscribe to room messages
Jido.Signal.Bus.subscribe("messaging.message.room.#{room_id}")

# Subscribe to streaming chunks
Jido.Signal.Bus.subscribe("messaging.streaming.#{room_id}")
```

**Signal Publishing**:
```elixir
# Emit message signal
Jido.Signal.Bus.publish([
  %Jido.Signal{
    type: "messaging.message.sent",
    source: "jido_messaging",
    subject: "room/#{room_id}",
    data: message
  }
])
```

### With jido agents

**Agent Signal Routes**:
```elixir
defmodule MyAgent do
  use Jido.Agent

  def signal_routes do
    [
      {"messaging.message.received", &handle_chat_message/1}
    ]
  end

  def handle_chat_message(signal) do
    message = signal.data.message
    # Process message and respond
  end
end
```

---

## 11. Testing Strategy

### Unit Tests

**Test Coverage Target**: 90% (from mix.exs config)

**Test Structure**:
```elixir
defmodule JidoMessagingTest do
  use JidoMessaging.DataCase

  describe "message creation" do
    test "creates valid text message" do
      assert {:ok, message} = Message.new(%{
        room_id: "room_123",
        sender_id: "user_123",
        role: :user,
        content: [%{type: :text, text: "Hello!"}]
      })
    end
  end
end
```

### Integration Tests

**Agent Integration**:
```elixir
defmodule JidoMessaging.AgentIntegrationTest do
  test "agent receives message and responds" do
    # Create room with agent
    # Send message
    # Assert agent response signal received
  end
end
```

### Streaming Tests

**Streaming Response**:
```elixir
test "streams agent response chunks" do
  # Mock agent streaming response
  # Subscribe to streaming signals
  # Assert chunks received in order
  # Assert final signal with finish_reason
end
```

---

## 12. Known Limitations for v1

Based on item overview, explicitly document:

**Deferred to Future Versions**:
- Read receipts (delivery confirmation beyond basic status)
- Complex routing rules (basic room-based routing only)
- Multi-agent coordination (single agent per room)
- Advanced moderation features (basic allow/block only)
- Channel implementations (internal/Phoenix LiveView only)
- Media storage (references only, no upload handling)
- Encryption (all content stored as-is)
- Federation/bridging (single-instance only)

**Supported in v1**:
- Basic message sending/receiving
- Room creation and management
- Participant management
- Agent participation (single agent per room)
- Streaming responses (basic chunk emission)
- In-memory persistence (via ETS adapter)
- Signal-based communication
- Phoenix LiveView rendering (basic)

---

## 13. Documentation Requirements

**README.md Sections**:
1. Quick start guide
2. Basic usage examples
3. API reference (link to HexDocs)
4. Migration guide from jido_chat
5. Known limitations
6. Future roadmap

**Code Documentation**:
- All public modules must have `@moduledoc`
- All public functions must have `@doc`
- Include examples in docs
- Use TypedSpecs for type specifications

---

## 14. Success Criteria

**Minimal Viable Product**:
- [ ] Can create a room
- [ ] Can send a message to a room
- [ ] Can add an agent to a room
- [ ] Agent receives message via signal
- [ ] Agent can respond with streaming
- [ ] Messages persisted via adapter
- [ ] Can replace jido_chat in small integration
- [ ] All tests passing (90% coverage)
- [ ] Basic documentation complete

**Integration Test**:
```elixir
# End-to-end test
room = JidoMessaging.create_room("Test")
JidoMessaging.add_agent_to_room(room.id, agent: TestAgent)
JidoMessaging.send_message(room.id, user_id, "Hello!")
# Assert agent response received
```

---

## 15. Next Steps After This Implementation

1. **Item 021-023**: jido_hub Phoenix project setup
   - Use jido_messaging as backend
   - LibreChat-style interface
   - Agent integration

2. **Channel Implementations** (future items):
   - WhatsApp adapter
   - Discord adapter
   - Slack adapter

3. **Advanced Features** (future items):
   - Multi-agent coordination
   - Advanced routing
   - Read receipts
   - Media handling

---

## Key Findings Summary

- **Project exists** as skeleton with only stub implementation
- **Vision document** (JIDO_MESSAGING_VISION.md) provides comprehensive 585-line specification
- **jido_chat** can be replaced with signal-driven, agent-first architecture
- **Streaming support** patterns available in ReqLLM
- **Persistence** can use ETS adapter for v1, design for PostgreSQL later
- **Agent integration** via Jido.Signal.Bus with priority-based routing

## Files Identified for Implementation

**New Files to Create** (35+ files):
- 8 domain model files (message, room, participant, instance, content types)
- 5 signal definition files
- 5 agent integration files
- 3 adapter files (behaviour + ETS + placeholder for Postgres)
- 6 room management files
- 8 test files

**Files to Modify**:
- `lib/jido_messaging.ex` - Replace stub with full API
- `mix.exs` - Add jido_signal, jido, jido_action dependencies
- `README.md` - Add usage documentation

**Existing Dependencies to Reference**:
- `/projects/jido_chat/` - Patterns to preserve/migrate
- `/projects/jido/lib/jido/agent_server/signal_router.ex` - Agent integration
- `/projects/req_llm/lib/req_llm/response/stream.ex` - Streaming patterns
- `/projects/jido_signal/lib/jido_signal/journal/persistence.ex` - Adapter patterns
- `/projects/jido_messaging/JIDO_MESSAGING_VISION.md` - Full specification

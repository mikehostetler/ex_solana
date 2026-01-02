# Jido Messaging Vision

> A unified messaging abstraction layer for the Jido ecosystem, enabling AI agents and humans to communicate across multiple messaging platforms through a consistent, pure-Elixir API.

## Overview

Jido Messaging provides a platform-agnostic messaging system that allows Jido agents (including LLM-backed agents) to participate in conversations alongside humans. The system abstracts away platform-specific complexity while maintaining full feature support for each channel.

**Key Differentiators:**
- **Agent-first design** - AI agents are first-class participants, not afterthoughts
- **LLM-native message model** - Messages have structural similarity to LLM context (tool calls, structured content)
- **Pure Elixir core** - Persistence is an adapter; can run fully in-memory (ETS) for testing
- **Jido ecosystem integration** - Built on `jido_action`, `jido_signal`, and `jido` agents

**Inspired by**:
- [automagik-omni](https://github.com/namastexlabs/automagik-omni) - Multi-platform messaging hub features
- [Juvet](https://github.com/juvet/juvet) - OTP process architecture and supervision patterns

---

## Core Features

### 1. Multi-Platform Channel Support

**Production Targets:**
- WhatsApp (via Evolution API or similar)
- Discord (native bot implementation)
- Slack (workspace integration)
- Telegram (bots, channels, groups)

**Built-in Renderers:**
- Phoenix LiveView (web chat interface)
- Terminal/IEx (TUI for development and CLI tools)
- API (headless JSON interface)

**Future Expansion:**
- Microsoft Teams
- SMS Gateway
- Matrix/Element

### 2. Message Handling

| Feature | Description |
|---------|-------------|
| **Unified Send API** | Single interface to send messages across all platforms |
| **Rich Message Types** | Text, media, audio, stickers, reactions, tool calls, tool responses |
| **Message Routing** | Automatic routing based on room and participant configuration |
| **Streaming Support** | Real-time streaming for LLM responses |
| **Sub-threads** | Messages can spawn sub-threads within rooms |
| **Quoted Messages** | Reply/thread support with message references |
| **Mention Parsing** | Handle @mentions including @agent mentions |

### 3. LLM-Native Message Structure

Messages are designed with structural similarity to LLM context formats:

```elixir
%Message{
  id: "msg_uuid",
  role: :user | :assistant | :system | :tool,
  content: [
    %TextContent{text: "What's the weather?"},
    %ImageContent{url: "...", alt: "screenshot"},
    %ToolUse{id: "call_123", name: "get_weather", input: %{city: "NYC"}},
    %ToolResult{tool_use_id: "call_123", content: "72°F, sunny"}
  ],
  metadata: %{
    model: "claude-3-5-sonnet",
    tokens: %{input: 150, output: 42},
    latency_ms: 1234
  }
}
```

This enables:
- Direct serialization to/from LLM APIs (compatible with `req_llm` Context)
- Tool call/response tracking within conversation history
- Rich content mixing (text + images + structured data)
- Agent response metadata (model, tokens, timing)

### 4. Agent Participation Model

AI agents are first-class participants in conversations:

```elixir
%Participant{
  id: "participant_uuid",
  type: :human | :agent | :system,
  identity: %{
    name: "Claude Assistant",
    avatar_url: "...",
    # For agents:
    agent_id: "agent_uuid",
    character_id: "char_uuid",  # From jido_character
    capabilities: [:text, :tool_use, :vision]
  },
  presence: :online | :away | :busy | :offline,
  permissions: %Permissions{...}
}
```

Agents can:
- Join rooms and participate in conversations
- Use tools and report results inline
- Have distinct personalities via `jido_character`
- Auto-moderate based on room rules
- Stream responses in real-time

### 5. Multi-Tenancy & Instance Management

- **Complete isolation** between instances, teams, and clients
- Per-instance configuration (credentials, agent endpoints, settings)
- Instance lifecycle management (create, connect, restart, disconnect)
- Default instance designation for backward compatibility
- Instance health monitoring and auto-recovery

### 6. Room & Conversation Management

Rooms are the primary conversation container:

```elixir
%Room{
  id: "room_uuid",
  type: :direct | :group | :channel | :thread,
  parent_room_id: nil | "parent_uuid",  # For sub-threads
  name: "General Chat",
  topic: "Discuss anything",
  permissions: %RoomPermissions{
    default_role: :member,
    roles: %{
      admin: [:manage_room, :kick, :ban, :pin, :moderate],
      moderator: [:kick, :mute, :pin, :moderate],
      member: [:send, :react, :reply],
      guest: [:read]
    }
  },
  moderation: %ModerationConfig{
    auto_moderate: true,
    moderator_agent_id: "agent_uuid",
    rules: [...],
    actions: [:warn, :delete, :mute, :ban]
  }
}
```

Features:
- **Sub-threads** - Messages can spawn threaded discussions
- **Role-based permissions** - Fine-grained access control
- **Auto-moderation** - AI agent can enforce room rules
- **Typing indicators** - Real-time presence updates

### 7. Access Control & Moderation

Comprehensive permission system:

| Level | Controls |
|-------|----------|
| **Instance** | Who can create rooms, invite users |
| **Room** | Who can join, send, moderate |
| **Participant** | Individual allow/block rules |
| **Message** | Who can edit, delete, react |

Moderation capabilities:
- Allow/block lists per room or globally
- AI-powered auto-moderation with configurable actions
- Audit logging for compliance
- Rate limiting per participant
- Content filtering rules

### 8. Observability & Tracing

- **Complete message lifecycle tracking** - From receipt to delivery
- **Jido Signal integration** - Messages wrapped in signals for ecosystem compatibility
- **Performance metrics** - Processing time, token counts, agent latency
- **Error tracking** - Stage identification, error details
- **Telemetry hooks** - Standard Elixir telemetry events

---

## Domain Model

The domain model is built around **Rooms** containing **Messages** from **Participants**, with **Instances** managing platform connections.

### Core Entities

```
┌─────────────────────────────────────────────────────────────────┐
│                        Instance                                  │
│  (Platform connection - bridges external channels to rooms)     │
├─────────────────────────────────────────────────────────────────┤
│  - id (UUID)                                                    │
│  - name (unique identifier)                                     │
│  - channel_type (:whatsapp | :discord | :slack | :internal)     │
│  - status (:connected | :disconnected | :connecting | :error)   │
│  - credentials (platform-specific, encrypted)                   │
│  - settings (auto_split, webhook_url, etc.)                     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                        Participant                               │
│  (A user or agent that can participate in conversations)        │
├─────────────────────────────────────────────────────────────────┤
│  - id (UUID, stable primary key)                                │
│  - type (:human | :agent | :system)                             │
│  - identity (name, avatar, agent_id, character_id)              │
│  - external_ids (platform-specific identifiers)                 │
│  - presence (:online | :away | :busy | :offline)                │
│  - capabilities ([:text, :tool_use, :vision, :audio])           │
│  - metadata (last_seen_at, session_state)                       │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         Room                                     │
│  (A conversation container - may have sub-threads)              │
├─────────────────────────────────────────────────────────────────┤
│  - id (UUID)                                                    │
│  - type (:direct | :group | :channel | :thread)                 │
│  - parent_room_id (optional, for sub-threads)                   │
│  - name, topic, avatar_url                                      │
│  - permissions (RoomPermissions struct)                         │
│  - moderation (ModerationConfig struct)                         │
│  - instance_bindings (which instances this room bridges to)     │
│  - metadata (created_at, last_message_at, message_count)        │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                        Message                                   │
│  (LLM-native message with rich content support)                 │
├─────────────────────────────────────────────────────────────────┤
│  - id (UUID)                                                    │
│  - room_id (FK → Room)                                          │
│  - thread_id (optional, FK → Room for sub-thread)               │
│  - sender_id (FK → Participant)                                 │
│  - role (:user | :assistant | :system | :tool)                  │
│  - content ([TextContent | ImageContent | ToolUse | ToolResult])│
│  - reply_to_id (optional, for quoted messages)                  │
│  - mentions ([participant_ids])                                 │
│  - reactions ([{emoji, participant_id, timestamp}])             │
│  - status (:sending | :sent | :delivered | :read | :failed)     │
│  - metadata (model, tokens, latency, external_id)               │
│  - timestamps (sent_at, edited_at, deleted_at)                  │
└─────────────────────────────────────────────────────────────────┘
```

### Message Content Types

```elixir
# Text content
%TextContent{text: "Hello, world!"}

# Media content
%ImageContent{url: "...", alt: "description", mime_type: "image/png"}
%AudioContent{url: "...", duration_ms: 5000, transcript: "..."}
%VideoContent{url: "...", duration_ms: 30000, thumbnail_url: "..."}
%DocumentContent{url: "...", filename: "report.pdf", size_bytes: 12345}

# Tool interactions (LLM-native)
%ToolUse{
  id: "call_123",
  name: "search_database",
  input: %{query: "recent orders"}
}

%ToolResult{
  tool_use_id: "call_123",
  content: "Found 5 orders...",
  is_error: false
}

# Structured content
%CardContent{
  title: "Order #12345",
  subtitle: "Shipped",
  fields: [%{label: "ETA", value: "Tomorrow"}],
  actions: [%{label: "Track", url: "..."}]
}
```

### Supporting Entities

```
┌─────────────────────────────────────────────────────────────────┐
│                     RoomMembership                               │
│  (Links participants to rooms with roles)                       │
├─────────────────────────────────────────────────────────────────┤
│  - participant_id (FK → Participant)                            │
│  - room_id (FK → Room)                                          │
│  - role (:admin | :moderator | :member | :guest)                │
│  - joined_at, last_read_message_id                              │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     ExternalId                                   │
│  (Links a Participant to platform-specific identifiers)         │
├─────────────────────────────────────────────────────────────────┤
│  - participant_id (FK → Participant)                            │
│  - provider (:whatsapp | :discord | :telegram | ...)            │
│  - external_id (string - JID, user snowflake, etc.)             │
│  - instance_id (optional, for instance-scoped IDs)              │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     AccessRule                                   │
│  (Allow/block rules for access control)                         │
├─────────────────────────────────────────────────────────────────┤
│  - scope (:global | :instance | :room)                          │
│  - scope_id (instance_id or room_id)                            │
│  - participant_id or identifier_pattern                         │
│  - rule_type (:allow | :block | :mute)                          │
│  - expires_at (optional)                                        │
│  - reason (audit trail)                                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## OTP Process Architecture

Inspired by Juvet's hierarchical supervision model, with adaptations for multi-room and agent management.

```
                        ┌────────────────────────────────────────┐
                        │      JidoMessaging.Application         │
                        └────────────────────┬───────────────────┘
                                             │
        ┌────────────────────────────────────┼────────────────────────────────────┐
        │                                    │                                    │
┌───────▼───────────┐              ┌─────────▼──────────┐              ┌──────────▼─────────┐
│  InstanceManager  │              │   RoomSupervisor   │              │  ParticipantStore  │
│  (Supervisor)     │              │ (DynamicSupervisor)│              │  (GenServer + ETS) │
│                   │              │                    │              │                    │
│ Manages platform  │              │ Creates/supervises │              │ Participant lookup │
│ connections       │              │ room processes     │              │ and presence       │
└───────┬───────────┘              └─────────┬──────────┘              └────────────────────┘
        │                                    │
┌───────▼───────────┐              ┌─────────▼──────────┐
│InstanceSupervisor │              │   Room (GenServer) │ ← One per active room
│ (per instance)    │              │                    │
│                   │              │ - Message history  │
│ - Instance state  │              │ - Participant list │
│ - Receivers       │              │ - Permissions      │
│ - Connection      │              │ - Moderation       │
└───────┬───────────┘              │ - Sub-threads      │
        │                          └─────────┬──────────┘
        │                                    │
┌───────▼───────────┐              ┌─────────▼──────────┐
│ChannelReceiver    │              │  AgentRunner       │
│ (GenServer)       │              │  (GenServer)       │
│                   │              │                    │
│ WhatsApp/Discord/ │              │ Manages agent      │
│ Slack WebSocket   │              │ participation in   │
│ or webhook        │              │ room (if enabled)  │
└───────────────────┘              └────────────────────┘
```

### Key Patterns

**1. Room as GenServer:**
Each active room is a GenServer holding:
- Message history (bounded, configurable)
- Current participants and their presence
- Permissions and moderation config
- References to sub-thread rooms

**2. Instance Isolation:**
Each platform instance has its own supervisor tree:
- Connection state management
- Platform-specific receivers
- Automatic reconnection on failure

**3. Participant Registry:**
ETS-backed participant store for fast lookups:
- Presence tracking
- External ID resolution
- Session state

**4. Agent Integration:**
AgentRunner GenServer per agent in room:
- Subscribes to room messages
- Routes to Jido agent for processing
- Streams responses back to room

---

## Jido Ecosystem Integration

### Signal Integration

Messages are wrapped in `Jido.Signal` for ecosystem compatibility:

```elixir
%Jido.Signal{
  type: "jido.messaging.message.sent",
  source: "/rooms/room_123",
  subject: "/participants/user_456",
  data: %Message{...},
  jidoaction: %{room_id: "room_123", instance_id: "whatsapp_main"}
}
```

Signal types:
- `jido.messaging.message.*` - sent, edited, deleted, reacted
- `jido.messaging.room.*` - created, updated, member_joined, member_left
- `jido.messaging.participant.*` - presence_changed, typing
- `jido.messaging.moderation.*` - warning, mute, ban

### Action Integration

Room operations are `Jido.Action` implementations:

```elixir
defmodule JidoMessaging.Actions.SendMessage do
  use Jido.Action,
    name: "send_message",
    description: "Send a message to a room",
    schema: [
      room_id: [type: :string, required: true],
      content: [type: {:list, :map}, required: true],
      reply_to_id: [type: :string]
    ]
end
```

### Agent Integration

Agents participate via Jido agent framework:

```elixir
# Agent joins room
JidoMessaging.add_agent_to_room(room_id, %{
  agent: MyAgent,
  character: "helpful_assistant",  # From jido_character
  auto_respond: true,
  trigger: :mention  # Respond when @mentioned
})
```

---

## Persistence Adapters

The core is pure Elixir with pluggable persistence:

```elixir
# In-memory for testing
config :jido_messaging, :adapter, JidoMessaging.Adapters.ETS

# PostgreSQL for production
config :jido_messaging, :adapter, JidoMessaging.Adapters.Postgres

# Custom adapter
config :jido_messaging, :adapter, MyApp.CustomAdapter
```

Adapter behaviour:

```elixir
defmodule JidoMessaging.Adapter do
  @callback init(opts :: keyword()) :: {:ok, state} | {:error, reason}
  
  # Messages
  @callback save_message(Message.t()) :: {:ok, Message.t()} | {:error, reason}
  @callback get_messages(room_id, opts) :: {:ok, [Message.t()]} | {:error, reason}
  
  # Rooms
  @callback save_room(Room.t()) :: {:ok, Room.t()} | {:error, reason}
  @callback get_room(room_id) :: {:ok, Room.t()} | {:error, :not_found}
  @callback list_rooms(opts) :: {:ok, [Room.t()]}
  
  # Participants
  @callback save_participant(Participant.t()) :: {:ok, Participant.t()} | {:error, reason}
  @callback get_participant(id) :: {:ok, Participant.t()} | {:error, :not_found}
  @callback find_by_external_id(provider, external_id) :: {:ok, Participant.t()} | {:error, :not_found}
end
```

---

## Rendering Adapters

Chat can be rendered in multiple formats:

### Phoenix LiveView
```elixir
# In your LiveView
def mount(_params, _session, socket) do
  room = JidoMessaging.get_room!(room_id)
  JidoMessaging.subscribe(room_id)
  {:ok, assign(socket, room: room, messages: room.messages)}
end

def handle_info({:message_sent, message}, socket) do
  {:noreply, update(socket, :messages, &[message | &1])}
end
```

### Terminal/IEx TUI
```elixir
# Interactive terminal chat
JidoMessaging.TUI.start(room_id)
# > [Alice]: Hello!
# > [Claude]: Hi Alice, how can I help?
# > _
```

### Headless API
```elixir
# JSON API for external integrations
JidoMessaging.API.send_message(room_id, content, participant_id)
# => {:ok, %Message{}}
```

---

## Channel Behaviour

Each platform implements a common behaviour:

```elixir
defmodule JidoMessaging.Channel do
  @callback connect(instance :: Instance.t()) :: {:ok, state} | {:error, reason}
  @callback disconnect(instance :: Instance.t()) :: :ok | {:error, reason}
  @callback status(instance :: Instance.t()) :: {:ok, ConnectionStatus.t()}
  
  @callback send_message(instance :: Instance.t(), room_external_id, message :: Message.t()) :: 
    {:ok, external_message_id} | {:error, reason}
  
  @callback handle_incoming(raw_payload, state) :: 
    {:message, Message.t()} | {:event, event} | {:error, reason}
  
  @callback transform_outgoing(message :: Message.t()) :: platform_payload
  @callback transform_incoming(platform_payload) :: Message.t()
end
```

---

## Key Design Principles

1. **Agent-first** - AI agents are first-class participants with full capabilities
2. **LLM-native messages** - Content structure maps directly to LLM context formats
3. **Pure Elixir core** - No database required; persistence is an adapter
4. **Jido ecosystem** - Built on signals, actions, and agents
5. **Multi-tenancy by design** - Instance isolation is fundamental
6. **Sub-threads** - Messages can spawn threaded discussions
7. **Comprehensive moderation** - AI-powered moderation built in
8. **Multi-renderer** - Same conversations, multiple UIs

---

## Elixir-Specific Patterns

| Pattern | Use Case |
|---------|----------|
| **GenServer per Room** | Manage room state, messages, participants |
| **DynamicSupervisor** | Spawn rooms and instances on demand |
| **ETS caching** | Fast participant/presence lookups |
| **Registry** | Named process lookup for rooms and instances |
| **Telemetry** | Built-in observability with standard metrics |
| **Broadway** | High-throughput message processing (optional) |
| **Phoenix.PubSub** | Real-time updates across nodes |

---

## Future Considerations

- **Webhook management** - Register/manage webhooks per instance
- **Rate limiting** - Respect platform-specific rate limits
- **Media storage** - Unified media upload/download abstraction
- **Encryption** - End-to-end encryption where supported
- **Presence** - Real-time online/typing indicators
- **Voice integration** - Audio/video call support
- **Federation** - Room bridging across instances

---

## References

- [automagik-omni](https://github.com/namastexlabs/automagik-omni) - Multi-platform feature inspiration
- [Juvet](https://github.com/juvet/juvet) - OTP process architecture patterns
- [jido](https://github.com/agentjido/jido) - Agent framework
- [jido_signal](https://github.com/agentjido/jido_signal) - Signal/event system
- [jido_action](https://github.com/agentjido/jido_action) - Action framework
- [jido_character](https://github.com/agentjido/jido_character) - Agent personalities

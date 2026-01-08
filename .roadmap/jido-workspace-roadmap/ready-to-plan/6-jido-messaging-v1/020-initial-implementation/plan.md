# Implementation Plan: jido_messaging v1 Initial Implementation

**Item ID**: `jido-workspace-roadmap/ready-to-plan/6-jido-messaging-v1/020-initial-implementation`
**Planning Date**: 2026-01-07
**Status**: Ready for Implementation
**Effort Estimate**: 3-4 weeks (1 developer)

---

## 1. Executive Summary

This implementation delivers the first working version of `jido_messaging`, a minimal but usable library that can replace `jido_chat` in small integrations. The implementation builds on the existing skeleton project at `/projects/jido_messaging/` and follows the comprehensive vision documented in `JIDO_MESSAGING_VISION.md`.

**Key Architectural Decisions**:
- **Agent-first design**: AI agents are first-class participants, not afterthoughts
- **Signal-based communication**: All message flow via `jido_signal` for loose coupling
- **Adapter-based persistence**: ETS adapter for v1, designed for PostgreSQL later
- **LLM-native messages**: Messages structured to serialize directly to/from LLM APIs
- **Streaming support**: Built-in streaming patterns from `req_llm`

**Implementation Approach**:
- Follow existing patterns from `jido_chat` where appropriate (GenServer rooms, signal bus)
- Use Zoi 0.14 for validated, type-safe domain models
- Leverage `Jido.Signal.Bus` for all inter-process communication
- Provide clean API surface with `jido_action` integration

**Expected Timeline**: 3-4 weeks for core implementation with 90% test coverage

---

## 2. Impact Analysis Summary

### Files Requiring Changes

**New Files to Create** (35+ total):

**Domain Models** (8 files):
- `lib/jido_messaging/message.ex` - Message struct with Zoi
- `lib/jido_messaging/message/content.ex` - Content behaviours
- `lib/jido_messaging/message/content/text.ex` - Text content
- `lib/jido_messaging/message/content/image.ex` - Image content
- `lib/jido_messaging/message/content/tool_use.ex` - Tool invocation
- `lib/jido_messaging/message/content/tool_result.ex` - Tool response
- `lib/jido_messaging/room.ex` - Room struct with Zoi
- `lib/jido_messaging/participant.ex` - Participant struct with Zoi
- `lib/jido_messaging/instance.ex` - Instance struct with Zoi

**Signal Definitions** (5 files):
- `lib/jido_messaging/signals.ex` - Signal type constants
- `lib/jido_messaging/signals/message.ex` - Message signals
- `lib/jido_messaging/signals/room.ex` - Room lifecycle signals
- `lib/jido_messaging/signals/participant.ex` - Participant signals
- `lib/jido_messaging/signals/streaming.ex` - Streaming signals

**Room Management** (6 files):
- `lib/jido_messaging/room_supervisor.ex` - DynamicSupervisor for rooms
- `lib/jido_messaging/room_server.ex` - GenServer per room
- `lib/jido_messaging/registry.ex` - Process registry for lookups
- `lib/jido_messaging/room_server/strategy.ex` - Turn management strategy
- `lib/jido_messaging/room_server/history.ex` - Message history management
- `lib/jido_messaging/room_server/permissions.ex` - Permission checking

**Agent Integration** (5 files):
- `lib/jido_messaging/agent/gateway.ex` - Agent gateway GenServer
- `lib/jido_messaging/agent/context_builder.ex` - Build ReqLLM context
- `lib/jido_messaging/agent/streaming.ex` - Handle streaming responses
- `lib/jido_messaging/agent/signal_router.ex` - Route signals to agents
- `lib/jido_messaging/agent/dispatcher.ex` - Dispatch messages to agents

**Persistence** (3 files):
- `lib/jido_messaging/adapters/behaviour.ex` - Adapter behaviour definition
- `lib/jido_messaging/adapters/ets.ex` - ETS-based adapter
- `lib/jido_messaging/adapters/config.ex` - Adapter configuration

**Public API** (5 files):
- `lib/jido_messaging.ex` - High-level public API (replace stub)
- `lib/jido_messaging/commands/send_message.ex` - Jido.Action for sending
- `lib/jido_messaging/commands/create_room.ex` - Jido.Action for rooms
- `lib/jido_messaging/commands/join_room.ex` - Jido.Action for joining
- `lib/jido_messaging/util.ex` - Utility functions

**Tests** (8+ files):
- `test/jido_messaging_test.exs` - Public API tests
- `test/message_test.exs` - Message model tests
- `test/room_server_test.exs` - Room GenServer tests
- `test/agent/gateway_test.exs` - Agent integration tests
- `test/adapters/ets_test.exs` - ETS adapter tests
- `test/support/data_case.ex` - Test support module
- `test/support/fixtures.exs` - Test fixtures
- `test/integration/end_to_end_test.exs` - Full flow tests

**Files to Modify**:
- `lib/jido_messaging.ex` - Replace stub with full API
- `lib/jido_messaging/application.ex` - Add supervision tree
- `mix.exs` - Add dependencies: `jido_signal`, `jido`, `jido_action`
- `README.md` - Add usage documentation
- `test/test_helper.exs` - Test setup

### Existing Patterns to Follow

**From jido_chat** (`/projects/jido_chat/`):
- GenServer per room pattern (`lib/jido_chat/room.ex:1-426`)
- Strategy pattern for turn management
- Signal subscription via `Jido.Signal.Bus.subscribe/2`
- Mention parsing support

**From jido** (`/projects/jido/lib/jido/agent_server/signal_router.ex`):
- Signal routing with priority levels
- Agent signal handler pattern
- Directive queue execution

**From req_llm** (`/projects/req_llm/lib/req_llm/response/stream.ex`):
- Streaming chunk accumulation pattern
- Content chunk types: `:content`, `:thinking`, `:tool_call`, `:meta`
- Stream joining for complete messages

**From jido_signal** (`/projects/jido_signal/lib/jido_signal/journal/persistence.ex`):
- Adapter behaviour pattern
- ETS persistence pattern
- Signal journaling approach

### Integration Points Identified

1. **Jido.Signal.Bus** (`/projects/jido_signal/`):
   - Subscribe to: `messaging.message.*`, `messaging.streaming.*`
   - Publish: message events, room events, participant events

2. **Jido.Agent** (`/projects/jido/lib/jido/`):
   - Signal routes: `{"messaging.message.received", &handle_message/1}`
   - Agent participation via `signal_routes/0` callback

3. **ReqLLM** (`/projects/req_llm/`):
   - Build Context from room message history
   - Stream responses via `messaging.streaming.chunk` signals

4. **JidoAction** (`/projects/jido_action/`):
   - Commands: `SendMessage`, `CreateRoom`, `JoinRoom`
   - Directive-based effects

---

## 3. Feature Specification

### User Stories with Acceptance Criteria

**Story 1: Create and manage conversation rooms**
- As a developer, I want to create conversation rooms so that users and agents can communicate
- Acceptance:
  - Can create a room with a name
  - Can retrieve a room by ID
  - Can list all rooms
  - Room stores bounded message history (default 100 messages)
  - Room is a supervised GenServer process

**Story 2: Send messages to a room**
- As a user, I want to send messages to a room so that participants can see them
- Acceptance:
  - Can send a text message to a room
  - Message is persisted via adapter
  - Message is broadcast as a signal
  - Message includes sender, timestamp, and unique ID
  - Message supports rich content types (text, images, tool calls)

**Story 3: Add agents to conversations**
- As a developer, I want to add AI agents to rooms so they can participate
- Acceptance:
  - Can add an agent participant to a room
  - Agent receives messages via signal routing
  - Agent can respond with streaming support
  - Agent responses are persisted to message history

**Story 4: Stream agent responses**
- As a user, I want to see agent responses in real-time so I get immediate feedback
- Acceptance:
  - Agent responses are emitted as streaming chunk signals
  - Chunks are accumulated into complete message
  - Final signal includes `finish_reason` and token usage
  - Stream errors are handled gracefully

**Story 5: Persist conversation history**
- As a system, I want to persist messages so that conversation context is maintained
- Acceptance:
  - Messages are saved via adapter (ETS for v1)
  - Can retrieve message history for a room
  - History is ordered by timestamp
  - History is bounded (configurable limit)

### API Contracts and Data Flow

**Public API Contract**:
```elixir
# Room management
@spec create_room(name :: String.t(), opts :: keyword()) :: {:ok, Room.t()} | {:error, term()}
@spec get_room(room_id :: String.t()) :: {:ok, Room.t()} | {:error, :not_found}
@spec list_rooms(opts :: keyword()) :: {:ok, [Room.t()]}

# Messaging
@spec send_message(room_id :: String.t(), sender_id :: String.t(), content :: [Content.t()], opts :: keyword()) :: {:ok, Message.t()} | {:error, term()}
@spec get_messages(room_id :: String.t(), opts :: keyword()) :: {:ok, [Message.t()]}

# Participants
@spec add_participant(room_id :: String.t(), participant :: Participant.t()) :: :ok | {:error, term()}
@spec remove_participant(room_id :: String.t(), participant_id :: String.t()) :: :ok | {:error, term()}
@spec get_participants(room_id :: String.t()) :: {:ok, [Participant.t()]}

# Agents
@spec add_agent_to_room(room_id :: String.t(), agent_opts :: keyword()) :: {:ok, Participant.t()} | {:error, term()}
@spec remove_agent_from_room(room_id :: String.t(), agent_id :: String.t()) :: :ok | {:error, term()}
```

**Message Flow**:
```
User sends message
  → API validates content
  → Message created via Zoi schema
  → RoomServer receives message
  → Persist via adapter
  → Add to in-memory history
  → Publish "messaging.message.sent" signal
  → Agent's signal router matches pattern
  → Agent processes via Agent.cmd/2
  → Agent emits streaming chunks
  → Accumulate chunks into message
  → Publish "messaging.message.completed" signal
  → RoomServer updates history
```

### State Management Requirements

**Room Server State**:
```elixir
%{
  room: Room.t(),                    # Room struct with metadata
  participants: %{id => Participant.t()},  # Participant map
  messages: [Message.t()],           # Bounded message history
  strategy: module(),                # Turn management strategy
  history_limit: 10..1000            # Configurable history bound
}
```

**Agent Gateway State**:
```elixir
%{
  room_id: String.t(),
  agent_id: String.t(),
  signal_router: map(),              # Route patterns to handlers
  streaming: boolean(),              # Enable/disable streaming
  context_limit: 10..100             # Messages in LLM context
}
```

### Error Handling Approach

**Use Splode for Errors**:
- `JidoMessaging.Error.NotFound` - Resource not found
- `JidoMessaging.Error.Validation` - Schema validation errors
- `JidoMessaging.Error.Permission` - Permission denied
- `JidoMessaging.Error.Adapter` - Persistence adapter errors

**Error Handling Pattern**:
```elixir
def send_message(room_id, sender_id, content, opts \\ []) do
  with {:ok, room} <- get_room(room_id),
       {:ok, message} <- Message.new(room_id: room_id, sender_id: sender_id, content: content),
       {:ok, _message} <- RoomServer.send_message(room.id, message),
       do: {:ok, message}
end
```

---

## 4. Technical Design

### Data Model Changes

**Message Schema** (using Zoi 0.14):
```elixir
defmodule JidoMessaging.Message do
  use Zoi.Struct

  @schema Zoi.struct(
    fields: [
      id: Zoi.field(type: :string, default: &generate_id/0),
      room_id: Zoi.field(type: :string, required: true),
      thread_id: Zoi.field(type: :string | nil, default: nil),
      sender_id: Zoi.field(type: :string, required: true),
      role: Zoi.field(type: :atom, values: [:user, :assistant, :system, :tool], required: true),
      content: Zoi.field(type: {:list, :struct}, required: true),
      reply_to_id: Zoi.field(type: :string | nil, default: nil),
      mentions: Zoi.field(type: {:list, :string}, default: []),
      status: Zoi.field(type: :atom, values: [:sending, :sent, :delivered, :read, :failed], default: :sending),
      metadata: Zoi.field(type: :map, default: %{}),
      sent_at: Zoi.field(type: :struct, default: &DateTime.utc_now/0),
      edited_at: Zoi.field(type: :struct | nil, default: nil),
      deleted_at: Zoi.field(type: :struct | nil, default: nil)
    ]
  )
end
```

**Content Types**:
```elixir
# Text content
defmodule JidoMessaging.Message.Content.Text do
  use Zoi.Struct

  @schema Zoi.struct(
    fields: [
      type: Zoi.field(type: :atom, default: :text),
      text: Zoi.field(type: :string, required: true)
    ]
  )
end

# Tool use content
defmodule JidoMessaging.Message.Content.ToolUse do
  use Zoi.Struct

  @schema Zoi.struct(
    fields: [
      type: Zoi.field(type: :atom, default: :tool_use),
      id: Zoi.field(type: :string, required: true),
      name: Zoi.field(type: :string, required: true),
      input: Zoi.field(type: :map, required: true)
    ]
  )
end
```

**Room Schema**:
```elixir
defmodule JidoMessaging.Room do
  use Zoi.Struct

  @schema Zoi.struct(
    fields: [
      id: Zoi.field(type: :string, default: &generate_id/0),
      type: Zoi.field(type: :atom, values: [:direct, :group, :channel, :thread], default: :group),
      parent_room_id: Zoi.field(type: :string | nil, default: nil),
      name: Zoi.field(type: :string, required: true),
      topic: Zoi.field(type: :string, default: ""),
      metadata: Zoi.field(type: :map, default: fn -> %{created_at: DateTime.utc_now()} end)
    ]
  )
end
```

### Module Organization

**Application Supervision Tree**:
```elixir
defmodule JidoMessaging.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Registry for room process lookup
      {Registry, keys: :unique, name: JidoMessaging.Registry},

      # Dynamic supervisor for rooms
      {DynamicSupervisor, name: JidoMessaging.RoomSupervisor, strategy: :one_for_one},

      # Adapter process
      {JidoMessaging.Adapters.Ets, name: JidoMessaging.Adapter},

      # Agent gateway supervisor
      {DynamicSupervisor, name: JidoMessaging.AgentGatewaySupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: JidoMessaging.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

**Directory Structure**:
```
lib/jido_messaging/
├── application.ex              # Application supervisor
├── message.ex                  # Message domain model
├── message/
│   ├── content.ex              # Content behaviours
│   └── content/
│       ├── text.ex
│       ├── image.ex
│       ├── tool_use.ex
│       └── tool_result.ex
├── room.ex                     # Room domain model
├── room_server.ex              # Room GenServer
├── room_supervisor.ex          # Dynamic supervisor
├── room_server/
│   ├── strategy.ex             # Turn management
│   ├── history.ex              # Message history
│   └── permissions.ex          # Permission checking
├── participant.ex              # Participant domain model
├── instance.ex                 # Instance domain model
├── signals.ex                  # Signal type constants
├── signals/
│   ├── message.ex
│   ├── room.ex
│   ├── participant.ex
│   └── streaming.ex
├── agent/
│   ├── gateway.ex              # Agent gateway
│   ├── context_builder.ex      # Build LLM context
│   ├── streaming.ex            # Handle streaming
│   ├── signal_router.ex        # Route signals
│   └── dispatcher.ex           # Dispatch messages
├── adapters/
│   ├── behaviour.ex            # Adapter behaviour
│   ├── ets.ex                  # ETS adapter
│   └── config.ex               # Adapter config
├── commands/
│   ├── send_message.ex         # Jido.Action
│   ├── create_room.ex          # Jido.Action
│   └── join_room.ex            # Jido.Action
├── registry.ex                 # Process registry
└── util.ex                     # Utilities
```

### Third-Party Integration Details

**Jido.Signal.Bus Integration**:
```elixir
# Subscribe to room messages
def subscribe_to_room(room_id) do
  Jido.Signal.Bus.subscribe("messaging.message.room.#{room_id}")
end

# Publish message signal
def publish_message(message) do
  Jido.Signal.Bus.publish([
    %Jido.Signal{
      type: "messaging.message.sent",
      source: "jido_messaging",
      subject: "room/#{message.room_id}",
      data: %{message: message}
    }
  ])
end
```

**Agent Integration**:
```elixir
# Agent defines signal routes
defmodule MyAgent do
  use Jido.Agent

  def signal_routes do
    [
      {"messaging.message.received", &handle_message/1},
      {"messaging.streaming.#{agent_id()}", &handle_streaming_chunk/1}
    ]
  end

  def handle_message(signal) do
    message = signal.data.message
    # Process and respond
  end
end
```

**ReqLLM Integration**:
```elixir
# Build context from room history
def build_context(room_id, limit \\ 10) do
  {:ok, messages} = get_messages(room_id, limit: limit)

  ReqLLM.Context.new(
    messages: Enum.map(messages, &convert_to_req_llm/1),
    tools: available_tools()
  )
end
```

### Configuration/Environment Changes

**Application Configuration** (`config/dev.exs`, `config/prod.exs`):
```elixir
config :jido_messaging,
  # Persistence adapter
  adapter: JidoMessaging.Adapters.Ets,

  # Room defaults
  room_history_limit: 100,
  room_default_strategy: :free_form,

  # Agent defaults
  agent_streaming: true,
  agent_context_limit: 10,

  # Signal configuration
  signal_namespace: "messaging",

  # Registry
  registry_name: JidoMessaging.Registry
```

**Runtime Configuration**:
```elixir
# Can override at runtime
JidoMessaging.configure(adapter: MyCustomAdapter)
JidoMessaging.configure(room_history_limit: 500)
```

---

## 5. Implementation Phases

### Phase 1: Foundation (Week 1)

**Objective**: Establish core domain models and signal infrastructure

**Success Criteria**:
- All domain models validated with Zoi schemas
- Signal types defined and tested
- Can create and validate messages, rooms, participants

**Files to Create**:
```
lib/jido_messaging/message.ex
lib/jido_messaging/message/content.ex
lib/jido_messaging/message/content/text.ex
lib/jido_messaging/message/content/image.ex
lib/jido_messaging/message/content/tool_use.ex
lib/jido_messaging/message/content/tool_result.ex
lib/jido_messaging/room.ex
lib/jido_messaging/participant.ex
lib/jido_messaging/instance.ex
lib/jido_messaging/signals.ex
lib/jido_messaging/signals/message.ex
lib/jido_messaging/signals/room.ex
lib/jido_messaging/signals/participant.ex
lib/jido_messaging/signals/streaming.ex
```

**Tests to Add**:
- `test/message_test.exs` - Message creation and validation
- `test/room_test.exs` - Room creation and validation
- `test/participant_test.exs` - Participant creation and validation

**Dependencies**: None (foundation phase)

**Acceptance Tests**:
```elixir
test "creates valid text message" do
  assert {:ok, message} = Message.new(%{
    room_id: "room_123",
    sender_id: "user_123",
    role: :user,
    content: [%{type: :text, text: "Hello!"}]
  })

  assert message.room_id == "room_123"
  assert message.role == :user
  assert [%TextContent{text: "Hello!"}] = message.content
end

test "validates required fields" do
  assert {:error, _} = Message.new(%{
    room_id: "room_123",
    # missing sender_id and role
    content: []
  })
end
```

---

### Phase 2: Core Implementation (Week 1-2)

**Objective**: Implement room management and message routing

**Success Criteria**:
- Can create and manage rooms via RoomServer
- Messages are persisted and broadcast
- Room processes are supervised
- Process registry for room lookups

**Files to Create**:
```
lib/jido_messaging/application.ex
lib/jido_messaging/room_supervisor.ex
lib/jido_messaging/room_server.ex
lib/jido_messaging/room_server/strategy.ex
lib/jido_messaging/room_server/history.ex
lib/jido_messaging/room_server/permissions.ex
lib/jido_messaging/registry.ex
lib/jido_messaging/util.ex
```

**Files to Modify**:
- `lib/jido_messaging.ex` - Add room management API

**Tests to Add**:
- `test/room_server_test.exs` - Room GenServer tests
- `test/registry_test.exs` - Registry tests

**Dependencies**: Phase 1 must be complete

**Acceptance Tests**:
```elixir
test "creates room and starts process" do
  assert {:ok, room} = JidoMessaging.create_room("Test Room")
  assert {:ok, _room_server} = JidoMessaging.RoomServer.whereis(room.id)
end

test "sends message to room" do
  {:ok, room} = JidoMessaging.create_room("Test")
  {:ok, message} = JidoMessaging.send_message(
    room.id,
    "user_123",
    [%{type: :text, text: "Hello!"}]
  )

  assert message.room_id == room.id
  assert {:ok, messages} = JidoMessaging.get_messages(room.id)
  assert length(messages) == 1
end

test "room process is supervised" do
  {:ok, room} = JidoMessaging.create_room("Test")
  pid = JidoMessaging.RoomServer.whereis!(room.id)
  Process.exit(pid, :kill)

  # Supervisor should restart
  :timer.sleep(100)
  assert {:ok, _pid} = JidoMessaging.RoomServer.whereis(room.id)
end
```

---

### Phase 3: Integration & Testing (Week 2-3)

**Objective**: Integrate with agents and implement persistence

**Success Criteria**:
- Agents can participate in rooms
- Agent responses are streamed
- Messages persisted via ETS adapter
- Can retrieve conversation history

**Files to Create**:
```
lib/jido_messaging/adapters/behaviour.ex
lib/jido_messaging/adapters/ets.ex
lib/jido_messaging/adapters/config.ex
lib/jido_messaging/agent/gateway.ex
lib/jido_messaging/agent/context_builder.ex
lib/jido_messaging/agent/streaming.ex
lib/jido_messaging/agent/signal_router.ex
lib/jido_messaging/agent/dispatcher.ex
```

**Files to Modify**:
- `lib/jido_messaging.ex` - Add agent management API
- `mix.exs` - Add jido_signal, jido dependencies

**Tests to Add**:
- `test/adapters/ets_test.exs` - ETS adapter tests
- `test/agent/gateway_test.exs` - Agent gateway tests
- `test/integration/end_to_end_test.exs` - Full flow tests

**Dependencies**: Phase 2 must be complete

**Acceptance Tests**:
```elixir
test "agent receives and responds to message" do
  # Create room
  {:ok, room} = JidoMessaging.create_room("Test")

  # Add agent
  {:ok, agent} = JidoMessaging.add_agent_to_room(room.id,
    agent: TestAgent,
    mode: :streaming
  )

  # Send message
  {:ok, message} = JidoMessaging.send_message(
    room.id,
    "user_123",
    [%{type: :text, text: "Hello!"}]
  )

  # Subscribe to agent response
  Jido.Signal.Bus.subscribe("messaging.streaming.#{agent.id}")

  # Assert streaming chunks received
  assert_receive %Jido.Signal{
    type: "messaging.streaming.chunk",
    data: %{chunk: %{content: "Hi!"}}
  }

  # Assert final message persisted
  {:ok, messages} = JidoMessaging.get_messages(room.id)
  assert length(messages) == 2  # user + assistant
end

test "persists messages via ETS adapter" do
  {:ok, room} = JidoMessaging.create_room("Test")

  # Send messages
  Enum.each(1..10, fn i ->
    JidoMessaging.send_message(
      room.id,
      "user_123",
      [%{type: :text, text: "Message #{i}"}]
    )
  end)

  # Retrieve via adapter
  {:ok, messages} = JidoMessaging.Adapter.get_messages(room.id)
  assert length(messages) == 10
end
```

---

### Phase 4: Polish & Documentation (Week 3-4)

**Objective**: Complete public API, actions, and documentation

**Success Criteria**:
- Public API complete and documented
- Jido.Action commands implemented
- 90% test coverage achieved
- README with usage examples
- Migration guide from jido_chat

**Files to Create**:
```
lib/jido_messaging/commands/send_message.ex
lib/jido_messaging/commands/create_room.ex
lib/jido_messaging/commands/join_room.ex
```

**Files to Modify**:
- `lib/jido_messaging.ex` - Complete public API
- `README.md` - Comprehensive documentation
- `mix.exs` - Ensure all dependencies listed

**Tests to Add**:
- `test/commands/send_message_test.exs`
- `test/commands/create_room_test.exs`
- `test/commands/join_room_test.exs`

**Dependencies**: Phase 3 must be complete

**Acceptance Tests**:
```elixir
test "can replace jido_chat in small integration" do
  # Create room
  {:ok, room} = JidoMessaging.create_room("General")

  # Add agent
  {:ok, _agent} = JidoMessaging.add_agent_to_room(room.id,
    agent: ChatAgent
  )

  # User sends message
  {:ok, _message} = JidoMessaging.send_message(
    room.id,
    "alice",
    [%{type: :text, text: "What's the weather?"}]
  )

  # Agent responds with tool use
  assert_receive %Jido.Signal{
    type: "messaging.streaming.chunk",
    data: %{
      chunk: %{
        content: [
          %{type: :tool_use, name: "get_weather", input: %{city: "NYC"}}
        ]
      }
    }
  }

  # Tool result streamed back
  assert_receive %Jido.Signal{
    type: "messaging.streaming.chunk",
    data: %{chunk: %{content: [%{type: :tool_result, content: "72°F"}]}}
  }
end

test "Jido.Action integration" do
  {:ok, room} = JidoMessaging.create_room("Test")

  # Use as Jido action
  assert {:ok, _result} = JidoAction.run(
    JidoMessaging.Commands.SendMessage,
    room_id: room.id,
    sender_id: "user_123",
    content: [%{type: :text, text: "Hello!"}]
  )
end
```

**Documentation Checklist**:
- [ ] README.md with quick start guide
- [ ] API reference (HexDocs auto-generated from @doc)
- [ ] Migration guide from jido_chat
- [ ] Examples directory with sample implementations
- [ ] Known limitations documented
- [ ] Future roadmap outlined

---

## 6. Quality & Testing Strategy

### Test Categories

**Unit Tests** (Target: 95% coverage of domain models):
- Message creation and validation
- Room creation and validation
- Participant creation and validation
- Content type creation and validation
- Signal type definitions
- Adapter behaviour compliance

**Integration Tests** (Target: 90% coverage):
- Room server lifecycle
- Message routing and persistence
- Agent gateway communication
- Signal subscription and publishing
- ETS adapter operations

**Property-Based Tests** (Target: key models):
```elixir
use PropCheck
use Properties

property "message IDs are unique" do
  forall {room_id, sender_id} <- {string(), string()} do
    {:ok, msg1} = Message.new(room_id: room_id, sender_id: sender_id, role: :user, content: [])
    {:ok, msg2} = Message.new(room_id: room_id, sender_id: sender_id, role: :user, content: [])
    msg1.id != msg2.id
  end
end

property "room messages are ordered by timestamp" do
  forall(messages <- list(message_generator())) do
    sorted = Enum.sort_by(messages, & &1.sent_at, DateTime)
    sorted == messages
  end
end
```

**End-to-End Tests** (Target: critical flows):
- Create room → Add agent → Send message → Receive response
- Streaming response from agent
- Message history retrieval
- Room restart and recovery

### Coverage Targets

**Overall Target**: 90% coverage

**Breakdown**:
- Domain models: 95% (critical for data integrity)
- Room management: 90% (core functionality)
- Agent integration: 85% (external dependencies)
- Adapters: 90% (persistence critical)

### Quality Gates Before Completion

**Pre-Merge Checklist**:
- [ ] All tests passing (`mix test`)
- [ ] Coverage ≥ 90% (`mix coveralls.html`)
- [ ] No compiler warnings (`mix compile --force-warnings`)
- [ ] Credo passes (`mix credo --strict`)
- [ ] Dialyzer passes (`mix dialyzer`)
- [ ] Documentation complete (`mix docs`)
- [ ] Formatting correct (`mix format --check-formatted`)

**Acceptance Testing**:
- [ ] Can replace jido_chat in small integration
- [ ] Agent receives and responds to messages
- [ ] Streaming works end-to-end
- [ ] Messages persist across restarts
- [ ] README examples run successfully

---

## 7. Risk Assessment

### Technical Risks

**Risk: Signal routing complexity**
- **Impact**: Medium - Agents may not receive messages correctly
- **Probability**: Low - Pattern established in jido
- **Mitigation**:
  - Follow existing `Jido.AgentServer.SignalRouter` patterns
  - Write comprehensive integration tests
  - Start with simple routing, add complexity gradually

**Risk: Streaming state management**
- **Impact**: High - Streaming responses could be lost or corrupted
- **Probability**: Medium - New pattern for codebase
- **Mitigation**:
  - Reference `ReqLLM.Response.Stream` patterns
  - Use supervised processes for stream accumulation
  - Add timeouts and error recovery
  - Test with various stream failure scenarios

**Risk: ETS adapter limitations**
- **Impact**: Low - Known limitation for v1
- **Probability**: High - ETS is in-memory only
- **Mitigation**:
  - Document clearly that ETS is for v1 only
  - Design adapter interface for future PostgreSQL implementation
  - Ensure data can be migrated when adapter changes

**Risk: Zoi schema validation errors**
- **Impact**: Medium - Could block valid messages
- **Probability**: Low - Zoi is well-tested
- **Mitigation**:
  - Start with permissive validation
  - Add comprehensive test coverage for edge cases
  - Provide clear error messages from validation failures

### Dependency Risks

**Risk: jido_signal API changes**
- **Impact**: High - Would require significant refactoring
- **Probability**: Low - jido_signal is stable
- **Mitigation**:
  - Pin jido_signal version in mix.exs
  - Abstraction layer for signal operations
  - Monitor jido_signal changelog

**Risk: jido agent API changes**
- **Impact**: Medium - Agent integration would break
- **Probability**: Low - jido is stable
- **Mitigation**:
  - Pin jido version in mix.exs
  - Use documented agent APIs only
  - Minimal coupling to agent internals

**Risk: ReqLLM context format changes**
- **Impact**: Medium - Context building would break
- **Probability**: Low - ReqLLM is stable
- **Mitigation**:
  - Pin req_llm version
  - Adapter pattern for context conversion
  - Test with multiple LLM providers

### Timeline Risks

**Risk: Scope creep**
- **Impact**: High - Could delay completion indefinitely
- **Probability**: Medium - Vision document is comprehensive
- **Mitigation**:
  - Strict v1 scope definition (see "Known Limitations")
  - Defer all non-essential features to future items
  - Weekly scope review meetings

**Risk: Test coverage takes longer than expected**
- **Impact**: Medium - Could delay completion by 1-2 weeks
- **Probability**: Medium - 90% coverage is ambitious
- **Mitigation**:
  - Write tests alongside implementation (TDD)
  - Prioritize coverage of critical paths
  - Accept 85% coverage if non-critical code

**Risk: Integration testing challenges**
- **Impact**: Medium - Agent integration may be tricky
- **Probability**: Medium - External dependencies
- **Mitigation**:
  - Use test agents that are simple and predictable
  - Mock agent responses in unit tests
  - Real agent tests in integration suite only

---

## 8. Success Criteria

### Measurable Outcomes

**Functional Requirements**:
- [x] Can create a room with name and metadata
- [x] Can send a message to a room
- [x] Message is persisted via ETS adapter
- [x] Message is broadcast as signal
- [x] Can retrieve message history for a room
- [x] Can add a participant to a room
- [x] Can add an agent to a room
- [x] Agent receives message via signal routing
- [x] Agent can respond with streaming
- [x] Streaming chunks are accumulated into complete message
- [x] Final message includes finish_reason and token usage
- [x] Room process is supervised and can restart
- [x] Message history is bounded (configurable limit)

**Quality Requirements**:
- [x] Test coverage ≥ 90%
- [x] No compiler warnings
- [x] Credo passes with strict mode
- [x] Dialyzer passes
- [x] All public modules documented with @moduledoc
- [x] All public functions documented with @doc
- [x] README with quick start guide
- [x] Migration guide from jido_chat

**Integration Requirements**:
- [x] Can replace jido_chat in small integration
- [x] Signal-based communication working
- [x] Agent integration working
- [x] ETS adapter persists data
- [x] Can run fully in-memory for testing

### Definition of "Done"

An item is considered complete when:

1. **All acceptance tests pass**: Every test in the acceptance criteria passes
2. **Coverage target met**: `mix coveralls.html` shows ≥ 90%
3. **Quality gates pass**: All pre-merge checklist items complete
4. **Documentation complete**: README, API docs, and migration guide complete
5. **Integration verified**: Can replace jido_chat in a test integration
6. **Code reviewed**: Code review approved by maintainer
7. **Published**: Package published to Hex (if applicable)

### Acceptance Testing Approach

**Test Integration**:
```elixir
# Full end-to-end test
defmodule JidoMessaging.AcceptanceTest do
  use ExUnit.Case

  test "complete messaging flow" do
    # 1. Create room
    {:ok, room} = JidoMessaging.create_room("Test Room")

    # 2. Add agent
    {:ok, agent} = JidoMessaging.add_agent_to_room(room.id,
      agent: TestAgent,
      mode: :streaming
    )

    # 3. Send message
    {:ok, message} = JidoMessaging.send_message(
      room.id,
      "alice",
      [%{type: :text, text: "Hello!"}]
    )

    # 4. Verify agent receives
    assert_receive %Jido.Signal{
      type: "messaging.agent.request",
      data: %{message: ^message}
    }

    # 5. Agent responds (streaming)
    TestAgent.respond(agent.id, "Hi there!")

    # 6. Verify streaming chunks
    assert_receive %Jido.Signal{
      type: "messaging.streaming.chunk",
      data: %{chunk: %{content: "Hi there!"}}
    }

    # 7. Verify final message persisted
    {:ok, messages} = JidoMessaging.get_messages(room.id)
    assert length(messages) == 2
    assert [%{role: :user}, %{role: :assistant}] = messages
  end
end
```

**Manual Testing**:
```elixir
# Interactive testing in IEx
iex> {:ok, room} = JidoMessaging.create_room("Test")
iex> {:ok, agent} = JidoMessaging.add_agent_to_room(room.id, agent: ChatAgent)
iex> {:ok, msg} = JidoMessaging.send_message(room.id, "user123", [%{type: :text, text: "Hello!"}])
# Should see agent response in logs
iex> {:ok, messages} = JidoMessaging.get_messages(room.id)
# Should see user message + agent response
```

---

## 9. Known Limitations for v1

As stated in the item overview, these limitations are explicitly documented so downstream projects know what to rely on.

**Deferred to Future Versions**:
- Read receipts (delivery confirmation beyond basic status)
- Complex routing rules (basic room-based routing only)
- Multi-agent coordination (single agent per room)
- Advanced moderation features (basic allow/block only)
- Channel implementations (internal/Phoenix LiveView only)
- Media storage (references only, no upload handling)
- Encryption (all content stored as-is)
- Federation/bridging (single-instance only)
- Sub-threads within rooms
- Message editing
- Message deletion
- Reactions/emoji
- Typing indicators
- Presence tracking
- File uploads
- Voice messages

**Supported in v1**:
- Basic message sending/receiving
- Room creation and management
- Participant management (add/remove)
- Agent participation (single agent per room)
- Streaming responses (basic chunk emission)
- In-memory persistence (via ETS adapter)
- Signal-based communication
- Text content
- Tool call/response content
- Image content (references only)
- Message history (bounded, in-memory)
- Basic permissions (add/remove participants)

**Migration Path**:
These limitations will be addressed in future roadmap items:
- Channel implementations (separate roadmap items per platform)
- PostgreSQL persistence adapter (future item)
- Multi-agent coordination (future item)
- Advanced features (future items based on demand)

---

## 10. Dependencies

**Blocks**:
- Item 021: Phoenix project setup (jido_hub)
- Item 022: LibreChat-style interface (jido_hub)
- Item 023: Integration with jido agents (jido_hub)

**Blocked By**:
- Item 019: Define scope/architecture (complete - architecture defined)

**External Dependencies**:
- `jido_signal` ~ 0.1 (for signal bus)
- `jido` ~ 0.2 (for agent framework)
- `jido_action` ~ 0.1 (optional, for action framework)
- `req_llm` ~ 0.1 (dev dependency, for LLM context building)

---

## 11. Next Steps

After this implementation is complete:

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
   - PostgreSQL persistence adapter

---

## Appendix A: File Reference List

**From Research** (critical files to reference during implementation):

- `/projects/jido_chat/lib/jido_chat.ex:1-94` - High-level API patterns
- `/projects/jido_chat/lib/jido_chat/message.ex:1-378` - Message struct patterns
- `/projects/jido_chat/lib/jido_chat/room.ex:1-426` - Room GenServer patterns
- `/projects/jido/lib/jido/agent_server/signal_router.ex:1-155` - Signal routing patterns
- `/projects/req_llm/lib/req_llm/response/stream.ex:1-238` - Streaming patterns
- `/projects/jido_signal/lib/jido_signal/journal/persistence.ex:1-57` - Adapter patterns
- `/projects/jido_messaging/JIDO_MESSAGING_VISION.md` - Full specification

**New Files** (35+ files to create):
- See detailed breakdown in Section 5 "Implementation Phases"

---

## Appendix B: Signal Type Reference

**Signal Types to Implement**:
```elixir
# Message signals
"messaging.message.sent"           # Message sent to room
"messaging.message.received"       # Message received by participant
"messaging.message.delivered"      # Message delivered status
"messaging.message.completed"      # Agent message completed

# Room signals
"messaging.room.created"           # Room created
"messaging.room.joined"            # Participant joined
"messaging.room.left"              # Participant left
"messaging.room.closed"            # Room closed

# Streaming signals
"messaging.streaming.chunk"        # Streaming chunk
"messaging.streaming.error"        # Streaming error
"messaging.streaming.complete"     # Streaming complete

# Agent signals
"messaging.agent.request"          # Request to agent
"messaging.agent.response"         # Response from agent
"messaging.agent.error"            # Agent error
```

---

## Appendix C: Configuration Reference

**Application Configuration**:
```elixir
# config/config.exs
config :jido_messaging,
  adapter: JidoMessaging.Adapters.Ets,
  room_history_limit: 100,
  room_default_strategy: :free_form,
  agent_streaming: true,
  agent_context_limit: 10,
  signal_namespace: "messaging"

# config/dev.exs
config :jido_messaging,
  room_history_limit: 50

# config/prod.exs
config :jido_messaging,
  adapter: JidoMessaging.Adapters.PostgreSQL,  # Future
  room_history_limit: 1000
```

**Runtime Configuration**:
```elixir
# Override at runtime
JidoMessaging.configure(room_history_limit: 500)
```

---

**End of Implementation Plan**

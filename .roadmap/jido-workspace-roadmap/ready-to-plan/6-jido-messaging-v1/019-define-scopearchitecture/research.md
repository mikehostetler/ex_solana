# Research: jido_messaging v1 Architecture Definition

**Item ID**: `jido-workspace-roadmap/ready-to-plan/6-jido-messaging-v1/019-define-scopearchitecture`
**Research Date**: 2025-01-07
**Status**: Complete

## Executive Summary

This research analyzes the existing `jido_chat` implementation and provides architectural recommendations for `jido_messaging` v1, a new messaging layer designed to replace `jido_chat` with a signal-driven, multi-channel architecture.

---

## 1. Existing jido_chat Implementation Analysis

### Core Components & File Locations

The current `jido_chat` implementation is located in `/projects/jido_chat/` with the following core modules:

**Key Files:**
- `/projects/jido_chat/lib/jido_chat.ex` - Main API module
- `/projects/jido_chat/lib/jido_chat/message.ex` - Message struct and handling
- `/projects/jido_chat/lib/jido_chat/conversation.ex` - Conversation/room management
- `/projects/jido_chat/lib/jido_chat/room.ex` - Room server implementation
- `/projects/jido_chat/lib/jido_chat/participant.ex` - Participant management

### Current Architecture Strengths

1. **OTP-based supervision** with proper GenServer patterns
2. **Registry-based naming** for room lookups
3. **Event-driven design** with basic emit/subscribe patterns
4. **Structured data model** using Zoi for validation
5. **Multi-participant support** with role-based permissions

### Pain Points Driving Redesign

1. **Limited signal integration** - Custom event system vs. jido_signal
2. **Channel-specific coupling** - WhatsApp-specific logic mixed with core chat
3. **Scalability issues** - Single supervisor for all rooms
4. **Limited streaming support** - Basic message passing without streaming
5. **No multi-tenancy** - All instances share configuration

### Current Message Flow

```
User -> Channel -> RoomServer -> (Simple routing) -> Agent -> Response
```

The current system uses direct GenServer calls between components with basic message routing.

---

## 2. Jido Agent Integration Patterns

### Agent Communication Architecture

Jido agents communicate through a sophisticated signal routing system:

**Key Files:**
- `/projects/jido/lib/jido/agent_server/signal_router.ex` - Signal routing with trie-based router
- `/projects/jido/lib/jido/agent_server.ex` - Main agent runtime
- `/projects/jido_signal/lib/jido_signal/bus.ex` - Central signal bus

### Signal Routing Pattern

The system uses a priority-based routing approach:

| Source | Default Priority | Range |
|--------|------------------|-------|
| Strategy | 50 | 50-100 |
| Agent | 0 | -25 to 25 |
| Skill | -10 | -50 to -10 |

### Agent Message Handling

1. **Signal Receipt**: Agents receive signals via `AgentServer.call/cast`
2. **Route Processing**: SignalRouter matches signal paths to handlers
3. **Agent Command**: Signal routed to `Agent.cmd/2` for processing
4. **Directive Execution**: Results executed via directive queue

### Integration Points

```elixir
# Agent signal routes define how messages are handled
defmodule MyAgent do
  def signal_routes do
    [
      # Route messages to specific handlers
      {"chat.message", &handle_chat/1},
      {"system.command", &handle_command/1}
    ]
  end
end
```

---

## 3. Related Projects & Infrastructure

### jido_signal - The Foundation

**Location**: `/projects/jido_signal/`

**Key Components:**
- **Signal Bus**: Central hub for signal distribution
- **Signal Router**: Trie-based routing for efficient signal matching
- **Journal System**: Persistent signal storage with replay capability
- **Middleware Pipeline**: Transform signals before processing

**Architecture Benefits:**
- Decoupled component communication
- Persistent signal history for debugging
- Efficient routing with path-based matching
- Middleware for cross-cutting concerns

### jido - Core Agent Framework

**Location**: `/projects/jido/`

**Integration Points:**
- **AgentServer**: GenServer runtime for agents
- **Directive System**: Asynchronous action execution
- **Strategy Pattern**: High-level agent behavior
- **Registry**: Process naming and discovery

---

## 4. Architectural Recommendations for jido_messaging v1

### Core Design Principles

1. **Signal-First Architecture**: All communication via `Jido.Signal.Bus`
2. **Layered Separation**: Clear boundaries between concerns
3. **Multi-tenant Ready**: Instance-level isolation from day one
4. **Streaming Native**: Built-in support for streaming responses
5. **Channel Agnostic**: Normalized message model across all platforms

### Proposed Architecture

```
Layer 6: APIs & Admin (Phoenix controllers)
Layer 5: Signal Events (jido_signal)
Layer 4: Agent Gateway (ReqLLM + Jido.Character)
Layer 3: Conversation & Routing (Rooms, Middleware)
Layer 2: Channel Normalization (Edge adapters)
Layer 1: Core Domain (Instances, Rooms, Participants)
```

### Core Domain Model

#### Message Envelope Structure

```elixir
defmodule Jido.Messaging.Message do
  @moduledoc """
  Normalized message envelope for all platforms.
  """

  use Zoi.Struct

  @schema Zoi.struct(
    id: {:string, required: true},
    thread_id: {:string, required: false},      # Conversation threading
    from: {:map, required: true},              # Participant reference
    to: {:list, item_type: :map, default: []}, # Recipients
    role: {:enum, values: [:user, :assistant, :system, :tool]},
    content: {:map, required: true},            # Platform-agnostic content
    metadata: {:map, default: %{}},             # Routing metadata
    timestamp: {:datetime, required: true},
    delivery_state: {:enum, values: [:pending, :delivered, :failed]}
  )
end
```

#### Thread Management

```elixir
defmodule Jido.Messaging.Thread do
  @moduledoc """
  Conversation thread with bounded history.
  """

  use Zoi.Struct

  @schema Zoi.struct(
    id: {:string, required: true},
    instance_id: {:string, required: true},
    participants: {:list, item_type: :map},
    messages: {:list, item_type: :map, default: []},
    metadata: {:map, default: %{}}
  )
end
```

### Integration with Jido Agents

#### Signal Flow Architecture

```elixir
# Signal definitions for messaging
defmodule Jido.Messaging.Signals do
  def message_received, do: "messaging.message.received"
  def message_delivered, do: "messaging.message.delivered"
  def agent_request, do: "messaging.agent.request"
  def agent_response, do: "messaging.agent.response"
  def streaming_chunk, do: "messaging.streaming.chunk"
end
```

#### Agent Integration Pattern

```elixir
defmodule Jido.Messaging.AgentGateway do
  use GenServer

  def process_message(message, thread_id) do
    # Build ReqLLM context from thread
    context = build_context(thread_id, message)

    # Emit agent request signal
    signal = Jido.Messaging.Signals.agent_request()
    Jido.Signal.Bus.publish([context: context, message: message])

    # Handle streaming response
    handle_streaming_response(context)
  end
end
```

---

## 5. API Boundaries and Responsibilities

### jido_messaging v1 Responsibilities

**Core Messaging:**
- Message envelope creation and validation
- Thread/conversation management
- Participant management
- Message routing and delivery

**Agent Integration:**
- Signal emission for agent requests
- Streaming response handling
- Error propagation and retries
- Backpressure management

**Channel Abstraction:**
- Normalized message model
- Platform-specific formatting
- Connection management
- Delivery status tracking

### Explicit Exclusions

**Persistence Strategy:**
- Message history storage (handled by external journal)
- State persistence (delegated to adapter)
- Long-term archival (separate service)

**UI Concerns:**
- Chat interfaces (handled by clients)
- Message formatting (handled by channels)
- Presence indicators (handled by channels)

**Orchestration Beyond Routing:**
- Multi-agent coordination (handled by Jido framework)
- Complex workflows (separate workflow engine)
- Business logic (handled by agents)

---

## 6. Key Design Decisions and Trade-offs

### 1. Signal-Driven Architecture

**Decision**: All communication via `Jido.Signal.Bus`

**Pros**:
- Decoupled components
- Built-in observability
- Replay capabilities for debugging
- Ecosystem integration

**Cons**:
- Slightly higher overhead than direct calls
- Steeper learning curve
- Signal management complexity

### 2. Six-Layer Architecture

**Decision**: Layered separation with clear boundaries

**Pros**:
- Single responsibility per layer
- Easier testing and maintenance
- Flexible channel additions
- Clear upgrade paths

**Cons**:
- More boilerplate code
- Potential over-engineering for simple cases
- Cross-cutting concerns require careful handling

### 3. Streaming by Default

**Decision**: Native streaming support for all responses

**Pros**:
- Better user experience
- Progressive response rendering
- Resource efficiency for large responses
- Natural fit for LLM interactions

**Cons**:
- Increased complexity in buffering
- Delivery state tracking challenges
- Client-side handling complexity

### 4. Multi-tenant First

**Decision**: Instance-level isolation from day one

**Pros**:
- Production-ready from start
- Clear boundaries
- Scalability built-in
- Security by design

**Cons**:
- Higher initial complexity
- Resource overhead per instance
- Configuration management complexity

---

## 7. File/Module Structure Recommendations

```
lib/jido_messaging/
├── jido_messaging.ex          # Public API
├── signals/                   # Signal definitions
│   ├── message_received.ex
│   ├── message_delivered.ex
│   ├── agent_request.ex
│   └── agent_response.ex
├── domain/                    # Core domain models
│   ├── message.ex
│   ├── thread.ex
│   ├── participant.ex
│   └── instance.ex
├── routing/                   # Message routing
│   ├── router.ex
│   ├── middleware.ex
│   └── gateway.ex
├── channels/                  # Channel adapters
│   ├── behaviour.ex
│   ├── whatsapp.ex
│   ├── slack.ex
│   └── adapter.ex
├── agents/                    # Agent integration
│   ├── gateway.ex
│   ├── context_builder.ex
│   └── streaming.ex
└── persistence/               # Persistence abstractions
    ├── journal.ex
    ├── history.ex
    └── recovery.ex
```

---

## 8. Integration Points to Consider

### 1. Client Integration

**Pattern**: WebSocket + Signal subscription

```elixir
# Client connects and subscribes to thread signals
Jido.Signal.Bus.subscribe("messaging.thread.123")
```

### 2. Channel Integration

**Pattern**: Behaviour-based adapters

```elixir
defmodule MyChannel do
  @behaviour Jido.Messaging.Channel

  def init(config) do
    # Platform-specific initialization
  end

  def format_outgoing(message) do
    # Convert to platform format
  end
end
```

### 3. Agent Integration

**Pattern**: Signal-based communication

```elixir
# Agents subscribe to agent.request signals
def handle_info({:signal, %{type: "messaging.agent.request"}}, state) do
  # Process and respond
end
```

### 4. Persistence Integration

**Pattern**: Journal-based persistence

```elixir
# All important messages journaled
Jido.Signal.Journal.append("messaging.message", signal)
```

---

## 9. Error Handling and Backpressure

### Error Handling Strategy

1. **Signal-level errors**: Propagate via error signals
2. **Delivery failures**: Retry with exponential backoff
3. **Agent timeouts**: Graceful degradation with fallback
4. **Channel errors**: Circuit breaker pattern

### Backpressure Management

1. **Message queuing**: Bounded queues with overflow handling
2. **Rate limiting**: Per-instance and per-thread limits
3. **Streaming control**: Chunk-based streaming with pause/resume
4. **Priority routing**: High-priority messages bypass queue

---

## 10. Next Steps

Based on this research, the recommended next steps for implementing jido_messaging v1:

1. **Phase 1**: Core domain models and signal definitions
2. **Phase 2**: Signal-based message routing and gateway
3. **Phase 3**: Agent integration and streaming support
4. **Phase 4**: Channel adapter behavior and implementations
5. **Phase 5**: Persistence integration and error handling
6. **Phase 6**: API surface and management interfaces

---

## Key Findings Summary

- **jido_chat** exists at `/projects/jido_chat/` with solid OTP patterns but needs signal integration
- **Jido agents** use sophisticated signal routing via `jido_signal` bus
- **Six-layer architecture** recommended for clear separation of concerns
- **Signal-driven design** enables ecosystem integration and observability
- **Streaming by default** aligns with LLM interaction patterns

## Files Identified

**Existing jido_chat:**
- `/projects/jido_chat/lib/jido_chat.ex`
- `/projects/jido_chat/lib/jido_chat/message.ex`
- `/projects/jido_chat/lib/jido_chat/conversation.ex`
- `/projects/jido_chat/lib/jido_chat/room.ex`

**Agent Integration:**
- `/projects/jido/lib/jido/agent_server/signal_router.ex`
- `/projects/jido/lib/jido/agent_server.ex`
- `/projects/jido_signal/lib/jido_signal/bus.ex`

## Dependencies Affected

- **jido_chat** - Will be deprecated/replaced
- **jido** - Agent signal integration points
- **jido_signal** - Core messaging infrastructure
- **jido_ai** - Potential character integration

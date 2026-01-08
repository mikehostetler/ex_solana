# Implementation Plan: jido_messaging v1 Architecture Definition

**Item ID**: `jido-workspace-roadmap/ready-to-plan/6-jido-messaging-v1/019-define-scopearchitecture`
**Planning Date**: 2025-01-07
**Status**: Ready for Implementation

---

## Executive Summary

This implementation plan defines the scope and architecture for `jido_messaging` v1, a new messaging layer designed to replace `jido_chat` with a signal-driven, multi-channel architecture. The approach leverages the existing Jido ecosystem's signal infrastructure (`jido_signal`) and OTP patterns while addressing scalability concerns from the current implementation.

**Key Architectural Decisions:**
- **Signal-first architecture** using `Jido.Signal.Bus` for all communication
- **Six-layer architecture** with clear separation of concerns
- **Multi-tenant ready** with instance-level isolation
- **Streaming native** support for LLM-based agent interactions
- **Channel agnostic** design with normalized message model

**Effort Estimate**: 2-3 weeks for complete architecture definition, RFC, and initial scaffolding

---

## Impact Analysis Summary

### Key Findings from Research

The research (`research.md:1-481`) identified critical insights:

1. **Existing jido_chat Strengths** (`research.md:26-32`):
   - OTP-based supervision with proper GenServer patterns
   - Registry-based naming for room lookups
   - Event-driven design with basic emit/subscribe patterns
   - Structured data model using Zoi for validation
   - Multi-participant support with role-based permissions

2. **Pain Points Driving Redesign** (`research.md:34-41`):
   - Limited signal integration - Custom event system vs. `jido_signal`
   - Channel-specific coupling - WhatsApp-specific logic mixed with core chat
   - Scalability issues - Single supervisor for all rooms
   - Limited streaming support - Basic message passing without streaming
   - No multi-tenancy - All instances share configuration

3. **Agent Integration Patterns** (`research.md:52-93`):
   - Jido agents use priority-based signal routing via `SignalRouter`
   - Signal paths define how messages are handled
   - Agents receive signals via `AgentServer.call/cast`
   - Results executed via directive queue

### Files Requiring Changes

**New Package Structure:**
```
/projects/jido_messaging/          # New package
├── lib/jido_messaging/
│   ├── jido_messaging.ex         # Public API
│   ├── signals/                   # Signal definitions
│   ├── domain/                    # Core domain models
│   ├── routing/                   # Message routing
│   ├── channels/                  # Channel adapters
│   ├── agents/                    # Agent integration
│   └── persistence/               # Persistence abstractions
├── test/                          # Comprehensive test suite
├── mix.exs                        # Package configuration
└── README.md                      # Architecture documentation
```

**Affected Dependencies:**
- `jido_chat` - Will be deprecated after migration path defined
- `jido` - Agent signal integration points validated
- `jido_signal` - Core messaging infrastructure dependency
- `jido_ai` - Character integration for agent personalities

### Existing Patterns to Follow

**From jido_chat:**
- OTP supervision tree patterns (`/projects/jido_chat/lib/jido_chat/room.ex`)
- Registry-based process naming
- Zoi schema validation for data structures

**From jido:**
- Signal-based communication (`/projects/jido/lib/jido/agent_server/signal_router.ex`)
- Directive-based execution pattern
- Agent lifecycle management

**From jido_signal:**
- Signal bus usage patterns (`/projects/jido_signal/lib/jido_signal/bus.ex`)
- Journal-based persistence
- Middleware pipeline design

### Integration Points Identified

1. **Agent Integration** (`research.md:194-227`): Signal-based communication with Jido agents
2. **Client Integration** (`research.md:374-381`): WebSocket + Signal subscription pattern
3. **Channel Integration** (`research.md:383-399`): Behaviour-based adapter pattern
4. **Persistence Integration** (`research.md:413-420`): Journal-based persistence for audit trails

---

## Feature Specification

### User Stories with Acceptance Criteria

#### US-1: Message Envelope Creation
**As a** developer integrating jido_messaging
**I want to** create normalized message envelopes
**So that** messages can be routed across different platforms consistently

**Acceptance Criteria:**
- Message struct validates required fields using Zoi
- Supports user, assistant, system, and tool roles
- Includes delivery state tracking (pending, delivered, failed)
- Metadata field allows arbitrary routing information
- Thread ID enables conversation threading
- Timestamps are automatically generated

#### US-2: Thread/Conversation Management
**As a** system
**I want to** maintain conversation threads with bounded history
**So that** agents have context for multi-turn conversations

**Acceptance Criteria:**
- Thread struct manages participant list
- Message history is bounded (configurable limit)
- Thread ID is unique per instance
- Threads can be queried by instance ID
- Threads support metadata for custom attributes

#### US-3: Signal-Based Message Routing
**As a** messaging layer
**I want to** route messages via signals
**So that** communication is decoupled and observable

**Acceptance Criteria:**
- All message flow generates signals
- Signal paths follow naming convention: `messaging.*`
- Signals are journaled for replay/debugging
- Middleware can transform signals in-flight
- Priority routing for urgent messages

#### US-4: Agent Gateway Integration
**As a** messaging layer
**I want to** integrate with Jido agents via signals
**So that** agents can respond to messages naturally

**Acceptance Criteria:**
- Agent request signals include thread context
- Streaming responses are supported
- Error signals propagate to caller
- Backpressure prevents overwhelming agents
- Timeout handling with graceful degradation

#### US-5: Channel Abstraction
**As a** developer
**I want to** add new communication channels
**So that** jido_messaging works across platforms

**Acceptance Criteria:**
- Channel behaviour defines required callbacks
- Messages normalized to internal format
- Platform-specific formatting handled by channel
- Delivery status tracked per channel
- Failed deliveries generate error signals

### API Contracts and Data Flow

#### Message Creation API

```elixir
# Create a new message
{:ok, message} = Jido.Messaging.Message.new(%{
  thread_id: "thread-123",
  from: %{id: "user-1", type: :user},
  to: [%{id: "agent-1", type: :agent}],
  role: :user,
  content: %{text: "Hello, agent!"},
  metadata: %{channel: :web}
})

# Send message through gateway
{:ok, status} = Jido.Messaging.send_message(message)
```

#### Signal Flow

```elixir
# Signal emitted when message received
Jido.Signal.Bus.publish(%{
  type: "messaging.message.received",
  data: %{message: message, thread_id: thread_id}
})

# Signal emitted for agent processing
Jido.Signal.Bus.publish(%{
  type: "messaging.agent.request",
  data: %{
    message: message,
    context: context,
    thread_id: thread_id
  }
})

# Streaming chunks
Jido.Signal.Bus.publish(%{
  type: "messaging.streaming.chunk",
  data: %{
    thread_id: thread_id,
    chunk: "partial response",
    index: 1
  }
})
```

### State Management Requirements

**Thread State:**
- Threads managed by DynamicSupervisor
- Registry-based lookup by thread ID
- ETS-based caching for thread metadata
- Bounded message history per thread

**Message State:**
- Delivery state tracked per message
- Retry queue for failed deliveries
- Exponential backoff for retries
- Circuit breaker for failing channels

**Instance State:**
- Instance-level isolation
- Configuration per instance
- Rate limiting per instance
- Telemetry and observability

### Error Handling Approach

**Signal-Level Errors** (`research.md:426-431`):
- Error signals propagate through system
- Error context includes original signal
- Handlers can recover or escalate

**Delivery Failures**:
- Retry with exponential backoff
- Max retry attempts configurable
- Dead letter queue for exhausted messages
- Circuit breaker for failing endpoints

**Agent Timeouts**:
- Graceful degradation with fallback
- Timeout signals for monitoring
- Partial responses delivered if available
- Fallback to default response if critical

**Channel Errors**:
- Circuit breaker pattern for failed channels
- Automatic reconnection with backoff
- Channel health monitoring
- Graceful degradation to alternative channels

---

## Technical Design

### Data Model Changes

#### Core Domain Models

**Message Schema** (`research.md:150-172`):

```elixir
defmodule Jido.Messaging.Message do
  use Zoi.Struct

  @schema Zoi.struct(
    id: {:string, required: true, default: &generate_id/0},
    thread_id: {:string, required: false},
    from: {:map, required: true},
    to: {:list, item_type: :map, default: []},
    role: {:enum, values: [:user, :assistant, :system, :tool], required: true},
    content: {:map, required: true},
    metadata: {:map, default: %{}},
    timestamp: {:datetime, required: true, default: &DateTime.utc_now/0},
    delivery_state: {:enum, values: [:pending, :delivered, :failed], default: :pending}
  )
end
```

**Thread Schema** (`research.md:174-192`):

```elixir
defmodule Jido.Messaging.Thread do
  use Zoi.Struct

  @schema Zoi.struct(
    id: {:string, required: true, default: &generate_id/0},
    instance_id: {:string, required: true},
    participants: {:list, item_type: :map, default: []},
    messages: {:list, item_type: :map, default: []},
    metadata: {:map, default: %{}},
    max_history: {:integer, default: 100},
    created_at: {:datetime, required: true},
    updated_at: {:datetime, required: true}
  )
end
```

**Participant Schema**:

```elixir
defmodule Jido.Messaging.Participant do
  use Zoi.Struct

  @schema Zoi.struct(
    id: {:string, required: true},
    type: {:enum, values: [:user, :agent, :system], required: true},
    role: {:enum, values: [:admin, :member, :guest], default: :member},
    metadata: {:map, default: %{}}
  )
end
```

**Instance Schema**:

```elixir
defmodule Jido.Messaging.Instance do
  use Zoi.Struct

  @schema Zoi.struct(
    id: {:string, required: true, default: &generate_id/0},
    name: {:string, required: true},
    config: {:map, required: true},
    status: {:enum, values: [:active, :paused, :terminated], default: :active},
    created_at: {:datetime, required: true}
  )
end
```

### Module Organization

**Public API** (`lib/jido_messaging.ex`):

```elixir
defmodule Jido.Messaging do
  @moduledoc """
  Public API for jido_messaging.

  Provides high-level functions for message creation, thread management,
  and integration with Jido agents.
  """

  # Message operations
  def send_message(message, opts \\ [])
  def create_message(params)
  def get_message(message_id)

  # Thread operations
  def create_thread(params)
  def get_thread(thread_id)
  def list_threads(instance_id)
  def add_participant(thread_id, participant)
  def remove_participant(thread_id, participant_id)

  # Instance operations
  def create_instance(params)
  def get_instance(instance_id)
  def list_instances()

  # Configuration
  def child_spec(opts)
  def start_link(opts)
end
```

**Signal Definitions** (`lib/jido_messaging/signals/`):

```elixir
defmodule Jido.Messaging.Signals do
  @moduledoc """
  Signal type definitions for messaging layer.
  """

  def message_received, do: "messaging.message.received"
  def message_delivered, do: "messaging.message.delivered"
  def message_failed, do: "messaging.message.failed"
  def agent_request, do: "messaging.agent.request"
  def agent_response, do: "messaging.agent.response"
  def streaming_chunk, do: "messaging.streaming.chunk"
  def streaming_complete, do: "messaging.streaming.complete"
  def thread_created, do: "messaging.thread.created"
  def thread_updated, do: "messaging.thread.updated"
end
```

**Agent Gateway** (`lib/jido_messaging/agents/gateway.ex`):

```elixir
defmodule Jido.Messaging.AgentGateway do
  use GenServer

  def process_message(message, thread_id, opts \\ [])
  def build_context(thread_id, message)
  def handle_streaming_response(context)
  def handle_timeout(message_id)

  # Callbacks
  def init(opts)
  def handle_info({:signal, signal}, state)
end
```

**Router** (`lib/jido_messaging/routing/router.ex`):

```elixir
defmodule Jido.Messaging.Router do
  use GenServer

  def route_message(message)
  def register_route(pattern, handler)
  def unregister_route(pattern)
  def add_middleware(middleware)

  # Callbacks
  def init(opts)
  def handle_cast({:route, message}, state)
end
```

**Channel Behaviour** (`lib/jido_messaging/channels/behaviour.ex`):

```elixir
defmodule Jido.Messaging.Channel do
  @moduledoc """
  Behaviour for channel adapters.
  """

  @callback init(config :: map()) :: {:ok, state :: term()} | {:error, term()}

  @callback send_message(
    message :: Jido.Messaging.Message.t(),
    state :: term()
  ) :: {:ok, term()} | {:error, term()}

  @callback format_outgoing(
    message :: Jido.Messaging.Message.t(),
    state :: term()
  ) :: {:ok, formatted :: term()} | {:error, term()}

  @callback handle_incoming(
    raw_message :: term(),
    state :: term()
  ) :: {:ok, Jido.Messaging.Message.t()} | {:error, term()}

  @callback health_check(state :: term()) :: :ok | {:error, term()}
end
```

### Third-Party Integration Details

**Required Dependencies:**

```elixir
# mix.exs
defp deps do
  [
    {:jido, "~> 0.2"},              # Core agent framework
    {:jido_signal, "~> 0.1"},       # Signal bus and routing
    {:zoi, "~> 0.14"},              # Schema validation
    {:splode, "~> 0.2"},            # Error handling
    {:req, "~> 0.5"}                # HTTP client for channels
  ]
end
```

**Optional Dependencies:**

```elixir
[
  {:req_llm, "~> 0.1"},            # LLM streaming support
  {:jido_ai, "~> 0.1"},            # Character integration
  {:phoenix, "~> 1.7"}             # WebSocket support (for clients)
]
```

### Configuration/Environment Changes

**Application Configuration** (`config/config.exs`):

```elixir
import Config

config :jido_messaging,
  # Instance management
  default_max_history: 100,
  instance_timeout: :timer.minutes(30),

  # Message routing
  router_pool_size: 10,
  max_queue_size: 1000,

  # Agent integration
  agent_timeout: :timer.seconds(30),
  streaming_chunk_size: 512,

  # Retry strategy
  max_retry_attempts: 3,
  retry_backoff_base: 1000,  # milliseconds

  # Circuit breaker
  circuit_breaker_threshold: 5,
  circuit_breaker_timeout: :timer.seconds(30),

  # Persistence
  journal_enabled: true,
  journal_retention: :timer.days(7)
```

**Runtime Configuration:**

```elixir
# Per-instance configuration
def start_instance(config) do
  Jido.Messaging.create_instance(%{
    id: "instance-1",
    name: "Production",
    config: %{
      max_threads: 1000,
      max_participants_per_thread: 50,
      allowed_channels: [:web, :slack, :whatsapp],
      rate_limit: %{
        messages_per_minute: 100,
        burst: 200
      }
    }
  })
end
```

---

## Implementation Phases

### Phase 1: Foundation & Scaffolding

**Objective:** Establish package structure, core domain models, and signal definitions

**Success Criteria:**
- Package compiles and tests pass
- Core domain models validated with Zoi
- Signal definitions published and documented
- Basic supervision tree running

**Files to Create:**
- `/projects/jido_messaging/mix.exs` - Package configuration
- `/projects/jido_messaging/lib/jido_messaging.ex` - Public API skeleton
- `/projects/jido_messaging/lib/jido_messaging/application.ex` - Application supervision
- `/projects/jido_messaging/lib/jido_messaging/domain/message.ex` - Message schema
- `/projects/jido_messaging/lib/jido_messaging/domain/thread.ex` - Thread schema
- `/projects/jido_messaging/lib/jido_messaging/domain/participant.ex` - Participant schema
- `/projects/jido_messaging/lib/jido_messaging/domain/instance.ex` - Instance schema
- `/projects/jido_messaging/lib/jido_messaging/signals.ex` - Signal definitions

**Tests to Add:**
- `test/jido_messaging/domain/message_test.exs`
- `test/jido_messaging/domain/thread_test.exs`
- `test/jido_messaging/domain/participant_test.exs`
- `test/jido_messaging/domain/instance_test.exs`
- `test/jido_messaging/signals_test.exs`

**Dependencies:**
- None (foundational phase)

**Acceptance Tests:**
```elixir
defmodule Jido.Messaging.FoundationTest do
  test "creates valid message with required fields" do
    assert {:ok, message} = Jido.Messaging.Message.new(@valid_params)
    assert message.role == :user
    assert message.delivery_state == :pending
  end

  test "rejects message with invalid role" do
    assert {:error, _} = Jido.Messaging.Message.new(%{role: :invalid})
  end

  test "thread maintains bounded history" do
    {:ok, thread} = Jido.Messaging.Thread.new(%{max_history: 5})
    # Add 10 messages, verify only 5 retained
  end
end
```

---

### Phase 2: Message Routing & Gateway

**Objective:** Implement signal-based message routing and agent gateway

**Success Criteria:**
- Messages route via signal bus
- Agent gateway processes messages
- Middleware pipeline transforms signals
- Delivery tracking functional

**Files to Create:**
- `/projects/jido_messaging/lib/jido_messaging/routing/router.ex` - Message router
- `/projects/jido_messaging/lib/jido_messaging/routing/middleware.ex` - Middleware pipeline
- `/projects/jido_messaging/lib/jido_messaging/routing/gateway.ex` - Routing gateway
- `/projects/jido_messaging/lib/jido_messaging/agents/gateway.ex` - Agent gateway
- `/projects/jido_messaging/lib/jido_messaging/agents/context_builder.ex` - Context builder
- `/projects/jido_messaging/lib/jido_messaging/agents/streaming.ex` - Streaming handler

**Files to Modify:**
- `/projects/jido_messaging/lib/jido_messaging.ex` - Add routing APIs
- `/projects/jido_messaging/lib/jido_messaging/application.ex` - Add router to supervision

**Tests to Add:**
- `test/jido_messaging/routing/router_test.exs`
- `test/jido_messaging/routing/middleware_test.exs`
- `test/jido_messaging/agents/gateway_test.exs`
- `test/jido_messaging/agents/streaming_test.exs`
- `test/jido_messaging/integration/routing_test.exs`

**Dependencies:**
- Phase 1 complete
- `jido_signal` dependency configured

**Acceptance Tests:**
```elixir
defmodule Jido.Messaging.RoutingTest do
  test "routes message via signal bus" do
    message = create_test_message()
    assert {:ok, _} = Jido.Messaging.send_message(message)

    assert_receive {:signal, %{
      type: "messaging.message.received",
      data: %{message: ^message}
    }}
  end

  test "agent gateway processes message request" do
    message = create_test_message()
    {:ok, thread} = create_test_thread()

    assert {:ok, _} = Jido.Messaging.AgentGateway.process_message(
      message,
      thread.id
    )

    assert_receive {:signal, %{
      type: "messaging.agent.request"
    }}
  end
end
```

---

### Phase 3: Agent Integration & Streaming

**Objective:** Complete agent integration with streaming support and error handling

**Success Criteria:**
- Agents receive message requests via signals
- Streaming responses handled correctly
- Errors propagate through signal system
- Backpressure prevents overwhelming agents
- Timeout handling with graceful degradation

**Files to Create:**
- `/projects/jido_messaging/lib/jido_messaging/agents/supervisor.ex` - Agent supervisor
- `/projects/jido_messaging/lib/jido_messaging/agents/backpressure.ex` - Backpressure manager
- `/projects/jido_messaging/lib/jido_messaging/agents/error_handler.ex` - Error handling
- `/projects/jido_messaging/lib/jido_messaging/agents/retry_queue.ex` - Retry queue

**Files to Modify:**
- `/projects/jido_messaging/lib/jido_messaging/agents/gateway.ex` - Add streaming
- `/projects/jido_messaging/lib/jido_messaging/agents/context_builder.ex` - Enhance context
- `/projects/jido_messaging/lib/jido_messaging/application.ex` - Add supervisor

**Tests to Add:**
- `test/jido_messaging/agents/backpressure_test.exs`
- `test/jido_messaging/agents/retry_queue_test.exs`
- `test/jido_messaging/agents/error_handler_test.exs`
- `test/jido_messaging/integration/streaming_test.exs`
- `test/jido_messaging/integration/agent_integration_test.exs`

**Dependencies:**
- Phase 2 complete
- `jido` agent integration validated

**Acceptance Tests:**
```elixir
defmodule Jido.Messaging.AgentIntegrationTest do
  test "agent receives and responds to message" do
    message = create_test_message()
    thread = create_test_thread()

    # Start test agent
    {:ok, _agent} = start_test_agent()

    # Send message
    assert {:ok, _} = Jido.Messaging.send_message(message, thread_id: thread.id)

    # Verify agent received signal
    assert_receive {:signal, %{
      type: "messaging.agent.request",
      data: %{message: ^message}
    }}

    # Verify response signal
    assert_receive {:signal, %{
      type: "messaging.agent.response"
    }}
  end

  test "streaming response emits chunk signals" do
    message = create_test_message()
    thread = create_test_thread()

    {:ok, _} = Jido.Messaging.send_message(message,
      thread_id: thread.id,
      stream: true
    )

    # Verify streaming chunks
    assert_receive {:signal, %{
      type: "messaging.streaming.chunk"
    }}

    assert_receive {:signal, %{
      type: "messaging.streaming.complete"
    }}
  end

  test "timeout generates error signal" do
    message = create_test_message()

    {:ok, _} = Jido.Messaging.send_message(message,
      agent_timeout: 100
    )

    assert_receive {:signal, %{
      type: "messaging.agent.timeout"
    }}
  end
end
```

---

### Phase 4: Channel Abstraction & Integration

**Objective:** Implement channel adapter behaviour and initial channels

**Success Criteria:**
- Channel behaviour defined and documented
- Message normalization working
- Platform-specific formatting functional
- Delivery status tracked
- Circuit breaker for failed channels

**Files to Create:**
- `/projects/jido_messaging/lib/jido_messaging/channels/behaviour.ex` - Channel behaviour
- `/projects/jido_messaging/lib/jido_messaging/channels/adapter.ex` - Base adapter
- `/projects/jido_messaging/lib/jido_messaging/channels/registry.ex` - Channel registry
- `/projects/jido_messaging/lib/jido_messaging/channels/supervisor.ex` - Channel supervisor
- `/projects/jido_messaging/lib/jido_messaging/channels/web.ex` - Web channel (reference)
- `/projects/jido_messaging/lib/jido_messaging/channels/mock.ex` - Mock channel for testing

**Files to Modify:**
- `/projects/jido_messaging/lib/jido_messaging.ex` - Add channel APIs
- `/projects/jido_messaging/lib/jido_messaging/application.ex` - Add supervisor

**Tests to Add:**
- `test/jido_messaging/channels/behaviour_test.exs`
- `test/jido_messaging/channels/adapter_test.exs`
- `test/jido_messaging/channels/web_test.exs`
- `test/jido_messaging/integration/channel_test.exs`

**Dependencies:**
- Phase 3 complete
- Channel requirements finalized

**Acceptance Tests:**
```elixir
defmodule Jido.Messaging.ChannelTest do
  test "channel behaviour implementation" do
    {:ok, channel} = start_test_channel()

    message = create_test_message()

    assert {:ok, _} = Jido.Messaging.Channel.send_message(
      message,
      channel.state
    )
  end

  test "message normalization" do
    raw_message = %{
      text: "Hello",
      user: "user-1",
      platform: :slack
    }

    assert {:ok, normalized} = Jido.Messaging.Channel.normalize(
      raw_message,
      :slack
    )

    assert normalized.role == :user
    assert normalized.content.text == "Hello"
    assert normalized.metadata.platform == :slack
  end

  test "delivery tracking" do
    message = create_test_message()
    channel = start_test_channel()

    {:ok, _} = Jido.Messaging.send_message(message,
      channel: channel,
      track_delivery: true
    )

    assert_receive {:signal, %{
      type: "messaging.message.delivered",
      data: %{message_id: _, status: :delivered}
    }}
  end
end
```

---

## Quality & Testing Strategy

### Test Categories

**Unit Tests:**
- Domain model validation (Message, Thread, Participant, Instance)
- Signal definitions and emission
- Individual component logic
- Error handling paths

**Integration Tests:**
- Message flow through routing
- Agent gateway interaction
- Signal propagation
- Multi-component workflows

**Property-Based Tests:**
- Message validation invariant
- Thread history boundedness
- Signal ordering guarantees
- Retry queue correctness

**Contract Tests:**
- Channel behaviour conformance
- Signal schema validation
- API contract adherence

### Coverage Targets

| Category | Target | Notes |
|----------|--------|-------|
| Domain Models | 95%+ | Critical business logic |
| Signal System | 90%+ | Core communication |
| Agent Gateway | 85%+ | Integration complexity |
| Channels | 80%+ | Platform variations |
| Overall | 85%+ | Standard threshold |

### Quality Gates

**Pre-Commit:**
- All tests pass
- Type specs validate
- Format check passes
- No compiler warnings

**Pre-Merge:**
- CI pipeline passes
- Coverage threshold met
- Integration tests pass
- Documentation builds
- No security vulnerabilities

**Pre-Release:**
- Full test suite passes
- Performance benchmarks acceptable
- Load tests pass
- Documentation complete
- Migration guide available

---

## Risk Assessment

### Technical Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Signal bus performance bottlenecks | High | Medium | Implement partitioning, monitor throughput |
| Streaming complexity increases bugs | High | Medium | Extensive testing, start simple |
| Multi-tenancy isolation failures | High | Low | Strict boundary validation, test suites |
| Channel integration complexity | Medium | High | Behaviour contract, reference implementations |
| Memory leaks from unbounded threads | Medium | Medium | Strict history limits, monitoring |

### Dependency Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| jido_signal API changes | High | Low | Version pinning, migration strategy |
| jido agent incompatibilities | Medium | Low | Integration tests, version matrix |
| Zoi validation performance | Medium | Medium | Benchmark, optimize hot paths |

### Timeline Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Scope creep from feature requests | Medium | High | Strict change control, phased delivery |
| Integration testing takes longer | Medium | Medium | Early integration testing, parallel work |
| Documentation underestimation | Low | Medium | Start documentation early, examples |

---

## Success Criteria

### Measurable Outcomes

**Architecture Document:**
- RFC published and reviewed
- Architecture approved by stakeholders
- Migration path from jido_chat defined
- Integration guide available

**Implementation:**
- All domain models implemented and tested
- Signal-based routing functional
- Agent gateway integrated with Jido agents
- Streaming support working end-to-end
- At least one reference channel implemented

**Quality:**
- 85%+ test coverage achieved
- All quality gates passed
- Performance benchmarks met
- Zero critical bugs in initial release

**Documentation:**
- Public API documented
- Architecture guide published
- Migration guide available
- Examples and tutorials provided
- Error handling documented

### Definition of "Done"

An item is considered complete when:

1. **Code:**
   - All phases implemented
   - Tests passing at target coverage
   - Code reviewed and approved
   - No critical or high-severity bugs

2. **Documentation:**
   - API documentation complete
   - Architecture RFC published
   - Migration guide available
   - Examples provided

3. **Integration:**
   - Works with Jido agents
   - Signal integration validated
   - Reference channel working
   - Performance benchmarks met

4. **Approval:**
   - Design review approved
   - Code review approved
   - Documentation review approved
   - Stakeholder sign-off

### Acceptance Testing Approach

**Manual Testing:**
- End-to-end message flow
- Agent interaction scenarios
- Multi-turn conversations
- Error scenarios
- Performance under load

**Automated Testing:**
- Unit test suite
- Integration test suite
- Property-based tests
- Contract tests
- Performance benchmarks

**Beta Testing:**
- Internal beta with Jido team
- Selected external partners
- Feedback collection and iteration

---

## Next Steps

1. **Immediate (Week 1):**
   - Create jido_messaging package structure
   - Implement Phase 1 (Foundation & Scaffolding)
   - Begin architecture RFC document

2. **Short-term (Weeks 2-3):**
   - Complete Phase 2 (Message Routing & Gateway)
   - Draft architecture RFC for review
   - Begin integration testing with Jido agents

3. **Medium-term (Weeks 4-5):**
   - Complete Phase 3 (Agent Integration & Streaming)
   - Implement Phase 4 (Channel Abstraction)
   - Finalize and publish RFC

4. **Long-term (Week 6+):**
   - Additional channel implementations
   - Performance optimization
   - Documentation and examples
   - Migration from jido_chat

---

## References

- Research document: `research.md`
- Existing jido_chat: `/projects/jido_chat/`
- Jido agent system: `/projects/jido/`
- Jido signal system: `/projects/jido_signal/`
- Architecture decisions: `research.md:272-333`

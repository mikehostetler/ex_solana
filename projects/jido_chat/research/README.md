# JIDO_CHAT_V2 Research Documentation

This directory contains deep research for the JIDO_CHAT_V2 architecture - a multi-tenant conversation fabric that connects Jido AI agents to humans across any messaging platform.

## Overview

**JIDO_CHAT_V2** is where the Jido ecosystem puzzle fits together. It provides the **interface layer** between:
- **Human users** (via WhatsApp, Slack, Discord, SMS, etc.)
- **AI agents** (via ReqLLM + Jido runtime)
- **Backend systems** (via Jido.Actions)
- **Observability** (via Jido.Signal)

## Core Documents

### [JIDO_CHAT_V2.md](JIDO_CHAT_V2.md) - Main Architecture Proposal

**Comprehensive architecture specification** covering:
- Vision & positioning in Jido ecosystem
- Six-layer architecture design
- Core domain model (Instance, Room, Participant, Message)
- Integration with Jido.Action, Jido.Signal, Jido.Character
- Multi-tenancy & isolation
- ReqLLM context building
- Signal-driven events
- 16-week implementation roadmap

**Key Concepts**:
- **Instances**: Tenant-level configuration (1 instance = 1 tenant + 1 channel + 1 agent backend)
- **Rooms**: Conversation contexts with participants, history, and state
- **Channel Normalization**: Platform-specific → unified message model
- **Agent Gateway**: Room context → ReqLLM request → streaming responses

**Start Here** if you're new to the architecture.

---

## Deep Research Topics

### [channel-adapters.md](channel-adapters.md) - Channel Normalization Layer

**Focus**: How do we translate between platform-specific and normalized formats?

**Key Questions**:
- How do we handle platform-specific features (Slack threads, WhatsApp media)?
- What's the right abstraction for interactive components (buttons, modals)?
- How do we normalize attachments across platforms?
- Should adapters be plugins or built-in?

**Covers**:
- Normalized message structure with platform extensions
- Interactive component abstraction (buttons, cards, selects)
- Attachment normalization strategy
- Built-in vs plugin adapter architecture
- Implementation examples (WhatsApp, Slack, Discord)
- Adapter contract testing

**Status**: ✅ Design complete, ready for prototyping

---

### [reqllm-integration.md](reqllm-integration.md) - Agent Integration Layer

**Focus**: How do we build rich LLM contexts and orchestrate agent responses?

**Key Questions**:
- How do we optimize context window usage (token limits)?
- What's the right tool calling pattern (single-turn vs multi-turn)?
- How do we handle streaming across platforms?
- How do we manage prompt governance (safety, compliance)?

**Covers**:
- Token-aware context windowing strategies
- Multi-turn tool execution loops
- Streaming buffer strategies for non-streaming platforms
- Prompt governance and safety layers
- Context builder implementation
- Testing strategies (mocking LLMs)

**Status**: ✅ Design complete, ready for implementation

---

## Planned Research Topics

The following topics are identified but require deeper research:

### routing-strategies.md (TODO)

**Focus**: When to route to Actions vs Agents, intent-based routing

**Questions**:
- How do we detect intent without calling LLM first?
- What's the right pattern matching DSL?
- How do we handle ambiguous inputs?
- Should we support multi-agent routing?

---

### character-system.md (TODO)

**Focus**: Agent personality and capability configuration

**Questions**:
- How granular should character configuration be?
- Should characters be versioned?
- How do we handle character evolution?
- What's the right tool selection strategy?

---

### multi-tenancy.md (TODO)

**Focus**: Tenant isolation and resource management

**Questions**:
- How do we isolate tenant data?
- What's the right tenant billing model?
- How do we handle tenant-specific compliance?
- Should we support tenant-level clustering?

---

### event-architecture.md (TODO)

**Focus**: Signal design and event sourcing

**Questions**:
- What's the right signal granularity?
- How do we handle signal versioning?
- Should signals be persistent (event sourcing)?
- How do we prevent signal fanout issues?

---

### conversation-state.md (TODO)

**Focus**: Managing multi-turn conversation flows

**Questions**:
- How do we persist conversation state?
- What's the right TTL strategy?
- How do we support complex workflows?
- Should we use behavior trees or state machines?

---

### api-design.md (TODO)

**Focus**: Management and operational APIs

**Questions**:
- REST vs GraphQL for management APIs?
- How do we version APIs?
- What's the right authentication model?
- Should we support webhooks for events?

---

### testing-strategies.md (TODO)

**Focus**: Testing multi-channel, multi-agent systems

**Questions**:
- How do we test multi-channel flows?
- What's the right mocking strategy for LLMs?
- How do we test streaming?
- What property-based tests make sense?

---

### performance-scaling.md (TODO)

**Focus**: Scaling to 1000+ concurrent rooms

**Questions**:
- What's the bottleneck: rooms, instances, or channels?
- How do we handle 1000+ concurrent rooms?
- Should we cluster across nodes?
- What's the right persistence strategy for history?

---

## Quick Reference

### Architecture Layers

```
Layer 6: Multi-Tenant APIs & Admin Surfaces
    ↓ Phoenix controllers, webhooks, management
Layer 5: Signals & Events
    ↓ Observability, extensibility via jido_signal
Layer 4: Agent Gateway
    ↓ ReqLLM context building, tool orchestration
Layer 3: Conversation & Routing
    ↓ Rooms, turn strategies, middleware
Layer 2: Channel Normalization
    ↓ Platform-specific → normalized messages
Layer 1: Core Domain Model
    ↓ Instance, Room, Participant, Message
```

### Key Integration Points

**With Jido Ecosystem**:
- `Jido.Action` → Exposed as LLM tools
- `Jido.Signal` → Emit/subscribe to chat events
- `Jido.Character` → Define agent personalities
- `ReqLLM` → Submit rich conversation contexts

**With External Platforms**:
- WhatsApp → Evolution API
- Slack → Events API / Bolt
- Discord → Nostrum library
- SMS → Twilio

### Process Supervision

```
Application.Supervisor
├─── Registry (InstanceRegistry)
├─── Registry (RoomRegistry)
├─── DynamicSupervisor (InstanceSupervisor)
│       └─── InstanceServer (per tenant instance)
├─── DynamicSupervisor (RoomSupervisor)
│       └─── RoomServer (per conversation)
└─── AgentGateway (GenServer pool)
```

---

## Implementation Progress

### Phase 1: Core Foundation (Weeks 1-2) - ⏳ NOT STARTED
- [ ] Migrate structs to Zoi
- [ ] Add Splode error handling
- [ ] Implement InstanceSupervisor + InstanceServer
- [ ] Refactor RoomServer
- [ ] Add Registry-based lookups

### Phase 2: Channel Abstraction (Weeks 3-4) - ⏳ NOT STARTED
- [ ] Define Channel behaviour
- [ ] Implement WhatsApp adapter
- [ ] Implement Slack adapter
- [ ] Build webhook infrastructure

### Phase 3: Agent Integration (Weeks 5-6) - ⏳ NOT STARTED
- [ ] Build ContextBuilder
- [ ] Implement AgentGateway
- [ ] Integrate Jido.Character
- [ ] Map Actions to tools

### Phase 4-8: See [JIDO_CHAT_V2.md](JIDO_CHAT_V2.md#implementation-strategy)

---

## Contributing to Research

Each research document should follow this structure:

```markdown
# Topic Name

## Overview
Brief description of the research area

## Core Questions
List of key questions to answer

## Proposed Approaches
Multiple options with trade-offs

## Implementation Examples
Code sketches showing how it would work

## Testing Strategy
How to validate the approach

## Next Steps
Concrete actions to move forward
```

---

## Next Steps

1. **Review** main architecture proposal ([JIDO_CHAT_V2.md](JIDO_CHAT_V2.md))
2. **Dive deep** into channel adapters and ReqLLM integration
3. **Prototype** core domain model with Zoi
4. **Implement** Phase 1 (Core Foundation)
5. **Expand** research docs for remaining topics

**Questions?** Open an issue or start a discussion in the Jido workspace.

---

## Document Status Legend

- ✅ **Design complete** - Ready for implementation
- 🔄 **In progress** - Actively being researched
- ⏳ **Planned** - Identified but not started
- 📝 **Draft** - Initial thoughts, needs refinement

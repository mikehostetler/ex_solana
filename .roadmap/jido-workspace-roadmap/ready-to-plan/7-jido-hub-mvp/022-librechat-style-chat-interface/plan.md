# Implementation Plan: LibreChat-style Chat Interface for Jido Hub

**Item ID:** 022-librechat-style-chat-interface
**Status:** Ready to Implement
**Estimated Effort:** Medium-Large (2-3 weeks)
**Dependencies:** Item 021 (Phoenix project setup), jido_messaging implementation status

## Executive Summary

Implement a LibreChat-style chat interface in `jido_hub` that provides a ChatGPT-like experience for conversing with Jido agents. The implementation leverages Phoenix LiveView 1.1.0 for real-time chat capabilities, streaming LLM responses, and modern chat UI patterns.

The primary work involves:
1. **Creating a chat LiveView** with message list, input, and streaming support
2. **Integrating with jido_messaging** layer for message persistence and routing
3. **Implementing LibreChat-style UI patterns** including message bubbles, code highlighting, markdown rendering
4. **Adding real-time features** including streaming responses, typing indicators, conversation management

**Key Architectural Decisions:**
- Use Phoenix LiveView for server-rendered real-time UI (no client-side framework needed)
- Integrate with jido_messaging's Room/Message/Participant entities
- Support streaming responses via LiveView streams and assigns
- Use Earmark for markdown rendering and Makeup for code highlighting
- Follow existing JidoHub authentication and component patterns

**Critical Dependency:** jido_messaging must implement Room/Message/Participant entities before full integration. Plan includes mock mode for development.

## Impact Analysis Summary

### Key Findings from Research

**Existing Infrastructure:**
- Phoenix 1.8.1 with LiveView 1.1.0 - perfect for chat interfaces
- DaisyUI Components 0.9.2 - provides modern UI styling
- AshAuthentication 4.0 - user authentication already set up
- Phoenix.PubSub - real-time message broadcasting infrastructure
- Ash Framework 3.0 - domain modeling (though chat may use jido_messaging directly)

**Integration Requirements:**
- jido_messaging layer (currently vision-only - needs implementation)
- Agent integration pattern (how agents connect to messaging rooms)
- Real-time streaming (LLM responses chunk by chunk)
- Message persistence (ETS for dev, PostgreSQL for prod)

### Files Requiring Changes

**Phase 1 - Foundation (5 new files, 1 modified):**
- Create: `lib/jido_hub_web/live/chat_live.ex` - Main chat LiveView
- Create: `lib/jido_hub_web/live/chat_live.html.heex` - Chat UI template
- Create: `lib/jido_hub_web/live/components/message_component.ex` - Message rendering
- Create: `lib/jido_hub_web/live/components/chat_input_component.ex` - Message input
- Create: `lib/jido_hub_web/live/components/conversation_list_component.ex` - Conversation sidebar
- Modify: `lib/jido_hub_web/router.ex` - Add chat routes

**Phase 2 - Real-Time Integration (3 new files, 2 modified):**
- Create: `lib/jido_hub_web/live/components/typing_indicator_component.ex` - Typing indicator
- Create: `lib/jido_hub_web/live/components/streaming_message_component.ex` - Streaming message wrapper
- Create: `lib/jido_hub_web/chat/subscriber.ex` - PubSub subscription manager
- Modify: `lib/jido_hub_web/live/chat_live.ex` - Add PubSub integration
- Modify: `lib/jido_hub/application.ex` - Add chat-related supervisors (if needed)

**Phase 3 - Rich Content (4 new files, 2 modified):**
- Create: `lib/jido_hub_web/live/components/markdown_component.ex` - Markdown rendering
- Create: `lib/jido_hub_web/live/components/code_block_component.ex` - Code highlighting
- Modify: `lib/jido_hub_web/live/components/message_component.ex` - Add markdown support
- Modify: `lib/jido_hub_web/live/chat_live.html.heex` - Add streaming UI

**Phase 4 - Polish & Testing (3 new files, 2 modified):**
- Create: `test/jido_hub_web/live/chat_live_test.ex` - Chat LiveView tests
- Create: `test/jido_hub_web/live/components/message_component_test.ex` - Component tests
- Create: `test/support/chat_helpers.ex` - Test fixtures and helpers
- Modify: `lib/jido_hub_web/components/layouts.ex` - Ensure chat layout support
- Modify: `config/dev.exs`, `config/prod.exs` - Configure messaging adapters

### Existing Patterns to Follow

**LiveView Pattern:** Follow `DashboardLive` structure (mount/3, handle_event/3, handle_info/2, render/1)
**Authentication:** Use `JidoHubWeb.LiveUserAuth` on_mount hooks
**Component Pattern:** Use function components in `CoreComponents` with HEEx templates
**PubSub Pattern:** Subscribe to room-specific topics for real-time updates
**Testing Pattern:** Use ExUnit with PhoenixTest.Playwright for E2E tests

### Integration Points Identified

**JidoMessaging Layer:** Room/Message/Participant entities (needs implementation verification)
**Phoenix.PubSub:** Message broadcasting and real-time updates
**AshAuthentication:** User session management and authorization
**Agent Integration:** Agents participate in rooms via agent runner pattern
**Database:** PostgreSQL via AshPostgres (or ETS for dev/testing)

## Feature Specification

### User Stories with Acceptance Criteria

**US1: User can view chat interface**
- As a user, I want to see a chat interface so I can converse with agents
- AC:
  - Chat page loads at `/chat`
  - User sees message list (empty or with previous messages)
  - User sees message input field
  - User sees send button
  - Interface is responsive on mobile and desktop

**US2: User can send messages**
- As a user, I want to send messages so I can interact with agents
- AC:
  - User types in message input
  - User presses Enter or clicks Send
  - Message appears in message list
  - Message shows user's name/avatar
  - Message shows timestamp
  - Input clears after sending

**US3: User receives agent responses**
- As a user, I want to receive agent responses so I can get help
- AC:
  - Agent response appears in message list
  - Agent message shows agent name/avatar
  - Agent message shows timestamp
  - Agent message is visually distinct from user messages

**US4: User sees streaming responses**
- As a user, I want to see agent responses stream in real-time so I don't wait
- AC:
  - Agent response appears character by character (or chunk by chunk)
  - Typing indicator shows while agent is generating
  - Typing indicator disappears when complete
  - Streaming stops smoothly (no flickering)

**US5: User can read formatted responses**
- As a user, I want to see formatted text so I can read code and structured content
- AC:
  - Markdown renders correctly (headers, lists, bold, italic)
  - Code blocks have syntax highlighting
  - Code blocks have language labels
  - Code blocks can be copied (copy button)

**US6: User can manage conversations**
- As a user, I want to manage multiple conversations so I can organize topics
- AC:
  - User can start a new conversation
  - User sees conversation list in sidebar
  - User can switch between conversations
  - User can see conversation titles (first message or auto-generated)
  - User can delete conversations

### API Contracts and Data Flow

**JidoMessaging Integration:**
```elixir
# Room entity (conversation container)
%JidoMessaging.Room{
  id: "room_123",
  instance_id: "default",  # Multi-tenancy
  participants: ["user_123", "agent_default"],
  metadata: %{title: "My Conversation"}
}

# Message entity (LLM-native with content blocks)
%JidoMessaging.Message{
  id: "msg_456",
  room_id: "room_123",
  from: "user_123",
  to: "agent_default",
  role: :user,  # :user | :assistant | :system
  content: [
    {%JidoMessaging.Content.Text{}, "Hello, can you help me?"}
  ],
  metadata: %{timestamp: DateTime.utc_now()}
}
```

**LiveView Data Flow:**
```
User types message
  → handle_event("send_message")
  → JidoMessaging.send_message(room_id, user_id, content)
  → Broadcast via Phoenix.PubSub
  → Agent runner receives message
  → Agent processes via jido_ai
  → Agent sends response via JidoMessaging
  → PubSub broadcast to LiveView
  → handle_info({:new_message, message})
  → stream_insert(:messages, message)
  → UI updates
```

**Streaming Data Flow:**
```
Agent starts generating response
  → JidoMessaging.send_message_start(room_id, agent_id)
  → PubSub broadcast
  → handle_info({:message_stream_start, message_id})
  → Assign streaming flag

Agent sends chunk
  → JidoMessaging.send_chunk(room_id, message_id, chunk)
  → PubSub broadcast
  → handle_info({:message_chunk, message_id, chunk})
  → Append to current_stream assign
  → UI updates incrementally

Agent completes
  → JidoMessaging.send_message_complete(room_id, message_id)
  → PubSub broadcast
  → handle_info({:message_stream_complete, message_id})
  → Convert stream to final message
  → Insert into messages stream
```

### State Management Requirements

**LiveView Assigns:**
- `current_user` - From authentication
- `room` - Current conversation room
- `messages` - Stream of messages (via LiveView streams)
- `current_stream` - Active streaming response (if any)
- `streaming?` - Boolean flag for streaming state
- `conversations` - List of user's conversations
- `draft_message` - Current input (for draft persistence)

**Component State:**
- MessageComponent: `@message` - Message entity
- ChatInputComponent: `@draft` - Current input
- TypingIndicatorComponent: `@agents` - List of typing agents

### Error Handling Approach

**Connection Errors:**
- Show banner: "Connection lost. Reconnecting..."
- Auto-reconnect with exponential backoff
- Disable input while disconnected

**Send Errors:**
- Show inline error: "Failed to send. Click to retry."
- Keep message in draft
- Enable retry button

**Agent Errors:**
- Display error message from agent
- Show "Something went wrong" UI
- Offer option to retry or start new conversation

**Timeout Errors:**
- Show "Agent took too long to respond" message
- Offer option to retry or skip

## Technical Design

### Data Model Changes

**No Ash resources needed** - use jido_messaging entities directly:
- `JidoMessaging.Room` - Conversation container
- `JidoMessaging.Message` - Message with content blocks
- `JidoMessaging.Participant` - User or agent in room

**If jido_messaging is not ready:** Create mock module:
```elixir
# lib/jido_hub/messaging_mock.ex
defmodule JidoHub.MessagingMock do
  def list_rooms(user_id), do: [...]
  def get_room(room_id), do: %{}
  def create_room(user_id), do: {:ok, %{}}
  def send_message(room_id, from, to, content), do: :ok
  def subscribe(room_id), do: :ok
end
```

### Module Organization

**New Chat Modules:**
```
lib/jido_hub_web/
  ├── live/
  │   ├── chat_live.ex                  # Main chat LiveView
  │   ├── chat_live.html.heex           # Chat UI template
  │   └── components/
  │       ├── message_component.ex      # Message bubble
  │       ├── chat_input_component.ex   # Message input
  │       ├── conversation_list_component.ex  # Sidebar
  │       ├── typing_indicator_component.ex   # Typing indicator
  │       ├── streaming_message_component.ex  # Streaming wrapper
  │       ├── markdown_component.ex     # Markdown renderer
  │       └── code_block_component.ex   # Code highlighter
  └── chat/
      └── subscriber.ex                 # PubSub manager (optional)
```

**Test Modules:**
```
test/
  ├── jido_hub_web/
  │   ├── live/
  │   │   ├── chat_live_test.ex         # LiveView tests
  │   │   └── components/
  │   │       └── message_component_test.ex
  └── support/
      └── chat_helpers.ex               # Test fixtures
```

### Third-Party Integration Details

**Markdown Rendering - Earmark:**
```elixir
# mix.exs
{:earmark, "~> 1.4"}

# Usage
{:ok, html, _errors} = Earmark.as_html(markdown)
```

**Code Highlighting - Makeup:**
```elixir
# mix.exs
{:makeup, "~> 1.1"}

# Usage
 Makeup.highlight(Formatters.HTML.HTML, code, language: "elixir")
```

**XSS Prevention - HTMLSanitizeEx:**
```elixir
# mix.exs
{:html_sanitize_ex, "~> 0.4"}

# Usage
HTMLSanitizeEx.html5(user_input)
```

**Note:** User decision required on makeup vs makeup_elixir (pure Elixir vs Python dependency)

### Configuration/Environment Changes

**config/dev.exs:**
```elixir
# Use in-memory adapter for development
config :jido_messaging, :adapter, JidoMessaging.Adapters.ETS
```

**config/prod.exs:**
```elixir
# Use PostgreSQL adapter for production
config :jido_messaging, :adapter, JidoMessaging.Adapters.Postgres
```

**config/runtime.exs:**
```elixir
# Runtime configuration for messaging instance
if config_env() == :prod do
  config :jido_messaging,
    instance_name: System.get_env("JIDO_MESSAGING_INSTANCE", "default")
end
```

**mix.exs (add dependencies):**
```elixir
defp deps do
  [
    # ... existing deps
    {:earmark, "~> 1.4"},           # Markdown rendering
    {:makeup, "~> 1.1"},            # Code highlighting (pure Elixir)
    # OR {:makeup_elixir, "~> 0.1"}, # Code highlighting (more languages)
    {:html_sanitize_ex, "~> 0.4"}   # XSS prevention
  ]
end
```

## Implementation Phases

### Phase 1: Foundation (Basic Chat UI)

**Objective:** Create basic chat interface with message list and input.

**Success Criteria:**
- Chat page accessible at `/chat`
- User sees empty message list
- User can type and send messages
- Messages appear in list
- Basic styling (user vs agent messages)

**Tasks:**
1. Create `chat_live.ex` with mount/3 and render/1
2. Create `chat_live.html.heex` with message container and input
3. Create `message_component.ex` for message bubbles
4. Create `chat_input_component.ex` for text input
5. Add chat route to router.ex
6. Add chat link to navigation

**Files to Create:**
- `projects/jido_hub/lib/jido_hub_web/live/chat_live.ex` (NEW)
- `projects/jido_hub/lib/jido_hub_web/live/chat_live.html.heex` (NEW)
- `projects/jido_hub/lib/jido_hub_web/live/components/message_component.ex` (NEW)
- `projects/jido_hub/lib/jido_hub_web/live/components/chat_input_component.ex` (NEW)

**Files to Modify:**
- `projects/jido_hub/lib/jido_hub_web/router.ex` (MODIFY - add chat route)
- `projects/jido_hub/lib/jido_hub_web/components/layouts.ex` (MODIFY - add chat nav)

**Tests to Add:**
- Test chat page loads
- Test user can send message
- Test message appears in list
- Test input clears after send

**Dependencies:** Item 021 complete, jido_messaging entities defined OR mock mode

**Deliverables:**
- Basic chat interface working
- Messages send and display
- User authentication required

---

### Phase 2: Real-Time Integration (Streaming & PubSub)

**Objective:** Integrate with jido_messaging and add real-time message updates.

**Success Criteria:**
- Chat integrates with jido_messaging Room/Message entities
- Messages persist to database (or ETS)
- Real-time message updates via Phoenix.PubSub
- Streaming responses display incrementally
- Typing indicators show agent activity

**Tasks:**
1. Integrate jido_messaging in ChatLive mount
2. Subscribe to room via Phoenix.PubSub
3. Handle incoming messages via handle_info/2
4. Implement streaming message state
5. Create typing_indicator_component.ex
6. Create streaming_message_component.ex
7. Add PubSub subscription manager (optional)

**Files to Create:**
- `projects/jido_hub/lib/jido_hub_web/live/components/typing_indicator_component.ex` (NEW)
- `projects/jido_hub/lib/jido_hub_web/live/components/streaming_message_component.ex` (NEW)
- `projects/jido_hub/lib/jido_hub_web/chat/subscriber.ex` (NEW - optional)

**Files to Modify:**
- `projects/jido_hub/lib/jido_hub_web/live/chat_live.ex` (MODIFY - add PubSub)
- `projects/jido_hub/lib/jido_hub/application.ex` (MODIFY - add supervisors if needed)

**Tests to Add:**
- Test PubSub subscription
- Test real-time message updates
- Test streaming message display
- Test typing indicator

**Dependencies:** Phase 1 complete, jido_messaging PubSub integration

**Deliverables:**
- Real-time message updates working
- Streaming responses display
- Typing indicators functional

---

### Phase 3: Rich Content (Markdown & Code)

**Objective:** Add markdown rendering and code highlighting to messages.

**Success Criteria:**
- Markdown renders correctly (headers, lists, formatting)
- Code blocks have syntax highlighting
- Code blocks have language labels
- Code blocks have copy button
- XSS protection on all user/agent content

**Tasks:**
1. Add earmark dependency to mix.exs
2. Add makeup dependency to mix.exs
3. Create markdown_component.ex with sanitization
4. Create code_block_component.ex with highlighting
5. Update message_component.ex to use markdown
6. Add copy button to code blocks
7. Test XSS prevention

**Files to Create:**
- `projects/jido_hub/lib/jido_hub_web/live/components/markdown_component.ex` (NEW)
- `projects/jido_hub/lib/jido_hub_web/live/components/code_block_component.ex` (NEW)

**Files to Modify:**
- `projects/jido_hub/lib/jido_hub_web/live/components/message_component.ex` (MODIFY - markdown)
- `projects/jido_hub/lib/jido_hub_web/live/chat_live.html.heex` (MODIFY - streaming UI)
- `projects/jido_hub/mix.exs` (MODIFY - add deps)

**Tests to Add:**
- Test markdown rendering (headers, lists, code)
- Test code highlighting (multiple languages)
- Test XSS sanitization
- Test copy button

**Dependencies:** Phase 2 complete, earmark/makeup/HTMLSanitizeEx added

**Deliverables:**
- Rich content rendering working
- Code highlighting functional
- XSS protection verified

---

### Phase 4: Conversation Management & Polish

**Objective:** Add conversation sidebar, conversation management, and final polish.

**Success Criteria:**
- User can create new conversations
- User sees conversation list in sidebar
- User can switch between conversations
- User can delete conversations
- Mobile responsive (sidebar collapses)
- Loading states and error handling

**Tasks:**
1. Create conversation_list_component.ex
2. Add conversation CRUD operations
3. Implement conversation switching
4. Add delete conversation functionality
5. Add mobile responsive sidebar
6. Add loading states
7. Add error handling and retry
8. Add accessibility (ARIA labels, keyboard nav)

**Files to Create:**
- `projects/jido_hub/lib/jido_hub_web/live/components/conversation_list_component.ex` (NEW)
- `projects/jido_hub/test/jido_hub_web/live/chat_live_test.ex` (NEW)
- `projects/jido_hub/test/jido_hub_web/live/components/message_component_test.ex` (NEW)
- `projects/jido_hub/test/support/chat_helpers.ex` (NEW)

**Files to Modify:**
- `projects/jido_hub/lib/jido_hub_web/live/chat_live.ex` (MODIFY - conversation mgmt)
- `projects/jido_hub/lib/jido_hub_web/live/chat_live.html.heex` (MODIFY - sidebar)
- `projects/jido_hub/lib/jido_hub_web/components/layouts.ex` (MODIFY - layout)
- `projects/jido_hub/config/dev.exs` (MODIFY - adapter config)
- `projects/jido_hub/config/prod.exs` (MODIFY - adapter config)

**Tests to Add:**
- Test conversation creation
- Test conversation switching
- Test conversation deletion
- Test mobile responsive
- Test accessibility
- E2E test with PhoenixTest.Playwright

**Dependencies:** Phase 3 complete

**Deliverables:**
- Full LibreChat-style interface working
- Conversation management functional
- All tests passing
- Accessibility verified

---

## Quality & Testing Strategy

### Test Categories

**Unit Tests:**
- MessageComponent rendering
- MarkdownComponent sanitization
- CodeBlockComponent highlighting
- ChatInputComponent validation

**Integration Tests:**
- ChatLive mount and handle_event
- PubSub subscription and broadcasts
- Streaming message flow
- Conversation CRUD operations

**E2E Tests:**
- Complete user chat flow (PhoenixTest.Playwright)
- Agent response flow with streaming
- Conversation switching
- Mobile responsive
- Accessibility

### Coverage Targets

**Current:** 80% minimum (jido_hub standard)
**Goal:** 85%+ for new chat code
**Focus Areas:**
- Message rendering and sanitization (100% - security critical)
- Streaming logic (95% - complex state)
- Conversation management (90% - business logic)

### Quality Gates

**Pre-commit:**
- `mix format --check-formatted`
- `mix compile --warnings-as-errors`

**Pre-PR:**
- `mix test` (all tests pass)
- `mix coveralls` (85%+ coverage)
- `mix credo` (no warnings)
- `mix sobelow` (no security issues)

**Pre-merge:**
- All above checks
- Manual accessibility audit
- Manual mobile responsive test
- E2E tests pass

## Risk Assessment

### Technical Risks

**Risk 1: JidoMessaging Not Ready**
- **Impact:** HIGH - Blocks full integration
- **Probability:** HIGH - Currently vision-only
- **Mitigation:** Create mock module for development, define integration interface
- **Contingency:** Implement with mock data, integrate real API when ready

**Risk 2: Streaming Performance**
- **Impact:** MEDIUM - Could cause UI lag
- **Probability:** MEDIUM - LiveView streams can be tricky
- **Mitigation:** Use chunking, limit stream length, optimize updates
- **Contingency:** Fallback to non-streaming if performance issues

**Risk 3: XSS in Markdown/Code**
- **Impact:** HIGH - Security vulnerability
- **Probability:** MEDIUM - User/agent content is untrusted
- **Mitigation:** Sanitize all content with HTMLSanitizeEx, test XSS vectors
- **Contingency:** Disable markdown if security issues found

**Risk 4: Agent Integration Unclear**
- **Impact:** MEDIUM - How agents connect to rooms?
- **Probability:** MEDIUM - Agent runner pattern undefined
- **Mitigation:** Define agent API contract, create mock agent for testing
- **Contingency:** Mock agent responses for MVP

### Dependency Risks

**Risk 1: Earmark/Makeup Breaking Changes**
- **Impact:** LOW - Well-established libraries
- **Probability:** LOW - Stable versions
- **Mitigation:** Pin versions in mix.lock

**Risk 2: Phoenix LiveView Version**
- **Impact:** LOW - Using 1.1.0 (stable)
- **Probability:** LOW - No breaking changes expected
- **Mitigation:** Follow LiveView best practices

### Timeline Risks

**Risk 1: Scope Creep**
- **Impact:** MEDIUM - Adding too many features
- **Probability:** MEDIUM - Temptation to add more
- **Mitigation:** Strictly follow 4-phase plan, defer advanced features
- **Contingency:** Cut streaming or markdown if timeline issues

**Risk 2: JidoMessaging Delays**
- **Impact:** HIGH - Blocks integration
- **Probability:** HIGH - Implementation not started
- **Mitigation:** Mock mode for development, parallel work on jido_messaging
- **Contingency:** Implement basic chat without jido_messaging, integrate later

## Success Criteria

### Measurable Outcomes

1. **Chat Interface Functional:**
   - Chat page accessible at `/chat`
   - User can send messages
   - Agent responses display
   - Messages persist across sessions

2. **Real-Time Features Working:**
   - Streaming responses display incrementally
   - Typing indicators show
   - Real-time message updates work

3. **Rich Content Rendering:**
   - Markdown renders correctly
   - Code blocks have highlighting
   - XSS protection verified

4. **Conversation Management:**
   - User can create conversations
   - User can switch conversations
   - User can delete conversations

5. **Quality Standards Met:**
   - 85%+ test coverage
   - All quality gates pass
   - Accessibility verified
   - Mobile responsive

### Definition of "Done"

This item is complete when:
1. All 4 phases are complete
2. Chat interface matches LibreChat patterns (message bubbles, sidebar, streaming)
3. Integration with jido_messaging working (or mock mode verified)
4. All tests passing (unit, integration, E2E)
5. Test coverage >= 85%
6. Quality gates passing (format, credo, sobelow)
7. Accessibility audit passed
8. Mobile responsive verified
9. Documentation complete (README, code comments)
10. Demo video or screenshots available

### Acceptance Testing Approach

**Manual Testing:**
1. Create new conversation
2. Send message to agent
3. Verify streaming response
4. Verify markdown rendering
5. Verify code highlighting
6. Create second conversation
7. Switch between conversations
8. Delete conversation
9. Test on mobile device
10. Test accessibility (keyboard nav, screen reader)

**Automated Testing:**
1. Unit tests for all components
2. Integration tests for LiveView
3. E2E tests with PhoenixTest.Playwright
4. XSS vector tests
5. Performance tests (streaming)

**User Acceptance:**
1. Demo to stakeholders
2. Feedback session
3. Bug fixes
4. Final sign-off

## Dependencies & Blockers

### Dependencies

**Required:**
- Item 021 (Phoenix project setup) - Must be complete
- jido_messaging entities - Room/Message/Participant defined
- Phoenix.PubSub - Already available
- AshAuthentication - Already configured

**Optional (can mock):**
- Agent integration - Can mock agent responses
- PostgreSQL adapter - Can use ETS for dev

### Blockers

**JidoMessaging Implementation Status**
- Blocks: Full integration testing
- Does not block: UI development (can use mock)
- Resolution: Coordinate with jido_messaging implementation (Item 020)

**Agent Integration Pattern**
- Blocks: Real agent responses
- Does not block: UI development (can mock)
- Resolution: Define agent API contract, create mock agent

**Markdown/Code Library Decision**
- Blocks: Rich content rendering
- Does not block: Basic chat (Phase 1)
- Resolution: User decision required (earmark vs markdown, makeup vs makeup_elixir)

### Predecessors

- Item 021: Phoenix project setup (must be complete)
- Item 020: jido_messaging initial implementation (should be in progress)

### Successors

- Item 023: Integration with Jido agents (depends on this item's chat interface)

## Notes

### Assumptions

1. jido_messaging will implement Room/Message/Participant entities
2. Agent responses will be LLM-generated and may support streaming
3. Users are authenticated via AshAuthentication
4. Conversations belong to users (not shared in MVP)
5. Message persistence uses PostgreSQL in production

### User Decisions Required

1. **Markdown library:** earmark (lightweight) vs markdown (feature-rich)?
2. **Code highlighting:** makeup (pure Elixir) vs makeup_elixir (more languages, Python dep)?
3. **Content types MVP:** Text only vs text+markdown vs text+markdown+images?
4. **Conversation persistence:** Ephemeral vs persistent vs hybrid?
5. **Multi-tenancy:** How are conversations scoped to users/organizations?

### Open Questions

1. **How do agents connect to messaging rooms?**
   - Agent runner pattern?
   - Registration API?
   - Resolution: Coordinate with agent integration design

2. **What's the streaming protocol?**
   - Server-Sent Events?
   - WebSocket chunks?
   - Phoenix.LiveView stream assigns?
   - Resolution: Use LiveView assigns for simplicity

3. **Should we support attachments in MVP?**
   - Images?
   - Files?
   - Resolution: Defer to Phase 4 or future item

### Design Decisions Made

1. **Phoenix LiveView for UI** - Server-rendered, no client-side framework
2. **LibreChat-style UI** - Message bubbles, sidebar, streaming
3. **Markdown + Code highlighting** - Use earmark and makeup
4. **XSS prevention** - Sanitize all content with HTMLSanitizeEx
5. **Streaming by default** - All agent responses stream
6. **Mock mode for development** - Don't block on jido_messaging

---

## Next Steps After This Item

1. **Item 023:** Integration with Jido agents (real agent responses)
2. **jido_messaging:** Complete Room/Message/Participant implementation
3. **Agent runner:** Define how agents connect to messaging rooms
4. **Advanced features:** File uploads, voice input, multi-agent conversations (future items)
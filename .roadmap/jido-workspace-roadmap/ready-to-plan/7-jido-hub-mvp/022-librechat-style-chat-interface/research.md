# Research: LibreChat-style Chat Interface for Jido Hub

**Item ID:** 022-librechat-style-chat-interface
**Date:** 2025-01-07
**Status:** Researched

---

## Executive Summary

This research analyzes the requirements for implementing a LibreChat-style chat interface in `jido_hub` that integrates with the `jido_messaging` layer. The implementation will leverage Phoenix LiveView 1.1.0 for real-time chat capabilities, streaming LLM responses, and modern chat UI patterns.

**Key Finding:** `jido_messaging` is currently in early development (vision document only) with minimal implementation. The chat interface should be designed to work with the planned message structure (Room, Message, Participant entities) and should accommodate both the in-memory ETS adapter and future PostgreSQL persistence.

---

## 1. Project Dependencies Discovered

### From `projects/jido_hub/mix.exs`:
- **Phoenix Framework:** `~> 1.8.1`
- **Phoenix LiveView:** `~> 1.1.0` ✅ (Perfect for chat interfaces)
- **Phoenix.HTML:** `~> 4.1`
- **Phoenix.PubSub:** (via Phoenix, for real-time broadcasting)
- **Bandit:** `~> 1.5` (HTTP server)
- **DaisyUI Components:** `~> 0.9.2` (CSS framework for UI)
- **Heroicons:** v2.2.0 (icons)
- **Lucide Icons:** `~> 2.0` (additional icons)
- **Ash Framework:** `~> 3.0` (domain modeling, though chat may use jido_messaging directly)

### From `projects/jido_messaging/mix.exs`:
- **Zoi:** `~> 0.14` (schema validation)
- **Jason:** `~> 1.4` (JSON encoding)

### Authentication approach:
- **AshAuthentication:** `~> 4.0` with magic link support
- User sessions managed via Phoenix LiveView `on_mount` hooks

### Testing framework:
- **ExUnit** (standard Elixir testing)
- **PhoenixTest.Playwright:** `~> 0.1` (end-to-end testing)
- **Quokka:** `~> 2.11` (dev/testing utilities)

---

## 2. Files Requiring Changes

### New Files to Create

#### Core Chat LiveView
- `lib/jido_hub_web/live/chat_live.ex` - Main chat LiveView
  - 📖 [Phoenix.LiveView module docs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html)
  - 📖 [LiveView lifecycle callbacks](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#callbacks)
  - **Pattern:** Follow existing `DashboardLive` structure in `lib/jido_hub_web/live/dashboard_live.ex:1`

#### Chat Template
- `lib/jido_hub_web/live/chat_live.html.heex` - Chat UI template
  - 📖 [HEEx templates guide](https://hexdocs.pm/phoenix_live_view/assigns-eex.html)
  - 📖 [Function components](https://hexdocs.pm/phoenix/phoenix_component.html)
  - **Pattern:** Follow existing component patterns in `lib/jido_hub_web/components/core_components.ex`

#### Chat Components
- `lib/jido_hub_web/live/components/message_component.ex` - Message rendering
  - 📖 [LiveComponent docs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveComponent.html)
- `lib/jido_hub_web/live/components/chat_input_component.ex` - Message input
- `lib/jido_hub_web/live/components/conversation_sidebar_component.ex` - Conversation list

#### Routing
- `lib/jido_hub_web/router.ex:97` - Add chat routes
  - Add `live "/chat", ChatLive, :index` under authenticated scope
  - **Pattern:** Follow existing routing pattern for `DashboardLive` at line 103

### Files to Modify

#### Router
- `lib/jido_hub_web/router.ex` - Add chat route in authenticated section
  - 📖 [Phoenix Router docs](https://hexdocs.pm/phoenix/Phoenix.Router.html)
  - **Location:** After line 103 (DashboardLive route)

#### Navigation/Layout
- `lib/jido_hub_web/components/dashboard_nav.ex` - Add chat navigation link
- `lib/jido_hub_web/components/layouts.ex` - Ensure chat layout support

#### Application
- `lib/jido_hub/application.ex` - Add chat-related supervisors if needed
  - **Current pattern:** Uses Ash and existing supervision tree

### Configuration Files
- `config/dev.exs` - Configure jido_messaging adapter (ETS for dev)
- `config/prod.exs` - Configure PostgreSQL adapter for production
- `config/runtime.exs` - Runtime configuration for messaging

---

## 3. Existing Patterns Found

### LiveView Pattern
**Project uses Phoenix LiveView with:**
- `use JidoHubWeb, :live_view` module attribute (see `DashboardLive:2`)
- `mount/3` callback for initialization (see `DashboardLive:8-32`)
- `handle_event/3` for user interactions (see `DashboardLive:40-102`)
- `handle_info/2` for PubSub broadcasts (see `DashboardLive:112-162`)
- `render/1` with HEEx template (see `DashboardLive:204-221`)

**Example found in:** `lib/jido_hub_web/live/dashboard_live.ex:1-223`
**📖 [LiveView patterns guide](https://hexdocs.pm/phoenix_live_view/patterns.html)**

### Authentication Pattern
**Project uses AshAuthentication with:**
- LiveView `on_mount` hooks for auth gates
- `JidoHubWeb.LiveUserAuth` module for required/optional auth
- Pattern: `on_mount: [{JidoHubWeb.LiveUserAuth, :live_user_required}]`

**Example found in:** `lib/jido_hub_web/router.ex:100-102`
**📖 [AshAuthentication.Phoenix docs](https://hexdocs.pm/ash_authentication_phoenix/AshAuthentication.Phoenix.Router.html)**

### Component Pattern
**Project uses:**
- Function components in `CoreComponents` module
- HEEx templates with `~H` sigil
- DaisyUI CSS classes for styling
- Slots for flexible composition

**Example found in:** `lib/jido_hub_web/components/core_components.ex`
**📖 [DaisyUI components docs](https://hexdocs.pm/daisy_ui_components)**

### PubSub Pattern
**Phoenix PubSub is available via Phoenix application:**
- Used for broadcasting message updates
- Subscribe to room-specific topics
- Pattern: `Phoenix.PubSub.subscribe(JidoHub.PubSub, "room:#{room_id}")`

**📖 [Phoenix.PubSub docs](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html)**

---

## 4. Integration Points

### JidoMessaging Layer Integration

**Current Status:** `jido_messaging` is in early development (vision document only)

**Planned Integration:**
- **Room entity:** Represents a conversation/chat
- **Message entity:** LLM-native message structure with content blocks
- **Participant entity:** Users and agents in conversations

**Integration Pattern:**
```elixir
# In ChatLive mount
room = JidoMessaging.get_room(room_id)
JidoMessaging.subscribe(room_id)
messages = JidoMessaging.list_messages(room_id, limit: 50)

# In handle_info for new messages
def handle_info({:message_sent, message}, socket) do
  {:noreply, stream_insert(socket, :messages, message)}
end
```

**📖 [JidoMessaging Vision](../../projects/jido_messaging/JIDO_MESSAGING_VISION.md)** - Complete architecture

### Database: PostgreSQL via AshPostgres
- **Current schema patterns:** Ash resources with PostgreSQL
- **Future:** `jido_messaging` will have PostgreSQL adapter
- **Dev:** Can use ETS adapter for in-memory testing

**📖 [AshPostgres docs](https://hexdocs.pm/ash_postgres/AshPostgres.html)**

### Real-time Communication
- **Phoenix LiveView WebSocket:** Built-in at `/live` socket (see `Endpoint:14-16`)
- **Phoenix.PubSub:** For broadcasting messages to connected clients
- **Presence tracking:** For showing typing indicators, online status

**📖 [Phoenix.PubSub docs](https://hexdocs.pm/phoenix_pubsub/)**

---

## 5. Test Impact & Patterns

### Tests to Create
- `test/jido_hub_web/live/chat_live_test.ex` - LiveView tests
- `test/jido_hub_web/live/components/message_component_test.ex` - Component tests
- `test/support/messaging_helpers.ex` - Test fixtures and helpers

### Current Testing Patterns
- **ExUnit** for unit/integration tests
- **PhoenixTest.Playwright** for E2E browser tests
- **DataCase** for database tests (see `test/support/data_case.ex`)
- **ConnCase** for connection tests (see `test/support/conn_case.ex`)

### Testing Patterns to Follow
```elixir
# LiveView test example (based on existing patterns)
use JidoHubWeb.ConnCase

import Phoenix.LiveViewTest

test "user can send a message", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/chat")

  view
  |> element("#message-input")
  |> render_change(%{message: %{content: "Hello"}})

  assert has_element?(view, "[data-role='assistant']")
end
```

**📖 [Phoenix.LiveViewTest docs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveViewTest.html)**

### Mocking Strategy
- **Mox** not currently in dependencies
- Use `jido_messaging` ETS adapter for testing (no DB required)
- Mock LLM responses via test helpers

---

## 6. Configuration & Environment

### Config Files to Update

#### `config/dev.exs`
```elixir
# Use in-memory adapter for development
config :jido_messaging, :adapter, JidoMessaging.Adapters.ETS
```

#### `config/prod.exs`
```elixir
# Use PostgreSQL adapter for production
config :jido_messaging, :adapter, JidoMessaging.Adapters.Postgres
```

#### `config/runtime.exs`
```elixir
# Runtime configuration for messaging instance
if config_env() == :prod do
  config :jido_messaging,
    instance_name: System.get_env("JIDO_MESSAGING_INSTANCE", "default")
end
```

### Environment Variables
- `JIDO_MESSAGING_INSTANCE` - Instance name for multi-tenancy
- `JIDO_MESSAGING_ADAPTER` - Override adapter selection
- `DATABASE_URL` - PostgreSQL connection (for prod adapter)

### Build/Deployment Implications
- No new build steps required (Phoenix LiveView compiles with app)
- Asset pipeline: Tailwind CSS already configured
- Hot reload: Works in development via Phoenix.LiveReloader

---

## 7. Required New Dependencies/Patterns

### ⚠️ **User Decision Required:**

#### Markdown Rendering
**Task requires:** Markdown support for AI responses (code blocks, formatting)

**Options:**
1. **Use `earmark`** (Lightweight, CommonMark-compliant)
   - Pros: Simple, fast, widely used
   - Cons: Limited extensibility
2. **Use `markdown`** (Feature-rich, GitHub-flavored)
   - Pros: More features, custom renderers
   - Cons: Heavier dependency
3. **Use `marked`** (JavaScript-based, via Phoenix LiveView JS)
   - Pros: Client-side rendering, no server cost
   - Cons: Security concerns (XSS), more complex

**Recommendation:** Use `earmark` for server-side rendering with sanitization

#### Code Syntax Highlighting
**Task requires:** Code block syntax highlighting

**Options:**
1. **Use `makeup_elixir`** (Pygments wrapper)
   - Pros: Supports 200+ languages, fast
   - Cons: External Python dependency
2. **Use `makeup`** (Pure Elixir)
   - Pros: Pure Elixir, no external deps
   - Cons: Fewer languages supported
3. **Client-side highlighting** (Prism.js, highlight.js)
   - Pros: No server cost, rich themes
   - Cons: Larger bundle size, XSS risk

**Recommendation:** Use `makeup` with common languages

#### Streaming Implementation
**Task requires:** Real-time streaming of LLM responses

**Pattern:**
```elixir
# Use Phoenix.LiveView stream for efficient updates
stream(socket, :messages, messages)

# For streaming content within a message
assign(socket, :current_stream, "")
# Update as chunks arrive
assign(socket, :current_stream, socket.assigns.current_stream <> chunk)
```

**📖 [LiveView streams guide](https://hexdocs.pm/phoenix_live_view/bindings.html#streams)**

---

## 8. Risk Assessment

### Breaking Changes
- **Low risk:** New feature, no existing chat to break
- **Medium risk:** `jido_messaging` API may evolve during implementation

### Performance Implications
- **Message list:** Use LiveView streams for efficiency (don't keep all messages in assigns)
- **Streaming:** Chunk responses to avoid blocking
- **Database:** Pagination for message history (limit to last 50-100 messages)

**📖 [LiveView performance guide](https://hexdocs.pm/phoenix_live_view/performance.html)**

### Security Touchpoints
- **XSS prevention:** Sanitize markdown/HTML from AI responses
- **CSRF:** Phoenix.LiveView handles automatically
- **Rate limiting:** Use existing `JidoHubWeb.Plugs.RateLimit`
- **Message access control:** Enforce room membership via `jido_messaging` permissions

**📖 [Phoenix security guide](https://hexdocs.pm/phoenix/security.html)**

### Migration Complexity
- **Low:** New feature, no data migration required
- **Medium:** `jido_messaging` schema may require migrations as it evolves
- **Future:** Migration path from ETS to PostgreSQL should be seamless

---

## 9. Third-Party Integrations & External Services

### LLM Provider Integration

**Service Detection Results:**
- **Detected:** "wired to the jido_messaging layer" + "Jido agent"
- **Integration Type:** Chat interface → Jido Agent → LLM Provider
- **Context:** Chat UI sends messages to agents, which may use LLMs

**Current Status:**
- Jido agents are managed via `jido` and `jido_ai` projects
- LLM calls likely use `req_llm` library (in workspace dependencies)

**Integration Pattern:**
```elixir
# Chat UI sends message to room
JidoMessaging.send_message(room_id, participant_id, content)

# Agent runner in room receives message
# Agent processes via jido_ai
# Agent sends response back to room
JidoMessaging.send_message(room_id, agent_participant_id, response_content)
```

**📖 [req_llm docs](https://hexdocs.pm/req_llm/)** - LLM client library
**📖 [jido_ai project](../../projects/jido_ai/)** - Agent AI integration

---

## 10. Unclear Areas Requiring Clarification

### 1. JidoMessaging Implementation Status
- **Question:** Is `jido_messaging` implemented beyond the vision document?
- **Impact:** Chat interface depends on Room/Message/Participant entities
- **Recommendation:** Review `projects/jido_messaging/lib/` for current implementation status

### 2. Agent Integration Pattern
- **Question:** How do Jido agents connect to messaging rooms?
- **Context:** Vision document mentions `AgentRunner` but implementation unclear
- **Recommendation:** Define agent registration API before implementing chat UI

### 3. Message Content Structure
- **Question:** What content types should be supported initially?
- **Options:**
  - MVP: Text only
  - V1: Text + code blocks + markdown
  - V2: Text + code + images + file attachments
- **Recommendation:** Start with text + markdown (LibreChat-style)

### 4. Conversation Persistence
- **Question:** Should conversations be persistent across sessions?
- **Options:**
  - Ephemeral (in-memory only)
  - Persistent (PostgreSQL)
  - Hybrid (recent in memory, older in DB)
- **Recommendation:** Use PostgreSQL adapter for production

### 5. Multi-Tenancy
- **Question:** How are conversations scoped to users/organizations?
- **Context:** JidoHub has organizations and pods
- **Recommendation:** Conversations belong to users, shared via organization

---

## 11. Implementation Recommendations

### Phase 1: MVP (Minimum Viable Chat)
1. **Basic chat UI** with message list and input
2. **Simple message rendering** (text only)
3. **Conversation creation** (new chat button)
4. **Agent response** (mock or simple echo)
5. **Authentication** (user must be logged in)

### Phase 2: Real-Time Streaming
1. **LiveView streams** for message updates
2. **Streaming LLM responses** (chunk by chunk)
3. **Typing indicators**
4. **Phoenix.PubSub** for real-time broadcasts

### Phase 3: Rich Content
1. **Markdown rendering** (earmark)
2. **Code highlighting** (makeup)
3. **Message history** with pagination
4. **Conversation management** (rename, delete, search)

### Phase 4: Advanced Features
1. **File uploads** (images, documents)
2. **Voice input** (Web Speech API)
3. **Multi-agent conversations**
4. **Context management** (token tracking, custom instructions)

---

## 12. Documentation Links

### Phoenix LiveView
- 📖 [Welcome to LiveView](https://hexdocs.pm/phoenix_live_view/welcome.html)
- 📖 [LiveView module docs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html)
- 📖 [Assigns and HEEx](https://hexdocs.pm/phoenix_live_view/assigns-eex.html)
- 📖 [JavaScript interop](https://hexdocs.pm/phoenix_live_view/js-interop.html)
- 📖 [Bindings reference](https://hexdocs.pm/phoenix_live_view/bindings.html)
- 📖 [Uploads guide](https://hexdocs.pm/phoenix_live_view/uploads.html)
- 📖 [Streaming guide](https://hexdocs.pm/phoenix_live_view/bindings.html#streams)

### Jido Ecosystem
- 📖 [JidoMessaging Vision](../../projects/jido_messaging/JIDO_MESSAGING_VISION.md)
- 📖 [Jido Hub README](../../projects/jido_hub/README.md) (if exists)
- 📖 [Jido Agent docs](../../projects/jido/README.md) (if exists)

### Chat UI Patterns
- 📖 [LibreChat GitHub](https://github.com/danny-avila/LibreChat)
- 📖 [Building a Chat App with LiveView Streams](https://fly.io/phoenix-files/building-a-chat-app-with-liveview-streams/)
- 📖 [Stream Chat LiveView Example](https://github.com/SophieDeBenedetto/stream_chat)

### Markdown/Code Highlighting
- 📖 [Earmark docs](https://hexdocs.pm/earmark)
- 📖 [Makeup docs](https://hexdocs.pm/makeup)
- 📖 [HTMLSanitizeEx docs](https://hexdocs.pm/html_sanitize_ex) - XSS prevention

---

## 13. Next Steps

1. **Verify jido_messaging implementation status**
   - Check if Room/Message/Participant schemas exist
   - Confirm adapter availability (ETS and/or Postgres)

2. **Create basic chat LiveView**
   - Follow existing `DashboardLive` pattern
   - Implement message list and input components

3. **Integrate with jido_messaging**
   - Connect to Room entity
   - Subscribe to message broadcasts
   - Handle incoming messages

4. **Add streaming support**
   - Implement LiveView streams for messages
   - Add chunk-by-chunk response rendering

5. **Enhance UI with LibreChat patterns**
   - Add markdown rendering
   - Add code highlighting
   - Add conversation sidebar

---

**Research Complete:** Ready for planning phase

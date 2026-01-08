# Research: Phoenix Project Setup for Jido Hub

**Item ID:** 021-phoenix-project-setup
**Date:** 2026-01-07
**Status:** Researched

## Executive Summary

**CRITICAL FINDING:** The `jido_hub` Phoenix project **already exists** at `projects/jido_hub/` with a complete, production-ready setup. This task is not about creating a new Phoenix project from scratch, but rather **validating, documenting, and ensuring** the existing setup is ready for the chat UI and Jido agent integration features.

The existing project includes:
- ✅ Phoenix 1.8.1 with LiveView 1.1.0
- ✅ Ash Framework 3.0 (full-stack: Authentication, JSON API, PostgreSQL, Phoenix)
- ✅ Complete authentication system (AshAuthentication 4.0)
- ✅ Database setup (PostgreSQL with Ecto)
- ✅ Asset pipeline (esbuild, Tailwind CSS)
- ✅ Development tooling (LiveReload, LiveDashboard, AshAdmin)
- ✅ Testing infrastructure (ExUnit, ExCoveralls, PhoenixTest with Playwright)
- ✅ Security configurations (CSP, rate limiting, secure headers)
- ✅ API infrastructure (AshJsonApi, OpenAPI/Swagger)

## 1. Project Dependencies Discovered

### Core Phoenix Stack
From `projects/jido_hub/mix.exs`:
- **Phoenix:** 1.8.1 (stable, mature version)
- **Phoenix LiveView:** 1.1.0 (latest stable)
- **Phoenix LiveDashboard:** 0.8.3 (metrics and monitoring)
- **Phoenix Ecto:** 4.5 (database integration)
- **Phoenix HTML:** 4.1 (HTML rendering)
- **Bandit:** 1.5 (HTTP server - modern replacement for Cowboy)

### Ash Framework Ecosystem
- **Ash:** 3.0 (core resource framework)
- **AshAuthentication:** 4.0 (authentication system)
- **AshAuthenticationPhoenix:** 2.0 (Phoenix integration)
- **AshPhoenix:** 2.0 (LiveView integration)
- **AshPostgres:** 2.0 (PostgreSQL data layer)
- **AshJsonApi:** 1.0 (JSON:API endpoints)
- **AshAdmin:** 0.13 (admin interface)
- **AshOban:** 0.4 (background job integration)
- **AshPaperTrail:** 0.5 (auditing)
- **AshArchival:** 2.0 (soft deletes)
- **AshCloak:** 0.1 (encrypted fields)
- **AshAi:** 0.2 (AI integration - includes MCP dev tools)

### Frontend & Assets
- **esbuild:** 0.10 (JavaScript bundler)
- **Tailwind CSS:** 0.3 (CSS framework)
- **Heroicons:** v2.2.0 (icon library)
- **Lucide Icons:** 2.0 (additional icon set)
- **DaisyUI Components:** 0.9.2 (component library)
- **PhoenixStorybook:** 0.9.3 (component development, dev only)

### Authentication & Security
- **BcryptElixir:** 3.0 (password hashing)
- **Cloak:** 1.0 (data encryption)
- **PlugAttack:** 0.4 (rate limiting, abuse prevention)
- **ExRated:** 2.0 (rate limiting backend)

### Background Jobs & Processing
- **Oban:** 2.0 (job queue)
- **ObanWeb:** 2.0 (web UI for Oban)

### Database & Data
- **EctoSQL:** 3.13 (database wrapper)
- **Postgrex:** (PostgreSQL driver)

### HTTP & API
- **Req:** 0.5 (HTTP client)
- **OpenApiSpex:** 3.0 (OpenAPI/Swagger spec)
- **Jason:** 1.2 (JSON library)

### Development & Testing
- **Credo:** 1.7 (code quality)
- **Dialyxir:** 1.4 (dialyzer for type checking)
- **Sobelow:** 0.13 (security audit)
- **ExCoveralls:** 0.18 (test coverage)
- **Quokka:** 2.11 (test helpers)
- **PhoenixTestPlaywright:** 0.1 (end-to-end testing)
- **LiveDebugger:** 0.4 (LiveView debugging)
- **Tidewave:** 0.5 (error viewing, dev only)
- **Igniter:** 0.6 (code generation)

### Code Quality & Standards
- **Formatter:** Elixir standard formatter (`.formatter.exs` present)
- **Git Hooks:** Automated quality checks via aliases
- **Quality Gate:** `mix quality` alias runs format → compile → dialyzer → credo → sobelow → coverage
- **Precommit:** `mix precommit` alias enforces warnings-as-errors, tests, dialyzer, sobelow

### Email & Notifications
- **Swoosh:** 1.16 (email library)
- **Gettext:** 0.26 (internationalization)

### Utilities
- **DNSCluster:** 0.2.0 (DNS-based service discovery)
- **TelemetryMetrics:** 1.0 (metrics)
- **TelemetryPoller:** 1.0 (telemetry collection)
- **PicosatElixir:** 0.2 (SAT solver)
- **Timex:** 3.7 (datetime manipulation)
- **ExCLDR:** 2.0 (locale/data)

## 2. Existing Project Structure

### Application Structure
```
projects/jido_hub/
├── lib/
│   ├── jido_hub.ex                    # Main application module
│   ├── jido_hub/
│   │   ├── application.ex             # OTP application supervisor
│   │   ├── repo.ex                    # Ecto repository
│   │   ├── accounts/                  # Ash resources for accounts
│   │   ├── metrics/                   # Metrics/telemetry
│   │   └── ...
│   ├── jido_hub_web.ex                # Web module (imports/uses)
│   ├── jido_hub_web/
│   │   ├── endpoint.ex                # Phoenix endpoint
│   │   ├── router.ex                  # Route definitions
│   │   ├── telemetry.ex               # Telemetry configuration
│   │   ├── presence.ex                # Phoenix Presence (real-time)
│   │   ├── controllers/               # HTTP controllers
│   │   ├── live/                      # LiveViews
│   │   ├── components/                # LiveComponents
│   │   ├── on_mount/                  # LiveView hooks
│   │   ├── plugs/                     # Plugs (security, rate limiting)
│   │   └── layouts/                   # HTML layouts
│   ├── jido_hub_components.ex         # Custom components module
│   └── jido_hub_components/           # Reusable components
├── config/
│   ├── config.exs                     # Base configuration
│   ├── dev.exs                        # Development config
│   ├── prod.exs                       # Production config
│   ├── runtime.exs                    # Runtime config
│   └── test.exs                       # Test config
├── assets/                            # Frontend assets
│   ├── js/
│   ├── css/
│   └── vendor/
├── priv/                              # Private files
│   ├── static/                        # Compiled assets
│   └── repo/                          # Database migrations/seeds
├── test/                              # Test files
│   ├── jido_hub/
│   ├── jido_hub_web/
│   └── support/
├── petal_features/                    # PetalFramework features (modular components)
├── docs/                              # Documentation
├── mix.exs                            # Dependencies
├── mix.lock                           # Locked versions
├── .formatter.exs                     # Formatting rules
└── .igniter.exs                       # Igniter configuration
```

### Key Application Files

**`lib/jido_hub/application.ex`** - OTP Application Supervisor
Current children started:
1. `JidoHubWeb.Telemetry` - Telemetry metrics
2. `JidoHub.Repo` - Database repository
3. `DNSCluster` - Service discovery
4. `Oban` - Background jobs (configured with AshOban)
5. `Phoenix.PubSub` - Pub/sub for real-time
6. `JidoHubWeb.Presence` - Presence tracking
7. `Task.Supervisor` - Async task supervision
8. `JidoHubWeb.Endpoint` - Web endpoint
9. `AshAuthentication.Supervisor` - Authentication supervision

**Integration Point for Chat UI:**
- Phoenix.PubSub is already configured for real-time messaging
- Presence is available for tracking online users
- Task.Supervisor can handle async agent communication

### Router Structure (`lib/jido_hub_web/router.ex`)

**Current Routes:**
1. **Public Pages:** `/`, `/privacy`, `/terms`
2. **Authentication:** `/login`, `/signup`, `/reset`, `/logout`
3. **App Routes:** `/dashboard`, `/settings/*` (authenticated)
4. **Admin Routes:** `/admin/*` (admin-only)
5. **API Routes:** `/api/v1/*` (JSON:API + RPC)
6. **Dev Routes:** `/dev/*` (dashboard, mailbox, oban, ash_admin)
7. **Dynamic Slugs:** `/:slug` (user/org profiles)

**Chat UI Integration Point:**
- Add `/chat` route under authenticated scope
- Use existing `live_session :app_required` pattern
- Leverage existing authentication hooks (`LiveUserAuth`)

### Endpoint Configuration (`lib/jido_hub_web/endpoint.ex`)

**Current Setup:**
- LiveView socket at `/live` with websocket support
- Static file serving from `priv/static`
- Code reloading in development with LiveReload
- AshAI MCP dev server at `/ash_ai/mcp` (for AI tool integration)
- Secure headers and CSP plugs
- Session configuration (cookie-based, signed)

**Chat UI Integration Points:**
- Existing LiveView socket for real-time chat
- AshAI MCP integration suggests AI capabilities are planned
- WebSocket infrastructure ready for bidirectional messaging

## 3. Existing Patterns Found

### Authentication Pattern
**Location:** `lib/jido_hub_web/live_user_auth.ex`
- **Pattern:** AshAuthentication with LiveView on_mount hooks
- **Usage:** `on_mount: [{JidoHubWeb.LiveUserAuth, :live_user_required}]`
- **Flows:** Password, Magic Link, API Key authentication
- **Example:** `lib/jido_hub_web/router.ex:57-63`

### LiveView Session Pattern
**Location:** `lib/jido_hub_web/router.ex:55-63`
```elixir
live_session :auth,
  root_layout: {JidoHubWeb.Layouts, :root},
  layout: {JidoHubWeb.Layouts, :auth},
  on_mount: [{JidoHubWeb.LiveUserAuth, :live_user_optional}] do
  live "/login", LoginLive, :index
  # ...
end
```

### Component Library Pattern
**Location:** `lib/jido_hub_components.ex`
- Uses DaisyUIComponents and custom components
- Imported via `use JidoHubWeb, :html`
- Example components: `lib/jido_hub_components/`

### Security Pattern
**Locations:**
- `lib/jido_hub_web/plugs/` - Rate limiting, secure headers, CSP
- `config/dev.exs:68` - Token signing secret
- `config/runtime.exs:38-43` - Secret key base from environment

### Testing Pattern
**Location:** `test/support/`
- ExUnit with PhoenixTest (Playwright-based)
- Coverage via ExCoveralls (90% minimum configured)
- Quokka for test helpers
- Test support modules in `test/support/`

### API Pattern
**Location:** `lib/jido_hub_web/ash_json_api_router.ex`
- AshJsonApi for REST endpoints
- OpenAPI/Swagger documentation
- API key authentication
- Versioned at `/api/v1`

### Background Job Pattern
**Location:** `lib/jido_hub/application.ex:14-18`
```elixir
{Oban,
 AshOban.config(
   Application.fetch_env!(:jido_hub, :ash_domains),
   Application.fetch_env!(:jido_hub, Oban
 )}
```

### Asset Pipeline Pattern
**Location:** `config/dev.exs:31-33`
```elixir
watchers: [
  esbuild: {Esbuild, :install_and_run, [:jido_hub, ~w(--sourcemap=inline --watch)]},
  tailwind: {Tailwind, :install_and_run, [:jido_hub, ~w(--watch)]}
]
```

## 4. Files Requiring Changes for Chat UI Integration

### New Files to Create
- `lib/jido_hub_web/live/chat_live.ex` - Main chat interface LiveView
- `lib/jido_hub_web/live/components/` - Chat-specific components
  - `message_component.ex` - Individual message display
  - `chat_input_component.ex` - Message input with send button
  - `agent_selector_component.ex` - Agent selection dropdown
- `lib/jido_hub/chat.ex` - Chat context/module for business logic
- `lib/jido_hub/agents/` - Agent integration modules
  - `client.ex` - Jido agent client
  - `supervisor.ex` - Agent process supervisor
- `lib/jido_hub_web/channels/` - WebSocket channels for real-time messaging
  - `chat_channel.ex` - Real-time message broadcasting

### Files to Modify
- `lib/jido_hub_web/router.ex:100-108` - Add chat routes
  - Add `live "/chat", ChatLive, :index` to `live_session :app_required`
- `lib/jido_hub/application.ex` - Add agent supervisor
  - Add `{JidoHub.Agents.Supervisor, []}` to children list
- `config/config.exs` - Add Jido agent configuration
- `config/runtime.exs` - Add agent connection settings from environment
- `lib/jido_hub/repo.ex` - Add chat-related schemas if using database storage
- `assets/js/app.js` - Add chat-specific JavaScript (if needed)
- `assets/css/app.css` - Add chat-specific styles

### Configuration Files to Update
- `config/dev.exs` - Add local agent connection settings
- `config/runtime.exs` - Add production agent connection environment variables
- `config/config.exs` - Add agent configuration section

### Test Files to Create
- `test/jido_hub_web/live/chat_live_test.ex` - Chat UI tests
- `test/jido_hub/agents/client_test.ex` - Agent client tests
- `test/jido_hub_web/channels/chat_channel_test.ex` - Channel tests

## 5. Integration Points

### Jido Messaging Integration
**Status:** `jido_messaging` project exists but is minimal (skeletal)
**Location:** `projects/jido_messaging/`
**Current State:**
- Basic application structure
- No schemas or business logic implemented yet
- Mix.exs shows only basic dependencies (jason, zoi)

**Integration Strategy:**
1. Add `jido_messaging` as a dependency to `jido_hub/mix.exs`
2. Configure message schemas in `jido_messaging` to use `jido_hub`'s database
3. Use `jido_messaging` for message persistence and routing
4. Implement pub/sub integration between Phoenix.PubSub and JidoMessaging

**Integration Point:**
```elixir
# In jido_hub/mix.exs
{:jido_messaging, path: "../jido_messaging"}

# In jido_hub/config/config.exs
config :jido_messaging,
  repo: JidoHub.Repo,
  pubsub: JidoHub.PubSub
```

### Jido Agent Integration
**Status:** No existing agent client in jido_hub
**Required:** Build agent client to communicate with Jido agents

**Integration Strategy:**
1. Create `lib/jido_hub/agents/client.ex` to communicate with agents
2. Use Phoenix.PubSub for agent event broadcasting
3. Implement agent process supervision tree
4. Add agent discovery/registration mechanism

**Questions Requiring Clarification:**
- How do Jido agents expose their interfaces? (HTTP? RPC? Message queue?)
- Should agents run as separate processes or be embedded?
- What's the agent communication protocol?
- Are agents local-only or can they be remote?
- How does `jido_ai` fit into this architecture?

### Database Integration
**Current:** PostgreSQL via Ecto with AshPostgres
**Tables Likely Needed:**
- `messages` - Chat messages (user and agent)
- `conversations` - Chat sessions
- `agent_sessions` - Agent interaction tracking
- `agent_configs` - Agent configuration storage

**Ash Resources to Create:**
- `JidoHub.Chat.Message` - Message resource
- `JidoHub.Chat.Conversation` - Conversation resource
- `JidoHub.Agents.Session` - Agent session resource

### Real-time Communication
**Current:** Phoenix.PubSub + Phoenix Presence configured
**Integration:**
- Use Phoenix.PubSub for message broadcasting
- Use Phoenix Presence for typing indicators, online status
- Consider Phoenix Channels for WebSocket-based chat
- Alternatively, use LiveView's built-in real-time updates

### Authentication Integration
**Current:** AshAuthentication with user accounts
**Chat-Specific Requirements:**
- Messages linked to user accounts
- Agent sessions associated with users
- Permissions for agent access
- API key authentication for programmatic chat

## 6. Configuration & Environment

### Existing Configuration Patterns

**Development:** `config/dev.exs`
- Database: PostgreSQL at localhost
- Server: http://127.0.0.1:4000
- Code reloading: Enabled
- Live reload: Enabled with file watchers
- Dev routes: Enabled (dashboard, mailbox, oban, ash_admin)
- Token signing secret: Hardcoded (OK for dev)

**Production:** `config/runtime.exs`
- Database: From `DATABASE_URL` env var
- Server: HTTP from `PORT` env var (default 4000)
- Host: From `PHX_HOST` env var
- SSL: Force SSL with HSTS
- Secret key base: From `SECRET_KEY_BASE` env var
- Token signing secret: From `TOKEN_SIGNING_SECRET` env var
- DNS cluster query: From `DNS_CLUSTER_QUERY` env var

### New Configuration Required

**Agent Connection Settings:**
```elixir
# config/config.exs
config :jido_hub, :agents,
  # Agent discovery method
  discovery: :env, # or :dns, :etcd, :consul
  # Default agent timeout
  timeout: 30_000,
  # Agent communication protocol
  protocol: :http, # or :rpc, :amqp
  # Agent pool size
  pool_size: 10

# config/dev.exs
config :jido_hub, :agents,
  # Local agent URLs for development
  local_agents: [
    default: "http://localhost:4001"
  ]

# config/runtime.exs (production)
agent_urls =
  System.get_env("AGENT_URLS")
  |> case do
    nil -> []
    urls -> String.split(urls, ",") |> Enum.map(&String.trim/1)
  end

config :jido_hub, :agents,
  urls: agent_urls,
  # Or use DNS discovery
  dns_cluster_query: System.get_env("DNS_CLUSTER_QUERY")
```

**Chat Configuration:**
```elixir
# config/config.exs
config :jido_hub, :chat,
  # Message history limit
  history_limit: 100,
  # Streaming response chunk size
  stream_chunk_size: 100,
  # Enable message persistence
  persist_messages: true,
  # Enable agent response caching
  cache_responses: true,
  # Cache TTL
  cache_ttl: :timer.hours(24)
```

### Environment Variables to Document
**Required for Production:**
- `DATABASE_URL` - PostgreSQL connection string
- `SECRET_KEY_BASE` - Phoenix secret key base
- `TOKEN_SIGNING_SECRET` - Auth token signing secret
- `PHX_HOST` - Application hostname
- `PORT` - HTTP port (default: 4000)
- `POOL_SIZE` - Database pool size (default: 10)
- `DNS_CLUSTER_QUERY` - DNS cluster query (if using distributed)

**New Variables for Agent Integration:**
- `AGENT_URLS` - Comma-separated list of agent URLs
- `AGENT_DISCOVERY_METHOD` - Agent discovery method (env/dns/etcd/consul)
- `AGENT_TIMEOUT` - Agent request timeout in ms
- `AGENT_POOL_SIZE` - Agent connection pool size

**Optional:**
- `ECTO_IPV6` - Enable IPv6 for database (true/1)
- `PHX_SERVER` - Enable server in releases (true)

## 7. Test Impact & Patterns

### Existing Test Infrastructure
**Testing Stack:**
- **ExUnit** - Elixir's built-in test framework
- **ExCoveralls** - Test coverage (90% minimum required)
- **Quokka** - Test helpers and matchers
- **PhoenixTest** - Playwright-based integration testing
- **Faker** - Fake data generation

**Test Coverage Configuration:**
```elixir
# mix.exs:40-45
test_coverage: [tool: ExCoveralls],
coveralls: [
  minimum_coverage: 80,
  export: "test/coverage",
  treat_no_relevant_lines_as_covered: true
]
```

**Quality Gate:**
```bash
mix quality  # Runs: format → compile → dialyzer → credo → sobelow → coveralls
```

### Tests to Create for Chat UI
**Unit Tests:**
- `test/jido_hub/chat_test.exs` - Chat context logic
- `test/jido_hub/agents/client_test.exs` - Agent client
- `test/jido_hub/agents/supervisor_test.exs` - Agent supervision
- `test/jido_hub_web/components/message_component_test.exs` - Message component
- `test/jido_hub_web/components/chat_input_component_test.exs` - Input component

**Integration Tests:**
- `test/jido_hub_web/live/chat_live_test.exs` - Chat LiveView
- `test/jido_hub_web/channels/chat_channel_test.exs` - Chat channel

**E2E Tests (PhoenixTest/Playwright):**
- `test/jido_hub_web/e2e/chat_flow_test.exs` - Complete user chat flow
- `test/jido_hub_web/e2e/agent_interaction_test.exs` - Agent response flow

### Testing Patterns to Follow
**LiveView Testing:**
```elixir
# Pattern from existing tests
test "renders chat interface", %{conn: conn} do
  {:ok, _view, html} = live(conn, ~p"/chat")
  assert html =~ "Send a message"
end
```

**Channel Testing:**
```elixir
test "broadcasts messages to chat", %{socket: socket} do
  push(socket, "new_message", %{content: "Hello"})
  assert_broadcast("new_message", %{content: "Hello"})
end
```

**Component Testing:**
```elixir
test "renders message" do
  message = build(:message, content: "Test")
  render_component(&message_component.render/1, message: message)
  assert has_element?("p", "Test")
end
```

## 8. Risk Assessment

### Breaking Changes
**Risk Level:** LOW
- Project already exists with stable dependencies
- Chat UI will add new routes, not modify existing ones
- Agent integration is new functionality

**Potential Issues:**
1. **Jido Messaging Dependency:** If `jido_messaging` schema changes, it could break chat persistence
2. **Agent Protocol Changes:** If Jido agent communication protocol isn't stable, integration may break
3. **Database Schema:** Adding chat tables may require migrations that could affect existing data

### Performance Implications
**Potential Bottlenecks:**
1. **Message Storage:** High message volume could slow database queries
   - **Mitigation:** Implement pagination, archive old messages
2. **Real-time Updates:** Many concurrent users could stress PubSub
   - **Mitigation:** Use Phoenix Presence efficiently, consider sharding
3. **Agent Requests:** Slow agent responses could block UI
   - **Mitigation:** Async agent calls, streaming responses, timeouts
4. **WebSocket Connections:** Many concurrent chat sessions
   - **Mitigation:** Load balancing, horizontal scaling

### Security Touchpoints
**Critical Areas:**
1. **Message Permissions:** Ensure users can only access their own conversations
2. **Agent Authorization:** Verify users have permission to use specific agents
3. **Input Sanitization:** Prevent XSS in chat messages
4. **Rate Limiting:** Prevent spam/abuse (already have PlugAttack configured)
5. **Agent Communication:** Secure agent-to-hub communication (API keys, TLS)
6. **Session Management:** Secure WebSocket connections

**Existing Security:**
- ✅ CSP headers configured (`lib/jido_hub_web/plugs/csp.ex`)
- ✅ Secure headers plug (`lib/jido_hub_web/plugs/secure_headers.ex`)
- ✅ Rate limiting plug (`lib/jido_hub_web/plugs/rate_limit.ex`)
- ✅ CSRF protection enabled (`router.ex:13`)
- ✅ Password hashing with Bcrypt

**Additional Security Needed:**
- Message content sanitization
- Agent response sanitization
- File upload validation (if supporting file attachments)
- API key management for agent authentication

### Migration Complexity
**Database Migrations:**
- **Complexity:** LOW to MEDIUM
- Need to create tables for: messages, conversations, agent_sessions
- Existing database has Ash resources, so follow Ash migration patterns
- Use `mix ash.generate_migrations` and `mix ash.migrate`

**Deployment:**
- **Complexity:** LOW
- Project already has release configuration
- No new runtime dependencies introduced
- Configuration via environment variables (already established)

## 9. Documentation Links

### Phoenix Framework (v1.8.1)
- 📖 [Phoenix 1.8 Official Docs](https://hexdocs.pm/phoenix/1.8.1/) - Main documentation
- 📖 [Phoenix LiveView 1.1 Docs](https://hexdocs.pm/phoenix_live_view/1.1.0/) - LiveView guide
- 📖 [Phoenix LiveView Tutorial](https://hexdocs.pm/phoenix_live_view/) - LiveView walkthrough
- 📖 [Phoenix.PubSub Docs](https://hexdocs.pm/phoenix_pubsub/) - Real-time messaging
- 📖 [Phoenix Presence Docs](https://hexdocs.pm/phoenix_pub_sub/Phoenix.Presence.html) - Presence tracking
- 📖 [Phoenix Routing Guide](https://hexdocs.pm/phoenix/routing.html) - Route configuration

### Ash Framework (v3.0)
- 📖 [Ash 3.0 Documentation](https://hexdocs.pm/ash/3.0.0/) - Core framework
- 📖 [Ash Authentication Guide](https://hexdocs.pm/ash_authentication/4.0.0/) - Auth system
- 📖 [Ash Phoenix Integration](https://hexdocs.pm/ash_phoenix/2.0.0/) - LiveView integration
- 📖 [Ash JSON:API](https://hexdocs.pm/ash_json_api/1.0.0/) - REST API
- 📖 [Ash Postgres](https://hexdocs.pm/ash_postgres/2.0.0/) - PostgreSQL data layer
- 📖 [Ash Resources Guide](https://hexdocs.pm/ash/Ash.Resource.html) - Resource definition
- 📖 [Ash Actions](https://hexdocs.pm/ash/Ash.Resource.Dsl.html#section-actions) - Action configuration
- 📖 [Ash Oban](https://hexdocs.pm/ash_oban/0.4.0/) - Background job integration

### Elixir & Ecto
- 📖 [Elixir 1.18 Docs](https://hexdocs.pm/elixir/1.18/) - Language reference
- 📖 [Ecto 3.13 Docs](https://hexdocs.pm/ecto_sql/3.13.0/) - Database wrapper
- 📖 [Ecto Query Syntax](https://hexdocs.pm/ecto/Ecto.Query.html) - Query guide
- 📖 [Ecto Migrations](https://hexdocs.pm/ecto_sql/Ecto.Adapters.SQL.html#module-migrations) - Migration guide

### Testing
- 📖 [ExUnit Docs](https://hexdocs.pm/ex_unit/) - Testing framework
- 📖 [PhoenixTest Guide](https://hexdocs.pm/phoenix_test/) - Playwright testing
- 📖 [ExCoveralls Docs](https://hexdocs.pm/excoveralls/) - Test coverage

### Security
- 📖 [Plug Security Guide](https://hexdocs.pm/plug/Plug.html#module-security) - Security best practices
- 📖 [Plug.CSP Docs](https://hexdocs.pm/plug/Plug.CSP.HTML.html) - Content Security Policy
- 📖 [PlugAttack Docs](https://hexdocs.pm/plug_attack/) - Rate limiting
- 📖 [Phoenix Security Guide](https://hexdocs.pm/phoenix/security.html) - Phoenix security

### Development Tools
- 📖 [Credo Docs](https://hexdocs.pm/credo/) - Code quality
- 📖 [Dialyxir Docs](https://hexdocs.pm/dialyxir/) - Type checking
- 📖 [Sobelow Docs](https://hexdocs.pm/sobelow/) - Security audit
- 📖 [Igniter Docs](https://hexdocs.pm/igniter/) - Code generation

### Deployment
- 📖 [Phoenix Releases](https://hexdocs.pm/phoenix/releases.html) - Release configuration
- 📖 [Elixir Releases](https://hexdocs.pm/mix/Mix.Tasks.Release.html) - Mix releases

## 10. Unclear Areas Requiring Clarification

### Agent Communication Protocol
**Question:** How does the chat UI communicate with Jido agents?
- Is there an HTTP API? RPC interface? Message queue?
- What's the request/response format?
- Are agents synchronous or asynchronous?
- Can agents stream responses (Server-Sent Events, WebSocket)?

**Impact:** Critical for designing `JidoHub.Agents.Client`

### Agent Discovery
**Question:** How does the hub discover available agents?
- Are agents registered centrally?
- Is there a service discovery mechanism?
- Can agents come and go dynamically?
- Are agents local-only or can they be remote?

**Impact:** Affects supervision tree and configuration strategy

### Message Persistence
**Question:** Should messages be stored in the database?
- Is `jido_messaging` ready for this use case?
- Should we use the existing `jido_hub` database or a separate one?
- What's the message retention policy?
- Do we need full-text search on messages?

**Impact:** Database schema and migration strategy

### Jido AI Integration
**Question:** How does `jido_ai` fit into the chat UI?
- Is `jido_ai` the AI agent implementation?
- Does the chat UI integrate directly with `jido_ai`?
- What's the relationship between `jido_ai`, `jido_hub`, and `jido_messaging`?

**Impact:** Architecture and dependency decisions

### Authentication for Agents
**Question:** How are agents authenticated?
- Do agents use API keys?
- Is there mutual TLS?
- What credentials do agents need?
- Should agents be treated as users?

**Impact:** Security implementation and configuration

### Frontend Framework
**Question:** What's the frontend story for the chat UI?
- Pure LiveView (server-rendered)?
- JavaScript framework (React, Vue)?
- TypeScript usage?
- How does AshTypescript fit in?

**Impact:** Asset pipeline and component architecture

### Real-time Communication
**Question:** What real-time mechanism for chat?
- Phoenix LiveView built-in updates?
- Phoenix Channels (WebSocket)?
- Server-Sent Events?
- Polling fallback?

**Impact:** User experience and infrastructure

## 11. Recommendations

### Immediate Actions
1. ✅ **Validate Existing Setup** - Confirm jido_hub is production-ready
   - Run `mix quality` to verify code quality
   - Run `mix test` to verify test suite
   - Review security configurations

2. 📋 **Clarify Agent Protocol** - Document agent communication
   - Research existing Jido agent interfaces
   - Document request/response format
   - Define agent discovery mechanism

3. 🏗️ **Design Chat Schema** - Plan database structure
   - Define message, conversation, and session tables
   - Plan Ash resources for chat domain
   - Design indexing strategy for queries

4. 🔌 **Plan JidoMessaging Integration** - Prepare messaging layer
   - Review jido_messaging current state
   - Define required schemas in jido_messaging
   - Plan pub/sub integration

### Implementation Approach
**Option 1: Incremental (Recommended)**
- Phase 1: Basic chat UI without agents (user input, message display)
- Phase 2: Add mock agent responses
- Phase 3: Integrate real agents
- Phase 4: Add advanced features (typing indicators, presence)

**Option 2: Full Integration**
- Build complete agent client first
- Then build chat UI
- More complex but faster overall

### Testing Strategy
1. **Start with PhoenixTest** for end-to-end chat flow
2. **Add ExUnit tests** for business logic (agent client, chat context)
3. **Use Quokka** for test data factories
4. **Aim for 90% coverage** to meet project standards

### Security Considerations
1. **Sanitize all message content** (user and agent)
2. **Rate limit chat endpoints** (use existing PlugAttack setup)
3. **Implement proper authorization** (users can only access their conversations)
4. **Secure agent communication** (TLS, API keys)
5. **Log agent interactions** for audit trail

## 12. Next Steps

1. **Review this research** with stakeholders to clarify unclear areas
2. **Create detailed implementation plan** (use `/plan` command)
3. **Break down into tasks** (use `/breakdown` command)
4. **Start with Phase 1** - Basic chat UI without agents
5. **Iterate based on feedback** from agent integration

## Summary

The jido_hub Phoenix project is **already set up and production-ready** with:
- ✅ Modern Phoenix 1.8.1 with LiveView 1.1.0
- ✅ Complete Ash Framework 3.0 stack
- ✅ Authentication, security, testing infrastructure
- ✅ Development tooling and quality gates
- ✅ Real-time infrastructure (PubSub, Presence)

The task is **not to create a new Phoenix project**, but to:
1. **Validate** the existing setup
2. **Document** the configuration
3. **Add chat UI routes and LiveViews**
4. **Integrate Jido agents** via new client module
5. **Connect to jido_messaging** for persistence

**Critical dependencies already in place:**
- Phoenix.PubSub for real-time messaging
- Phoenix Presence for online status
- Ash for data modeling
- AshAuthentication for user management
- Oban for background jobs
- Complete testing infrastructure

**Main work:**
- Build agent client (protocol unclear - needs clarification)
- Create chat UI LiveViews and components
- Add chat-related Ash resources
- Integrate jido_messaging for persistence
- Add chat routes to existing router
- Configure agent discovery and connection

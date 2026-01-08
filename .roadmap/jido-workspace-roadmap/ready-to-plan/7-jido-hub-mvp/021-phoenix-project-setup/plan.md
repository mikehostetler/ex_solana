# Implementation Plan: Phoenix Project Setup for Jido Hub

**Item ID:** 021-phoenix-project-setup
**Status:** Ready to Implement
**Estimated Effort:** Medium (3-5 days)
**Dependencies:** None (but blocked on agent protocol clarification for full implementation)

## Executive Summary

The `jido_hub` Phoenix project **already exists** at `projects/jido_hub/` with a complete, production-ready setup including Phoenix 1.8.1, LiveView 1.1.0, Ash Framework 3.0, authentication, security, and testing infrastructure. This implementation plan focuses on **validating, documenting, and preparing** the existing project for chat UI and Jido agent integration features.

The primary work involves:
1. **Validating** the existing setup meets production standards
2. **Documenting** the configuration, environment variables, and development workflow
3. **Preparing** the project structure for chat UI integration
4. **Creating placeholder modules** for future agent integration

**Key Architectural Decision:** Since the project already exists, we will NOT create a new Phoenix application. Instead, we will validate the existing setup and add documentation/placeholder modules for the chat functionality.

## Impact Analysis Summary

### Key Findings from Research

**Existing Project State:**
- Phoenix 1.8.1 with LiveView 1.1.0 - modern and stable
- Ash Framework 3.0 full-stack (Authentication, PostgreSQL, JSON:API, Phoenix integration)
- Complete authentication system via AshAuthentication 4.0
- Security infrastructure (CSP, rate limiting, secure headers, CSRF)
- Real-time infrastructure (Phoenix.PubSub, Phoenix Presence)
- Testing infrastructure (ExUnit, ExCoveralls, PhoenixTest with Playwright)
- Development tooling (LiveDashboard, AshAdmin, quality gates)

**Critical Gap:** Agent communication protocol is undefined. This blocks full agent client implementation but does not block project validation/documentation.

### Files Requiring Changes

**Phase 1 - Validation (No Code Changes):**
- Review: `projects/jido_hub/mix.exs` - verify dependencies
- Review: `projects/jido_hub/config/*.exs` - verify configuration
- Review: `projects/jido_hub/lib/jido_hub_web/router.ex` - verify routes
- Review: `projects/jido_hub/lib/jido_hub/application.ex` - verify supervision tree

**Phase 2 - Documentation:**
- Create: `projects/jido_hub/docs/SETUP.md` - setup guide
- Create: `projects/jido_hub/docs/DEPLOYMENT.md` - deployment guide
- Create: `projects/jido_hub/docs/AGENT_INTEGRATION.md` - agent integration guide
- Create: `projects/jido_hub/.env.example` - environment variables template

**Phase 3 - Preparation:**
- Create: `projects/jido_hub/lib/jido_hub/chat.ex` - placeholder chat context
- Create: `projects/jido_hub/lib/jido_hub/agents/client.ex` - placeholder agent client
- Create: `projects/jido_hub/lib/jido_hub/agents/supervisor.ex` - placeholder supervisor
- Create: `projects/jido_hub/test/jido_hub/chat_test.exs` - placeholder tests

**Phase 4 - Verification:**
- Run: `mix quality` - verify all quality checks pass
- Run: `mix test` - verify test suite passes
- Create: `projects/jido_hub/docs/VALIDATION_REPORT.md` - validation results

### Existing Patterns to Follow

**Authentication:** Use AshAuthentication with `JidoHubWeb.LiveUserAuth` on_mount hooks
**LiveView Sessions:** Follow existing `live_session :app_required` pattern
**Security:** Use existing plugs in `lib/jido_hub_web/plugs/`
**Testing:** Use PhoenixTest for E2E, ExUnit for unit tests
**API:** Use AshJsonApi for REST endpoints
**Real-time:** Leverage existing Phoenix.PubSub and Presence

### Integration Points Identified

**Jido Messaging:** `projects/jido_messaging/` exists but is skeletal - will need schema definition
**Jido AI:** Dependency present (`ash_ai` package) but integration undefined
**Database:** Existing PostgreSQL via Ecto - will need chat tables
**Real-time:** Phoenix.PubSub and Presence already configured

## Feature Specification

### User Stories with Acceptance Criteria

**US1: Developer Setup**
- As a developer, I want to set up jido_hub locally so I can develop the chat UI
- AC:
  - Running `mix deps.get` completes without errors
  - Running `mix setup` (if exists) creates database, runs migrations
  - Running `mix phx.server` starts the server on port 4000
  - All quality checks pass: `mix quality`

**US2: Documentation**
- As a developer, I want comprehensive documentation so I can understand the project architecture
- AC:
  - SETUP.md documents all dependencies and setup steps
  - DEPLOYMENT.md documents all environment variables and deployment process
  - AGENT_INTEGRATION.md documents how to integrate agents (with placeholders for undefined protocol)
  - .env.example lists all required environment variables

**US3: Placeholder Modules**
- As a developer, I want placeholder modules for chat/agent functionality so I know where to add code
- AC:
  - `JidoHub.Chat` context exists with documented module doc
  - `JidoHub.Agents.Client` placeholder exists with documented interface
  - `JidoHub.Agents.Supervisor` placeholder exists with supervision tree plan
  - All placeholder modules have `@todo` annotations with implementation guidance

**US4: Validation**
- As a project lead, I want validation that the project is production-ready
- AC:
  - All tests pass (current test suite)
  - Test coverage meets minimum (80% configured)
  - No Dialyzer warnings
  - No Credo warnings
  - No Sobelow security issues
  - VALIDATION_REPORT.md documents results

### API Contracts and Data Flow

**Placeholder Agent Client Interface:**
```elixir
# lib/jido_hub/agents/client.ex
defmodule JidoHub.Agents.Client do
  @moduledoc """
  Client for communicating with Jido agents.

  ## TODO: Define agent protocol

  Current assumptions:
  - Agents communicate via HTTP (default)
  - Request format: JSON
  - Response format: JSON (may support streaming)

  Implementation required once agent protocol is defined.
  """

  @type agent_id :: String.t()
  @type message :: %{content: String.t(), metadata: map()}
  @type response :: %{content: String.t(), metadata: map()}

  @callback send_message(agent_id(), message()) :: {:ok, response()} | {:error, term()}
end
```

**Placeholder Chat Context:**
```elixir
# lib/jido_hub/chat.ex
defmodule JidoHub.Chat do
  @moduledoc """
  Context for chat functionality.

  ## TODO: Implement business logic

  Planned features:
  - Creating conversations
  - Sending messages to agents
  - Storing message history
  - Managing agent sessions

  Implementation blocked on agent protocol definition.
  """
end
```

### State Management Requirements

**Current State:**
- User authentication via AshAuthentication
- Session management via Phoenix sessions
- No chat-specific state yet

**Required State (Future):**
- Conversation state (messages, participants)
- Agent session state (active, pending responses)
- Message history (database-backed)
- Real-time presence (typing indicators, online status)

### Error Handling Approach

**Existing Pattern:** Use Splode for error handling (standard in Jido ecosystem)
**Placeholder Pattern:** Return `{:ok, result}` or `{:error, reason}` tuples
**Unknowns:** Agent error handling depends on agent protocol

## Technical Design

### Data Model Changes

**No immediate changes** - existing Ash resources are sufficient for validation phase.

**Planned Changes (Future, for chat UI):**
- `JidoHub.Chat.Message` - message resource (user and agent messages)
- `JidoHub.Chat.Conversation` - conversation/session resource
- `JidoHub.Agents.Session` - agent interaction tracking
- `JidoHub.Agents.Config` - agent configuration storage

**Note:** These will be defined once jido_messaging schema is finalized.

### Module Organization

**Existing Structure (No Changes):**
```
lib/jido_hub.ex                    # Main application
lib/jido_hub/application.ex        # OTP supervisor
lib/jido_hub/repo.ex               # Ecto repository
lib/jido_hub_web.ex                # Web module
lib/jido_hub_web/
  ├── endpoint.ex                  # Phoenix endpoint
  ├── router.ex                    # Routes
  ├── live/                        # LiveViews
  ├── components/                  # LiveComponents
  └── plugs/                       # Security plugs
```

**New Placeholder Modules:**
```
lib/jido_hub/
  ├── chat.ex                      # Chat context (NEW - placeholder)
  └── agents/                      # Agent integration (NEW - placeholder)
      ├── client.ex
      └── supervisor.ex
```

**Documentation:**
```
docs/
  ├── SETUP.md                     # NEW
  ├── DEPLOYMENT.md                # NEW
  ├── AGENT_INTEGRATION.md         # NEW
  └── VALIDATION_REPORT.md         # NEW
```

### Third-Party Integration Details

**Current Dependencies (No Changes):**
- Phoenix 1.8.1 - web framework
- LiveView 1.1.0 - real-time UI
- Ash 3.0 - data modeling
- AshAuthentication 4.0 - user auth
- Ecto/PostgreSQL - database
- Oban 2.0 - background jobs
- ExCoveralls - test coverage

**Future Dependencies (Not Now):**
- `jido_messaging` - will be added once schema is defined
- `jido_ai` - integration undefined

### Configuration/Environment Changes

**No configuration changes** - existing configuration is sufficient.

**Documentation of Existing Config:**
- `config/config.exs` - base configuration (document in SETUP.md)
- `config/dev.exs` - development settings (document in SETUP.md)
- `config/runtime.exs` - production environment variables (document in DEPLOYMENT.md)
- `.env.example` - NEW - list all required environment variables

## Implementation Phases

### Phase 1: Validation (Foundation)

**Objective:** Verify the existing jido_hub project is production-ready.

**Success Criteria:**
- All dependencies install successfully
- All quality checks pass
- All tests pass
- No security vulnerabilities
- Validation report documents findings

**Tasks:**
1. Run `mix deps.get` and verify no errors
2. Run `mix compile` and verify no warnings
3. Run `mix quality` (format, compile, dialyzer, credo, sobelow, coveralls)
4. Run `mix test` and verify all tests pass
5. Review security configurations (CSP, rate limiting, secure headers)
6. Review database setup and migrations
7. Document any issues found

**Files to Review:**
- `projects/jido_hub/mix.exs`
- `projects/jido_hub/config/*.exs`
- `projects/jido_hub/lib/jido_hub_web/plugs/*.ex`
- `projects/jido_hub/test/test_helper.exs`

**Tests to Run:**
- Existing test suite: `mix test`
- Quality gate: `mix quality`

**Dependencies:** None

**Deliverables:**
- Validation checklist completed
- Any issues documented
- Quality gate results recorded

---

### Phase 2: Documentation (Core Implementation)

**Objective:** Create comprehensive documentation for developers.

**Success Criteria:**
- SETUP.md allows new developer to set up project in <15 minutes
- DEPLOYMENT.md documents all deployment steps
- AGENT_INTEGRATION.md documents current understanding + gaps
- .env.example lists all environment variables
- All docs are accurate and tested

**Tasks:**
1. Create `docs/SETUP.md` with:
   - Prerequisites (Elixir, PostgreSQL, Node.js)
   - Installation steps (`mix deps.get`, `mix setup`)
   - Running development server (`mix phx.server`)
   - Running tests (`mix test`, `mix quality`)
   - Troubleshooting common issues
   - Development workflow (format, compile, test)

2. Create `docs/DEPLOYMENT.md` with:
   - Environment variables (DATABASE_URL, SECRET_KEY_BASE, etc.)
   - Build steps (`mix release`)
   - Deployment steps
   - Runtime configuration
   - Monitoring and logging

3. Create `docs/AGENT_INTEGRATION.md` with:
   - Current understanding of agent protocol
   - Placeholder interface definitions
   - Unknowns/gaps requiring clarification
   - Planned implementation approach
   - Example usage (mock)

4. Create `.env.example` with:
   - Required environment variables (DATABASE_URL, SECRET_KEY_BASE, etc.)
   - Optional variables (PORT, POOL_SIZE, etc.)
   - Comments explaining each variable

5. Create `README.md` update (if needed) with links to docs

**Files to Create:**
- `projects/jido_hub/docs/SETUP.md` (NEW)
- `projects/jido_hub/docs/DEPLOYMENT.md` (NEW)
- `projects/jido_hub/docs/AGENT_INTEGRATION.md` (NEW)
- `projects/jido_hub/.env.example` (NEW)

**Tests to Add:**
- None (documentation only)

**Dependencies:** Phase 1 complete

**Deliverables:**
- 4 documentation files created
- Documentation reviewed for accuracy
- Setup instructions tested on clean environment

---

### Phase 3: Placeholder Modules (Integration & Testing)

**Objective:** Create placeholder modules for future chat/agent functionality.

**Success Criteria:**
- All placeholder modules exist and compile
- All placeholder modules have comprehensive module docs
- All placeholder modules have @todo annotations
- Placeholder tests exist and pass
- Modules don't break existing tests

**Tasks:**
1. Create `lib/jido_hub/chat.ex` with:
   - Module doc explaining planned functionality
   - @todo section listing required functions
   - Placeholder function definitions with documentation
   - Typespecs for planned interfaces

2. Create `lib/jido_hub/agents/client.ex` with:
   - Module doc explaining agent client purpose
   - @behaviour definition for agent protocol
   - @todo section listing protocol unknowns
   - Placeholder callback implementations

3. Create `lib/jido_hub/agents/supervisor.ex` with:
   - Module doc explaining supervision tree plan
   - @todo section listing child processes
   - Placeholder supervisor structure
   - Documentation on restart strategies

4. Create `test/jido_hub/chat_test.exs` with:
   - Placeholder tests for future functionality
   - @todo annotations for real tests
   - Tests that verify module exists

5. Create `test/jido_hub/agents/client_test.exs` with:
   - Placeholder tests for agent client
   - @todo annotations for real tests
   - Tests that verify behaviour is defined

**Files to Create:**
- `projects/jido_hub/lib/jido_hub/chat.ex` (NEW)
- `projects/jido_hub/lib/jido_hub/agents/client.ex` (NEW)
- `projects/jido_hub/lib/jido_hub/agents/supervisor.ex` (NEW)
- `projects/jido_hub/test/jido_hub/chat_test.exs` (NEW)
- `projects/jido_hub/test/jido_hub/agents/client_test.exs` (NEW)

**Tests to Add:**
- Placeholder tests that verify modules exist and compile
- All tests should pass (even if they're placeholders)

**Dependencies:** Phase 2 complete

**Deliverables:**
- 5 placeholder module/test files created
- All modules compile without warnings
- All tests pass
- Module docs comprehensive and clear

---

### Phase 4: Verification & Report (Polish & Documentation)

**Objective:** Create final validation report and verify all work is complete.

**Success Criteria:**
- All previous phases complete
- Final validation report created
- All quality checks still pass
- Documentation is accurate and complete
- Project is marked as "ready for chat UI implementation"

**Tasks:**
1. Re-run quality checks:
   - `mix quality` (all checks pass)
   - `mix test` (all tests pass)
   - `mix format --check-formatted` (code is formatted)

2. Review all documentation:
   - Verify SETUP.md is accurate
   - Verify DEPLOYMENT.md is complete
   - Verify AGENT_INTEGRATION.md documents gaps
   - Verify .env.example is complete

3. Create `docs/VALIDATION_REPORT.md` with:
   - Executive summary
   - Quality check results
   - Test coverage report
   - Security review summary
   - Performance considerations
   - Recommendations for next steps
   - Blocked items (agent protocol)

4. Update roadmap item state to "planned" (or appropriate state)

5. Update progress tracking (ralph/progress.txt)

**Files to Create:**
- `projects/jido_hub/docs/VALIDATION_REPORT.md` (NEW)

**Tests to Run:**
- All tests: `mix test`
- Quality gate: `mix quality`
- Coverage: `mix coveralls.html`

**Dependencies:** Phases 1, 2, 3 complete

**Deliverables:**
- Validation report created
- All quality checks passing
- Documentation complete
- Ready for chat UI implementation

---

## Quality & Testing Strategy

### Test Categories

**Unit Tests:**
- Placeholder module tests (verify modules exist and compile)
- Future: chat context logic, agent client logic

**Integration Tests:**
- Existing test suite (should continue to pass)
- Future: chat LiveView, agent integration

**E2E Tests:**
- Existing PhoenixTest suite (should continue to pass)
- Future: complete chat flow tests

### Coverage Targets

**Current:** 80% minimum (as configured in mix.exs)
**Goal:** Maintain or improve coverage
**New Code:** Placeholder modules should have placeholder tests (even if simple)

### Quality Gates

**Pre-commit:** `mix precommit` (if defined)
**Pre-PR:** `mix quality` must pass
**Pre-merge:** All tests must pass, coverage >= 80%

**Quality Check Components:**
1. `mix format --check-formatted` - code formatting
2. `mix compile --warnings-as-errors` - no warnings
3. `mix dialyzer` - type checking
4. `mix credo` - code quality
5. `mix sobelow` - security audit
6. `mix coveralls` - test coverage

## Risk Assessment

### Technical Risks

**Risk 1: Agent Protocol Undefined**
- **Impact:** HIGH - Blocks full agent implementation
- **Probability:** HIGH - Protocol not yet defined
- **Mitigation:** Create placeholder modules with @todo annotations; document assumptions; proceed with validation/documentation that doesn't require protocol knowledge
- **Contingency:** If protocol not defined soon, can implement mock agent for development/testing

**Risk 2: Jido_Messaging Schema Changes**
- **Impact:** MEDIUM - Could affect chat persistence design
- **Probability:** MEDIUM - Schema is not yet finalized
- **Mitigation:** Keep chat persistence flexible; use placeholder schemas until jido_messaging is stable
- **Contingency:** Implement simple message storage without jido_messaging initially

**Risk 3: Existing Project Has Undiscovered Issues**
- **Impact:** MEDIUM - Could delay chat UI implementation
- **Probability:** LOW - Project appears well-maintained
- **Mitigation:** Thorough validation in Phase 1; document all issues found
- **Contingency:** Fix issues as they're discovered; add to technical debt tracker

### Dependency Risks

**Risk 1: Ash Framework Updates**
- **Impact:** LOW - Project uses stable versions
- **Probability:** LOW - Versions are pinned in mix.lock
- **Mitigation:** No dependency updates planned; validate existing versions work

**Risk 2: Phoenix Version Compatibility**
- **Impact:** LOW - Phoenix 1.8.1 is stable
- **Probability:** LOW - No compatibility issues expected
- **Mitigation:** Validate existing setup works

### Timeline Risks

**Risk 1: Scope Creep**
- **Impact:** MEDIUM - Adding too much beyond validation/documentation
- **Probability:** MEDIUM - Temptation to implement real features
- **Mitigation:** Strictly focus on validation/documentation; placeholder modules only
- **Contingency:** If real implementation needed, create separate roadmap item

**Risk 2: Agent Protocol Delays**
- **Impact:** HIGH - Blocks full implementation
- **Probability:** HIGH - Not yet defined
- **Mitigation:** This item focuses on validation/documentation only; agent implementation is separate item
- **Contingency:** Can proceed with chat UI using mock agents

## Success Criteria

### Measurable Outcomes

1. **Validation Complete:**
   - All quality checks pass (mix quality)
   - All tests pass (mix test)
   - No security vulnerabilities (mix sobelow)
   - No code quality issues (mix credo)
   - No type errors (mix dialyzer)

2. **Documentation Complete:**
   - SETUP.md exists and is accurate
   - DEPLOYMENT.md exists and is complete
   - AGENT_INTEGRATION.md exists with gaps documented
   - .env.example exists with all variables listed

3. **Placeholder Modules Complete:**
   - JidoHub.Chat context exists
   - JidoHub.Agents.Client exists
   - JidoHub.Agents.Supervisor exists
   - All modules compile without warnings
   - All modules have comprehensive documentation

4. **Validation Report Complete:**
   - VALIDATION_REPORT.md exists
   - Report summarizes all findings
   - Report documents any issues
   - Report provides recommendations

### Definition of "Done"

This item is complete when:
1. All 4 phases are complete
2. All quality checks pass
3. All documentation is created and reviewed
4. All placeholder modules exist and compile
5. Validation report is written
6. ralph/progress.txt is updated
7. Roadmap item state is updated to "planned" or appropriate next state

### Acceptance Testing Approach

**Manual Verification:**
1. Clone jido_hub to fresh directory
2. Follow SETUP.md instructions
3. Verify project runs locally
4. Verify all quality checks pass
5. Review all documentation for clarity

**Automated Verification:**
1. Run `mix test` - all tests pass
2. Run `mix quality` - all checks pass
3. Run `mix format --check-formatted` - code is formatted

**Peer Review:**
1. Have another developer review documentation
2. Have another developer test setup instructions
3. Address any feedback

## Dependencies & Blockers

### Dependencies

**None** - This item can proceed independently.

### Blockers

**Agent Protocol Definition** (for full implementation, not for this validation item)
- Blocks: Real agent client implementation
- Does not block: Project validation, documentation, placeholder modules
- Resolution: Separate roadmap item or spike to define agent protocol

### Predecessors

None - this is a foundational item for Jido Hub MVP.

### Successors

- Item 022: LibreChat-style chat interface (requires this item's validation to be complete)
- Item 023: Integration with Jido agents (requires agent protocol to be defined)

## Notes

### Assumptions

1. Agent communication will be via HTTP (to be confirmed)
2. Agent request/response format will be JSON (to be confirmed)
3. Agents can be local or remote (to be confirmed)
4. Chat messages will be stored in database (to be confirmed)
5. jido_messaging will be used for persistence (to be confirmed)

### Open Questions

1. **How do Jido agents expose their interfaces?**
   - HTTP API? RPC? Message queue?
   - Resolution: Required for item 023, not for this item

2. **What's the agent communication protocol?**
   - Request format? Response format?
   - Resolution: Required for item 023, not for this item

3. **How does jido_messaging fit in?**
   - What schemas does it define?
   - Resolution: Coordinate with jido_messaging roadmap item

4. **How does jido_ai fit in?**
   - Is jido_ai the agent implementation?
   - Resolution: Research jido_ai and document findings

### Decisions Made

1. **Use existing jido_hub project** - Do not create new Phoenix project
2. **Focus on validation/documentation** - Do not implement real features yet
3. **Create placeholder modules** - Provide structure for future implementation
4. **Document assumptions** - Clearly label what's assumed vs. confirmed
5. **Highlight gaps** - AGENT_INTEGRATION.md should document unknowns

---

## Next Steps After This Item

1. **Item 022:** Implement LibreChat-style chat interface (requires this item's validation)
2. **Item 023:** Integrate with Jido agents (requires agent protocol definition)
3. **Separate spike:** Define Jido agent communication protocol (unblocks item 023)
4. **Separate item:** Finalize jido_messaging schemas (unblocks chat persistence)

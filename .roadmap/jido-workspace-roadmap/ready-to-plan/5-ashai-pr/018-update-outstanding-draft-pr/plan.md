# Implementation Plan: Update Outstanding Draft PR (Item 018)

## 1. Executive Summary

This plan updates **PR #152: "ReqLLM Integration & Architecture Overhaul"** in the upstream `ash-project/ash_ai` repository. The PR adds a new ReqLLM-based integration layer alongside a live LLM testing framework, while removing the legacy adapter system. The implementation involves rebasing the 5-month-old branch onto the latest upstream main, resolving conflicts from recent merges, and ensuring all tests pass. This is a **HIGH complexity** task involving 31 files and architectural changes to the AshAI codebase.

**Key Architectural Decisions:**
- Preserve backward compatibility with LangChain while adding ReqLLM as first-class integration
- Use `reqllm_` prefixed functions to avoid API collisions (future v1.0 may simplify)
- Remove complex adapter system in favor of direct ReqLLM usage
- Add live LLM testing framework for real API integration testing

**Estimated Effort:** 2-3 days (rebase, conflict resolution, testing, documentation refresh)

## 2. Impact Analysis Summary

### Key Findings from Research

The PR introduces three major components:

1. **ReqLLM Integration Layer** (`lib/ash_ai/tool_loop.ex`, `lib/ash_ai/embedding_models/req_llm.ex`)
   - Synchronous and streaming LLM conversation APIs
   - Multi-provider embedding support (OpenAI, Anthropic, Google, Cohere, Voyage)

2. **Modular Tool System** (`lib/ash_ai/tool/`)
   - Schema generation from Ash action arguments
   - Execution engine for running Ash actions from tool calls
   - Error formatting as JSON:API responses
   - Builder pattern for ReqLLM.Tool creation

3. **Live LLM Testing Framework** (`test/live_llm/`)
   - Real API integration tests for tool calling, structured output, embeddings, streaming
   - Documentation for writing live tests

### Files Requiring Changes

**New Files (12):**
- `lib/ash_ai/tool_loop.ex` - Main ReqLLM conversation API
- `lib/ash_ai/tool/builder.ex` - Tool builder module
- `lib/ash_ai/tool/errors.ex` - Error formatting
- `lib/ash_ai/tool/execution.ex` - Tool execution engine
- `lib/ash_ai/tool/schema.ex` - JSON schema generation
- `lib/ash_ai/embedding_models/req_llm.ex` - ReqLLM embedding model
- `test/support/live_llm_case.ex` - Live test helper
- `test/live_llm/*.exs` - 4 live test files
- `documentation/topics/live-llm-testing.md` - Testing guide

**Modified Files (12):**
- `lib/ash_ai.ex` - Add new ReqLLM API exports
- `lib/ash_ai/actions.ex` - Action DSL extensions
- `lib/ash_ai/actions/prompt.ex` - Simplified from adapter system
- `lib/ash_ai/tools.ex` - Refactored tool generation
- `lib/ash_ai/embedding_model.ex` - Minor additions
- `mix.exs`, `mix.lock` - ReqLLM dependency
- Test files updated for new patterns

**Deleted Files (10):**
- Entire `lib/ash_ai/actions/prompt/adapter/` directory
- Associated adapter tests

### Existing Patterns to Follow

- **Splode Error Handling**: Use `Splode.Error` for structured errors
- **Zoi Schemas**: Use Zoi for validated structs (in jido ecosystem, may not apply to ash_ai)
- **Test Organization**: Follow existing `test/ash_ai/` structure
- **Documentation**: Follow existing `.md` documentation format

### Integration Points Identified

- **ReqLLM**: New dependency requiring version `~> 1.0`
- **Ash Framework**: Core integration point for actions, resources
- **jido_ai**: May benefit from new patterns (separate project)
- **LangChain**: Preserved for backward compatibility

## 3. Feature Specification

### User Stories & Acceptance Criteria

**US1: Rebase PR onto latest upstream**
- **As a** maintainer
- **I want to** rebase the PR branch onto latest upstream/main
- **So that** the PR includes all recent upstream changes
- **Acceptance Criteria:**
  - Branch successfully rebased with no merge conflicts OR all conflicts resolved
  - All commits from upstream/main since PR creation are included
  - Local branch ahead of upstream by exactly PR commit count

**US2: All tests pass**
- **As a** maintainer
- **I want to** verify all tests pass after rebase
- **So that** the codebase is stable
- **Acceptance Criteria:**
  - `mix test` passes with 100% of non-live_llm tests passing
  - `mix test --only live_llm` passes when API keys are provided
  - No compilation warnings or errors

**US3: PR description is current**
- **As a** reviewer
- **I want to** see an up-to-date PR description
- **So that** I understand the scope and impact
- **Acceptance Criteria:**
  - PR description reflects all post-rebase changes
  - Breaking changes are clearly documented
  - Migration guide is accurate and complete
  - All TODOs are resolved or documented

**US4: No outdated patterns**
- **As a** maintainer
- **I want to** ensure code follows current conventions
- **So that** the codebase is maintainable
- **Acceptance Criteria:**
  - No deprecated Ash APIs used
  - Code style matches upstream conventions
  - All comments and docs are accurate

### API Contracts & Data Flow

**ReqLLM ToolLoop API:**
```elixir
# Synchronous
AshAi.ToolLoop.run(messages, opts)

# Streaming
AshAi.ToolLoop.stream(messages, opts) -> Enumerable
```

**Tool Registration:**
```elixir
# Convert Ash action to ReqLLM tool
AshAi.reqllm_tool(action_schema)

# Get all tools for a resource
AshAi.reqllm_functions(resource)
```

**Embedding Model:**
```elixir
# In resource DSL
vectorize do
  embedding_model {AshAi.EmbeddingModels.ReqLLM,
    model: "openai:text-embedding-3-small",
    dimensions: 1536
  }
end
```

### State Management Requirements

- No persistent state (API is stateless)
- Test state managed through `AshAi.LiveLLMCase` module
- Live tests require environment variables for API keys

### Error Handling Approach

- Tool execution errors formatted as JSON:API responses via `AshAi.Tool.Errors`
- Use `Splode.Error` for structured errors (if used in ash_ai)
- Live test failures should clearly indicate API vs code issues

## 4. Technical Design

### Data Model Changes

No persistent data model changes. The PR adds:
- `ReqLLM.Tool` structs (from ReqLLM dependency)
- `AshAi.ToolLoop` state struct for streaming operations
- Test case modules for live testing

### Module Organization

Follow existing ash_ai structure:
```
lib/ash_ai/
  ├── tool/                    # NEW: Tool system modules
  │   ├── builder.ex
  │   ├── errors.ex
  │   ├── execution.ex
  │   └── schema.ex
  ├── tool_loop.ex             # NEW: Main API
  ├── embedding_models/
  │   └── req_llm.ex          # NEW: ReqLLM embeddings
  └── ...
```

### Third-Party Integration Details

**ReqLLM** (`~> 1.0`):
- Used for all LLM API calls
- Supports multiple providers (OpenAI, Anthropic, Google, Cohere, Voyage)
- Handles streaming, tool calling, structured output

**Configuration:**
```elixir
# In config/dev.exs
config :req_llm,
  openai_key: System.get_env("OPENAI_API_KEY"),
  anthropic_key: System.get_env("ANTHROPIC_API_KEY")
```

### Configuration/Environment Changes

**mix.exs:**
- Add `{:req_llm, "~> 1.0"}` to dependencies

**Environment Variables (for live tests):**
- `OPENAI_API_KEY` - Required for OpenAI tests
- `ANTHROPIC_API_KEY` - Required for Anthropic tests
- Other provider keys optional

## 5. Implementation Phases

### Phase 1: Rebase & Conflict Resolution

**Objective:** Update PR branch to latest upstream/main with all conflicts resolved

**Files to Modify:**
- Git history (rebase operation)

**Steps:**
1. Fetch latest upstream: `git fetch upstream main`
2. Checkout PR branch (identify from PR #152)
3. Rebase: `git rebase upstream/main`
4. Resolve conflicts in files that diverged
5. Run `mix test` to verify compilation
6. Continue rebase until complete

**Success Criteria:**
- Branch cleanly rebased OR all conflicts manually resolved
- `mix compile` succeeds without errors

**Dependencies:** None

**Tests:** None yet (compilation only)

---

### Phase 2: Test Suite Verification

**Objective:** Ensure all tests pass after rebase

**Files to Run:**
- All test files in `test/`

**Steps:**
1. Run full test suite: `mix test`
2. Fix any broken tests from rebase conflicts
3. Run live LLM tests (requires API keys):
   ```bash
   export OPENAI_API_KEY="sk-..."
   export ANTHROPIC_API_KEY="sk-ant-..."
   mix test --only live_llm
   ```
4. Fix any live test failures

**Success Criteria:**
- 100% of unit tests pass
- All live_llm tests pass when API keys provided

**Dependencies:** Phase 1 complete

**Tests to Add:** None (verify existing tests)

---

### Phase 3: Code Review & Pattern Updates

**Objective:** Ensure code follows current conventions and has no outdated patterns

**Files to Review:**
- All modified and new files from PR
- Check against recent upstream PRs (#157, #148) for API changes

**Steps:**
1. Review changes from PR #157 (tool load definition)
   - Update any tool loading code to match new patterns
2. Review changes from PR #148 (AshOban compilation)
   - Ensure action definitions compile correctly
3. Check for deprecated Ash API usage
4. Verify code style matches upstream conventions
5. Update any outdated comments or documentation

**Success Criteria:**
- No deprecated API usage
- Code style consistent with upstream
- All documentation accurate

**Dependencies:** Phase 2 complete

**Tests:** `mix test` should still pass

---

### Phase 4: PR Documentation Update

**Objective:** Refresh PR description and ensure all documentation is complete

**Files to Update:**
- GitHub PR description (via web or gh CLI)
- Any inline documentation if needed

**Steps:**
1. Review current PR description
2. Update with any post-rebase changes
3. Verify breaking changes section is complete
4. Verify migration guide is accurate
5. Check all TODOs:
   - Resolve if possible
   - Document if deferring
6. Add "Updated for rebase" note with date

**Success Criteria:**
- PR description accurately reflects final state
- Breaking changes clearly documented
- Migration guide tested and accurate
- All TODOs resolved or tracked

**Dependencies:** Phase 3 complete

**Tests:** Documentation review (no automated tests)

---

### Phase 5: Final Validation & Push

**Objective:** Final checks and push updated PR

**Files to Update:**
- Git remote (push force to PR branch)

**Steps:**
1. Run final test suite: `mix test`
2. Run live tests if keys available
3. Push to fork: `git push -f origin <branch>`
4. Verify GitHub CI/CD passes (if enabled)
5. Request formal review from ash_ai maintainers

**Success Criteria:**
- All tests passing
- PR branch updated on GitHub
- Ready for maintainer review

**Dependencies:** Phase 4 complete

**Tests:** Full test suite

## 6. Quality & Testing Strategy

### Test Categories

**Unit Tests:**
- Existing test suite in `test/ash_ai/`
- Cover all modules without external API calls
- Run with: `mix test`

**Integration Tests (Live LLM):**
- New `test/live_llm/` suite
- Real API calls to LLM providers
- Requires API keys in environment
- Run with: `mix test --only live_llm`

**Manual Testing:**
- Verify PR description accuracy
- Test migration guide examples
- Verify documentation builds correctly

### Coverage Targets

- Maintain existing coverage levels
- New code (ToolLoop, tool modules) should have >80% coverage
- Live tests cover critical paths (tool calling, streaming, embeddings)

### Quality Gates

1. **Compilation:** `mix compile` with no warnings
2. **Unit Tests:** 100% pass rate
3. **Live Tests:** 100% pass rate when API keys available
4. **Docs:** All documentation builds without errors
5. **Style:** No formatter warnings (`mix format --check-formatted`)

## 7. Risk Assessment

### Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Rebase conflicts HIGH | HIGH | Medium | Step-by-step conflict resolution, run tests frequently |
| Live test flakiness | Medium | Low | Retry tests, check API quotas, use specific test models |
| Upstream API changes | Medium | High | Review merged PRs carefully, check for breaking changes |
| Dependency conflicts | Low | Medium | Verify mix.lock updates, test in isolation |

### Dependency Risks

| Dependency | Risk | Mitigation |
|------------|------|------------|
| ReqLLM ~> 1.0 | API changes | Pin to specific version if needed |
| Ash framework | Breaking changes | Review Ash changelog, test thoroughly |
| Upstream ash_ai | Divergence | Rebase frequently, track upstream changes |

### Timeline Risks

| Risk | Mitigation |
|------|------------|
| Unforeseen conflicts | Allocate 2-3 days, have contingency for complex resolutions |
| Maintainer feedback | Be prepared for revision cycles based on review |
| API key setup | Document setup clearly, have backup test strategy |

## 8. Success Criteria

### Measurable Outcomes

1. **Rebase Success:** Branch cleanly rebased to latest upstream/main
2. **Test Success:** 100% of unit tests passing
3. **Live Test Success:** All live_llm tests passing with valid API keys
4. **Documentation Complete:** PR description updated, migration guide accurate
5. **Code Quality:** No compiler warnings, follows upstream conventions

### Definition of "Done"

The PR update is complete when:
- [x] Branch is rebased onto latest upstream/main
- [x] All merge conflicts resolved
- [x] `mix test` passes (100% of unit tests)
- [x] `mix test --only live_llm` passes (with API keys)
- [x] PR description reflects current state
- [x] Breaking changes documented
- [x] Migration guide tested and accurate
- [x] All TODOs resolved or documented
- [x] No outdated patterns remain
- [x] Changes pushed to fork
- [x] Ready for formal maintainer review

### Acceptance Testing Approach

1. **Automated:** Full test suite (unit + live_llm)
2. **Manual:** Review PR description and migration guide
3. **Peer Review:** Ash.ai maintainers review code changes
4. **Integration:** Verify downstream projects (jido_ai) can use new patterns

---

**Plan Created:** 2026-01-07
**Estimated Complexity:** HIGH
**Estimated Duration:** 2-3 days
**Dependencies:** None (can start immediately)

# Research: Update Outstanding Draft PR (Item 018)

## Overview

This task involves updating **PR #152: "ReqLLM Integration & Architecture Overhaul"** in the upstream `ash-project/ash_ai` repository. This is an open PR (not draft) by @mikehostetler that needs to be brought up to date with the current codebase.

## PR Details

- **Repository**: `ash-project/ash_ai` (upstream)
- **Fork**: `mikehostetler/ash_ai` (local workspace: `projects/ash_ai`)
- **PR Number**: #152
- **State**: OPEN
- **Created**: 2025-12-09
- **Last Updated**: 2025-12-09 (needs refresh)
- **Size**: +3896, -2701 lines across 31 files

## PR Scope

### Major Changes

#### 1. NEW ReqLLM Integration
- **`AshAi.ToolLoop` module** - New API for LLM conversations with tool calling
  - Synchronous: `AshAi.ToolLoop.run/2`
  - Streaming: `AshAi.ToolLoop.stream/2` with events
  - Configurable max iterations and tool callbacks

- **`AshAi.EmbeddingModels.ReqLLM`** - ReqLLM-backed embedding model
  - Multiple providers: OpenAI, Anthropic, Google, Cohere, Voyage
  - Batch chunking for large embedding requests
  - DSL configuration in `vectorize`

- **New public API**:
  - `AshAi.reqllm_tool/1` - Creates ReqLLM.Tool struct with callback
  - `AshAi.reqllm_functions/1` - Returns list of ReqLLM.Tool structs
  - `AshAi.build_tools_and_registry/1` - For advanced customization

#### 2. Live LLM Testing Framework
- **`AshAi.LiveLLMCase`** - Test case module for real API integration tests
- **Test coverage** in `test/live_llm/`:
  - `tool_calling_test.exs` - Multi-turn conversations with tool execution
  - `structured_output_test.exs` - Enum, integer, embedded struct outputs
  - `embeddings_test.exs` - Single/batch embeddings, semantic similarity
  - `streaming_test.exs` - Content streaming with tool call events
- Documentation: `documentation/topics/live-llm-testing.md`

#### 3. Architecture Refactoring
- **Modular Tool System** (`lib/ash_ai/tool/`):
  - `AshAi.Tool.Schema` - JSON schemas for tool parameters
  - `AshAi.Tool.Execution` - Executes Ash actions from tool calls
  - `AshAi.Tool.Errors` - Formats errors as JSON:API responses
  - `AshAi.Tool.Builder` - Creates ReqLLM.Tool structs and callbacks

- **Removed Legacy Adapter System**:
  - Deleted `AshAi.Actions.Prompt.Adapter` and all sub-modules
  - Simplified `AshAi.Actions.Prompt` to use ReqLLM directly

#### 4. Dependencies
- Added `req_llm ~> 1.0` to mix.exs

## Files Identified (31 total)

### New Files Created (10)
1. `lib/ash_ai/tool/builder.ex` (+134 lines)
2. `lib/ash_ai/tool/errors.ex` (+61 lines)
3. `lib/ash_ai/tool/execution.ex` (+342 lines)
4. `lib/ash_ai/tool/schema.ex` (+266 lines)
5. `lib/ash_ai/tool_loop.ex` (+475 lines)
6. `lib/ash_ai/embedding_models/req_llm.ex` (+75 lines)
7. `test/live_llm/tool_calling_test.exs` (+219 lines)
8. `test/live_llm/structured_output_test.exs` (+259 lines)
9. `test/live_llm/embeddings_test.exs` (+158 lines)
10. `test/live_llm/streaming_test.exs` (+259 lines)
11. `documentation/topics/live-llm-testing.md` (+156 lines)
12. `test/support/live_llm_case.ex` (+113 lines)

### Modified Files (9)
1. `lib/ash_ai.ex` (+245, -60 lines)
2. `lib/ash_ai/actions.ex` (+50, -8 lines)
3. `lib/ash_ai/actions/prompt.ex` (+150, -261 lines)
4. `lib/ash_ai/embedding_model.ex` (+3, -1 lines)
5. `lib/ash_ai/tools.ex` (+67, -617 lines)
6. `mix.exs` (+1 line)
7. `mix.lock` (+12 lines)
8. `test/ash_ai/actions/prompt_test.exs` (+355 lines)
9. `test/ash_ai/embedding_models/req_llm_test.exs` (+207 lines)
10. `test/ash_ai/reqllm_tool_test.exs` (+283 lines)
11. `test/ash_ai_test.exs` (+3 lines)
12. `test/test_helper.exs` (+1, -1 lines)

### Deleted Files (12 - Adapter System)
1. `lib/ash_ai/actions/prompt/adapter.ex` (-79 lines)
2. `lib/ash_ai/actions/prompt/adapter/completion_tool.ex` (-99 lines)
3. `lib/ash_ai/actions/prompt/adapter/helpers.ex` (-84 lines)
4. `lib/ash_ai/actions/prompt/adapter/raw.ex` (-87 lines)
5. `lib/ash_ai/actions/prompt/adapter/request_json.ex` (-375 lines)
6. `lib/ash_ai/actions/prompt/adapter/structured_output.ex` (-111 lines)
7. `test/ash_ai/actions/prompt/adapter/completion_test.exs` (-244 lines)
8. `test/ash_ai/actions/prompt/adapter/messages_test.exs` (-334 lines)
9. `test/ash_ai/actions/prompt/adapter/request_json_test.exs` (-309 lines)
10. `test/ash_ai/open_api_test.exs` (-31 lines)

## Integration Points

### Within ash_ai
- **`lib/ash_ai.ex`** - Main API module, exports new ReqLLM functions
- **`lib/ash_ai/actions.ex`** - Action DSL extensions
- **`lib/ash_ai/tools.ex`** - Tool generation (heavily refactored)
- **`lib/ash_ai/dsl.ex`** - DSL definitions

### Dependencies
- **`req_llm`** - New dependency for LLM interactions
- **`ash`** - Core framework (already dependency)
- **`langchain`** - Preserved for backward compatibility

### External Projects
- **`jido_ai`** - May benefit from new ReqLLM integration
- **`jido_workspace`** - Contains the fork

## Current State

### Upstream (ash-project/ash_ai)
- **Latest Release**: v0.4.0 (2025-11-23)
- **Recent Merged PRs**:
  - #161: Dependabot dependencies update
  - #160: Dependabot dev dependencies update
  - #157: Handle anonymous function in tool load definition
  - #148: Fix AshOban compiling before AshAi action definition
  - #147: Dependabot dependencies update

### Local Fork (projects/ash_ai)
- Located at: `/Users/mostetler/Source/Jido/jido_workspace/projects/ash_ai`
- Current version: 0.4.0
- May have diverged from upstream since PR creation

## Update Strategy

### Step 1: Rebase onto latest main
```bash
cd projects/ash_ai
git fetch upstream main
git rebase upstream/main
```

### Step 2: Resolve conflicts
- Check for merge conflicts with recent upstream changes
- Recent PRs that might conflict:
  - #157: Tool load definition changes
  - #148: AshOban compilation changes

### Step 3: Verify tests pass
```bash
# Unit tests (excludes live LLM)
mix test

# Live LLM tests (requires API keys)
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
mix test --only live_llm
```

### Step 4: Update PR description
- Refresh with latest scope changes
- Verify breaking changes are documented
- Ensure migration guide is complete

### Step 5: Code review checklist
- [ ] All tests passing (unit + live_llm)
- [ ] Documentation complete
- [ ] Breaking changes documented
- [ ] Migration guide accurate
- [ ] No outdated patterns
- [ ] All TODOs resolved or documented

## Known Issues/TODOs

From PR description:
- LangChain support preserved for backward compatibility
- Future major version could simplify `reqllm_` prefixes to `tool/1`, `tools/1`
- Consider removing LangChain dependency in v1.0

## Relevant Documentation

- **PR**: https://github.com/ash-project/ash_ai/pull/152
- **Upstream**: https://github.com/ash-project/ash_ai
- **Fork**: https://github.com/mikehostetler/ash_ai
- **Local Path**: `projects/ash_ai`

## Next Steps

1. **Rebase** the PR branch onto latest upstream/main
2. **Resolve** any merge conflicts
3. **Test** locally with both unit and live_llm tests
4. **Update** PR description with any additional changes
5. **Review** for any outdated patterns or conventions
6. **Submit** for formal review once ready

## Migration Guide Summary

### For New ReqLLM Integration
```elixir
# Simple usage with ToolLoop
messages = [ReqLLM.Context.system("You are a helpful assistant.")]

{:ok, result} = AshAi.ToolLoop.run(messages,
  model: "openai:gpt-4o-mini",
  otp_app: :my_app,
  actor: current_user
)
```

### For prompt() Actions
```elixir
# Before (adapter syntax)
run prompt(adapter: :openai, model: "gpt-4o", ...)

# After (direct model string)
run prompt("openai:gpt-4o", prompt: ...)
```

### For Embeddings
```elixir
vectorize do
  embedding_model {AshAi.EmbeddingModels.ReqLLM,
    model: "openai:text-embedding-3-small",
    dimensions: 1536
  }
end
```

---

**Research Completed**: 2026-01-07
**Files Identified**: 31 files across lib/, test/, documentation/
**Key Integration Points**: `AshAi.ToolLoop`, ReqLLM integration, tool system refactoring
**Estimated Complexity**: HIGH (large architectural change with test coverage)

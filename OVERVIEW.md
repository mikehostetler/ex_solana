<!--
SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# AshAi Overview (ReqLLM Migration)

This document summarizes AshAi's major features, how they integrate with the Ash framework, the current testing approach, and recommended integration tests to validate the recent migration from LangChain to ReqLLM.

## Executive Summary

AshAi now uses ReqLLM end-to-end for tools, prompt-backed actions, embeddings, and MCP tool serving. The unit tests mostly cover behavior at the function/callback level; we should add small seams and focused integration tests to validate real ReqLLM flows (especially tool-call loops and MCP server interactions).

## Features Covered

- [Tool Exposure](#1-tool-exposure) - Exposing Ash actions as LLM tools
- [Prompt-Backed Actions](#2-prompt-backed-actions) - LLM-implemented actions with structured outputs
- [Vectorization System](#3-vectorization-system) - Strategies: after_action, ash_oban, manual
- [MCP Servers](#4-mcp-servers-dev-and-production) - Model Context Protocol servers
- [Chat Generation](#5-chat-generation-feature) - `mix ash_ai.gen.chat`
- [Tool Execution Callbacks](#6-tool-execution-callbacks) - Lifecycle hooks for tool execution

---

## 1) Tool Exposure

### What It Does

Exposes Ash resource actions as LLM-callable tools with a JSON schema for parameters and predictable outputs.

- Enforces Ash's public attributes for filtering/sorting/aggregation
- Optionally includes private attributes in outputs via the `load` option
- Delivers responses as JSON strings (tool contract) and returns raw loaded Ash records for internal use

### Key Modules and Integration with Ash

- **DSL**: `tools` section on a Domain; entity `AshAi.Tool` (`lib/ash_ai.ex`)
- **Discovery**: `AshAi.exposed_tools/1` collects tools from domains or an explicit actions list
- **Execution**: `AshAi.tool/1` builds:
  - `ReqLLM.Tool` struct for tool metadata and parameter schema (via `AshAi.OpenApi`)
  - A `function/2` callback that executes the Ash action (create/update/destroy/read/action), including:
    - `Ash.Query.filter_input` / `sort_input` / limit/offset handling
    - Aggregations and result types (run_query, count, exists, aggregate)
    - Loading and serialization via `AshAi.Serializer`
    - Permission check via `Ash.can?` (empty input preflight) and identity filtering for update/destroy
- **Tool Callbacks**: Emits `AshAi.ToolStartEvent` and `AshAi.ToolEndEvent` via `context.tool_callbacks`
- **DSL and Transformers**: None required for tool exposure (pure DSL entity, OpenAPI schema generation in `AshAi.OpenApi`)

### Current Testing Approach (Unit)

- `test/ash_ai_test.exs` - Validates tool build, parameter schema, and raw execution path
- `test/ash_ai/tool_test.exs` - Validates public/private field behavior and nil-argument handling
- `test/ash_ai/open_api_test.exs` - Validates JSON schema generation and filter schema
- `test/ash_ai/req_llm_tool_test.exs` - Validates `ReqLLM.Tool` formation and callback execution
- `test/ash_ai/tool_callbacks_test.exs` - Validates tool start/end callbacks and edge cases

### Recommended Integration Test Scenarios

#### E2E Tool-Call Loop (ReqLLM)

**Scenario**: Simulate an assistant response that issues a tool_call, ensure tool execution runs with load and returns tool_result, and ensure subsequent assistant content is generated.

**Approach**:
- Add a seam to `AshAi.iex_chat` to allow injecting a mock ReqLLM (like prompt-backed actions do with the `:req_llm` option)
- Mock `ReqLLM.stream_text` to stream a tool_call chunk for a known tool (e.g., read action)
- Ensure the tool registry callback is invoked and tool_result message is appended
- Mock `ReqLLM.stream_text` again to return a final assistant message verifying the tool_result was consumed

**Assertions**: Tool callback fired, tool arguments respected, response text captured

**Effort**: Medium (1–3h) including adding the small seam to iex_chat

#### MCP-to-Tool Execution

**Scenario**: Use `Plug.Test` against `AshAi.Mcp.Router` to call initialize, tools/list, and tools/call.

**Assertions**: 
- `tools/list` returns the same schema names/inputs as the exposed tools
- `tools/call` executes action and returns `content: [%{type: "text", text: ...}]` JSON with expected record data

**Effort**: Small (≤1h) — similar to existing rpc_test but add tools/list and failure cases

#### Authorization Check Path

**Scenario**: Create a resource with an authorizer that forbids an action by default; ensure `AshAi.exposed_tools` respects `can?`/preflight and excludes those tools.

**Assertions**: Forbidden tools are not exposed or return error JSON; verify error shape via `to_json_api_errors`

**Effort**: Medium (1–3h)

---

## 2) Prompt-Backed Actions

### What It Does

Implements Ash actions as LLM-backed with structured output that matches `action.returns` (leveraging JSON schema).

- Supports dynamic models and flexible prompt inputs (string templates, `{system,user}` tuples, message lists, functions)
- Supports tools within prompt execution (`tools: true` or specific list)
- Uses ReqLLM for text and structured-object generation and for iterating tool-call loops

### Key Modules and Integration with Ash

- **Macro**: `AshAi.Actions.prompt/2` wraps `AshAi.Actions.Prompt` with options; attached as action run implementation
- **Implementation**: `AshAi.Actions.Prompt`
  - Builds messages from prompt option or a sensible default template (uses EEx for templating)
  - Builds a JSON schema for the return type using `AshAi.OpenApi`
  - Converts Ash tools to `ReqLLM.Tool` via `AshAi.functions` and internal conversion
  - Runs four modes based on whether a schema is required and whether tools are present:
    - Text only
    - Tool loop without schema
    - Structured output without tools
    - Tool loop with schema (max iterations guard)
  - Uses `ReqLLM.Context.execute_and_append_tools` when tool_calls are present
  - Supports injecting a `req_llm` module for testing (`opts[:req_llm]`)

### Current Testing Approach (Unit)

- `test/ash_ai/actions/prompt/prompt_test.exs` validates:
  - Structured outputs with a FakeReqLLM for object/text
  - Legacy and new prompt formats (strings/tuples/messages/images)
  - Normalization to ReqLLM message parts

### Recommended Integration Test Scenarios

#### Tool Loop with Structured Output

**Scenario**: Action with returns and `tools: true`; FakeReqLLM responds with a tool_call to a known tool and then, after tool execution, `generate_object` returns the final structured result.

**Assertions**: Tool callback invoked; structured object matches the schema; tool filtering/loading rules honored

**Effort**: Medium (1–3h) — build on existing FakeReqLLM by adding `generate_text` returning `message.tool_calls` and ensuring `execute_and_append_tools` is exercised

#### Error Propagation and JSON:API Format

**Scenario**: Force a validation error in tool execution (e.g., missing required field), ensure the error returned to the LLM is encoded as JSON:API and stops the iteration or surfaces appropriately.

**Effort**: Small (≤1h)

---

## 3) Vectorization System

### What It Does

Adds vector columns and automatic/manual embedding generation for configured attributes or "full_text" computed blobs.

**Strategies**:
- `after_action`: Generate embeddings post-action inline and persist via `ash_ai_update_embeddings`
- `ash_oban`: Enqueue an Oban trigger to compute embeddings asynchronously; embed updates written via `ash_ai_update_embeddings`
- `manual`: Only generate when explicitly running the `ash_ai_update_embeddings` action (or custom action if disabled)

Embedding model is pluggable; includes ReqLLM-backed embedding model.

### Key Modules and Integration with Ash

- **DSL**: `vectorize` section with entities for `full_text` definitions; requires `embedding_model` behaviour
- **Transformer**: `AshAi.Transformers.Vectorize`
  - Adds vector attributes with correct dimensions (from `embedding_model.dimensions/1`)
  - Defines `ash_ai_update_embeddings` action based on strategy and wires changes:
    - `after_action`: `AshAi.Changes.VectorizeAfterAction` (inline generation + update action)
    - `manual`: `AshAi.Changes.Vectorize` (compute and set)
    - `ash_oban`: `AshAi.Changes.VectorizeAfterActionObanTrigger` (enqueue trigger)
- **Embedding Behaviour**: `AshAi.EmbeddingModel`; ReqLLM implementation at `lib/ash_ai/embedding_models/req_llm.ex`
  - Uses `ReqLLM.embed/3`; chunks requests; can be mocked via `Process.put(:reqllm_mock)`

### Current Testing Approach (Unit)

- `test/vectorize_test.exs`:
  - Validates all three strategies with a test embedding model (non-ReqLLM)
  - Validates ash_oban queue drain updates vectors
- `test/ash_ai/embedding_models/req_llm_test.exs`:
  - Validates ReqLLM embedding model behavior, batching, nil normalization, error handling, and req_opts passing

### Recommended Integration Test Scenarios

#### E2E with ReqLLM Embedding Model

**Scenario**: Configure a test resource to use `AshAi.EmbeddingModels.ReqLLM` directly. Mock ReqLLM via `Process.put(:reqllm_mock)` to return deterministic vectors.

**Test Each Strategy**:
- `after_action`: create/update record → vectors present immediately
- `manual`: create → no vectors; run `ash_ai_update_embeddings` → vectors present
- `ash_oban`: create → job enqueued; drain → vectors present; update → re-enqueue and update

**Assertions**: Vectors are lists with expected sizes; `updated_at` refresh on update in ash_oban path

**Effort**: Medium (1–3h) — resources exist in tests; just swap embedding model and mocks

#### Expression Usage with Vectors

**Scenario**: Use `vector_cosine_distance(...)` in a read action (as shown in README), mocking ReqLLM embedding for the query vector. Verify sort/filter semantics and limit.

**Effort**: Medium (1–3h)

---

## 4) MCP Servers (Dev and Production)

### What It Does

Exposes AshAi tools to MCP clients over HTTP per MCP Streamable HTTP spec.

- **Dev plug** (`AshAi.Mcp.Dev`) mounts easily into Phoenix during code reload
- **Production router** forwards to `AshAi.Mcp.Router`
- Server handles initialize/shutdown, session IDs (header `mcp-session-id`), tools/list, tools/call
- GET returns SSE endpoint event with post URL
- AuthN stubbed via AshAuthentication API key strategy; context (actor, tenant, context) propagated through tool execution

### Key Modules and Integration with Ash

- **Router**: `AshAi.Mcp.Router` (Plug) — POST/GET/DELETE endpoints
- **Server**: `AshAi.Mcp.Server` — JSON-RPC parsing, session IDs, initialize caps, tool registry, and call dispatch
- **Dev**: `AshAi.Mcp.Dev` — forwards under `/ash_ai/mcp` during dev; uses the same Router
- **Tool Integration**: Reuses `AshAi.exposed_tools` + `AshAi.tool` callback registry; calls callbacks directly with actor/tenant/context built from Plug conn

### Current Testing Approach (Unit)

- `test/ash_ai/mcp/rpc_test.exs`:
  - Initialize and tools/call via `Plug.Test`; validates successful tool execution result content

### Recommended Integration Test Scenarios

#### SSE GET Support

**Scenario**: GET `/mcp` with `Accept: text/event-stream` returns an "endpoint" SSE event with the correct post URL.

**Assertions**: content-type, event payload shape, connection chunked

**Effort**: Small (≤1h)

#### tools/list

**Scenario**: POST tools/list with a session; verify tools enumerated match exposed DSL (names, descriptions, inputSchema).

**Effort**: Small (≤1h)

#### Version Negotiation and Errors

**Scenario**: 
- Initialize with/without `protocol_version_statement`, verify returned `protocolVersion` is set from opts
- Call an unknown method and verify error shape and codes
- tools/call unknown tool returns -32602

**Effort**: Small (≤1h)

#### Authentication Pipeline (Optional)

**Scenario**: Mount Router under a pipeline with AshAuthentication API key; test an authenticated and an unauthenticated request path (if required by your app).

**Effort**: Medium (1–3h)

**Notes**: MCP path currently doesn't propagate `on_tool_start`/`on_tool_end` callbacks; you can extend `Server.build_tools_and_registry` to include `tool_callbacks` if you want MCP to emit those.

---

## 5) Chat Generation Feature

### What It Does

Generates a Phoenix LiveView chat scaffold with Ash resources (Conversation/Message), Oban triggers for responses and conversation naming, streaming updates, and a simple UI.

Currently scaffolding uses LangChain internally in generated code (not ReqLLM).

### Integration with Ash

- **Mix Task**: `lib/mix/tasks/ash_ai.gen.chat.ex`
  - Generates Ash resources and changes, Oban triggers, LiveView, and UI glue
  - Depends on ash_postgres, ash_oban, ash_phoenix, mdex
- **Generated Actions**: Call LangChain in change modules to name a conversation and to respond to messages

### Current Testing Approach (Unit)

- `test/mix/tasks/ash_ai.gen.conversation_test.exs` validates the generator runs in a Phoenix-like test project

### Recommended Integration Test Scenarios

#### Generator Smoke Test + Oban-Flow Test

**Scenario**: Run generator in a temp project (`Igniter.Test`), create a user (if configured), create a message via resource action, drain Oban, and assert a response message is created and streamed. This may require stubbing LangChain calls used in generated code.

**Effort**: Large (1–2d) if end-to-end in a temp Phoenix project; otherwise keep unit-level verification

**Notes**: The generator still uses LangChain; if aligning everything to ReqLLM is a goal, consider a follow-up task to add a ReqLLM-based generation option or seam for testing.

---

## 6) Tool Execution Callbacks

### What It Does

Allows UI/metrics/logging hooks around tool execution.

- `on_tool_start` receives `AshAi.ToolStartEvent` with tool name, action, resource, args, actor, tenant
- `on_tool_end` receives `AshAi.ToolEndEvent` with tool name and `{:ok | :error, ...}` result

### Integration with Ash

- Callbacks are carried through `context.tool_callbacks` and invoked inside `AshAi.tool/1` execution
- Present in iex_chat's context; not currently passed through MCP server path

### Current Testing Approach (Unit)

- `test/ash_ai/tool_callbacks_test.exs` exercises both callbacks across read/create/update/destroy/custom actions and error paths

### Recommended Integration Test Scenarios

#### End-to-End Callback Emission via Tool Loop

**Scenario**: Using the recommended iex_chat seam, trigger a tool_call and validate callback emission ordering and contents.

**Effort**: Small–Medium (≤3h)

---

## General Testing Guidance After the ReqLLM Migration

### Test Harness and Seams

- **Prompt-backed actions** already support `req_llm` injection; reuse `FakeReqLLM` in tests for structured/object and tool-call loops
- **Vectorization with ReqLLM embedding** can be fully mocked using `Process.put(:reqllm_mock)` as provided by `AshAi.EmbeddingModels.ReqLLM`
- **iex_chat** now supports `req_llm` injection via the options:
  ```elixir
  AshAi.iex_chat(nil,
    req_llm: FakeReqLLM,
    otp_app: :my_app,
    model: "test:model"
  )
  ```
  - The `req_llm` option defaults to `ReqLLM` and is passed through to `run_loop`
  - Tests can inject a FakeReqLLM with `stream_text/3` behavior to simulate tool-call loops
  - See `test/ash_ai/iex_chat_integration_test.exs` for an example FakeReqLLM implementation

### Assertions to Prioritize

- Correct `ReqLLM.Tool` parameter_schema content for different action types, including `action_parameters` restriction
- Filtering/sorting/limits respect public attributes and pagination defaults
- Aggregates and `result_type` behavior (run_query, count, exists, aggregate)
- JSON:API error shapes through `to_json_api_errors` for invalid inputs and forbidden access
- Tool loop correctness: tool_calls executed in order, tool_results appended, structured output returned, iteration guard enforced
- Embedding dimensions and batch behavior respected; vector columns match expected dimensions and update timing per strategy
- MCP server contract: initialize response fields, session header, tools/list payload shapes, tools/call success and error paths, SSE endpoint event

### Effort/Scope Signals

- ✅ Add iex_chat seam: **Complete** - `req_llm` option now available
- End-to-end tool-loop test with iex_chat: **Small–Medium (≤3h)** - seam in place, needs non-interactive test harness
- MCP SSE/tools/list tests: **Small (≤1h)**
- Vectorization E2E with ReqLLM embedding: **Medium (1–3h)**
- Prompt-backed action tool-loop E2E (FakeReqLLM): **Medium (1–3h)**
- Optional auth pipeline test for MCP: **Medium (1–3h)**
- Generator E2E in temp project: **Large (1–2d)** or defer

### Risks and Guardrails

- ✅ **Injection seam for iex_chat**: Now implemented - `req_llm` option available for testing
- **Permissions**: `can?`/preflight uses empty inputs; ensure actions tolerate empty inputs for permission checks. Add a targeted test for an authorizer-protected resource to avoid regressions
- **Private attribute leakage**: `load` can include private attributes; tests should verify that this only affects outputs and not filters/sorts
- **MCP protocol versions**: Tools may require older `protocol_version_statement`. Tests should explicitly set and validate the returned `protocolVersion` in initialize

### When to Consider an Advanced Path

- If multiple providers and models are exercised across environments, consider a thin "ReqLLM client behaviour" abstraction for injection everywhere (iex_chat, prompt, embeddings) for consistent testing and easier swapping
- If MCP usage grows (sessions, cancellations, streaming), add session state and cancellation handling in the server and extend tests accordingly

### Optional Advanced Path

Unify LLM usage behind a single `AshAi.Client` behaviour implemented by ReqLLM; prompt, chat, and embeddings depend on that behaviour. This centralizes seams and version control. 

**Trade-off**: More indirection now for easier provider evolution later.

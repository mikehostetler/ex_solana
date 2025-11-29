<!--
SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>

SPDX-License-Identifier: MIT
-->

# ReqLLM.Tool ↔ Ash Actions Integration Refactoring Plan

## Executive Summary

**Goal**: Streamline the Ash Actions → ReqLLM.Tool integration to make it trivially easy to expose Ash actions as LLM-callable tools while seamlessly integrating with Ash policies, authorization, and multi-tenancy.

**Current State**: The integration works but suffers from:
- A monolithic 300-line `AshAi.tool/1` function mixing discovery, schema generation, execution, auth, serialization, and error handling
- Duplicated logic between direct tool usage and MCP server
- Unclear "Ash policies + tool execution" pattern
- No clear public API boundary

**Proposed State**: A composable pipeline with clear separation of concerns:
```
Discovery → Schema → Executor → Registry
```

Implemented via focused modules with a stable public API, maintaining backward compatibility while enabling future extensions.

---

## Architecture Overview

### Current Flow

```
DSL Definition (tools do ... end)
  ↓
AshAi.exposed_tools/1 (discovery)
  ↓
AshAi.tool/1 (300 lines: schema + callback + auth + serialization + errors)
  ↓
{ReqLLM.Tool, callback/2} tuple
  ↓
Registry: %{tool_name => callback}
```

**Problems**:
- Tight coupling of concerns in `tool/1`
- MCP server duplicates tool building logic
- Hard to test individual stages
- Authorization pattern buried in implementation
- Error handling scattered

### Proposed Flow

```
DSL Definition (tools do ... end)
  ↓
AshAi.Tools.discovery/1 (find tools from domains/actions)
  ↓
AshAi.Tool.Builder.build/2 (orchestration only)
  ├─ AshAi.Tool.Schema.for_action/4 (parameter schema)
  ├─ AshAi.Tool.Execution.run/4 (execute with policies)
  └─ AshAi.Tool.Errors (JSON:API formatting)
  ↓
AshAi.Tools.build/1 → {[ReqLLM.Tool], registry}
```

**Benefits**:
- Clear separation of concerns
- Each module independently testable
- MCP and direct usage share same pipeline
- Explicit authorization/policy handling
- Single source of error formatting

---

## Core Features

This refactoring enables three primary features:

1. **Tool Exposure**: Expose Ash actions as ReqLLM.Tool instances with automatic schema generation
2. **Tool Execution**: Execute tools with Ash policies, authorization, and multi-tenancy
3. **Tool Loop**: Orchestrate LLM ↔ Tool calling loops within Ash environment (NEW)

The Tool Loop feature enables autonomous LLM agents that can call multiple Ash actions sequentially while maintaining context, respecting policies, and tracking execution.

---

## Module Structure

### 1. `AshAi.Tools` (Public API)

**Purpose**: Stable public interface for tool discovery and registry building.

**API**:
```elixir
@spec list(opts) :: [ReqLLM.Tool.t()]
@spec registry(opts) :: %{String.t() => tool_callback}
@spec build(opts) :: {[ReqLLM.Tool.t()], registry_map}
@spec discovery(opts) :: [tool_definition]
```

**Opts Schema**:
```elixir
[
  # Discovery
  otp_app: atom | nil,
  domains: [module] | nil,
  actions: [{resource, :* | [action_name]}] | nil,
  tools: [atom] | nil,
  exclude_actions: [{resource, action}] | nil,
  filter: (tool_def -> boolean) | nil,
  
  # Execution Context
  actor: any | nil,
  tenant: any | nil,
  context: map,
  
  # Callbacks
  tool_callbacks: %{
    on_tool_start: (ToolStartEvent.t() -> any) | nil,
    on_tool_end: (ToolEndEvent.t() -> any) | nil
  }
]
```

**Implementation Notes**:
- Replaces current `AshAi.exposed_tools/1` (deprecated, kept as wrapper)
- Consolidates discovery logic from both `ash_ai.ex` and `mcp/server.ex`
- Provides caching hooks for future optimization (not implemented initially)

---

### 2. `AshAi.Tool.Builder`

**Purpose**: Orchestrate building {ReqLLM.Tool, callback} tuples from DSL definitions.

**API**:
```elixir
@spec build(tool_definition, opts) :: {ReqLLM.Tool.t(), tool_callback}
```

**Responsibilities**:
- Extract metadata (name, description, resource, action, load, identity)
- Delegate to `Schema.for_action/4` for parameter schema
- Delegate to `Execution.run/4` for callback implementation
- Construct `ReqLLM.Tool` struct with stub callback (per ReqLLM contract)
- Return actual `function/2` callback for registry

**Implementation Notes**:
- Replaces current `AshAi.tool/1` (deprecated, kept as wrapper)
- ~50 lines max (orchestration only, no business logic)
- Handles loading tool metadata from DSL struct
- Manages description defaults: `"Call the #{action} action on the #{inspect(resource)} resource"`

---

### 3. `AshAi.Tool.Schema`

**Purpose**: Generate OpenAPI/JSON Schema parameter schemas for different action types.

**API**:
```elixir
@spec for_action(resource, action, tool_def, opts) :: parameter_schema_map

# Internal helpers (not exported)
defp for_read(resource, action, visibility, action_params)
defp for_mutation(resource, action, mutation_type)
defp for_generic(resource, action)
```

**Responsibilities**:
- Wrap `AshAi.OpenApi` with action-type-specific entry points
- **Read actions**: filter/sort/limit/offset/result_type with public-only attributes
- **Create/Update**: "input" schema from accept + arguments + identity (update)
- **Destroy**: identity keys as top-level; no input unless action has arguments
- **Generic actions**: "input" from action.arguments
- Respect `action_parameters` allowlist (default: `[:sort, :offset, :limit, :result_type, :filter]`)
- Ensure required fields based on `allow_nil?` and identity requirements

**Visibility Rules**:
```elixir
# Filter/Sort/Aggregate enums: PUBLIC attributes only
public_attrs = Ash.Resource.Info.public_attributes(resource)

# Load option: can include PRIVATE attributes (affects output only)
# - Private loaded fields appear in serialized output
# - Private attributes NEVER appear in filter/sort/aggregate schemas
```

**Implementation Notes**:
- Does NOT change `AshAi.OpenApi` internals (wraps existing functions)
- Consolidates schema-building logic currently scattered in `tool/1`
- ~100-150 lines (one function per action type + visibility filtering)

---

### 4. `AshAi.Tool.Execution`

**Purpose**: Execute Ash actions with proper authorization, identity scoping, and serialization.

**API**:
```elixir
@spec run(resource, action, args, exec_ctx) :: 
  {:ok, json_string, raw_result} | {:error, json_string}
```

**Execution Context**:
```elixir
%{
  actor: any | nil,
  tenant: any | nil,
  context: map,
  tool_callbacks: %{
    on_tool_start: function | nil,
    on_tool_end: function | nil
  },
  load: load_spec,
  identity: atom | false,
  preflight: :identity | :empty | :none
}
```

**Execution Flow**:
```elixir
1. Normalize nil arguments to %{}
2. Emit on_tool_start event
3. Build Ash input based on action type:
   - Read: filter_input, sort_input, limit, offset, result_type
   - Create: for_create with input map
   - Update: get! via identity_filter, then for_update
   - Destroy: get! via identity_filter, then for_destroy
   - Generic: for_action with arguments
4. Run preflight authorization check (Ash.can?)
5. Execute action with actor/tenant/context
6. Handle result_type branching (run_query | count | exists | aggregate)
7. Load relationships/calculations if specified
8. Serialize result via AshAi.Serializer
9. Format errors via AshAi.Tool.Errors if exception
10. Emit on_tool_end event
11. Return {:ok, json_string, raw} or {:error, json_string}
```

**Preflight Strategy**:
```elixir
# Default strategies by action type
:read -> :empty        # Ash.can?(query, actor)
:create -> :empty      # Ash.can?(changeset, actor)
:update -> :identity   # Ash.can?(changeset with identity filter, actor)
:destroy -> :identity  # Ash.can?(changeset with identity filter, actor)
:action -> :empty      # Ash.can?(action_input, actor)

# Override via exec_ctx.preflight if needed
```

**Identity Filtering**:
```elixir
# For update/destroy actions
identity: nil          # Use primary key (default)
identity: :unique_name # Use named identity
identity: false        # No identity; must use filter param (error if missing)

# Build filter expression from identity keys
defp identity_filter(nil, resource, args) do
  # Primary key: %{id: args["id"]}
end

defp identity_filter(identity_name, resource, args) do
  # Named identity: %{key1: args["key1"], key2: args["key2"]}
end

defp identity_filter(false, resource, args) do
  # No identity; require filter param or error
  nil
end
```

**Error Handling**:
```elixir
rescue error ->
  error_class = Ash.Error.to_error_class(error)
  json_errors = AshAi.Tool.Errors.to_json_api(error_class, resource, action.type)
  {:error, Jason.encode!(json_errors)}
```

**Implementation Notes**:
- Consolidates all execution logic from current `tool/1`
- ~200-250 lines (handles all action types systematically)
- Makes authorization pattern explicit and configurable
- Enables reuse in MCP server and direct tool invocation

---

### 5. `AshAi.Tool.Errors`

**Purpose**: Centralize JSON:API error formatting for consistent LLM consumption.

**API**:
```elixir
@spec to_json_api(error | [error], resource, action_type) :: [AshJsonApi.Error.t()]
@spec class_to_status(error_class) :: integer
@spec serialize(errors) :: [json_map]
```

**Responsibilities**:
- Move `to_json_api_errors`, `class_to_status`, `serialize_errors` from `ash_ai.ex`
- Reuse in both tool execution and MCP server error responses
- Ensure consistent error shapes across all integration points

**Error Classes**:
```elixir
:forbidden -> 403
:invalid   -> 400
_          -> 500
```

**Implementation Notes**:
- ~100 lines (extract from current `ash_ai.ex`)
- No behavior changes, just consolidation
- Used by `Execution.run/4` and MCP server

---

### 6. `AshAi.ToolLoop` (NEW - Core Feature)

**Purpose**: Orchestrate LLM ↔ Tool calling loops with Ash context, policies, and execution tracking.

**API**:
```elixir
@spec run(messages, opts) :: {:ok, result} | {:error, reason}
@spec stream(messages, opts) :: Enumerable.t()
```

**Opts Schema**:
```elixir
[
  # LLM Configuration
  model: String.t(),
  req_llm: module (default: ReqLLM),
  
  # Tool Configuration
  otp_app: atom | nil,
  tools: [atom] | :all,
  actions: [{resource, :* | [action]}] | nil,
  
  # Execution Context (threaded through all tool calls)
  actor: any | nil,
  tenant: any | nil,
  context: map,
  
  # Loop Control
  max_iterations: integer (default: 10),
  timeout: integer (default: 30_000),
  
  # Callbacks
  on_tool_start: (ToolStartEvent.t() -> any) | nil,
  on_tool_end: (ToolEndEvent.t() -> any) | nil,
  on_iteration: (IterationEvent.t() -> any) | nil,
  
  # Output Control
  return_messages?: boolean (default: false),
  return_tool_results?: boolean (default: false)
]
```

**Event Structs**:
```elixir
defmodule AshAi.IterationEvent do
  @type t :: %__MODULE__{
    iteration: integer,
    message_count: integer,
    tool_calls: [String.t()],
    timestamp: DateTime.t()
  }
end
```

**Execution Flow**:
```elixir
1. Build tools and registry from opts
2. Initialize message history with input messages
3. Start iteration loop (max_iterations guard):
   a. Call ReqLLM.generate_text with current messages + tools
   b. Emit on_iteration event
   c. Check for tool_calls in response:
      - None: Return final assistant message
      - Present: Execute each tool_call:
        i. Lookup callback in registry
        ii. Build exec_ctx with actor/tenant/context/tool_callbacks
        iii. Execute callback (emits on_tool_start/on_tool_end)
        iv. Append tool_result to messages
   d. If streaming: yield chunks as they arrive
   e. Continue to next iteration
4. Return final result or timeout error
```

**Loop Termination Conditions**:
```elixir
# Success cases
1. LLM returns message with no tool_calls
2. LLM returns finish_reason: "stop"

# Error cases
1. max_iterations reached
2. timeout exceeded
3. Tool execution error (configurable: halt | continue)
4. Authorization failure (always halts)
```

**Context Threading**:
```elixir
# Context flows through entire loop
Initial Context → Tool Call 1 → Tool Call 2 → ... → Final Result

# Each tool execution receives:
exec_ctx = %{
  actor: opts[:actor],           # Same actor for all tools
  tenant: opts[:tenant],         # Same tenant for all tools
  context: opts[:context],       # Shared context map
  tool_callbacks: %{...}         # Consistent callbacks
}

# Context can accumulate state across iterations
context = %{
  request_id: req_id,
  conversation_id: conv_id,
  tool_trace: []  # Optionally track tool calls
}
```

**Error Handling**:
```elixir
# Tool execution error strategies
on_tool_error: :halt    # Stop loop, return error (default)
on_tool_error: :continue # Append error as tool_result, continue
on_tool_error: :retry    # Retry tool once, then halt

# Error returned to LLM as tool_result
{:error, json_string} → tool_result with error content
# LLM can see error and potentially recover or try different approach
```

**Streaming Support**:
```elixir
# Stream text chunks and tool calls
AshAi.ToolLoop.stream(messages, opts)
|> Stream.each(fn
  {:text, chunk} -> IO.write(chunk)
  {:tool_call, name, args} -> log_tool_call(name, args)
  {:tool_result, name, result} -> log_tool_result(name, result)
  {:done, final_message} -> handle_completion(final_message)
end)
|> Stream.run()
```

**Implementation Notes**:
- ~200-250 lines (loop orchestration + streaming + error handling)
- Reuses `AshAi.Tools.build/1` for registry
- Delegates to ReqLLM for LLM calls (injectable for testing)
- Maintains message history internally
- Emits telemetry events for observability
- Respects Ash policies on every tool execution
- Thread-safe (no shared state except messages list)

**Security & Authorization**:
```elixir
# Authorization checked on EVERY tool execution
# No privilege escalation across iterations
# Actor/tenant remain constant throughout loop

# Example: User tries to read private data
1. Tool call: read_private_posts
2. Execution.run checks Ash.can? with actor
3. Authorization fails → {:error, forbidden}
4. Error returned to LLM as tool_result
5. LLM can see it failed and try different approach
   (e.g., read_public_posts instead)
```

**Use Cases**:
```elixir
# 1. Autonomous agent with multiple actions
messages = [
  %{role: "user", content: "Create a blog post and publish it"}
]

{:ok, result} = AshAi.ToolLoop.run(messages,
  model: "gpt-4",
  otp_app: :my_blog,
  actor: current_user,
  tools: [:create_post, :update_post, :publish_post]
)
# LLM will call create_post, then publish_post in sequence

# 2. Research agent with data retrieval
messages = [
  %{role: "user", content: "Find the top 3 selling products and summarize"}
]

{:ok, result} = AshAi.ToolLoop.run(messages,
  model: "gpt-4",
  otp_app: :my_shop,
  actor: analyst_user,
  tools: [:read_products, :read_orders],
  max_iterations: 5
)
# LLM will call read_products, analyze, maybe read_orders for details

# 3. Interactive chat with streaming
AshAi.ToolLoop.stream(messages,
  model: "gpt-4",
  otp_app: :my_app,
  actor: current_user,
  on_tool_start: &log_tool_start/1,
  on_tool_end: &log_tool_end/1
)
|> Enum.each(&handle_chunk/1)
```

---

## Integration Points

### MCP Server

**Current**: Duplicates tool building in `build_tools_and_registry/1`

**Proposed**:
```elixir
defp build_tools_and_registry(opts) do
  # Handle special dev tools case
  opts = case opts[:tools] do
    :ash_dev_tools ->
      opts
      |> Keyword.put(:actions, [{AshAi.DevTools.Tools, :*}])
      |> Keyword.put(:tools, [:list_ash_resources, ...])
    _ ->
      opts
  end
  
  # Single call to unified API
  AshAi.Tools.build(opts)
end
```

**Benefits**:
- Removes ~40 lines of duplication
- MCP automatically gets tool_callbacks support
- Consistent tool schemas across ReqLLM and MCP

---

### Direct Tool Usage (Manual Loop)

**Current**: Call `exposed_tools/1` then `tool/1`, manually implement loop

**Proposed**:
```elixir
# Simple case
{tools, registry} = AshAi.Tools.build(otp_app: :my_app)

# With context
{tools, registry} = AshAi.Tools.build(
  otp_app: :my_app,
  actor: current_user,
  tenant: org_id,
  context: %{conversation_id: conv_id},
  tool_callbacks: %{
    on_tool_start: &log_tool_start/1,
    on_tool_end: &log_tool_end/1
  }
)

# Execute tool manually
callback = Map.fetch!(registry, "read_users")
{:ok, json, raw} = callback.(%{"limit" => 10}, ctx)
```

---

### Tool Loop Usage (Automated Loop - NEW)

**High-Level API**:
```elixir
# Autonomous agent - LLM calls tools as needed
messages = [
  %{role: "user", content: "Create a draft post about Elixir and publish it"}
]

{:ok, result} = AshAi.ToolLoop.run(messages,
  model: "gpt-4",
  otp_app: :my_blog,
  actor: current_user,
  tools: [:create_post, :update_post, :publish_post],
  max_iterations: 5
)

# result = %{
#   content: "I've created and published the post...",
#   tool_calls: [
#     %{name: "create_post", arguments: %{...}},
#     %{name: "publish_post", arguments: %{...}}
#   ],
#   iterations: 2
# }
```

**Streaming API**:
```elixir
# Stream chunks as they arrive
AshAi.ToolLoop.stream(messages,
  model: "gpt-4",
  otp_app: :my_app,
  actor: current_user
)
|> Stream.each(fn
  {:text, chunk} -> 
    IO.write(chunk)
  
  {:tool_call, name, args} -> 
    IO.puts("\n[Calling #{name}...]")
  
  {:tool_result, name, {:ok, result, _}} -> 
    IO.puts("[#{name} completed]")
  
  {:tool_result, name, {:error, error}} -> 
    IO.puts("[#{name} failed: #{error}]")
  
  {:done, final_message} -> 
    IO.puts("\n\nFinal: #{final_message.content}")
end)
|> Stream.run()
```

**Integration with iex_chat**:
```elixir
# Current iex_chat can be refactored to use ToolLoop
# Instead of manual loop implementation, delegate to ToolLoop.stream

def iex_chat(messages, opts) do
  AshAi.ToolLoop.stream(messages, opts)
  |> Stream.each(&handle_stream_event/1)
  |> Stream.run()
end

# Benefits:
# - Consistent loop logic across all usage
# - Built-in iteration guards and timeout
# - Telemetry and callback support
# - Testable via req_llm injection
```

---

## Edge Cases & Requirements

### 1. Aggregations & Result Types

**Schema Requirements**:
```elixir
# result_type oneOf
["run_query", "count", "exists", "aggregate"]

# aggregate.kind enum (per field type)
# For integer: ["count", "sum", "avg", "min", "max"]
# For string: ["count", "list"]

# aggregate.field enum: PUBLIC attributes only
```

**Execution Requirements**:
```elixir
case result_type do
  "run_query" -> query |> Ash.read!() |> serialize
  "count" -> query |> Ash.count!() |> to_string()
  "exists" -> query |> Ash.exists?() |> to_string()
  "aggregate" -> 
    query 
    |> Ash.aggregate!([{kind, field}]) 
    |> Map.fetch!(field) 
    |> serialize_aggregate()
end
```

### 2. Identity Filtering (Update/Destroy)

**Requirements**:
- Default: use primary key as identity
- DSL `identity: :name` → use named identity keys
- DSL `identity: false` → no identity; require filter param (error if missing)
- Always validate identity keys are present in arguments
- Build Ash.Expr filter expression from identity keys

**Error Cases**:
```elixir
# identity: false and no filter
{:error, "Either identity or filter must be provided for update/destroy"}

# Missing identity key
{:error, "Required identity key 'email' not provided"}
```

### 3. Load Option & Private Attributes

**Rules**:
- Load spec can include private attributes/relationships/calculations
- Private loaded fields appear in JSON output (via Serializer)
- Private attributes NEVER appear in filter/sort/aggregate schemas
- Load is specified in DSL: `tool :read_users, User, :read, load: [:private_notes]`

**Test Coverage**:
```elixir
# Existing test validates this (test/ash_ai/tool_test.exs)
test "includes public and loaded fields" do
  # internal_status is private but loaded
  # Appears in JSON output
  # Does NOT appear in filter schema
end
```

### 4. Nil Arguments (MCP Compatibility)

**Requirement**: Handle `nil` arguments from MCP clients

**Implementation**:
```elixir
def run(resource, action, args, exec_ctx) do
  args = args || %{}  # Normalize at entry point
  # ... rest of execution
end
```

**Test Coverage**: `test/ash_ai/tool_test.exs` validates this

### 5. Action Parameters Restriction

**Requirement**: Limit available parameters on read actions

**DSL**:
```elixir
tool :limited_read, Post, :read do
  action_parameters [:filter, :limit]  # Only these available
end
```

**Schema Impact**: Drop `sort`, `offset`, `result_type` from parameter schema

**Default**: `[:sort, :offset, :limit, :result_type, :filter]`

---

## Migration Path

### Phase 1: New Modules (Backward Compatible)

**Add**:
- `lib/ash_ai/tools.ex` - Public API
- `lib/ash_ai/tool/builder.ex` - Tool construction
- `lib/ash_ai/tool/schema.ex` - Parameter schemas
- `lib/ash_ai/tool/execution.ex` - Action execution
- `lib/ash_ai/tool/errors.ex` - Error formatting

**Deprecate (keep as wrappers)**:
```elixir
# lib/ash_ai.ex
@deprecated "Use AshAi.Tools.discovery/1"
def exposed_tools(opts), do: AshAi.Tools.discovery(opts)

@deprecated "Use AshAi.Tool.Builder.build/2"
def tool(tool_def, opts \\ []), do: AshAi.Tool.Builder.build(tool_def, opts)
```

**Update**:
- `lib/ash_ai/mcp/server.ex` - Use `AshAi.Tools.build/1`
- Move error helpers from `ash_ai.ex` to `tool/errors.ex`

**Tests**:
- Keep all existing tests (update imports if needed)
- Add focused unit tests for new modules
- Add MCP callback emission test

**Effort**: 1-2 days

---

### Phase 2: Documentation & Examples

**Add**:
- Update README with new public API examples
- Add "Ash Policies & Tool Execution" guide
- Document preflight strategies
- Document identity filtering patterns
- Add migration guide from old API

**Effort**: 0.5 days

---

### Phase 3: Remove Deprecated APIs (Future)

**After 1 full release cycle**:
- Remove `AshAi.exposed_tools/1`
- Remove `AshAi.tool/1`
- Update all internal usage
- Remove deprecation wrappers

**Effort**: 0.5 days

---

## Testing Strategy

### Unit Tests (Per Module)

#### `AshAi.Tools`
- Discovery from domains
- Discovery from explicit actions list
- Filter by tools list
- Filter by exclude_actions
- Custom filter predicate
- Registry mapping correctness

#### `AshAi.Tool.Schema`
- Read action schema (filter, sort, limit, offset, result_type)
- Public-only attribute visibility in filters/sorts
- Aggregate schema with correct kinds per field type
- Create action schema (input with accept + arguments)
- Update action schema (input + identity keys)
- Destroy action schema (identity keys, no input)
- Generic action schema (arguments only)
- action_parameters restriction

#### `AshAi.Tool.Execution`
- Read with filter/sort/limit/offset
- Read with aggregations (count, exists, aggregate)
- Create with input validation
- Update with identity filtering
- Destroy with identity filtering
- Generic action execution
- Nil argument normalization
- Load option handling
- Preflight authorization
- Error formatting
- Callback emission (start/end)

#### `AshAi.Tool.Errors`
- Invalid error formatting
- Forbidden error formatting
- Unknown error formatting
- Field-level validation errors
- Error class to status code mapping

---

### Integration Tests (End-to-End)

#### Tool Execution Flow
```elixir
test "read tool with filter and load" do
  {tools, registry} = AshAi.Tools.build(
    otp_app: :ash_ai,
    actor: user,
    tools: [:read_posts]
  )
  
  callback = Map.fetch!(registry, "read_posts")
  
  {:ok, json, raw} = callback.(
    %{"filter" => %{"author_id" => %{"eq" => author.id}}},
    %{actor: user, tenant: nil, context: %{}, tool_callbacks: %{}}
  )
  
  decoded = Jason.decode!(json)
  assert is_list(decoded)
  assert Enum.all?(decoded, &(&1["author_id"] == author.id))
end
```

#### MCP Server Integration
```elixir
test "MCP tools/call with callbacks" do
  test_pid = self()
  
  opts = [
    otp_app: :ash_ai,
    tool_callbacks: %{
      on_tool_start: &send(test_pid, {:start, &1}),
      on_tool_end: &send(test_pid, {:end, &1})
    }
  ]
  
  body = Jason.encode!(%{
    "jsonrpc" => "2.0",
    "id" => 1,
    "method" => "tools/call",
    "params" => %{
      "name" => "read_posts",
      "arguments" => %{"limit" => 5}
    }
  })
  
  conn = conn(:post, "/mcp", body)
  conn = AshAi.Mcp.Server.handle_post(conn, body, nil, opts)
  
  assert_receive {:start, %ToolStartEvent{}}
  assert_receive {:end, %ToolEndEvent{}}
  assert conn.status == 200
end
```

#### Authorization & Policies
```elixir
test "tool respects Ash policies" do
  # Resource with policy forbidding reads without actor
  {tools, registry} = AshAi.Tools.build(
    otp_app: :ash_ai,
    tools: [:read_private_posts]
  )
  
  callback = Map.fetch!(registry, "read_private_posts")
  
  # Without actor: should fail authorization
  {:error, json} = callback.(
    %{},
    %{actor: nil, tenant: nil, context: %{}, tool_callbacks: %{}}
  )
  
  errors = Jason.decode!(json)
  assert Enum.any?(errors, &(&1["code"] == "forbidden"))
end
```

---

## API Examples

### Basic Usage

```elixir
# Get all tools from an app
{tools, registry} = AshAi.Tools.build(otp_app: :my_app)

# Pass to ReqLLM
ReqLLM.stream_text(
  messages: messages,
  tools: tools,
  model: "gpt-4"
)

# Execute a tool
callback = Map.fetch!(registry, "read_users")
{:ok, json, raw_records} = callback.(
  %{"limit" => 10},
  %{actor: current_user, tenant: org, context: %{}, tool_callbacks: %{}}
)
```

### With Callbacks

```elixir
{tools, registry} = AshAi.Tools.build(
  otp_app: :my_app,
  actor: current_user,
  tool_callbacks: %{
    on_tool_start: fn event ->
      Logger.info("Tool #{event.tool_name} started with #{inspect(event.arguments)}")
    end,
    on_tool_end: fn event ->
      case event.result do
        {:ok, _, _} -> Logger.info("Tool #{event.tool_name} succeeded")
        {:error, _} -> Logger.error("Tool #{event.tool_name} failed")
      end
    end
  }
)
```

### Filtering Tools

```elixir
# Only specific tools
{tools, registry} = AshAi.Tools.build(
  otp_app: :my_app,
  tools: [:read_users, :create_post]
)

# Exclude specific actions
{tools, registry} = AshAi.Tools.build(
  otp_app: :my_app,
  exclude_actions: [{Post, :destroy}, {User, :update}]
)

# Custom filter predicate
{tools, registry} = AshAi.Tools.build(
  otp_app: :my_app,
  filter: fn tool -> tool.mcp == :tool end
)
```

### Direct Execution API

```elixir
# For advanced use cases: execute without building full registry
exec_ctx = %{
  actor: current_user,
  tenant: org_id,
  context: %{request_id: req_id},
  load: [:comments_count],
  identity: :email,
  preflight: :identity,
  tool_callbacks: %{}
}

{:ok, json, raw} = AshAi.Tool.Execution.run(
  Post,
  :update,
  %{"email" => "user@example.com", "input" => %{"status" => "published"}},
  exec_ctx
)
```

---

## Open Questions & Future Enhancements

### 1. Policy-Aware Tool Discovery

**Question**: Should tools be filtered at discovery time based on actor permissions?

**Current**: All DSL-defined tools are exposed; authorization happens at execution time via `Ash.can?` preflight

**Proposed Option**: Add `strict_expose?: true` to filter tools by preflight check

**Pros**:
- LLM only sees tools the actor can use
- Reduces hallucination attempts on forbidden tools

**Cons**:
- Discovery becomes stateful (per actor/tenant)
- Cache complexity increases
- Preflight check may not match actual execution permissions (different inputs)

**Decision**: Defer until user feedback indicates this is needed

---

### 2. Tool Adapter Protocol

**Question**: Should we support non-Ash tools in the same registry?

**Proposed**:
```elixir
defmodule AshAi.ToolAdapter do
  @callback build(tool_def, opts) :: {ReqLLM.Tool.t(), tool_callback}
  @callback schema(tool_def, opts) :: parameter_schema
  @callback execute(tool_def, args, exec_ctx) :: result
end

# Default: AshAi.AshToolAdapter (implements current behavior)
# Custom: MyApp.CustomToolAdapter (for external APIs, etc.)
```

**Pros**:
- Unified registry for Ash and non-Ash tools
- Reuse MCP server and callback infrastructure
- Enable complex multi-source tool systems

**Cons**:
- Adds abstraction layer
- Current use cases don't require this

**Decision**: Defer until non-Ash tool requirement emerges

---

### 3. Streaming Tool Results

**Question**: Should tools support streaming responses for long-running operations?

**Current**: All tool results are synchronous `{:ok, json, raw} | {:error, json}`

**Use Case**: Large dataset reads, AI generation actions, file processing

**Proposed**:
```elixir
# Streaming callback variant
{:ok_streaming, stream} -> 
  stream 
  |> Stream.map(&serialize_chunk/1)
  |> Stream.map(&Jason.encode!/1)
```

**Decision**: Defer; requires ReqLLM streaming tool support

---

### 4. Tool Registry Caching

**Question**: Should we cache built tools/registry per session?

**Current**: Tools are rebuilt on every `AshAi.Tools.build/1` call

**Use Case**: MCP sessions, long-running chat sessions

**Proposed**:
```elixir
# Option 1: Process-based registry
{:ok, pid} = AshAi.ToolRegistry.start_link(otp_app: :my_app, actor: user)
{tools, registry} = AshAi.ToolRegistry.get(pid)

# Option 2: ETS cache
{tools, registry} = AshAi.Tools.build(
  otp_app: :my_app,
  cache: true,
  cache_key: {user.id, tenant_id}
)
```

**Decision**: Defer until performance profiling shows rebuild cost is material

---

## Success Criteria

### Code Quality
- [ ] `AshAi.tool/1` reduced from ~300 lines to ~50 lines (orchestration only)
- [ ] Each new module < 250 lines
- [ ] No duplication between MCP and direct tool usage
- [ ] Error handling centralized in one module

### Functionality
- [ ] All existing tests pass without modification
- [ ] MCP server uses `AshAi.Tools.build/1`
- [ ] Tool callbacks work in both direct and MCP usage
- [ ] Authorization pattern documented and explicit
- [ ] Tool Loop handles iteration limits and timeouts correctly
- [ ] Tool Loop respects Ash policies on every tool execution
- [ ] Tool Loop streaming works with backpressure
- [ ] iex_chat refactored to use ToolLoop (optional)

### Documentation
- [ ] Public API (`AshAi.Tools`) fully documented
- [ ] Migration guide from old API
- [ ] "Ash Policies & Tool Execution" guide
- [ ] Example code for common patterns

### Performance
- [ ] No regression in tool execution time
- [ ] Tool building cost < 1ms per tool (baseline established)

---

## Timeline Estimate

| Phase | Tasks | Effort | Dependencies |
|-------|-------|--------|--------------|
| 1. New Modules | Create Tools, Builder, Schema, Execution, Errors modules | 1-2d | None |
| 2. Tool Loop | Create ToolLoop module with run/stream APIs | 1-1.5d | Phase 1 |
| 3. Deprecation | Add wrappers, update MCP server | 0.5d | Phase 1 |
| 4. Testing | Unit tests for new modules, ToolLoop integration tests | 1d | Phase 1-3 |
| 5. Documentation | API docs, migration guide, examples, ToolLoop guides | 0.5d | Phase 1-4 |
| **Total** | | **4-5.5d** | |

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking changes to existing code | High | Maintain deprecated wrappers for 1+ release |
| Preflight strategy doesn't match runtime auth | Medium | Document clearly; add `preflight: :none` escape hatch |
| Performance regression | Low | Benchmark before/after; optimize if needed |
| MCP callback integration complexity | Low | Test thoroughly; MCP already uses same callback shape |
| Identity filtering edge cases | Medium | Comprehensive test coverage; fail fast with clear errors |
| Tool Loop infinite loops | High | Enforce max_iterations (default 10) and timeout (default 30s) |
| Tool Loop memory consumption (large message history) | Medium | Add message pruning option; monitor telemetry |
| Authorization bypass in Tool Loop | Critical | Validate actor/tenant on EVERY tool execution; no caching |
| ReqLLM API changes | Medium | Injectable req_llm module; version constraints |

---

## Next Steps

1. **Review & Approval**: Team review of this plan
2. **Spike Phase 1**: Quick prototype of `AshAi.Tools` and `AshAi.Tool.Execution` to validate approach (~2-4h)
3. **Spike Phase 2**: Quick prototype of `AshAi.ToolLoop.run` with FakeReqLLM to validate loop logic (~2-4h)
4. **Implementation**: Follow migration path Phase 1-5
5. **Testing**: Run full test suite + new integration tests + ToolLoop tests
6. **Documentation**: Update README and add guides (including ToolLoop patterns)
7. **Release**: Ship with deprecation warnings; plan removal for next major version

---

## Appendix: Current Code Complexity

### `AshAi.tool/1` Breakdown (302 lines)

| Lines | Responsibility |
|-------|----------------|
| 20 | Metadata extraction (name, description, resource, action) |
| 80 | Parameter schema building (delegates to OpenApi) |
| 150 | Callback implementation (auth, execution, serialization) |
| 30 | Error handling and JSON:API formatting |
| 12 | Tool start/end callback emission |
| 10 | Returning ReqLLM.Tool + callback tuple |

**After refactor**: ~50 lines (orchestration + delegation only)

---

## Appendix: Reference Implementation Signatures

```elixir
# AshAi.Tools
@spec build(Keyword.t()) :: {[ReqLLM.Tool.t()], registry_map}
@spec list(Keyword.t()) :: [ReqLLM.Tool.t()]
@spec registry(Keyword.t()) :: registry_map
@spec discovery(Keyword.t()) :: [tool_definition]

# AshAi.Tool.Builder
@spec build(AshAi.Tool.t(), Keyword.t()) :: {ReqLLM.Tool.t(), tool_callback}

# AshAi.Tool.Schema
@spec for_action(module, Ash.Resource.Actions.action, AshAi.Tool.t(), Keyword.t()) :: map

# AshAi.Tool.Execution
@spec run(module, Ash.Resource.Actions.action, map, exec_ctx) :: 
  {:ok, String.t(), any} | {:error, String.t()}

# AshAi.Tool.Errors
@spec to_json_api(any, module, atom) :: [AshJsonApi.Error.t()]
@spec class_to_status(atom) :: integer
@spec serialize([AshJsonApi.Error.t()]) :: [map]

# AshAi.ToolLoop (NEW)
@spec run([message], Keyword.t()) :: {:ok, loop_result} | {:error, reason}
@spec stream([message], Keyword.t()) :: Enumerable.t()

# Types
@type registry_map :: %{String.t() => tool_callback}
@type tool_callback :: (map, exec_ctx -> {:ok, String.t(), any} | {:error, String.t()})
@type exec_ctx :: %{
  actor: any,
  tenant: any,
  context: map,
  tool_callbacks: %{
    on_tool_start: function | nil,
    on_tool_end: function | nil
  }
}
@type tool_definition :: AshAi.Tool.t()
@type message :: %{role: String.t(), content: String.t(), tool_calls: [map] | nil}
@type loop_result :: %{
  content: String.t(),
  tool_calls: [map],
  iterations: integer,
  messages: [message] | nil
}
@type stream_event :: 
  {:text, String.t()} |
  {:tool_call, String.t(), map} |
  {:tool_result, String.t(), {:ok, String.t(), any} | {:error, String.t()}} |
  {:done, message}
```

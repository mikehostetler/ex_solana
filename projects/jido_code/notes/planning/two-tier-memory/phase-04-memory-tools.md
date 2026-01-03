# Phase 4: Memory Tools (Jido Actions)

This phase implements the memory tools that allow the LLM agent to explicitly manage its long-term memory. These tools are implemented as Jido Actions following the existing action pattern in the codebase.

## Memory Tools Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│  LLM Agent Tool Call                                                     │
│  e.g., {"name": "remember", "arguments": {"content": "...", ...}}       │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Tool Executor                                                           │
│  - Parses tool call from LLM response                                   │
│  - Routes to appropriate Jido Action                                     │
│  - Returns formatted result to LLM                                       │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Jido Actions                                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                      │
│  │  Remember   │  │   Recall    │  │   Forget    │                      │
│  │             │  │             │  │             │                      │
│  │ Persist to  │  │ Query from  │  │ Supersede   │                      │
│  │ long-term   │  │ long-term   │  │ memories    │                      │
│  └─────────────┘  └─────────────┘  └─────────────┘                      │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  JidoCode.Memory API                                                     │
│  - persist/2, query/2, supersede/3                                       │
│  - Session-scoped operations                                             │
└─────────────────────────────────────────────────────────────────────────┘
```

## Module Structure

```
lib/jido_code/memory/
├── actions/
│   ├── remember.ex           # Agent self-determination memory storage
│   ├── recall.ex             # Query long-term memory
│   └── forget.ex             # Supersede memories (soft delete)
```

## Tools in This Phase

| Tool | Action Module | Purpose |
|------|---------------|---------|
| remember | `Actions.Remember` | Agent self-determination memory storage |
| recall | `Actions.Recall` | Query long-term memory by type/query |
| forget | `Actions.Forget` | Supersede memories (soft delete with provenance) |

---

## 4.1 Remember Action

Implement the remember action for agent self-determination memory storage. This allows the LLM to explicitly persist important information to long-term memory with maximum importance score (bypasses threshold).

### 4.1.1 Action Definition

- [ ] 4.1.1.1 Create `lib/jido_code/memory/actions/remember.ex` with moduledoc:
  ```elixir
  @moduledoc """
  Persist important information to long-term memory.

  Use when you discover something valuable for future sessions:
  - Project facts (framework, dependencies, architecture)
  - User preferences and coding style
  - Successful solutions to problems
  - Important patterns or conventions
  - Risks or known issues

  Agent-initiated memories bypass the normal importance threshold
  and are persisted immediately with maximum importance score.
  """
  ```
- [ ] 4.1.1.2 Implement `use Jido.Action` with configuration:
  ```elixir
  use Jido.Action,
    name: "remember",
    description: "Persist important information to long-term memory. " <>
      "Use when you discover something valuable for future sessions.",
    schema: [
      content: [
        type: :string,
        required: true,
        doc: "What to remember - concise, factual statement (max 2000 chars)"
      ],
      type: [
        type: {:in, [:fact, :assumption, :hypothesis, :discovery,
                     :risk, :unknown, :decision, :convention, :lesson_learned]},
        default: :fact,
        doc: "Type of memory (maps to Jido ontology class)"
      ],
      confidence: [
        type: :float,
        default: 0.8,
        doc: "Confidence level (0.0-1.0, maps to jido:ConfidenceLevel)"
      ],
      rationale: [
        type: :string,
        required: false,
        doc: "Why this is worth remembering"
      ]
    ]
  ```
- [ ] 4.1.1.3 Define valid memory types constant for validation
- [ ] 4.1.1.4 Define maximum content length constant (2000 chars)

### 4.1.2 Action Implementation

- [ ] 4.1.2.1 Implement `run/2` callback:
  ```elixir
  @impl true
  def run(params, context) do
    with {:ok, validated} <- validate_params(params),
         {:ok, session_id} <- get_session_id(context),
         {:ok, memory_item} <- build_memory_item(validated, context),
         {:ok, memory_id} <- promote_immediately(memory_item, session_id) do
      {:ok, format_success(memory_id, validated.type)}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  ```
- [ ] 4.1.2.2 Implement `validate_params/1` private function:
  - Validate content is non-empty string
  - Validate content length <= 2000 characters
  - Validate type is in allowed list
  - Clamp confidence to 0.0-1.0 range
- [ ] 4.1.2.3 Implement `get_session_id/1` to extract session_id from context:
  ```elixir
  defp get_session_id(context) do
    case context[:session_id] do
      nil -> {:error, :missing_session_id}
      id -> {:ok, id}
    end
  end
  ```
- [ ] 4.1.2.4 Implement `build_memory_item/2`:
  ```elixir
  defp build_memory_item(params, context) do
    {:ok, %{
      id: generate_id(),
      content: params.content,
      memory_type: params.type,
      confidence: params.confidence,
      source_type: :agent,
      evidence: [],
      rationale: params[:rationale],
      suggested_by: :agent,
      importance_score: 1.0,  # Maximum - bypass threshold
      created_at: DateTime.utc_now(),
      access_count: 1
    }}
  end
  ```
- [ ] 4.1.2.5 Implement `promote_immediately/2`:
  ```elixir
  defp promote_immediately(memory_item, session_id) do
    # Add to agent decisions for immediate promotion
    Session.State.add_agent_memory_decision(session_id, memory_item)

    # Build memory input for persistence
    memory_input = %{
      id: memory_item.id,
      content: memory_item.content,
      memory_type: memory_item.memory_type,
      confidence: memory_item.confidence,
      source_type: :agent,
      session_id: session_id,
      agent_id: nil,  # Could be extracted from context
      project_id: nil,
      evidence_refs: [],
      rationale: memory_item.rationale,
      created_at: memory_item.created_at
    }

    Memory.persist(memory_input, session_id)
  end
  ```
- [ ] 4.1.2.6 Implement `format_success/2`:
  ```elixir
  defp format_success(memory_id, type) do
    %{
      remembered: true,
      memory_id: memory_id,
      memory_type: type,
      message: "Successfully stored #{type} memory with id #{memory_id}"
    }
  end
  ```
- [ ] 4.1.2.7 Implement `generate_id/0` for unique memory IDs:
  ```elixir
  defp generate_id do
    :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
  end
  ```
- [ ] 4.1.2.8 Add telemetry emission for remember operations:
  ```elixir
  :telemetry.execute(
    [:jido_code, :memory, :remember],
    %{duration: duration_ms},
    %{session_id: session_id, memory_type: type}
  )
  ```

### 4.1.3 Unit Tests for Remember Action

- [ ] Test remember creates memory item with correct type
- [ ] Test remember sets default type to :fact when not provided
- [ ] Test remember sets default confidence (0.8) when not provided
- [ ] Test remember clamps confidence to valid range (0.0-1.0)
- [ ] Test remember validates content is non-empty
- [ ] Test remember validates content max length (2000 chars)
- [ ] Test remember validates type against allowed enum
- [ ] Test remember generates unique memory ID
- [ ] Test remember sets source_type to :agent
- [ ] Test remember sets importance_score to 1.0 (maximum)
- [ ] Test remember triggers immediate promotion via add_agent_memory_decision
- [ ] Test remember persists to long-term store via Memory.persist
- [ ] Test remember returns formatted success message with memory_id
- [ ] Test remember handles missing session_id with clear error
- [ ] Test remember handles optional rationale parameter
- [ ] Test remember emits telemetry event

---

## 4.2 Recall Action

Implement the recall action for querying long-term memory. This allows the LLM to retrieve previously learned information filtered by type and confidence.

### 4.2.1 Action Definition

- [ ] 4.2.1.1 Create `lib/jido_code/memory/actions/recall.ex` with moduledoc:
  ```elixir
  @moduledoc """
  Search long-term memory for relevant information.

  Use to retrieve previously learned:
  - Facts about the project or codebase
  - Decisions and their rationale
  - Patterns and conventions
  - Lessons learned from past issues

  Supports filtering by memory type and minimum confidence level.
  """
  ```
- [ ] 4.2.1.2 Implement `use Jido.Action` with configuration:
  ```elixir
  use Jido.Action,
    name: "recall",
    description: "Search long-term memory for relevant information. " <>
      "Use to retrieve previously learned facts, decisions, patterns, or lessons.",
    schema: [
      query: [
        type: :string,
        required: false,
        doc: "Search query or keywords (optional, for text matching)"
      ],
      type: [
        type: {:in, [:all, :fact, :assumption, :hypothesis, :discovery,
                     :risk, :decision, :convention, :lesson_learned]},
        default: :all,
        doc: "Filter by memory type (default: all)"
      ],
      min_confidence: [
        type: :float,
        default: 0.5,
        doc: "Minimum confidence threshold 0.0-1.0"
      ],
      limit: [
        type: :integer,
        default: 10,
        doc: "Maximum memories to return (default: 10, max: 50)"
      ]
    ]
  ```

### 4.2.2 Action Implementation

- [ ] 4.2.2.1 Implement `run/2` callback:
  ```elixir
  @impl true
  def run(params, context) do
    with {:ok, validated} <- validate_query_params(params),
         {:ok, session_id} <- get_session_id(context),
         {:ok, memories} <- query_memories(validated, session_id),
         :ok <- record_access(memories, session_id) do
      {:ok, format_results(memories)}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  ```
- [ ] 4.2.2.2 Implement `validate_query_params/1`:
  - Validate limit is between 1 and 50
  - Validate min_confidence is between 0.0 and 1.0
  - Validate type is in allowed list
- [ ] 4.2.2.3 Implement `query_memories/2`:
  ```elixir
  defp query_memories(params, session_id) do
    opts = [
      min_confidence: params.min_confidence,
      limit: params.limit
    ]

    result = if params.type == :all do
      Memory.query(session_id, opts)
    else
      Memory.query_by_type(session_id, params.type, opts)
    end

    # Apply text query filter if provided
    case {result, params[:query]} do
      {{:ok, memories}, nil} -> {:ok, memories}
      {{:ok, memories}, query} -> {:ok, filter_by_query(memories, query)}
      {error, _} -> error
    end
  end
  ```
- [ ] 4.2.2.4 Implement `filter_by_query/2` for text matching:
  ```elixir
  defp filter_by_query(memories, query) do
    query_lower = String.downcase(query)
    Enum.filter(memories, fn mem ->
      String.contains?(String.downcase(mem.content), query_lower)
    end)
  end
  ```
- [ ] 4.2.2.5 Implement `record_access/2` to update access tracking:
  ```elixir
  defp record_access(memories, session_id) do
    Enum.each(memories, fn mem ->
      Memory.record_access(session_id, mem.id)
    end)
    :ok
  end
  ```
- [ ] 4.2.2.6 Implement `format_results/1`:
  ```elixir
  defp format_results(memories) do
    %{
      count: length(memories),
      memories: Enum.map(memories, &format_memory/1)
    }
  end

  defp format_memory(mem) do
    %{
      id: mem.id,
      content: mem.content,
      type: mem.memory_type,
      confidence: mem.confidence,
      timestamp: DateTime.to_iso8601(mem.timestamp)
    }
  end
  ```
- [ ] 4.2.2.7 Add telemetry emission for recall operations

### 4.2.3 Unit Tests for Recall Action

- [ ] Test recall returns memories matching type filter
- [ ] Test recall with type :all returns all memory types
- [ ] Test recall filters by min_confidence correctly
- [ ] Test recall respects limit parameter
- [ ] Test recall validates limit range (1-50)
- [ ] Test recall with query performs text search (case-insensitive)
- [ ] Test recall with query filters results after type/confidence
- [ ] Test recall records access for all returned memories
- [ ] Test recall returns empty list when no matches
- [ ] Test recall formats results with count and memory list
- [ ] Test recall handles missing session_id with clear error
- [ ] Test recall emits telemetry event
- [ ] Test recall returns memories sorted by relevance/recency

---

## 4.3 Forget Action

Implement the forget action for superseding memories. This uses soft deletion via the supersededBy relation to maintain provenance.

### 4.3.1 Action Definition

- [ ] 4.3.1.1 Create `lib/jido_code/memory/actions/forget.ex` with moduledoc:
  ```elixir
  @moduledoc """
  Mark a memory as superseded (soft delete).

  The memory remains in storage for provenance tracking but won't
  appear in normal recall queries. Use when information is outdated
  or incorrect.

  Optionally specify a replacement memory that supersedes the old one.
  """
  ```
- [ ] 4.3.1.2 Implement `use Jido.Action` with configuration:
  ```elixir
  use Jido.Action,
    name: "forget",
    description: "Mark a memory as superseded (soft delete). " <>
      "The memory remains for provenance but won't be retrieved in normal queries.",
    schema: [
      memory_id: [
        type: :string,
        required: true,
        doc: "ID of memory to supersede"
      ],
      reason: [
        type: :string,
        required: false,
        doc: "Why this memory is being superseded"
      ],
      replacement_id: [
        type: :string,
        required: false,
        doc: "ID of memory that supersedes this one (optional)"
      ]
    ]
  ```

### 4.3.2 Action Implementation

- [ ] 4.3.2.1 Implement `run/2` callback:
  ```elixir
  @impl true
  def run(params, context) do
    with {:ok, validated} <- validate_forget_params(params),
         {:ok, session_id} <- get_session_id(context),
         {:ok, _memory} <- verify_memory_exists(validated.memory_id, session_id),
         :ok <- maybe_verify_replacement(validated, session_id),
         :ok <- supersede_memory(validated, session_id) do
      {:ok, format_forget_success(validated)}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  ```
- [ ] 4.3.2.2 Implement `validate_forget_params/1`:
  - Validate memory_id is non-empty string
  - Validate replacement_id if provided
- [ ] 4.3.2.3 Implement `verify_memory_exists/2`:
  ```elixir
  defp verify_memory_exists(memory_id, session_id) do
    case Memory.get(session_id, memory_id) do
      {:ok, memory} -> {:ok, memory}
      {:error, :not_found} -> {:error, {:memory_not_found, memory_id}}
    end
  end
  ```
- [ ] 4.3.2.4 Implement `maybe_verify_replacement/2`:
  ```elixir
  defp maybe_verify_replacement(%{replacement_id: nil}, _session_id), do: :ok
  defp maybe_verify_replacement(%{replacement_id: id}, session_id) do
    case Memory.get(session_id, id) do
      {:ok, _} -> :ok
      {:error, :not_found} -> {:error, {:replacement_not_found, id}}
    end
  end
  ```
- [ ] 4.3.2.5 Implement `supersede_memory/2`:
  ```elixir
  defp supersede_memory(params, session_id) do
    Memory.supersede(session_id, params.memory_id, params[:replacement_id])
  end
  ```
- [ ] 4.3.2.6 Implement `format_forget_success/1`:
  ```elixir
  defp format_forget_success(params) do
    base = %{
      forgotten: true,
      memory_id: params.memory_id,
      message: "Memory #{params.memory_id} has been superseded"
    }

    if params[:reason] do
      Map.put(base, :reason, params.reason)
    else
      base
    end
  end
  ```
- [ ] 4.3.2.7 Add telemetry emission for forget operations

### 4.3.3 Unit Tests for Forget Action

- [ ] Test forget marks memory as superseded
- [ ] Test forget with replacement_id creates supersededBy relation
- [ ] Test forget validates memory_id exists
- [ ] Test forget validates replacement_id exists (if provided)
- [ ] Test forget handles non-existent memory_id with clear error
- [ ] Test forget handles non-existent replacement_id with clear error
- [ ] Test forget stores reason if provided
- [ ] Test forget returns formatted success message
- [ ] Test forget handles missing session_id with clear error
- [ ] Test forgotten memories excluded from normal recall queries
- [ ] Test forgotten memories still retrievable with include_superseded option
- [ ] Test forget emits telemetry event

---

## 4.4 Action Registration

Integrate memory actions with the tool system for LLM access.

### 4.4.1 Action Discovery

- [ ] 4.4.1.1 Create `lib/jido_code/memory/actions.ex` module:
  ```elixir
  defmodule JidoCode.Memory.Actions do
    @moduledoc """
    Memory actions for LLM agent memory management.
    """

    alias JidoCode.Memory.Actions.{Remember, Recall, Forget}

    @doc "Returns all memory action modules"
    def all do
      [Remember, Recall, Forget]
    end

    @doc "Returns action module by name"
    def get(name) do
      case name do
        "remember" -> {:ok, Remember}
        "recall" -> {:ok, Recall}
        "forget" -> {:ok, Forget}
        _ -> {:error, :not_found}
      end
    end
  end
  ```
- [ ] 4.4.1.2 Implement action-to-tool-definition conversion:
  ```elixir
  def to_tool_definitions do
    Enum.map(all(), &action_to_tool_def/1)
  end

  defp action_to_tool_def(action_module) do
    # Convert Jido.Action schema to tool definition format
    %{
      name: action_module.__jido_action__(:name),
      description: action_module.__jido_action__(:description),
      parameters: schema_to_parameters(action_module.__jido_action__(:schema))
    }
  end
  ```
- [ ] 4.4.1.3 Add memory tools to available tools in LLMAgent

### 4.4.2 Executor Integration

> **⚠️ STOP: Architecture Decision Required**
>
> Before proceeding with executor integration, an Architecture Decision Record (ADR) must be written and approved. This section modifies `lib/jido_code/tools/executor.ex`, which is also modified by the parallel Tooling implementation.
>
> **Decision to document:**
> - Memory tools (remember, recall, forget) use Jido Actions pattern and bypass the Lua sandbox
> - Standard tools route through Lua sandbox for security sandboxing
> - Executor needs a guard clause to route memory tools differently
>
> **Required ADR:** `notes/decisions/XXXX-memory-tool-executor-routing.md`
>
> See `notes/planning/two-tier-memory/conciliation.md` for full conflict analysis.
>
> - [ ] 4.4.2.0 **Write and approve ADR for memory tool executor routing before proceeding**

- [ ] 4.4.2.1 Update tool executor to handle memory actions:
  ```elixir
  def execute_tool(name, args, context) when name in ["remember", "recall", "forget"] do
    {:ok, action_module} = Memory.Actions.get(name)
    action_module.run(args, context)
  end
  ```
- [ ] 4.4.2.2 Ensure session_id is passed in context for all memory tool calls
- [ ] 4.4.2.3 Format action results for LLM consumption

### 4.4.3 Unit Tests for Action Registration

- [ ] Test Actions.all/0 returns all three action modules
- [ ] Test Actions.get/1 returns correct module for each name
- [ ] Test Actions.get/1 returns error for unknown name
- [ ] Test to_tool_definitions/0 produces valid tool definitions
- [ ] Test tool definitions have correct name, description, parameters
- [ ] Test executor routes memory tool calls to correct action
- [ ] Test executor passes session_id in context

---

## 4.5 Phase 4 Integration Tests

Comprehensive integration tests verifying memory tools work end-to-end.

### 4.5.1 Tool Execution Integration

- [ ] 4.5.1.1 Create `test/jido_code/integration/memory_tools_test.exs`
- [ ] 4.5.1.2 Test: Remember tool creates memory accessible via Recall
- [ ] 4.5.1.3 Test: Remember -> Recall flow returns persisted memory
- [ ] 4.5.1.4 Test: Recall returns memories filtered by type
- [ ] 4.5.1.5 Test: Recall returns memories filtered by confidence
- [ ] 4.5.1.6 Test: Recall with query filters by text content
- [ ] 4.5.1.7 Test: Forget tool removes memory from normal Recall results
- [ ] 4.5.1.8 Test: Forgotten memories still exist for provenance
- [ ] 4.5.1.9 Test: Forget with replacement_id creates supersession chain

### 4.5.2 Session Context Integration

- [ ] 4.5.2.1 Test: Memory tools work with valid session context
- [ ] 4.5.2.2 Test: Memory tools return appropriate error without session_id
- [ ] 4.5.2.3 Test: Memory tools respect session isolation
- [ ] 4.5.2.4 Test: Multiple sessions can use memory tools concurrently

### 4.5.3 Executor Integration

- [ ] 4.5.3.1 Test: Memory tools execute through standard executor flow
- [ ] 4.5.3.2 Test: Tool validation rejects invalid arguments
- [ ] 4.5.3.3 Test: Tool results format correctly for LLM consumption
- [ ] 4.5.3.4 Test: Error messages are clear and actionable

### 4.5.4 Telemetry Integration

- [ ] 4.5.4.1 Test: Remember emits telemetry with session_id and type
- [ ] 4.5.4.2 Test: Recall emits telemetry with query parameters
- [ ] 4.5.4.3 Test: Forget emits telemetry with memory_id

---

## Phase 4 Success Criteria

1. **Remember Action**: Agent can persist explicit memories with type classification
2. **Recall Action**: Agent can query memories by type, confidence, and text
3. **Forget Action**: Agent can supersede outdated memories with provenance
4. **Action Registration**: All memory actions discoverable and executable
5. **Executor Integration**: Memory tools work through standard tool execution
6. **Session Isolation**: Memory operations scoped to session_id
7. **Error Handling**: Clear error messages for all failure cases
8. **Telemetry**: All operations emit monitoring events
9. **Test Coverage**: Minimum 80% for Phase 4 modules

---

## Phase 4 Critical Files

**New Files:**
- `lib/jido_code/memory/actions/remember.ex`
- `lib/jido_code/memory/actions/recall.ex`
- `lib/jido_code/memory/actions/forget.ex`
- `lib/jido_code/memory/actions.ex`
- `test/jido_code/memory/actions/remember_test.exs`
- `test/jido_code/memory/actions/recall_test.exs`
- `test/jido_code/memory/actions/forget_test.exs`
- `test/jido_code/memory/actions_test.exs`
- `test/jido_code/integration/memory_tools_test.exs`

**Modified Files:**
- `lib/jido_code/tools/executor.ex` - Add memory action routing
- `lib/jido_code/agents/llm_agent.ex` - Register memory tools

# Phase 1: Memory Foundation & Session.State Extension

This phase establishes the core memory types and extends Session.State with memory-related fields. All memory data structures are designed to work with the existing session lifecycle.

## Memory System Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         JidoCode Session (Unique ID)                      │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │                    Session.State GenServer                          │  │
│  │  ┌──────────────────────────────────────────────────────────────┐  │  │
│  │  │                    SHORT-TERM MEMORY                          │  │  │
│  │  │                  (Extended State Fields)                      │  │  │
│  │  │  ┌─────────────┐  ┌──────────────┐  ┌────────────────────┐   │  │  │
│  │  │  │   Working   │  │   Pending    │  │     Access         │   │  │  │
│  │  │  │   Context   │  │   Memories   │  │       Log          │   │  │  │
│  │  │  │ (scratchpad)│  │ (staging)    │  │   (tracking)       │   │  │  │
│  │  │  └─────────────┘  └──────────────┘  └────────────────────┘   │  │  │
│  │  │                                                               │  │  │
│  │  │  Existing Fields: messages, reasoning_steps, tool_calls,     │  │  │
│  │  │                   todos, prompt_history, file_reads/writes   │  │  │
│  │  └──────────────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────┘
```

## Module Structure

```
lib/jido_code/memory/
├── types.ex                       # Shared type definitions
└── short_term/
    ├── working_context.ex         # Semantic scratchpad
    ├── pending_memories.ex        # Pre-promotion staging
    └── access_log.ex              # Usage tracking
```

---

## 1.1 Core Memory Types

Define the foundational types and structs for the memory system. These types map directly to the Jido ontology classes and provide the building blocks for all memory operations.

### 1.1.1 Memory Types Module

Create the shared type definitions used across all memory components.

- [ ] 1.1.1.1 Create `lib/jido_code/memory/types.ex` with module documentation describing the type system
- [ ] 1.1.1.2 Define `memory_type()` typespec matching Jido ontology MemoryItem subclasses:
  ```elixir
  @type memory_type ::
    :fact | :assumption | :hypothesis | :discovery |
    :risk | :unknown | :decision | :convention | :lesson_learned
  ```
- [ ] 1.1.1.3 Define `confidence_level()` typespec mapping to Jido ConfidenceLevel individuals:
  ```elixir
  @type confidence_level :: :high | :medium | :low
  ```
- [ ] 1.1.1.4 Define `source_type()` typespec matching Jido SourceType individuals:
  ```elixir
  @type source_type :: :user | :agent | :tool | :external_document
  ```
- [ ] 1.1.1.5 Define `context_key()` typespec for working context semantic keys:
  ```elixir
  @type context_key ::
    :active_file | :project_root | :primary_language | :framework |
    :current_task | :user_intent | :discovered_patterns | :active_errors |
    :pending_questions | :file_relationships
  ```
- [ ] 1.1.1.6 Define `pending_item()` struct type for pre-promotion staging:
  ```elixir
  @type pending_item :: %{
    id: String.t(),
    content: String.t(),
    memory_type: memory_type(),
    confidence: float(),
    source_type: source_type(),
    evidence: [String.t()],
    rationale: String.t() | nil,
    suggested_by: :implicit | :agent,
    importance_score: float(),
    created_at: DateTime.t(),
    access_count: non_neg_integer()
  }
  ```
- [ ] 1.1.1.7 Define `access_entry()` struct type for access log entries:
  ```elixir
  @type access_entry :: %{
    key: context_key() | {:memory, String.t()},
    timestamp: DateTime.t(),
    access_type: :read | :write | :query
  }
  ```
- [ ] 1.1.1.8 Implement `confidence_to_level/1` helper function (float -> atom)
- [ ] 1.1.1.9 Implement `level_to_confidence/1` helper function (atom -> float)

### 1.1.2 Unit Tests for Memory Types

- [ ] Test memory_type values are valid atoms matching Jido ontology
- [ ] Test confidence_level values map correctly (:high >= 0.8, :medium >= 0.5, :low < 0.5)
- [ ] Test source_type values match Jido SourceType individuals
- [ ] Test context_key exhaustiveness matches design specification
- [ ] Test pending_item struct creation with all required fields
- [ ] Test pending_item struct creation with optional fields as nil
- [ ] Test access_entry struct creation with timestamp
- [ ] Test confidence_to_level/1 returns correct level for boundary values
- [ ] Test level_to_confidence/1 returns expected float values

---

## 1.2 Working Context Module

Implement the semantic scratchpad that holds extracted understanding about the current session. This provides fast access to current session context without requiring database queries.

### 1.2.1 WorkingContext Struct and API

- [ ] 1.2.1.1 Create `lib/jido_code/memory/short_term/working_context.ex` with comprehensive moduledoc
- [ ] 1.2.1.2 Define struct with fields:
  ```elixir
  defstruct [
    items: %{},           # %{context_key() => context_item()}
    current_tokens: 0,    # Approximate token count for budget management
    max_tokens: 12_000    # Maximum tokens allowed in working context
  ]
  ```
- [ ] 1.2.1.3 Define `context_item()` internal type:
  ```elixir
  @type context_item :: %{
    key: context_key(),
    value: term(),
    source: :inferred | :explicit | :tool,
    confidence: float(),
    access_count: non_neg_integer(),
    first_seen: DateTime.t(),
    last_accessed: DateTime.t(),
    suggested_type: memory_type() | nil
  }
  ```
- [ ] 1.2.1.4 Implement `new/0` and `new/1` constructors with optional max_tokens parameter
- [ ] 1.2.1.5 Implement `put/4` to add/update context items:
  ```elixir
  @spec put(t(), context_key(), term(), keyword()) :: t()
  def put(ctx, key, value, opts \\ [])
  ```
  - Accept options: `source`, `confidence`, `memory_type`
  - Track first_seen (preserve on update) and last_accessed (update always)
  - Increment access_count on updates
  - Infer suggested_type if not provided
- [ ] 1.2.1.6 Implement `get/2` to retrieve value and update access tracking:
  ```elixir
  @spec get(t(), context_key()) :: {t(), term() | nil}
  ```
  - Return updated context (with incremented access) and value
  - Return nil for missing keys without error
- [ ] 1.2.1.7 Implement `delete/2` to remove context items
- [ ] 1.2.1.8 Implement `to_list/1` to export all items for context assembly
- [ ] 1.2.1.9 Implement `to_map/1` to export items as key-value map (without metadata)
- [ ] 1.2.1.10 Implement `size/1` to return number of items
- [ ] 1.2.1.11 Implement `clear/1` to reset to empty context
- [ ] 1.2.1.12 Implement private `infer_memory_type/2` for suggested_type assignment:
  ```elixir
  defp infer_memory_type(:framework, :tool), do: :fact
  defp infer_memory_type(:primary_language, :tool), do: :fact
  defp infer_memory_type(:project_root, :tool), do: :fact
  defp infer_memory_type(:user_intent, :inferred), do: :assumption
  defp infer_memory_type(:discovered_patterns, _), do: :discovery
  defp infer_memory_type(:active_errors, _), do: nil  # Ephemeral, not promoted
  defp infer_memory_type(:pending_questions, _), do: :unknown
  defp infer_memory_type(_, _), do: nil
  ```

### 1.2.2 Unit Tests for WorkingContext

- [ ] Test new/0 creates empty context with default max_tokens (12_000)
- [ ] Test new/1 accepts custom max_tokens value
- [ ] Test put/4 creates new context item with all required fields
- [ ] Test put/4 sets first_seen and last_accessed to current time for new items
- [ ] Test put/4 updates existing item, incrementing access_count
- [ ] Test put/4 updates last_accessed but preserves first_seen on update
- [ ] Test put/4 accepts source option (:inferred, :explicit, :tool)
- [ ] Test put/4 accepts confidence option (0.0 to 1.0)
- [ ] Test put/4 accepts memory_type option overriding inference
- [ ] Test get/2 returns {context, value} for existing key
- [ ] Test get/2 increments access_count on retrieval
- [ ] Test get/2 updates last_accessed on retrieval
- [ ] Test get/2 returns {context, nil} for missing keys
- [ ] Test delete/2 removes item from context
- [ ] Test delete/2 handles non-existent keys gracefully
- [ ] Test to_list/1 returns all items as list
- [ ] Test to_map/1 returns key-value pairs without metadata
- [ ] Test size/1 returns correct count
- [ ] Test clear/1 resets to empty context
- [ ] Test infer_memory_type assigns :fact for :framework from :tool source
- [ ] Test infer_memory_type assigns :assumption for :user_intent from :inferred
- [ ] Test infer_memory_type assigns :discovery for :discovered_patterns
- [ ] Test infer_memory_type assigns nil for ephemeral keys like :active_errors

---

## 1.3 Pending Memories Module

Implement the staging area for memory items awaiting promotion to long-term storage. Supports both implicit promotion (via importance scoring) and explicit agent decisions.

### 1.3.1 PendingMemories Struct and API

- [ ] 1.3.1.1 Create `lib/jido_code/memory/short_term/pending_memories.ex` with moduledoc
- [ ] 1.3.1.2 Define struct:
  ```elixir
  defstruct [
    items: %{},           # %{id => pending_item()} - implicit staging
    agent_decisions: [],  # [pending_item()] - explicit agent requests (bypass threshold)
    max_items: 500        # Maximum pending items to prevent memory bloat
  ]
  ```
- [ ] 1.3.1.3 Implement `new/0` and `new/1` constructors with optional max_items
- [ ] 1.3.1.4 Implement `add_implicit/2` for items from pattern detection:
  ```elixir
  @spec add_implicit(t(), pending_item()) :: t()
  ```
  - Generate unique id if not provided
  - Enforce max_items limit (evict lowest importance_score)
  - Set suggested_by: :implicit
- [ ] 1.3.1.5 Implement `add_agent_decision/2` for explicit remember requests:
  ```elixir
  @spec add_agent_decision(t(), pending_item()) :: t()
  ```
  - These bypass importance threshold during promotion
  - Set suggested_by: :agent
  - Set importance_score: 1.0 (maximum)
- [ ] 1.3.1.6 Implement `ready_for_promotion/2` with configurable threshold:
  ```elixir
  @spec ready_for_promotion(t(), float()) :: [pending_item()]
  def ready_for_promotion(pending, threshold \\ 0.6)
  ```
  - Return items from `items` map with importance_score >= threshold
  - Always include all `agent_decisions` regardless of score
  - Sort by importance_score descending
- [ ] 1.3.1.7 Implement `clear_promoted/2` to remove promoted items:
  ```elixir
  @spec clear_promoted(t(), [String.t()]) :: t()
  ```
  - Remove specified ids from items map
  - Clear agent_decisions list entirely
- [ ] 1.3.1.8 Implement `get/2` to retrieve pending item by id
- [ ] 1.3.1.9 Implement `size/1` to return total pending count (items + agent_decisions)
- [ ] 1.3.1.10 Implement `update_score/3` to update importance_score for an item
- [ ] 1.3.1.11 Implement private `generate_id/0` for unique id generation
- [ ] 1.3.1.12 Implement private `evict_lowest/1` for enforcing max_items limit

### 1.3.2 Unit Tests for PendingMemories

- [ ] Test new/0 creates empty pending memories with default max_items
- [ ] Test new/1 accepts custom max_items value
- [ ] Test add_implicit/2 adds item to items map
- [ ] Test add_implicit/2 generates unique id if not provided
- [ ] Test add_implicit/2 sets suggested_by to :implicit
- [ ] Test add_implicit/2 enforces max_items limit by evicting lowest score
- [ ] Test add_agent_decision/2 adds to agent_decisions list
- [ ] Test add_agent_decision/2 sets suggested_by to :agent
- [ ] Test add_agent_decision/2 sets importance_score to 1.0
- [ ] Test ready_for_promotion/2 returns items above default threshold (0.6)
- [ ] Test ready_for_promotion/2 with custom threshold
- [ ] Test ready_for_promotion/2 always includes agent_decisions
- [ ] Test ready_for_promotion/2 sorts by importance_score descending
- [ ] Test clear_promoted/2 removes specified ids from items
- [ ] Test clear_promoted/2 clears agent_decisions list
- [ ] Test clear_promoted/2 handles non-existent ids gracefully
- [ ] Test get/2 returns pending item by id
- [ ] Test get/2 returns nil for non-existent id
- [ ] Test size/1 returns correct total count
- [ ] Test update_score/3 updates importance_score for existing item
- [ ] Test eviction removes item with lowest importance_score

---

## 1.4 Access Log Module

Implement tracking for memory access patterns to inform importance scoring during promotion decisions.

### 1.4.1 AccessLog Struct and API

- [ ] 1.4.1.1 Create `lib/jido_code/memory/short_term/access_log.ex` with moduledoc
- [ ] 1.4.1.2 Define struct:
  ```elixir
  defstruct [
    entries: [],          # [access_entry()] - newest first for O(1) prepend
    max_entries: 1000     # Limit to prevent unbounded memory growth
  ]
  ```
- [ ] 1.4.1.3 Define `access_entry()` type:
  ```elixir
  @type access_entry :: %{
    key: context_key() | {:memory, String.t()},
    timestamp: DateTime.t(),
    access_type: :read | :write | :query
  }
  ```
- [ ] 1.4.1.4 Implement `new/0` and `new/1` constructors with optional max_entries
- [ ] 1.4.1.5 Implement `record/3` to add access entry:
  ```elixir
  @spec record(t(), context_key() | {:memory, String.t()}, :read | :write | :query) :: t()
  ```
  - Prepend new entry (newest first)
  - Enforce max_entries limit (drop oldest)
  - Set timestamp to current time
- [ ] 1.4.1.6 Implement `get_frequency/2` to count accesses for a key:
  ```elixir
  @spec get_frequency(t(), context_key() | {:memory, String.t()}) :: non_neg_integer()
  ```
- [ ] 1.4.1.7 Implement `get_recency/2` to get most recent access timestamp:
  ```elixir
  @spec get_recency(t(), context_key() | {:memory, String.t()}) :: DateTime.t() | nil
  ```
- [ ] 1.4.1.8 Implement `get_stats/2` to get combined frequency and recency:
  ```elixir
  @spec get_stats(t(), context_key()) :: %{frequency: integer(), recency: DateTime.t() | nil}
  ```
- [ ] 1.4.1.9 Implement `recent_accesses/2` to get last N entries:
  ```elixir
  @spec recent_accesses(t(), pos_integer()) :: [access_entry()]
  ```
- [ ] 1.4.1.10 Implement `clear/1` to reset log to empty
- [ ] 1.4.1.11 Implement `size/1` to return entry count

### 1.4.2 Unit Tests for AccessLog

- [ ] Test new/0 creates empty log with default max_entries (1000)
- [ ] Test new/1 accepts custom max_entries value
- [ ] Test record/3 adds entry to front of list (newest first)
- [ ] Test record/3 sets timestamp to current time
- [ ] Test record/3 enforces max_entries limit by dropping oldest
- [ ] Test record/3 accepts context_key as key
- [ ] Test record/3 accepts {:memory, id} tuple as key
- [ ] Test record/3 accepts all access_type values (:read, :write, :query)
- [ ] Test get_frequency/2 counts all accesses for key
- [ ] Test get_frequency/2 returns 0 for unknown keys
- [ ] Test get_recency/2 returns most recent timestamp for key
- [ ] Test get_recency/2 returns nil for unknown keys
- [ ] Test get_stats/2 returns both frequency and recency
- [ ] Test recent_accesses/2 returns last N entries
- [ ] Test recent_accesses/2 returns all entries if N > size
- [ ] Test clear/1 resets entries to empty list
- [ ] Test size/1 returns correct entry count

---

## 1.5 Session.State Memory Extensions

Extend the existing Session.State GenServer with memory-related fields and callbacks. This integrates short-term memory into the existing session lifecycle.

### 1.5.1 State Struct Extensions

- [ ] 1.5.1.1 Add `working_context` field to `@type state` typespec in session/state.ex:
  ```elixir
  working_context: WorkingContext.t()
  ```
- [ ] 1.5.1.2 Add `pending_memories` field to `@type state`:
  ```elixir
  pending_memories: PendingMemories.t()
  ```
- [ ] 1.5.1.3 Add `access_log` field to `@type state`:
  ```elixir
  access_log: AccessLog.t()
  ```
- [ ] 1.5.1.4 Add memory configuration constants:
  ```elixir
  @max_pending_memories 500
  @max_access_log_entries 1000
  @default_context_max_tokens 12_000
  ```
- [ ] 1.5.1.5 Update `init/1` to initialize memory fields:
  ```elixir
  state = %{
    # ... existing fields ...
    working_context: WorkingContext.new(@default_context_max_tokens),
    pending_memories: PendingMemories.new(@max_pending_memories),
    access_log: AccessLog.new(@max_access_log_entries)
  }
  ```
- [ ] 1.5.1.6 Add alias imports for memory modules at top of file

### 1.5.2 Working Context Client API

- [ ] 1.5.2.1 Add `update_context/4` client function:
  ```elixir
  @spec update_context(String.t(), context_key(), term(), keyword()) ::
    :ok | {:error, :not_found}
  def update_context(session_id, key, value, opts \\ [])
  ```
- [ ] 1.5.2.2 Add `get_context/2` client function:
  ```elixir
  @spec get_context(String.t(), context_key()) ::
    {:ok, term()} | {:error, :not_found | :key_not_found}
  def get_context(session_id, key)
  ```
- [ ] 1.5.2.3 Add `get_all_context/1` client function:
  ```elixir
  @spec get_all_context(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_all_context(session_id)
  ```
- [ ] 1.5.2.4 Add `clear_context/1` client function:
  ```elixir
  @spec clear_context(String.t()) :: :ok | {:error, :not_found}
  def clear_context(session_id)
  ```

### 1.5.3 Pending Memories Client API

- [ ] 1.5.3.1 Add `add_pending_memory/2` client function:
  ```elixir
  @spec add_pending_memory(String.t(), pending_item()) :: :ok | {:error, :not_found}
  def add_pending_memory(session_id, item)
  ```
- [ ] 1.5.3.2 Add `add_agent_memory_decision/2` client function:
  ```elixir
  @spec add_agent_memory_decision(String.t(), pending_item()) :: :ok | {:error, :not_found}
  def add_agent_memory_decision(session_id, item)
  ```
- [ ] 1.5.3.3 Add `get_pending_memories/1` client function:
  ```elixir
  @spec get_pending_memories(String.t()) :: {:ok, [pending_item()]} | {:error, :not_found}
  def get_pending_memories(session_id)
  ```
- [ ] 1.5.3.4 Add `clear_promoted_memories/2` client function:
  ```elixir
  @spec clear_promoted_memories(String.t(), [String.t()]) :: :ok | {:error, :not_found}
  def clear_promoted_memories(session_id, promoted_ids)
  ```

### 1.5.4 Access Log Client API

- [ ] 1.5.4.1 Add `record_access/3` client function (async cast for performance):
  ```elixir
  @spec record_access(String.t(), context_key(), :read | :write | :query) :: :ok
  def record_access(session_id, key, access_type)
  ```
- [ ] 1.5.4.2 Add `get_access_stats/2` client function:
  ```elixir
  @spec get_access_stats(String.t(), context_key()) ::
    {:ok, %{frequency: integer(), recency: DateTime.t() | nil}} | {:error, :not_found}
  def get_access_stats(session_id, key)
  ```

### 1.5.5 GenServer Callbacks for Memory

- [ ] 1.5.5.1 Add `handle_call({:update_context, key, value, opts}, ...)` callback:
  ```elixir
  def handle_call({:update_context, key, value, opts}, _from, state) do
    updated_context = WorkingContext.put(state.working_context, key, value, opts)
    new_state = %{state | working_context: updated_context}
    {:reply, :ok, new_state}
  end
  ```
- [ ] 1.5.5.2 Add `handle_call({:get_context, key}, ...)` callback:
  - Return value and update access tracking
  - Return `{:error, :key_not_found}` for missing keys
- [ ] 1.5.5.3 Add `handle_call(:get_all_context, ...)` callback:
  - Return working_context as map via WorkingContext.to_map/1
- [ ] 1.5.5.4 Add `handle_call(:clear_context, ...)` callback:
  - Reset working_context via WorkingContext.clear/1
- [ ] 1.5.5.5 Add `handle_call({:add_pending_memory, item}, ...)` callback:
  - Use PendingMemories.add_implicit/2
  - Enforce size limit
- [ ] 1.5.5.6 Add `handle_call({:add_agent_memory_decision, item}, ...)` callback:
  - Use PendingMemories.add_agent_decision/2
- [ ] 1.5.5.7 Add `handle_call(:get_pending_memories, ...)` callback:
  - Return PendingMemories.ready_for_promotion/1 results
- [ ] 1.5.5.8 Add `handle_call({:clear_promoted_memories, ids}, ...)` callback:
  - Use PendingMemories.clear_promoted/2
- [ ] 1.5.5.9 Add `handle_cast({:record_access, key, type}, ...)` callback:
  - Use AccessLog.record/3
  - Async for performance during high-frequency access
- [ ] 1.5.5.10 Add `handle_call({:get_access_stats, key}, ...)` callback:
  - Use AccessLog.get_stats/2

### 1.5.6 Unit Tests for Session.State Memory Extensions

- [ ] Test init/1 initializes working_context with correct defaults
- [ ] Test init/1 initializes pending_memories with correct defaults
- [ ] Test init/1 initializes access_log with correct defaults
- [ ] Test update_context/4 stores context item in working_context
- [ ] Test update_context/4 updates existing item with incremented access_count
- [ ] Test update_context/4 accepts all supported options
- [ ] Test get_context/2 returns value for existing key
- [ ] Test get_context/2 returns {:error, :key_not_found} for missing key
- [ ] Test get_context/2 updates access tracking
- [ ] Test get_all_context/1 returns all context items as map
- [ ] Test clear_context/1 resets working_context to empty
- [ ] Test add_pending_memory/2 adds item to pending_memories
- [ ] Test add_pending_memory/2 enforces max_pending_memories limit
- [ ] Test add_agent_memory_decision/2 adds to agent_decisions with max score
- [ ] Test get_pending_memories/1 returns items ready for promotion
- [ ] Test clear_promoted_memories/2 removes promoted ids
- [ ] Test record_access/3 adds entry to access_log (async)
- [ ] Test get_access_stats/2 returns frequency and recency
- [ ] Test memory fields persist across multiple GenServer calls
- [ ] Test memory operations work with existing Session.State operations

---

## 1.6 Phase 1 Integration Tests

Comprehensive integration tests verifying memory foundation works with existing session lifecycle.

### 1.6.1 Session Lifecycle Integration

- [ ] 1.6.1.1 Create `test/jido_code/integration/memory_phase1_test.exs`
- [ ] 1.6.1.2 Test: Session.State initializes with empty memory fields
- [ ] 1.6.1.3 Test: Memory fields persist across multiple GenServer calls within session
- [ ] 1.6.1.4 Test: Session restart resets memory fields to defaults (not persisted in Phase 1)
- [ ] 1.6.1.5 Test: Memory operations don't interfere with existing Session.State operations
- [ ] 1.6.1.6 Test: Multiple sessions have isolated memory state

### 1.6.2 Working Context Integration

- [ ] 1.6.2.1 Test: Context updates propagate correctly through GenServer
- [ ] 1.6.2.2 Test: Multiple sessions have isolated working contexts
- [ ] 1.6.2.3 Test: Context access tracking updates correctly on get/put
- [ ] 1.6.2.4 Test: Context survives heavy read/write load without corruption

### 1.6.3 Pending Memories Integration

- [ ] 1.6.3.1 Test: Pending memories accumulate correctly over time
- [ ] 1.6.3.2 Test: Agent decisions bypass normal staging (importance_score = 1.0)
- [ ] 1.6.3.3 Test: Pending memory limit enforced correctly (evicts lowest score)
- [ ] 1.6.3.4 Test: clear_promoted_memories correctly removes specified items

### 1.6.4 Access Log Integration

- [ ] 1.6.4.1 Test: Access log records operations from context and memory access
- [ ] 1.6.4.2 Test: High-frequency access recording doesn't block other operations
- [ ] 1.6.4.3 Test: Access stats accurately reflect recorded activity

---

## Phase 1 Success Criteria

1. **Types Module**: All memory types defined with Jido ontology alignment
2. **WorkingContext**: Semantic scratchpad with access tracking and type inference functional
3. **PendingMemories**: Staging area with implicit and agent-decision paths working
4. **AccessLog**: Usage pattern tracking for importance scoring operational
5. **Session.State Extended**: All three memory fields integrated and accessible
6. **Isolation**: Multiple sessions maintain completely isolated memory state
7. **Compatibility**: Memory extensions don't break existing Session.State functionality
8. **Test Coverage**: Minimum 80% for all Phase 1 modules

---

## Phase 1 Critical Files

**New Files:**
- `lib/jido_code/memory/types.ex`
- `lib/jido_code/memory/short_term/working_context.ex`
- `lib/jido_code/memory/short_term/pending_memories.ex`
- `lib/jido_code/memory/short_term/access_log.ex`
- `test/jido_code/memory/types_test.exs`
- `test/jido_code/memory/short_term/working_context_test.exs`
- `test/jido_code/memory/short_term/pending_memories_test.exs`
- `test/jido_code/memory/short_term/access_log_test.exs`
- `test/jido_code/integration/memory_phase1_test.exs`

**Modified Files:**
- `lib/jido_code/session/state.ex` - Add memory fields and callbacks
- `test/jido_code/session/state_test.exs` - Add memory extension tests

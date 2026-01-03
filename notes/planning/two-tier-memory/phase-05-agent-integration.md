# Phase 5: LLMAgent Integration

This phase integrates the two-tier memory system with the LLMAgent, enabling automatic context assembly from memory, memory tool availability during chat, and automatic working context updates from LLM responses.

## Agent Integration Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                             LLMAgent                                      │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │                    Memory Integration Layer                         │  │
│  │                                                                      │  │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │  │
│  │  │  Context Builder │  │ Tool Registration │  │    Response      │  │  │
│  │  │                  │  │                   │  │   Processor      │  │  │
│  │  │ Assembles memory │  │ Registers memory  │  │                  │  │  │
│  │  │ context for LLM  │  │ actions at init   │  │ Extracts context │  │  │
│  │  │ prompts          │  │                   │  │ from responses   │  │  │
│  │  └──────────────────┘  └──────────────────┘  └──────────────────┘  │  │
│  │           │                     │                     │             │  │
│  │           ▼                     ▼                     ▼             │  │
│  │  ┌──────────────────────────────────────────────────────────────┐  │  │
│  │  │                  Token Budget Manager                         │  │  │
│  │  │  - Allocates tokens: system, conversation, context, memory   │  │  │
│  │  │  - Enforces budget limits during assembly                    │  │  │
│  │  │  - Triggers summarization when needed                        │  │  │
│  │  └──────────────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                    │                                      │
│  Before LLM Call:                  │  After LLM Response:                │
│  - Assemble memory context         │  - Extract context items            │
│  - Format for system prompt        │  - Update working context           │
│  - Respect token budget            │  - Record access patterns           │
└──────────────────────────────────────────────────────────────────────────┘
```

## Module Structure

```
lib/jido_code/memory/
├── context_builder.ex         # Context assembly from memory
├── response_processor.ex      # Automatic context extraction
└── token_counter.ex           # Token estimation utilities
```

---

## 5.1 Context Builder

Implement the context builder that combines short-term and long-term memory for inclusion in LLM prompts.

### 5.1.1 Context Builder Module

- [ ] 5.1.1.1 Create `lib/jido_code/memory/context_builder.ex` with moduledoc:
  ```elixir
  @moduledoc """
  Builds memory-enhanced context for LLM prompts.

  Combines:
  - Working context (current session state)
  - Long-term memories (relevant persisted knowledge)

  Respects token budget allocation and prioritizes content
  based on relevance and recency.
  """
  ```
- [ ] 5.1.1.2 Define context struct type:
  ```elixir
  @type context :: %{
    conversation: [message()],
    working_context: map(),
    long_term_memories: [stored_memory()],
    system_context: String.t(),
    token_counts: %{
      conversation: non_neg_integer(),
      working: non_neg_integer(),
      long_term: non_neg_integer(),
      total: non_neg_integer()
    }
  }
  ```
- [ ] 5.1.1.3 Define default token budget:
  ```elixir
  @default_budget %{
    total: 32_000,
    system: 2_000,
    conversation: 20_000,
    working: 4_000,
    long_term: 6_000
  }
  ```
- [ ] 5.1.1.4 Implement `build/2` main function:
  ```elixir
  @spec build(String.t(), keyword()) :: {:ok, context()} | {:error, term()}
  def build(session_id, opts \\ []) do
    token_budget = Keyword.get(opts, :token_budget, @default_budget)
    query_hint = Keyword.get(opts, :query_hint)
    include_memories = Keyword.get(opts, :include_memories, true)

    with {:ok, conversation} <- get_conversation(session_id, token_budget.conversation),
         {:ok, working} <- get_working_context(session_id),
         {:ok, long_term} <- get_relevant_memories(session_id, query_hint, include_memories) do
      {:ok, assemble_context(conversation, working, long_term, token_budget)}
    end
  end
  ```
- [ ] 5.1.1.5 Implement `get_conversation/2`:
  - Retrieve messages from Session.State
  - Apply token-aware truncation (keep most recent)
  - Return within budget allocation
- [ ] 5.1.1.6 Implement `get_working_context/1`:
  - Retrieve working context from Session.State
  - Serialize to key-value map
- [ ] 5.1.1.7 Implement `get_relevant_memories/3`:
  ```elixir
  defp get_relevant_memories(session_id, query_hint, include?) do
    if include? do
      opts = if query_hint do
        [limit: 10]  # More memories when we have a query hint
      else
        [min_confidence: 0.7, limit: 5]  # Fewer, higher confidence when no hint
      end

      Memory.query(session_id, opts)
    else
      {:ok, []}
    end
  end
  ```
- [ ] 5.1.1.8 Implement `assemble_context/4`:
  - Combine all components
  - Calculate token counts for each
  - Enforce budget limits with priority ordering
  - Return assembled context struct

### 5.1.2 Context Formatting

- [ ] 5.1.2.1 Implement `format_for_prompt/1`:
  ```elixir
  @spec format_for_prompt(context()) :: String.t()
  def format_for_prompt(%{working_context: working, long_term_memories: memories}) do
    parts = []

    parts = if map_size(working) > 0 do
      ["## Session Context\n" <> format_working_context(working) | parts]
    else
      parts
    end

    parts = if length(memories) > 0 do
      ["## Remembered Information\n" <> format_memories(memories) | parts]
    else
      parts
    end

    Enum.join(Enum.reverse(parts), "\n\n")
  end
  ```
- [ ] 5.1.2.2 Implement `format_working_context/1`:
  ```elixir
  defp format_working_context(working) do
    working
    |> Enum.map(fn {key, value} ->
      "- **#{format_key(key)}**: #{format_value(value)}"
    end)
    |> Enum.join("\n")
  end

  defp format_key(key) when is_atom(key) do
    key |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
  end
  ```
- [ ] 5.1.2.3 Implement `format_memories/1`:
  ```elixir
  defp format_memories(memories) do
    memories
    |> Enum.map(fn mem ->
      confidence_badge = confidence_badge(mem.confidence)
      type_badge = "[#{mem.memory_type}]"
      "- #{type_badge} #{confidence_badge} #{mem.content}"
    end)
    |> Enum.join("\n")
  end

  defp confidence_badge(c) when c >= 0.8, do: "(high confidence)"
  defp confidence_badge(c) when c >= 0.5, do: "(medium confidence)"
  defp confidence_badge(_), do: "(low confidence)"
  ```
- [ ] 5.1.2.4 Include memory timestamps for recency context

### 5.1.3 Unit Tests for Context Builder

- [ ] Test build/2 assembles all context components
- [ ] Test build/2 respects total token budget
- [ ] Test build/2 with query_hint retrieves more memories
- [ ] Test build/2 without query_hint filters by high confidence
- [ ] Test build/2 with include_memories: false skips memory query
- [ ] Test get_conversation/2 truncates to budget
- [ ] Test get_conversation/2 preserves most recent messages
- [ ] Test get_working_context/1 returns serialized map
- [ ] Test get_relevant_memories/3 applies correct filters
- [ ] Test assemble_context/4 calculates token counts
- [ ] Test format_for_prompt/1 produces valid markdown
- [ ] Test format_for_prompt/1 handles empty context gracefully
- [ ] Test format_working_context/1 formats key-value pairs
- [ ] Test format_memories/1 includes type and confidence badges
- [ ] Test context handles missing session gracefully

---

## 5.2 LLMAgent Memory Integration

Extend LLMAgent to use the memory system for context assembly and tool availability.

### 5.2.1 Agent Initialization Updates

- [ ] 5.2.1.1 Add memory configuration to agent state:
  ```elixir
  @default_token_budget 32_000

  defstruct [
    # ... existing fields ...
    memory_enabled: true,
    token_budget: @default_token_budget
  ]
  ```
- [ ] 5.2.1.2 Update `init/1` to accept memory options:
  ```elixir
  def init(opts) do
    memory_opts = Keyword.get(opts, :memory, [])

    state = %{
      # ... existing init ...
      memory_enabled: Keyword.get(memory_opts, :enabled, true),
      token_budget: Keyword.get(memory_opts, :token_budget, @default_token_budget)
    }

    {:ok, state}
  end
  ```
- [ ] 5.2.1.3 Document memory configuration options in moduledoc

### 5.2.2 Memory Tool Registration

- [ ] 5.2.2.1 Add memory tools to available tools list:
  ```elixir
  defp get_available_tools(state) do
    base_tools = get_base_tools()

    if state.memory_enabled do
      base_tools ++ Memory.Actions.to_tool_definitions()
    else
      base_tools
    end
  end
  ```
- [ ] 5.2.2.2 Implement helper to identify memory tools:
  ```elixir
  defp memory_tool?(name) do
    name in ["remember", "recall", "forget"]
  end
  ```
- [ ] 5.2.2.3 Route memory tool calls to action executor:
  ```elixir
  defp execute_tool_call(name, args, context) when memory_tool?(name) do
    {:ok, action} = Memory.Actions.get(name)
    action.run(args, context)
  end
  ```

### 5.2.3 Pre-Call Context Assembly

- [ ] 5.2.3.1 Update chat flow to assemble memory context:
  ```elixir
  defp execute_stream(model, message, topic, session_id, state) do
    # Build memory-enhanced context
    context = if state.memory_enabled and valid_session_id?(session_id) do
      case ContextBuilder.build(session_id,
        token_budget: state.token_budget,
        query_hint: message
      ) do
        {:ok, ctx} -> ctx
        {:error, _} -> nil
      end
    else
      nil
    end

    # Build system prompt with memory context
    system_prompt = build_system_prompt(session_id, context)

    # ... rest of streaming logic ...
  end
  ```
- [ ] 5.2.3.2 Update `build_system_prompt/2`:
  ```elixir
  defp build_system_prompt(session_id, context) do
    base = get_base_system_prompt()
    with_language = add_language_instruction(base, get_language(session_id))

    if context do
      memory_section = ContextBuilder.format_for_prompt(context)
      with_language <> "\n\n" <> memory_section
    else
      with_language
    end
  end
  ```
- [ ] 5.2.3.3 Ensure context is session-scoped

### 5.2.4 Unit Tests for Agent Integration

- [ ] Test agent initializes with memory enabled by default
- [ ] Test agent accepts memory_enabled: false option
- [ ] Test agent accepts custom token_budget option
- [ ] Test get_available_tools includes memory tools when enabled
- [ ] Test get_available_tools excludes memory tools when disabled
- [ ] Test memory tool calls route to action executor
- [ ] Test context assembly runs before LLM call
- [ ] Test system prompt includes formatted memory context
- [ ] Test agent works correctly with memory disabled
- [ ] Test invalid session_id doesn't crash context assembly

---

## 5.3 Response Processor

Implement automatic extraction and storage of working context from LLM responses.

### 5.3.1 Response Processor Module

- [ ] 5.3.1.1 Create `lib/jido_code/memory/response_processor.ex` with moduledoc
- [ ] 5.3.1.2 Define extraction patterns:
  ```elixir
  @context_patterns %{
    active_file: [
      ~r/(?:working on|editing|reading|looking at)\s+[`"]?([^`"\s]+\.\w+)[`"]?/i,
      ~r/file[:\s]+[`"]?([^`"\s]+\.\w+)[`"]?/i
    ],
    framework: [
      ~r/(?:using|project uses|built with|based on)\s+([A-Z][a-zA-Z]+(?:\s+\d+(?:\.\d+)*)?)/i
    ],
    current_task: [
      ~r/(?:implementing|fixing|creating|adding|updating|refactoring)\s+(.+?)(?:\.|$)/i
    ],
    primary_language: [
      ~r/(?:this is an?|written in)\s+(\w+)\s+(?:project|codebase|application)/i
    ]
  }
  ```
- [ ] 5.3.1.3 Implement `process_response/2`:
  ```elixir
  @spec process_response(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def process_response(response, session_id) do
    extractions = extract_context(response)

    if map_size(extractions) > 0 do
      update_working_context(extractions, session_id)
    end

    {:ok, extractions}
  end
  ```
- [ ] 5.3.1.4 Implement `extract_context/1`:
  ```elixir
  defp extract_context(response) do
    @context_patterns
    |> Enum.reduce(%{}, fn {key, patterns}, acc ->
      case extract_first_match(response, patterns) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp extract_first_match(text, patterns) do
    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, text) do
        [_, match | _] -> String.trim(match)
        _ -> nil
      end
    end)
  end
  ```
- [ ] 5.3.1.5 Implement `update_working_context/2`:
  ```elixir
  defp update_working_context(extractions, session_id) do
    Enum.each(extractions, fn {key, value} ->
      Session.State.update_context(session_id, key, value,
        source: :inferred,
        confidence: 0.6  # Lower confidence for inferred
      )
    end)
  end
  ```

### 5.3.2 Integration with Stream Processing

- [ ] 5.3.2.1 Add response processing after stream completion:
  ```elixir
  defp broadcast_stream_end(topic, full_content, session_id, metadata) do
    # Broadcast stream end event
    PubSub.broadcast(topic, {:stream_end, full_content, metadata})

    # Process response for context extraction (async)
    if valid_session_id?(session_id) do
      Task.start(fn ->
        ResponseProcessor.process_response(full_content, session_id)
      end)
    end
  end
  ```
- [ ] 5.3.2.2 Make extraction async to not block stream completion
- [ ] 5.3.2.3 Add error handling for extraction failures
- [ ] 5.3.2.4 Log extraction results for debugging

### 5.3.3 Unit Tests for Response Processor

- [ ] Test extract_context finds active_file from "working on file.ex"
- [ ] Test extract_context finds active_file from "editing `config.exs`"
- [ ] Test extract_context finds framework from "using Phoenix 1.7"
- [ ] Test extract_context finds current_task from "implementing user auth"
- [ ] Test extract_context finds primary_language from "this is an Elixir project"
- [ ] Test extract_context handles responses without patterns
- [ ] Test extract_context extracts multiple context items
- [ ] Test process_response updates working context
- [ ] Test process_response assigns inferred source
- [ ] Test process_response uses lower confidence (0.6)
- [ ] Test extraction handles empty response
- [ ] Test extraction handles malformed patterns gracefully

---

## 5.4 Token Budget Management

Implement token budget management for memory-aware context assembly.

### 5.4.1 Token Counter Module

- [ ] 5.4.1.1 Create `lib/jido_code/memory/token_counter.ex`
- [ ] 5.4.1.2 Implement approximate token estimation:
  ```elixir
  @moduledoc """
  Fast token estimation for budget management.

  Uses character-based approximation (4 chars ≈ 1 token for English).
  Suitable for budget enforcement, not billing.
  """

  @chars_per_token 4

  @spec estimate_tokens(String.t()) :: non_neg_integer()
  def estimate_tokens(text) when is_binary(text) do
    div(String.length(text), @chars_per_token)
  end

  def estimate_tokens(nil), do: 0
  ```
- [ ] 5.4.1.3 Implement message token counting:
  ```elixir
  @spec count_message(map()) :: non_neg_integer()
  def count_message(%{content: content, role: role}) do
    # Account for role/structure overhead
    overhead = 4
    estimate_tokens(content) + overhead
  end
  ```
- [ ] 5.4.1.4 Implement memory token counting:
  ```elixir
  @spec count_memory(stored_memory()) :: non_neg_integer()
  def count_memory(memory) do
    content_tokens = estimate_tokens(memory.content)
    metadata_overhead = 10  # type, confidence, timestamp
    content_tokens + metadata_overhead
  end
  ```
- [ ] 5.4.1.5 Implement list counting:
  ```elixir
  @spec count_messages([map()]) :: non_neg_integer()
  def count_messages(messages) do
    Enum.reduce(messages, 0, &(count_message(&1) + &2))
  end

  @spec count_memories([stored_memory()]) :: non_neg_integer()
  def count_memories(memories) do
    Enum.reduce(memories, 0, &(count_memory(&1) + &2))
  end
  ```

### 5.4.2 Budget Allocator

- [ ] 5.4.2.1 Implement budget allocation in ContextBuilder:
  ```elixir
  @spec allocate_budget(non_neg_integer()) :: map()
  def allocate_budget(total) do
    %{
      total: total,
      system: min(2_000, div(total, 16)),        # ~6%
      conversation: div(total * 5, 8),            # 62.5%
      working: div(total, 8),                     # 12.5%
      long_term: div(total * 3, 16)               # ~19%
    }
  end
  ```
- [ ] 5.4.2.2 Implement budget enforcement during assembly:
  ```elixir
  defp enforce_budget(content, budget, counter_fn) do
    current = counter_fn.(content)
    if current <= budget do
      content
    else
      truncate_to_budget(content, budget, counter_fn)
    end
  end
  ```
- [ ] 5.4.2.3 Implement conversation truncation (preserve recent):
  ```elixir
  defp truncate_conversation(messages, budget) do
    # Start from most recent, add until budget exhausted
    {kept, _remaining} = Enum.reduce_while(
      Enum.reverse(messages),
      {[], budget},
      fn msg, {acc, remaining} ->
        tokens = TokenCounter.count_message(msg)
        if tokens <= remaining do
          {:cont, {[msg | acc], remaining - tokens}}
        else
          {:halt, {acc, 0}}
        end
      end
    )
    kept
  end
  ```
- [ ] 5.4.2.4 Implement memory truncation (preserve highest confidence):
  ```elixir
  defp truncate_memories(memories, budget) do
    memories
    |> Enum.sort_by(& &1.confidence, :desc)
    |> Enum.reduce_while({[], budget}, fn mem, {acc, remaining} ->
      tokens = TokenCounter.count_memory(mem)
      if tokens <= remaining do
        {:cont, {[mem | acc], remaining - tokens}}
      else
        {:halt, {acc, 0}}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end
  ```

### 5.4.3 Unit Tests for Token Budget

- [ ] Test estimate_tokens produces reasonable estimates
- [ ] Test estimate_tokens handles empty string
- [ ] Test count_message includes overhead
- [ ] Test count_memory includes metadata overhead
- [ ] Test count_messages sums correctly
- [ ] Test count_memories sums correctly
- [ ] Test allocate_budget distributes tokens correctly
- [ ] Test allocate_budget handles small budgets
- [ ] Test enforce_budget returns content within budget
- [ ] Test truncate_conversation preserves most recent
- [ ] Test truncate_memories preserves highest confidence
- [ ] Test context assembly respects total budget

---

## 5.5 Phase 5 Integration Tests

Comprehensive integration tests for LLMAgent memory integration.

### 5.5.1 Context Assembly Integration

- [ ] 5.5.1.1 Create `test/jido_code/integration/agent_memory_test.exs`
- [ ] 5.5.1.2 Test: Agent assembles context including working context
- [ ] 5.5.1.3 Test: Agent assembles context including long-term memories
- [ ] 5.5.1.4 Test: Agent context respects total token budget
- [ ] 5.5.1.5 Test: Context updates after tool execution
- [ ] 5.5.1.6 Test: Context reflects most recent session state

### 5.5.2 Memory Tool Execution Integration

- [ ] 5.5.2.1 Test: Agent can execute remember tool during chat
- [ ] 5.5.2.2 Test: Agent can execute recall tool during chat
- [ ] 5.5.2.3 Test: Agent can execute forget tool during chat
- [ ] 5.5.2.4 Test: Memory tool results formatted correctly for LLM
- [ ] 5.5.2.5 Test: Tool execution updates session state

### 5.5.3 Response Processing Integration

- [ ] 5.5.3.1 Test: Response processor extracts context from real LLM responses
- [ ] 5.5.3.2 Test: Extracted context appears in next context assembly
- [ ] 5.5.3.3 Test: Response processing runs async (doesn't block)
- [ ] 5.5.3.4 Test: Multiple responses accumulate context correctly

### 5.5.4 Token Budget Integration

- [ ] 5.5.4.1 Test: Large conversations truncated to budget
- [ ] 5.5.4.2 Test: Many memories truncated to budget
- [ ] 5.5.4.3 Test: Budget allocation correct for various total budgets
- [ ] 5.5.4.4 Test: Truncation preserves most important content

---

## Phase 5 Success Criteria

1. **Context Assembly**: Agent builds memory-enhanced prompts from both tiers
2. **Memory Tools Available**: All memory tools callable during chat sessions
3. **Automatic Extraction**: Working context updated from LLM responses
4. **Token Budget**: Context respects configured token limits
5. **Graceful Degradation**: Memory features fail safely without breaking agent
6. **Performance**: Context assembly doesn't significantly slow response time
7. **Test Coverage**: Minimum 80% for Phase 5 components

---

## Phase 5 Critical Files

**New Files:**
- `lib/jido_code/memory/context_builder.ex`
- `lib/jido_code/memory/response_processor.ex`
- `lib/jido_code/memory/token_counter.ex`
- `test/jido_code/memory/context_builder_test.exs`
- `test/jido_code/memory/response_processor_test.exs`
- `test/jido_code/memory/token_counter_test.exs`
- `test/jido_code/integration/agent_memory_test.exs`

**Modified Files:**
- `lib/jido_code/agents/llm_agent.ex` - Add memory integration
- `test/jido_code/agents/llm_agent_test.exs` - Add memory tests

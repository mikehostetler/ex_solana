# Phase 6: Advanced Features & Optimization

This phase adds advanced memory features including context summarization, semantic search, automatic pruning, backup/restore functionality, and comprehensive telemetry for monitoring and debugging.

## Advanced Features Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                      Advanced Memory Features                             │
│                                                                           │
│  ┌────────────────┐  ┌────────────────┐  ┌────────────────────────────┐  │
│  │  Summarizer    │  │   Semantic     │  │    Pruning Engine          │  │
│  │                │  │   Search       │  │                            │  │
│  │ Compresses     │  │                │  │ Removes low-value          │  │
│  │ conversation   │  │ TF-IDF based   │  │ memories based on:         │  │
│  │ when budget    │  │ similarity     │  │ - Age                      │  │
│  │ exceeded       │  │ matching       │  │ - Confidence               │  │
│  │                │  │                │  │ - Access patterns          │  │
│  └────────────────┘  └────────────────┘  └────────────────────────────┘  │
│                                                                           │
│  ┌──────────────────────────────────────────────────────────────────────┐│
│  │                    Backup & Restore                                   ││
│  │  - Export memories to JSON                                            ││
│  │  - Import with conflict resolution                                    ││
│  │  - Version-aware format                                               ││
│  └──────────────────────────────────────────────────────────────────────┘│
│                                                                           │
│  ┌──────────────────────────────────────────────────────────────────────┐│
│  │                    Telemetry & Monitoring                             ││
│  │  - Events for all memory operations                                   ││
│  │  - Statistics collection                                              ││
│  │  - Performance metrics                                                ││
│  └──────────────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────────────┘
```

## Module Structure

```
lib/jido_code/memory/
├── summarizer.ex              # Context summarization
├── embeddings.ex              # TF-IDF embeddings for semantic search
├── pruning.ex                 # Memory pruning strategies
├── backup.ex                  # Export/import functionality
└── telemetry.ex               # Telemetry events and metrics
```

---

## 6.1 Context Summarization

Implement context summarization to compress conversation history when token budget is exceeded. Uses extractive summarization (rule-based, no LLM dependency).

### 6.1.1 Summarizer Module

- [ ] 6.1.1.1 Create `lib/jido_code/memory/summarizer.ex` with moduledoc:
  ```elixir
  @moduledoc """
  Extracts key information from conversation history for compression.

  Uses rule-based extractive summarization to identify and preserve
  the most important messages while reducing token count.

  Scoring heuristics:
  - User messages weighted higher than assistant
  - Questions and decisions score higher
  - Recent messages preferred over old
  - Tool results summarized to outcomes only
  """
  ```
- [ ] 6.1.1.2 Define message importance weights:
  ```elixir
  @role_weights %{
    user: 1.0,
    assistant: 0.6,
    tool: 0.4,
    system: 0.8
  }

  @content_indicators %{
    question: {~r/\?/, 0.3},
    decision: {~r/(?:decided|choosing|going with|will use)/i, 0.4},
    error: {~r/(?:error|failed|exception|bug)/i, 0.3},
    important: {~r/(?:important|critical|must|required)/i, 0.2}
  }
  ```
- [ ] 6.1.1.3 Implement `summarize/2`:
  ```elixir
  @spec summarize([message()], non_neg_integer()) :: [message()]
  def summarize(messages, target_tokens) do
    messages
    |> score_messages()
    |> select_top_messages(target_tokens)
    |> add_summary_markers()
  end
  ```
- [ ] 6.1.1.4 Implement `score_messages/1`:
  ```elixir
  defp score_messages(messages) do
    total = length(messages)

    messages
    |> Enum.with_index()
    |> Enum.map(fn {msg, idx} ->
      role_score = Map.get(@role_weights, msg.role, 0.5)
      recency_score = idx / total  # More recent = higher
      content_score = score_content(msg.content)

      score = (role_score * 0.3) + (recency_score * 0.4) + (content_score * 0.3)
      {msg, score}
    end)
  end
  ```
- [ ] 6.1.1.5 Implement `score_content/1`:
  ```elixir
  defp score_content(content) do
    @content_indicators
    |> Enum.reduce(0.0, fn {_name, {pattern, boost}}, acc ->
      if Regex.match?(pattern, content), do: acc + boost, else: acc
    end)
    |> min(1.0)
  end
  ```
- [ ] 6.1.1.6 Implement `select_top_messages/2`:
  ```elixir
  defp select_top_messages(scored_messages, target_tokens) do
    scored_messages
    |> Enum.sort_by(fn {_msg, score} -> score end, :desc)
    |> Enum.reduce_while({[], 0}, fn {msg, _score}, {acc, tokens} ->
      msg_tokens = TokenCounter.count_message(msg)
      if tokens + msg_tokens <= target_tokens do
        {:cont, {[msg | acc], tokens + msg_tokens}}
      else
        {:halt, {acc, tokens}}
      end
    end)
    |> elem(0)
    |> Enum.sort_by(& &1.timestamp)  # Restore chronological order
  end
  ```
- [ ] 6.1.1.7 Implement `add_summary_markers/1`:
  ```elixir
  defp add_summary_markers(messages) do
    # Add marker indicating summarization occurred
    summary_note = %{
      id: "summary-marker",
      role: :system,
      content: "[Earlier conversation summarized to key points]",
      timestamp: DateTime.utc_now()
    }
    [summary_note | messages]
  end
  ```

### 6.1.2 Summarization Integration

- [ ] 6.1.2.1 Add summarization to ContextBuilder:
  ```elixir
  defp get_conversation(session_id, budget) do
    {:ok, messages} = Session.State.get_messages(session_id)
    current_tokens = TokenCounter.count_messages(messages)

    if current_tokens > budget do
      {:ok, Summarizer.summarize(messages, budget)}
    else
      {:ok, messages}
    end
  end
  ```
- [ ] 6.1.2.2 Implement summary caching:
  ```elixir
  @summary_cache_key :conversation_summary

  defp get_cached_summary(session_id) do
    Session.State.get_context(session_id, @summary_cache_key)
  end

  defp cache_summary(session_id, summary, message_count) do
    Session.State.update_context(session_id, @summary_cache_key, %{
      summary: summary,
      message_count: message_count,
      created_at: DateTime.utc_now()
    })
  end
  ```
- [ ] 6.1.2.3 Invalidate cache on new messages
- [ ] 6.1.2.4 Add force_summarize option to bypass cache

### 6.1.3 Unit Tests for Summarization

- [ ] Test summarize/2 reduces token count to target
- [ ] Test summarize/2 preserves user messages preferentially
- [ ] Test summarize/2 preserves recent messages
- [ ] Test summarize/2 preserves questions and decisions
- [ ] Test summarize/2 maintains chronological order after selection
- [ ] Test summarize/2 adds summary marker
- [ ] Test score_messages assigns correct role weights
- [ ] Test score_content boosts questions
- [ ] Test score_content boosts decisions
- [ ] Test score_content boosts error mentions
- [ ] Test summary caching works correctly
- [ ] Test cache invalidation on new messages

---

## 6.2 Semantic Memory Search

Implement semantic similarity search for more intelligent memory retrieval using TF-IDF embeddings (no external dependencies).

### 6.2.1 Embeddings Module

- [ ] 6.2.1.1 Create `lib/jido_code/memory/embeddings.ex` with moduledoc:
  ```elixir
  @moduledoc """
  TF-IDF based text embeddings for semantic similarity.

  Provides lightweight semantic search without external model dependencies.
  Suitable for finding related memories based on content similarity.
  """
  ```
- [ ] 6.2.1.2 Implement tokenization:
  ```elixir
  @spec tokenize(String.t()) :: [String.t()]
  def tokenize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&stopword?/1)
  end

  @stopwords ~w(the a an is are was were be been being have has had do does did will would could should may might must shall can)

  defp stopword?(word), do: word in @stopwords
  ```
- [ ] 6.2.1.3 Implement TF-IDF calculation:
  ```elixir
  @spec compute_tfidf([String.t()], map()) :: map()
  def compute_tfidf(tokens, corpus_stats) do
    # Term frequency in document
    tf = Enum.frequencies(tokens)
    doc_length = length(tokens)

    # TF-IDF for each term
    Enum.reduce(tf, %{}, fn {term, count}, acc ->
      tf_score = count / doc_length
      idf_score = Map.get(corpus_stats.idf, term, corpus_stats.default_idf)
      Map.put(acc, term, tf_score * idf_score)
    end)
  end
  ```
- [ ] 6.2.1.4 Implement embedding generation:
  ```elixir
  @spec generate(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def generate(text, corpus_stats \\ default_corpus_stats()) do
    tokens = tokenize(text)
    if tokens == [] do
      {:error, :empty_text}
    else
      {:ok, compute_tfidf(tokens, corpus_stats)}
    end
  end
  ```
- [ ] 6.2.1.5 Implement cosine similarity:
  ```elixir
  @spec cosine_similarity(map(), map()) :: float()
  def cosine_similarity(vec_a, vec_b) do
    # Get all terms
    all_terms = MapSet.union(
      MapSet.new(Map.keys(vec_a)),
      MapSet.new(Map.keys(vec_b))
    )

    # Calculate dot product and magnitudes
    {dot, mag_a, mag_b} = Enum.reduce(all_terms, {0.0, 0.0, 0.0}, fn term, {dot, ma, mb} ->
      a = Map.get(vec_a, term, 0.0)
      b = Map.get(vec_b, term, 0.0)
      {dot + (a * b), ma + (a * a), mb + (b * b)}
    end)

    if mag_a == 0.0 or mag_b == 0.0 do
      0.0
    else
      dot / (:math.sqrt(mag_a) * :math.sqrt(mag_b))
    end
  end
  ```
- [ ] 6.2.1.6 Implement default corpus stats (common English IDF values)

### 6.2.2 Semantic Search Integration

- [ ] 6.2.2.1 Add embedding storage to memory persistence:
  ```elixir
  # In TripleStoreAdapter.persist/2
  embedding = Embeddings.generate(memory.content)
  embedding_triple = {subject, Vocab.has_embedding(), serialize_embedding(embedding)}
  ```
- [ ] 6.2.2.2 Update Recall action to use semantic search:
  ```elixir
  defp query_with_semantic_search(query, memories) do
    {:ok, query_embedding} = Embeddings.generate(query)

    memories
    |> Enum.map(fn mem ->
      {:ok, mem_embedding} = get_or_compute_embedding(mem)
      score = Embeddings.cosine_similarity(query_embedding, mem_embedding)
      {mem, score}
    end)
    |> Enum.filter(fn {_, score} -> score > 0.2 end)  # Similarity threshold
    |> Enum.sort_by(fn {_, score} -> score end, :desc)
    |> Enum.map(fn {mem, _} -> mem end)
  end
  ```
- [ ] 6.2.2.3 Add fallback to text search when embeddings unavailable
- [ ] 6.2.2.4 Cache embeddings in memory struct

### 6.2.3 Unit Tests for Semantic Search

- [ ] Test tokenize removes stopwords
- [ ] Test tokenize handles punctuation
- [ ] Test tokenize handles case
- [ ] Test compute_tfidf produces valid scores
- [ ] Test generate returns embedding map
- [ ] Test generate handles empty text
- [ ] Test cosine_similarity returns 1.0 for identical vectors
- [ ] Test cosine_similarity returns 0.0 for orthogonal vectors
- [ ] Test cosine_similarity handles partial overlap
- [ ] Test semantic search returns related memories
- [ ] Test semantic search ranks by relevance
- [ ] Test fallback to text search works

---

## 6.3 Memory Pruning

Implement automatic memory pruning to manage long-term storage growth.

### 6.3.1 Pruning Engine Module

- [ ] 6.3.1.1 Create `lib/jido_code/memory/pruning.ex` with moduledoc:
  ```elixir
  @moduledoc """
  Automatic memory pruning to manage storage growth.

  Strategies:
  - Age-based: Remove memories older than retention period
  - Confidence-based: Remove low-confidence memories
  - Access-based: Remove memories never accessed after creation
  - Combined: Score-based removal using all factors

  Always uses supersession (soft delete) to maintain provenance.
  """
  ```
- [ ] 6.3.1.2 Define pruning configuration:
  ```elixir
  @default_config %{
    strategy: :combined,
    retention_days: 90,
    min_confidence: 0.3,
    min_access_count: 2,
    max_memories: 1000,
    protected_types: [:decision, :convention, :lesson_learned]
  }
  ```
- [ ] 6.3.1.3 Implement `prune/2`:
  ```elixir
  @spec prune(String.t(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def prune(session_id, opts \\ []) do
    config = Keyword.merge(@default_config, opts) |> Map.new()

    with {:ok, memories} <- Memory.query(session_id, include_superseded: false),
         candidates <- identify_candidates(memories, config),
         {:ok, count} <- supersede_candidates(candidates, session_id) do
      emit_pruning_telemetry(session_id, count)
      {:ok, count}
    end
  end
  ```
- [ ] 6.3.1.4 Implement `identify_candidates/2`:
  ```elixir
  defp identify_candidates(memories, config) do
    memories
    |> Enum.reject(&protected?(&1, config))
    |> Enum.map(&score_for_pruning(&1, config))
    |> Enum.filter(fn {_mem, score} -> score < config.retention_threshold end)
    |> Enum.map(fn {mem, _} -> mem end)
  end
  ```
- [ ] 6.3.1.5 Implement `score_for_pruning/2`:
  ```elixir
  defp score_for_pruning(memory, config) do
    age_score = age_score(memory.timestamp, config.retention_days)
    conf_score = memory.confidence
    access_score = access_score(memory.access_count, config.min_access_count)

    # Higher score = more valuable = less likely to prune
    score = (age_score * 0.3) + (conf_score * 0.4) + (access_score * 0.3)
    {memory, score}
  end

  defp age_score(timestamp, retention_days) do
    age_days = DateTime.diff(DateTime.utc_now(), timestamp, :day)
    max(0, 1 - (age_days / retention_days))
  end

  defp access_score(count, min_count) do
    min(count / min_count, 1.0)
  end
  ```
- [ ] 6.3.1.6 Implement `protected?/2`:
  ```elixir
  defp protected?(memory, config) do
    memory.memory_type in config.protected_types
  end
  ```
- [ ] 6.3.1.7 Implement `supersede_candidates/2`:
  ```elixir
  defp supersede_candidates(candidates, session_id) do
    results = Enum.map(candidates, fn mem ->
      Memory.supersede(session_id, mem.id, nil)
    end)
    {:ok, Enum.count(results, &(&1 == :ok))}
  end
  ```

### 6.3.2 Automatic Pruning Scheduler

- [ ] 6.3.2.1 Add pruning timer to Memory.Supervisor or Session.State:
  ```elixir
  @pruning_interval_ms 3_600_000  # 1 hour

  def handle_info(:run_pruning, state) do
    Task.start(fn ->
      Pruning.prune(state.session_id, state.pruning_config)
    end)
    schedule_pruning()
    {:noreply, state}
  end
  ```
- [ ] 6.3.2.2 Make pruning configurable per session
- [ ] 6.3.2.3 Add `enable_pruning/1` and `disable_pruning/1` functions
- [ ] 6.3.2.4 Run pruning on session close (final cleanup)

### 6.3.3 Unit Tests for Pruning

- [ ] Test prune/2 removes old memories beyond retention
- [ ] Test prune/2 removes low-confidence memories
- [ ] Test prune/2 removes unaccessed memories
- [ ] Test combined strategy calculates correct scores
- [ ] Test protected types are never pruned
- [ ] Test pruning uses supersession (not hard delete)
- [ ] Test pruning respects max_memories limit
- [ ] Test automatic pruning scheduler runs
- [ ] Test pruning telemetry emitted
- [ ] Test pruning handles empty memory store

---

## 6.4 Backup and Restore

Implement backup and restore functionality for long-term memory.

### 6.4.1 Backup Module

- [ ] 6.4.1.1 Create `lib/jido_code/memory/backup.ex` with moduledoc
- [ ] 6.4.1.2 Define backup format version:
  ```elixir
  @backup_version 1

  @type backup :: %{
    version: pos_integer(),
    exported_at: DateTime.t(),
    session_id: String.t(),
    memory_count: non_neg_integer(),
    memories: [serialized_memory()],
    metadata: map()
  }
  ```
- [ ] 6.4.1.3 Implement `export/2`:
  ```elixir
  @spec export(String.t(), keyword()) :: {:ok, backup()} | {:error, term()}
  def export(session_id, opts \\ []) do
    include_superseded = Keyword.get(opts, :include_superseded, false)

    query_opts = if include_superseded do
      [include_superseded: true]
    else
      []
    end

    with {:ok, memories} <- Memory.query(session_id, query_opts) do
      {:ok, %{
        version: @backup_version,
        exported_at: DateTime.utc_now(),
        session_id: session_id,
        memory_count: length(memories),
        memories: Enum.map(memories, &serialize_memory/1),
        metadata: build_metadata(session_id)
      }}
    end
  end
  ```
- [ ] 6.4.1.4 Implement `export_to_file/3`:
  ```elixir
  @spec export_to_file(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def export_to_file(session_id, path, opts \\ []) do
    with {:ok, backup} <- export(session_id, opts),
         json <- Jason.encode!(backup, pretty: true) do
      File.write(path, json)
    end
  end
  ```
- [ ] 6.4.1.5 Implement `serialize_memory/1`:
  ```elixir
  defp serialize_memory(memory) do
    %{
      id: memory.id,
      content: memory.content,
      memory_type: Atom.to_string(memory.memory_type),
      confidence: memory.confidence,
      source_type: Atom.to_string(memory.source_type),
      timestamp: DateTime.to_iso8601(memory.timestamp),
      rationale: memory.rationale,
      superseded_by: memory.superseded_by
    }
  end
  ```

### 6.4.2 Restore Module

- [ ] 6.4.2.1 Implement `import/3`:
  ```elixir
  @spec import(String.t(), backup(), keyword()) ::
    {:ok, non_neg_integer()} | {:error, term()}
  def import(session_id, backup, opts \\ []) do
    conflict_strategy = Keyword.get(opts, :conflict, :skip)

    with {:ok, validated} <- validate_backup(backup),
         {:ok, memories} <- deserialize_memories(validated.memories) do
      import_memories(memories, session_id, conflict_strategy)
    end
  end
  ```
- [ ] 6.4.2.2 Implement `import_from_file/3`:
  ```elixir
  @spec import_from_file(String.t(), String.t(), keyword()) ::
    {:ok, non_neg_integer()} | {:error, term()}
  def import_from_file(session_id, path, opts \\ []) do
    with {:ok, json} <- File.read(path),
         {:ok, backup} <- Jason.decode(json, keys: :atoms) do
      import(session_id, backup, opts)
    end
  end
  ```
- [ ] 6.4.2.3 Implement `validate_backup/1`:
  ```elixir
  defp validate_backup(backup) do
    cond do
      backup.version > @backup_version ->
        {:error, {:unsupported_version, backup.version}}
      not is_list(backup.memories) ->
        {:error, :invalid_format}
      true ->
        {:ok, backup}
    end
  end
  ```
- [ ] 6.4.2.4 Implement conflict resolution strategies:
  ```elixir
  defp import_memories(memories, session_id, :skip) do
    existing_ids = get_existing_ids(session_id)
    new_memories = Enum.reject(memories, &(&1.id in existing_ids))
    persist_memories(new_memories, session_id)
  end

  defp import_memories(memories, session_id, :overwrite) do
    Enum.each(memories, fn mem ->
      Memory.supersede(session_id, mem.id, nil)  # Remove old
      Memory.persist(mem, session_id)             # Add new
    end)
  end

  defp import_memories(memories, session_id, :merge) do
    # Import with new IDs to keep both
    Enum.each(memories, fn mem ->
      new_mem = %{mem | id: generate_id()}
      Memory.persist(new_mem, session_id)
    end)
  end
  ```

### 6.4.3 Unit Tests for Backup/Restore

- [ ] Test export/2 produces valid backup format
- [ ] Test export/2 includes all active memories
- [ ] Test export/2 optionally includes superseded
- [ ] Test export_to_file/3 writes valid JSON
- [ ] Test import/3 creates memories from backup
- [ ] Test import/3 validates backup version
- [ ] Test import/3 rejects unsupported version
- [ ] Test import with :skip strategy skips existing
- [ ] Test import with :overwrite strategy replaces existing
- [ ] Test import with :merge strategy creates duplicates with new ids
- [ ] Test round-trip export/import preserves all data
- [ ] Test import_from_file/3 reads and imports correctly

---

## 6.5 Telemetry and Monitoring

Implement comprehensive telemetry for memory operations.

### 6.5.1 Telemetry Events Module

- [ ] 6.5.1.1 Create `lib/jido_code/memory/telemetry.ex` with moduledoc
- [ ] 6.5.1.2 Define all telemetry events:
  ```elixir
  @events [
    # Memory operations
    [:jido_code, :memory, :remember, :start],
    [:jido_code, :memory, :remember, :stop],
    [:jido_code, :memory, :remember, :exception],
    [:jido_code, :memory, :recall, :start],
    [:jido_code, :memory, :recall, :stop],
    [:jido_code, :memory, :recall, :exception],
    [:jido_code, :memory, :forget, :start],
    [:jido_code, :memory, :forget, :stop],

    # Promotion
    [:jido_code, :memory, :promotion, :start],
    [:jido_code, :memory, :promotion, :stop],
    [:jido_code, :memory, :promotion, :triggered],

    # Pruning
    [:jido_code, :memory, :pruning, :start],
    [:jido_code, :memory, :pruning, :stop],

    # Context
    [:jido_code, :memory, :context, :assembled],
    [:jido_code, :memory, :context, :summarized],

    # Backup
    [:jido_code, :memory, :backup, :exported],
    [:jido_code, :memory, :backup, :imported],

    # Store
    [:jido_code, :memory, :store, :opened],
    [:jido_code, :memory, :store, :closed]
  ]
  ```
- [ ] 6.5.1.3 Implement event emission helpers:
  ```elixir
  def emit_remember(session_id, memory_type, duration_ms) do
    :telemetry.execute(
      [:jido_code, :memory, :remember, :stop],
      %{duration: duration_ms},
      %{session_id: session_id, memory_type: memory_type}
    )
  end

  def emit_recall(session_id, count, duration_ms) do
    :telemetry.execute(
      [:jido_code, :memory, :recall, :stop],
      %{duration: duration_ms, count: count},
      %{session_id: session_id}
    )
  end

  def emit_promotion(session_id, promoted_count) do
    :telemetry.execute(
      [:jido_code, :memory, :promotion, :stop],
      %{count: promoted_count},
      %{session_id: session_id}
    )
  end
  ```
- [ ] 6.5.1.4 Add telemetry calls to all memory handlers

### 6.5.2 Metrics Collection

- [ ] 6.5.2.1 Implement `get_stats/1`:
  ```elixir
  @spec get_stats(String.t()) :: {:ok, map()} | {:error, term()}
  def get_stats(session_id) do
    with {:ok, store} <- StoreManager.get(session_id) do
      {:ok, %{
        total_memories: count_memories(store, session_id),
        by_type: count_by_type(store, session_id),
        by_confidence: count_by_confidence_range(store, session_id),
        superseded_count: count_superseded(store, session_id),
        average_confidence: average_confidence(store, session_id),
        oldest_memory: oldest_timestamp(store, session_id),
        newest_memory: newest_timestamp(store, session_id),
        store_size_bytes: estimate_store_size(store)
      }}
    end
  end
  ```
- [ ] 6.5.2.2 Implement type distribution counting:
  ```elixir
  defp count_by_type(store, session_id) do
    types = [:fact, :assumption, :hypothesis, :discovery,
             :risk, :decision, :convention, :lesson_learned]

    Enum.reduce(types, %{}, fn type, acc ->
      {:ok, memories} = TripleStoreAdapter.query_by_type(store, session_id, type)
      Map.put(acc, type, length(memories))
    end)
  end
  ```
- [ ] 6.5.2.3 Implement confidence distribution:
  ```elixir
  defp count_by_confidence_range(store, session_id) do
    {:ok, all} = TripleStoreAdapter.query_all(store, session_id)

    %{
      high: Enum.count(all, &(&1.confidence >= 0.8)),
      medium: Enum.count(all, &(&1.confidence >= 0.5 and &1.confidence < 0.8)),
      low: Enum.count(all, &(&1.confidence < 0.5))
    }
  end
  ```
- [ ] 6.5.2.4 Add periodic stats emission for monitoring dashboards

### 6.5.3 Unit Tests for Telemetry

- [ ] Test telemetry events emitted for remember
- [ ] Test telemetry events emitted for recall
- [ ] Test telemetry events emitted for forget
- [ ] Test telemetry events emitted for promotion
- [ ] Test telemetry events emitted for pruning
- [ ] Test telemetry includes correct metadata
- [ ] Test telemetry includes duration measurements
- [ ] Test get_stats returns accurate counts
- [ ] Test get_stats returns type distribution
- [ ] Test get_stats returns confidence distribution

---

## 6.6 Phase 6 Integration Tests

Comprehensive integration tests for all advanced features.

### 6.6.1 Summarization Integration

- [ ] 6.6.1.1 Create `test/jido_code/integration/memory_advanced_test.exs`
- [ ] 6.6.1.2 Test: Long conversation triggers summarization
- [ ] 6.6.1.3 Test: Summary preserves key context (questions, decisions)
- [ ] 6.6.1.4 Test: Context assembly works with summarized conversation
- [ ] 6.6.1.5 Test: Summary caching prevents redundant computation

### 6.6.2 Semantic Search Integration

- [ ] 6.6.2.1 Test: Recall with query returns semantically relevant memories
- [ ] 6.6.2.2 Test: Semantic search ranks results by relevance
- [ ] 6.6.2.3 Test: Falls back to text search gracefully
- [ ] 6.6.2.4 Test: Embeddings cached for performance

### 6.6.3 Pruning Integration

- [ ] 6.6.3.1 Test: Automatic pruning removes old low-value memories
- [ ] 6.6.3.2 Test: Protected memory types preserved
- [ ] 6.6.3.3 Test: Pruning respects max_memories limit
- [ ] 6.6.3.4 Test: Pruning uses supersession for audit trail

### 6.6.4 Backup/Restore Integration

- [ ] 6.6.4.1 Test: Export and import round-trip preserves all data
- [ ] 6.6.4.2 Test: Import into new session works correctly
- [ ] 6.6.4.3 Test: Conflict resolution strategies work as expected
- [ ] 6.6.4.4 Test: Large backup files handled correctly

### 6.6.5 Full System Integration

- [ ] 6.6.5.1 Test: Complete workflow - remember, recall, forget, prune, backup
- [ ] 6.6.5.2 Test: Memory system works across session restart
- [ ] 6.6.5.3 Test: Telemetry captures all operations
- [ ] 6.6.5.4 Test: Stats accurately reflect memory state

---

## Phase 6 Success Criteria

1. **Summarization**: Conversation compressed when budget exceeded
2. **Semantic Search**: TF-IDF based similarity matching functional
3. **Pruning**: Automatic cleanup of low-value memories working
4. **Backup/Restore**: Memory export/import with conflict resolution
5. **Telemetry**: All operations emit monitoring events
6. **Stats**: Accurate memory statistics available
7. **Performance**: Advanced features don't significantly slow operations
8. **Test Coverage**: Minimum 80% for Phase 6 components

---

## Phase 6 Critical Files

**New Files:**
- `lib/jido_code/memory/summarizer.ex`
- `lib/jido_code/memory/embeddings.ex`
- `lib/jido_code/memory/pruning.ex`
- `lib/jido_code/memory/backup.ex`
- `lib/jido_code/memory/telemetry.ex`
- `test/jido_code/memory/summarizer_test.exs`
- `test/jido_code/memory/embeddings_test.exs`
- `test/jido_code/memory/pruning_test.exs`
- `test/jido_code/memory/backup_test.exs`
- `test/jido_code/memory/telemetry_test.exs`
- `test/jido_code/integration/memory_advanced_test.exs`

**Modified Files:**
- `lib/jido_code/memory/context_builder.ex` - Add summarization integration
- `lib/jido_code/memory/actions/recall.ex` - Add semantic search
- `lib/jido_code/memory/memory.ex` - Add stats function
- All memory modules - Add telemetry calls

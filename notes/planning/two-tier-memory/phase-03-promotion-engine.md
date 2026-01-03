# Phase 3: Promotion Engine

This phase implements the intelligence layer that evaluates short-term memories for promotion to long-term storage. The promotion engine uses multi-factor importance scoring and supports both automatic (implicit) and agent-directed (explicit) promotion.

## Promotion Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         Session.State (Short-Term)                        │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │   Working Context + Pending Memories + Access Log                   │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                              │                                            │
│                              ▼                                            │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │                    PROMOTION ENGINE                                 │  │
│  │  ┌──────────────────────────────────────────────────────────────┐  │  │
│  │  │                ImportanceScorer                               │  │  │
│  │  │   Recency (0.2) + Frequency (0.3) + Confidence (0.25) +      │  │  │
│  │  │   Type Salience (0.25) = Importance Score                     │  │  │
│  │  └──────────────────────────────────────────────────────────────┘  │  │
│  │                              │                                      │  │
│  │                              ▼                                      │  │
│  │  ┌──────────────────────────────────────────────────────────────┐  │  │
│  │  │                Promotion.Engine                               │  │  │
│  │  │   • evaluate(state) -> candidates                             │  │  │
│  │  │   • promote(candidates, session_id) -> persisted              │  │  │
│  │  │   • run(session_id) -> evaluate + promote + cleanup           │  │  │
│  │  └──────────────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                              │                                            │
│                              ▼ promotion                                  │
└──────────────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                         Long-Term Memory (Triple Store)                   │
│                    Persisted via TripleStoreAdapter                       │
└──────────────────────────────────────────────────────────────────────────┘
```

## Module Structure

```
lib/jido_code/memory/
├── promotion/
│   ├── engine.ex              # Evaluation and promotion logic
│   └── importance_scorer.ex   # Multi-factor scoring algorithm
```

---

## 3.1 Importance Scorer

Implement the multi-factor importance scoring algorithm that determines which memories are worth promoting to long-term storage.

### 3.1.1 ImportanceScorer Module

- [ ] 3.1.1.1 Create `lib/jido_code/memory/promotion/importance_scorer.ex` with comprehensive moduledoc
- [ ] 3.1.1.2 Define weight constants (configurable via module attribute):
  ```elixir
  @recency_weight 0.2
  @frequency_weight 0.3
  @confidence_weight 0.25
  @salience_weight 0.25

  @frequency_cap 10  # Accesses beyond this don't increase score
  ```
- [ ] 3.1.1.3 Define high salience memory types:
  ```elixir
  @high_salience_types [
    :decision, :architectural_decision, :convention,
    :coding_standard, :lesson_learned, :risk
  ]
  ```
- [ ] 3.1.1.4 Define `scorable_item()` type for input:
  ```elixir
  @type scorable_item :: %{
    last_accessed: DateTime.t(),
    access_count: non_neg_integer(),
    confidence: float(),
    suggested_type: memory_type() | nil
  }
  ```
- [ ] 3.1.1.5 Implement `score/1` main scoring function:
  ```elixir
  @spec score(scorable_item()) :: float()
  def score(item) do
    recency = recency_score(item.last_accessed)
    frequency = frequency_score(item.access_count)
    confidence = item.confidence
    salience = salience_score(item.suggested_type)

    (@recency_weight * recency) +
    (@frequency_weight * frequency) +
    (@confidence_weight * confidence) +
    (@salience_weight * salience)
  end
  ```
- [ ] 3.1.1.6 Implement `score_with_breakdown/1` for debugging:
  ```elixir
  @spec score_with_breakdown(scorable_item()) :: %{
    total: float(),
    recency: float(),
    frequency: float(),
    confidence: float(),
    salience: float()
  }
  ```
- [ ] 3.1.1.7 Implement private `recency_score/1`:
  ```elixir
  defp recency_score(last_accessed) do
    minutes_ago = DateTime.diff(DateTime.utc_now(), last_accessed, :minute)
    # Decay function: 1 / (1 + minutes_ago / 30)
    # Full score at 0 mins, ~0.5 at 30 mins, ~0.33 at 60 mins
    1 / (1 + minutes_ago / 30)
  end
  ```
- [ ] 3.1.1.8 Implement private `frequency_score/1`:
  ```elixir
  defp frequency_score(access_count) do
    # Normalize against cap, max 1.0
    min(access_count / @frequency_cap, 1.0)
  end
  ```
- [ ] 3.1.1.9 Implement private `salience_score/1`:
  ```elixir
  defp salience_score(nil), do: 0.3
  defp salience_score(type) when type in @high_salience_types, do: 1.0
  defp salience_score(:fact), do: 0.7
  defp salience_score(:discovery), do: 0.8
  defp salience_score(:hypothesis), do: 0.5
  defp salience_score(:assumption), do: 0.4
  defp salience_score(_), do: 0.3
  ```
- [ ] 3.1.1.10 Implement `configure/1` to override default weights:
  ```elixir
  @spec configure(keyword()) :: :ok
  def configure(opts)
  ```
  - Accept :recency_weight, :frequency_weight, :confidence_weight, :salience_weight
  - Store in application env or module attribute

### 3.1.2 Unit Tests for ImportanceScorer

- [ ] Test score/1 returns value between 0 and 1
- [ ] Test score/1 returns maximum (1.0) for ideal item (recent, frequent, high confidence, high salience)
- [ ] Test score/1 returns low value for old, unaccessed, low confidence item
- [ ] Test recency_score returns 1.0 for item accessed now
- [ ] Test recency_score returns ~0.5 for item accessed 30 minutes ago
- [ ] Test recency_score returns ~0.33 for item accessed 60 minutes ago
- [ ] Test recency_score decays correctly over hours
- [ ] Test frequency_score returns 0 for 0 accesses
- [ ] Test frequency_score returns 0.5 for 5 accesses (with cap 10)
- [ ] Test frequency_score caps at 1.0 for accesses >= cap
- [ ] Test salience_score returns 1.0 for :decision
- [ ] Test salience_score returns 1.0 for :lesson_learned
- [ ] Test salience_score returns 1.0 for :convention
- [ ] Test salience_score returns 0.8 for :discovery
- [ ] Test salience_score returns 0.7 for :fact
- [ ] Test salience_score returns 0.5 for :hypothesis
- [ ] Test salience_score returns 0.4 for :assumption
- [ ] Test salience_score returns 0.3 for nil
- [ ] Test salience_score returns 0.3 for unknown types
- [ ] Test score_with_breakdown returns all component scores
- [ ] Test score_with_breakdown components sum to total (within float precision)
- [ ] Test configure/1 changes weight values

---

## 3.2 Promotion Engine

Implement the core promotion logic that evaluates short-term memory and promotes worthy candidates to long-term storage.

### 3.2.1 Engine Module

- [ ] 3.2.1.1 Create `lib/jido_code/memory/promotion/engine.ex` with comprehensive moduledoc
- [ ] 3.2.1.2 Define promotion configuration:
  ```elixir
  @promotion_threshold 0.6
  @max_promotions_per_run 20
  ```
- [ ] 3.2.1.3 Define `promotion_candidate()` type:
  ```elixir
  @type promotion_candidate :: %{
    id: String.t() | nil,
    content: term(),
    suggested_type: memory_type(),
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
- [ ] 3.2.1.4 Implement `evaluate/1` to find promotion candidates:
  ```elixir
  @spec evaluate(Session.State.state()) :: [promotion_candidate()]
  def evaluate(state) do
    # Score context items and build candidates
    context_candidates = build_context_candidates(state.working_context, state.access_log)

    # Get pending items ready for promotion
    pending_ready = PendingMemories.ready_for_promotion(
      state.pending_memories,
      @promotion_threshold
    )

    # Combine and filter
    (context_candidates ++ pending_ready)
    |> Enum.filter(&promotable?/1)
    |> Enum.filter(&(&1.importance_score >= @promotion_threshold))
    |> Enum.sort_by(& &1.importance_score, :desc)
    |> Enum.take(@max_promotions_per_run)
  end
  ```
- [ ] 3.2.1.5 Implement `promote/3` to persist candidates:
  ```elixir
  @spec promote([promotion_candidate()], String.t(), keyword()) ::
    {:ok, non_neg_integer()} | {:error, term()}
  def promote(candidates, session_id, opts \\ []) do
    agent_id = Keyword.get(opts, :agent_id)
    project_id = Keyword.get(opts, :project_id)

    results = Enum.map(candidates, fn candidate ->
      memory_input = build_memory_input(candidate, session_id, agent_id, project_id)
      Memory.persist(memory_input, session_id)
    end)

    success_count = Enum.count(results, &match?({:ok, _}, &1))
    {:ok, success_count}
  end
  ```
- [ ] 3.2.1.6 Implement `run/2` convenience function combining all steps:
  ```elixir
  @spec run(String.t(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def run(session_id, opts \\ []) do
    with {:ok, state} <- Session.State.get_state(session_id) do
      candidates = evaluate(state)

      if candidates != [] do
        {:ok, count} = promote(candidates, session_id, opts)

        # Clear promoted items from pending
        promoted_ids = candidates
          |> Enum.map(& &1.id)
          |> Enum.reject(&is_nil/1)

        Session.State.clear_promoted_memories(session_id, promoted_ids)

        # Emit telemetry
        emit_promotion_telemetry(session_id, count)

        {:ok, count}
      else
        {:ok, 0}
      end
    end
  end
  ```
- [ ] 3.2.1.7 Implement private `build_context_candidates/2`:
  ```elixir
  defp build_context_candidates(working_context, access_log) do
    working_context
    |> WorkingContext.to_list()
    |> Enum.map(fn item ->
      access_stats = AccessLog.get_stats(access_log, item.key)
      build_candidate_from_context(item, access_stats)
    end)
    |> Enum.filter(&(&1.suggested_type != nil))  # Only promotable types
  end
  ```
- [ ] 3.2.1.8 Implement private `build_candidate_from_context/2`:
  - Convert context item to promotion_candidate
  - Calculate importance score using ImportanceScorer
  - Set suggested_by: :implicit
- [ ] 3.2.1.9 Implement private `build_memory_input/4`:
  - Convert candidate to memory_input format
  - Generate id if not present
  - Set created_at timestamp
  - Format content (handle non-string values)
- [ ] 3.2.1.10 Implement private `promotable?/1`:
  - Check suggested_type is not nil
  - Check content is not empty
- [ ] 3.2.1.11 Implement private `format_content/1`:
  ```elixir
  defp format_content(%{value: v}) when is_binary(v), do: v
  defp format_content(%{value: v, key: k}), do: "#{k}: #{inspect(v)}"
  defp format_content(%{content: c}) when is_binary(c), do: c
  defp format_content(item), do: inspect(item)
  ```
- [ ] 3.2.1.12 Implement private `generate_id/0`:
  ```elixir
  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
  ```
- [ ] 3.2.1.13 Implement private `emit_promotion_telemetry/2`

### 3.2.2 Unit Tests for Promotion Engine

- [ ] Test evaluate/1 returns empty list for empty state
- [ ] Test evaluate/1 scores context items correctly
- [ ] Test evaluate/1 includes items above threshold
- [ ] Test evaluate/1 excludes items below threshold
- [ ] Test evaluate/1 always includes agent_decisions (importance_score = 1.0)
- [ ] Test evaluate/1 excludes items with nil suggested_type
- [ ] Test evaluate/1 sorts by importance descending
- [ ] Test evaluate/1 limits to max_promotions_per_run
- [ ] Test promote/3 persists candidates to long-term store
- [ ] Test promote/3 returns count of successfully persisted items
- [ ] Test promote/3 includes agent_id in memory input
- [ ] Test promote/3 includes project_id in memory input
- [ ] Test promote/3 handles partial failures gracefully
- [ ] Test run/2 evaluates, promotes, and clears pending
- [ ] Test run/2 returns {:ok, 0} when no candidates
- [ ] Test run/2 clears promoted ids from pending_memories
- [ ] Test run/2 emits telemetry on promotion
- [ ] Test run/2 handles session not found error
- [ ] Test build_memory_input generates id when nil
- [ ] Test format_content handles string values
- [ ] Test format_content handles non-string values

---

## 3.3 Promotion Triggers

Implement trigger points for when promotion should run, including periodic timers and event-based hooks.

### 3.3.1 Periodic Promotion Timer

- [ ] 3.3.1.1 Add promotion configuration to Session.State:
  ```elixir
  @promotion_interval_ms 30_000  # 30 seconds
  @promotion_enabled true
  ```
- [ ] 3.3.1.2 Add promotion timer scheduling to `init/1`:
  ```elixir
  def init(%Session{} = session) do
    # ... existing init ...

    if @promotion_enabled do
      schedule_promotion()
    end

    {:ok, state}
  end
  ```
- [ ] 3.3.1.3 Implement private `schedule_promotion/0`:
  ```elixir
  defp schedule_promotion do
    Process.send_after(self(), :run_promotion, @promotion_interval_ms)
  end
  ```
- [ ] 3.3.1.4 Add `handle_info(:run_promotion, state)` callback:
  ```elixir
  def handle_info(:run_promotion, state) do
    # Run promotion in a task to avoid blocking GenServer
    Task.start(fn ->
      Promotion.Engine.run(state.session_id,
        agent_id: get_agent_id(state),
        project_id: get_project_id(state)
      )
    end)

    schedule_promotion()
    {:noreply, state}
  end
  ```
- [ ] 3.3.1.5 Make promotion interval configurable via session config
- [ ] 3.3.1.6 Add `enable_promotion/1` and `disable_promotion/1` client functions

### 3.3.2 Event-Based Promotion Triggers

- [ ] 3.3.2.1 Create `lib/jido_code/memory/promotion/triggers.ex` module
- [ ] 3.3.2.2 Add session pause trigger:
  - Implement `on_session_pause/1` callback
  - Call `Promotion.Engine.run/2` synchronously before pause completes
- [ ] 3.3.2.3 Add session close trigger:
  - Implement `on_session_close/1` callback
  - Run final promotion before session closes
  - Ensure all pending memories have chance to promote
- [ ] 3.3.2.4 Add memory limit trigger:
  - Implement `on_memory_limit_reached/2` callback
  - Trigger when pending_memories hits max_items
  - Run promotion to clear space
- [ ] 3.3.2.5 Add high-priority trigger for agent decisions:
  - Implement `on_agent_decision/2` callback
  - Immediate promotion for explicit remember requests
- [ ] 3.3.2.6 Integrate triggers with Session.State callbacks:
  ```elixir
  # In Session.State
  def handle_call(:pause, _from, state) do
    Triggers.on_session_pause(state.session_id)
    # ... existing pause logic ...
  end
  ```
- [ ] 3.3.2.7 Add telemetry events for all trigger activations:
  ```elixir
  :telemetry.execute(
    [:jido_code, :memory, :promotion, :triggered],
    %{trigger: :periodic},
    %{session_id: session_id}
  )
  ```

### 3.3.3 Unit Tests for Promotion Triggers

- [ ] Test periodic promotion timer schedules correctly on init
- [ ] Test :run_promotion message triggers promotion in background task
- [ ] Test promotion timer reschedules after each run
- [ ] Test disable_promotion/1 stops timer
- [ ] Test enable_promotion/1 restarts timer
- [ ] Test on_session_pause triggers synchronous promotion
- [ ] Test on_session_close triggers final promotion
- [ ] Test on_memory_limit_reached triggers promotion
- [ ] Test on_agent_decision triggers immediate promotion
- [ ] Test telemetry events emitted for each trigger type
- [ ] Test promotion doesn't run when disabled

---

## 3.4 Session.State Promotion Integration

Wire the promotion engine into Session.State callbacks and state management.

### 3.4.1 Promotion State Fields

- [ ] 3.4.1.1 Add promotion_stats to state struct:
  ```elixir
  promotion_stats: %{
    last_run: DateTime.t() | nil,
    total_promoted: non_neg_integer(),
    runs: non_neg_integer()
  }
  ```
- [ ] 3.4.1.2 Add promotion_enabled field to state:
  ```elixir
  promotion_enabled: boolean()
  ```
- [ ] 3.4.1.3 Initialize promotion fields in `init/1`:
  ```elixir
  promotion_stats: %{last_run: nil, total_promoted: 0, runs: 0},
  promotion_enabled: true
  ```

### 3.4.2 Promotion Client API

- [ ] 3.4.2.1 Add `run_promotion/1` client function:
  ```elixir
  @spec run_promotion(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def run_promotion(session_id) do
    Promotion.Engine.run(session_id)
  end
  ```
- [ ] 3.4.2.2 Add `get_promotion_stats/1` client function:
  ```elixir
  @spec get_promotion_stats(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_promotion_stats(session_id)
  ```
- [ ] 3.4.2.3 Add `update_promotion_stats/2` internal function:
  ```elixir
  @spec update_promotion_stats(String.t(), non_neg_integer()) :: :ok
  defp update_promotion_stats(session_id, promoted_count)
  ```
- [ ] 3.4.2.4 Add `set_promotion_enabled/2` client function:
  ```elixir
  @spec set_promotion_enabled(String.t(), boolean()) :: :ok | {:error, :not_found}
  def set_promotion_enabled(session_id, enabled)
  ```

### 3.4.3 Promotion GenServer Callbacks

- [ ] 3.4.3.1 Add `handle_call(:get_promotion_stats, ...)` callback:
  ```elixir
  def handle_call(:get_promotion_stats, _from, state) do
    {:reply, {:ok, state.promotion_stats}, state}
  end
  ```
- [ ] 3.4.3.2 Add `handle_cast({:update_promotion_stats, count}, ...)` callback:
  ```elixir
  def handle_cast({:update_promotion_stats, count}, state) do
    new_stats = %{
      state.promotion_stats |
      last_run: DateTime.utc_now(),
      total_promoted: state.promotion_stats.total_promoted + count,
      runs: state.promotion_stats.runs + 1
    }
    {:noreply, %{state | promotion_stats: new_stats}}
  end
  ```
- [ ] 3.4.3.3 Add `handle_call({:set_promotion_enabled, enabled}, ...)` callback
- [ ] 3.4.3.4 Update Engine.run/2 to call update_promotion_stats after promotion

### 3.4.4 Unit Tests for Promotion Integration

- [ ] Test promotion_stats initialize to zeros/nil
- [ ] Test run_promotion/1 invokes engine and updates stats
- [ ] Test get_promotion_stats/1 returns current stats
- [ ] Test promotion stats update correctly after each run
- [ ] Test total_promoted accumulates across runs
- [ ] Test last_run timestamp updates on each run
- [ ] Test runs counter increments on each run
- [ ] Test set_promotion_enabled/2 changes enabled state
- [ ] Test promotion timer respects enabled state

---

## 3.5 Phase 3 Integration Tests

Integration tests for complete promotion flow.

### 3.5.1 Promotion Flow Integration

- [ ] 3.5.1.1 Create `test/jido_code/integration/memory_phase3_test.exs`
- [ ] 3.5.1.2 Test: Full flow - add context items, trigger promotion, verify in long-term store
- [ ] 3.5.1.3 Test: Agent decisions promoted immediately with importance_score 1.0
- [ ] 3.5.1.4 Test: Low-importance items (below threshold) not promoted
- [ ] 3.5.1.5 Test: Items with nil suggested_type not promoted
- [ ] 3.5.1.6 Test: Promoted items cleared from pending_memories
- [ ] 3.5.1.7 Test: Promotion stats updated correctly after each run

### 3.5.2 Trigger Integration

- [ ] 3.5.2.1 Test: Periodic timer triggers promotion at correct interval
- [ ] 3.5.2.2 Test: Session pause triggers synchronous promotion
- [ ] 3.5.2.3 Test: Session close triggers final promotion
- [ ] 3.5.2.4 Test: Memory limit trigger clears space via promotion
- [ ] 3.5.2.5 Test: Agent decision trigger promotes immediately

### 3.5.3 Multi-Session Integration

- [ ] 3.5.3.1 Test: Promotion isolated per session - no cross-session contamination
- [ ] 3.5.3.2 Test: Concurrent promotions in multiple sessions
- [ ] 3.5.3.3 Test: Each session maintains independent promotion stats
- [ ] 3.5.3.4 Test: Store isolation maintained during concurrent promotions

### 3.5.4 Scoring Integration

- [ ] 3.5.4.1 Test: ImportanceScorer correctly ranks candidates
- [ ] 3.5.4.2 Test: Recency decay affects promotion order over time
- [ ] 3.5.4.3 Test: Frequently accessed items score higher
- [ ] 3.5.4.4 Test: High-salience types (decisions, lessons) prioritized

---

## Phase 3 Success Criteria

1. **ImportanceScorer**: Multi-factor scoring with configurable weights operational
2. **Promotion.Engine**: Evaluation and persistence of candidates working
3. **Periodic Trigger**: Timer-based promotion runs at configured interval
4. **Event Triggers**: Session pause/close and memory limit triggers functional
5. **Agent Decisions**: Explicit remember requests bypass threshold and promote immediately
6. **Stats Tracking**: Promotion statistics accurately tracked per session
7. **Integration**: Promotion correctly bridges short-term and long-term memory
8. **Test Coverage**: Minimum 80% for all Phase 3 modules

---

## Phase 3 Critical Files

**New Files:**
- `lib/jido_code/memory/promotion/importance_scorer.ex`
- `lib/jido_code/memory/promotion/engine.ex`
- `lib/jido_code/memory/promotion/triggers.ex`
- `test/jido_code/memory/promotion/importance_scorer_test.exs`
- `test/jido_code/memory/promotion/engine_test.exs`
- `test/jido_code/memory/promotion/triggers_test.exs`
- `test/jido_code/integration/memory_phase3_test.exs`

**Modified Files:**
- `lib/jido_code/session/state.ex` - Add promotion callbacks and state fields
- `lib/jido_code/memory/memory.ex` - Add promotion convenience functions
- `test/jido_code/session/state_test.exs` - Add promotion tests

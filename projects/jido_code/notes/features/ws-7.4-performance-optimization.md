# Feature: Task 7.4 - Performance Optimization

**Feature ID**: ws-7.4-performance-optimization
**Status**: Planning
**Dependencies**: 7.1 (Integration Tests), 7.2 (Edge Cases), 7.3 (Error Messages)

---

## Problem Statement

As the work-session feature supports multiple concurrent sessions with conversation history, reasoning steps, and persistence, we need to ensure the system performs efficiently under realistic load conditions. Key performance concerns include:

1. **Session Switching Latency**: Users expect instant feedback when switching between sessions (Ctrl+1-0)
2. **Memory Management**: Multiple sessions with large conversation histories could consume excessive memory
3. **Persistence Performance**: Save/load operations with large conversations could block the UI thread

Current implementation has some optimizations in place (message pagination in `Session.State`, reversed lists for O(1) prepend), but we need to profile actual performance, identify bottlenecks, and optimize critical paths.

---

## Solution Overview

This task will systematically profile, measure, and optimize the three critical performance dimensions:

1. **Session Switching**: Profile the session switch operation to ensure < 50ms latency
2. **Memory Management**: Measure memory footprint with 10 active sessions and prevent leaks
3. **Persistence**: Profile save/load operations to ensure < 100ms for typical sessions

We'll use Elixir's built-in profiling tools (`:timer.tc/1`, `:erlang.memory/0`, `:observer`) and potentially add `benchee` for detailed benchmarking. All optimizations will be validated with performance tests to prevent regression.

---

## Current Performance Analysis

### Existing Optimizations

The codebase already includes several performance optimizations:

1. **Message Storage** (`Session.State`):
   - Messages stored in reverse chronological order for O(1) prepend
   - Maximum limits enforced: 1000 messages, 100 reasoning steps, 500 tool calls
   - Pagination support (`get_messages/3`) to avoid O(n) reversal for large histories

2. **Registry Lookups**:
   - ETS-backed `SessionRegistry` with `read_concurrency: true` and `write_concurrency: true`
   - O(1) lookups via `SessionProcessRegistry` using Registry module
   - No linear scans for session switching

3. **Persistence**:
   - Atomic writes using temp file + rename
   - Per-session save locks to prevent concurrent saves
   - JSON encoding with `:strict` maps for deterministic output

4. **Rate Limiting** (`RateLimit`):
   - ETS-based sliding window rate limiting
   - Periodic cleanup to prevent unbounded memory growth

### Potential Bottlenecks

Based on code analysis, potential bottlenecks include:

1. **Session Switching** (`TUI.update/2`):
   - Currently switches by updating `active_session_id` in model (O(1))
   - May trigger re-rendering of entire conversation view
   - Unknown cost of TUI re-render cycle

2. **Memory Growth**:
   - Each session maintains full conversation history up to 1000 messages
   - With 10 sessions × 1000 messages × ~1KB per message ≈ 10MB just for messages
   - Reasoning steps and tool calls add additional overhead
   - Persisted sessions in `~/.jido_code/sessions/` could accumulate

3. **Persistence Operations** (`Session.Persistence`):
   - `save/1`: Fetches state, builds persisted map, encodes JSON, computes HMAC, writes file
   - `load/1`: Reads file, decodes JSON, verifies HMAC, deserializes, validates
   - Large conversations (1000 messages) could result in large JSON payloads
   - JSON encoding/decoding is O(n) in message count

4. **TUI Rendering**:
   - `ConversationView` renders all visible messages on every update
   - Unknown cost of rendering large conversation histories
   - Viewport calculations for scroll positions

---

## Performance Targets

Based on Phase 7.4 requirements:

| Operation | Target | Rationale |
|-----------|--------|-----------|
| Session Switch | < 50ms | Imperceptible to users (< 100ms feels instant) |
| Save Operation | < 100ms | Non-blocking UI update |
| Load/Resume | < 200ms | One-time operation, slightly more tolerance |
| Memory (10 sessions) | < 100MB total | Reasonable for a TUI application |
| Memory Stability | No leaks | Repeated create/close should not grow memory |

---

## Profiling Approach

### Tools

1. **`:timer.tc/1`**: Measure execution time of functions
   ```elixir
   {time_us, result} = :timer.tc(fn -> expensive_operation() end)
   IO.puts("Operation took #{time_us / 1000}ms")
   ```

2. **`:erlang.memory/0`**: Get memory usage breakdown
   ```elixir
   before = :erlang.memory()
   # ... perform operations ...
   after = :erlang.memory()
   diff = after[:total] - before[:total]
   IO.puts("Memory delta: #{div(diff, 1024)}KB")
   ```

3. **`:observer.start/0`**: Visual profiling and memory inspection
   - Process tree view
   - Memory allocator view
   - Table viewer for ETS tables

4. **`benchee` (optional)**: Detailed statistical benchmarking
   ```elixir
   Benchee.run(%{
     "session_switch" => fn -> switch_session(...) end
   }, time: 10, memory_time: 2)
   ```

### Profiling Scenarios

1. **Session Switching**:
   - Create 10 sessions with varying conversation sizes (0, 100, 500, 1000 messages)
   - Measure `Model.switch_session/2` execution time
   - Measure TUI re-render time after switch
   - Profile with `:observer` to identify hot functions

2. **Memory Management**:
   - Create 10 sessions, each with 1000 messages, 100 reasoning steps, 50 tool calls
   - Measure total memory footprint
   - Repeatedly create and close sessions (100 iterations)
   - Check for memory leaks using `:observer` and `:erlang.memory/0`
   - Profile ETS table sizes

3. **Persistence Performance**:
   - Create sessions with varying conversation sizes (10, 100, 500, 1000 messages)
   - Measure `Persistence.save/1` time for each size
   - Measure `Persistence.load/1` time for each size
   - Profile JSON encoding/decoding separately
   - Profile HMAC signature computation

---

## Optimization Strategies

### 7.4.1 Session Switching Optimization

**Goal**: < 50ms for session switch operation

**Current Flow**:
1. User presses Ctrl+N (N = 1-9, 0)
2. TUI receives `{:switch_to_session_index, N}` message
3. `Model.switch_session/2` updates `active_session_id`
4. TUI re-renders conversation view, status bar, tabs

**Optimization Strategies**:

1. **Lazy Loading Conversation History** (if needed):
   - Current: Full conversation loaded in `Session.State`
   - Optimization: Load only last N messages on switch, fetch more on scroll
   - Trade-off: More complex state management

2. **Cache Rendered Conversation** (if TUI rendering is slow):
   - Current: Re-render entire conversation on every update
   - Optimization: Cache rendered output, only re-render on content change
   - Trade-off: More complex cache invalidation logic

3. **Minimize State Copying**:
   - Current: Model contains session structs in map
   - Optimization: Ensure switch only updates pointer, not deep copy
   - Implementation: Already optimal (map update is O(1) with structural sharing)

4. **Defer Non-Critical Updates**:
   - Current: All UI components update on switch
   - Optimization: Update conversation first, defer reasoning panel, tool calls
   - Trade-off: Potential visual lag in side panels

**Implementation Priority**:
1. Measure current performance (establish baseline)
2. If > 50ms, profile with `:observer` to identify bottleneck
3. Optimize bottleneck (likely TUI rendering or conversation fetching)
4. Add performance test to prevent regression

### 7.4.2 Memory Management Optimization

**Goal**: Stable memory usage with 10 active sessions, no leaks

**Current State**:
- Max limits enforced: 1000 messages, 100 reasoning steps, 500 tool calls per session
- ETS tables: `SessionRegistry`, `SessionProcessRegistry`, `RateLimit` table
- Persisted sessions in `~/.jido_code/sessions/` directory

**Optimization Strategies**:

1. **Conversation History Limits** (already implemented):
   - Current: Hard limit of 1000 messages per session
   - Verification: Ensure `Enum.take(@max_messages)` is working correctly
   - Test: Create session with 2000 messages, verify only 1000 retained

2. **Resource Cleanup on Session Close**:
   - Current: `SessionSupervisor.stop_session/1` stops all processes
   - Verification: Ensure all GenServers release memory on terminate
   - Test: Repeated create/close cycles should not grow memory

3. **ETS Table Monitoring**:
   - Current: ETS tables have implicit cleanup
   - Optimization: Monitor table sizes in `:observer`
   - Verification: Ensure `SessionRegistry.unregister/1` removes entries

4. **Persisted Session Cleanup** (already implemented):
   - Current: `Persistence.cleanup/1` removes old session files
   - Optimization: Consider auto-cleanup on startup (configurable)
   - Trade-off: User data loss if not carefully configured

5. **Streaming Message Buffering**:
   - Current: `streaming_message` accumulates chunks in GenServer state
   - Verification: Ensure buffer is cleared after `end_streaming/1`
   - Risk: Long-running streams could accumulate large strings

**Implementation Priority**:
1. Measure baseline memory with 10 sessions (each with max data)
2. Perform 100 create/close cycles, check memory delta
3. If leak detected, use `:observer` to identify source
4. Add memory stability test

### 7.4.3 Persistence Performance Optimization

**Goal**: < 100ms for save operation, < 200ms for load operation

**Current Flow** (`save/1`):
1. Acquire save lock (ETS atomic operation)
2. `State.get_state/1` (GenServer call)
3. `build_persisted_session/1` (map construction, list traversal)
4. `Jason.encode/2` (JSON serialization)
5. `Crypto.compute_signature/1` (HMAC-SHA256)
6. `Jason.encode/2` again (with signature)
7. `File.write/2` (temp file)
8. `File.rename/2` (atomic replace)
9. Release save lock

**Current Flow** (`load/1`):
1. `File.stat/1` (check file size)
2. `File.read/1` (read file)
3. `Jason.decode/1` (JSON parse)
4. `Crypto.verify_signature/2` (HMAC verification + JSON re-encode)
5. `deserialize_session/1` (type conversions, DateTime parsing)
6. `validate_session/1` (schema validation)

**Optimization Strategies**:

1. **Incremental Saves** (if needed):
   - Current: Entire session saved on each `save/1` call
   - Optimization: Track dirty flag, only save changed conversations
   - Trade-off: More complex state tracking, potential consistency issues

2. **JSON Encoding Optimization**:
   - Current: Two JSON encodes per save (unsigned + signed)
   - Optimization: Single encode, manually insert signature in string
   - Trade-off: More complex, potential bugs in signature verification

3. **Parallel Encoding** (if large sessions):
   - Current: Single-threaded JSON encode
   - Optimization: Encode messages in parallel using `Task.async_stream/3`
   - Trade-off: More complex, only helps with very large sessions (> 1000 messages)

4. **Compression** (if file size is large):
   - Current: Plain JSON (human-readable)
   - Optimization: Gzip compression for large conversations
   - Trade-off: Loss of readability, compatibility issues

5. **Caching Persisted Format** (aggressive optimization):
   - Current: Rebuild persisted map on every save
   - Optimization: Cache serialized form, only rebuild on change
   - Trade-off: Complex cache invalidation

**Implementation Priority**:
1. Measure baseline save/load times for varying conversation sizes (10, 100, 500, 1000 messages)
2. Profile to identify bottleneck (likely JSON encoding or file I/O)
3. If > 100ms, optimize the slowest part first
4. Add performance tests with realistic data

---

## Implementation Plan

### Phase 1: Baseline Profiling (Task 7.4.1.1, 7.4.2.1, 7.4.3.1)

**Goal**: Establish current performance metrics

**Steps**:
1. Create profiling test module `test/jido_code/performance/` (not run by default)
2. Implement profiling scenarios for each dimension
3. Run profiling with current implementation
4. Document baseline metrics in this file

**Profiling Tests**:

```elixir
# test/jido_code/performance/session_switching_test.exs
defmodule JidoCode.Performance.SessionSwitchingTest do
  @moduletag :performance
  @moduletag timeout: :infinity

  describe "session switching latency" do
    test "switch between sessions with varying conversation sizes" do
      # Create 10 sessions with different message counts
      sessions = for i <- 1..10 do
        messages = create_messages(i * 100) # 100, 200, ..., 1000
        create_session_with_messages(messages)
      end

      # Measure switch time for each session
      results = for session <- sessions do
        {time_us, _} = :timer.tc(fn ->
          Model.switch_session(model, session.id)
        end)
        {session.id, time_us / 1000} # Convert to ms
      end

      # Report results
      for {session_id, time_ms} <- results do
        IO.puts("Switch to #{session_id}: #{time_ms}ms")
      end

      # Assert target
      max_time = Enum.max_by(results, fn {_, time} -> time end) |> elem(1)
      assert max_time < 50.0, "Max switch time #{max_time}ms exceeds 50ms target"
    end
  end
end

# test/jido_code/performance/memory_test.exs
defmodule JidoCode.Performance.MemoryTest do
  @moduletag :performance
  @moduletag timeout: :infinity

  describe "memory management" do
    test "memory footprint with 10 active sessions" do
      # Force garbage collection for clean baseline
      :erlang.garbage_collect()
      Process.sleep(100)

      before = :erlang.memory()

      # Create 10 sessions, each with max data
      sessions = for i <- 1..10 do
        session = create_session_with_data(
          messages: 1000,
          reasoning_steps: 100,
          tool_calls: 500
        )
        {i, session}
      end

      # Force GC and measure
      :erlang.garbage_collect()
      Process.sleep(100)
      after_create = :erlang.memory()

      # Calculate delta
      delta_kb = div(after_create[:total] - before[:total], 1024)
      delta_mb = div(delta_kb, 1024)

      IO.puts("Memory with 10 sessions: #{delta_mb}MB (#{delta_kb}KB)")
      IO.puts("  Processes: #{div(after_create[:processes] - before[:processes], 1024)}KB")
      IO.puts("  ETS: #{div(after_create[:ets] - before[:ets], 1024)}KB")

      # Assert target
      assert delta_mb < 100, "Memory usage #{delta_mb}MB exceeds 100MB target"
    end

    test "no memory leaks on repeated create/close" do
      # Baseline
      :erlang.garbage_collect()
      Process.sleep(100)
      before = :erlang.memory()

      # Perform 100 create/close cycles
      for i <- 1..100 do
        session = create_session_with_data(messages: 100)
        SessionSupervisor.stop_session(session.id)

        # GC every 10 iterations
        if rem(i, 10) == 0 do
          :erlang.garbage_collect()
          Process.sleep(10)
        end
      end

      # Final GC and measure
      :erlang.garbage_collect()
      Process.sleep(100)
      after_cycles = :erlang.memory()

      # Calculate delta (should be close to 0)
      delta_kb = div(after_cycles[:total] - before[:total], 1024)

      IO.puts("Memory delta after 100 cycles: #{delta_kb}KB")

      # Allow 1MB tolerance for normal runtime variation
      assert abs(delta_kb) < 1024, "Memory leak detected: #{delta_kb}KB delta"
    end
  end
end

# test/jido_code/performance/persistence_test.exs
defmodule JidoCode.Performance.PersistenceTest do
  @moduletag :performance
  @moduletag timeout: :infinity

  describe "persistence performance" do
    test "save operation with varying conversation sizes" do
      sizes = [10, 100, 500, 1000]

      results = for size <- sizes do
        session = create_session_with_data(messages: size)

        {time_us, {:ok, _path}} = :timer.tc(fn ->
          Persistence.save(session.id)
        end)

        {size, time_us / 1000} # Convert to ms
      end

      # Report results
      for {size, time_ms} <- results do
        IO.puts("Save #{size} messages: #{time_ms}ms")
      end

      # Assert target (largest conversation)
      {_, max_time} = Enum.max_by(results, fn {_, time} -> time end)
      assert max_time < 100.0, "Max save time #{max_time}ms exceeds 100ms target"
    end

    test "load operation with varying conversation sizes" do
      sizes = [10, 100, 500, 1000]

      # Pre-create saved sessions
      saved_ids = for size <- sizes do
        session = create_session_with_data(messages: size)
        {:ok, _} = Persistence.save(session.id)
        SessionSupervisor.stop_session(session.id)
        session.id
      end

      # Measure load times
      results = for {session_id, size} <- Enum.zip(saved_ids, sizes) do
        {time_us, {:ok, _session}} = :timer.tc(fn ->
          Persistence.load(session_id)
        end)

        {size, time_us / 1000} # Convert to ms
      end

      # Report results
      for {size, time_ms} <- results do
        IO.puts("Load #{size} messages: #{time_ms}ms")
      end

      # Assert target (largest conversation)
      {_, max_time} = Enum.max_by(results, fn {_, time} -> time end)
      assert max_time < 200.0, "Max load time #{max_time}ms exceeds 200ms target"
    end
  end
end
```

**Deliverables**:
- [ ] Performance test modules created
- [ ] Baseline metrics documented in this file
- [ ] Performance targets validated or adjusted based on reality

### Phase 2: Identify Bottlenecks (Task 7.4.1.2, 7.4.2.2, 7.4.3.2)

**Goal**: Profile critical paths and identify optimization opportunities

**Tools**:
1. `:observer.start()` - Visual profiling
2. `:timer.tc/1` - Measure specific operations
3. `:fprof` or `:eprof` - Function-level profiling (if needed)

**Steps**:
1. Run profiling tests with `:observer` attached
2. Identify hot functions in session switch path
3. Identify memory allocation patterns
4. Identify slow persistence operations (JSON vs file I/O vs HMAC)

**Deliverables**:
- [ ] Profiling report identifying bottlenecks
- [ ] Recommended optimizations prioritized by impact

### Phase 3: Implement Optimizations (Task 7.4.1.3-4, 7.4.2.3-4, 7.4.3.3-4)

**Goal**: Apply optimizations to meet performance targets

**Session Switching**:
- [ ] 7.4.1.3: Implement lazy conversation loading (if needed)
- [ ] 7.4.1.4: Add caching for frequently accessed session data (if needed)
- [ ] Validate improvements with profiling tests

**Memory Management**:
- [ ] 7.4.2.2: Verify conversation history limits are enforced
- [ ] 7.4.2.3: Audit resource cleanup in `terminate/2` callbacks
- [ ] 7.4.2.4: Fix any identified memory leaks
- [ ] Validate with memory stability test

**Persistence**:
- [ ] 7.4.3.3: Implement incremental saves (if needed)
- [ ] 7.4.3.4: Optimize JSON encoding (benchmark Jason alternatives if needed)
- [ ] Validate with persistence performance tests

**Deliverables**:
- [ ] Code changes for optimizations
- [ ] Updated baseline metrics showing improvements
- [ ] Documentation of optimization techniques used

### Phase 4: Performance Testing (Task 7.4.1.5, 7.4.2.5, 7.4.3.5)

**Goal**: Add regression tests to prevent performance degradation

**Test Strategy**:
1. Performance tests run as separate suite (not in CI by default)
2. Tests tagged with `@moduletag :performance`
3. Run locally before releases: `mix test --only performance`
4. Document expected performance ranges in test comments

**Performance Test Requirements**:
- [ ] Session switch test: 10 sessions, varying sizes, assert < 50ms
- [ ] Memory stability test: 100 create/close cycles, assert < 1MB delta
- [ ] Memory footprint test: 10 sessions with max data, assert < 100MB
- [ ] Save performance test: 1000 messages, assert < 100ms
- [ ] Load performance test: 1000 messages, assert < 200ms

**Deliverables**:
- [ ] Performance test suite in `test/jido_code/performance/`
- [ ] Documentation for running performance tests
- [ ] Baseline metrics documented in CLAUDE.md

---

## Success Criteria

### Performance Targets Met

- [ ] Session switch latency < 50ms (90th percentile)
- [ ] Save operation < 100ms for sessions with 1000 messages
- [ ] Load operation < 200ms for sessions with 1000 messages
- [ ] Memory footprint with 10 active sessions < 100MB
- [ ] No memory leaks (< 1MB delta after 100 create/close cycles)

### Testing

- [ ] Performance test suite created in `test/jido_code/performance/`
- [ ] All performance tests pass with realistic data
- [ ] Baseline metrics documented
- [ ] Performance targets validated on development hardware

### Code Quality

- [ ] All optimizations documented with comments
- [ ] No introduction of bugs (existing tests still pass)
- [ ] Credo and Dialyzer still clean
- [ ] Performance characteristics documented in module docs

### Documentation

- [ ] CLAUDE.md updated with performance characteristics
- [ ] Profiling methodology documented
- [ ] Performance testing guide created
- [ ] Known performance limitations documented

---

## Testing Strategy

### Performance Test Organization

```
test/jido_code/performance/
├── session_switching_test.exs    # Session switch latency
├── memory_test.exs                # Memory footprint and leaks
└── persistence_test.exs           # Save/load performance
```

### Test Execution

```bash
# Run all performance tests (not in CI)
mix test --only performance

# Run specific performance test
mix test test/jido_code/performance/session_switching_test.exs

# Run with profiling
iex -S mix test --only performance
:observer.start()
```

### Test Data Generation

Use existing test helpers with extensions:

```elixir
# test/support/performance_test_helpers.ex
defmodule JidoCode.Test.PerformanceTestHelpers do
  def create_session_with_data(opts \\ []) do
    message_count = Keyword.get(opts, :messages, 100)
    reasoning_count = Keyword.get(opts, :reasoning_steps, 10)
    tool_count = Keyword.get(opts, :tool_calls, 5)

    # Create session
    {:ok, session} = Session.new(project_path: tmp_dir())

    # Add messages
    for i <- 1..message_count do
      message = %{
        id: "msg-#{i}",
        role: if(rem(i, 2) == 0, do: :user, else: :assistant),
        content: generate_realistic_content(i),
        timestamp: DateTime.utc_now()
      }
      State.append_message(session.id, message)
    end

    # Add reasoning steps
    for i <- 1..reasoning_count do
      step = %{
        id: "reason-#{i}",
        content: "Reasoning step #{i}",
        timestamp: DateTime.utc_now()
      }
      State.add_reasoning_step(session.id, step)
    end

    # Add tool calls
    for i <- 1..tool_count do
      tool_call = %{
        id: "tc-#{i}",
        name: "read_file",
        arguments: %{path: "/tmp/file-#{i}.txt"},
        result: {:ok, "file contents #{i}"},
        status: :completed,
        timestamp: DateTime.utc_now()
      }
      State.add_tool_call(session.id, tool_call)
    end

    session
  end

  defp generate_realistic_content(index) do
    # Generate realistic message content (100-500 chars)
    base = "This is message #{index} with some realistic content. "
    String.duplicate(base, :rand.uniform(5))
  end
end
```

### Assertions and Tolerances

Performance tests should have reasonable tolerances:

```elixir
# Allow 10% variance for timing (flaky tests are worse than no tests)
assert time_ms < target_ms * 1.1

# Memory assertions should account for runtime variance
assert abs(delta_kb) < tolerance_kb

# Use statistical measures for repeated operations
times = for _ <- 1..100, do: measure_operation()
p90 = Enum.at(Enum.sort(times), 90)
assert p90 < target_ms
```

---

## Rollback Plan

If optimizations introduce bugs or complexity without sufficient gains:

1. **Revert Changes**: Git revert optimization commits
2. **Document Findings**: Update this document with "attempted optimizations"
3. **Adjust Targets**: If targets are unrealistic, document revised targets
4. **Partial Rollout**: Keep optimizations that work, revert problematic ones

---

## Notes and Observations

### Baseline Metrics

_(To be filled in after Phase 1 profiling)_

**Session Switching**:
- Empty session: ___ ms
- 100 messages: ___ ms
- 500 messages: ___ ms
- 1000 messages: ___ ms

**Memory**:
- Single session (1000 messages): ___ MB
- 10 sessions (1000 messages each): ___ MB
- 100 create/close cycles delta: ___ KB

**Persistence**:
- Save 100 messages: ___ ms
- Save 1000 messages: ___ ms
- Load 100 messages: ___ ms
- Load 1000 messages: ___ ms

### Bottleneck Analysis

_(To be filled in after Phase 2 profiling)_

**Session Switching Bottleneck**: ___
**Memory Growth Source**: ___
**Persistence Bottleneck**: ___

### Optimization Results

_(To be filled in after Phase 3 implementation)_

**Applied Optimizations**:
- [ ] ___: Before ___ ms → After ___ ms
- [ ] ___: Before ___ MB → After ___ MB

---

## Related Files

**Core Modules**:
- `/home/ducky/code/jido_code/lib/jido_code/session_registry.ex` - Session lookup (ETS)
- `/home/ducky/code/jido_code/lib/jido_code/session/state.ex` - Message storage and pagination
- `/home/ducky/code/jido_code/lib/jido_code/session/persistence.ex` - Save/load operations
- `/home/ducky/code/jido_code/lib/jido_code/tui.ex` - Session switching and rendering

**Test Files**:
- `/home/ducky/code/jido_code/test/jido_code/session/state_pagination_test.exs` - Pagination performance example
- `/home/ducky/code/jido_code/test/jido_code/performance/` - New performance test suite (to be created)

**Configuration**:
- `/home/ducky/code/jido_code/config/runtime.exs` - Performance tuning configs

---

## References

- [Elixir Profiling Guide](https://hexdocs.pm/elixir/1.12/profiling.html)
- [Benchee Documentation](https://hexdocs.pm/benchee/Benchee.html)
- [Erlang Observer Guide](https://www.erlang.org/doc/apps/observer/observer_ug.html)
- [ETS Performance](https://www.erlang.org/doc/efficiency_guide/tablesDatabases.html)

---

**Next Steps**:
1. Create performance test suite structure
2. Run baseline profiling tests
3. Document baseline metrics in this file
4. Analyze results and identify bottlenecks
5. Implement targeted optimizations
6. Validate improvements with tests

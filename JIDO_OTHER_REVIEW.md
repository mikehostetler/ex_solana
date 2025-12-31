# Jido Code Review: Supporting Modules

**Review Date:** December 31, 2025  
**Scope:** All Jido modules EXCEPT `Jido.Agent`, `Jido.AI.*`, and `Jido.AgentServer`  
**Reviewer:** Code Review via Oracle Analysis

---

## Executive Summary

The Jido codebase is in **very good shape overall**. The architecture is clear, the API is mostly consistent and idiomatic Elixir, and the separation between pure agent logic, directives, and internal effects is strong.

### Key Findings

| Severity | Count | Description |
|----------|-------|-------------|
| 🔴 Critical | 1 | Atom leak vulnerability in Strategy param normalization |
| 🟠 High | 4 | Bugs/mismatches in MultiAgent, Discovery, FSM behavior |
| 🟡 Medium | 8 | Performance, type safety, API consistency issues |
| 🟢 Low | 12 | Documentation, minor style, optional improvements |

---

## 🔴 Critical Issues

### 1. Atom Creation from User Params (Security/Robustness)

**File:** [lib/jido/agent/strategy.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/agent/strategy.ex#L364-L385)

**Issue:** `safe_to_atom/1` falls back to `String.to_atom/1`, which can create unbounded atoms from user-supplied keys – an eventual VM-killer in long-running systems.

```elixir
defp safe_to_atom(str) when is_binary(str) do
  try do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> String.to_atom(str)   # <- UNSAFE: creates new atoms
  end
end
```

**Risk:** Malicious or unexpectedly large input can exhaust the atom table (limited to ~1M atoms), crashing the BEAM VM.

**Recommendation:**
```elixir
defp safe_to_atom(str) when is_binary(str) do
  try do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> str   # Keep as string instead of creating atom
  end
end
```

Then either:
1. Handle mixed atom/string keys downstream, or
2. Normalize keys against known schemas only

**Priority:** Fix immediately before any production use.

---

## 🟠 High Priority Issues

### 2. FSM Strategy Never Reaches Terminal States

**File:** [lib/jido/agent/strategy/fsm.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/agent/strategy/fsm.ex#L71-L230)

**Issue:** Documentation describes states `"idle"`, `"processing"`, `"completed"`, `"failed"` and `snapshot/2` maps these to `:success`/`:failure`. However, the implementation **never** transitions to `"completed"` or `"failed"` states.

- Lines 71-76: Default transitions include `"completed"` and `"failed"`
- Lines 122-175: `cmd/3` only transitions to `"processing"` and back to `initial_state`
- Lines 209-223: `snapshot/2` expects these states but they're never set
- Result: `done?` is always `false`, status never becomes `:success`/`:failure`

**Recommendation:** Add transitions on success/failure:

```elixir
# After successful instruction batch
machine =
  case Machine.transition(machine, "completed") do
    {:ok, m} -> m
    {:error, _} -> machine
  end

# On any error in run_instruction/3
machine =
  case Machine.transition(machine, "failed") do
    {:ok, m} -> m  
    {:error, _} -> machine
  end
```

---

### 3. Incomplete Pattern Match in MultiAgent

**File:** [lib/jido/multi_agent.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/multi_agent.ex#L151-L164)

**Issue:** `wait_for_child_pid/4` will raise `FunctionClauseError` if `children[child_tag]` exists but is not a map with `:pid` key.

```elixir
case Map.get(children, child_tag) do
  %{pid: child_pid} when is_pid(child_pid) ->
    {:ok, child_pid}

  nil ->
    Process.sleep(poll_interval)
    wait_for_child_pid(...)
  # Missing: catch-all for unexpected shapes
end
```

**Recommendation:** Add catch-all clause:

```elixir
_other ->
  # Treat unexpected shape as "not yet available"
  Process.sleep(poll_interval)
  wait_for_child_pid(parent_server, child_tag, deadline, poll_interval)
```

---

### 4. MultiAgent Docs Promise Unimplemented Error

**File:** [lib/jido/multi_agent.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/multi_agent.ex#L123-L127)

**Issue:** Documentation for `await_child_completion/4` promises `{:error, :child_not_found}` but implementation only returns `{:error, :timeout}` or `{:error, reason}` from `AgentServer.state/1`.

**Recommendation:** Either implement `:child_not_found` detection or update docs to remove it.

---

### 5. Redundant persistent_term Call in Discovery

**File:** [lib/jido/discovery.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/discovery.ex#L218-L223)

**Issue:** First `:persistent_term.get/1` result is discarded:

```elixir
defp get_catalog do
  :persistent_term.get(@catalog_key)           # <- Result discarded
  {:ok, :persistent_term.get(@catalog_key)}    # <- Called again
rescue
  ArgumentError -> {:error, :not_initialized}
end
```

**Recommendation:**
```elixir
defp get_catalog do
  {:ok, :persistent_term.get(@catalog_key)}
rescue
  ArgumentError -> {:error, :not_initialized}
end
```

---

## 🟡 Medium Priority Issues

### 6. O(n²) List Building in Strategies and Effects

**Files:**
- [lib/jido/agent/strategy/direct.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/agent/strategy/direct.ex#L24-L27) - `acc_directives ++ new_directives`
- [lib/jido/agent/strategy/fsm.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/agent/strategy/fsm.ex#L178-L185) - `acc_directives ++ new_directives`
- [lib/jido/agent/effects.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/agent/effects.ex#L63-L65) - `directives ++ [directive]`

**Issue:** Using `++` in a fold creates O(n²) complexity for large directive lists.

**Recommendation:** Accumulate in reverse and `Enum.reverse/1` once:

```elixir
# In Effects.apply_effects/2
%_{} = directive, {a, directives} ->
  {a, [directive | directives]}  # Prepend instead of append
```

Then reverse at the end of the reduction.

---

### 7. Supervisor Spec Return Type Mismatch

**File:** [lib/jido/supervisor.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/supervisor.ex#L70-L73)

**Issue:** Spec claims `:ok | {:error, :not_found}` but `DynamicSupervisor.terminate_child/2` returns `:ok | {:error, term()}`.

```elixir
@spec stop_agent(String.t() | pid()) :: :ok | {:error, :not_found}
def stop_agent(pid) when is_pid(pid) do
  DynamicSupervisor.terminate_child(Jido.AgentSupervisor, pid)
end
```

**Recommendation:** Broaden spec or normalize errors:
```elixir
@spec stop_agent(String.t() | pid()) :: :ok | {:error, term()}
```

---

### 8. Effects.deep_put_in/3 Crashes on Non-Map Intermediate Values

**File:** [lib/jido/agent/effects.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/agent/effects.ex#L71-L79)

**Issue:** If `map[key]` exists and is not a map (e.g., integer), `deep_put_in/3` will crash.

**Recommendation:**
```elixir
def deep_put_in(map, [key | rest], value) do
  nested =
    case Map.get(map, key, %{}) do
      v when is_map(v) -> v
      _ -> %{}  # Overwrite non-map with new map
    end

  Map.put(map, key, deep_put_in(nested, rest, value))
end
```

---

### 9. Unused Metrics List in Telemetry.init/1

**File:** [lib/jido/telemetry.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/telemetry.ex#L86-L179)

**Issue:** A list of `Telemetry.Metrics.*` is constructed but never returned or registered - dead code.

**Recommendation:** Either:
1. Expose a `metrics/0` function for use by reporters, or
2. Move to docs/comments if just for reference

---

### 10. Potential PII Leakage in Telemetry Logs

**File:** [lib/jido/telemetry.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/telemetry.ex#L235-L416)

**Issue:** Error metadata is logged with `inspect(metadata[:error])` without redaction. Errors can contain user prompts, payloads, or sensitive data.

**Locations:** Lines 235-243, 267-272, 300-305, 338-343, 371-377

**Recommendation:** Use `Jido.Observe.redact/2`:
```elixir
Logger.warning("[Agent] Command failed",
  agent_id: metadata[:agent_id],
  agent_module: metadata[:agent_module],
  duration_μs: duration,
  error: Jido.Observe.redact(inspect(metadata[:error]))
)
```

---

### 11. Discovery Unsupervised Init Task

**File:** [lib/jido/application.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/application.ex#L25)

**Issue:** `Jido.Discovery.init/0` runs in an unsupervised task. If it crashes, no retries occur.

```elixir
Task.start(fn -> Jido.Discovery.init() end)
```

**Recommendation:** For production reliability:
```elixir
Task.Supervisor.start_child(Jido.TaskSupervisor, fn -> Jido.Discovery.init() end)
```
Or add to supervision tree with restart logic.

---

### 12. Silent Exception Swallowing in Application

**File:** [lib/jido/application.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/application.ex#L43-L47)

**Issue:** All exceptions in `register_signal_extensions/0` are silently swallowed, making misconfiguration hard to detect.

**Recommendation:**
```elixir
rescue
  e ->
    Logger.warning("Failed to register signal extensions: #{inspect(e)}")
    :ok
end
```

---

### 13. Duration Unit Mismatch in Telemetry Logs

**File:** [lib/jido/telemetry.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/telemetry.ex)

**Issue:** Duration is in `:native` units but logged as `duration_μs` without conversion.

**Recommendation:** Either convert:
```elixir
duration_us = System.convert_time_unit(duration, :native, :microsecond)
```
Or rename fields to `duration_native`.

---

## 🟢 Low Priority Issues

### 14. Docstring Example References Wrong Module

**File:** [lib/jido/util.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/util.ex#L56-L61)

**Issue:** Docs reference `Jido.Action.validate_name/1` but function lives in `Jido.Util`.

**Recommendation:** Update examples to `Jido.Util.validate_name/1`.

---

### 15. Dual Return Styles for validate_name/2

**File:** [lib/jido/util.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/util.ex#L65-L92)

**Issue:** `validate_name(name, [])` returns `{:ok, name}` via OK macro, while `validate_name(name, opts)` returns `:ok`.

**Recommendation:** Add docstring explanation of the two modes, or consolidate to one style.

---

### 16. Discovery Slug Lookup is O(n)

**File:** [lib/jido/discovery.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/discovery.ex#L206-L215)

**Issue:** `get_by_slug/2` uses `Enum.find/2` for every lookup.

**Recommendation (optional):** Build a `slug_index` map in `build_catalog/0` for O(1) lookups if catalog size becomes large.

---

### 17. Schema Key Collision Not Detected

**File:** [lib/jido/agent/schema.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/agent/schema.ex#L29-L47)

**Issue:** If a skill uses `state_key: :status` and agent base schema already has `:status`, one silently overwrites the other.

**Recommendation:** Add collision detection:
```elixir
base_keys = known_keys(base_schema)
skill_keys = Map.keys(skill_fields)
collisions = base_keys -- (base_keys -- skill_keys)

if collisions != [] do
  raise ArgumentError,
    "Skill state_key(s) #{inspect(collisions)} clash with agent base schema keys"
end
```

---

### 18. new/4 Ignores Stacktrace Parameter

**File:** [lib/jido/error.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/error.ex#L513-L575)

**Issue:** The `new/4` function accepts a `stacktrace` argument but never uses it.

**Recommendation:** Either capture it into error `details` or document it's for backwards compatibility only.

---

### 19. Configuration Lookups on Every Call

**File:** [lib/jido/observe.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/observe.ex#L380-L387)

**Issue:** `observability_config/0` calls `Application.get_env/3` every time (used in `tracer/0`, `debug_enabled?/0`, `redact/2`).

**Recommendation:** For hot paths, consider caching in `persistent_term` with a refresh mechanism.

---

### 20. string_to_binary!/1 is Identity Function

**File:** [lib/jido/util.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/util.ex#L35-L38)

**Issue:** Function just returns the input unchanged.

**Recommendation:** Document if it's compatibility glue, or remove if unused.

---

### 21. Skill Schema Types Are `Zoi.any()`

**File:** [lib/jido/skill.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/skill.ex#L77-L81)

**Issue:** `schema` and `config_schema` options are typed as `Zoi.any()` which doesn't enforce they're valid Zoi schemas.

**Recommendation:** Document explicitly in `@moduledoc` that these must be valid Zoi schemas or `nil`.

---

### 22. SpanCtx.new/1 Error Documentation

**File:** [lib/jido/observe/span_ctx.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/observe/span_ctx.ex#L33-L38)

**Issue:** Error uses `Jido.Error.validation_error/1` but callers may not know it returns a Splode-based error struct.

**Recommendation:** Document the error type in the docstring.

---

### 23. Internal Effects Docs Reference put_in/3

**File:** [lib/jido/agent/internal.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/agent/internal.ex#L127-L137)

**Issue:** `SetPath` docs say "Uses `put_in/3` semantics" but actual behavior is via `Effects.deep_put_in/3`.

**Recommendation:** After fixing `deep_put_in/3` to be more forgiving, update docs to reflect actual semantics.

---

### 24. Scheduler Module Documentation

**File:** [lib/jido/scheduler.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido/scheduler.ex)

**Issue:** Docs reference `:jido_quantum` name but it's not explicitly shown how this integrates.

**Recommendation:** Add explicit example of scheduler name usage.

---

### 25. Top-Level Jido Module Could Link to More Resources

**File:** [lib/jido.ex](file:///Users/mhostetler/Source/Jido/jido/lib/jido.ex)

**Recommendation:** Add pointers to:
- `Jido.Supervisor` for process-level control
- `Jido.MultiAgent` for synchronous waiting patterns

---

## Architecture Observations

### Strengths

1. **Clean Separation of Concerns**
   - Pure agent logic vs directives vs internal effects is well-defined
   - Elm/Redux-inspired pattern is consistently applied

2. **Strong Type Safety**
   - Zoi schemas provide compile-time validation
   - Splode-based error system enables cross-package error handling

3. **Good Extension Points**
   - Tracer behaviour allows OpenTelemetry integration
   - Custom directives can be defined by external packages
   - Strategy pattern enables pluggable execution

4. **Defensive Coding**
   - Signal extension registration gracefully handles missing modules
   - Discovery initialization is async to not block startup

### Areas for Future Enhancement

1. **Performance at Scale**
   - Discovery indexing for large component catalogs
   - Configurable caching for hot config paths

2. **Observability**
   - Extract metrics list to dedicated module
   - Consider `jido_otel` package for OpenTelemetry

3. **Error Rendering**
   - Unified "error view" module for consistent logging/redaction

---

## Recommended Fix Priority

### Immediate (Before Production)
1. ✅ Fix atom leak in Strategy param normalization

### High Priority (Next Sprint)
2. Fix FSM terminal states behavior
3. Fix MultiAgent pattern match and docs
4. Fix Discovery redundant call

### Medium Priority (Technical Debt)
5. Fix O(n²) list building
6. Add PII redaction to telemetry
7. Supervise Discovery init
8. Fix spec mismatches

### Low Priority (Polish)
9. Documentation updates
10. Optional performance improvements
11. Style consistency fixes

---

## Testing Recommendations

1. **Add test for atom table exhaustion** - Verify unknown string keys don't create atoms
2. **FSM state transition tests** - Verify `"completed"`/`"failed"` states are reachable
3. **MultiAgent edge case tests** - Test with malformed children maps
4. **Effects boundary tests** - Test `deep_put_in` with non-map intermediate values
5. **Redaction tests** - Verify sensitive data is redacted in production config

---

*Review completed. All issues tracked with file paths and line numbers for easy reference.*

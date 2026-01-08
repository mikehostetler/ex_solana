# Research Report: Convert to Zoi Error Handling for jido_htn

## Overview

The jido_htn project currently uses a mixed approach to error handling:
1. **Zoi.parse()** for struct validation (returns `{:ok, struct}` | `{:error, Zoi.Error.t()}`)
2. **String-based error tuples** (`{:error, "reason string"}`) for business logic errors
3. **ArgumentError exceptions** via `raise` for immediate failures
4. **Custom error tuples** with debug trees for planning failures

This research identifies all error-producing paths and provides a roadmap for migrating to Zoi-compatible error handling following the patterns established in `jido` and `jido_action`.

---

## 1. Files in jido_htn that handle errors

### Core Planning Files (10 files)

| File | Line Count | Error Patterns |
|------|------------|----------------|
| `projects/jido_htn/lib/jido_htn/planner.ex` | 232 | String tuples, timeout errors |
| `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex` | 283 | String tuples, debug trees |
| `projects/jido_htn/lib/jido_htn/planner/condition_evaluator.ex` | 49 | Boolean returns (no errors) |
| `projects/jido_htn/lib/jido_htn/planner/effect_handler.ex` | 47 | No error returns |
| `projects/jido_htn/lib/jido_htn/planner/method_traversal_record.ex` | 67 | Zoi.parse + raise |

### Domain Files (7 files)

| File | Line Count | Error Patterns |
|------|------------|----------------|
| `projects/jido_htn/lib/jido_htn/domain.ex` | 66 | Zoi struct definition |
| `projects/jido_htn/lib/jido_htn/domain/domain_builder.ex` | ~320 | String errors, raise ArgumentError |
| `projects/jido_htn/lib/jido_htn/domain/domain_validation.ex` | ~550 | String error lists |
| `projects/jido_htn/lib/jido_htn/domain/domain_reader.ex` | ~60 | String tuples |
| `projects/jido_htn/lib/jido_htn/domain/helpers.ex` | ~50 | String tuples |
| `projects/jido_htn/lib/jido_htn/domain/builder/validator.ex` | ~50 | Callback interface |

### Struct Files (4 files)

| File | Line Count | Error Patterns |
|------|------------|----------------|
| `projects/jido_htn/lib/jido_htn/method.ex` | 143 | Zoi.parse + raise |
| `projects/jido_htn/lib/jido_htn/compound_task.ex` | 56 | Zoi.parse + raise |
| `projects/jido_htn/lib/jido_htn/primitive_task.ex` | 142 | Zoi.parse + raise + string error |
| `projects/jido_htn/lib/jido_htn/serializer.ex` | ~220 | String tuples, rescue ArgumentError |

### Behavior Files (1 file)

| File | Line Count | Error Patterns |
|------|------------|----------------|
| `projects/jido_htn/lib/jido_htn/behaviour.ex` | 13 | Callback specs |

---

## 2. Current Error Types/Patterns Used

### Pattern 1: Zoi.parse() (Already Zoi-compatible)

**Used in:** All struct constructors

**Returns:** `{:ok, struct}` | `{:error, Zoi.Error.t()}`

**Example from `projects/jido_htn/lib/jido_htn/method.ex:51-55`:**

```elixir
@spec new(keyword()) :: {:ok, t()} | {:error, term()}
def new(opts \\ []) do
  attrs = Map.new(opts)
  Zoi.parse(@schema, attrs)
end
```

**Status:** No changes needed - already Zoi-compatible

---

### Pattern 2: String-based error tuples (NEEDS MIGRATION)

**Used in:** 118 occurrences across 15 files

**Returns:** `{:error, "reason string"}` or `{:error, "reason", debug_tree}`

**Example from `projects/jido_htn/lib/jido_htn/planner.ex:47-51`:**

```elixir
{:exit, reason} ->
  dbug("Planning failed: #{inspect(reason)}")
  {:error, "Planning failed: #{inspect(reason)}"}

nil ->
  dbug("Planning timed out after #{timeout}ms")
  {:error, "Planning timed out after #{timeout}ms"}
```

**Example from `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex:55`:**

```elixir
nil ->
  {:error, "Unknown task: #{inspect(task_name)}", {:empty, task_name, false, []}}
```

**Status:** NEEDS MIGRATION - Should return Zoi.Error or Splode.Error

---

### Pattern 3: ArgumentError exceptions via raise (NEEDS MIGRATION)

**Used in:** 19 occurrences across 7 files

**Raises:** `ArgumentError` exception

**Example from `projects/jido_htn/lib/jido_htn/method.ex:61`:**

```elixir
def new!(opts \\ []) do
  case new(opts) do
    {:ok, method} -> method
    {:error, reason} -> raise ArgumentError, "Invalid Method: #{inspect(reason)}"
  end
end
```

**Status:** NEEDS MIGRATION - Should use `Jido.Error` from jido

---

## 3. Reference Zoi Error Patterns from Other Jido Projects

### From `jido/lib/jido/error.ex`:

The jido project uses **Splode** for unified error handling with error classes:

```elixir
# Error classes (in order of precedence):
:invalid     # Input validation, bad requests, invalid configurations
:execution   # Runtime execution errors and action failures
:planning    # Action planning and workflow errors
:routing     # Agent routing and dispatch errors
:timeout     # Action and process timeouts
:internal    # Unexpected internal errors and system failures
```

**Usage pattern:**

```elixir
# Create a specific error
{:error, error} = Jido.Error.validation_error("Invalid parameters", field: :user_id)
{:error, timeout} = Jido.Error.timeout_error("Action timed out after 30s", timeout: 30000)
{:error, planning} = Jido.Error.planning_error("No valid method found", task: "do_work")
```

---

## 4. Error-Producing Paths in jido_htn

### A. Failed Preconditions

**Location:** `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex:60-94`

**Current pattern:**

```elixir
defp decompose_primitive(domain, task, world_state, current_plan, mtr) do
  {conditions_met, condition_results} =
    ConditionEvaluator.preconditions_met?(domain, task.preconditions, world_state)

  if conditions_met do
    # ... success path
  else
    {:error, "Precondition not met for #{inspect(task.name)}",
     {:primitive, task.name, false, condition_results}}
  end
end
```

**Should become:**

```elixir
Jido.Error.planning_error(
  "Precondition not met",
  task: task.name,
  condition_results: condition_results
)
```

---

### B. Method Selection Failures

**Location:** `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex:96-175`

**Current pattern:**

```elixir
|> Enum.reduce_while({{:error, "No valid method found"}, []}, fn {method, index}, {_, acc_trees} ->
  # ...
  {:cont, {{:error, "Path pruned due to lower priority"}, ...}}
  {:cont, {{:error, "Method failed"}, ...}}
end)
```

**Should become:**

```elixir
Jido.Error.planning_error("No valid method found", task: task.name, attempted: method_count)
```

---

### C. Dead-ends / Task Not Found

**Location:** `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex:54-56`

**Current pattern:**

```elixir
nil ->
  {:error, "Unknown task: #{inspect(task_name)}", {:empty, task_name, false, []}}
```

---

### D. Timeout Errors

**Location:** `projects/jido_htn/lib/jido_htn/planner.ex`

**Current pattern:**

```elixir
{:error, "Planning timed out after #{timeout}ms"}
```

**Should use:**

```elixir
Jido.Error.timeout_error("Planning timed out", timeout: timeout)
```

---

## 5. Key Integration Points to Consider

### 1. Debug Tree Preservation

**Challenge:** Current error format includes debug trees:

```elixir
{:error, "Precondition not met", {:primitive, "task_name", false, condition_results}}
```

**Solution:** Store debug info in error details:

```elixir
Jido.Error.planning_error("Precondition not met",
  task: "task_name",
  debug_tree: {:primitive, "task_name", false, condition_results}
)
```

---

### 2. Error Aggregation in Validation

**Current:** `domain_validation.ex` aggregates multiple errors into lists

```elixir
{:error, ["Error 1", "Error 2", "Error 3"]}
```

**Zoi approach:** Use `Enum.reduce_while` with `{:halt, {:error, error}}`

---

## 6. Approximate Number of Call Sites Requiring Updates

| Category | Count | Files Affected |
|----------|-------|----------------|
| `{:error, "string"}` tuples | ~118 | 15 files |
| `raise ArgumentError` calls | ~19 | 7 files |
| `raise "string"` calls | ~3 | 2 files |
| Error tuple pattern matches | ~50 | 10 files |
| **TOTAL** | **~190** | **~20 files** |

---

## 7. Recommended Implementation Strategy

### Phase 1: Create Jido.HTN.Error Module

**File:** `projects/jido_htn/lib/jido_htn/error.ex`

```elixir
defmodule Jido.HTN.Error do
  use Splode,
    error_classes: [
      invalid: Invalid,
      planning: Planning,
      execution: Execution,
      validation: Validation,
      timeout: Timeout,
      internal: Internal
    ],
    unknown_error: __MODULE__.Internal.UnknownError
end
```

**Error Classes for HTN:**
- `:invalid` - Invalid domain configuration, task definitions
- `:planning` - HTN planning failures (preconditions, method selection, dead-ends)
- `:execution` - Runtime action execution errors
- `:validation` - Domain validation failures
- `:timeout` - Planning timeout errors
- `:internal` - Unexpected system errors

---

### Phase 2: Update Core Planning Functions

**Priority:** High - Core planning logic

**Files:**
- `planner.ex` (10 error sites)
- `task_decomposer.ex` (8 error sites)

**Changes:**
- Replace `{:error, "reason"}` with `Jido.HTN.Error.planning_error(...)`
- Update type specs from `{:error, String.t()}` to `{:error, Exception.t()}`

---

### Phase 3: Update Domain Validation

**Priority:** High - User-facing validation

**File:** `domain_validation.ex` (42+ error sites)

**Changes:**
- Replace `{:error, "reason"}` with `Jido.HTN.Error.validation_error(...)`

---

### Phase 4: Update Domain Builder

**Priority:** Medium - Build-time errors

**File:** `domain_builder.ex` (7 raise sites)

**Changes:**
- Replace `raise ArgumentError` with `Jido.HTN.Error.invalid(...)`

---

### Phase 5: Update Serialization

**Priority:** Medium - I/O errors

**File:** `serializer.ex` (13 error sites)

**Changes:**
- Replace `{:error, "reason"}` with `Jido.HTN.Error.validation_error(...)`

---

## 8. Files Summary

**Files requiring changes:** ~20 files

**Core Library Files:**
1. `projects/jido_htn/lib/jido_htn/planner.ex`
2. `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex`
3. `projects/jido_htn/lib/jido_htn/domain/domain_builder.ex`
4. `projects/jido_htn/lib/jido_htn/domain/domain_validation.ex`
5. `projects/jido_htn/lib/jido_htn/serializer.ex`
6. `projects/jido_htn/lib/jido_htn/method.ex`
7. `projects/jido_htn/lib/jido_htn/compound_task.ex`
8. `projects/jido_htn/lib/jido_htn/primitive_task.ex`
9. `projects/jido_htn/lib/jido_htn/behaviour.ex`
10. `projects/jido_htn/lib/jido_htn/domain/domain_reader.ex`
11. `projects/jido_htn/lib/jido_htn/domain/helpers.ex`

**New file to create:**
- `projects/jido_htn/lib/jido_htn/error.ex`

**Test files requiring updates:**
- All test files matching error patterns (approximately 8-10 test files)

---

## 9. Type Spec Changes Required

**Before:**

```elixir
@spec plan(Domain.t(), map(), keyword()) ::
        {:ok, [{module(), keyword()}]} | {:error, String.t()}
```

**After:**

```elixir
@spec plan(Domain.t(), map(), keyword()) ::
        {:ok, [{module(), keyword()}]} | {:error, Exception.t()}
```

---

## 10. Estimated Effort

| Task | Estimate |
|------|----------|
| Create `Jido.HTN.Error` module | 2-3 hours |
| Update core planning functions | 4-6 hours |
| Update domain validation | 3-4 hours |
| Update domain builder | 2-3 hours |
| Update serialization | 2-3 hours |
| Update tests | 4-6 hours |
| Documentation | 2-3 hours |
| **Total** | **19-28 hours** |

---

## Conclusion

The jido_htn project has ~190 error-handling call sites across ~20 files that need migration to Zoi-compatible error handling. The migration involves:

1. Creating a new `Jido.HTN.Error` module using Splode
2. Replacing string-based `{:error, "reason"}` tuples with proper error structs
3. Updating `raise ArgumentError` calls to use the new error types
4. Preserving debug tree information in error details
5. Updating type specs to use `Exception.t()` instead of `String.t()`

The good news is that jido_htn already uses Zoi for struct validation, so the foundation is in place. The main work is standardizing business logic errors to use the same Zoi/Splode pattern used in jido and jido_action.

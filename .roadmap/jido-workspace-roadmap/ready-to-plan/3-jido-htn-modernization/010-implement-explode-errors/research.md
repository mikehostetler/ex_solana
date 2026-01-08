# Research: Implement Explode Errors for jido_htn

**Item ID**: `jido-workspace-roadmap/ready-to-plan/3-jido-htn-modernization/010-implement-explode-errors`

**Research Date**: 2025-01-07

---

## Executive Summary

The jido_htn project currently uses a **simple tuple-based error system** (`{:error, reason}`) that lacks structured error types, context, and the ability to distinguish between recoverable planning failures and critical errors. In contrast, other Jido projects (jido, jido_action, jido_signal, jido_ai) have standardized on **Splode-based error handling** with error classes and structured error types.

This research identifies:
- **Current error handling patterns** in jido_htn
- **Integration points** where explode errors should be introduced
- **Reference implementations** from other Jido libraries
- **Implementation strategy** with specific file locations

---

## 1. Current Error Handling in jido_htn

### Error Return Pattern

**Location**: Throughout `projects/jido_htn/lib/jido_htn/`

jido_htn uses a simple tuple-based error system:

```elixir
# planner.ex:17-18
@spec plan(Domain.t(), map(), keyword()) ::
        {:ok, [{module(), keyword()}]} | {:error, String.t()}

# planner.ex:61-62
@spec decompose(...) ::
        {:ok, list(), map(), list(), tuple()} | {:error, String.t(), tuple()}
```

### Error Types Currently Raised

#### 1. **Planning Failures** (Recoverable - Try Next Method)

**File**: `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex`

| Line | Error | Context |
|------|-------|---------|
| 91-92 | Precondition not met | `{:error, "Precondition not met for #{inspect(task.name)}", {:primitive, task.name, false, condition_results}}` |
| 269 | Method conditions not met | `{:error, "Method conditions not met"}` |
| 54 | Unknown task during decomposition | `{:error, "Unknown task: #{inspect(task_name)}", {:empty, task_name, false, []}}` |

#### 2. **Planning Failures** (Exhausted All Options)

**File**: `projects/jido_htn/lib/jido_htn/planner.ex`

| Line | Error | Context |
|------|-------|---------|
| 183-184 | Max recursion depth reached | `{:error, "Max recursion depth reached", ...}` |
| 50 | Planning timeout | `{:error, "Planning timed out after #{timeout}ms"}` |

#### 3. **Validation Errors** (Critical - Should Explode)

**File**: `projects/jido_htn/lib/jido_htn/planner.ex`

| Line | Error | Type |
|------|-------|------|
| 104 | Root task not found in domain | `raise ArgumentError` |
| 105 | Root task must be compound | `raise ArgumentError` |
| 112 | Invalid root_tasks parameter | `raise ArgumentError` |

### Current Error Handling Characteristics

1. **No Error Classification**: All errors are strings
2. **No Context**: Error messages contain minimal context
3. **No Stack Traces**: No structured error tracking
4. **Mixed Strategy**: Some use `raise`, some return `{:error, reason}`
5. **Debug Tree**: Errors include a tree structure for debugging (when `debug: true`)

---

## 2. HTN Planner Core Architecture

### Main Entry Points

**File**: `projects/jido_htn/lib/jido_htn/planner.ex`

| Function | Lines | Purpose |
|----------|-------|---------|
| `plan/3` | 19-56 | Public planning API with timeout |
| `decompose/8` | 61-86 | Task decomposition entry point |
| `validate_root_tasks!/2` | 89-114 | Validates and raises ArgumentError if invalid |
| `do_plan/5` | 116-152 | Core planning recursion |
| `do_decompose/9` | 154-230 | Decomposition recursion |

### Method Decomposition Logic

**File**: `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex`

| Function | Lines | Purpose |
|----------|-------|---------|
| `decompose_task/8` | 28-57 | Dispatch to primitive/compound handlers |
| `decompose_primitive/5` | 60-94 | Handle primitive tasks (actions) |
| `decompose_compound/8` | 96-175 | Handle compound tasks (try methods) |
| `try_method/9` | 197-271 | Attempt specific method with plan culling |

---

## 3. Zoi Integration Patterns

### Current Zoi Usage in jido_htn

**Files with Zoi schemas**:
- `lib/jido_htn/compound_task.ex`
- `lib/jido_htn/primitive_task.ex`
- `lib/jido_htn/method.ex`

### Zoi Schema Pattern Example

**From** `primitive_task.ex:14-58`:

```elixir
@schema Zoi.struct(
  __MODULE__,
  %{
    name: Zoi.string(description: "Unique name for this primitive task"),
    task: Zoi.tuple(
      {Zoi.atom(description: "Jido.Action module"),
       Zoi.array(Zoi.any(), description: "Action parameters")},
      description: "Jido.Action module and parameters"
    ) |> Zoi.default({nil, []}),
    # ...
  },
  coerce: true
)

def new(name, methods \\ []) when is_binary(name) do
  Zoi.parse(@schema, %{name: name, methods: methods})
end
```

---

## 4. Jido Error Patterns (Splode-Based Reference)

### Jido.Error (Core Framework)

**File**: `projects/jido/lib/jido/error.ex`

**Error Classes** (Lines 46-88):
```elixir
defmodule Invalid do
  use Splode.ErrorClass, class: :invalid
end

defmodule Execution do
  use Splode.ErrorClass, class: :execution
end

defmodule Planning do
  use Splode.ErrorClass, class: :planning
end

defmodule Routing do
  use Splode.ErrorClass, class: :routing
end

defmodule Timeout do
  use Splode.ErrorClass, class: :timeout
end

defmodule Internal do
  use Splode.ErrorClass, class: :internal
end
```

**Splode Usage** (Lines 90-99):
```elixir
use Splode,
  error_classes: [
    invalid: Invalid,
    execution: Execution,
    planning: Planning,
    routing: Routing,
    timeout: Timeout,
    internal: Internal
  ],
  unknown_error: Internal.UnknownError
```

### Jido.Action.Error

**File**: `projects/jido_action/lib/jido_action/error.ex`

**Error Classes** (Lines 36-42):
- `Invalid` - Input validation failures
- `Execution` - Runtime execution failures
- `Config` - Configuration issues
- `Internal` - Unexpected failures

### Jido.AI.Error

**File**: `projects/jido_ai/lib/jido_ai/error.ex`

**Error Classes** (Lines 11-18):
- `API` - Rate limits, auth, network errors
- `Validation` - Input validation
- `Execution` - LLM execution failures

### Key Splode Features Used

1. **Error Classes**: Hierarchical organization with precedence
2. **Error Composition**: Multiple errors can be aggregated
3. **Stack Traces**: Automatic stacktrace capture
4. **Structured Fields**: Type-safe error fields
5. **Class Precedence**: When aggregating, highest class wins

---

## 5. "Explode Errors" Implementation Requirements

### What "Explode Errors" Means

Based on the Jido error patterns, "explode errors" means:

1. **Structured Error Types**: Use Splode to define error classes
2. **Error Aggregation**: Collect multiple errors during validation
3. **Clear Distinction**: Separate planning failures (expected) from critical errors (unexpected)
4. **Rich Context**: Include task names, domain state, method paths, etc.
5. **Stack Traces**: Capture full context for debugging

### Proposed Error Classes for jido_htn

```elixir
# Planning errors - expected during search (RETURN, don't raise)
defmodule Planning do
  use Splode.ErrorClass, class: :planning
end

# Validation errors - critical (SHOULD EXPLODE/raise)
defmodule Validation do
  use Splode.ErrorClass, class: :validation
end

# Domain errors - critical (SHOULD EXPLODE/raise)
defmodule Domain do
  use Splode.ErrorClass, class: :domain
end

# Execution errors - runtime failures
defmodule Execution do
  use Splode.ErrorClass, class: :execution
end
```

### Specific Error Types to Create

#### Planning Errors (Non-Exploding - Return tuples)

- `PlanningError.NoValidMethod` - All methods failed for compound task
- `PlanningError.PreconditionNotMet` - Task precondition failed
- `PlanningError.MaxRecursionDepth` - Hit recursion limit
- `PlanningError.Timeout` - Planning exceeded time limit
- `PlanningError.UnknownTask` - Task not found in domain

#### Validation Errors (Exploding - Raise exceptions)

- `ValidationError.InvalidDomain` - Domain structure invalid
- `ValidationError.InvalidRootTask` - Root task not found or wrong type
- `ValidationError.InvalidMethod` - Method has no subtasks or cycles
- `ValidationError.InvalidCallback` - Callback signature wrong
- `ValidationError.DuplicateNames` - Name conflicts in domain

#### Domain Errors (Exploding - Raise exceptions)

- `DomainError.MissingTask` - Referenced task not defined
- `DomainError.InvalidAction` - Action not in allowed_workflows
- `DomainError.CallbackNotFound` - Callback name doesn't exist

---

## 6. Integration Points

### A. Planner Entry Points

**File**: `projects/jido_htn/lib/jido_htn/planner.ex`

| Line | Current | Proposed Change |
|------|---------|-----------------|
| 104 | `raise ArgumentError, "Root task '#{task}' not found"` | `raise Error.Validation.InvalidRootTask.exception(...)` |
| 105 | `raise ArgumentError, "Root task '#{task}' must be compound"` | `raise Error.Validation.InvalidRootTask.exception(...)` |
| 112 | `raise ArgumentError, "root_tasks must be a list"` | `raise Error.Validation.InvalidRootTask.exception(...)` |
| 143-150 | `{:error, reason, tree}` | `{:error, Error.Planning.NoValidMethod.exception(...)}` |
| 183-184 | `{:error, "Max recursion depth reached", ...}` | `{:error, Error.Planning.MaxRecursionDepth.exception(...)}` |
| 50 | `{:error, "Planning timed out..."}` | `{:error, Error.Planning.Timeout.exception(...)}` |

### B. Task Decomposition

**File**: `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex`

| Line | Current | Proposed Change |
|------|---------|-----------------|
| 91-92 | `{:error, "Precondition not met..."}` | `{:error, Error.Planning.PreconditionNotMet.exception(...)}` |
| 54 | `{:error, "Unknown task..."}` | `{:error, Error.Domain.MissingTask.exception(...)}` |
| 269 | `{:error, "Method conditions not met"}` | `{:error, Error.Planning.NoValidMethod.exception(...)}` |

### C. Domain Validation

**File**: `projects/jido_htn/lib/jido_htn/domain/domain_validation.ex`

| Lines | Purpose | Change |
|-------|---------|--------|
| 60-68 | Validation pipeline | Aggregate all errors into `ValidationError.InvalidDomain` |
| 92-101 | Non-empty domain check | Return structured validation error |
| 105-118 | Unique names check | Return structured validation error |
| 122-142 | Subtasks validation | Return structured validation error |
| 287-309 | Root task presence check | Return structured validation error |

### D. Domain Builder

**File**: `projects/jido_htn/lib/jido_htn/domain/domain_builder.ex`

| Lines | Purpose | Change |
|-------|---------|--------|
| 133 | Root task validation | Use `ValidationError.InvalidRootTask` |
| 139 | Task not found error | Use `ValidationError.InvalidRootTask` |

---

## 7. Implementation Strategy

### Phase 1: Add Splode Dependency

**File**: `projects/jido_htn/mix.exs`

```elixir
defp deps do
  [
    # ... existing deps
    {:splode, "~> 0.2"}
  ]
end
```

### Phase 2: Create Error Module

**New File**: `projects/jido_htn/lib/jido_htn/error.ex`

```elixir
defmodule Jido.HTN.Error do
  @moduledoc """
  Structured error handling for Jido HTN using Splode.
  """

  use Splode,
    error_classes: [
      planning: Planning,
      validation: Validation,
      domain: Domain
    ],
    unknown_error: __MODULE__.Planning.UnknownError

  # Define error classes
  defmodule Planning do
    use Splode.ErrorClass, class: :planning
  end

  defmodule Validation do
    use Splode.ErrorClass, class: :validation
  end

  defmodule Domain do
    use Splode.ErrorClass, class: :domain
  end

  # Define specific error types
  defmodule Planning.NoValidMethod do
    use Splode.Error,
      fields: [:task, :attempted_methods, :failure_reasons, :debug_tree],
      class: :planning
  end

  defmodule Planning.PreconditionNotMet do
    use Splode.Error,
      fields: [:task, :precondition_results, :world_state],
      class: :planning
  end

  defmodule Planning.MaxRecursionDepth do
    use Splode.Error,
      fields: [:depth, :task_path],
      class: :planning
  end

  defmodule Planning.Timeout do
    use Splode.Error,
      fields: [:timeout_ms, :partial_plan],
      class: :planning
  end

  defmodule Planning.UnknownTask do
    use Splode.Error,
      fields: [:task, :available_tasks],
      class: :planning
  end

  defmodule Validation.InvalidRootTask do
    use Splode.Error,
      fields: [:task, :reason, :domain],
      class: :validation
  end

  defmodule Validation.InvalidDomain do
    use Splode.Error,
      fields: [:validation_errors],
      class: :validation
  end

  defmodule Validation.InvalidMethod do
    use Splode.Error,
      fields: [:method, :reason],
      class: :validation
  end

  defmodule Domain.MissingTask do
    use Splode.Error,
      fields: [:task, :available_tasks],
      class: :domain
  end

  defmodule Domain.InvalidAction do
    use Splode.Error,
      fields: [:action, :allowed_workflows],
      class: :domain
  end
end
```

### Phase 3: Update Planner

**File**: `projects/jido_htn/lib/jido_htn/planner.ex`

Replace string errors with structured errors:

```elixir
# Line 104
# Before:
raise ArgumentError, "Root task '#{task}' not found in domain"

# After:
raise Error.Validation.InvalidRootTask.exception(
  message: "Root task '#{task}' not found in domain",
  task: task
)

# Line 143-150
# Before:
{:error, reason, tree}

# After:
{:error, Error.Planning.NoValidMethod.exception(
  message: "Planning failed: #{reason}",
  debug_tree: tree
)}
```

### Phase 4: Update Task Decomposer

**File**: `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex`

```elixir
# Line 91-92
# Before:
{:error, "Precondition not met for #{inspect(task.name)}", debug_tree}

# After:
{:error, Error.Planning.PreconditionNotMet.exception(
  message: "Precondition not met for task '#{task.name}'",
  task: task.name,
  precondition_results: condition_results,
  world_state: world_state
)}

# Line 54
# Before:
{:error, "Unknown task: #{inspect(task_name)}", debug_tree}

# After:
{:error, Error.Domain.MissingTask.exception(
  message: "Task '#{task_name}' not found in domain",
  task: task_name,
  available_tasks: Map.keys(domain.tasks)
)}
```

### Phase 5: Update Domain Validation

**File**: `projects/jido_htn/lib/jido_htn/domain/domain_validation.ex`

Aggregate validation errors into Splode errors:

```elixir
# Lines 60-68
# Before:
Enum.reduce_while(@validation_functions, :ok, fn validator_name, _acc ->
  case apply(__MODULE__, validator_name, [domain]) do
    {:ok, _} -> {:cont, :ok}
    {:error, errors} -> {:halt, {:error, errors}}
  end
end)

# After:
errors =
  Enum.reduce(@validation_functions, [], fn validator_name, acc ->
    case apply(__MODULE__, validator_name, [domain]) do
      {:ok, _} -> acc
      {:error, error_list} when is_list(error_list) ->
        acc ++ error_list
      {:error, error} ->
        acc ++ [error]
    end
  end)

case errors do
  [] -> :ok
  errors ->
    {:error, Error.Validation.InvalidDomain.exception(
      message: "Domain validation failed with #{length(errors)} error(s)",
      validation_errors: errors
    )}
end
```

### Phase 6: Update Tests

**File**: `projects/jido_htn/test/jido_htn/planner_test.exs`

Update assertions to handle structured errors:

```elixir
# Before:
assert_raise ArgumentError, "Root task 'nonexistent' not found in domain", fn ->
  HTN.plan(domain, %{}, root_tasks: ["nonexistent"])
end

# After:
assert_raise Error.Validation.InvalidRootTask, ~r/nonexistent/, fn ->
  HTN.plan(domain, %{}, root_tasks: ["nonexistent"])
end

# For planning errors (returned, not raised):
assert {:error, %Error.Planning.NoValidMethod{}} =
  HTN.plan(domain, world_state)
```

---

## 8. Key Files and Line Numbers Reference

### Core Planning Files

| File | Lines | Purpose |
|------|-------|---------|
| `lib/jido_htn/planner.ex` | 19-56 | Main `plan/3` entry point |
| `lib/jido_htn/planner.ex` | 61-86 | `decompose/8` public API |
| `lib/jido_htn/planner.ex` | 89-114 | `validate_root_tasks!/2` |
| `lib/jido_htn/planner.ex` | 116-152 | `do_plan/5` core logic |
| `lib/jido_htn/planner.ex` | 154-230 | `do_decompose/9` recursion |
| `lib/jido_htn/planner/task_decomposer.ex` | 28-57 | `decompose_task/8` dispatcher |
| `lib/jido_htn/planner/task_decomposer.ex` | 60-94 | `decompose_primitive/5` |
| `lib/jido_htn/planner/task_decomposer.ex` | 96-175 | `decompose_compound/8` |
| `lib/jido_htn/planner/task_decomposer.ex` | 197-271 | `try_method/9` |

### Error-Related Locations

| File | Lines | Current Error |
|------|-------|---------------|
| `planner.ex` | 104 | Root task not found (raise) |
| `planner.ex` | 105 | Root task not compound (raise) |
| `planner.ex` | 112 | Invalid root_tasks param (raise) |
| `planner.ex` | 143-150 | Planning failed (return) |
| `planner.ex` | 183-184 | Max recursion (return) |
| `planner.ex` | 50 | Timeout (return) |
| `task_decomposer.ex` | 91-92 | Precondition failed (return) |
| `task_decomposer.ex` | 54 | Unknown task (return) |
| `task_decomposer.ex` | 269 | Method conditions not met (return) |

### Validation Files

| File | Lines | Purpose |
|------|-------|---------|
| `domain/domain_validation.ex` | 60-68 | Validation pipeline |
| `domain/domain_validation.ex` | 92-101 | Non-empty domain check |
| `domain/domain_validation.ex` | 105-118 | Unique names check |
| `domain/domain_validation.ex` | 122-142 | Subtasks validation |
| `domain/domain_validation.ex` | 287-309 | Root task presence check |

### Domain Builder Files

| File | Lines | Purpose |
|------|-------|---------|
| `domain/domain_builder.ex` | 133-140 | Root task validation (raises) |
| `domain/domain_builder.ex` | 31-36 | `new!/1` conversion |

### Reference Error Implementations

| File | Purpose |
|------|---------|
| `projects/jido/lib/jido/error.ex` | Core Splode pattern reference |
| `projects/jido_action/lib/jido_action/error.ex` | Action error pattern reference |
| `projects/jido_ai/lib/jido_ai/error.ex` | AI error pattern reference |

---

## 9. Recommendations

### 1. Error Classification Strategy

**Planning Errors** (Return tuples, don't explode):
- Precondition failures
- Method failures (try next method)
- Timeout (return partial plan if available)
- Max recursion depth

**Validation Errors** (Explode immediately):
- Invalid domain structure
- Missing tasks
- Root task validation
- Invalid callbacks
- Name conflicts

**Domain Errors** (Explode immediately):
- Referenced but undefined tasks
- Actions not in allowed_workflows
- Cyclic dependencies

### 2. Backward Compatibility

Consider maintaining compatibility during transition:

```elixir
# Option 1: Accept both old and new format
def plan(domain, world_state, opts \\ []) do
  result = do_plan(...)

  case result do
    {:error, %Splode.Error{} = error} ->
      {:error, error}
    {:error, reason} when is_binary(reason) ->
      # Legacy format - convert
      {:error, Error.from_tuple({:error, reason})}
  end
end

# Option 2: Feature flag
def plan(domain, world_state, opts \\ []) do
  structured_errors = Keyword.get(opts, :structured_errors, false)

  if structured_errors do
    # Return Splode errors
  else
    # Return string errors
  end
end
```

### 3. Error Aggregation Pattern

Use Splode's error composition for validation:

```elixir
def validate_domain(domain) do
  errors =
    []
    |> check_non_empty(domain)
    |> check_unique_names(domain)
    |> check_subtasks(domain)

  case errors do
    [] -> :ok
    list ->
      {:error, Splode.ErrorClass.to_errors(Validation, list)}
  end
end
```

### 4. Debug Tree Integration

Preserve the existing debug tree feature:

```elixir
defmodule Error.Planning.NoValidMethod do
  use Splode.Error,
    fields: [:task, :attempted_methods, :debug_tree],
    class: :planning
end

# When returning error
{:error, Error.Planning.NoValidMethod.exception(
  message: "No valid method found for '#{task_name}'",
  task: task_name,
  attempted_methods: Enum.map(methods, & &1.name),
  debug_tree: debug_tree  # Preserve existing debugging info
)}
```

### 5. Testing Strategy

Add comprehensive error tests:

```elixir
describe "error handling" do
  test "returns structured planning error when no methods available" do
    assert {:error, %Error.Planning.NoValidMethod{}} =
      HTN.plan(domain, world_state)
  end

  test "explodes with validation error for invalid root task" do
    assert_raise Error.Validation.InvalidRootTask, fn ->
      HTN.plan(domain, %{}, root_tasks: ["bogus"])
    end
  end

  test "aggregates multiple validation errors" do
    assert {:error, %Error.Validation.InvalidDomain{
      validation_errors: errors
    }} = Domain.build(invalid_builder)

    assert length(errors) > 1
  end
end
```

---

## 10. Dependencies

### External Dependencies

- **splode** (~> 0.2) - Structured error handling library

### Internal Jido Dependencies

- **jido** - For reference error patterns (`projects/jido/lib/jido/error.ex`)
- **jido_action** - For action error patterns (`projects/jido_action/lib/jido_action/error.ex`)
- **jido_ai** - For AI error patterns (`projects/jido_ai/lib/jido_ai/error.ex`)

---

## Summary

The jido_htn project currently uses a **simple string-based error system** that returns `{:error, reason}` tuples. To implement "explode errors":

1. **Add Splode dependency** to `mix.exs`
2. **Create `Jido.HTN.Error` module** with error classes:
   - `Planning` - Expected failures (don't explode)
   - `Validation` - Critical validation errors (explode)
   - `Domain` - Domain structure errors (explode)
3. **Replace string errors** with structured Splode errors in:
   - `planner.ex` - Lines 104, 143-150, 183-184
   - `task_decomposer.ex` - Lines 54, 91-92, 269
   - `domain_validation.ex` - Lines 60-68
   - `domain_builder.ex` - Lines 133, 139
4. **Preserve debug tree** information in error fields
5. **Update tests** to assert on structured errors
6. **Consider backward compatibility** during transition

**Key distinction**:
- **Planning failures** → Return `{:error, structured_error}` (expected during search)
- **Validation/critical errors** → `raise` with Splode error (should explode immediately)

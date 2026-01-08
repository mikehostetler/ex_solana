# Implementation Plan: Convert to Zoi Error Handling

**Item ID:** jido-workspace-roadmap/ready-to-plan/3-jido-htn-modernization/009-convert-to-zoi-error-handling

---

## 1. Executive Summary

This implementation migrates `jido_htn` from mixed error handling (string tuples, exceptions, and Zoi validation) to a unified Zoi/Splode-based error system. The migration will create a new `Jido.HTN.Error` module using Splode with HTN-specific error classes, then systematically update ~190 error-handling call sites across ~20 files. This aligns jido_htn with the jido and jido_action error patterns, enabling better error introspection, consistent error classification, and improved debugging capabilities.

**Key Architectural Decisions:**
- Use Splode for unified error handling (matching jido/jido_action patterns)
- Preserve existing debug tree information by storing it in error metadata
- Maintain backward compatibility where possible (error tuples still return `{:error, exception}`)
- Phase the migration to minimize risk and enable testing at each stage

**Effort Estimate:** 19-28 hours across 5 phases

---

## 2. Impact Analysis Summary

### Key Findings from Research

**Files Requiring Changes:** ~20 files

**Error Sites by Category:**
| Category | Count | Files Affected |
|----------|-------|----------------|
| `{:error, "string"}` tuples | ~118 | 15 files |
| `raise ArgumentError` calls | ~19 | 7 files |
| `raise "string"` calls | ~3 | 2 files |
| Error tuple pattern matches | ~50 | 10 files |

### Core Files to Modify

**High Priority (Core Planning):**
1. `projects/jido_htn/lib/jido_htn/planner.ex` (10 error sites)
2. `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex` (8 error sites)

**High Priority (User-Facing):**
3. `projects/jido_htn/lib/jido_htn/domain/domain_validation.ex` (42+ error sites)

**Medium Priority (Build/Serialization):**
4. `projects/jido_htn/lib/jido_htn/domain/domain_builder.ex` (7 raise sites)
5. `projects/jido_htn/lib/jido_htn/serializer.ex` (13 error sites)

**Struct Files:**
6. `projects/jido_htn/lib/jido_htn/method.ex`
7. `projects/jido_htn/lib/jido_htn/compound_task.ex`
8. `projects/jido_htn/lib/jido_htn/primitive_task.ex`

**Supporting Files:**
9. `projects/jido_htn/lib/jido_htn/domain/domain_reader.ex`
10. `projects/jido_htn/lib/jido_htn/domain/helpers.ex`

### Existing Patterns to Follow

**From `jido/lib/jido/error.ex`:**
```elixir
# Error classes:
:invalid     # Input validation, bad requests, invalid configurations
:execution   # Runtime execution errors and action failures
:planning    # Action planning and workflow errors
:routing     # Agent routing and dispatch errors
:timeout     # Action and process timeouts
:internal    # Unexpected internal errors and system failures
```

**Usage Pattern:**
```elixir
{:error, error} = Jido.Error.validation_error("Invalid parameters", field: :user_id)
{:error, timeout} = Jido.Error.timeout_error("Action timed out after 30s", timeout: 30000)
{:error, planning} = Jido.Error.planning_error("No valid method found", task: "do_work")
```

### Integration Points Identified

1. **Debug Tree Preservation:** Current errors include debug trees that must be preserved in error metadata
2. **Error Aggregation:** Domain validation aggregates errors - needs refactoring to early-return pattern
3. **Test Files:** All existing tests need updates to match new error format
4. **Type Specs:** Need to update from `{:error, String.t()}` to `{:error, Exception.t()}`

---

## 3. Feature Specification

### User Stories

**As a developer using jido_htn**, I want structured error information so that I can:
- Programmatically inspect error types and metadata
- Extract detailed context (task names, conditions, world state) from errors
- Log errors in a structured format
- Make control-flow decisions based on error classes

**As a contributor to jido_htn**, I want consistent error handling so that:
- All errors follow the same pattern as jido/jido_action
- Error creation is straightforward and well-documented
- Error information is sufficient for debugging
- Tests can assert on error types and metadata

### API Contracts

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

**New Error Module API:**
```elixir
# Planning errors
Jido.HTN.Error.planning_error("No valid method found", task: "do_work")

# Validation errors
Jido.HTN.Error.validation_error("Invalid domain", domain: "my_domain")

# Timeout errors
Jido.HTN.Error.timeout_error("Planning timed out", timeout: 5000)

# Invalid errors
Jido.HTN.Error.invalid("Invalid task definition", task: "bad_task")

# Execution errors
Jido.HTN.Error.execution_error("Action failed", action: MyAction, error: reason)
```

### Data Flow

```
Planning/Execution Request
    |
    v
Error Condition Detected
    |
    v
Call Jido.HTN.Error.*_error(...)
    |
    v
Return {:error, %Exception{}}
    |
    v
Caller pattern matches or inspects Exception
    |
    v
Log/Handle/Propagate error with full context
```

### State Management Requirements

No state management changes required - this is purely an error handling refactor.

### Error Handling Approach

**For Validation Errors:**
- Use `Jido.HTN.Error.validation_error()` with descriptive message
- Include field names and invalid values in metadata
- Aggregate validation errors by returning early on first error

**For Planning Errors:**
- Use `Jido.HTN.Error.planning_error()` for failed preconditions, method selection
- Include task name, method name, world state snapshot in metadata
- Preserve debug tree in `:debug_tree` metadata field

**For Timeout Errors:**
- Use `Jido.HTN.Error.timeout_error()` with timeout value
- Include operation being timed out in metadata

**For Invalid Input:**
- Use `Jido.HTN.Error.invalid()` for bad arguments
- Include parameter names and values in metadata

---

## 4. Technical Design

### Data Model Changes

**New File:** `projects/jido_htn/lib/jido_htn/error.ex`

```elixir
defmodule Jido.HTN.Error do
  @moduledoc """
  Error types for Jido.HTN operations.

  Error Classes:
  - :invalid - Invalid domain configuration, task definitions, parameters
  - :planning - HTN planning failures (preconditions, method selection, dead-ends)
  - :execution - Runtime action execution errors
  - :validation - Domain validation failures
  - :timeout - Planning timeout errors
  - :internal - Unexpected system errors
  """

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

  # Helper functions for each error class
  def planning_error(message, metadata \\ []) do
    error = Planning.new(message)
    {:error, %{error | __struct__: error.__struct__, metadata: Map.new(metadata)}}
  end

  def validation_error(message, metadata \\ []) do
    error = Validation.new(message)
    {:error, %{error | __struct__: error.__struct__, metadata: Map.new(metadata)}}
  end

  def timeout_error(message, metadata \\ []) do
    error = Timeout.new(message)
    {:error, %{error | __struct__: error.__struct__, metadata: Map.new(metadata)}}
  end

  def invalid(message, metadata \\ []) do
    error = Invalid.new(message)
    {:error, %{error | __struct__: error.__struct__, metadata: Map.new(metadata)}}
  end

  def execution_error(message, metadata \\ []) do
    error = Execution.new(message)
    {:error, %{error | __struct__: error.__struct__, metadata: Map.new(metadata)}}
  end

  def internal_error(message, metadata \\ []) do
    error = Internal.new(message)
    {:error, %{error | __struct__: error.__struct__, metadata: Map.new(metadata)}}
  end
end
```

### Module Organization

Following existing jido_htn structure:
- New module: `Jido.HTN.Error` at `projects/jido_htn/lib/jido_htn/error.ex`
- Update existing modules to use new error functions
- Maintain all existing public APIs

### Third-Party Integration

**Dependencies:**
- Add `:splode` to `mix.exs` dependencies (should already be present via jido)
- No new external dependencies

### Configuration Changes

None required - this is an internal refactor.

---

## 5. Implementation Phases

### Phase 1: Foundation - Error Module Creation

**Objective:** Create the `Jido.HTN.Error` module with Splode-based error classes

**Success Criteria:**
- Error module compiles without errors
- All error classes are defined
- Helper functions work correctly
- Basic test coverage of error creation

**Files to Create:**
- `projects/jido_htn/lib/jido_htn/error.ex` - New error module

**Files to Modify:**
- `projects/jido_htn/mix.exs` - Ensure splode dependency (likely already present)

**Tests to Add:**
- `projects/jido_htn/test/jido_htn/error_test.exs` - New test file
  - Test error creation for each error class
  - Test metadata preservation
  - Test error message formatting

**Dependencies:**
- None (foundational phase)

**Acceptance Criteria:**
- All error classes compile
- Can create errors with `Jido.HTN.Error.planning_error(...)`
- Errors include metadata in error struct
- Tests pass

---

### Phase 2: Core Planning Functions

**Objective:** Migrate error handling in core planning logic

**Success Criteria:**
- `planner.ex` uses new error types
- `task_decomposer.ex` uses new error types
- All error sites migrated (18 sites)
- Planning tests updated and passing

**Files to Modify:**
- `projects/jido_htn/lib/jido_htn/planner.ex`
  - Update 10 error sites (timeout, planning failures)
  - Update type specs
  - Preserve timeout information in error metadata

- `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex`
  - Update 8 error sites (preconditions, method selection, task not found)
  - Preserve debug trees in `:debug_tree` metadata field
  - Update type specs

**Tests to Update:**
- `projects/jido_htn/test/jido_htn/planner_test.exs`
- `projects/jido_htn/test/jido_htn/task_decomposer_test.exs`

**Dependencies:**
- Phase 1 must be complete

**Specific Changes:**

**planner.ex:**
```elixir
# Before:
{:error, "Planning timed out after #{timeout}ms"}

# After:
Jido.HTN.Error.timeout_error("Planning timed out", timeout: timeout)
```

**task_decomposer.ex:**
```elixir
# Before:
{:error, "Precondition not met for #{inspect(task.name)}",
 {:primitive, task.name, false, condition_results}}

# After:
Jido.HTN.Error.planning_error("Precondition not met",
  task: task.name,
  debug_tree: {:primitive, task.name, false, condition_results}
)
```

**Acceptance Criteria:**
- All planning errors return `{:error, %Jido.HTN.Error.Planning{}}`
- Metadata includes task names, conditions, debug trees
- Tests assert on error types, not string matching
- Planning tests pass

---

### Phase 3: Domain Validation

**Objective:** Migrate domain validation error handling

**Success Criteria:**
- `domain_validation.ex` uses new error types
- `domain_builder.ex` uses new error types
- All validation errors migrated (49+ sites)
- Validation tests updated and passing

**Files to Modify:**
- `projects/jido_htn/lib/jido_htn/domain/domain_validation.ex`
  - Update 42+ error sites
  - Convert error aggregation to early-return pattern
  - Update type specs

- `projects/jido_htn/lib/jido_htn/domain/domain_builder.ex`
  - Replace `raise ArgumentError` with `Jido.HTN.Error.invalid(...)`
  - Update 7 raise sites
  - Update type specs

**Tests to Update:**
- `projects/jido_htn/test/jido_htn/domain/domain_validation_test.exs`
- `projects/jido_htn/test/jido_htn/domain/domain_builder_test.exs`

**Dependencies:**
- Phase 1 must be complete

**Specific Changes:**

**domain_validation.ex:**
```elixir
# Before (aggregating errors):
errors = []
errors = if invalid?, do: ["Error 1" | errors]
errors = if also_invalid?, do: ["Error 2" | errors]
if errors == [], do: {:ok, domain}, else: {:error, Enum.reverse(errors)}

# After (early return):
cond do
  invalid? ->
    Jido.HTN.Error.validation_error("Invalid domain", reason: "Error 1")

  also_invalid? ->
    Jido.HTN.Error.validation_error("Invalid domain", reason: "Error 2")

  true ->
    {:ok, domain}
end
```

**domain_builder.ex:**
```elixir
# Before:
raise ArgumentError, "Invalid Method: #{inspect(reason)}"

# After:
Jido.HTN.Error.invalid("Invalid Method", reason: inspect(reason))
```

**Acceptance Criteria:**
- All validation errors return `{:error, %Jido.HTN.Error.Validation{}}`
- All invalid argument errors return `{:error, %Jido.HTN.Error.Invalid{}}`
- Tests assert on error types
- Validation tests pass

---

### Phase 4: Serialization and Supporting Modules

**Objective:** Migrate error handling in serialization and supporting modules

**Success Criteria:**
- `serializer.ex` uses new error types
- `domain_reader.ex` uses new error types
- `helpers.ex` uses new error types
- All serialization/supporting errors migrated
- All tests updated and passing

**Files to Modify:**
- `projects/jido_htn/lib/jido_htn/serializer.ex`
  - Update 13 error sites
  - Replace rescue ArgumentError with error returns
  - Update type specs

- `projects/jido_htn/lib/jido_htn/domain/domain_reader.ex`
  - Update error sites
  - Update type specs

- `projects/jido_htn/lib/jido_htn/domain/helpers.ex`
  - Update error sites
  - Update type specs

- `projects/jido_htn/lib/jido_htn/method.ex`
  - Update `new!/1` to use new error type
- `projects/jido_htn/lib/jido_htn/compound_task.ex`
  - Update `new!/1` to use new error type
- `projects/jido_htn/lib/jido_htn/primitive_task.ex`
  - Update `new!/1` to use new error type

**Tests to Update:**
- `projects/jido_htn/test/jido_htn/serializer_test.exs`
- All other affected test files

**Dependencies:**
- Phase 1 must be complete

**Specific Changes:**

**serializer.ex:**
```elixir
# Before:
rescue
  ArgumentError -> {:error, "Invalid JSON"}

# After:
rescue
  e -> Jido.HTN.Error.validation_error("Invalid JSON", details: Exception.message(e))
```

**Struct `new!` functions:**
```elixir
# Before:
def new!(opts \\ []) do
  case new(opts) do
    {:ok, struct} -> struct
    {:error, reason} -> raise ArgumentError, "Invalid #{__MODULE__}: #{inspect(reason)}"
  end
end

# After:
def new!(opts \\ []) do
  case new(opts) do
    {:ok, struct} -> struct
    {:error, error} -> raise error  # Raise the error struct directly
  end
end
```

**Acceptance Criteria:**
- All serialization errors use new error types
- All struct `new!` functions raise error structs
- Tests assert on error types
- All tests pass

---

### Phase 5: Documentation and Polish

**Objective:** Update documentation and ensure code quality

**Success Criteria:**
- All documentation updated
- Type specs consistently use `Exception.t()`
- Code review complete
- All tests passing with good coverage

**Documentation Updates:**
- Update `moduledoc` for `Jido.HTN.Error`
- Update `@doc` for functions that return errors
- Update README with error handling examples
- Add error handling guide to documentation

**Type Spec Cleanup:**
- Audit all `@spec` attributes
- Replace `{:error, String.t()}` with `{:error, Exception.t()}`
- Replace `{:error, term()}` with `{:error, Exception.t()}` where appropriate

**Code Quality:**
- Run `mix format` on all changed files
- Run `mix credo` and fix warnings
- Run `mix dialyzer` and fix type warnings
- Review all error messages for clarity

**Test Coverage:**
- Ensure all error paths have tests
- Test error metadata preservation
- Test error class matching
- Add property-based tests for error creation if needed

**Dependencies:**
- All previous phases complete

**Acceptance Criteria:**
- Documentation complete and accurate
- Type specs consistent
- Code quality tools pass
- Test coverage maintained or improved
- Ready for code review

---

## 6. Quality & Testing Strategy

### Test Categories

**Unit Tests:**
- Error creation for each error class
- Error metadata preservation
- Error message formatting
- Error pattern matching

**Integration Tests:**
- End-to-end planning with error scenarios
- Domain validation with errors
- Serialization with errors
- Error propagation through call stack

**Property-Based Tests:**
- Error metadata preservation (properties)
- Error class inheritance
- Error struct validity

### Coverage Targets

- **Overall:** Maintain existing coverage (aim for >90%)
- **New Code:** 100% coverage for `Jido.HTN.Error` module
- **Error Paths:** 100% coverage of all error sites

### Quality Gates

**Before Each Phase:**
- Previous phase tests pass
- Code compiles without warnings

**Before Merge:**
- All tests pass (`mix test`)
- Type checking passes (`mix dialyzer`)
- Code quality passes (`mix credo --strict`)
- Documentation complete
- Code review approved

---

## 7. Risk Assessment

### Technical Risks

**Risk: Breaking existing user code**
- **Mitigation:** Maintain error tuple format `{:error, exception}`, only change content
- **Impact:** Low - error tuple format unchanged

**Risk: Debug tree information loss**
- **Mitigation:** Explicitly preserve debug trees in `:debug_tree` metadata field
- **Impact:** Medium - could affect debugging

**Risk: Test updates miss edge cases**
- **Mitigation:** Comprehensive test audit, add regression tests
- **Impact:** Medium - could introduce bugs

### Dependency Risks

**Risk: Splode version compatibility**
- **Mitigation:** Use same version as jido/jido_action
- **Impact:** Low - shared dependency management

**Risk: Changes to jido/jido_action error patterns**
- **Mitigation:** Coordinate with jido team, align on patterns
- **Impact:** Low - patterns are stable

### Timeline Risks

**Risk: More error sites than estimated**
- **Mitigation:** Buffer in estimate, phase-based approach allows course correction
- **Impact:** Medium - could extend timeline

**Risk: Test updates take longer than expected**
- **Mitigation:** Update tests incrementally with each phase
- **Impact:** Low - phased approach isolates test work

---

## 8. Success Criteria

### Measurable Outcomes

1. **All ~190 error sites migrated** to Zoi/Splode errors
2. **Zero string-based `{:error, "reason"}` tuples** remaining in codebase
3. **All tests passing** with updated error assertions
4. **Type specs updated** to use `Exception.t()` instead of `String.t()`
5. **Documentation complete** with error handling examples
6. **Code quality tools pass** (credo, dialyzer, formatter)

### Definition of Done

An item is complete when:
- [ ] `Jido.HTN.Error` module created with Splode
- [ ] All error sites in `planner.ex` and `task_decomposer.ex` migrated
- [ ] All error sites in `domain_validation.ex` and `domain_builder.ex` migrated
- [ ] All error sites in `serializer.ex` and supporting modules migrated
- [ ] All tests updated to assert on error types, not strings
- [ ] All type specs updated to use `Exception.t()`
- [ ] Documentation updated with error handling guide
- [ ] All tests pass (`mix test`)
- [ ] Code quality tools pass (`mix credo --strict`, `mix dialyzer`)
- [ ] Code review approved

### Acceptance Testing Approach

1. **Smoke Test:** Run existing test suite - all should pass with new error types
2. **Error Inspection Test:** Create a planning scenario that fails, inspect error struct
3. **Metadata Test:** Verify error metadata contains expected information
4. **Debug Tree Test:** Verify debug trees preserved in error metadata
5. **Integration Test:** Test full planning workflow with various error scenarios
6. **Regression Test:** Ensure no behavior changes beyond error format

---

## Appendix A: Error Migration Examples

### Example 1: Planning Timeout

**Before:**
```elixir
# planner.ex:92
nil ->
  dbug("Planning timed out after #{timeout}ms")
  {:error, "Planning timed out after #{timeout}ms"}
```

**After:**
```elixir
# planner.ex:92
nil ->
  dbug("Planning timed out after #{timeout}ms")
  Jido.HTN.Error.timeout_error("Planning timed out", timeout: timeout)
```

### Example 2: Failed Precondition

**Before:**
```elixir
# task_decomposer.ex:170-172
else
  {:error, "Precondition not met for #{inspect(task.name)}",
   {:primitive, task.name, false, condition_results}}
end
```

**After:**
```elixir
# task_decomposer.ex:170-172
else
  Jido.HTN.Error.planning_error("Precondition not met",
    task: task.name,
    debug_tree: {:primitive, task.name, false, condition_results}
  )
end
```

### Example 3: Task Not Found

**Before:**
```elixir
# task_decomposer.ex:55
nil ->
  {:error, "Unknown task: #{inspect(task_name)}", {:empty, task_name, false, []}}
```

**After:**
```elixir
# task_decomposer.ex:55
nil ->
  Jido.HTN.Error.planning_error("Unknown task",
    task: task_name,
    debug_tree: {:empty, task_name, false, []}
  )
end
```

---

## Appendix B: Test Update Examples

### Before (String Matching)

```elixir
test "plan/3 returns error when timeout" do
  assert {:error, "Planning timed out"} = Jido.HTN.plan(@domain, %{}, timeout: 1)
end
```

### After (Type Matching)

```elixir
test "plan/3 returns timeout error when timeout" do
  assert {:error, %Jido.HTN.Error.Timeout{message: "Planning timed out"} = error} =
    Jido.HTN.plan(@domain, %{}, timeout: 1)

  assert error.metadata.timeout == 1
end
```

---

**End of Implementation Plan**

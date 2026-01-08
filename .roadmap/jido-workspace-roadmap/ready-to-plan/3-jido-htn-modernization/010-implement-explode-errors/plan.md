# Implementation Plan: Explode Errors for jido_htn

**Item ID**: `jido-workspace-roadmap/ready-to-plan/3-jido-htn-modernization/010-implement-explode-errors`

**Planning Date**: 2025-01-07

**Status**: Ready for Implementation

---

## Executive Summary

This plan introduces **structured error handling** using Splode to jido_htn, replacing the current simple string-based error system with typed, structured errors that can distinguish between recoverable planning failures and critical validation/domain errors. The implementation follows established patterns from jido, jido_action, and jido_ai libraries.

**Key Architectural Decisions**:
- Use **Splode** for error class hierarchy and structured error types
- **Three error classes**: Planning (non-exploding), Validation (exploding), Domain (exploding)
- Preserve existing **debug tree** functionality within error fields
- Maintain **backward compatibility** during transition period

**Estimated Effort**: 3-4 days
- Phase 1 (Foundation): 0.5 day
- Phase 2 (Core Implementation): 1.5 days
- Phase 3 (Integration & Testing): 1 day
- Phase 4 (Documentation): 0.5 day

---

## Impact Analysis Summary

### Key Findings from Research

The jido_htn project currently uses a **simple tuple-based error system** (`{:error, reason}`) that:
- Lacks structured error types
- Has no error classification
- Provides minimal context in error messages
- Uses mixed strategies (some `raise`, some return tuples)
- Includes debug tree structure only when `debug: true`

### Files Requiring Changes

**Phase 1 - Foundation**:
- `projects/jido_htn/mix.exs` - Add Splode dependency

**Phase 2 - Core Implementation**:
- `projects/jido_htn/lib/jido_htn/error.ex` - **NEW FILE** - Error module with Splode classes

**Phase 3 - Integration**:
- `projects/jido_htn/lib/jido_htn/planner.ex` - Lines 104, 105, 112, 143-150, 183-184, 50
- `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex` - Lines 54, 91-92, 269
- `projects/jido_htn/lib/jido_htn/domain/domain_validation.ex` - Lines 60-68, 92-101, 105-118, 122-142, 287-309
- `projects/jido_htn/lib/jido_htn/domain/domain_builder.ex` - Lines 133, 139

**Phase 4 - Testing**:
- `projects/jido_htn/test/jido_htn/planner_test.exs` - Update error assertions
- `projects/jido_htn/test/jido_htn/domain/builder_test.exs` - Update validation error tests
- `projects/jido_htn/test/jido_htn/domain/validation_test.exs` - Update validation tests

### Existing Patterns to Follow

**Reference Implementations**:
- `projects/jido/lib/jido/error.ex:46-99` - Core Splode pattern with 6 error classes
- `projects/jido_action/lib/jido_action/error.ex:36-42` - Action-specific error classes
- `projects/jido_ai/lib/jido_ai/error.ex:11-18` - AI error classes

**Pattern Template**:
```elixir
defmodule Jido.HTN.Error do
  use Splode,
    error_classes: [planning: Planning, validation: Validation, domain: Domain],
    unknown_error: __MODULE__.Planning.UnknownError

  defmodule Planning do
    use Splode.ErrorClass, class: :planning
  end
  # ... etc
end
```

### Integration Points Identified

1. **Planner Entry Points** (`planner.ex`):
   - `validate_root_tasks!/2` (lines 89-114) - Critical validation → explode
   - `plan/3` (lines 19-56) - Timeout handling → return structured error
   - `do_plan/5` (lines 116-152) - Planning failures → return structured error
   - `do_decompose/9` (lines 154-230) - Decomposition failures → return structured error

2. **Task Decomposition** (`task_decomposer.ex`):
   - `decompose_primitive/5` (lines 60-94) - Precondition checks → return structured error
   - `decompose_compound/8` (lines 96-175) - Method failures → return structured error
   - `try_method/9` (lines 197-271) - Method conditions → return structured error

3. **Domain Validation** (`domain_validation.ex`):
   - Validation pipeline (lines 60-68) - Aggregate errors → explode if any
   - Individual validators (lines 92-309) - Return structured errors for aggregation

4. **Domain Builder** (`domain_builder.ex`):
   - Root task validation (lines 133-140) - Critical validation → explode

---

## Feature Specification

### User Stories

#### US-1: Structured Planning Errors
**As a** developer using jido_htn
**I want** planning failures to return structured error types with context
**So that** I can programmatically handle different failure scenarios

**Acceptance Criteria**:
- Planning errors return `{:error, %Jido.HTN.Error.Planning.*{}}`
- Error includes task name, attempted methods, failure reasons
- Debug tree is preserved in error fields when available
- Error type can be pattern matched for specific handling

#### US-2: Exploding Validation Errors
**As a** developer building an HTN domain
**I want** invalid domain configurations to raise exceptions immediately
**So that** I catch configuration errors during development

**Acceptance Criteria**:
- Invalid domain structure raises `Jido.HTN.Error.Validation.*`
- Root task validation failures raise exceptions (not return tuples)
- Multiple validation errors are aggregated into single exception
- Exception message clearly indicates all validation failures

#### US-3: Error Context Preservation
**As a** developer debugging HTN planning failures
**I want** errors to include rich context (task names, domain state, method paths)
**So that** I can quickly identify the root cause

**Acceptance Criteria**:
- Planning errors include task name and available alternatives
- Precondition failures include condition results and world state
- Timeout errors include partial plan if available
- All errors include stack traces via Splode

### API Contracts

#### Planning API (No Change to Signature)
```elixir
# Existing API - maintained for backward compatibility
@spec plan(Domain.t(), map(), keyword()) ::
        {:ok, [{module(), keyword()}]} |
        {:error, Error.Planning.t()} |
        no_return()  # May raise for validation errors
```

**Error Response Structure**:
```elixir
# Planning failure (returned)
{:error, %Error.Planning.NoValidMethod{
  task: "cook_meal",
  attempted_methods: ["method_1", "method_2"],
  failure_reasons: [...],
  debug_tree: {...}
}}

# Validation failure (raised)
raise Error.Validation.InvalidRootTask,
  message: "Root task 'invalid' not found in domain",
  task: "invalid"
```

### Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                     HTN.plan/3 Entry                        │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │ validate_root_tasks! │  ← Explodes here if invalid
              └──────────┬───────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │   do_plan/5          │
              └──────────┬───────────┘
                         │
         ┌───────────────┴───────────────┐
         │                               │
         ▼                               ▼
┌─────────────────┐           ┌────────────────────┐
│ Planning Errors │           │ Validation Errors  │
│ (Return tuples) │           │ (Raise exceptions) │
└─────────────────┘           └────────────────────┘
```

### State Management Requirements

No state management changes required. Errors are purely informational.

### Error Handling Approach

**Classification Strategy**:

| Error Class | Behavior | Examples |
|-------------|----------|----------|
| **Planning** | Return `{:error, %Error{}}` | No valid method, precondition failed, timeout, max recursion |
| **Validation** | `raise` exception | Invalid domain, invalid root task, duplicate names, invalid method |
| **Domain** | `raise` exception | Missing task, invalid action, callback not found |

**Error Escalation Rules**:
1. **Planning errors** never explode - they're expected during HTN search
2. **Validation errors** always explode - they indicate configuration bugs
3. **Domain errors** always explode - they indicate structural problems

---

## Technical Design

### Data Model Changes

No schema changes required. Errors use Splode's structured error pattern.

### Module Organization

```
jido_htn/
├── lib/
│   └── jido_htn/
│       ├── error.ex                    # NEW - Error module
│       ├── planner.ex                  # MODIFY - Use structured errors
│       ├── domain/
│       │   ├── domain_validation.ex    # MODIFY - Aggregate errors
│       │   └── domain_builder.ex       # MODIFY - Use validation errors
│       └── planner/
│           └── task_decomposer.ex      # MODIFY - Use planning errors
└── test/
    └── jido_htn/
        ├── planner_test.exs            # MODIFY - Update assertions
        └── domain/
            ├── builder_test.exs        # MODIFY - Update assertions
            └── validation_test.exs     # MODIFY - Update assertions
```

### Third-Party Integration

**Splode Dependency**:
```elixir
# mix.exs
defp deps do
  [
    {:splode, "~> 0.2"},
    # ... existing deps
  ]
end
```

### Configuration Changes

No configuration changes required.

---

## Implementation Phases

### Phase 1: Foundation

**Objective**: Set up infrastructure for structured error handling

**Success Criteria**:
- Splode dependency added
- Error module created with all error classes and types
- Module compiles without errors

**Files to Create**:
- `projects/jido_htn/lib/jido_htn/error.ex`

**Files to Modify**:
- `projects/jido_htn/mix.exs`

**Tests to Add**:
- `projects/jido_htn/test/jido_htn/error_test.exs` - **NEW FILE**
  - Test error creation
  - Test error class precedence
  - Test error field access

**Dependencies**: None

**Implementation Tasks**:

1. Add Splode to `mix.exs`:
   ```elixir
   {:splode, "~> 0.2"}
   ```

2. Create `lib/jido_htn/error.ex` with:
   - `use Splode` with 3 error classes
   - `Planning` error class with 5 error types
   - `Validation` error class with 5 error types
   - `Domain` error class with 3 error types
   - Full field specifications for each error type

3. Create basic error tests in `test/jido_htn/error_test.exs`

---

### Phase 2: Core Implementation

**Objective**: Replace string errors with structured errors throughout codebase

**Success Criteria**:
- All error locations use structured errors
- Error messages preserved
- Debug tree information captured in error fields
- All existing tests pass

**Files to Modify**:

#### A. Planner Entry Points
**File**: `projects/jido_htn/lib/jido_htn/planner.ex`

| Lines | Change |
|-------|--------|
| 104 | Replace `ArgumentError` with `Error.Validation.InvalidRootTask` |
| 105 | Replace `ArgumentError` with `Error.Validation.InvalidRootTask` |
| 112 | Replace `ArgumentError` with `Error.Validation.InvalidRootTask` |
| 50 | Replace `{:error, string}` with `{:error, Error.Planning.Timeout}` |
| 143-150 | Replace `{:error, reason, tree}` with `{:error, Error.Planning.NoValidMethod}` |
| 183-184 | Replace `{:error, string}` with `{:error, Error.Planning.MaxRecursionDepth}` |

#### B. Task Decomposer
**File**: `projects/jido_htn/lib/jido_htn/planner/task_decomposer.ex`

| Lines | Change |
|-------|--------|
| 54 | Replace `{:error, string}` with `{:error, Error.Domain.MissingTask}` |
| 91-92 | Replace `{:error, string}` with `{:error, Error.Planning.PreconditionNotMet}` |
| 269 | Replace `{:error, string}` with `{:error, Error.Planning.NoValidMethod}` |

#### C. Domain Validation
**File**: `projects/jido_htn/lib/jido_htn/domain/domain_validation.ex`

| Lines | Change |
|-------|--------|
| 60-68 | Aggregate all errors into `Error.Validation.InvalidDomain` |
| 92-101 | Return structured validation errors |
| 105-118 | Return structured validation errors |
| 122-142 | Return structured validation errors |
| 287-309 | Return structured validation errors |

#### D. Domain Builder
**File**: `projects/jido_htn/lib/jido_htn/domain/domain_builder.ex`

| Lines | Change |
|-------|--------|
| 133 | Replace `ArgumentError` with `Error.Validation.InvalidRootTask` |
| 139 | Replace `ArgumentError` with `Error.Validation.InvalidRootTask` |

**Tests to Update**:
- `projects/jido_htn/test/jido_htn/planner_test.exs`
- `projects/jido_htn/test/jido_htn/domain/builder_test.exs`
- `projects/jido_htn/test/jido_htn/domain/validation_test.exs`

**Dependencies**: Phase 1 complete

**Implementation Tasks**:

1. Update `planner.ex`:
   - Import `Jido.HTN.Error` at top
   - Replace each error location with structured error
   - Preserve error messages in `message:` field
   - Capture context in error fields

2. Update `task_decomposer.ex`:
   - Import `Jido.HTN.Error`
   - Replace string errors with structured errors
   - Include task names, condition results in error fields

3. Update `domain_validation.ex`:
   - Modify validation pipeline to collect all errors
   - Wrap aggregated errors in `Error.Validation.InvalidDomain`
   - Preserve individual error details

4. Update `domain_builder.ex`:
   - Replace `ArgumentError` raises with validation errors
   - Include domain and task context

5. Update test files:
   - Replace `assert_raise ArgumentError, ...` with `assert_raise Error.Validation.*`
   - Replace `assert {:error, reason}` with `assert {:error, %Error.Planning.*{}}`
   - Add pattern matching for error fields

---

### Phase 3: Integration & Testing

**Objective**: Verify error handling works correctly across all scenarios

**Success Criteria**:
- All existing tests pass with structured errors
- New error tests cover all error types
- Error messages are clear and actionable
- Debug tree information is accessible

**Files to Test**:
- All planner tests
- All domain validation tests
- All domain builder tests
- Error-specific tests (new)

**Tests to Add**:

#### Error Type Tests
```elixir
# test/jido_htn/error_test.exs
describe "error classes" do
  test "planning errors don't explode" do
    assert {:error, %Error.Planning.NoValidMethod{}} =
      HTN.plan(invalid_domain, world_state)
  end

  test "validation errors explode" do
    assert_raise Error.Validation.InvalidRootTask, ~r/not found/, fn ->
      HTN.plan(domain, %{}, root_tasks: ["bogus"])
    end
  end

  test "errors include rich context" do
    assert {:error, %Error.Planning.PreconditionNotMet{
      task: task,
      precondition_results: results,
      world_state: state
    }} = HTN.plan(domain, world_state)

    assert is_binary(task)
    assert is_map(results)
    assert is_map(state)
  end

  test "aggregates multiple validation errors" do
    assert {:error, %Error.Validation.InvalidDomain{
      validation_errors: errors
    }} = Domain.build(invalid_builder)

    assert length(errors) > 1
  end
end
```

#### Integration Tests
```elixir
describe "planning with structured errors" do
  test "preserves debug tree in error" do
    assert {:error, %Error.Planning.NoValidMethod{
      debug_tree: tree
    }} = HTN.plan(domain, world_state, debug: true)

    assert is_tuple(tree)
  end

  test "timeout includes partial plan" do
    assert {:error, %Error.Planning.Timeout{
      timeout_ms: timeout,
      partial_plan: plan
    }} = HTN.plan(domain, world_state, timeout: 1)

    assert timeout == 1
    assert is_list(plan)
  end
end
```

**Dependencies**: Phase 2 complete

**Implementation Tasks**:

1. Run full test suite: `mix test`
2. Fix any failing tests
3. Add error-specific tests
4. Verify error messages are clear
5. Test error field access
6. Verify debug tree preservation

---

### Phase 4: Polish & Documentation

**Objective**: Complete documentation and ensure clean implementation

**Success Criteria**:
- All error modules documented
- Migration guide created
- Examples provided for common error handling patterns
- Code reviewed for consistency

**Files to Create**:
- `projects/jido_htn/guides/error_handling.md` - **NEW FILE** - Error handling guide
- `projects/jido_htn/CHANGELOG.md` - **UPDATE** - Add migration notes

**Files to Update**:
- `projects/jido_htn/lib/jido_htn/error.ex` - Add module documentation
- `projects/jido_htn/lib/jido_htn/planner.ex` - Update function docs with error info
- `projects/jido_htn/README.md` - Add error handling section

**Documentation Sections**:

#### Error Module Documentation
```elixir
@moduledoc """
Structured error handling for Jido HTN using Splode.

## Error Classes

### Planning Errors (Returned, Not Raised)
These errors are returned as `{:error, error_struct}` and represent
expected failures during HTN planning:

* `NoValidMethod` - All methods failed for a compound task
* `PreconditionNotMet` - Task precondition failed
* `MaxRecursionDepth` - Hit recursion limit
* `Timeout` - Planning exceeded time limit
* `UnknownTask` - Task not found in domain

### Validation Errors (Raised)
These errors are raised as exceptions and indicate configuration problems:

* `InvalidDomain` - Domain structure invalid
* `InvalidRootTask` - Root task not found or wrong type
* `InvalidMethod` - Method has no subtasks or cycles
* `InvalidCallback` - Callback signature wrong
* `DuplicateNames` - Name conflicts in domain

### Domain Errors (Raised)
These errors are raised as exceptions and indicate structural problems:

* `MissingTask` - Referenced task not defined
* `InvalidAction` - Action not in allowed_workflows
* `CallbackNotFound` - Callback name doesn't exist

## Example

    case Jido.HTN.plan(domain, world_state) do
      {:ok, plan} ->
        # Use plan

      {:error, %Jido.HTN.Error.Planning.NoValidMethod{task: task}} ->
        # Handle planning failure
        IO.puts("No valid method found for task: #{task}")

      {:error, %Jido.HTN.Error.Planning.Timeout{partial_plan: plan}} ->
        # Handle timeout with partial plan
        IO.puts("Planning timed out, using partial plan")
    end
"""
```

#### Migration Guide
```markdown
# Error Handling Migration Guide

## Breaking Changes

The error format has changed from string-based to structured errors.

## Before

```elixir
case Jido.HTN.plan(domain, world_state) do
  {:ok, plan} -> plan
  {:error, reason} -> IO.puts("Error: #{reason}")
end
```

## After

```elixir
case Jido.HTN.plan(domain, world_state) do
  {:ok, plan} -> plan
  {:error, %Error.Planning.NoValidMethod{task: task}} ->
    IO.puts("No method for #{task}")
  {:error, %Error.Planning.Timeout{}} ->
    IO.puts("Planning timed out")
end
```

## Pattern Matching

You can pattern match on specific error types:

```elixir
case result do
  {:error, %Error.Planning.NoValidMethod{} = error} ->
    # Handle no valid method
    # Access error.task, error.attempted_methods, etc.

  {:error, %Error.Planning.PreconditionNotMet{} = error} ->
    # Handle precondition failure
    # Access error.task, error.precondition_results, etc.

  {:error, error} ->
    # Fallback for any error
    IO.puts(Exception.message(error))
end
```
```

**Dependencies**: Phase 3 complete

**Implementation Tasks**:

1. Add comprehensive module documentation
2. Create error handling guide
3. Update README with error handling section
4. Add examples to documentation
5. Update CHANGELOG with migration notes
6. Review code for consistency
7. Final test run: `mix test`

---

## Quality & Testing Strategy

### Test Categories

#### Unit Tests
- **Error creation tests** (test/jido_htn/error_test.exs)
  - Each error type can be created
  - Error fields are accessible
  - Error messages are formatted correctly

#### Integration Tests
- **Planner error tests** (test/jido_htn/planner_test.exs)
  - Planning errors returned correctly
  - Validation errors raised correctly
  - Error context preserved

#### Property-Based Tests
- **Error aggregation tests**
  - Multiple validation errors aggregate correctly
  - Error class precedence works as expected

### Coverage Targets

- **Error module**: 100% coverage
- **Planner error paths**: 95%+ coverage
- **Validation error paths**: 95%+ coverage
- **Overall**: Maintain current coverage levels

### Quality Gates

1. All tests pass: `mix test`
2. No compiler warnings: `mix compile --warnings-as-errors`
3. Formatter check passes: `mix format --check-formatted`
4. Credo checks pass: `mix credo --strict`
5. Documentation compiles: `mix docs`

---

## Risk Assessment

### Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **Splode API changes** | Low | Medium | Pin to specific version (`~> 0.2`) |
| **Breaking existing code** | Medium | High | Provide migration guide; consider backward compatibility layer |
| **Debug tree data loss** | Low | Medium | Add explicit tests for debug tree preservation |
| **Error message clarity** | Medium | Low | Review all error messages with users |

### Dependency Risks

| Risk | Mitigation |
|------|------------|
| **Splode not maintained** | Splode is actively maintained by Ash team; used across Ash ecosystem |
| **Conflicting error types** | Use namespaced error types (`Jido.HTN.Error.*`) |

### Timeline Risks

| Risk | Mitigation |
|------|------------|
| **Underestimated complexity** | Research identified all error locations; clear implementation path |
| **Test update complexity** | Existing tests are well-structured; changes are mechanical |

---

## Success Criteria

### Measurable Outcomes

1. **All error locations use structured errors**
   - 100% of `{:error, string}` replaced with `{:error, %Error{}}`
   - 100% of `raise ArgumentError` replaced with `raise Error.*`

2. **Error handling follows Jido patterns**
   - Consistent with jido, jido_action, jido_ai error patterns
   - Uses same Splode class hierarchy approach

3. **Tests comprehensively cover error paths**
   - All error types have dedicated tests
   - Error field access is tested
   - Error aggregation is tested

4. **Documentation is complete**
   - Error module fully documented
   - Migration guide provided
   - Examples included

### Definition of "Done"

1. Phase 1-4 complete
2. All quality gates pass
3. No regressions in existing functionality
4. Documentation reviewed and approved
5. Migration guide tested with example code

### Acceptance Testing Approach

1. **Manual Testing**:
   - Create test domain with various failure modes
   - Verify error messages are clear
   - Verify error fields contain correct data

2. **Integration Testing**:
   - Test with actual jido actions
   - Verify error handling in real-world scenarios
   - Test error recovery patterns

3. **User Acceptance**:
   - Review error messages with domain experts
   - Validate migration guide with existing users
   - Confirm error types meet use cases

---

## Dependencies

### External Dependencies

- **splode** (~> 0.2) - Structured error handling library
  - Used by: jido, jido_action, jido_ai
  - Maintained by: Ash team
  - License: Apache-2.0

### Internal Jido Dependencies

- **jido** - Reference implementation for error patterns
  - File: `projects/jido/lib/jido/error.ex`
- **jido_action** - Action error pattern reference
  - File: `projects/jido_action/lib/jido_action/error.ex`
- **jido_ai** - AI error pattern reference
  - File: `projects/jido_ai/lib/jido_ai/error.ex`

### Work Item Dependencies

**Depends On**:
- Item 009: "Convert to Zoi error handling" (MUST be complete first)
  - This item assumes Zoi schemas are in place
  - Error field design aligns with Zoi patterns

**Enables**:
- Item 011: "Modernize to current Jido patterns (actions, signals, effects)"
- Item 012: "Define effects for HTN planning/execution"
- Item 013: "Define signals for multi-agent coordination"

---

## References

- **Research Document**: `.roadmap/.../010-implement-explode-errors/research.md`
- **Jido Error Pattern**: `projects/jido/lib/jido/error.ex`
- **Splode Documentation**: https://hexdocs.pm/splode
- **Zoi Documentation**: https://hexdocs.pm/zoi

---

## Appendix: Error Type Reference

### Complete Error Type List

#### Planning Errors (Returned)

```elixir
Error.Planning.NoValidMethod
  fields: [:task, :attempted_methods, :failure_reasons, :debug_tree]

Error.Planning.PreconditionNotMet
  fields: [:task, :precondition_results, :world_state]

Error.Planning.MaxRecursionDepth
  fields: [:depth, :task_path]

Error.Planning.Timeout
  fields: [:timeout_ms, :partial_plan]

Error.Planning.UnknownTask
  fields: [:task, :available_tasks]
```

#### Validation Errors (Raised)

```elixir
Error.Validation.InvalidDomain
  fields: [:validation_errors]

Error.Validation.InvalidRootTask
  fields: [:task, :reason, :domain]

Error.Validation.InvalidMethod
  fields: [:method, :reason]

Error.Validation.InvalidCallback
  fields: [:callback, :reason]

Error.Validation.DuplicateNames
  fields: [:duplicates]
```

#### Domain Errors (Raised)

```elixir
Error.Domain.MissingTask
  fields: [:task, :available_tasks]

Error.Domain.InvalidAction
  fields: [:action, :allowed_workflows]

Error.Domain.CallbackNotFound
  fields: [:callback_name, :available_callbacks]
```

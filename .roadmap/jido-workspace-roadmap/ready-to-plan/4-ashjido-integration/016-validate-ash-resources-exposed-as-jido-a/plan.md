# Implementation Plan: Validate Ash resources exposed as Jido actions

**Item ID:** 016
**Date:** 2026-01-07
**Status:** Ready to Implement

---

## 1. Executive Summary

This implementation validates that Ash Framework resources can be reliably surfaced as Jido actions with predictable behavior across common Ash usage patterns. The ash_jido integration uses a compile-time Spark-based code generation approach that automatically bridges Ash resources to Jido.Action modules.

**Key Architectural Decisions:**
- Create a validation test suite within the `ash_jido` project under `test/validation/`
- Use representative Ash resources that cover common patterns (CRUD, relationships, custom actions)
- Generate a validation matrix documenting support levels for each Ash feature
- Document findings with executable code examples in `VALIDATION_GUIDE.md`

**Effort Estimate:** This is a validation and documentation task with no production code changes. Expected to be completed in a single focused implementation cycle.

---

## 2. Impact Analysis Summary

### Key Research Findings

The ash_jido integration (`projects/ash_jido/`) is well-structured with clear separation of concerns:

| Component | Purpose | Key Files |
|-----------|---------|-----------|
| **Extension Registration** | Spark DSL extension entry point | `lib/ash_jido.ex` |
| **Code Generation** | Compile-time Jido.Action module generation | `lib/ash_jido/generator.ex` |
| **Result Mapping** | Ash result to Jido format conversion | `lib/ash_jido/mapper.ex` |
| **Type Mapping** | Ash types to NimbleOptions schema | `lib/ash_jido/type_mapper.ex` |
| **DSL Definition** | Resource DSL configuration | `lib/ash_jido/resource/dsl.ex` |
| **Transformers** | Compile-time action generation | `lib/ash_jido/resource/transformers/` |

### Files to Create

```
projects/ash_jido/
├── test/validation/
│   ├── validation_test.exs           # Main validation test suite
│   ├── support/
│   │   ├── test_resources.ex         # Representative Ash resources
│   │   ├── test_domain.ex            # Ash domain for test resources
│   │   └── test_agent.ex             # Jido agent test harness
│   └── cases/
│       ├── crud_validation_test.exs  # CRUD operation tests
│       ├── relationship_validation_test.exs  # Relationship tests
│       ├── custom_action_validation_test.exs # Custom action tests
│       └── error_handling_validation_test.exs # Error handling tests
└── VALIDATION_GUIDE.md               # Comprehensive validation matrix
```

### Existing Patterns to Follow

1. **Error Classification Pattern** (`mapper.ex:132-166`): Ash errors are already mapped to Jido error types
2. **Type Conversion Pattern** (`type_mapper.ex:31-93`): Comprehensive Ash type to NimbleOptions mapping exists
3. **Parameter Handling Pattern** (`generator.ex:589-644`): Action-type-specific parameter schemas are defined
4. **Context Management Pattern** (`generator.ex:169-174`): Domain, actor, and tenant context handling

### Integration Points

- **Jido.Actions Base Module**: All generated actions use `Jido.Action` behavior
- **Ash Query Builder**: Read actions use `Ash.Query` for filter construction
- **Ash Changeset**: Create/update/destroy use changeset APIs
- **Ash.Domain**: Resources must be registered in a domain for discovery

---

## 3. Feature Specification

### User Stories

#### US-1: CRUD Validation
As a system integrator, I want to validate that basic CRUD operations work through ash_jido, so that I can confidently use it for simple data management.

**Acceptance Criteria:**
- Create action successfully creates records with valid parameters
- Read action retrieves records with basic filters (id, limit, offset)
- Update action modifies existing records
- Destroy action deletes records
- All actions return `{:ok, result}` or `{:error, %Jido.Error{}}`

#### US-2: Relationship Validation
As a system integrator, I want to understand how Ash relationships behave through Jido actions, so I can design my data model accordingly.

**Acceptance Criteria:**
- Resources with belongs_to relationships can be created
- Resources with has_many relationships can be created
- Related data is accessible in action results
- Validation errors from relationship constraints are properly surfaced

#### US-3: Custom Action Validation
As a system integrator, I want to validate that custom Ash actions work through Jido, so I can expose domain-specific operations.

**Acceptance Criteria:**
- Custom actions with multiple arguments execute correctly
- Custom action return values are properly mapped
- Custom action validations produce appropriate errors

#### US-4: Error Handling Validation
As a system integrator, I want to verify that all Ash error types are converted to Jido errors, so that agents can handle failures gracefully.

**Acceptance Criteria:**
- Authorization errors map to `:authorization_error`
- Validation errors map to `:validation_error`
- Framework errors map to `:system_error`
- Field-level error details are preserved

### API Contracts

#### Input Format
All generated Jido actions accept a map of parameters:
```elixir
params = %{
  field1: "value1",
  field2: 42,
  # ... action-specific parameters
}
```

#### Context Format
Actions require an Ash domain in context:
```elixir
context = %{
  domain: MyApp.Domain,     # Required
  actor: current_user,      # Optional (for authorization)
  tenant: "org_123"        # Optional (for multitenancy)
}
```

#### Output Format
Successful actions return `{:ok, result}` where result is:
```elixir
# Create/Update
%{result: %{id: "...", field: "value"}, action: :create}

# Read
%{results: [...], count: 5}  # or %{result: ...} for single record

# Destroy
%{deleted: true, action: :destroy}

# Custom actions
%{result: <custom_return_value>}
```

Errors return `{:error, %Jido.Error{type: ..., message: ..., details: ...}}`

### State Management

- No persistent state is maintained by ash_jido
- All state is managed by Ash's data layer (ETS, SQL, etc.)
- Context is passed through but not modified

---

## 4. Technical Design

### Data Model

This validation task does not modify the data model. We create temporary test resources:

```elixir
# Simple CRUD resource
defmodule AshJido.Test.Post do
  use Ash.Resource, data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false
    attribute :body, :string
    attribute :published, :boolean, default: false
  end

  actions do
    create :create
    read :read
    update :update
    destroy :destroy
  end

  jido do
    all_actions
  end
end

# Resource with relationships
defmodule AshJido.Test.Comment do
  use Ash.Resource, data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
    attribute :body, :string, allow_nil?: false
  end

  relationships do
    belongs_to :post, AshJido.Test.Post
  end

  jido do
    all_actions
  end
end

# Resource with custom actions and validations
defmodule AshJido.Test.User do
  use Ash.Resource, data_layer: Ash.DataLayer.Ets

  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false
    attribute :age, :integer
  end

  validations do
    validate {AshJido.Test.Validations.Email, attribute: :email}
    validate {AshJido.Test.Validations.AgeRange, attribute: :age}
  end

  actions do
    create :create
    read :read

    action :send_welcome_email do
      argument :template, :string, allow_nil?: true
      run {AshJido.Test.Actions.SendWelcomeEmail, argument: :template}
    end
  end

  jido do
    all_actions
  end
end
```

### Module Organization

```
projects/ash_jido/test/validation/
├── validation_test.exs              # Entry point - runs all validation cases
├── support/
│   ├── test_resources.ex            # Test resource definitions
│   ├── test_domain.ex               # Domain registering test resources
│   ├── test_agent.ex                # Agent execution harness
│   ├── assertions.ex                # Custom validation assertions
│   └── helpers.ex                   # Test helpers and fixtures
└── cases/
    ├── crud_validation_test.exs     # Test suite for CRUD operations
    ├── relationship_validation_test.exs
    ├── custom_action_validation_test.exs
    ├── validation_error_test.exs
    ├── authorization_test.exs
    └── multitenancy_test.exs
```

### Third-Party Integration

No new dependencies. This validates existing integrations:
- **Ash Framework** (>= 3.0)
- **Jido.Actions** (from jido project)
- **Spark** (for DSL extension)

### Configuration/Environment

Test configuration in `test/test_helper.exs`:
```elixir
# Ensure ETS data layer is available
Application.put_env(:ash, :missed_reference_migrations, :ignore)

# Start test domain
{:ok, _} = AshJido.Test.Domain.start_link()
```

---

## 5. Implementation Phases

### Phase 1: Test Infrastructure Setup

**Objective:** Create the foundation for validation testing

**Success Criteria:**
- Test resources compile and are registered in test domain
- Agent test harness can execute Jido actions
- Validation assertions are available

**Files to Create:**
- `test/validation/support/test_resources.ex` (150 lines)
- `test/validation/support/test_domain.ex` (30 lines)
- `test/validation/support/test_agent.ex` (80 lines)
- `test/validation/support/assertions.ex` (60 lines)
- `test/validation/support/helpers.ex` (50 lines)

**Tests to Add:**
- Smoke test: Verify test resources are accessible via Ash
- Smoke test: Verify Jido actions are generated for test resources
- Smoke test: Verify agent harness can execute actions

**Dependencies:** None

**Acceptance Testing:**
```bash
cd projects/ash_jido
mix test test/validation/support
# All smoke tests pass
```

---

### Phase 2: CRUD Operation Validation

**Objective:** Validate basic CRUD operations work correctly

**Success Criteria:**
- All CRUD operations execute successfully with valid parameters
- Invalid parameters produce appropriate Jido errors
- Parameter type coercion works correctly
- Results are properly formatted as maps

**Files to Create:**
- `test/validation/cases/crud_validation_test.exs` (300 lines)

**Tests to Add:**

1. **Create Action Tests:**
   - Create with all required fields succeeds
   - Create with missing required fields returns validation error
   - Create with invalid types returns validation error
   - Returned result contains created record as map
   - UUID primary key is generated

2. **Read Action Tests:**
   - Read without filters returns all records (paginated)
   - Read with id filter returns specific record
   - Read with limit/offset applies pagination
   - Read with non-existent id returns empty list
   - Results are maps (not structs)

3. **Update Action Tests:**
   - Update with valid id and fields succeeds
   - Update with invalid id returns not found error
   - Update with invalid fields returns validation error
   - Only specified fields are updated
   - Returned result contains updated record

4. **Destroy Action Tests:**
   - Destroy with valid id deletes record
   - Destroy with invalid id returns not found error
   - Destroy returns success confirmation

**Dependencies:** Phase 1

**Acceptance Testing:**
```bash
mix test test/validation/cases/crud_validation_test.exs
# All CRUD tests pass
```

---

### Phase 3: Relationship & Complex Pattern Validation

**Objective:** Validate advanced Ash patterns through Jido

**Success Criteria:**
- Resources with relationships can be created
- Related data is accessible in results
- Custom actions execute correctly
- Validations produce field-specific errors

**Files to Create:**
- `test/validation/cases/relationship_validation_test.exs` (200 lines)
- `test/validation/cases/custom_action_validation_test.exs` (150 lines)
- `test/validation/cases/validation_error_test.exs` (200 lines)

**Tests to Add:**

1. **Relationship Tests:**
   - Create resource with belongs_to relationship
   - Create resource with has_many relationship
   - Nested relationship handling
   - Relationship validation errors

2. **Custom Action Tests:**
   - Custom action with no arguments
   - Custom action with multiple arguments
   - Custom action returning custom data
   - Custom action raising errors

3. **Validation Error Tests:**
   - Built-in Ash validations (format, length, inclusion)
   - Custom validation modules
   - Field-specific error messages
   - Multiple validation errors at once

**Dependencies:** Phase 2

**Acceptance Testing:**
```bash
mix test test/validation/cases/relationship_validation_test.exs
mix test test/validation/cases/custom_action_validation_test.exs
mix test test/validation/cases/validation_error_test.exs
# All tests pass
```

---

### Phase 4: Authorization, Multitenancy & Edge Cases

**Objective:** Validate advanced features and edge cases

**Success Criteria:**
- Authorization policies are enforced
- Multitenancy context is respected
- All Ash error types map to Jido errors
- Edge cases are documented

**Files to Create:**
- `test/validation/cases/authorization_test.exs` (150 lines)
- `test/validation/cases/multitenancy_test.exs` (100 lines)
- `test/validation/edge_cases_test.exs` (150 lines)

**Tests to Add:**

1. **Authorization Tests:**
   - Action without actor passes
   - Action with authorized actor passes
   - Action with unauthorized actor returns `:authorization_error`
   - Policy-specific error details are preserved

2. **Multitenancy Tests:**
   - Create with tenant context stores in tenant
   - Read with tenant context only returns tenant records
   - Update/destroy respect tenant boundaries
   - Tenant context is required for tenant resources

3. **Edge Case Tests:**
   - Concurrent modification handling
   - Large result sets (pagination)
   - Special characters in strings
   - Null value handling
   - Array/map parameter handling

**Dependencies:** Phase 3

**Acceptance Testing:**
```bash
mix test test/validation/cases/authorization_test.exs
mix test test/validation/cases/multitenancy_test.exs
mix test test/validation/edge_cases_test.exs
# All tests pass
```

---

### Phase 5: Documentation & Validation Matrix

**Objective:** Document findings and create validation matrix

**Success Criteria:**
- VALIDATION_GUIDE.md is comprehensive
- Validation matrix documents all tested features
- Code examples are provided for each pattern
- Known limitations are clearly stated

**Files to Create:**
- `VALIDATION_GUIDE.md` (500 lines)

**Documentation Structure:**

```markdown
# Ash.Jido Validation Guide

## Executive Summary
[Brief overview of validation results]

## Validation Matrix

| Feature | Support Level | Notes | Test Reference |
|---------|---------------|-------|----------------|
| Simple CRUD | Fully Supported | All operations tested | `CrudValidationTest` |
| Relationships | Partially Supported | Belongs_to works, has_many needs manual loading | `RelationshipValidationTest` |
| Custom Actions | Fully Supported | - | `CustomActionValidationTest` |
| Validations | Fully Supported | Field errors preserved | `ValidationErrorTest` |
| Authorization | Fully Supported | Actor context respected | `AuthorizationTest` |
| Multitenancy | Fully Supported | Tenant context respected | `MultitenancyTest` |
| Bulk Operations | Not Supported | Requires manual implementation | N/A |
| Aggregates | Unknown | Not yet tested | Future work |
| Calculations | Unknown | Not yet tested | Future work |

## Usage Examples

### Basic CRUD
```elixir
# Example code
```

### With Relationships
```elixir
# Example code
```

### Custom Actions
```elixir
# Example code
```

### Error Handling
```elixir
# Example code
```

## Known Limitations

1. **Relationship Loading**: Related entities are not automatically loaded in results
2. **Bulk Operations**: No support for bulk create/update/destroy
3. **Complex Queries**: Only basic id/limit/offset filters supported

## Recommendations

[If any inconsistencies found, propose API adjustments]

## Test Execution

```bash
cd projects/ash_jido
mix test test/validation
```
```

**Dependencies:** Phase 4

**Acceptance Testing:**
- Documentation review by team
- All code examples execute successfully
- Validation matrix is accurate

---

## 6. Quality & Testing Strategy

### Test Categories

1. **Unit Tests**: Individual action behavior
   - Parameter validation
   - Error mapping
   - Result formatting

2. **Integration Tests**: Full action execution
   - End-to-end Ash → Jido flow
   - Context passing
   - Domain discovery

3. **Property-Based Tests** (optional):
   - Random parameter generation
   - Type coercion boundaries

### Coverage Targets

- **Line Coverage**: 90%+ for ash_jido code execution paths
- **Branch Coverage**: 85%+ for error handling branches
- **Feature Coverage**: 100% of documented Ash features in matrix

### Quality Gates

1. All tests pass
2. Validation matrix is complete
3. Code examples execute without errors
4. Documentation is reviewed
5. No critical bugs found

---

## 7. Risk Assessment

### Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Ash version incompatibility | Low | Medium | Pin Ash version in test suite |
| Relationship loading complexity | Medium | Low | Document current behavior, defer complex cases |
| Error mapping gaps | Low | Low | Add custom error converters as needed |

### Dependency Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Jido.Action API changes | Low | Medium | Pin jido version in mix.exs |
| Ash DSL changes | Low | Low | Use stable Ash 3.x features |

### Timeline Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Test resource complexity underestimated | Medium | Low | Start with simple resources, add complexity incrementally |
| Documentation scope creep | Medium | Low | Focus on validation matrix first, examples second |

---

## 8. Success Criteria

### Measurable Outcomes

1. **Test Suite**: 50+ test cases covering all major Ash patterns
2. **Validation Matrix**: 100% of tested features documented
3. **Code Examples**: 10+ executable examples
4. **Bug Discovery**: Identify and document any inconsistencies

### Definition of Done

- [ ] All validation tests pass
- [ ] VALIDATION_GUIDE.md is complete
- [ ] Validation matrix documents all tested features
- [ ] Code examples execute successfully
- [ ] Known limitations are documented
- [ ] Recommendations are proposed (if issues found)
- [ ] Team review is completed

### Acceptance Testing Approach

1. **Automated**: Run full test suite
2. **Manual**: Execute code examples from guide
3. **Review**: Team reviews validation matrix
4. **Sign-off**: Product owner approves findings

---

## Execution Checklist

### Phase 1: Test Infrastructure
- [ ] Create test resource definitions
- [ ] Create test domain
- [ ] Create agent test harness
- [ ] Write smoke tests
- [ ] Verify test infrastructure works

### Phase 2: CRUD Validation
- [ ] Write create action tests
- [ ] Write read action tests
- [ ] Write update action tests
- [ ] Write destroy action tests
- [ ] Verify all CRUD tests pass

### Phase 3: Advanced Patterns
- [ ] Write relationship tests
- [ ] Write custom action tests
- [ ] Write validation error tests
- [ ] Verify all advanced tests pass

### Phase 4: Edge Cases
- [ ] Write authorization tests
- [ ] Write multitenancy tests
- [ ] Write edge case tests
- [ ] Verify all edge case tests pass

### Phase 5: Documentation
- [ ] Create VALIDATION_GUIDE.md
- [ ] Populate validation matrix
- [ ] Add code examples
- [ ] Document limitations
- [ ] Write recommendations (if any)
- [ ] Review documentation

---

## References

- **Ash Documentation**: https://hexdocs.pm/ash/
- **Jido Actions**: `projects/jido/lib/jido_action/`
- **ash_jido Source**: `projects/ash_jido/`
- **Research Findings**: `.roadmap/.../016/research.md`

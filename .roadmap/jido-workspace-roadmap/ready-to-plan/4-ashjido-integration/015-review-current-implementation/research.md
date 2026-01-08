# Research: Review Current ash_jido Implementation

**Item ID**: `jido-workspace-roadmap/ready-to-plan/4-ashjido-integration/015-review-current-implementation`

**Date**: 2026-01-07

---

## Executive Summary

The `ash_jido` project (v0.1.0, EXPERIMENTAL) provides a clean, functional integration between Ash resources and Jido actions. The implementation uses Spark DSL extensions to automatically generate `Jido.Action` modules from Ash resource definitions. The codebase is well-architected with good test coverage and proper context handling for authorization and multi-tenancy.

**Status**: Functional for basic CRUD, needs stabilization work for advanced use cases.

---

## Project Location and Status

- **Path**: `projects/ash_jido/`
- **Repository**: `git@github.com:agentjido/ash_jido.git`
- **Branch**: `main`
- **Version**: `0.1.0` (EXPERIMENTAL)

### Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| `ash` | `~> 3.5` | Ash Framework integration |
| `jido` | `~> 1.1` | Jido agent framework |
| `usage_rules` | `~> 0.1` | Dev - best practices linting |
| `igniter` | `~> 0.6` | Dev/test - code generation |

---

## Module Structure Overview

```
/projects/ash_jido/
├── lib/ash_jido/
│   ├── ash_jido.ex                      # Main extension module
│   ├── resource/
│   │   ├── dsl.ex                       # DSL section definitions
│   │   ├── jido_action.ex               # JidoAction struct
│   │   ├── all_actions.ex               # AllActions struct
│   │   └── transformers/
│   │       └── generate_jido_actions.ex # Spark transformer
│   ├── generator.ex                     # Code generation logic
│   ├── mapper.ex                        # Result mapping (struct->map)
│   └── type_mapper.ex                   # Ash type -> NimbleOptions mapping
├── test/                                # 10 test files
├── README.md                            # User documentation
├── usage-rules.md                       # Best practices
└── PLAN.md                              # Implementation plan
```

---

## Core Integration Patterns

### 1. Extension Registration

Users add `extensions: [AshJido]` to Ash resource definitions:

```elixir
use Ash.Resource,
  domain: MyApp.Blog,
  extensions: [AshJido]
```

### 2. DSL Configuration

Two configuration entities:

**`action`** - Expose individual Ash actions:
- `action` - Ash action name to expose
- `name` - Custom Jido action name (optional, auto-generated)
- `module_name` - Custom module name (optional)
- `description`, `tags` - Documentation
- `output_map?` - Convert structs to maps (default: true)
- `pagination?` - Include pagination params (default: true, not implemented)

**`all_actions`** - Bulk exposure with filtering:
- `except` - Exclude specific actions
- `only` - Include only specified actions
- `tags` - Additional tags for all

### 3. Compile-Time Generation

The Spark transformer (`AshJido.Resource.Transformers.GenerateJidoActions`) runs after Ash validation:

1. Extract `jido` entities from DSL state
2. Expand `all_actions` into individual `JidoAction` structs
3. Generate action modules via `Generator.generate_jido_action_module/3`
4. Persist module list in DSL state

### 4. Context Flow

Generated `Jido.Action.run/2` extracts context:

```elixir
def run(params, context) do
  actor = context[:actor]      # Authorization
  tenant = context[:tenant]    # Multi-tenancy
  domain = context[:domain]    # REQUIRED - Ash domain

  # ... execute with context
end
```

**Actor Flow**:
- Create: `Ash.Changeset.for_create(resource, action, params, actor: actor)`
- Read: `Ash.Query.set_context(query, %{actor: actor, tenant: tenant})`
- Update: `Ash.Changeset.for_update(..., actor: actor)`
- Destroy: `Ash.Changeset.for_destroy(..., actor: actor)`

### 5. Smart Naming Convention

Auto-generated action names:
- Creates: `"create_#{resource}"`
- Reads: `"get_#{resource}"`, `"list_#{plural(resource)}"`
- Updates: `"update_#{resource}"`
- Destroys: `"destroy_#{resource}"`
- Custom actions use action name

### 6. Type Mapping

Ash types mapped to NimbleOptions schemas:
- `Ash.Type.String` → `:string`
- `Ash.Type.Integer` → `:integer`
- `Ash.Type.Decimal` → `:float`
- `Ash.Type.UUID` → `:string`
- `Ash.Type.DateTime` → `:string`
- `{:array, inner_type}` → `{:list, inner_type}`
- Unknown types → `:map`

### 7. Error Handling

Ash errors wrapped and classified:

| Ash Error | Wrapped As |
|-----------|------------|
| `Ash.Error.Forbidden` | `:authorization_error` |
| `Ash.Error.Invalid` | `:validation_error` |
| `Ash.Error.Framework` | `:system_error` |
| `Ash.Error.Unknown` | `:execution_error` |

Field-level details preserved.

---

## Testing Coverage

**Test Files** (10 total):
1. `ash_jido_test.exs` - Version and extension validation
2. `generator_test.exs` - Code generation
3. `mapper_test.exs` - Result mapping
4. `type_mapper_test.exs` - Type mapping
5. `resource_test.exs` - DSL configuration
6. `transformers/generate_jido_actions_test.exs` - Transformer logic
7. `integration/ash_jido_integration_test.exs` - End-to-end
8. `enhanced_generator_test.exs` - Advanced scenarios
9. `module_name_override_test.exs` - Custom naming
10. `test_domain_test.exs` - Domain configuration

**Coverage**: Strong - includes unit, integration, and edge cases

---

## Strengths

1. **Clean Architecture**: Well-separated concerns (DSL, generation, mapping, types)
2. **Smart Defaults**: Intelligent naming reduces configuration burden
3. **Comprehensive Types**: Handles all Ash types with extensibility
4. **Robust Errors**: Proper error wrapping with detail preservation
5. **Good Tests**: 10 test files covering key scenarios
6. **Documentation**: README, usage rules, inline examples
7. **Context-Aware**: Proper actor, tenant, domain handling
8. **Flexible Naming**: Custom module naming with sensible defaults
9. **Type Safety**: NimbleOptions schemas for validation
10. **Bulk Operations**: `all_actions` for rapid setup

---

## Gaps and Technical Debt

### High Priority Issues

#### 1. Read Action Arguments Not Applied
- **Location**: `lib/ash_jido/generator.ex:388-416`
- **Issue**: `maybe_apply_filters/2` only handles `id`, `limit`, `offset`
- **Gap**: Action-specific arguments not applied to query filters
- **Example**: `by_email` read action with `email` argument - email not applied as filter

#### 2. Composite Primary Keys Not Supported
- **Location**: `lib/ash_jido/generator.ex:200-251`
- **Issue**: Update/destroy require single `id` parameter
- **Gap**: Does not handle multi-column primary keys
- **Assumption**: Single UUID/string primary key

#### 3. Incomplete Type Mapping
- **Location**: `lib/ash_jido/type_mapper.ex:31-93`
- **Issue**: `Ash.Type.UtcDateTime` falls through to `:map`
- **Gap**: Some Ash types not explicitly handled

#### 4. Limited Error Classification
- **Location**: `lib/ash_jido/mapper.ex:132-166`
- **Issue**: Only 4 Ash error types mapped
- **Gap**: Missing `Ash.Error.Changeset` and other subclasses

#### 5. Pagination Not Implemented
- **Location**: `lib/ash_jido/generator.ex:82`
- **Issue**: `pagination?: true` option exists but not used
- **Missing**: Cursor-based, keyset pagination support

### Medium Priority Issues

#### 6. No Hex Package Configuration
- **Location**: `config/workspace.exs:197-242`
- **Gap**: `ash_jido` not in hex_packages list
- **Impact**: Cannot publish to Hex as part of version train

#### 7. Generic Output Schemas
- **Location**: `lib/ash_jido/generator.ex:556-587`
- **Issue**: Output schemas don't reflect actual resource attributes
- **Gap**: AI tools cannot infer return structure accurately

#### 8. No Bulk Operations
- **Gap**: No bulk create/update/delete actions
- **Missing**: Batch operations, streaming

#### 9. Test-Only Module Recompilation
- **Location**: `lib/ash_jido/generator.ex:28-48`
- **Issue**: Recompilation check only in test environment
- **Gap**: Production may have stale compiled modules

### Low Priority Issues

#### 10. Ad Hoc String Key Normalization
- **Location**: `lib/ash_jido/generator.ex:342-357`
- **Issue**: Unsafe `String.to_existing_atom/1` with fallback
- **Pattern**: Workaround for JSON inputs

---

## Experimental / Ad Hoc Code

1. **Test-Only Recompilation** (`generator.ex:33-43`):
   ```elixir
   if Mix.env() == :test do
     # Recompile check only in test
   end
   ```
   Workaround for test module reloading.

2. **String Key Normalization** (`generator.ex:342-357`):
   ```elixir
   defp normalize_param_keys(params) when is_map(params) do
     # Converts string keys to atoms
   rescue
     ArgumentError -> params
   end
   ```
   Unsafe atom conversion with rescue fallback.

3. **Generic Read Filters** (`generator.ex:388-416`):
   Only handles `id`, `limit`, `offset` - not action-specific.

---

## Compatibility Notes

**Ash Version**: `~> 3.5`
- Compatible with Ash 3.5.x DSL
- Uses Spark extension system
- Relies on `Ash.Info.domains_and_resources/1`

**Jido Version**: `~> 1.1`
- Uses `Jido.Action` behavior
- Expects `run/2` interface

**Elixir**: `~> 1.18`

**Potential Issues**:
- Ash 4.0 changes may break compatibility
- Jido 2.0 (v2 branch) may have different `Jido.Action` interface
- No explicit version testing matrix

---

## Edge Cases Identified

1. **Multiple Domains**: Warns but uses first found
2. **No Domain**: Raises helpful error with configuration example
3. **Missing ID in Update/Destroy**: Validates and raises `ArgumentError`
4. **Nested Resources**: Converts recursively but not deeply tested
5. **Custom Types**: Falls back to `:map` if no `storage_type/0`
6. **Empty Jido Section**: Returns empty module list
7. **Non-Ash Structs**: Returned as-is (not converted)
8. **Array of Arrays**: Handles nested arrays
9. **Module Name Conflicts**: No conflict detection

---

## Adoption Ease Assessment

**Easy Aspects**:
- Simple DSL: `extensions: [AshJido]`
- Minimal configuration for basic usage
- Comprehensive README
- Example resources in tests

**Challenging Aspects**:
- Understanding domain requirement
- Action-specific query parameters not applied
- Debugging generated modules

**Missing for Adoption**:
- Mix tasks for scaffolding
- Getting started guide
- Video tutorials
- Example application
- Hex package

---

## Concrete Follow-Up Tasks for Stabilization

### High Priority

1. **Implement Read Action Arguments**
   - Apply action arguments to query filters
   - Support complex filter expressions
   - File: `lib/ash_jido/generator.ex:388-416`

2. **Add Composite Primary Key Support**
   - Handle multi-column primary keys in update/destroy
   - File: `lib/ash_jido/generator.ex:200-251`

3. **Complete Type Mapping**
   - Add `Ash.Type.UtcDateTime` explicit mapping
   - Handle all Ash 3.5 types
   - File: `lib/ash_jido/type_mapper.ex:31-93`

4. **Expand Error Classification**
   - Map all Ash error subclasses
   - Add `Ash.Error.Changeset` handling
   - File: `lib/ash_jido/mapper.ex:132-166`

5. **Implement Pagination**
   - Add cursor/keyset pagination support
   - Honor `pagination?:` option
   - File: `lib/ash_jido/generator.ex:190-198`

### Medium Priority

6. **Add Hex Package Configuration**
   - Add to `config/workspace.exs` hex_packages
   - Configure publish_order and dependencies

7. **Improve Output Schemas**
   - Generate actual attribute-based output schemas
   - Include relationship output structures
   - File: `lib/ash_jido/generator.ex:556-587`

8. **Add Bulk Operation Support**
   - Bulk create/update/delete actions
   - Streaming for large result sets

9. **Fix Module Recompilation**
   - Implement proper module cache invalidation
   - Remove test-only recompilation check
   - File: `lib/ash_jido/generator.ex:28-48`

10. **Add Validation Helpers**
    - Domain validation at compile time
    - Action existence verification
    - Module name conflict detection

### Low Priority

11. **Create Mix Tasks**
    - `mix ash_jido.gen.resource`
    - `mix ash_jido.gen.agent`
    - `mix ash_jido.validate`

12. **Improve Documentation**
    - Getting started guide
    - Example application
    - API reference with examples

13. **Add Telemetry**
    - Execution metrics
    - Error tracking
    - Performance monitoring

14. **Version Compatibility Testing**
    - Ash 3.4, 3.5, 3.6 testing matrix
    - Jido 1.0, 1.1, 2.0 compatibility

15. **Create Demo Application**
    - Simple CRUD app
    - Multi-tenant example
    - Policy demonstration

---

## Files Identified for Potential Changes

| File | Lines | Purpose | Change Type |
|------|-------|---------|-------------|
| `lib/ash_jido/generator.ex` | 83-478 | Main code generation | High |
| `lib/ash_jido/generator.ex` | 388-416 | Read filter application | High |
| `lib/ash_jido/generator.ex` | 200-251 | Update/destroy ID handling | High |
| `lib/ash_jido/type_mapper.ex` | 20-93 | Type mapping | High |
| `lib/ash_jido/mapper.ex` | 132-166 | Error classification | High |
| `lib/ash_jido/generator.ex` | 556-587 | Output schemas | Medium |
| `lib/ash_jido/generator.ex` | 28-48 | Module recompilation | Medium |
| `config/workspace.exs` | 197-242 | Hex package config | Medium |

---

## Summary

**Overall Assessment**: The ash_jido implementation is **well-architected and functional** with a clean separation of concerns, comprehensive type mapping, and good test coverage.

**Production Readiness**: **Medium-High** - Works well for basic CRUD, but needs stabilization for advanced use cases.

**Technical Debt**: **Low** - Clean code with no TODOs/FIXMEs, but some incomplete features.

**Key Strengths**: Smart defaults, flexible DSL, proper context handling, robust error conversion.

**Primary Gaps**: Incomplete read action argument application, missing pagination, limited error classification, no Hex package configuration.

**Recommended Next Steps**:
1. Prioritize the 5 high-priority stabilization tasks
2. Add Hex package configuration for publishing
3. Create a demo application for user onboarding

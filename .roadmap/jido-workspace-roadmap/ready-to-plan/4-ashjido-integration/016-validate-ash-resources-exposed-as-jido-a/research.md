# Research: Validate Ash resources exposed as Jido actions

**Item ID:** 016
**Date:** 2026-01-07

## Overview

This item requires validating that Ash resources and actions can be reliably surfaced as Jido actions with predictable behavior across common Ash usage patterns.

## Key Findings

### Current Architecture

The `ash_jido` integration (located at `projects/ash_jido/`) uses a **Spark-based extension approach**:

1. **Extension Registration**: Ash resources add `extensions: [AshJido]` to enable integration
2. **DSL Integration**: Adds a `jido` section to Ash resources
3. **Compile-time Generation**: Spark transformers generate Jido.Action modules at compile time
4. **Runtime Mapping**: Bridges Ash actions to Jido.Action interfaces

### Integration Flow

```
Ash Resource (with jido DSL)
    ↓
Spark Transformer (GenerateJidoActions)
    ↓
Jido.Action Module Generator
    ↓
Runtime Execution (Jido → Ash mapping)
```

## Key Files and Modules

| Module | Path | Purpose |
|--------|------|---------|
| `AshJido` | `lib/ash_jido.ex` | Main extension entry point |
| `AshJido.Generator` | `lib/ash_jido/generator.ex` | Generates Jido.Action modules |
| `AshJido.Mapper` | `lib/ash_jido/mapper.ex` | Maps Ash results to Jido format |
| `AshJido.TypeMapper` | `lib/ash_jido/type_mapper.ex` | Converts Ash types to NimbleOptions |
| `AshJido.Resource.Dsl` | `lib/ash_jido/resource/dsl.ex` | Defines DSL schema |
| `AshJido.Resource.Transformers.GenerateJidoActions` | `lib/ash_jido/resource/transformers/generate_jido_actions.ex` | Compile-time transformer |

## Supported Ash Resource Patterns

### CRUD Operations
- **Create**: `Ash.Changeset.for_create/4` → `Ash.create()`
- **Read**: `Ash.Query` with filters → `Ash.read()`
- **Update**: `Ash.Changeset.for_update/4` → `Ash.update()`
- **Destroy**: `Ash.Changeset.for_destroy/4` → `Ash.destroy()`
- **Custom Actions**: `Ash.run_action/2`

### DSL Configuration Options

```elixir
jido do
  action :create,
    name: "custom_name",
    description: "Custom description",
    tags: ["ai-discovery"],
    output_map?: true,
    pagination?: true

  all_actions except: [:internal]
  all_actions only: [:read, :create]
end
```

## Parameter Mapping

### Type Conversion (TypeMapper)

| Ash Type | Jido/NimbleOptions Type |
|----------|------------------------|
| `Ash.Type.String` | `:string` |
| `Ash.Type.Integer` | `:integer` |
| `Ash.Type.Float` | `:float` |
| `Ash.Type.Boolean` | `:boolean` |
| `Ash.Type.UUID` | `:string` |
| `Ash.Type.DateTime` | `:string` |
| `Ash.Type.Decimal` | `:float` |
| `{:array, inner_type}` | `{:list, mapped_type}` |
| (fallback) | `:map` |

### Parameter Handling by Action Type

- **Create actions**: Use Ash action arguments as parameters
- **Read actions**: Add `id`, `limit`, `offset` filters
- **Update actions**: Require `id` + action arguments
- **Destroy actions**: Require `id`
- **Custom actions**: Use action-specific arguments

## Error Handling Patterns

### Error Classification

```elixir
Ash.Error.Forbidden  → :authorization_error
Ash.Error.Invalid    → :validation_error
Ash.Error.Framework  → :system_error
Ash.Error.Unknown    → :execution_error
```

### Error Flow

1. Ash operation raises exception
2. `try/rescue` captures error
3. `AshJido.Mapper.convert_ash_error_to_jido_error/1` converts
4. Error wrapped with `Jido.Error` structure
5. Returns `{:error, %Jido.Error{}}`

## Integration Points

### Context Requirements

```elixir
context = %{
  domain: MyApp.Domain,  # Required
  actor: current_user,   # Optional (for authorization)
  tenant: "org_123"     # Optional (for multitenancy)
}
```

### Module Naming Convention

- Default: `Resource.Jido.ActionName`
- Example: `MyApp.User.Jido.Register`
- Custom naming supported via DSL

## Identified Gaps for Validation

### Current Limitations

1. **Relationship Support**: No explicit handling of Ash relationships
2. **Complex Queries**: Limited filter support beyond basic parameters
3. **Bulk Operations**: No batch operations support
4. **Advanced Pagination**: Basic only (limit/offset)
5. **Custom Error Types**: Limited to Ash.Error classes

### Validation Test Cases Needed

1. **Simple CRUD**: Basic create, read, update, destroy operations
2. **Resources with Relationships**: Test managing related data through Jido
3. **Custom Actions**: Actions with multiple arguments and complex logic
4. **Validations**: How changeset errors are surfaced
5. **Authorization**: Policy violations and permission errors
6. **Multi-tenancy**: Tenant context handling
7. **Different Data Layers**: ETS vs SQL vs other data layers

## Deliverable Structure

The validation matrix should document:

| Ash Feature | Support Level | Notes |
|-------------|---------------|-------|
| Simple CRUD | ✓ Fully Supported | - |
| Relationships | ? | Needs validation |
| Custom Actions | ✓ Supported | Via DSL configuration |
| Validations | ✓ Supported | Errors mapped to Jido.Error |
| Authorization | ✓ Supported | Actor context passed |
| Multi-tenancy | ✓ Supported | Tenant context supported |
| Bulk Operations | ✗ Unsupported | - |
| Aggregates | ? | Needs validation |
| Calculations | ? | Needs validation |

## Next Steps for Implementation

1. Create representative Ash resources covering each pattern
2. Build Jido agent test harness
3. Execute validation matrix test cases
4. Document findings with code examples
5. Propose API adjustments for any inconsistencies found

## References

- Ash Documentation: https://hexdocs.pm/ash/
- Jido Actions: `projects/jido/lib/jido_action/`
- ash_jido Source: `projects/ash_jido/`

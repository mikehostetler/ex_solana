# Jido HTN → Zoi Schema Migration Research

## Executive Summary

This research document provides a comprehensive analysis for migrating `jido_htn` from raw Elixir structs to Zoi schemas. This migration aligns with the broader Jido ecosystem's move toward validated, type-safe data structures.

**Key Finding**: The migration is straightforward but requires careful attention to:
1. Maintaining backward compatibility with existing APIs
2. Preserving function types (preconditions, effects, callbacks)
3. Adding Zoi as a dependency to `jido_htn`
4. Updating test patterns for struct construction

**Estimated Effort**: M (3-5 hours) for core structs; additional time for comprehensive testing

---

## 1. Project Dependencies Discovered

### From `projects/jido/mix.exs`:
- **zoi**: `~> 0.14` (currently using 0.14.1 in mix.lock)
- **jido**: Uses Zoi schemas extensively for agent state, directives, options
- **jido_action**: Uses Zoi schemas for action/tool validation

### From `projects/jido_htn/mix.exs`:
Current dependencies do NOT include Zoi - must be added:
```elixir
{:zoi, "~> 0.14"}  # NEW - needs to be added
```

### Current `jido_htn` Dependencies:
- `deep_merge` ~> 1.0 - Used for merging maps
- `proper_case` ~> 1.3 - Used for case conversion in helpers
- `private` ~> 0.1.2 - Used for private function macros
- `jido` - Local path dependency (already has Zoi)
- `jido_action` - Local path dependency (already has Zoi)

### Authentication approach:
- None (jido_htn is a library, not an application)

### Background jobs:
- None (uses standard Elixir processes)

### Testing framework:
- **ExUnit** with these patterns:
  - `use ExUnit.Case, async: true`
  - `@moduletag :capture_log` for suppressing logs
  - Direct struct construction in tests

---

## 2. Files Requiring Changes

### Core Struct Definitions

#### `lib/jido_htn/primitive_task.ex:26-36`
**Current**: Raw defstruct
```elixir
defstruct [
  :name,
  :task,
  :cost,
  :duration,
  :scheduling_constraints,
  preconditions: [],
  effects: [],
  expected_effects: [],
  background: false
]
```

**Migration to Zoi**:
```elixir
@schema Zoi.struct(__MODULE__, %{
  name: Zoi.string(description: "Task name"),
  task:
    Zoi.tuple({Zoi.atom(), Zoi.list(Zoi.any())})
    |> Zoi.default({nil, []}),
  cost: Zoi.integer(description: "Execution cost") |> Zoi.optional(),
  duration: Zoi.integer(description: "Duration in ms") |> Zoi.optional(),
  scheduling_constraints:
    Zoi.map(%{
      optional(:earliest_start_time) => Zoi.non_neg_integer(),
      optional(:latest_end_time) => Zoi.non_neg_integer()
    })
    |> Zoi.optional(),
  preconditions:
    Zoi.list(Zoi.function(), description: "Validation functions")
    |> Zoi.default([]),
  effects:
    Zoi.list(Zoi.function(), description: "Effect functions")
    |> Zoi.default([]),
  expected_effects:
    Zoi.list(Zoi.function(), description: "Expected effect functions")
    |> Zoi.default([]),
  background:
    Zoi.boolean(description: "Run in background?")
    |> Zoi.default(false)
}, coerce: true)

@type t :: unquote(Zoi.type_spec(@schema))
@enforce_keys Zoi.Struct.enforce_keys(@schema)
defstruct Zoi.Struct.struct_fields(@schema)
```

📖 [Zoi.struct/3 documentation](https://hexdocs.pm/zoi/Zoi.html#struct/3)

---

#### `lib/jido_htn/compound_task.ex:13`
**Current**:
```elixir
defstruct [:name, methods: []]
```

**Migration to Zoi**:
```elixir
@schema Zoi.struct(__MODULE__, %{
  name: Zoi.string(description: "Compound task name"),
  methods:
    Zoi.list(of: Jido.HTN.Method, description: "Decomposition methods")
    |> Zoi.default([])
}, coerce: true)

@type t :: unquote(Zoi.type_spec(@schema))
@enforce_keys Zoi.Struct.enforce_keys(@schema)
defstruct Zoi.Struct.struct_fields(@schema)
```

📖 [Zoi.list/2 documentation](https://hexdocs.pm/zoi/Zoi.html#list/2)

---

#### `lib/jido_htn/method.ex:17`
**Current**:
```elixir
defstruct [:name, :priority, conditions: [], subtasks: [], ordering: []]
```

**Migration to Zoi**:
```elixir
@schema Zoi.struct(__MODULE__, %{
  name: Zoi.string(description: "Method name") |> Zoi.optional(),
  priority:
    Zoi.non_neg_integer(description: "Method priority")
    |> Zoi.optional(),
  conditions:
    Zoi.list(Zoi.any(), description: "Precondition functions")
    |> Zoi.default([]),
  subtasks:
    Zoi.list(Zoi.string(), description: "Subtask names")
    |> Zoi.default([]),
  ordering:
    Zoi.list(
      Zoi.tuple({Zoi.string(), Zoi.string()}),
      description: "Ordering constraints"
    )
    |> Zoi.default([])
}, coerce: true)

@type t :: unquote(Zoi.type_spec(@schema))
@enforce_keys Zoi.Struct.enforce_keys(@schema)
defstruct Zoi.Struct.struct_fields(@schema)
```

📖 [Zoi.tuple/2 documentation](https://hexdocs.pm/zoi/Zoi.html#tuple/2)

---

#### `lib/jido_htn/domain.ex:22`
**Current**:
```elixir
defstruct [:name, tasks: %{}, allowed_workflows: %{}, callbacks: %{}, root_tasks: MapSet.new()]
```

**Migration to Zoi**:
```elixir
@schema Zoi.struct(__MODULE__, %{
  name: Zoi.string(description: "Domain name") |> Zoi.optional(),
  tasks:
    Zoi.map(
      %{
        optional(String.t()) => Zoi.one_of([Jido.HTN.PrimitiveTask, Jido.HTN.CompoundTask])
      },
      description: "Task registry"
    )
    |> Zoi.default(%{}),
  allowed_workflows:
    Zoi.map(%{optional(String.t()) => Zoi.atom()})
    |> Zoi.default(%{}),
  callbacks:
    Zoi.map(%{optional(String.t()) => Zoi.function()})
    |> Zoi.default(%{}),
  root_tasks:
    Zoi.custom(
      fn
        %MapSet{} -> {:ok, %MapSet{}}
        _ -> {:error, "Expected MapSet"}
      end,
      description: "Root task names"
    )
    |> Zoi.default(MapSet.new())
}, coerce: true)

@type t :: unquote(Zoi.type_spec(@schema))
@enforce_keys Zoi.Struct.enforce_keys(@schema)
defstruct Zoi.Struct.struct_fields(@schema)
```

📖 [Zoi.custom/3 documentation](https://hexdocs.pm/zoi/Zoi.html#custom/3)

---

#### `lib/jido_htn/planner/method_traversal_record.ex:14`
**Current**:
```elixir
defstruct choices: []
```

**Migration to Zoi**:
```elixir
@schema Zoi.struct(__MODULE__, %{
  choices:
    Zoi.list(
      Zoi.tuple({Zoi.string(), Zoi.string(), Zoi.non_neg_integer()}),
      description: "Method choices made during planning"
    )
    |> Zoi.default([])
}, coerce: true)

@type t :: unquote(Zoi.type_spec(@schema))
@enforce_keys Zoi.Struct.enforce_keys(@schema)
defstruct Zoi.Struct.struct_fields(@schema)
```

---

### Constructor Functions

#### `lib/jido_htn/primitive_task.ex:50-63` - `PrimitiveTask.new/3`
**Change needed**: Wrap with `Zoi.parse/2`

```elixir
@spec new(String.t(), {action(), params()}, keyword()) :: {:ok, t()} | {:error, term()}
def new(name, task, opts \\ []) when is_binary(name) do
  attrs = %{
    name: name,
    task: task,
    preconditions: Keyword.get(opts, :preconditions, []),
    effects: Keyword.get(opts, :effects, []),
    expected_effects: Keyword.get(opts, :expected_effects, []),
    cost: Keyword.get(opts, :cost),
    duration: Keyword.get(opts, :duration),
    scheduling_constraints: Keyword.get(opts, :scheduling_constraints),
    background: Keyword.get(opts, :background, false)
  }

  Zoi.parse(@schema, attrs)
end
```

📖 [Zoi.parse/2 documentation](https://hexdocs.pm/zoi/Zoi.html#parse/2)

---

#### `lib/jido_htn/compound_task.ex:18-21` - `CompoundTask.new/2`
**Change needed**: Wrap with `Zoi.parse/2`

```elixir
@spec new(String.t(), [Method.t()]) :: {:ok, t()} | {:error, term()}
def new(name, methods \\ []) when is_binary(name) do
  Zoi.parse(@schema, %{name: name, methods: methods})
end
```

---

#### `lib/jido_htn/method.ex:22-24` - `Method.new/1`
**Change needed**: Wrap with `Zoi.parse/2`

```elixir
@spec new(keyword()) :: {:ok, t()} | {:error, term()}
def new(opts \\ []) do
  attrs = Map.new(opts)
  Zoi.parse(@schema, attrs)
end
```

---

### Test Files Requiring Updates

All test files using direct struct construction need updating to handle `{:ok, struct}` or `{:error, reason}` returns:

1. `test/jido_htn/primitive_task_test.exs:14-33` - Update `PrimitiveTask.new/3` calls
2. `test/jido_htn/domain/method_test.exs` - Update `Method.new/1` calls
3. `test/jido_htn/domain/compound_task_test.exs` - Update `CompoundTask.new/2` calls
4. `test/jido_htn/domain/domain_validate_test.exs:410-470` - Update direct struct construction
5. `test/jido_htn/domain/domain_builder_test.exs` - Update builder tests
6. `test/jido_htn/planner/method_traversal_record_test.exs` - Update MTR tests

**Pattern for test updates**:

```elixir
# Before
task = PrimitiveTask.new("test", {MyAction, []})

# After
assert {:ok, task} = PrimitiveTask.new("test", {MyAction, []})
```

---

## 3. Existing Patterns Found

### Resource Definitions
Project uses raw Elixir structs with manual validation:
- Example: `lib/jido_htn/primitive_task.ex:26-36`
- Validation happens at domain build time, not struct creation
- No compile-time validation of struct fields

### Action Patterns
- Follows standard Elixir constructor pattern: `new/2, new/3`
- Returns structs directly from constructors
- No validation errors returned from constructors

### Pattern Discovered: Domain Builder DSL
**Found in**: `lib/jido_htn/domain/helpers.ex`

```elixir
# Current pattern - using keywords directly
Domain.new("my_domain")
|> Domain.primitive("task1", {MyAction, []}, cost: 10)
|> Domain.compound("task2", subtasks: ["task1"])
|> Domain.build()
```

**After migration**: The builder helpers should handle Zoi validation internally:

```elixir
# Builder helpers should internally use Zoi.parse
# and surface errors appropriately
def primitive(builder, name, task, opts \\ []) do
  case PrimitiveTask.new(name, task, opts) do
    {:ok, primitive_task} ->
      # Add to builder
    {:error, reason} ->
      # Add error to builder
  end
end
```

---

## 4. Integration Points

### External APIs Currently Integrated
- **jido** project: Uses `Jido.Action.t()` type in primitive tasks
- **jido_action** project: Primitive tasks wrap Jido actions
- No direct external HTTP APIs

### Database
- None (in-memory planning system)

### Current Schema Patterns
- Manual type specs with `@type` attributes
- No runtime validation of struct fields
- Validation happens at domain build time in `Domain.ValidationHelpers`

---

## 5. Test Impact & Patterns

### Tests Requiring Updates

| Test File | Changes Required |
|-----------|-----------------|
| `test/jido_htn/primitive_task_test.exs` | Update `PrimitiveTask.new/3` pattern matching |
| `test/jido_htn/domain/method_test.exs` | Update `Method.new/1` pattern matching |
| `test/jido_htn/domain/compound_task_test.exs` | Update `CompoundTask.new/2` pattern matching |
| `test/jido_htn/domain/domain_validate_test.exs` | Update direct `%PrimitiveTask{}` construction |
| `test/jido_htn/domain/domain_builder_test.exs` | Handle builder errors from Zoi |
| `test/jido_htn/planner/method_traversal_record_test.exs` | Update MTR construction |
| `test/jido_htn/serializer_test.exs` | May need updates for struct changes |

### Current Testing Patterns
- Direct struct construction: `%PrimitiveTask{name: "test"}`
- Constructor functions without error handling: `PrimitiveTask.new("test", {Action, []})`
- Property-based tests using `StreamData`

### Mocking Strategy
- Uses `Mimic` for mocking (see `mix.exs:43`)
- Mocking patterns should not change with Zoi migration

📖 [ExUnit documentation](https://hexdocs.pm/ex_unit/)

---

## 6. Configuration & Environment

### Config Files to Update
1. **`mix.exs`** - Add Zoi dependency:
   ```elixir
   defp deps do
     [
       # ... existing deps
       {:zoi, "~> 0.14"},  # ADD THIS
       # ... rest of deps
     ]
   end
   ```

2. **No environment variables** required for Zoi

### Build/Deployment Implications
- **mix.exs version**: No version bump required (internal change)
- **Hex publishing**: Zoi dependency must point to Hex package when publishing
- **Documentation**: Update module docs to reflect Zoi validation

---

## 7. Required New Dependencies/Patterns

### ⚠️ User Decision Required

**Dependency Addition**:
- Must add `{:zoi, "~> 0.14"}` to `mix.exs`

**Question for user**:
- Should we add Zoi as a direct dependency to `jido_htn`?
- **Options**:
  1. Add Zoi dependency (recommended) - Provides validation, better error messages
  2. Keep raw structs - Simpler, but loses validation benefits
  3. Make Zoi optional - Complex, not recommended

**Recommendation**: Add Zoi as a required dependency. It's already a transitive dependency via `jido` and `jido_action`, so this makes it explicit.

---

## 8. Risk Assessment

### Breaking Changes
| Severity | Change | Impact |
|----------|--------|--------|
| **HIGH** | Constructor functions now return `{:ok, t()} \| {:error, term()}` | All callers must update pattern matching |
| **MEDIUM** | Direct struct construction still works but bypasses validation | Tests may need updates for best practices |
| **LOW** | Type specs remain compatible | No type-level breaking changes |

### Performance Implications
- **Validation overhead**: Zoi.parse/2 adds validation cost at struct creation
- **Mitigation**: Validation only happens at construction time, not on every field access
- **Planning performance**: HTN planning creates many structs - consider lazy validation

### Security Touchpoints
- **No auth/data handling**: jido_htn is a pure planning library
- **No user input**: All data comes from developer-defined domains
- **No SQL injection risk**: No database queries

### Migration Complexity
| Aspect | Complexity | Notes |
|--------|-----------|-------|
| Core structs | LOW | Straightforward Zoi migration |
| Constructor functions | MEDIUM | Must change return types |
| Test updates | MEDIUM | Many test files need pattern matching updates |
| Builder helpers | MEDIUM | Must handle Zoi errors appropriately |
| Backward compatibility | HIGH | Constructor return type is breaking change |

---

## 9. Third-Party Integrations & External Services

### No Third-Party Service Integrations Detected

The `jido_htn` project is a pure planning library with no external service integrations.

---

## 10. Unclear Areas Requiring Clarification

### Questions for User

1. **Constructor Return Types**:
   - Should `new/2, new/3` functions return `{:ok, t()} \| {:error, term()}`?
   - Or should we provide `new/2` (that may raise) and `new!/2` (that returns ok/error)?
   - **Current jido pattern**: Uses `new/1` that returns `{:ok, t} \| {:error, term}`

2. **Backward Compatibility**:
   - Should we maintain compatibility with existing code using direct struct construction?
   - **Recommendation**: Yes, but add @deprecated tags with migration path

3. **Function Field Validation**:
   - Zoi doesn't natively validate function arity/types
   - Should we add custom refinements for precondition/effect functions?
   - **Current approach**: Runtime validation during domain build

4. **MapSet Handling**:
   - Zoi doesn't have built-in MapSet type
   - Should we use `Zoi.custom/3` or convert to lists internally?
   - **Recommendation**: Use `Zoi.custom/3` with MapSet validation

5. **Test Strategy**:
   - Should we add property-based tests for Zoi validation?
   - **Recommendation**: Yes, add StreamData tests for schema validation

---

## 11. Implementation Recommendations

### Phase 1: Add Zoi Dependency (5 minutes)
1. Add `{:zoi, "~> 0.14"}` to `mix.exs`
2. Run `mix deps.get`
3. Verify Zoi loads correctly

### Phase 2: Migrate Core Structs (1-2 hours)
1. Start with simplest struct: `MethodTraversalRecord`
2. Test migration, verify tests pass
3. Migrate `Method` struct
4. Migrate `CompoundTask` struct
5. Migrate `PrimitiveTask` struct
6. Migrate `Domain` struct last (most complex)

### Phase 3: Update Constructors (1 hour)
1. Change `new/2, new/3` to use `Zoi.parse/2`
2. Return `{:ok, t()} \| {:error, term()}`
3. Add `new!/2, new!/3` variants that raise on error (optional)

### Phase 4: Update Tests (1-2 hours)
1. Update all test files to pattern match on `{:ok, struct}`
2. Add error case tests
3. Verify all tests pass

### Phase 5: Update Builder Helpers (30 minutes)
1. Update domain builder to handle Zoi errors
2. Ensure error accumulation works correctly

### Phase 6: Documentation (30 minutes)
1. Update module documentation
2. Add migration guide for users
3. Update examples

---

## 12. Success Criteria

Migration is complete when:

- [ ] All core structs use Zoi schemas
- [ ] All constructors return `{:ok, t()} \| {:error, term()}`
- [ ] All tests pass with new constructor signatures
- [ ] Type specs are generated from Zoi schemas
- [ ] Documentation is updated
- [ ] No warnings from `mix compile --warnings-as-errors`
- [ ] All quality checks pass: `mix quality`

---

## 13. References

### Internal Documentation
- [Jido Migration Guide](../../jido/guides/migration.md) - NimbleOptions to Zoi migration
- [Jido Agent Schema](../../jido/lib/jido/agent/schema.ex) - Zoi schema patterns
- [Jido Action Schema](../../jido_action/lib/jido_action/schema.ex) - Unified schema handling

### External Documentation
- [Zoi HexDocs](https://hexdocs.pm/zoi) - Official Zoi documentation
- [Zoi GitHub](https://github.com/phcurado/zoi) - Source code
- [Zoi v0.14.1 Changelog](../../jido_character/deps/zoi/CHANGELOG.md) - Version history

### Key Zoi Modules
- `Zoi` - Main Zoi module
- `Zoi.Struct` - Struct helpers (`enforce_keys/1`, `struct_fields/1`)
- `Zoi.Type` - Type specification behavior
- `Zoi.Types` - Built-in type constructors

---

## 14. Example: Complete Migration

### Before: `PrimitiveTask`
```elixir
defmodule Jido.HTN.PrimitiveTask do
  @type t :: %__MODULE__{
    name: String.t(),
    task: {action(), params()},
    # ... other fields
  }

  defstruct [
    :name,
    :task,
    preconditions: [],
    effects: [],
    expected_effects: [],
    background: false
  ]

  @spec new(String.t(), {action(), params()}, keyword()) :: t()
  def new(name, task, opts \\ []) when is_binary(name) do
    %__MODULE__{
      name: name,
      task: task,
      preconditions: Keyword.get(opts, :preconditions, []),
      effects: Keyword.get(opts, :effects, []),
      expected_effects: Keyword.get(opts, :expected_effects, []),
      background: Keyword.get(opts, :background, false)
    }
  end
end
```

### After: `PrimitiveTask` with Zoi
```elixir
defmodule Jido.HTN.PrimitiveTask do
  alias Jido.Action

  @schema Zoi.struct(
            __MODULE__,
            %{
              name:
                Zoi.string(
                  description: "Unique name for this primitive task"
                ),
              task:
                Zoi.tuple(
                  {Zoi.atom(), Zoi.list(Zoi.any())},
                  description: "Jido.Action module and parameters"
                )
                |> Zoi.default({nil, []}),
              cost:
                Zoi.integer(
                  description: "Estimated cost for planning"
                )
                |> Zoi.optional(),
              duration:
                Zoi.integer(
                  description: "Estimated duration in milliseconds"
                )
                |> Zoi.optional(),
              scheduling_constraints:
                Zoi.map(
                  %{
                    optional(:earliest_start_time) => Zoi.non_neg_integer(),
                    optional(:latest_end_time) => Zoi.non_neg_integer()
                  },
                  description: "Time constraints for execution"
                )
                |> Zoi.optional(),
              preconditions:
                Zoi.list(
                  Zoi.function(),
                  description: "Functions that validate world state"
                )
                |> Zoi.default([]),
              effects:
                Zoi.list(
                  Zoi.function(),
                  description: "Functions that transform world state"
                )
                |> Zoi.default([]),
              expected_effects:
                Zoi.list(
                  Zoi.function(),
                  description: "Expected world state transformations"
                )
                |> Zoi.default([]),
              background:
                Zoi.boolean(
                  description: "Execute asynchronously without blocking"
                )
                |> Zoi.default(false)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec new(String.t(), {Action.t(), keyword()}, keyword()) ::
          {:ok, t()} | {:error, Zoi.Error.t() | [Zoi.Error.t()]}
  def new(name, task, opts \\ []) when is_binary(name) do
    attrs = %{
      name: name,
      task: task,
      cost: Keyword.get(opts, :cost),
      duration: Keyword.get(opts, :duration),
      scheduling_constraints: Keyword.get(opts, :scheduling_constraints),
      preconditions: Keyword.get(opts, :preconditions, []),
      effects: Keyword.get(opts, :effects, []),
      expected_effects: Keyword.get(opts, :expected_effects, []),
      background: Keyword.get(opts, :background, false)
    }

    Zoi.parse(@schema, attrs)
  end

  @spec new!(String.t(), {Action.t(), keyword()}, keyword()) :: t()
  def new!(name, task, opts \\ []) when is_binary(name) do
    case new(name, task, opts) do
      {:ok, task} -> task
      {:error, errors} -> raise ArgumentError, "Invalid PrimitiveTask: #{inspect(errors)}"
    end
  end
end
```

---

*Last Updated: 2025-01-06*
*Research Phase: Complete*
*Ready for Planning Phase*

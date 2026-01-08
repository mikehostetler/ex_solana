# Research: Modernize Jido HTN to Current Jido Patterns

**Item ID:** `011-modernize-to-current-jido-patterns-actio`
**Section:** 3. Jido HTN Modernization
**Research Date:** 2026-01-07

---

## Executive Summary

The `jido_htn` package exhibits partial modernization (Zoi schemas for structs) but retains several legacy patterns that differ from current Jido ecosystem conventions. Key areas requiring modernization:

1. **Action Integration** - HTN uses `{module, params}` tuples instead of `Jido.Action` behavior
2. **Error Handling** - String-based errors instead of `Jido.Error` with Splode
3. **Effects** - State mutation functions instead of `Jido.Agent.Directive`
4. **Validation** - Custom validation pipeline instead of structured error returns

---

## 1. Project Dependencies Discovered

### Current jido_htn Dependencies (`mix.exs:24-31`)

```elixir
{:zoi, "~> 0.14"},              # Schema validation (already using)
{:jido, path: "../jido", "~> 1.3.0"},     # Core agent system
{:jido_action, path: "../jido_action", "~> 1.3.0"}  # Action behavior
```

### Modern Jido Dependencies

**From `projects/jido/mix.exs:189-214`:**
- `jido_action` (via GitHub or path)
- `jido_signal` (via path)
- `splode, "~> 0.2.5"` (error handling)
- `nimble_options, "~> 1.1"` (action schema validation)
- `fsmx, "~> 0.5"` (state machine for strategies)

**From `projects/jido_action/mix.exs:204-214`:**
- `zoi, "~> 0.14"` (schema validation)
- `splode, "~> 0.2.4"` (error handling)
- `nimble_options, "~> 1.1"` (validation)

### Current Testing Approach

**From jido_htn mix.exs:44:**
- `mimic, "~> 2.0"` (mocking)
- `stream_data, "~> 1.0"` (property-based testing)
- `excoveralls, "~> 0.18.3"` (coverage)

---

## 2. Current Patterns in Jido Ecosystem

### 2.1 Jido.Action Definition Pattern

**Location:** `projects/jido_action/lib/jido_action.ex:1-150`

```elixir
defmodule MyAction do
  use Jido.Action,
    name: "my_action",
    description: "Performs my action",
    category: "processing",
    tags: ["example", "demo"],
    vsn: "1.0.0",
    schema: [
      input: [type: :string, required: true]
    ],
    output_schema: [
      result: [type: :string, required: true]
    ]

  @impl true
  def run(params, _context) do
    {:ok, %{result: "value"}}
  end
end
```

**Key Characteristics:**
- Compile-time configuration via `use Jido.Action`
- NimbleOptions for `schema` validation
- Optional `output_schema` for result validation
- Returns `{:ok, result_map}` or `{:ok, result_map, [directives]}`
- Open validation (unspecified fields pass through)

### 2.2 Error Handling with Splode

**Location:** `projects/jido/lib/jido/error.ex:90-100`

```elixir
defmodule Jido.Error do
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

**Helper Functions:** `error.ex:267-362`

```elixir
Jido.Error.validation_error("Invalid parameters", field: :user_id)
Jido.Error.execution_error("Failed to process", details: %{step: 5})
Jido.Error.planning_error("No valid plan found")
Jido.Error.timeout("Action timed out", timeout: 30000)
```

### 2.3 Directives for Side Effects

**Location:** `projects/jido/lib/jido/agent/directive.ex`

```elixir
# Actions return directives as 3rd element
{:ok, %{status: :done}, [directive]}

# Directive types:
Directive.emit(signal)                    # Dispatch signal
Directive.error(error, :normalize)       # Signal error
Directive.spawn(child_spec, :worker)     # Fire-and-forget spawn
Directive.spawn_agent(MyWorker, :tag)    # Tracked child agent
Directive.schedule(5000, signal)         # Delayed execution
Directive.stop(:shutdown)                # Stop self
```

### 2.4 Signal-Based Coordination

**Location:** `projects/jido_signal/lib/jido_signal.ex`

```elixir
# CloudEvents v1.0.2 format
Signal.new("task.completed", %{task: "name"}, source: "/htn")

# Signal routing in skills
def router(_config) do
  [
    {"htn.task.completed", MyApp.Actions.HandleCompletion},
    {"htn.plan.failed", MyApp.Actions.HandleFailure}
  ]
end
```

---

## 3. Legacy Patterns in jido_htn

### 3.1 Task/Method Definitions

#### Current State (Already Using Zoi - Good)

**Method** (`lib/jido_htn/method.ex:10-46`):
```elixir
@schema Zoi.struct(
  __MODULE__,
  %{
    name: Zoi.string(),
    priority: Zoi.default(Zoi.integer(), 0),
    conditions: Zoi.list(Zoi.any()),
    subtasks: Zoi.list(Zoi.string()),
    ordering: Zoi.default(Zoi.atom(), :sequential)
  },
  coerce: true
)
```

**CompoundTask** (`lib/jido_htn/compound_task.ex:8-28`):
- Uses Zoi schemas ✓
- Fields: `name`, `methods`

**PrimitiveTask** (`lib/jido_htn/primitive_task.ex:14-63`):
- Uses Zoi schemas ✓
- **ISSUE**: `task` field stores `{action_module, params}` tuple (lines 19-25)
- **ISSUE**: `execute/2` references non-existent `Jido.Workflow.run/3` (lines 132, 138)

#### What Needs to Change

1. **Action Integration** (`primitive_task.ex:19-25, 127-140`):
   - Currently: `task: {MyAction, [param: "value"]}`
   - Should: `task: MyAction` (action module reference)
   - Execution: Replace `Jido.Workflow.run/3` with `Jido.Exec.run/3`

2. **Conditions Representation** (`method.ex:21-24`):
   - Currently: List of functions/booleans
   - Modern: Could be expressed as Actions or Signal predicates

### 3.2 Domain Building

#### Current Implementation

**Domain.Builder** (`lib/jido_htn/domain/domain_builder.ex:1-49`):
- Uses Zoi schemas ✓
- Builder pattern with error accumulation
- **ISSUE**: Uses `raise` for errors (lines 133, 139)

**Validation Pipeline** (`domain_builder.ex:250-288`):
- Custom validation with 14 validators
- **ISSUE**: Returns `{:error, String.t()}` or `{:error, [String.t()]}`

#### What Needs to Change

1. **Error Handling** (`domain_builder.ex:79-84, 133-139`):
   - Replace `raise ArgumentError` with `Jido.Error` exceptions
   - Return `{:error, Jido.Error.PlanningError.t()}` instead of strings

2. **Validation Pattern** (`domain_validation.ex:60-89`):
   - Current: Accumulates string errors in list
   - Modern: Use `Jido.Error` composition

### 3.3 Planner Integration

#### Current Implementation

**Planner** (`lib/jido_htn/planner.ex:14-56`):
```elixir
# Returns list of action tuples
{:ok, [{module(), keyword()}]}
```

**TaskDecomposer** (`lib/jido_htn/planner/task_decomposer.ex:60-94`):
```elixir
# Converts task to action tuple
{action, params}
```

#### What Needs to Change

1. **Return Format** (`planner.ex:17-18`):
   - Current: `{:ok, [{module(), keyword()}]}`
   - Modern: Should return executable plan or use `Jido.Exec`

2. **Error Types** (`planner.ex:45-51`):
   - Current: `{:error, String.t()}`
   - Modern: `{:error, Jido.Error.PlanningError.t()}`

3. **Action Execution** (`primitive_task.ex:127-140`):
   - Remove `Jido.Workflow.run/3` placeholder
   - Implement via `Jido.Exec.run/3` or direct action call

### 3.4 Error Handling

#### Current State

**String-based errors throughout:**
- `planner.ex:47` - `{:error, "Planning failed"}`
- `task_decomposer.ex:55` - `{:error, "Unknown task"}`
- `domain_validation.ex:97-98` - `{:error, "Domain must contain..."}`

**Exception usage:**
- `method.ex:71-111` - `validate_ordering!/1` raises `ArgumentError`
- `compound_task.ex:44` - `new!/2` raises `ArgumentError`
- `domain_builder.ex:133, 139` - Raises `ArgumentError`

#### What Needs to Change

**Replace all string errors with structured errors:**

| Location | Current | Modern |
|----------|---------|--------|
| `planner.ex:47` | `{:error, "Planning failed"}` | `Jido.Error.planning_error("...")` |
| `planner.ex:51` | `{:error, "Planning timed out"}` | `Jido.Error.timeout("...")` |
| `task_decomposer.ex:55` | `{:error, "Unknown task"}` | `Jido.Error.validation_error("...")` |
| `task_decomposer.ex:91` | `{:error, "Precondition not met"}` | `Jido.Error.execution_error("...")` |
| `domain_builder.ex:133` | `raise ArgumentError` | `raise Jido.Error.PlanningError` |

### 3.5 Signal/Effect Integration

#### Current State

**EffectHandler** (`lib/jido_htn/planner/effect_handler.ex:11-45`):
- Effects are functions applied to world_state
- Callbacks stored in `domain.callbacks` map
- No signal emission
- Direct state mutation

**PrimitiveTask Effects** (`primitive_task.ex:41-56`):
```elixir
effects: [fn world_state -> Map.update!(world_state, :key, fn v -> v + 1 end) end]
```

#### What Needs to Change

1. **Replace Effects with Directives:**
   - Current: State transformation functions
   - Modern: Actions return `{:ok, result, [directives]}`
   - Example: `Directive.emit(Signal.new!("task.completed", %{task: name}))`

2. **Add Signal Emission:**
   - Task completion: `Signal.new!("htn.task.completed", %{task: name}, source: "/htn")`
   - Planning events: `Signal.new!("htn.plan.generated", %{tasks: [...]})`
   - Enable reactive workflows via signal routing

3. **Effect Handler Redesign:**
   - Current: `apply_effects/4` mutates state
   - Modern: Should return directives for AgentServer to apply

---

## 4. Files Requiring Changes

### 4.1 Core Planning Files

| File | Lines | Changes | Priority |
|------|-------|---------|----------|
| `planner.ex` | 47, 51 | Replace string errors with `Jido.Error` | High |
| `task_decomposer.ex` | 55, 91-92, 269 | Error types, action execution | High |
| `primitive_task.ex` | 19-25, 127-140 | Remove placeholder, implement execution | High |
| `effect_handler.ex` | 11-45 | Replace with directive pattern | Medium |
| `condition_evaluator.ex` | 12-20 | Add error handling | Low |

### 4.2 Domain Building Files

| File | Lines | Changes | Priority |
|------|-------|---------|----------|
| `domain_builder.ex` | 133, 139 | Replace raise with `Jido.Error` | High |
| `domain_validation.ex` | 60-68, 97-474 | Return structured errors | Medium |
| `domain_reader.ex` | 12-96 | Update error returns | Low |

### 4.3 Struct Definition Files

| File | Lines | Changes | Priority |
|------|-------|---------|----------|
| `method.ex` | 21-24, 71-111 | Consider validation error returns | Low |
| `compound_task.ex` | 44 | Keep `new!/2` (acceptable) | None |
| `primitive_task.ex` | 19-25, 120 | Task field ref, `new!/3` | High |

### 4.4 New Files to Create

| File | Purpose | Priority |
|------|---------|----------|
| `lib/jido_htn/error.ex` | `Jido.HTN.Error` using Splode | High |
| `lib/jido_htn/planner/exec.ex` | HTN execution via `Jido.Exec` | High |
| `lib/jido_htn/signals.ex` | HTN signal definitions | Medium |

---

## 5. Integration Points

### 5.1 Jido.Exec Integration

**Location:** `projects/jido_action/lib/jido_action/exec.ex`

**Current HTN placeholder** (`primitive_task.ex:132`):
```elixir
Jido.Workflow.run(action, params, world_state)
```

**Modern approach:**
```elixir
# Option 1: Direct action execution
MyAction.run(params, context)

# Option 2: Via Jido.Exec (with directives)
{:ok, result, agent} = Jido.Exec.run(agent, MyAction, params)
```

### 5.2 Signal Routing Integration

**Pattern from Jido.Skill** (`projects/jido/lib/jido/skill.ex:182-184`):
```elixir
def router(_config) do
  [
    {"htn.plan.started", Jido.HTN.Actions.PlanStarted},
    {"htn.task.completed", Jido.HTN.Actions.TaskCompleted},
    {"htn.plan.failed", Jido.HTN.Actions.PlanFailed}
  ]
end
```

### 5.3 Error Aggregation

**Pattern from Jido.Error** (`projects/jido/lib/jido/error.ex:46-100`):
```elixir
# Define error classes
defmodule Jido.HTN.Error do
  use Splode,
    error_classes: [
      planning: PlanningError,
      validation: ValidationError,
      decomposition: DecompositionError
    ],
    unknown_error: PlanningError
end
```

---

## 6. Test Impact & Patterns

### 6.1 Existing Test Infrastructure

**From jido_htn mix.exs:44-45:**
- `mimic, "~> 2.0"` - Already using same mocking library as jido
- `stream_data, "~> 1.0"` - Property-based testing support

### 6.2 Test Files Requiring Updates

Based on error handling changes:

1. **Error assertion updates:**
   ```elixir
   # Current
   assert {:error, "Planning failed"} = result

   # Modern
   assert {:error, %Jido.Error.PlanningError{}} = result
   ```

2. **Action execution tests:**
   ```elixir
   # Current
   assert {{:ok, _}, world_state} = PrimitiveTask.execute(task, state)

   # Modern
   assert {:ok, result, [directive]} = MyAction.run(params, context)
   ```

### 6.3 Testing Patterns

**From Jido.Action** (`projects/jido_action/lib/jido_action.ex:112-141`):
```elixir
# Direct action testing
test "action returns result" do
  assert {:ok, result} = MyAction.run(params, context)
end

# Full execution testing
test "action in agent" do
  {:ok, result} = Jido.Exec.run(agent, MyAction, params)
end
```

---

## 7. Configuration & Environment

### 7.1 No Config Changes Required

- jido_htn has no external config files
- Domain building is code-only via DSL
- No environment variables needed

### 7.2 Build/Deployment Implications

- No deployment changes (library only)
- Existing mix tasks remain valid
- Quality checks (`mix quality`) will pass after changes

---

## 8. Required New Dependencies

**None required** - All modernization can use existing dependencies:
- `jido` (path) - Already using
- `jido_action` (path) - Already using
- `jido_signal` (path via jido) - Available through jido
- `zoi, "~> 0.14"` - Already using
- `splode` (via jido) - Available through jido

---

## 9. Risk Assessment

### 9.1 Breaking Changes

**Severity: Medium**

1. **Error Format Changes:**
   - String errors → Structured errors
   - **Impact:** All error-handling code needs updates
   - **Mitigation:** Provide migration guide

2. **Action Execution:**
   - `{module, params}` → Direct module calls
   - **Impact:** Existing domain definitions may need updates
   - **Mitigation:** Support both formats during transition

### 9.2 Performance Implications

**Risk: Low**

- Structured errors add minor overhead (acceptable for planning failures)
- Directives add indirection (necessary for agent coordination)
- No expected bottlenecks

### 9.3 Security Touchpoints

**Risk: None**

- No user input processing in HTN core
- No external API calls
- Planning is internal operation

### 9.4 Migration Complexity

**Severity: Medium**

- ~15 files require changes
- ~50 error sites need updating
- 1 major API change (action execution)

**Estimated Effort:** 3-5 days
- Error module creation: 2-3 hours
- Core planning updates: 4-6 hours
- Domain builder updates: 3-4 hours
- Validation updates: 2-3 hours
- Directive integration: 3-4 hours
- Test updates: 4-6 hours
- Documentation: 2-3 hours

---

## 10. Unclear Areas Requiring Clarification

### 10.1 Action Execution Strategy

**Question:** Should HTN tasks store action modules directly or keep the tuple format?

**Options:**
1. **Direct module reference** - `task: MyAction`
   - Pros: Cleaner, aligns with Jido.Action
   - Cons: Requires updating all domain definitions

2. **Keep tuple format** - `task: {MyAction, [params]}`
   - Pros: Backward compatible, params can be pre-configured
   - Cons: Inconsistent with Jido patterns

**Recommendation:** Option 1 (direct module reference) with transition period supporting both.

### 10.2 Planning vs Execution Separation

**Question:** Should HTN planner return executable plans or remain planning-only?

**Current:** Planner returns `[{module, params}]` list (not executed)

**Options:**
1. **Planning-only** - Keep current separation
   - Pros: Flexibility in execution strategy
   - Cons: Inconsistent with Jido.Exec patterns

2. **Integrated execution** - Use `Jido.Exec` for step-by-step execution
   - Pros: Consistent with Jido ecosystem, directive support
   - Cons: More coupling to Jido runtime

**Recommendation:** Option 2 - Integrate with `Jido.Exec` for consistency.

### 10.3 Signal Granularity

**Question:** How many signals should HTN emit?

**Current:** None

**Proposed signals:**
- `htn.plan.started`
- `htn.plan.completed`
- `htn.plan.failed`
- `htn.task.started`
- `htn.task.completed`
- `htn.task.failed`

**Concern:** Signal spam in high-frequency planning

**Recommendation:** Start with plan-level signals only, add task-level signals as opt-in.

---

## 11. Implementation Roadmap

### Phase 1: Error Handling (High Priority)
1. Create `Jido.HTN.Error` module with Splode
2. Update `planner.ex` error returns
3. Update `task_decomposer.ex` error returns
4. Update `domain_builder.ex` to use `Jido.Error`

### Phase 2: Action Integration (High Priority)
1. Update `primitive_task.ex` task field
2. Implement `execute/2` via `Jido.Exec.run/3`
3. Update domain examples to use action modules

### Phase 3: Directive Integration (Medium Priority)
1. Redesign `effect_handler.ex` to return directives
2. Add signal emission for plan lifecycle
3. Create `Jido.HTN.Signals` module

### Phase 4: Validation Modernization (Low Priority)
1. Update `domain_validation.ex` error returns
2. Add structured error composition
3. Update test assertions

---

## 12. Targeted Documentation

### 12.1 Zoi Schema Documentation

**Zoi v0.14.0 Documentation:**
- 📖 [Quickstart Guide](https://hexdocs.pm/zoi/quickstart_guide.html) - Validation patterns
- 📖 [Zoi Module](https://hexdocs.pm/zoi/Zoi.html) - API reference
- 📖 [Hex.pm Package](https://hex.pm/packages/zoi) - Release notes

**Key Patterns for jido_htn:**
```elixir
# Struct definition (already used in jido_htn)
@schema Zoi.struct(
  __MODULE__,
  %{field: Zoi.type()},
  coerce: true
)

# Validation
Zoi.parse(data, schema)
```

### 12.2 Splode Error Handling Documentation

**Splode Documentation:**
- 📖 [Get Started with Splode](https://hexdocs.pm/splode/get-started-with-splode.html) - Introduction
- 📖 [Splode.Error](https://hexdocs.pm/splode/Splode.Error.html) - Error definition
- 📖 [Splode Module](https://hexdocs.pm/splode/Splode.html) - Aggregator setup

**Key Patterns for jido_htn:**
```elixir
# Error aggregator
defmodule Jido.HTN.Error do
  use Splode,
    error_classes: [
      planning: PlanningError,
      validation: ValidationError
    ],
    unknown_error: PlanningError
end

# Error creation
Jido.HTN.Error.planning_error("No valid method found")
```

### 12.3 Jido.Action Documentation

**From `projects/jido_action/lib/jido_action.ex`:**
- 📖 Jido.Action behavior (moduledoc lines 1-150)
- 📖 Jido.Exec execution engine
- 📖 Jido.Agent.Directive directive types

**Key Patterns:**
```elixir
# Action definition
use Jido.Action,
  name: "action_name",
  schema: [param: [type: :string, required: true]]

# Execution
{:ok, result} = MyAction.run(params, context)
{:ok, result, [directive]} = MyAction.run(params, context)

# Via Exec
{:ok, result, agent} = Jido.Exec.run(agent, MyAction, params)
```

---

## 13. Key Findings Summary

### What's Already Modern ✓
1. **Zoi schemas** for all structs (Method, CompoundTask, PrimitiveTask, Domain)
2. **Builder pattern** for domain construction
3. **Path dependencies** on jido and jido_action
4. **Testing infrastructure** (Mimic, StreamData)

### What Needs Modernization
1. **Error handling** - String errors → `Jido.Error` with Splode
2. **Action execution** - `{module, params}` tuples → Direct `Jido.Action` calls
3. **Effects** - State functions → `Jido.Agent.Directive`
4. **Validation** - String returns → Structured errors
5. **Signals** - None → Signal emission for coordination

### Estimated Effort
- **Total:** 3-5 days
- **High Priority:** 2-3 days (errors, action integration)
- **Medium Priority:** 1-2 days (directives, signals)
- **Low Priority:** 1 day (validation cleanup)

### Dependencies
- **No new dependencies required**
- All modernization uses existing jido, jido_action, jido_signal

### Risk Level
- **Breaking Changes:** Medium (error format, action execution)
- **Performance:** Low (minimal overhead)
- **Security:** None (no external touchpoints)

---

## Sources

### Zoi Documentation
- [Zoi v0.14.0 - Quickstart Guide](https://hexdocs.pm/zoi/quickstart_guide.html)
- [Zoi v0.14.0 - Main Module](https://hexdocs.pm/zoi/Zoi.html)
- [Zoi on Hex.pm](https://hex.pm/packages/zoi)

### Splode Documentation
- [Get Started with Splode](https://hexdocs.pm/splode/get-started-with-splode.html)
- [Splode.Error Documentation](https://hexdocs.pm/splode/Splode.Error.html)
- [Splode Main Module](https://hexdocs.pm/splode/Splode.html)

### Jido Documentation
- Jido.Action behavior (`projects/jido_action/lib/jido_action.ex:1-150`)
- Jido.Error module (`projects/jido/lib/jido/error.ex:90-100`)
- Jido.Agent.Directive (`projects/jido/lib/jido/agent/directive.ex:381-515`)
- Jido.Signal (`projects/jido_signal/lib/jido_signal.ex:150-153`)

### Ash Error Handling Reference
- [Ash Error Handling Guide](https://hexdocs.pm/ash/error-handling.html) - Shows Splode usage patterns

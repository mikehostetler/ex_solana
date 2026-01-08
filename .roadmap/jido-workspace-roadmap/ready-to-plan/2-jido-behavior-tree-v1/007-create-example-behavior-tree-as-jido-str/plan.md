# Implementation Plan: Create Example - Behavior Tree as Jido Strategy

**Item ID**: 007
**State**: Planned
**Date**: 2025-01-07

---

## Executive Summary

This implementation creates the canonical "hello world" example demonstrating behavior trees as Jido strategies. The example will implement a smart coffee maker agent that autonomously brews coffee while handling resource constraints and errors through behavior tree composition.

**Approach**: Create a modular, runnable example with a "Smart Coffee Maker" scenario demonstrating Sequence, Selector, and decorator nodes with multi-tick execution, state preservation, and directive-based effects.

**Architecture**: Follow existing Jido patterns - use `Jido.Agent` with `BehaviorTree` strategy, define actions as `Jido.Action` modules, emit effects via directives, and validate with Zoi schemas.

**Effort Estimate**: 3-4 hours
- Phase 1 (Foundation): 1 hour - Create action modules and basic tree structure
- Phase 2 (Core Implementation): 1.5 hours - Build agent, runner, and integrate signals
- Phase 3 (Testing): 1 hour - Comprehensive test coverage
- Phase 4 (Documentation): 0.5 hours - Narrative walkthrough and README updates

---

## Impact Analysis Summary

### Key Research Findings

From `research.md`, the codebase already provides:
- **Strategy Infrastructure**: `Jido.Agent.Strategy.BehaviorTree` fully implemented
- **Node Library**: Sequence, Selector, Action, Inverter, Repeat, Failer available
- **Effects System**: Directive-based effects for signals, logging, state mutations
- **Signal Schemas**: Defined in items 005-006 (tree lifecycle, node completion)
- **Test Patterns**: Async tests with `ExUnit.Case`, agent lifecycle helpers
- **Example Pattern**: `bt_agent.exs` shows the structure to follow

### Files Requiring Changes

**Phase 1 - New Files**:
1. `projects/jido_behaviortree/examples/hello_world/actions.exs` - Coffee maker actions
2. `projects/jido_behaviortree/examples/hello_world/tree.exs` - Tree definition

**Phase 2 - New Files**:
3. `projects/jido_behaviortree/examples/hello_world/agent.exs` - Agent with BT strategy
4. `projects/jido_behaviortree/examples/hello_world/run.exs` - Executable runner

**Phase 3 - New Files**:
5. `projects/jido_behaviortree/examples/hello_world_test.exs` - Test coverage

**Phase 4 - New/Modified Files**:
6. `projects/jido_behaviortree/examples/hello_world/README.md` - Narrative walkthrough
7. `projects/jido_behaviortree/README.md` - Add quick start link

### Existing Patterns to Follow

**From `bt_agent.exs`**:
- Shebang line, logger config, action definitions, tree as module attribute, runner pattern

**From `agent_test.exs`**:
- Async tests, describe blocks, GenServer lifecycle, snapshot assertions

**From `strategy/behavior_tree.ex`**:
- Strategy options: `tree`, `blackboard`, `reset_on_completion`

**From `nodes/action.ex`**:
- Instruction building, `Jido.Exec.run/1`, effects application via `Jido.Agent.Effects`

### Integration Points

1. **Strategy System**: `Jido.Agent.Strategy.BehaviorTree` (already implemented)
2. **Effects System**: `Jido.Agent.Effects.apply_effects/2` for directives
3. **Signal System**: Emit via `Directive.Emit` for tree lifecycle events
4. **Telemetry**: Automatic via `Jido.Observe.start_span/2` wrapper
5. **Test Harness**: `mix run examples/hello_world/run.exs` and `mix test examples/hello_world_test.exs`

---

## Feature Specification

### User Stories

**US1**: As a new Jido user, I want a working example of a behavior tree strategy so I can understand how to structure my own agents.

**Acceptance Criteria**:
- Example runs successfully with `mix run examples/hello_world/run.exs`
- Output shows clear tick-by-tick progress
- Tree completes with `:success` status

**US2**: As a developer exploring behavior trees, I want to see how effects are expressed via directives so I can avoid direct IO in my actions.

**Acceptance Criteria**:
- All actions use `Directive.emit` for signals
- All logging uses `Directive.log`
- No `IO.puts` in action modules

**US3**: As a contributor, I want to understand multi-tick execution so I can build long-running autonomous agents.

**Acceptance Criteria**:
- Example demonstrates state preservation across ticks
- At least one action shows multi-step execution (heating water)
- Output shows tick number and status progression

**US4**: As a tester, I want comprehensive tests so I can verify behavior tree correctness.

**Acceptance Criteria**:
- Tests cover success path, error path, and multi-tick execution
- Tests assert on both state and emitted signals
- All tests pass with `mix test examples/hello_world_test.exs`

### API Contracts

**Actions**:
```elixir
# All actions follow Jido.Action contract
defmodule CheckWaterLevel do
  use Jido.Action,
    name: "check_water_level",
    schema: []

  @spec run(map(), Jido.Agent.context()) ::
    {:ok, map()} | {:ok, map(), [Directive.t()]} |
    {:error, term()} | {:error, term(), [Directive.t()]}
end
```

**Agent**:
```elixir
defmodule CoffeeMakerAgent do
  use Jido.Agent,
    name: "coffee_maker",
    strategy: {Jido.Agent.Strategy.BehaviorTree,
      tree: @tree,
      blackboard: %{initial: "data"}
    }

  @spec run(agent :: Jido.Agent.t(), cmd :: :tick) ::
    {Jido.Agent.t(), [Directive.t()]}
end
```

**Tree**:
```elixir
@tree Tree.new(
  Sequence.new([
    Selector.new([/* children */]),
    Sequence.new([/* children */])
  ])
)
```

### Data Flow

```
User runs script
    ↓
CoffeeMakerAgent.new()
    ↓
Loop: CoffeeMakerAgent.cmd(agent, :tick)
    ↓
Strategy executes one tree tick
    ↓
Actions return results + directives
    ↓
Directives executed (emit signals, log)
    ↓
State updated and preserved
    ↓
Repeat until tree status = :success/:failure
```

### State Management

**Agent State**:
- `water_level: integer()` - Current water in tank (cups)
- `bean_level: integer()` - Current bean supply (portions)
- `water_temp: integer()` - Current water temperature (°C)
- `notification_sent: boolean()` - Whether user was notified

**Blackboard State**:
- Shared across nodes for coordination
- Initial: `%{water_level: 5, bean_level: 3, water_temp: 20}`
- Updated by actions during execution

**Strategy State**:
- Stored in `agent.state.__strategy__`
- Contains: tree, current node, tick count, status
- Accessible via `Jido.Agent.Strategy.BehaviorTree.snapshot/2`

### Error Handling

**Action-Level Errors**:
- Return `{:error, reason, [directives]}` for expected failures
- Example: No water → `{:error, :no_water, [Directive.emit(WaterEmpty.new!())]}`

**Tree-Level Errors**:
- Selector tries alternatives on failure
- Inverter converts failure → success
- Failer always fails for error handling demos

**Recovery Patterns**:
- Selector with fallback actions
- Inverter for conditional refill (only if check fails)
- Repeat with max limit to prevent infinite loops

---

## Technical Design

### Data Model Changes

**No data model changes** - Example uses existing schemas and creates only ephemeral agent state.

### Module Organization

**New Modules**:
```
projects/jido_behaviortree/examples/hello_world/
├── actions.exs         # Action modules (CheckWaterLevel, HeatWater, etc.)
├── tree.exs            # Tree definition with composites and decorators
├── agent.exs           # CoffeeMakerAgent using BehaviorTree strategy
├── run.exs             # Runner module with executable script
├── README.md           # Narrative walkthrough
└── ../hello_world_test.exs  # Test coverage
```

**Module Responsibilities**:

**Actions** (`actions.exs`):
- `CheckWaterLevel` - Check if water available
- `RefillWater` - Refill water tank
- `CheckBeanLevel` - Check if beans available
- `RefillBeans` - Refill bean supply
- `HeatWater` - Heat water to target temperature (multi-tick)
- `GrindBeans` - Grind coffee beans
- `BrewCoffee` - Brew coffee
- `NotifyUser` - Notify user when ready

**Tree** (`tree.exs`):
- Define `@tree` module attribute
- Structure: Sequence(Selector([...]), Sequence([...]))

**Agent** (`agent.exs`):
- Define `CoffeeMakerAgent` with BT strategy
- Specify schema for agent state
- Provide initial blackboard values

**Runner** (`run.exs`):
- Configure logger level
- Create agent instance
- Loop ticks until completion
- Print progress and final status

**Tests** (`hello_world_test.exs`):
- Test success path
- Test error scenarios
- Test multi-tick execution
- Assert state and signals

### Third-Party Integrations

**None** - Example uses only Jido ecosystem dependencies.

### Configuration Changes

**None** - Example runs standalone with hardcoded values.

### Environment Changes

**None** - No environment variables required.

---

## Implementation Phases

### Phase 1: Foundation - Actions and Tree Structure

**Objective**: Create action modules and tree definition with proper node composition.

**Success Criteria**:
- All action modules compile
- Tree definition validates with Zoi schemas
- Actions return correct tuples

**Files to Create**:
1. `projects/jido_behaviortree/examples/hello_world/actions.exs`
2. `projects/jido_behaviortree/examples/hello_world/tree.exs`

**Implementation Steps**:

1.1 Create `actions.exs` with 8 action modules:
   - Each uses `Jido.Action` with proper schema
   - Returns `{:ok, result, [directives]}` or `{:error, reason, [directives]}`
   - Uses `Directive.emit` for signals
   - Uses `Directive.log` for logging

1.2 Implement resource check actions:
   - `CheckWaterLevel` - Returns `{:ok, %{has_water: true}}` if water > 0
   - `RefillWater` - Returns `{:ok, %{water_level: 5}}`
   - `CheckBeanLevel` - Returns `{:ok, %{has_beans: true}}` if beans > 0
   - `RefillBeans` - Returns `{:ok, %{bean_level: 3}}`

1.3 Implement brewing actions:
   - `HeatWater` - Multi-tick: increment temp by 10°C, return `{:ok, %{water_temp: new_temp}}`
   - `GrindBeans` - Returns `{:ok, %{ground_beans: true}}`
   - `BrewCoffee` - Returns `{:ok, %{coffee_brewed: true}}`
   - `NotifyUser` - Returns `{:ok, %{notification_sent: true}}`

1.4 Create `tree.exs` with tree definition:
   ```elixir
   defmodule HelloWorld.Tree do
     alias Jido.BehaviorTree.Tree
     alias Jido.BehaviorTree.Nodes.{Sequence, Selector, Action, Inverter, Repeat}

     @tree Tree.new(
       Sequence.new([
         Selector.new([
           Sequence.new([
             Action.new(CheckWaterLevel, []),
             Inverter.new(Action.new(RefillWater, []))
           ]),
           Sequence.new([
             Action.new(CheckBeanLevel, []),
             Inverter.new(Action.new(RefillBeans, []))
           ])
         ]),
         Sequence.new([
           Action.new(HeatWater, [target_temp: 90]),
           Repeat.new(Action.new(GrindBeans, []), times: 3),
           Action.new(BrewCoffee, []),
           Action.new(NotifyUser, [message: "Coffee is ready!"])
         ])
       ])
     )

     def tree, do: @tree
   end
   ```

**Tests to Add**:
- Verify actions compile
- Verify tree validates
- Manual test: Load in IEx and inspect structure

**Dependencies**:
- Requires items 005-006 to be complete (signal schemas defined)

---

### Phase 2: Core Implementation - Agent and Runner

**Objective**: Create agent with BT strategy and executable runner script.

**Success Criteria**:
- Agent starts without errors
- Runner executes tree to completion
- Output shows clear progress

**Files to Create**:
3. `projects/jido_behaviortree/examples/hello_world/agent.exs`
4. `projects/jido_behaviortree/examples/hello_world/run.exs`

**Implementation Steps**:

2.1 Create `agent.exs`:
   ```elixir
   defmodule CoffeeMakerAgent do
     @moduledoc """
     Smart coffee maker using BehaviorTree strategy.
     Demonstrates resource checking, multi-tick execution, and effects.
     """

     alias HelloWorld.Tree
     alias Jido.Agent.Strategy.BehaviorTree

     use Jido.Agent,
       name: "coffee_maker",
       description: "Smart coffee maker with behavior tree control",
       strategy: {BehaviorTree,
         tree: Tree.tree(),
         blackboard: %{
           water_level: 5,
           bean_level: 3,
           water_temp: 20
         }
       },
       schema: [
         water_level: [type: :integer, default: 0],
         bean_level: [type: :integer, default: 0],
         water_temp: [type: :integer, default: 20],
         notification_sent: [type: :boolean, default: false]
       ]
   end
   ```

2.2 Create `run.exs`:
   ```elixir
   #!/usr/bin/env elixir
   # Run with: mix run examples/hello_world/run.exs

   Logger.configure(level: :warning)

   # Load dependencies
   Code.require_file("actions.exs", __DIR__)
   Code.require_file("tree.exs", __DIR__)
   Code.require_file("agent.exs", __DIR__)

   defmodule Runner do
     def run do
       IO.puts("\n=== Smart Coffee Maker Demo ===\n")

       agent = CoffeeMakerAgent.new()
       run_ticks(agent, 0)
     end

     defp run_ticks(agent, tick_count) do
       {agent, directives} = CoffeeMakerAgent.cmd(agent, :tick)

       snapshot = Jido.Agent.Strategy.BehaviorTree.snapshot(agent, %{})
       status = snapshot.status
       done? = snapshot.done?

       IO.puts("Tick #{tick_count + 1}: Status = #{inspect(status)}")
       IO.puts("  Water: #{agent.state.water_level}cups @ #{agent.state.water_temp}°C")
       IO.puts("  Beans: #{agent.state.bean_level} portions")

       if done? do
         IO.puts("\n=== Complete: #{inspect(status)} ===\n")
       else
         run_ticks(agent, tick_count + 1)
       end
     end
   end

   Runner.run()
   ```

2.3 Test runner:
   - Execute: `mix run examples/hello_world/run.exs`
   - Verify output shows tick progression
   - Verify final status is `:success`

**Tests to Add**:
- Manual test: Run script and verify output
- Verify agent state updates correctly
- Verify tree completion

**Dependencies**:
- Depends on Phase 1 (actions and tree)

---

### Phase 3: Integration & Testing

**Objective**: Comprehensive test coverage for all scenarios.

**Success Criteria**:
- All tests pass
- Coverage > 90% for example code
- Tests document expected behavior

**Files to Create**:
5. `projects/jido_behaviortree/examples/hello_world_test.exs`

**Implementation Steps**:

3.1 Create test file:
   ```elixir
   defmodule HelloWorldExampleTest do
     use ExUnit.Case, async: true

     alias Jido.Agent.Strategy.BehaviorTree

     describe "Coffee Maker Behavior Tree" do
       test "completes full brew cycle" do
         agent = CoffeeMakerAgent.new()

         # Run to completion
         {final_agent, _directives} = run_until_done(agent, 0)

         # Verify final state
         assert final_agent.state.notification_sent == true
         assert final_agent.state.water_temp >= 90

         # Verify tree status
         snapshot = BehaviorTree.snapshot(final_agent, %{})
         assert snapshot.status == :success
         assert snapshot.done? == true
       end

       test "handles no water scenario" do
         agent = CoffeeMakerAgent.new(%{water_level: 0})

         # First tick detects no water
         {agent, directives} = CoffeeMakerAgent.cmd(agent, :tick)

         # Should have water empty signal (when item 005 complete)
         # For now, verify state update
         assert agent.state.water_level >= 0
       end

       test "multi-tick execution preserves state" do
         agent = CoffeeMakerAgent.new()

         # Tick 1
         {agent1, _} = CoffeeMakerAgent.cmd(agent, :tick)
         temp1 = agent1.state.water_temp

         # Tick 2
         {agent2, _} = CoffeeMakerAgent.cmd(agent1, :tick)

         # State preserved
         assert agent2.state.water_temp != nil
         assert agent2.state.water_level != nil
       end

       test "tree structure is correct" do
         agent = CoffeeMakerAgent.new()
         snapshot = BehaviorTree.snapshot(agent, %{})

         # Should have tree in strategy state
         assert snapshot.tree != nil
       end
     end

     defp run_until_done(agent, tick_count) when tick_count > 50 do
       # Safety limit
       {agent, _}
     end

     defp run_until_done(agent, tick_count) do
       {agent, _directives} = CoffeeMakerAgent.cmd(agent, :tick)
       snapshot = BehaviorTree.snapshot(agent, %{})

       if snapshot.done? do
         {agent, _directives}
       else
         run_until_done(agent, tick_count + 1)
       end
     end
   end
   ```

3.2 Run tests:
   - Execute: `mix test examples/hello_world_test.exs`
   - Verify all tests pass
   - Check coverage with `mix test --cover`

**Tests to Add**:
- Success path test
- Error scenario tests (no water, no beans)
- Multi-tick state preservation test
- Tree structure validation test

**Dependencies**:
- Depends on Phase 2 (agent and runner)

---

### Phase 4: Polish & Documentation

**Objective**: Narrative walkthrough and integration with project docs.

**Success Criteria**:
- README clearly explains the example
- Linked from main README
- Example is discoverable

**Files to Create**:
6. `projects/jido_behaviortree/examples/hello_world/README.md`

**Files to Modify**:
7. `projects/jido_behaviortree/README.md`

**Implementation Steps**:

4.1 Create narrative README following template from research:
   ```markdown
   # Hello World: Behavior Tree as Jido Strategy

   ## Overview

   This example demonstrates how to implement a behavior tree as a Jido agent strategy.
   It shows a smart coffee maker that autonomously brews coffee while handling resource
   constraints and errors.

   ## What You'll Learn

   - How to structure behavior trees with composites, decorators, and leaves
   - How the BehaviorTree strategy ticks the tree over time
   - How to express side effects via Jido effects (not direct IO)
   - Best practices for behavior tree design
   - How to test behavior tree agents

   ## Tree Structure

   [ASCII diagram showing the tree]

   ## Running the Example

   ```bash
   mix run examples/hello_world/run.exs
   ```

   ## Expected Output

   [Sample output]

   ## Key Concepts

   ### Effects vs Direct IO
   [Explanation with code examples]

   ### State Preservation
   [Explanation with code examples]

   ### Error Handling
   [Explanation with code examples]

   ## Testing

   See `hello_world_test.exs` for comprehensive tests.

   ## Next Steps

   [Links to further learning]
   ```

4.2 Update main README:
   - Add section in Quick Start:
     ```markdown
     ## Quick Start

     Try the hello world example:

     ```bash
     mix run examples/hello_world/run.exs
     ```

     See [examples/hello_world/README.md](examples/hello_world/README.md) for a walkthrough.
     ```
   - Add link to hello_world in navigation

4.3 Verify all files:
   - Check all files compile
   - Run example successfully
   - Run tests successfully
   - Verify README renders correctly

**Tests to Add**:
- Manual test: Follow README instructions
- Verify links work
- Check formatting

**Dependencies**:
- Depends on Phase 3 (tests passing)

---

## Quality & Testing Strategy

### Test Categories

**Unit Tests**:
- Individual action behavior (CheckWaterLevel, HeatWater, etc.)
- Tree structure validation
- Agent initialization

**Integration Tests**:
- Full tree execution
- Multi-tick state preservation
- Signal emission
- Directive application

**Property-Based Tests** (optional):
- State invariants (water_level never negative)
- Tree status transitions

### Coverage Targets

- **Actions**: 100% (simple, deterministic)
- **Agent**: 90%+ (complex interactions)
- **Tree**: 80%+ (structure validated)
- **Overall**: 90%+

### Quality Gates

1. **Compilation**: All files compile without warnings
2. **Formatting**: Code follows `mix format` standards
3. **Tests**: All tests pass with `mix test`
4. **Execution**: `mix run examples/hello_world/run.exs` completes successfully
5. **Documentation**: README is clear and complete
6. **Links**: All cross-references work

---

## Risk Assessment

### Technical Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Signal schemas not yet defined (items 005-006) | Medium | Use placeholder signals or defer to 005-006 completion |
| Multi-tick execution complexity | Low | Keep actions simple, use clear state transitions |
| State mutation bugs | Low | Use pure actions, test state transitions thoroughly |
| Runner infinite loop | Low | Add tick count limit (50 ticks max) |

### Dependency Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Items 005-006 incomplete (signals) | Medium | Implement without signals first, add signals when schemas ready |
| Strategy API changes | Low | Strategy is stable, follow existing patterns |

### Timeline Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Scope creep (adding more features) | Low | Stick to coffee maker scenario, keep it minimal |
| Documentation takes longer | Low | Use template from research, keep it concise |

---

## Success Criteria

### Measurable Outcomes

1. **Functional**:
   - `mix run examples/hello_world/run.exs` executes successfully
   - Output shows 5-10 ticks with clear progress
   - Final status is `:success`

2. **Code Quality**:
   - All files compile without warnings
   - All tests pass (100% pass rate)
   - Code coverage > 90%

3. **Documentation**:
   - README is clear and complete
   - Linked from main project README
   - Follows existing documentation patterns

4. **Educational Value**:
   - Demonstrates 3+ node types
   - Shows multi-tick execution
   - Illustrates effects via directives
   - Includes error handling

### Definition of "Done"

- [ ] All 7 files created
- [ ] Example runs successfully
- [ ] All tests pass
- [ ] README complete
- [ ] Main README updated
- [ ] No compilation warnings
- [ ] Code formatted
- [ ] Manual testing complete

### Acceptance Testing

**Manual Testing**:
```bash
# 1. Compile check
mix compile

# 2. Run example
mix run examples/hello_world/run.exs
# Expected: 5-10 ticks, final status :success

# 3. Run tests
mix test examples/hello_world_test.exs
# Expected: All tests pass

# 4. Format check
mix format --check-formatted
```

**Automated Testing**:
- CI/CD should run tests on PR
- Coverage report generated
- No warnings in compilation

---

## Dependencies on Other Work

### Required Before Starting

- **Items 005-006**: Signal schemas (optional but recommended)
  - If complete: Use proper signal schemas
  - If incomplete: Use placeholder signals or defer signal emission

### Parallel Work

- Can be done in parallel with item 008 (example as part of jido)
- Uses same patterns, independent scenarios

### Blocked By

- None (example is self-contained)

### Blocking

- None (example is additive, no downstream dependencies)

---

## Implementation Notes

### Code Style

- Follow existing project patterns from `bt_agent.exs`
- Use `Jido.Action` for all actions
- Use `Directive` for all effects
- No direct IO in actions

### File Organization

- Keep example self-contained in `hello_world/` directory
- Use relative requires in runner
- Follow naming conventions: `actions.exs`, `tree.exs`, `agent.exs`, `run.exs`

### Testing Approach

- Use `ExUnit.Case, async: true` for isolation
- Test success and failure paths
- Assert on both state and directives
- Use helper functions for common patterns

### Documentation Approach

- Keep README concise but complete
- Use ASCII diagrams for tree structure
- Show code examples for key concepts
- Include "What You'll Learn" section

---

## Next Steps After Implementation

1. **Item 008**: Create complementary example as part of jido (not jido_behaviortree)
2. **Documentation**: Add to "Getting Started" guide
3. **Community**: Share example in Discord/discussion
4. **Iteration**: Gather feedback and refine

---

## References

- Research: `.roadmap/.../007/research.md`
- Existing Example: `projects/jido_behaviortree/examples/bt_agent.exs`
- Strategy: `projects/jido_behaviortree/lib/jido_behaviortree/strategy/behavior_tree.ex`
- Nodes: `projects/jido_behaviortree/lib/jido_behaviortree/nodes/`
- Tests: `projects/jido_behaviortree/test/jido_behaviortree/`

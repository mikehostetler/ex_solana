# Research: Documentation Pass for jido_htn Modernization

## Item Overview

**ID**: 014-documentation-pass
**Title**: Documentation pass
**Section**: 3. Jido HTN Modernization

This item focuses on updating documentation for the modernized `jido_htn` module to reflect:
- Zoi-based error handling
- Effects system
- Signals for multi-agent coordination
- Current Jido patterns (actions, workflows)

## Codebase Analysis

### Key Documentation Locations

1. **Root Documentation Files**
   - `projects/jido_htn/README.md` - Currently a stub with TODO
   - `projects/jido_htn/guides/getting-started.md` - Comprehensive guide (558 lines)
   - `projects/jido_htn/JIDO_HTN_v1.md` - Technical inventory (247 lines)
   - `projects/jido_htn/JIDO_HTN_STRATEGY.md` - Strategy document
   - `projects/jido_htn/AGENTS.md` - Agent integration notes

2. **Inline Documentation (lib/)**
   - `lib/jido_htn.ex` - Commented out, needs @moduledoc
   - `lib/jido_htn/domain.ex` - Has basic @moduledoc, needs expansion
   - `lib/jido_htn/planner.ex` - Has minimal @moduledoc
   - `lib/jido_htn/compound_task.ex` - Needs @moduledoc
   - `lib/jido_htn/primitive_task.ex` - Needs @moduledoc
   - `lib/jido_htn/method.ex` - Needs @moduledoc
   - `lib/jido_htn/planner/*.ex` - Submodules need documentation

3. **Existing Guides**
   - `lib/jido_htn/htn_prompt_guide.md` - Prompt engineering guide

### Current Documentation Gaps

#### 1. README.md
**Status**: Placeholder only
**Needs**:
- Installation instructions (already present but basic)
- Quick start example
- Link to main guides
- Architecture overview
- Feature highlights

#### 2. Getting Started Guide
**Status**: Comprehensive but potentially outdated
**Content**: 558 lines covering:
- Installation
- Basic concepts (Domain, Compound/Primitive Tasks, Predicates, Transformers)
- State definition with structs
- Building domains with Builder DSL
- Running the planner
- Executing plans
- Concurrency patterns
- Testing with property-based testing
- Logging and observability

**Needs Update For**:
- Zoi schema constructors (new!/2 vs struct literals)
- New error handling patterns (explode errors from item 010)
- Effects system (item 012)
- Signals integration (item 013)
- Current Jido action patterns

#### 3. Module Documentation
**Status**: Sparse

**Key Modules Needing @moduledoc**:
- `Jido.HTN` - Main planner facade
- `Jido.HTN.Domain` - Domain builder and manager
- `Jido.HTN.CompoundTask` - Zoi schema
- `Jido.HTN.PrimitiveTask` - Zoi schema
- `Jido.HTN.Method` - Zoi schema
- `Jido.HTN.Planner.TaskDecomposer` - Core algorithm
- `Jido.HTN.Planner.EffectHandler` - Effects system
- `Jido.HTN.Planner.ConditionEvaluator` - Condition checking

### Modernization Context (Related Items)

This documentation pass depends on completion of:
- **Item 009**: Convert to Zoi error handling
- **Item 010**: Implement explode errors
- **Item 011**: Modernize to current Jido patterns
- **Item 012**: Define effects for HTN planning/execution
- **Item 013**: Define signals for multi-agent coordination

## Documentation Strategy

### Phase 1: Core Module Documentation

1. **Jido.HTN** (lib/jido_htn.ex)
   - Purpose: HTN planner facade
   - Main API: `plan/3`, `decompose/8`
   - Options: `:debug`, `:timeout`, `:root_tasks`, `:current_plan_mtr`
   - Return values with Zoi error tuples
   - Integration with Jido actions

2. **Jido.HTN.Domain** (lib/jido_htn/domain.ex)
   - Builder DSL usage
   - Zoi schema fields
   - Validation and error handling
   - Domain lifecycle (new → build → validate)

3. **Task Schemas**
   - `CompoundTask` - Hierarchical decomposition
   - `PrimitiveTask` - Action execution
   - `Method` - Decomposition strategies
   - Constructor patterns: `new!/2` with validation

### Phase 2: Planner Internals

1. **TaskDecomposer**
   - Recursive decomposition algorithm
   - Method selection and priority handling
   - State propagation during planning

2. **EffectHandler**
   - Effect application during planning
   - Expected vs actual effects
   - State simulation

3. **ConditionEvaluator**
   - Predicate evaluation
   - Callback resolution
   - Error handling with explode pattern

### Phase 3: Integration Documentation

1. **Effects System** (post-item 012)
   - How effects are defined
   - Effect execution during plan simulation
   - Effect composition patterns

2. **Signals** (post-item 013)
   - Signal emission during planning
   - Multi-agent coordination signals
   - Signal subscription patterns

3. **Error Handling** (post-items 009, 010)
   - Zoi validation errors
   - Explode error pattern
   - Recovery strategies

### Phase 4: Guide Updates

1. **Getting Started Guide Refresh**
   - Update for Zoi constructors
   - Modern error handling examples
   - Effects and signals examples
   - Current best practices

2. **New Guides Needed**
   - "Migrating from Legacy HTN API" - Migration guide
   - "HTN Effects Reference" - Complete effect catalog
   - "HTN Signals Reference" - Signal types and usage
   - "Error Handling in HTN" - Error taxonomy and handling
   - "Advanced Domain Patterns" - Complex domain structures

3. **Examples**
   - Minimal working example (MWE)
   - Real-world domain example
   - Multi-agent coordination example
   - Error recovery example

## File Changes Summary

### Files to Create
1. `projects/jido_htn/guides/migration.md` - Migration from legacy API
2. `projects/jido_htn/guides/effects.md` - Effects system guide
3. `projects/jido_htn/guides/signals.md` - Signals reference
4. `projects/jido_htn/guides/errors.md` - Error handling guide
5. `projects/jido_htn/examples/minimal.ex` - Minimal example
6. `projects/jido_htn/examples/advanced_domain.ex` - Complex example

### Files to Update Significantly
1. `projects/jido_htn/README.md` - Rewrite from stub
2. `projects/jido_htn/guides/getting-started.md` - Update for modernization
3. `projects/jido_htn/lib/jido_htn.ex` - Add @moduledoc
4. `projects/jido_htn/lib/jido_htn/domain.ex` - Expand @moduledoc
5. `projects/jido_htn/lib/jido_htn/planner.ex` - Expand @moduledoc
6. All task schema modules - Add @moduledoc
7. All planner submodule modules - Add @moduledoc

### Files to Review for Accuracy
1. `projects/jido_htn/JIDO_HTN_v1.md` - Update if still relevant
2. `projects/jido_htn/JIDO_HTN_STRATEGY.md` - Archive if obsolete
3. `projects/jido_htn/AGENTS.md` - Update for current patterns

## Success Criteria

1. **All public modules have @moduledoc**
   - Purpose and usage
   - Main API functions with @spec
   - Examples where appropriate
   - Return value documentation

2. **README.md is comprehensive**
   - Installation
   - Quick start
   - Feature overview
   - Links to guides
   - Architecture diagram (text/Mermaid)

3. **Getting Started Guide is modern**
   - Zoi constructor patterns
   - Current error handling
   - Effects and signals
   - Real-world examples

4. **Reference documentation complete**
   - Effects catalog
   - Signals reference
   - Error taxonomy
   - Migration guide

5. **Code examples run**
   - All examples tested
   - No outdated patterns
   - Clear comments

## Dependencies

This task should start AFTER:
- Item 009 (Zoi error handling)
- Item 010 (explode errors)
- Item 011 (Jido patterns modernization)
- Item 012 (Effects definition)
- Item 013 (Signals definition)

This ensures documentation reflects final implementation.

## Estimated Files to Modify

**Module Documentation**: ~15 files
- Main modules: 3
- Task schemas: 3
- Planner submodules: 6
- Utility modules: 3

**Guides**: ~6 files
- Create: 4 new guides
- Update: 2 existing guides

**Examples**: ~3 files
- Create: 2 examples
- Update: 1 existing

**Root Documentation**: 3 files
- README.md
- AGENTS.md
- Archive obsolete docs

**Total**: ~27 files

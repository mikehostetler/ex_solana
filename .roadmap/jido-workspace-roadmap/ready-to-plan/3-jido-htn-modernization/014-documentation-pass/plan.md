# Implementation Plan: Documentation Pass for jido_htn Modernization

**Item ID**: 014-documentation-pass
**Title**: Documentation pass
**Section**: 3. Jido HTN Modernization

---

## 1. Executive Summary

This implementation plan delivers comprehensive documentation for the modernized `jido_htn` module, reflecting the migration to Zoi schemas, effects system, signals for multi-agent coordination, and current Jido patterns. The approach is systematic: first complete all inline module documentation (@moduledoc), then refresh the getting-started guide with modern examples, create new reference guides for effects/signals/errors, add runnable examples, and finally rewrite the README as a complete project landing page.

**Key Architectural Decisions**:
- Documentation will mirror the actual implementation from items 009-013 (Zoi constructors, effects, signals)
- All code examples will be tested to ensure they run without modification
- Mermaid diagrams will be used for architecture visualization in Markdown
- Migration guide will help users transition from legacy API patterns

**Estimated Effort**: Medium (~27 files across 4 phases)

---

## 2. Impact Analysis Summary

### Key Findings from Research

The research (item 014/research.md) identified:
- **27 files** requiring creation or significant updates
- **15 modules** needing @moduledoc additions
- **4 new guides** needed (migration, effects, signals, errors)
- **1 existing guide** (getting-started.md) needing modernization for Zoi patterns
- **README.md** is currently a stub and needs complete rewrite

### Files Requiring Changes (Grouped by Phase)

**Phase 1 - Core Module Documentation**:
- `lib/jido_htn.ex` - Add comprehensive @moduledoc
- `lib/jido_htn/domain.ex` - Expand @moduledoc
- `lib/jido_htn/compound_task.ex` - Add @moduledoc
- `lib/jido_htn/primitive_task.ex` - Add @moduledoc
- `lib/jido_htn/method.ex` - Add @moduledoc
- `lib/jido_htn/planner.ex` - Expand @moduledoc

**Phase 2 - Planner Submodules**:
- `lib/jido_htn/planner/task_decomposer.ex` - Add @moduledoc
- `lib/jido_htn/planner/effect_handler.ex` - Add @moduledoc
- `lib/jido_htn/planner/condition_evaluator.ex` - Add @moduledoc
- `lib/jido_htn/planner/*.ex` - Any remaining submodules

**Phase 3 - Guides**:
- `guides/getting-started.md` - Update for Zoi, effects, signals
- `guides/migration.md` - CREATE: Migration from legacy API
- `guides/effects.md` - CREATE: Effects system reference
- `guides/signals.md` - CREATE: Signals reference
- `guides/errors.md` - CREATE: Error handling guide

**Phase 4 - Examples & README**:
- `examples/minimal.ex` - CREATE: Minimal working example
- `examples/advanced_domain.ex` - CREATE: Real-world example
- `README.md` - Complete rewrite
- `AGENTS.md` - Update for current patterns

### Existing Patterns to Follow

From research.md:
- Zoi schema constructors: `new!/2` returning `{:ok, t()} | {:error, term()}`
- Explode error pattern from item 010
- Effects defined in item 012 (directive-based)
- Signals defined in item 013
- Jido action patterns from item 011

### Integration Points Identified

- **Jido.HTN** is the main planner facade integrating with Jido actions
- **Jido.HTN.Domain** uses Zoi schemas for validation
- **EffectHandler** applies effects during planning simulation
- **Signals** enable multi-agent coordination

---

## 3. Feature Specification

### User Stories with Acceptance Criteria

**US1: As a new developer, I want to understand HTN concepts quickly**
- AC1: README has a clear architecture diagram
- AC2: Quick start example runs in under 5 minutes
- AC3: Concepts are explained with code snippets

**US2: As a contributor, I want to understand each module's purpose**
- AC1: All public modules have @moduledoc
- AC2: @moduledoc includes purpose, usage, and examples
- AC3: All public functions have @spec and @doc

**US3: As an existing user, I want to migrate from legacy HTN API**
- AC1: Migration guide exists
- AC2: Migration guide has before/after examples
- AC3: Breaking changes are clearly documented

**US4: As a developer, I want to understand effects and signals**
- AC1: Effects reference guide exists
- AC2: Signals reference guide exists
- AC3: Both guides have working examples

**US5: As a developer, I want to handle errors correctly**
- AC1: Error handling guide exists
- AC2: Error taxonomy is documented
- AC3: Recovery strategies are shown with examples

### API Contracts and Data Flow

**Documentation API**:
- All guides are Markdown in `guides/` directory
- All examples are runnable Elixir scripts in `examples/` directory
- Module docs follow ExDoc format (@moduledoc, @doc, @spec)

**Data Flow**:
1. User reads README for overview
2. User follows getting-started guide for concepts
3. User consults module docs for API details
4. User references specialized guides (effects, signals, errors)
5. User studies examples for patterns

### State Management Requirements

- Documentation state is static (files in repo)
- No runtime state management needed
- Examples should be self-contained

### Error Handling Approach

- Examples must demonstrate proper error handling
- Documentation should show both success and failure paths
- Migration guide should explain error handling changes

---

## 4. Technical Design

### Data Model Changes

No code changes required - this is pure documentation.

### Module Organization

Documentation structure mirrors code structure:
```
projects/jido_htn/
├── README.md                    (Phase 4)
├── guides/
│   ├── getting-started.md      (Phase 3 - update)
│   ├── migration.md            (Phase 3 - create)
│   ├── effects.md              (Phase 3 - create)
│   ├── signals.md              (Phase 3 - create)
│   └── errors.md               (Phase 3 - create)
├── examples/
│   ├── minimal.ex              (Phase 4 - create)
│   └── advanced_domain.ex      (Phase 4 - create)
└── lib/
    └── jido_htn/*.ex           (Phases 1-2 - @moduledoc)
```

### Third-Party Integration Details

- ExDoc for documentation generation
- Mermaid for diagrams in Markdown

### Configuration/Environment Changes

None required.

---

## 5. Implementation Phases

### Phase 1: Core Module Documentation

**Objective**: Add comprehensive @moduledoc to main public modules

**Success Criteria**:
- All main modules have complete @moduledoc
- @moduledoc includes purpose, usage examples, and links
- All public functions have @spec and @doc

**Files to Create/Modify**:
1. `lib/jido_htn.ex` - Add @moduledoc for planner facade
2. `lib/jido_htn/domain.ex` - Expand @moduledoc for builder DSL
3. `lib/jido_htn/compound_task.ex` - Add @moduledoc for schema
4. `lib/jido_htn/primitive_task.ex` - Add @moduledoc for schema
5. `lib/jido_htn/method.ex` - Add @moduledoc for schema
6. `lib/jido_htn/planner.ex` - Expand @moduledoc for planner module

**Tests to Add**:
- Verify all examples in docs compile/run
- No functional tests needed (documentation only)

**Dependencies on Other Work**:
- Requires items 009-013 to be complete (docs reflect actual implementation)

**Acceptance Criteria**:
- [ ] `mix docs` generates without warnings
- [ ] All code examples in docs are tested
- [ ] Each module has "Examples" section in @moduledoc

---

### Phase 2: Planner Submodules Documentation

**Objective**: Document internal planner modules for contributors

**Success Criteria**:
- All planner submodules have @moduledoc
- Algorithm explanations are clear
- Internal APIs are documented

**Files to Create/Modify**:
1. `lib/jido_htn/planner/task_decomposer.ex` - Document decomposition algorithm
2. `lib/jido_htn/planner/effect_handler.ex` - Document effect processing
3. `lib/jido_htn/planner/condition_evaluator.ex` - Document condition checking
4. Any remaining planner submodules

**Tests to Add**:
- Verify all examples compile

**Dependencies on Other Work**:
- Phase 1 complete

**Acceptance Criteria**:
- [ ] All submodules have @moduledoc
- [ ] `mix docs` generates clean
- [ ] Contributors can understand internals from docs

---

### Phase 3: Guide Updates

**Objective**: Create and update comprehensive user guides

**Success Criteria**:
- Getting-started guide reflects modernization
- New guides cover effects, signals, errors, migration
- All examples run without modification

**Files to Create/Modify**:
1. `guides/getting-started.md` - Update for Zoi constructors, effects, signals
2. `guides/migration.md` - CREATE: Migration from legacy API
3. `guides/effects.md` - CREATE: Effects system reference
4. `guides/signals.md` - CREATE: Signals reference
5. `guides/errors.md` - CREATE: Error handling guide

**Tests to Add**:
- Run all code examples from guides
- Verify links are valid

**Dependencies on Other Work**:
- Phases 1-2 complete
- Items 009-013 complete (docs must match implementation)

**Acceptance Criteria**:
- [ ] All code examples run
- [ ] Migration guide has before/after for each breaking change
- [ ] Effects/signals catalogs are complete
- [ ] Error taxonomy is documented

---

### Phase 4: Examples & README

**Objective**: Create runnable examples and comprehensive README

**Success Criteria**:
- README is complete project landing page
- Examples demonstrate key patterns
- All examples run as scripts

**Files to Create/Modify**:
1. `README.md` - Complete rewrite with quick start, architecture, features
2. `examples/minimal.ex` - CREATE: Minimal working example
3. `examples/advanced_domain.ex` - CREATE: Real-world domain example
4. `AGENTS.md` - Update for current Jido patterns

**Tests to Add**:
- Run each example: `elixir examples/minimal.ex`
- Verify README quick start works

**Dependencies on Other Work**:
- All previous phases complete

**Acceptance Criteria**:
- [ ] README has architecture diagram (Mermaid)
- [ ] Quick start takes <5 minutes
- [ ] All examples run without errors
- [ ] Examples are well-commented

---

## 6. Quality & Testing Strategy

### Test Categories

**Documentation Testing**:
- Compile all code examples in docs
- Run all example scripts
- Verify ExDoc generates without warnings

**Link Checking**:
- All internal links work
- All external references are accurate

**Content Quality**:
- Technical accuracy by comparing to implementation
- Completeness by checklist against research.md findings

### Coverage Targets

- 100% of public modules have @moduledoc
- 100% of public functions have @spec and @doc
- 100% of code examples tested

### Quality Gates Before Completion

1. **ExDoc Clean Build**: `mix docs` runs without warnings
2. **All Examples Run**: Each example script executes successfully
3. **Guide Review**: Getting-started guide tested by someone unfamiliar with HTN
4. **Migration Guide**: Verified against pre-modernization code

---

## 7. Risk Assessment

### Technical Risks

| Risk | Mitigation |
|------|------------|
| Docs don't match implementation | Wait for items 009-013 to complete; verify against source |
| Examples become outdated | Add to test suite; run examples in CI |
| ExDoc format changes | Use stable ExDoc version; follow official guides |

### Dependency Risks

| Risk | Mitigation |
|------|------------|
| Items 009-013 delayed | Document as implementation stabilizes; update if changes occur |
| API changes after documentation | Use examples as tests; catch breaking changes early |

### Timeline Risks

| Risk | Mitigation |
|------|------------|
| Scope creep (too many examples) | Start with minimal set; add advanced examples later |
| Guide length growth | Keep guides focused; link to module docs for details |

---

## 8. Success Criteria

### Measurable Outcomes

1. **Module Documentation**: 100% of public modules have @moduledoc with examples
2. **README**: Complete rewrite with architecture diagram and quick start
3. **Guides**: 5 comprehensive guides (getting-started, migration, effects, signals, errors)
4. **Examples**: 2+ runnable examples demonstrating patterns
5. **ExDoc**: Clean documentation build with zero warnings

### Definition of "Done"

- [ ] All 27 files from research.md are created or updated
- [ ] All code examples in documentation run successfully
- [ ] `mix docs` generates clean documentation
- [ ] README quick start can be completed in under 5 minutes
- [ ] Migration guide covers all breaking changes
- [ ] Effects and signals reference guides are complete
- [ ] At least 2 working examples exist (minimal, advanced)

### Acceptance Testing Approach

1. **New User Test**: Give README to someone unfamiliar with HTN; can they run quick start?
2. **Existing User Test**: Give migration guide to someone using legacy HTN; can they migrate?
3. **Example Test**: Run all example scripts; all pass
4. **Documentation Build**: `mix docs` succeeds with zero warnings
5. **Link Check**: All documentation links resolve correctly

---

## Dependencies

This task MUST start AFTER:
- Item 009: Convert to Zoi error handling
- Item 010: Implement explode errors
- Item 011: Modernize to current Jido patterns
- Item 012: Define effects for HTN planning/execution
- Item 013: Define signals for multi-agent coordination

This ensures documentation reflects the final, stable implementation.

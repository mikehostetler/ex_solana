# Implementation Plan: Write comprehensive documentation (moduledocs, guides, examples)

**Item ID:** `jido-workspace-roadmap/ready-to-plan/1-jido-core-20-release/003-write-comprehensive-documentation-module`

**Created:** 2025-01-07

---

## 1. Executive Summary

This implementation plan delivers comprehensive documentation for Jido Core 2.0 across the entire ecosystem (jido, jido_action, jido_signal, jido_ai). The approach focuses on three pillars: **completeness** (filling identified gaps), **quality** (ensuring all examples run correctly against v2 APIs), and **maintainability** (establishing patterns that prevent documentation drift).

Key architectural decisions:
- Use **LiveBook (.livemd)** for interactive, runnable tutorials in jido
- **Update existing examples** to use Jido 2.0 API patterns (Zoi schemas, not Ecto)
- **Establish documentation review checklist** as part of the release process
- Prioritize **missing jido guides** first, then **jido_ai documentation**, then **examples expansion**

Effort estimate: Medium - ~6-8 focused documentation sessions, can be done incrementally alongside other work.

---

## 2. Impact Analysis Summary

### Key Findings from Research

**Moduledoc Coverage:** Excellent - 100% across all packages (jido: 47 files, jido_action: 32 files, jido_signal: 29 files, jido_ai: 64 files).

**Existing Guide Coverage:**
- `jido_action`: 12 guides (comprehensive)
- `jido_signal`: 8 guides (comprehensive)
- `jido`: 8 guides (2 missing per TOC)
- `jido_ai`: 0 guides (gap identified)

**Identified Gaps:**
1. **Missing Jido guides** (per `JIDO_GUIDES_TOC.md`):
   - `guides/getting-started.livemd` - 5-minute quick start
   - `guides/fsm-strategy.livemd` - FSM strategy deep dive

2. **Jido.AI documentation needs:**
   - README references v1 API (`Jido.Workflow.run/2`)
   - Example uses Ecto schemas (should use Zoi)
   - No dedicated guide content

3. **Examples expansion:**
   - Only `examples/code_mapper/` exists
   - Need multi-agent patterns
   - Need AI integration examples

### Files Requiring Changes

**High Priority (Phase 1):**
- `projects/jido/guides/getting-started.livemd` (CREATE)
- `projects/jido/guides/fsm-strategy.livemd` (CREATE)
- `projects/jido_ai/README.md` (UPDATE)

**Medium Priority (Phase 2):**
- `projects/jido/examples/` (EXPAND - add 3-5 examples)
- `projects/jido_ai/guides/getting-started.md` (CREATE)
- `projects/jido_ai/guides/using-with-agents.md` (CREATE)
- `projects/jido_ai/guides/structured-output.md` (CREATE)
- `projects/jido_ai/guides/streaming.md` (CREATE)

**Lower Priority (Phase 3):**
- Update cross-references in existing guides if needed
- Create documentation review checklist

### Existing Patterns to Follow

1. **Moduledoc structure** from `Jido` module (projects/jido/lib/jido.ex):
   - One-line summary
   - Architecture section
   - Getting Started with examples
   - Core Concepts
   - API Reference
   - Examples

2. **Guide structure** from `JIDO_GUIDES_TOC.md`:
   - Clear purpose statement
   - Brief content focused on concepts
   - API details in moduledocs, not guides
   - Cross-references to related packages

3. **Example quality** from `jido_action` guides:
   - Runnable code examples
   - Clear explanations
   - Step-by-step progression

### Integration Points Identified

**Cross-Package Documentation References:**
- `jido` → `jido_action` (Actions), `jido_signal` (Signals/CloudEvents)
- `jido_action` → `jido` (Agent runtime), `jido_signal` (Signals)
- `jido_ai` → `jido` (Agent runtime), `jido_action` (Actions), `req_llm` (LLM client)

**Documentation Dependencies:**
- Zoi schemas - referenced for validation examples
- Splode - error handling patterns in moduledocs
- ReqLLM - LLM interactions in jido_ai

---

## 3. Feature Specification

### User Stories with Acceptance Criteria

**Story 1: New user wants to try Jido quickly**
- **As a** new Elixir developer
- **I want** a 5-minute getting started guide
- **So that** I can see Jido working with minimal setup
- **Acceptance Criteria:**
  - LiveBook format (.livemd)
  - Runs from zero dependencies (installs deps in notebook)
  - Creates simple agent with one action
  - Demonstrates both `cmd/2` and `AgentServer` usage
  - Clear next steps at end

**Story 2: User wants to understand FSM strategy pattern**
- **As a** Jido user
- **I want** a detailed FSM strategy example
- **So that** I can model stateful workflows
- **Acceptance Criteria:**
  - LiveBook format (.livemd)
  - Order fulfillment workflow (pending → confirmed → shipped → delivered)
  - Shows FSMX integration
  - Demonstrates state transitions
  - Runnable with visible state changes

**Story 3: User wants to use AI in their agents**
- **As a** Jido user
- **I want** clear AI integration docs
- **So that** I can add LLM capabilities to my agents
- **Acceptance Criteria:**
  - Getting started guide for jido_ai
  - Examples use Jido 2.0 API
  - Shows Zoi schema usage (not Ecto)
  - Demonstrates structured output
  - Shows streaming pattern
  - Integrates with Jido agents

**Story 4: User wants to see multi-agent patterns**
- **As a** Jido user
- **I want** example projects
- **So that** I can learn best practices for complex systems
- **Acceptance Criteria:**
  - 3-5 runnable examples
  - Multi-agent coordination example
  - AI integration example
  - Clear README for each example
  - Can be run with `mix run` or as script

### API Contracts and Data Flow

**Documentation Build Process:**
- Uses ExDoc (standard Elixir documentation tool)
- Run with `mix docs` from individual package directories
- Published to HexDocs automatically on release

**LiveBook Execution:**
- Users install LiveBook separately
- Each .livemd installs its own dependencies
- Cells can be executed individually
- Output shown inline

### State Management Requirements

- Documentation files are static (no runtime state)
- LiveBooks maintain their own execution state
- No cross-documentation state sharing

### Error Handling Approach

- Examples should handle errors gracefully
- Show both success and error paths where relevant
- Document Splade error patterns used in examples
- Include "troubleshooting" sections in guides

---

## 4. Technical Design

### Data Model Changes

No data model changes - this is pure documentation work.

### Module Organization Following Project Conventions

**New Files to Create:**

```
projects/jido/
├── guides/
│   ├── getting-started.livemd          (Phase 1)
│   └── fsm-strategy.livemd              (Phase 1)

projects/jido_ai/
├── guides/
│   ├── getting-started.md               (Phase 2)
│   ├── using-with-agents.md             (Phase 2)
│   ├── structured-output.md             (Phase 2)
│   └── streaming.md                     (Phase 2)

projects/jido/examples/
├── simple_agent/                        (Phase 3)
│   ├── README.md
│   ├── mix.exs
│   └── lib/
├── multi_agent_coordinator/             (Phase 3)
│   ├── README.md
│   ├── mix.exs
│   └── lib/
└── ai_integration/                      (Phase 3)
    ├── README.md
    ├── mix.exs
    └── lib/
```

### Third-Party Integration Details

**LiveBook:**
- Used for .livemd files
- Standard format: Elixir code cells with markdown
- Setup cells: `Mix.install([:jido, ...])`

**ExDoc:**
- Already configured in each package
- No additional setup needed

### Configuration/Environment Changes

No configuration changes - documentation builds use existing ExDoc configuration.

---

## 5. Implementation Phases

### Phase 1: Critical Jido Guides

**Objective:** Fill the two most critical documentation gaps identified in the Jido guides TOC.

**Success Criteria:**
- `getting-started.livemd` runs end-to-end in LiveBook
- `fsm-strategy.livemd` demonstrates complete FSM workflow
- Both guides follow existing guide structure patterns

**Files to Create:**
1. `projects/jido/guides/getting-started.livmd`
2. `projects/jido/guides/fsm-strategy.livemd`

**Tests to Add:**
- Manual: Run each LiveBook end-to-end before committing
- Verify all code cells execute without errors
- Verify output matches expected results described in prose

**Dependencies on Other Work:**
- None - can be done immediately
- Should verify against current jido API (ensure no drift)

**Detailed Tasks:**
1. Create `getting-started.livemd`:
   - Setup cell with `Mix.install([:jido])`
   - Define simple action
   - Create agent with action
   - Run agent with `Jido.cmd/2`
   - Show `AgentServer` usage
   - Include "What's Next" section

2. Create `fsm-strategy.livemd`:
   - Setup cell with dependencies
   - Define order states schema
   - Create FSM strategy with FSMX
   - Implement state transitions
   - Show agent running through workflow
   - Visualize state changes

---

### Phase 2: Jido.AI Documentation Update

**Objective:** Modernize jido_ai documentation to reflect Jido 2.0 patterns and provide comprehensive guides.

**Success Criteria:**
- README updated to use Jido 2.0 API
- Four comprehensive guides created
- All examples use Zoi schemas (not Ecto)

**Files to Modify:**
1. `projects/jido_ai/README.md` (UPDATE)

**Files to Create:**
1. `projects/jido_ai/guides/getting-started.md`
2. `projects/jido_ai/guides/using-with-agents.md`
3. `projects/jido_ai/guides/structured-output.md`
4. `projects/jido_ai/guides/streaming.md`

**Tests to Add:**
- Copy code from examples to test files
- Verify all examples compile and run
- Test AI examples with actual LLM calls (require API key)

**Dependencies on Other Work:**
- Should review current jido_ai API to ensure accuracy
- Coordinate with any jido_ai API changes

**Detailed Tasks:**
1. Update README.md:
   - Change example from Ecto to Zoi schemas
   - Update to use `Jido.AI` module directly
   - Remove any v1 API references
   - Verify example runs correctly

2. Create getting-started.md:
   - Installation instructions
   - Basic LLM call example
   - Structured output with Zoi schema
   - Error handling basics

3. Create using-with-agents.md:
   - Integrate Jido.AI actions into agents
   - Show prompt engineering patterns
   - Multi-turn conversation example
   - Tool calling example

4. Create structured-output.md:
   - Deep dive on Zoi schema usage
   - Complex nested schemas
   - Validation and error handling
   - Best practices

5. Create streaming.md:
   - Streaming response setup
   - Handling chunks
   - Accumulating results
   - Cancellation patterns

---

### Phase 3: Examples Expansion

**Objective:** Provide concrete, runnable example projects demonstrating common patterns.

**Success Criteria:**
- 3-5 complete example projects
- Each has clear README
- All examples run with `mix run` or as scripts

**Files to Create:**
1. `projects/jido/examples/simple_agent/`
2. `projects/jido/examples/multi_agent_coordinator/`
3. `projects/jido/examples/ai_integration/`
4. `projects/jido/examples/workflow_orchestration/` (optional)

**Tests to Add:**
- Each example should have test file
- Tests verify key functionality works
- Examples should be run as part of CI

**Dependencies on Other Work:**
- Can parallelize with Phase 2
- Use patterns from documented guides

**Detailed Tasks:**
1. Create simple_agent example:
   - Minimal agent with one action
   - Shows basic setup
   - README explains each component

2. Create multi_agent_coordinator example:
   - Two agents coordinating
   - Signal-based communication
   - Demonstrates supervision tree

3. Create ai_integration example:
   - Agent with AI action
   - Shows prompt/response flow
   - Error handling for AI failures

4. Create workflow_orchestration example (optional):
   - Complex workflow with multiple steps
   - FSM strategy usage
   - Error recovery patterns

---

### Phase 4: Documentation Quality Assurance

**Objective:** Ensure all documentation is accurate, consistent, and maintainable.

**Success Criteria:**
- All examples run without errors
- Cross-references are accurate
- Documentation review checklist created

**Files to Create:**
1. `projects/jido/DOCUMENTATION_CHECKLIST.md`
2. `projects/jido_action/DOCUMENTATION_CHECKLIST.md`
3. `projects/jido_signal/DOCUMENTATION_CHECKLIST.md`
4. `projects/jido_ai/DOCUMENTATION_CHECKLIST.md`

**Tests to Add:**
- Automated test that runs all example code
- Link checker for cross-references (if available)

**Dependencies on Other Work:**
- Must complete Phases 1-3 first
- Coordinate with item 004 (final quality audit)

**Detailed Tasks:**
1. Create documentation checklist template:
   - All code examples run?
   - All links valid?
   - API references accurate?
   - Cross-references correct?
   - Spelling/grammar check?

2. Run checklist on all documentation:
   - Verify each guide
   - Fix any issues found
   - Document any known limitations

3. Add checklist to release process:
   - Include in item 004 (final quality audit)
   - Ensure it runs before release

---

## 6. Quality & Testing Strategy

### Test Categories

**Documentation Testing:**
1. **LiveBook Execution Tests** (Phase 1)
   - Manual: Run each .livemd end-to-end
   - Verify all cells execute
   - Check output matches prose

2. **Example Code Tests** (Phase 2-3)
   - Extract code examples to test files
   - Run as part of package test suite
   - Ensure they compile and run correctly

3. **Link Validation** (Phase 4)
   - Check all internal cross-references
   - Check external links
   - Verify module/function links work

### Coverage Targets

- **Code Examples:** 100% of examples should be runnable
- **Links:** 100% of cross-references should resolve
- **API References:** All referenced modules/functions should exist

### Quality Gates Before Completion

- All LiveBooks run without errors
- All example projects run with `mix test`
- All links verified
- README examples tested
- Documentation checklist completed

---

## 7. Risk Assessment

### Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| API changes during documentation work | Medium | High | Complete documentation after API freezes (coordinate with item 001) |
| Examples break due to dependency updates | Low | Medium | Pin dependency versions in examples |
| LiveBook format changes | Low | Low | Use stable LiveBook features only |

### Dependency Risks

| Dependency | Risk | Mitigation |
|------------|------|------------|
| Item 001 (code review) | APIs may change | Coordinate timing - document after review |
| Item 002 (test coverage) | Examples should follow test patterns | Use established test patterns from research |

### Timeline Risks

| Risk | Mitigation |
|------|------------|
| Documentation takes longer than estimated | Work incrementally - can ship with partial docs |
| Scope creep (too many examples) | Define clear scope in each phase |
| competing priorities | Can be done in parallel with other items |

---

## 8. Success Criteria

### Measurable Outcomes

**Quantitative:**
- 2 new LiveBook guides for jido (getting-started, fsm-strategy)
- 4 new guides for jido_ai (getting-started, using-with-agents, structured-output, streaming)
- 3-5 new example projects
- 1 documentation review checklist per package
- 100% of code examples runnable

**Qualitative:**
- New users can get started in <5 minutes
- FSM pattern is clear and understandable
- AI integration is well-documented
- Examples demonstrate best practices

### Definition of "Done"

An item is done when:
1. All planned files are created
2. All code examples run without errors
3. Documentation checklist is completed
4. At least one other person has reviewed the documentation
5. Any feedback from review is addressed

### Acceptance Testing Approach

**Phase 1 Acceptance:**
- Open getting-started.livemd in LiveBook
- Run all cells in order
- Verify no errors
- Repeat for fsm-strategy.livemd

**Phase 2 Acceptance:**
- Read updated README - verify no v1 references
- Follow each guide step-by-step
- Copy code examples to test file
- Run tests - verify they pass

**Phase 3 Acceptance:**
- For each example:
  - `cd` to example directory
  - Run `mix deps.get`
  - Run `mix test`
  - Run example manually with `mix run`
  - Verify README instructions are accurate

**Phase 4 Acceptance:**
- Run documentation checklist
- Verify all items pass
- Have team member review

---

## Appendix A: LiveBook Template

```markdown
# Guide Title

## Setup

```elixir
Mix.install([
  {:jido, "~> 2.0"},
  # ... other deps
])
```

## Section Title

[Explanation text]

```elixir
# Code example
```

[More explanation]

## Next Steps

[Links to related guides and documentation]
```

## Appendix B: Documentation Checklist Template

```markdown
# Documentation Review Checklist

## Code Examples
- [ ] All code examples compile
- [ ] All code examples run without errors
- [ ] Output matches descriptions in prose

## Links
- [ ] All internal links resolve
- [ ] All external links resolve
- [ ] All module/function references exist

## Accuracy
- [ ] API references are current
- [ ] Function signatures are correct
- [ ] Examples use current patterns (Zoi, not Ecto)

## Clarity
- [ ] Spelling/grammar checked
- [ ] Technical terms explained
- [ ] Examples have context

## Completeness
- [ ] No "TODO" comments in documentation
- [ ] All referenced features are documented
- [ ] Cross-references are reciprocal
```

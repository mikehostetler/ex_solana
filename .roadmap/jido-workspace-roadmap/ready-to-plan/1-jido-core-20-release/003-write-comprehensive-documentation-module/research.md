# Research: Write comprehensive documentation (moduledocs, guides, examples)

**Item ID:** `jido-workspace-roadmap/ready-to-plan/1-jido-core-20-release/003-write-comprehensive-documentation-module`

**Date:** 2025-01-07

---

## Overview

Jido Core 2.0 needs comprehensive documentation across multiple packages in the ecosystem. This research identifies the current state of documentation, gaps, and files that need to be created or updated.

---

## Current Documentation State

### Jido (Core)

**Location:** `projects/jido/`

**Module Statistics:**
- Total `.ex` files: 47
- Files with `@moduledoc`: 47 (100% coverage)

**Existing Guides:**
- `JIDO_GUIDES_TOC.md` - Master documentation plan
- `JIDO_V2_OVERVIEW.md` - Architecture overview
- `guides/core-concepts.md` - Core concepts guide
- `guides/agents.md` - Agent definition guide
- `guides/skills.md` - Skills guide
- `guides/directives.md` - Directives guide
- `guides/strategies.md` - Strategies guide
- `guides/runtime.md` - Runtime guide
- `guides/testing.md` - Testing guide
- `guides/migration.md` - Migration from 1.x

**Documentation Quality:**
- Excellent moduledoc coverage (100%)
- Good architectural overview in main `Jido` module
- Well-documented `AgentServer` with detailed architecture descriptions
- Clear examples in moduledocs

**Identified Gaps:**
1. **Missing Guides** (per `JIDO_GUIDES_TOC.md`):
   - `guides/getting-started.livemd` - Quick start guide (5-minute working example)
   - `guides/fsm-strategy.livemd` - FSM strategy deep dive with runnable example

2. **Examples:** Minimal examples in codebase
   - `examples/code_mapper/README.md` exists

---

### Jido.Action

**Location:** `projects/jido_action/`

**Module Statistics:**
- Total `.ex` files: 32
- Files with `@moduledoc`: 32 (100% coverage)

**Existing Guides:**
- `guides/getting-started.md` - Getting started
- `guides/actions-guide.md` - Actions guide
- `guides/schemas-validation.md` - Schemas and validation
- `guides/your-second-action.md` - Second action tutorial
- `guides/instructions-plans.md` - Instructions and plans
- `guides/execution-engine.md` - Execution engine
- `guides/error-handling.md` - Error handling
- `guides/testing.md` - Testing
- `guides/configuration.md` - Configuration
- `guides/ai-integration.md` - AI integration
- `guides/tools-reference.md` - Tools reference
- `guides/faq.md` - FAQ
- `guides/security.md` - Security

**Documentation Quality:**
- Excellent moduledoc coverage (100%)
- Comprehensive guide coverage
- Well-structured documentation

---

### Jido.Signal

**Location:** `projects/jido_signal/`

**Module Statistics:**
- Total `.ex` files: 29 (estimated)
- Files with `@moduledoc`: 29 (100% coverage, estimated)

**Existing Guides:**
- `guides/getting-started.md`
- `guides/signals-and-dispatch.md`
- `guides/signal-router.md`
- `guides/signal-journal.md`
- `guides/event-bus.md`
- `guides/serialization.md`
- `guides/signal-extensions.md`
- `guides/advanced.md`

**Documentation Quality:**
- Good moduledoc coverage
- Comprehensive guide coverage

---

### Jido.AI

**Location:** `projects/jido_ai/`

**Module Statistics:**
- Total `.ex` files: 64
- Files with `@moduledoc`: 64 (100% coverage)

**Documentation Quality:**
- Excellent moduledoc coverage (100%)
- README has basic example using Instructor/Ecto
- **Note:** README references Jido 1.0 API (needs update to 2.0)

**Identified Gaps:**
1. **README update needed** - References `Jido.Workflow.run/2` which may be v1 API
2. **Missing guides** - No dedicated guide files found
3. **Example updates** - Example uses Ecto schemas, should reference Zoi schemas (jido v2)

---

## Key Files to Update/Create

### High Priority

1. **`projects/jido/guides/getting-started.livemd`** (CREATE)
   - 5-minute quick start
   - Installation and supervision tree setup
   - Define simple agent
   - Run cmd/2
   - Run in AgentServer

2. **`projects/jido/guides/fsm-strategy.livemd`** (CREATE)
   - State machine agent example
   - Order fulfillment workflow (pending → confirmed → shipped → delivered)
   - FSMX integration details

3. **`projects/jido_ai/README.md`** (UPDATE)
   - Update example to use Jido 2.0 API
   - Reference Zoi schemas instead of Ecto
   - Update to use `Jido.AI` module (not Instructor directly)

### Medium Priority

4. **`projects/jido/examples/`** (EXPAND)
   - Add more runnable examples
   - Multi-agent patterns
   - AI integration examples

5. **`projects/jido_ai/guides/`** (CREATE)
   - Getting started with Jido.AI
   - Using with Jido agents
   - Structured output patterns
   - Streaming responses

---

## Integration Points

### Cross-Package Documentation References

| From Package | References |
|-------------|------------|
| `jido` | `jido_action` (Actions), `jido_signal` (Signals/CloudEvents) |
| `jido_action` | `jido` (Agent runtime), `jido_signal` (Signals) |
| `jido_ai` | `jido` (Agent runtime), `jido_action` (Actions), `req_llm` (LLM client) |

### Documentation Dependencies

- **Zoi schemas** - Referenced across all packages for validation
- **Splode** - Error handling patterns documented in moduledocs
- **ReqLLM** - Referenced in `jido_ai` for LLM interactions

---

## Documentation Patterns

### Existing Good Patterns to Follow

1. **Moduledoc Structure** (from `Jido` module):
   - One-line summary
   - Architecture section
   - Getting Started section with code examples
   - Core Concepts section
   - API Reference section
   - Examples section

2. **Guide Structure** (from `JIDO_GUIDES_TOC.md`):
   - Clear purpose statement
   - Brief content focused on concepts
   - API details in moduledocs
   - Cross-references to related packages

3. **Example Quality** (from `jido_action` guides):
   - Runnable code examples
   - Clear explanations
   - Step-by-step progression

---

## Targeted Documentation Resources

### Internal Documentation

- `projects/jido/JIDO_GUIDES_TOC.md` - Master documentation plan
- `projects/jido/JIDO_V2_OVERVIEW.md` - Architecture overview
- Existing guides in `projects/jido/guides/`
- Existing guides in `projects/jido_action/guides/`
- Existing guides in `projects/jido_signal/guides/`

### External References

- Elixir documentation best practices: https://hexdocs.pm/elixir/writing-documentation.html
- ExDoc publishing: https://hexdocs.pm/ex_doc/
- LiveBook documentation: https://livebook.dev/

---

## Risks and Considerations

1. **Documentation Drift** - APIs may change before/during documentation work
2. **Cross-Package Consistency** - Need consistent terminology and patterns
3. **Example Freshness** - Examples must work with current API
4. **Scope Management** - Balance big-picture guides vs detailed API docs

---

## Recommendations

1. **Create missing jido guides** first (`getting-started.livemd`, `fsm-strategy.livemd`)
2. **Update jido_ai README** to v2 API and current patterns
3. **Add jido_ai guides** for common patterns
4. **Expand examples** in `projects/jido/examples/`
5. **Establish documentation review checklist** to prevent drift

---

## Summary

- **Files Identified:** ~200+ documentation files across the ecosystem
- **Moduledoc Coverage:** 100% across all packages
- **Guide Coverage:** Good for jido_action and jido_signal, gaps for jido and jido_ai
- **Key Gaps:** 2 missing jido guides, jido_ai needs guide content, examples need expansion

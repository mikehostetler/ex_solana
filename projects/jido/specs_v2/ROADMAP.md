# Jido 2.0 Specification Roadmap

> A guide to the remaining specification documents needed to fully document Jido 2.0.

---

## Completed Specifications

| Document | Status | Description |
|----------|--------|-------------|
| [core-thesis.md](./core-thesis.md) | ✅ Complete | Foundational vision, architecture, and design principles |
| [primitives.md](./primitives.md) | ✅ Complete | Reference for all core nouns and their contracts (v2: Effect/Directive distinction, LiveView-style callbacks) |
| [runners-spec.md](./runners-spec.md) | ✅ Complete | Comprehensive runner architecture from Simple to HTN |
| [effect-batching-spec.md](./effect-batching-spec.md) | ✅ Complete | Effect.Meta for organizing/prioritizing large effect lists |
| [skill-spec.md](./skill-spec.md) | ✅ Complete | Skills as pluggable capability bundles (Actions + signal handlers) |

---

## Specification Roadmap

Documents are organized by priority and dependency. **Kernel** specs must be completed before implementation. **Battery** specs can evolve alongside features.

### Phase 1: Kernel Specifications (Required for V2)

These documents define the core contracts and are prerequisites for implementation.

#### 1. `effects-spec.md`
**Priority:** High | **Effort:** Medium | **Layer:** Kernel

**Purpose:** Normative definition of every Effect and its execution semantics.

**Contents:**
- Complete type definitions for all 11 effect types
- Execution rules per effect (e.g., Timer uses `Process.send_after/3`)
- Agent-local vs Server-side effect classification
- Error semantics (invalid effects, partial failures)
- Idempotency and retryability guarantees
- Validation rules

**Dependencies:** primitives.md

---

#### 2. `agent-server-spec.md`
**Priority:** High | **Effort:** Medium | **Layer:** Kernel

**Purpose:** Define the runtime contract of AgentServer.

**Contents:**
- Public API specification (start, stop, send_signal, get_state)
- Signal processing lifecycle
- Effect execution loop
- Queue management and backpressure
- Timeout and error handling
- Integration with OTP supervision
- Instrumentation and telemetry hooks
- V1 → V2 mapping for `Agent.run/2` semantics

**Dependencies:** effects-spec.md

---

#### 3. `runner-state-machine-spec.md`
**Priority:** High | **Effort:** Medium-Large | **Layer:** Kernel

**Purpose:** Fully specify the built-in state machine runner.

**Contents:**
- State machine data model (states, transitions, guards, effects)
- DSL-free configuration (pure data structures)
- Integration with `handle_signal/2`
- Guard evaluation semantics
- Effect handler execution order
- Introspection APIs (`states/1`, `transitions_from/2`, `to_mermaid/1`)
- Validation and error reporting
- Examples without Spark DSL

**Dependencies:** agent-server-spec.md

---

#### 4. `schema-validation-spec.md`
**Priority:** High | **Effort:** Medium | **Layer:** Kernel

**Purpose:** Consolidate the move from NimbleOptions to Zoi.

**Contents:**
- Agent state schema declaration
- Action parameter schema declaration
- Validation lifecycle (when validation happens)
- Error message formatting
- Coercion rules
- NimbleOptions → Zoi migration strategy
- Adapter for V1 compatibility
- Deprecation timeline

**Dependencies:** primitives.md

---

#### 5. `signal-spec.md`
**Priority:** Medium | **Effort:** Small | **Layer:** Kernel

**Purpose:** Detailed specification of the Signal struct and lifecycle.

**Contents:**
- Signal creation and factory functions
- Standard signal types
- Correlation and causation tracking
- Trace context propagation
- Serialization format
- Signal routing

**Dependencies:** primitives.md

---

#### 6. `action-spec.md`
**Priority:** Medium | **Effort:** Medium | **Layer:** Kernel

**Purpose:** Complete specification for Actions.

**Contents:**
- Action behaviour and `use Jido.Action` macro
- Schema definition with Zoi
- Execution context
- Result types and error handling
- Timeouts and cancellation
- Action metadata for introspection
- Tool generation (`to_tool/1`)

**Dependencies:** schema-validation-spec.md

---

### Phase 2: Migration & Testing

These documents support the transition from V1 and establish testing patterns.

#### 7. `migration-v1-to-v2.md`
**Priority:** High | **Effort:** Medium | **Layer:** Kernel/Battery boundary

**Purpose:** Help existing users upgrade from V1.

**Contents:**
- Conceptual side-by-side comparison
  - V1 Agent vs V2 Agent
  - V1 NimbleOptions vs V2 Zoi
  - V1 Effects vs V2 Effects (with Reply, Timer additions)
- Mechanical migration steps
  - Return type changes: `{:ok, result}` → `{:ok, state, effects}`
  - Action planning/running to Effect model
- Transitional adapters and compatibility layer
- Deprecation warnings and timeline
- Common migration patterns

**Dependencies:** All Phase 1 specs

---

#### 8. `testing-replay-spec.md`
**Priority:** Medium | **Effort:** Small-Medium | **Layer:** Kernel

**Purpose:** Codify testing and replay as first-class capabilities.

**Contents:**
- Unit testing patterns for Agents
  - Using `init/2`, `handle_signal/2` directly
  - Asserting state and effects
- Integration testing with AgentServer
  - Starting servers, sending signals, asserting outcomes
- Replay story
  - Logging schema: `(state_before, signal, state_after, effects)`
  - Replay APIs (`Jido.Replay.run/3`)
  - Offline evaluation patterns
- Test helpers and utilities

**Dependencies:** agent-server-spec.md

---

### Phase 3: Battery Specifications

These documents define optional features that extend the kernel.

#### 9. `dsl-spark-spec.md`
**Priority:** Medium | **Effort:** Medium-Large | **Layer:** Battery

**Purpose:** Define the optional Spark DSL.

**Contents:**
- DSL sections: `runner do`, `state do`, `signals do`
- How DSL compiles to kernel contracts
  - Generates `handle_signal/2`
  - Generates struct + Zoi schema
- Extension points for custom DSL sections
- What is explicitly not provided in V2.0
- Relationship to non-DSL path (all examples work without DSL)

**Dependencies:** runner-state-machine-spec.md, schema-validation-spec.md

---

#### 10. `llm-runners-spec.md`
**Priority:** Medium | **Effort:** Medium | **Layer:** Battery
**Status:** ✅ Merged into [runners-spec.md](./runners-spec.md)

**Purpose:** Specification for LLM-powered runners.

> **Note:** This content has been incorporated into the comprehensive `runners-spec.md`, which covers Simple, StateMachine, ChainOfThought, ReAct, BehaviorTree, and HTN runners in a single document.

**Dependencies:** action-spec.md, primitives.md (Tool, Skill)

---

#### 11. `observability-introspection-spec.md`
**Priority:** Low | **Effort:** Small-Medium | **Layer:** Battery

**Purpose:** Specify how agents expose internal structure.

**Contents:**
- State machine introspection APIs
- Runner telemetry events
- Workbench UI integration points
- Metadata exposition
- Mermaid diagram generation
- Custom instrumentation hooks

**Dependencies:** runner-state-machine-spec.md

---

#### 12. `interop-spec.md`
**Priority:** Low | **Effort:** Medium | **Layer:** Battery

**Purpose:** Specification for cross-runtime interoperability.

**Contents:**
- Python tool execution
- JavaScript/Node.js tool execution
- MCP (Model Context Protocol) integration
- Remote action invocation
- Serialization formats
- Error handling across boundaries

**Dependencies:** action-spec.md

---

### Phase 4: Reference & Examples

#### 13. `architecture-overview.md`
**Priority:** High (but can be written last) | **Effort:** Medium | **Layer:** Reference

**Purpose:** "Big picture" document linking all others.

**Contents:**
- High-level diagrams
  - Sequence diagrams for common flows
  - Component relationships
- Pointers to other spec documents
- Typical Jido app module layout
- Quick start guide
- Index for new contributors

**Dependencies:** All other specs (synthesizes them)

---

#### 14. `examples/` directory
**Priority:** Medium | **Effort:** Ongoing | **Layer:** Reference

**Purpose:** Working examples demonstrating Jido 2.0 patterns.

**Contents:**
- `simple_echo_agent.ex` - Minimal agent (15 lines)
- `faq_bot.ex` - State machine with action dispatch
- `onboarding_flow.ex` - Multi-step deterministic workflow
- `research_assistant.ex` - ReAct-powered LLM agent
- `order_processor.ex` - Behavior tree example
- `migration_example.ex` - V1 to V2 migration

---

## Dependency Graph

```
                         primitives.md
                              │
              ┌───────────────┼───────────────┐
              │               │               │
              ▼               ▼               ▼
      effects-spec   signal-spec   schema-validation-spec
              │                               │
              ▼                               ▼
      agent-server-spec               action-spec
              │                               │
              ├───────────────┬───────────────┤
              │               │               │
              ▼               ▼               ▼
   runner-state-machine   testing-replay   llm-runners-spec
              │               │
              ▼               ▼
        dsl-spark-spec   migration-v1-to-v2
              │
              ▼
   observability-introspection
              │
              ▼
    architecture-overview (synthesizes all)
```

---

## Writing Guidelines

### Spec Document Structure

Each specification should follow this structure:

```markdown
# [Component] Specification

> One-line summary

---

## Overview
Brief description of purpose and scope.

## Terminology
Key terms used in this document.

## Requirements
MUST/SHOULD/MAY requirements (RFC 2119 style).

## Type Definitions
Elixir typespecs and struct definitions.

## Behaviour/API
Function signatures and contracts.

## Semantics
Detailed explanation of how things work.

## Examples
Code examples demonstrating usage.

## Error Handling
Error types and recovery patterns.

## Migration Notes (if applicable)
Changes from V1.

## Open Questions (during draft)
Unresolved design decisions.

---

*Version: X.Y.Z-draft*
*Last Updated: [Date]*
```

### Principles

1. **Kernel First** - All specs should work without Spark DSL
2. **Show the Types** - Include Elixir typespecs for everything
3. **Test Examples** - Examples should be copy-pasteable and runnable
4. **V1 Context** - Note what's changing from V1 where relevant
5. **Batteries Separate** - Clearly mark what's kernel vs battery

---

## Timeline Suggestion

| Week | Focus | Deliverables |
|------|-------|--------------|
| 1 | Core contracts | effects-spec, signal-spec |
| 2 | Runtime | agent-server-spec |
| 3 | Validation | schema-validation-spec, action-spec |
| 4 | Runner | runner-state-machine-spec |
| 5 | Migration | migration-v1-to-v2, testing-replay-spec |
| 6+ | Batteries | dsl-spark-spec, llm-runners-spec |
| Ongoing | Reference | architecture-overview, examples |

---

## Review Checklist

Before marking a spec complete:

- [ ] All types are defined with Elixir typespecs
- [ ] At least 3 runnable examples included
- [ ] Error cases documented
- [ ] Kernel vs Battery clearly marked
- [ ] V1 migration notes included (where applicable)
- [ ] Reviewed against core-thesis.md for consistency
- [ ] No conflicts with other specs

---

*Roadmap Version: 1.0.0*  
*Last Updated: December 2024*

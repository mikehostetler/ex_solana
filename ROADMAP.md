# Jido Workspace Roadmap

## Status Legend

| State | Description |
|-------|-------------|
| `READY` | Ready to plan and begin work |
| `PLANNED` | Has plan/PRD, ready for implementation |
| `IN_PROGRESS` | Actively being worked on |
| `IN_REVIEW` | PR open, awaiting review/merge |
| `DONE` | Complete |
| `DELEGATED` | Assigned to someone else |
| `BACKLOG` | Parked for future consideration |

---

## Ready to Plan

### 1. Jido Core 2.0 Release

**Project:** `jido` (v2 branch)  
**Kind:** implementation  
**Priority:** highest

Ship Jido Core 2.0 with production-quality code, comprehensive tests, and documentation.

**Tasks:**

- [ ] Hand review all code — audit modules for correctness, patterns, edge cases
- [ ] Maximize test coverage — target >90% coverage on core modules
- [ ] Write comprehensive documentation — moduledocs, guides, examples
- [ ] Final quality audit before release — dialyzer clean, credo clean, no warnings

---

### 2. Jido Behavior Tree v1

**Project:** `jido_behaviortree`  
**Kind:** implementation  
**Priority:** high

Integrate behavior tree execution with Jido's effects and signals system.

**Tasks:**

- [ ] Define effects for behavior tree execution
- [ ] Define signals for state transitions/events
- [ ] Create example: behavior tree as Jido strategy
- [ ] Create example: behavior tree as part of a larger strategy

---

### 3. Jido HTN Modernization

**Project:** `jido_htn`  
**Kind:** implementation  
**Priority:** high

Modernize HTN planner to current Jido patterns and integrate with effects/signals.

**Tasks:**

- [ ] Convert to Zoi error handling
- [ ] Implement explode errors
- [ ] Modernize to current Jido patterns (actions, schemas)
- [ ] Define effects for HTN planning/execution
- [ ] Define signals for multi-agent coordination
- [ ] Documentation pass

---

### 4. Ash.jido Integration

**Project:** `ash_jido`  
**Kind:** implementation  
**Priority:** medium

Validate and demonstrate Ash framework integration with Jido.

**Tasks:**

- [ ] Review current implementation
- [ ] Validate Ash resources exposed as Jido actions
- [ ] Create demo showing Ash + Jido integration strategy

---

### 5. Ash.ai PR

**Project:** `ash_ai`  
**Kind:** implementation  
**Priority:** medium

**Tasks:**

- [ ] Update outstanding draft PR

---

### 6. Jido Messaging v1

**Project:** `jido_messaging`  
**Kind:** implementation  
**Priority:** medium

New messaging layer to replace jido_chat.

**Tasks:**

- [ ] Define scope/architecture
- [ ] Initial implementation

---

### 7. Jido Hub MVP

**Project:** `jido_hub`  
**Kind:** implementation  
**Priority:** medium

Web interface for interacting with Jido agents.

**Tasks:**

- [ ] Phoenix project setup
- [ ] LibreChat-style chat interface
- [ ] Integration with Jido agents

---

### 8. ReqLLM Video Series

**Project:** `req_llm`  
**Kind:** content  
**Priority:** medium

Educational video series (already planned).

**Tasks:**

- [ ] Record 15 agent videos
- [ ] Edit and publish video series

---

## Delegated

### Jido AI 2.0 Release

**Project:** `jido_ai` (v2 branch)  
**Assignee:** Pascal  
**Kind:** implementation

Ship Jido AI 2.0 alongside core release.

**Tasks:**

- [ ] Hand review all code
- [ ] Maximize test coverage
- [ ] Write comprehensive documentation
- [ ] Final quality audit before release

---

## Backlog

### Jido Chat Deprecation

**Project:** `jido_chat`  
**Kind:** implementation  
**Blocked by:** Jido Messaging v1

- [ ] Migrate any remaining functionality to jido_messaging
- [ ] Update dependents
- [ ] Archive repository

---

### Karo v0 Design

**Project:** `karo`  
**Kind:** decision

Personal "god agent" that sits atop the entire Jido stack.

**Questions to resolve:**

- [ ] Define Karo's core identity/purpose
- [ ] Persistence strategy (agent state survives restarts)
- [ ] Multi-agent orchestration (Karo delegates to specialist agents?)
- [ ] Capability composition (which capabilities does Karo load?)
- [ ] Memory/context management (long-term + working memory)
- [ ] Interface: CLI? Jido Hub? API?
- [ ] Personal automation hooks (calendar, tasks, notes, etc.)

---

### ReqLLM Back-pressure Spike

**Project:** `req_llm`  
**Kind:** decision

Agent back-pressure architecture spike.

**Tasks:**

- [ ] Review existing spike work
- [ ] **Decision:** Continue or shelf?
- [ ] If continue: define scope and timeline
- [ ] If shelf: document current state for future pickup

---

### Capabilities Architecture

**Project:** *new — likely `jido` or `jido_capabilities`*  
**Kind:** decision  
**Blocks:** Task Management Capability, Planning Capability, Jido Context

Pluggable deep capabilities that agents can compose.

**Questions to resolve:**

- [ ] How do capabilities register with an agent?
- [ ] How do capabilities declare their actions/signals/effects?
- [ ] Can capabilities depend on other capabilities?
- [ ] How does persistence work across capabilities? (ties to Jido Context)

---

### Task Management Capability

**Project:** *TBD — depends on Capabilities Architecture*  
**Kind:** implementation  
**Blocked by:** Capabilities Architecture

- [ ] Define task schema (goal, subtasks, state, dependencies, priority)
- [ ] Action: create task from natural language
- [ ] Action: decompose task into subtasks (manual or LLM-assisted)
- [ ] Action: update task state (pending → in-progress → blocked → complete)
- [ ] Action: query/filter tasks
- [ ] Signals: task_created, task_updated, task_completed, task_blocked
- [ ] Effects: persistence hooks, notification hooks
- [ ] Integration point with Jido HTN for automated decomposition

---

### Planning Capability

**Project:** *TBD — depends on Capabilities Architecture*  
**Kind:** implementation  
**Blocked by:** Capabilities Architecture

- [ ] Define plan schema (goal, steps, dependencies, current_step)
- [ ] Action: generate plan from goal (LLM-backed)
- [ ] Action: validate plan feasibility
- [ ] Action: execute plan step
- [ ] Action: replan on failure
- [ ] Signals: plan_created, step_completed, plan_failed, replanning
- [ ] Integration point with Jido HTN for hierarchical decomposition
- [ ] Integration point with Jido Behavior Tree for execution patterns

---

### Jido Context v1

**Project:** `jido` (or new module)  
**Kind:** implementation  
**Blocked by:** Capabilities Architecture

- [ ] Design API for context forking
- [ ] Design API for context compaction
- [ ] JSON/JSONB serialization for storage
- [ ] Retrieval/hydration patterns

---

### Jido Guides & Docs

**Project:** *docs*  
**Kind:** content  
**Blocked by:** Jido Core 2.0 Release

- [ ] Identify key "what's possible" topics
- [ ] Write core guides (in-house)
- [ ] Define bounty-able guide topics
- [ ] Post bounties for community contributions
- [ ] Review/edit bounty submissions
- [ ] Publish and promote

---

### Jido Video Series

**Project:** *content*  
**Kind:** content  
**Blocked by:** Jido Guides & Docs

- [ ] Plan video topics for building Jido agents
- [ ] Script/outline each video
- [ ] Record videos
- [ ] Edit and publish

---

### ex-Solana Monorepo Split

**Project:** `ex_solana`  
**Kind:** implementation  
**Priority:** lowest

- [ ] Extract Solana API client package
- [ ] Extract JITO client package (MEV protocol)
- [ ] Identify/extract other discrete packages
- [ ] Thorough test coverage per package
- [ ] Documentation for each package

---

### LLMDB Open Graph Tags

**Project:** `llm_db`  
**Kind:** implementation  
**Priority:** low

- [ ] Add proper Open Graph tags to website

---

## Done

### Jido Action

**Project:** `jido_action`

- [x] Complete — good state

---

### Jido Signal

**Project:** `jido_signal`

- [x] Complete — good state

---

## Notes

**Content dependency:** Jido Guides & Docs and Jido Video Series are gated on Core 2.0 shipping. ReqLLM videos can proceed in parallel.

**Sequencing options:** ReqLLM videos and Jido videos could be batched together for recording efficiency, or sequenced if context-switching is costly.

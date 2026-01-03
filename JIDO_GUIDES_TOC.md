# Jido 2.0 Documentation Guides

> Streamlined guide structure. API details live in module `@moduledoc`.
> Actions/schemas → see `jido_action` docs. Signals/routing → see `jido_signal` docs.

---

## Guides to Write

### 1. Quick Start
**File:** `guides/getting-started.livemd`

Installation. Add `{Jido, name: MyApp.Jido}` to supervision tree. Define agent with `use Jido.Agent`. Call `cmd/2`. Run in AgentServer. 5-minute working example.

---

### 2. Core Concepts
**File:** `guides/core-concepts.md`

The Jido mental model:
- Elm/Redux pattern: pure agents, declarative effects
- `{agent, directives} = MyAgent.cmd(agent, action)`
- Agent (pure struct) vs AgentServer (runtime)
- Instance-scoped architecture (not global singletons)
- Key terms: Agent, Directive, Skill, Strategy

Cross-references to jido_action (Actions) and jido_signal (Signals) for those concepts.

---

### 3. Agents
**File:** `guides/agents.md`

Defining agents with `use Jido.Agent`. The `cmd/2` contract. State management: `set/2`, `validate/2`. Lifecycle hooks: `on_before_cmd/2`, `on_after_cmd/3`. Schema options (NimbleOptions vs Zoi).

Brief; detailed API in `Jido.Agent` moduledoc.

---

### 4. Skills
**File:** `guides/skills.md`

What skills are and when to use them. `use Jido.Skill` configuration. State isolation via `state_key`. Lifecycle callbacks: `mount/2`, `router/1`, `handle_signal/2`, `transform_result/3`, `child_spec/1`. Composing multiple skills.

Brief; detailed API in `Jido.Skill` moduledoc.

---

### 5. Directives
**File:** `guides/directives.md`

What directives are (pure effect descriptions). Core directives: `Emit`, `Error`, `Spawn`, `SpawnAgent`, `StopChild`, `Schedule`, `Stop`, `Cron`, `CronCancel`. Helper constructors. Custom directive extensibility.

Brief; detailed API in `Jido.Agent.Directive` moduledoc.

---

### 6. Strategies
**File:** `guides/strategies.md`

What strategies control. Built-in: `Direct`, `FSM`. Strategy configuration. Snapshot interface. Implementing custom strategies. `signal_routes/1` for routing.

Brief; detailed API in `Jido.Agent.Strategy` moduledoc.

---

### 7. Runtime
**File:** `guides/runtime.md`

AgentServer basics: `start/1`, `start_link/1`, `Jido.start_agent/3`. `call/3` vs `cast/2`. Signal processing flow. Parent-child hierarchy with `SpawnAgent`/`StopChild`. Completion detection via state (not process death). Await helpers.

Brief; detailed API in `Jido.AgentServer` and `Jido.Await` moduledocs.

---

### 8. Testing
**File:** `guides/testing.md`

`JidoTest.Case` for per-test isolation. Testing pure agents (no runtime). Testing with AgentServer. Await patterns in tests. Mocking with Mimic.

---

### 9. FSM Strategy Deep Dive
**File:** `guides/fsm-strategy.livemd`

Building a state machine agent. Defining states and transitions. Transition guards. State-dependent action routing. Complete example: order fulfillment workflow with states (pending → confirmed → shipped → delivered / cancelled). FSMX integration.

---

### 10. Migrating from 1.x
**File:** `guides/migration.md`

Breaking changes summary. Supervision tree setup. `Jido.start_agent/3` vs old API. Directive adoption. Incremental migration path.

---

## Documentation in Moduledocs (No Separate Guide Needed)

The following are well-documented in their respective `@moduledoc` and do not need separate guides:

| Topic | Module |
|-------|--------|
| Agent API | `Jido.Agent` |
| Skill API | `Jido.Skill` |
| Directive API | `Jido.Agent.Directive` |
| Strategy API | `Jido.Agent.Strategy` |
| FSM Strategy | `Jido.Agent.Strategy.FSM` |
| AgentServer API | `Jido.AgentServer` |
| Await/Coordination | `Jido.Await` |
| Discovery | `Jido.Discovery` |
| Telemetry | `Jido.Telemetry` |
| Errors | `Jido.Error` |
| DirectiveExec Protocol | `Jido.AgentServer.DirectiveExec` |

---

## Covered by Other Packages

| Topic | Package |
|-------|---------|
| Actions, Schemas, Validation | `jido_action` |
| Instructions, Plans, DAG workflows | `jido_action` |
| Actions as LLM Tools | `jido_action` |
| Signals, CloudEvents | `jido_signal` |
| Signal Routing (trie-based) | `jido_signal` |
| Dispatch Adapters | `jido_signal` |
| Signal Bus | `jido_signal` |
| Serialization | `jido_signal` |

---

## Not Included (Goes to jido_workbench)

- Recipe-style tutorials
- End-to-end examples (calculator, chat, coordinator, etc.)
- Multi-agent patterns
- AI integration examples (ReAct, tool use)
- Production deployment guides

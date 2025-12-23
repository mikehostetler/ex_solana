# Jido Workbench Examples: Production-Ready Livebook Catalog

**Purpose:** Comprehensive catalog of `.livemd` examples demonstrating Jido's capabilities, competitive positioning, and production patterns.

**Constraints:**
- All examples as Livebook (`.livemd`) files in `jido_workbench` project
- LLM access available via ReqLLM
- No database dependency (use ETS, LLMDB, or ephemeral state)
- Code-first, production-focused demonstrations

**Organization:** Beginner → Advanced, Foundation → Application layer

---

## Navigation

**By Category:**
- [Getting Started (Foundation + Core)](#category-1-getting-started-foundation--core) - Examples 1-3
- [Agent Patterns (Core + Actions/Signals)](#category-2-agent-patterns-core--jido_actionjido_signal) - Examples 4-6
- [Multi-Agent Coordination](#category-3-multi-agent-coordination) - Examples 7-9
- [Production Patterns](#category-4-production-patterns-resilience-observability-cost) - Examples 10-13
- [Advanced Topics & Application Layer](#category-5-advanced-topics--application-layer) - Examples 14-18

**By Package:**
- Foundation: LLMDB/ReqLLM - Examples 1, 6, 14, 18
- Core: Jido - Examples 2, 4-13, 15-16
- AI Layer: JidoAI - Examples 3, 6-9, 12, 14-16, 18
- Application: JidoCoder - Example 17

**By Competitive Positioning:**
- vs CrewAI - Examples 7, 8, 17
- vs AutoGen - Examples 8, 13, 16, 17
- vs LangGraph - Examples 11, 13, 15
- vs LangChain - Example 1, 6
- Unique to BEAM/Jido - Examples 2, 9, 10, 11, 13

---

## Category 1: Getting Started (Foundation + Core)

### Example 1: Hello BEAM + LLM – Deterministic Calls with ReqLLM and LLMDB

**File:** `01_hello_beam_llm.livemd`

**Goal:** Show the foundation layer working: make LLM calls via ReqLLM, log them in LLMDB, replay them deterministically.

**What It Demonstrates:**
- Foundation layer: `req_llm` basic usage (prompt, temperature, streaming vs non-streaming)
- `llmdb` as a local call log/cache (no external DB)
- Explicit control over LLM inputs/outputs from BEAM
- Deterministic replay for testing

**Difficulty:** Beginner

**Packages:**
- `req_llm` (HTTP client for LLM APIs)
- `llmdb` (model registry and call logging)

**Production Relevance:**
- Pattern for safe, repeatable API calls
- Foundation for "record + replay" of agent conversations under test
- Cost tracking via logged requests

**Status:** 🟡 Roadmap (no new runtime features required)

**Competitive Positioning:**
- **vs LangChain:** Equivalent to "Hello LLM" notebooks, but with explicit request logging and deterministic replay built in
- **Unique to Jido:** No framework positions LLM calls as a distinct foundation layer separate from agents

**Code Structure:**
```elixir
# 1. Register models in LLMDB
# 2. Make simple req_llm call with logging
# 3. Show streaming vs non-streaming
# 4. Replay from LLMDB cache
# 5. Cost calculation from logs
```

**Learning Path:**
- Start here if: You're new to Jido and want to understand the foundation
- Next example: 2 (First Jido Agent)

**Roadmap Items:**
- [ ] Optional: tagged sessions in LLMDB for organizing call logs
- [ ] Optional: lightweight search over past calls

---

### Example 2: First Jido Agent – Supervised Counter Without Any LLM

**File:** `02_first_jido_agent.livemd`

**Goal:** Show a pure Jido agent (no AI) that maintains state, runs under OTP supervision, and demonstrates crash/restart behavior.

**What It Demonstrates:**
- Core layer: `Jido.Agent` basic definition
- Integration with OTP supervisor tree in a Livebook
- "Let it crash" + supervisor restart strategy
- Per-agent state management
- Process lifecycle (init, handle_action, terminate)

**Difficulty:** Beginner

**Packages:**
- `jido` (core bot framework)

**Production Relevance:**
- Shows Jido is a general-purpose agent framework, not "LLM-or-nothing"
- Baseline for understanding agent state and lifecycle
- Foundation for thousands of long-lived processes

**Status:** 🟢 Implemented (core features exist)

**Competitive Positioning:**
- **vs all AI frameworks:** Most start with "chat with an LLM"; this starts with supervision and failure behavior
- **Unique to Jido:** Demonstrates actor model + supervision tree—no Python framework has this

**Code Structure:**
```elixir
# 1. Define CounterAgent with state
# 2. Start under DynamicSupervisor
# 3. Increment counter via handle_action
# 4. Force crash and show restart
# 5. Metrics: spawn 100 agents, measure memory
```

**Learning Path:**
- Start here if: You understand BEAM/OTP and want to see Jido basics
- Next example: 3 (add LLM to an agent)

**Roadmap Items:**
- [ ] Helper to spawn N agents with metrics (`Jido.Bench.spawn/2`)
- [ ] Simple introspection utilities for viewing agent state

---

### Example 3: First JidoAI Agent – Tool-Using LLM in a BEAM Process

**File:** `03_first_jidoai_agent.livemd`

**Goal:** Single Jido agent that wraps an LLM via JidoAI, exposes 1-2 tools (web search mock or simple math), runs under supervision.

**What It Demonstrates:**
- AI layer: `jido_ai` tool-calling interface
- How an LLM sits inside a supervised agent process
- Basic tool invocation and error handling
- Streaming responses from supervised process

**Difficulty:** Beginner

**Packages:**
- `jido` (agent framework)
- `jido_ai` (LLM-aware agents)
- `req_llm` (LLM calls)
- `llmdb` (optional, for logging)

**Production Relevance:**
- Building block for any tool-using assistant
- Shows where to hook logging, retry, rate limiting at process level
- Template for production AI agents

**Status:** 🟡 Roadmap

**Competitive Positioning:**
- **vs AutoGen/CrewAI:** Similar to single tool-using agent, but with OTP supervision instead of plain async tasks
- **Unique to Jido:** Process-level isolation means LLM failures don't cascade

**Code Structure:**
```elixir
# 1. Define WeatherAgent with JidoAI
# 2. Register simple tools (mock weather API)
# 3. Run tool-calling flow
# 4. Demonstrate crash recovery
# 5. Show streaming output to Livebook
```

**Learning Path:**
- Prerequisite: Examples 1-2
- Next example: 4 (validated actions)

**Roadmap Items:**
- [ ] Unified configuration struct for LLM provider + tools + supervision strategy
- [ ] Built-in tool library (web search, file ops)

---

## Category 2: Agent Patterns (Core + jido_action/jido_signal)

### Example 4: Validated Actions – Weather Agent with jido_action

**File:** `04_validated_actions.livemd`

**Goal:** Weather agent that validates inputs (location, units, API key) using `jido_action` before hitting a weather API.

**What It Demonstrates:**
- `jido_action` schema DSL and validation
- Clean separation between validation and agent logic
- Structured error handling for bad inputs
- Type-safe action definitions

**Difficulty:** Intermediate

**Packages:**
- `jido` (agent framework)
- `jido_action` (action validation)
- `req_llm` (optional, if using LLM to parse natural language → structured params)

**Production Relevance:**
- Pattern for any tool hitting external APIs
- Prevents silent failures from garbage input
- Type safety for agent actions

**Status:** 🟡 Roadmap

**Competitive Positioning:**
- **vs all frameworks:** Many rely on LLMs to "spell out tool args"; this shows validated, schema-based actions instead
- **Unique to Jido:** First-class action validation separate from LLM layer

**Code Structure:**
```elixir
# 1. Define FetchWeather action with schema
# 2. Show validation success and failure cases
# 3. Use in agent workflow
# 4. Demonstrate automatic retry on validation failure
```

**Learning Path:**
- Prerequisite: Example 3
- Next example: 5 (signals for coordination)

**Roadmap Items:**
- [ ] Helper for turning natural-language prompt into validated action struct via LLM
- [ ] Action composition utilities

---

### Example 5: Signals and Pub/Sub – Sensor + Monitor Agents with jido_signal

**File:** `05_signals_pubsub.livemd`

**Goal:** Set of Sensor agents emitting temperature signals and a Monitor agent reacting to those signals (alerts on thresholds).

**What It Demonstrates:**
- `jido_signal` pub/sub for decoupled communication
- Multiple agents subscribing/emitting events
- Event-driven patterns instead of tight-coupled RPC
- Coordination without direct process references

**Difficulty:** Intermediate

**Packages:**
- `jido` (agent framework)
- `jido_signal` (pub/sub signaling)

**Production Relevance:**
- Pattern for notifications, event buses, workflow hooks between agents
- Decoupled agent communication at scale

**Status:** 🟢 Implemented (snippets exist in docs)

**Competitive Positioning:**
- **vs LangGraph:** Similar to "event nodes", but using native process message-passing + pub/sub
- **Unique to Jido:** No external message broker needed—BEAM provides this natively

**Code Structure:**
```elixir
# 1. Define SensorAgent that emits signals
# 2. Define MonitorAgent that subscribes
# 3. Run swarm of sensors
# 4. Show alert triggering
# 5. Metrics on event throughput
```

**Learning Path:**
- Prerequisite: Example 2
- Next example: 6 (memory management)

**Roadmap Items:**
- [ ] Telemetry hooks on signals (who emits, who listens, event rates)
- [ ] Signal routing/filtering utilities

---

### Example 6: Conversational Agent with Short-Term Memory (Ephemeral LLMDB)

**File:** `06_conversational_memory.livemd`

**Goal:** Chat-style agent that keeps a sliding window of conversation in LLMDB/ETS, with explicit truncation and memory management.

**What It Demonstrates:**
- Using `llmdb` or ETS for transient, per-session memory (no external DB)
- Token budgeting: trimming history, summarization-on-demand
- Guardrails around context size
- Memory lifecycle tied to agent process

**Difficulty:** Intermediate

**Packages:**
- `jido` (agent framework)
- `jido_ai` (LLM integration)
- `req_llm` (LLM calls)
- `llmdb` (memory storage)

**Production Relevance:**
- Baseline pattern for stateful assistants without persistent storage
- Template for managing LLM context windows

**Status:** 🟡 Roadmap

**Competitive Positioning:**
- **vs CrewAI/AutoGen:** Equivalent to "memory" modules, but with explicit control of memory footprint
- **vs LangChain:** Shows manual memory management instead of opaque in-memory lists

**Code Structure:**
```elixir
# 1. Start conversational agent
# 2. Track messages in LLMDB
# 3. Implement sliding window (max N messages)
# 4. Optional: summarization when limit hit
# 5. Show token counting and cost tracking
```

**Learning Path:**
- Prerequisite: Examples 1, 3
- Next example: 7 (multi-agent coordination)

**Roadmap Items:**
- [ ] Helper functions for token counting integrated into JidoAI
- [ ] Context trimming strategies (FIFO, summarization, importance-based)

---

## Category 3: Multi-Agent Coordination

### Example 7: Manager–Worker Swarm – Research Crew on a Single BEAM Node

**File:** `07_manager_worker_swarm.livemd`

**Goal:** One Manager agent breaks a research task into sub-tasks, spawns N Worker agents, aggregates results, returns final report.

**What It Demonstrates:**
- Dynamic agent spawning and teardown under supervision
- Simple task decomposition with JidoAI (LLM-guided planning)
- Back-pressure: limit concurrent workers to N
- Result aggregation patterns

**Difficulty:** Intermediate → Advanced

**Packages:**
- `jido` (agent framework)
- `jido_ai` (LLM planning)
- `jido_action` (task definitions)
- `jido_signal` (worker→manager communication)
- `req_llm`, `llmdb`

**Production Relevance:**
- Pattern for document analysis, bulk classification, batched tasks
- Demonstrates scaling to hundreds of workers on one node
- Shows metrics: spawn 500 workers, observe memory/latencies

**Status:** 🟡 Roadmap

**Competitive Positioning:**
- **vs CrewAI:** Mirrors "manager + workers" pattern, but uses OTP supervisors for lifecycle
- **vs AutoGen:** Similar to GroupChat manager pattern, but with explicit supervision and back-pressure

**Code Structure:**
```elixir
# 1. Define ManagerAgent with planning LLM
# 2. Define WorkerAgent for executing subtasks
# 3. Spawn DynamicSupervisor for workers
# 4. Manager spawns N workers with tasks
# 5. Workers report back via signals
# 6. Manager aggregates and synthesizes
# 7. Metrics: memory, latency, throughput
```

**Learning Path:**
- Prerequisite: Examples 2, 3, 5
- Next example: 8 (critic-reviewer loop)

**Roadmap Items:**
- [ ] Utilities for structured task graphs (id, dependencies, status)
- [ ] In-memory task queue with priority
- [ ] Simple introspection UI (Livebook kino widgets or separate roadmap)

---

### Example 8: Critic–Reviewer Loop – Safer Tool Use via Multi-Agent Critique

**File:** `08_critic_reviewer_loop.livemd`

**Goal:** Two or three agents collaborate: "doer" drafts answer using tools, "critic" reviews against checklist, "fixer" refines output.

**What It Demonstrates:**
- Multi-agent communication with `jido_signal` or direct messaging
- Structured roles + quality gates around tools
- Loop termination to avoid infinite self-play
- Safety pattern for high-risk actions

**Difficulty:** Intermediate

**Packages:**
- `jido` (agent framework)
- `jido_ai` (LLM agents)
- `jido_signal` (coordination)
- `req_llm`

**Production Relevance:**
- Template for high-risk actions (code changes, prod config, legal text)
- Quality assurance via multiple agents

**Status:** 🟡 Roadmap

**Competitive Positioning:**
- **vs AutoGen:** Similar to Role-Playing/Critic patterns, but implemented as supervised BEAM processes
- **vs CrewAI:** Similar to hierarchical crews, but with explicit feedback loops

**Code Structure:**
```elixir
# 1. Define DoerAgent, CriticAgent, FixerAgent
# 2. Doer proposes solution
# 3. Critic evaluates with LLM
# 4. If fails: Fixer refines
# 5. Loop with max iterations
# 6. Return final result
```

**Learning Path:**
- Prerequisite: Examples 3, 5, 7
- Next example: 9 (long-lived agents)

**Roadmap Items:**
- [ ] Higher-level multi-agent coordinator API (register role, define protocol)
- [ ] Generic feedback loop pattern

---

### Example 9: Long-Lived Workflow Agents – Per-User Assistants at Scale

**File:** `09_long_lived_workflows.livemd`

**Goal:** Demo with hundreds/thousands of lightweight agents, each representing a user workflow (e.g., onboarding assistant), managed under supervisor.

**What It Demonstrates:**
- Running many long-lived agents (~1000+ processes)
- Minimal per-agent memory footprint pattern
- "Wake-on-message" model instead of busy loops
- Supervisor strategies for large swarms

**Difficulty:** Advanced (scale + measurement)

**Packages:**
- `jido` (agent framework)
- `jido_signal` (messaging)
- Optional: `jido_ai`, `req_llm`

**Production Relevance:**
- Realistic pattern: one agent per user or per long-running workflow
- Shows BEAM's strength: thousands of processes on single node
- Template for multi-tenant agent systems

**Status:** 🟡 Roadmap

**Competitive Positioning:**
- **vs all Python frameworks:** Most assume short-lived runs orchestrated externally; this shows resident agents managed by BEAM
- **Unique to Jido:** No other framework can run 1000s of concurrent agents this efficiently

**Code Structure:**
```elixir
# 1. Define WorkflowAgent with minimal state
# 2. Start DynamicSupervisor
# 3. Spawn 1000 agents
# 4. Send messages to random agents
# 5. Measure: memory per agent, message latency
# 6. Demonstrate crash of subset, observe isolation
```

**Learning Path:**
- Prerequisite: Examples 2, 7
- Next example: 10 (observability)

**Roadmap Items:**
- [ ] Official guidance on memory ceilings and config defaults
- [ ] Helper for bulk-spawn benchmarking
- [ ] Sample telemetry integration

---

## Category 4: Production Patterns (Resilience, Observability, Cost)

### Example 10: Observability – Telemetry + Logging for an Agent Swarm

**File:** `10_observability_telemetry.livemd`

**Goal:** Swarm of simple Jido agents with telemetry events plugged into `Logger` and Livebook visualizations (metrics plots).

**What It Demonstrates:**
- Emitting telemetry from Jido agents (actions/sec, failures)
- Aggregating metrics in Livebook (Kino plots)
- Basic diagnostic patterns: slow agent, noisy agent
- Integration with standard Elixir telemetry

**Difficulty:** Intermediate

**Packages:**
- `jido` (agent framework)
- `jido_action` (optional)
- Elixir `:telemetry`, `:logger`

**Production Relevance:**
- Templates for production dashboards and alerting
- Shows per-agent metrics without external services

**Status:** 🟡 Roadmap

**Competitive Positioning:**
- **vs all frameworks:** Most bolt on observability later; this shows per-agent telemetry baked into process model
- **Unique to Jido:** Native Elixir telemetry integration

**Code Structure:**
```elixir
# 1. Define agents with telemetry emissions
# 2. Attach telemetry handlers in Livebook
# 3. Spawn agent swarm
# 4. Visualize metrics with Kino
# 5. Demonstrate tracing slow operations
```

**Learning Path:**
- Prerequisite: Examples 2, 7
- Next example: 11 (fault injection)

**Roadmap Items:**
- [ ] Jido telemetry events spec (names, measurements, metadata)
- [ ] Pre-built Livebook dashboards for common metrics

---

### Example 11: Fault Injection – Supervision Strategies Under Load

**File:** `11_fault_injection.livemd`

**Goal:** Livebook that deliberately crashes subset of agents under load to show one-for-one restarts, backoff strategies, containment.

**What It Demonstrates:**
- OTP supervision strategies for Jido supervisors
- "Let it crash" in multi-agent context
- How failures in one agent don't take down others
- Recovery latency measurements

**Difficulty:** Intermediate

**Packages:**
- `jido` (agent framework)

**Production Relevance:**
- Concrete evidence for resilience claims
- "What happens at 3am when one agent misbehaves?"
- Template for chaos testing

**Status:** 🟡 Roadmap

**Competitive Positioning:**
- **vs all Python frameworks:** Most rely on process pools and external orchestrators; this shows built-in, low-latency restarts
- **Unique to Jido:** Demonstrates supervision trees—no other framework has this

**Code Structure:**
```elixir
# 1. Start supervised agent swarm
# 2. Define "poison" action that crashes agent
# 3. Trigger crashes in 10% of agents
# 4. Observe isolated restarts
# 5. Measure: restart latency, memory stability
# 6. Show different supervisor strategies
```

**Learning Path:**
- Prerequisite: Examples 2, 9
- Next example: 12 (rate limiting)

**Roadmap Items:**
- [ ] Documented, configurable backoff policies in Jido API
- [ ] Supervisor strategy presets for common patterns

---

### Example 12: Rate-Limited LLM Access with Back-Pressure

**File:** `12_rate_limited_llm.livemd`

**Goal:** Agents call LLMs through a rate-limited gateway process; demonstrates back-pressure and avoiding API quota explosions.

**What It Demonstrates:**
- Using `req_llm` behind a GenServer/Jido gateway agent
- Limiting concurrent API calls; queueing requests from many agents
- Per-request timeouts and retry policies
- Back-pressure when queue fills

**Difficulty:** Advanced (coordination + error handling)

**Packages:**
- `jido` (agent framework)
- `jido_ai` (LLM integration)
- `req_llm` (HTTP client)

**Production Relevance:**
- Essential pattern for any real-world multi-agent system hitting LLM APIs
- Cost control and quota management

**Status:** 🟡 Roadmap

**Competitive Positioning:**
- **vs LangGraph/CrewAI:** These commonly leave rate limiting to app code or provider SDKs
- **Unique to Jido:** Centers back-pressure and supervision as first-class

**Code Structure:**
```elixir
# 1. Define LLMGateway agent with rate limits
# 2. Multiple agents request LLM calls via gateway
# 3. Gateway enforces concurrency limit
# 4. Queue requests with timeout
# 5. Show graceful degradation under load
# 6. Metrics: throughput, queue depth, failures
```

**Learning Path:**
- Prerequisite: Examples 3, 7, 9
- Next example: 13 (distributed cluster)

**Roadmap Items:**
- [ ] Optional Jido-provided LLM gateway agent module
- [ ] Configurable concurrency, timeouts, per-model budgets

---

### Example 13: Distributed Jido Cluster – Agents Across Multiple Nodes

**File:** `13_distributed_cluster.livemd`

**Goal:** Livebook starts minimal multi-node BEAM cluster (local nodes), runs agents on multiple nodes, passes messages across them.

**What It Demonstrates:**
- BEAM distribution basics for Jido agents
- Locating and messaging agents on remote nodes
- What happens when a node leaves/joins
- Distributed supervisor strategies

**Difficulty:** Advanced

**Packages:**
- `jido` (agent framework)
- `jido_signal` (optional, for cross-node signals)

**Production Relevance:**
- Foundation for scaling beyond single VM/container
- Surviving node failures
- Geographic distribution

**Status:** 🟡 Roadmap

**Competitive Positioning:**
- **vs all frameworks:** Most achieve distribution via external queues and k8s
- **Unique to Jido:** Uses BEAM distribution with native process identifiers and supervision

**Code Structure:**
```elixir
# 1. Start 3 local BEAM nodes in Livebook
# 2. Define agent on each node
# 3. Send messages between nodes
# 4. Kill one node, observe recovery
# 5. Show node discovery and reconnection
```

**Learning Path:**
- Prerequisite: Examples 2, 9, 11
- Next example: 14 (cost-aware planning)

**Roadmap Items:**
- [ ] Clear guidance on clustering setup
- [ ] Recommended libraries (libcluster, etc.)
- [ ] Optional `Jido.Cluster` helpers for discovery

---

## Category 5: Advanced Topics & Application Layer

### Example 14: Cost-Aware Planning – Budget-Constrained Multi-Step Tasks

**File:** `14_cost_aware_planning.livemd`

**Goal:** Manager agent accepts a "budget" (tokens or dollars), chooses tools and sub-tasks via JidoAI, stops when budget nearly exhausted.

**What It Demonstrates:**
- High-level planning with explicit cost model
- Using `llmdb` logs or `req_llm` telemetry to approximate cost per call
- Adjusting behavior when cost budget is low (fallback paths)
- Cost tracking across multi-agent workflows

**Difficulty:** Advanced

**Packages:**
- `jido` (agent framework)
- `jido_ai` (LLM planning)
- `req_llm` (API calls)
- `llmdb` (cost logs)

**Production Relevance:**
- Core for production multi-agent systems: enforce cost ceilings per user or per workflow
- Template for budget-aware agents

**Status:** 🟡 Roadmap

**Competitive Positioning:**
- **vs all frameworks:** Many talk about "cost awareness" but leave it to external monitoring
- **Unique to Jido:** Cost constraints enforced at agent/planner layer

**Code Structure:**
```elixir
# 1. Define CostTracker module
# 2. Manager agent with token budget
# 3. Plan tasks with cost estimates
# 4. Execute tasks while tracking spend
# 5. Fallback to cheaper strategies when budget low
# 6. Report final cost breakdown
```

**Learning Path:**
- Prerequisite: Examples 1, 3, 7
- Next example: 15 (DAG workflows)

**Roadmap Items:**
- [ ] First-class cost accounting API in `jido_ai`
- [ ] Per-call cost estimates from LLMDB
- [ ] Accumulated cost in agent state

---

### Example 15: DAG Workflows the OTP Way – Recreating LangGraph-Style Flows in Jido

**File:** `15_dag_workflows_otp.livemd`

**Goal:** Implement simple DAG workflow (ingest → analyze → summarize → critique) as supervised agents and signals, contrasting with LangGraph graph definition.

**What It Demonstrates:**
- Mapping DAG nodes to agents and edges to signals/messages
- Handling failures of individual nodes with supervision
- Parallel branches and joins using coordination
- Side-by-side comparison with LangGraph approach

**Difficulty:** Advanced

**Packages:**
- `jido` (agent framework)
- `jido_signal` (coordination)
- Optional: `jido_ai`

**Production Relevance:**
- Shows how to port existing graph-based pipelines into Jido/OTP model
- Template for complex workflows

**Status:** 🟡 Roadmap

**Competitive Positioning:**
- **vs LangGraph:** Direct mental model translation from DAGs to BEAM supervision + messaging
- **Unique to Jido:** Better fault isolation via supervision

**Code Structure:**
```elixir
# 1. Define workflow as agents: IngestAgent, AnalyzeAgent, etc.
# 2. Connect with signals (edges)
# 3. Start workflow with input
# 4. Show parallel execution where possible
# 5. Crash one node, observe isolated failure
# 6. Compare to LangGraph equivalent code
```

**Learning Path:**
- Prerequisite: Examples 2, 5, 7, 11
- Next example: 16 (human-in-the-loop)

**Roadmap Items:**
- [ ] Optional higher-level workflow DSL
- [ ] Visual workflow builder (future, not required)

---

### Example 16: Human-in-the-Loop Orchestration – Approval Gate Agent

**File:** `16_human_in_loop.livemd`

**Goal:** Multi-agent flow where agent proposes actions, human approval step via Livebook UI input, approved actions proceed to execution agents.

**What It Demonstrates:**
- Combining agents with interactive Livebook cells as human input
- Pausing agent workflow pending human signal
- Resuming or aborting based on operator decision
- Safety pattern for high-risk operations

**Difficulty:** Intermediate → Advanced

**Packages:**
- `jido` (agent framework)
- `jido_ai` (LLM planning)
- `jido_signal` (coordination)
- `req_llm`

**Production Relevance:**
- Pattern for "humans in the loop" around high-risk tools (deployments, financial trades)
- Compliance and safety workflows

**Status:** 🟡 Roadmap

**Competitive Positioning:**
- **vs AutoGen:** Similar human-in-the-loop patterns, but integrated into supervised long-lived agents
- **vs CrewAI:** Shows explicit approval gates vs implicit tool execution

**Code Structure:**
```elixir
# 1. Define PlannerAgent that proposes action
# 2. Show proposal in Livebook UI
# 3. Kino input for approve/reject
# 4. If approved: ExecutorAgent runs action
# 5. If rejected: return to Planner
# 6. Log all decisions
```

**Learning Path:**
- Prerequisite: Examples 3, 5, 7
- Next example: 17 (JidoCoder)

**Roadmap Items:**
- [ ] Generic "approval gate" agent component
- [ ] Integration patterns for web UI (LiveView)

---

### Example 17: JidoCoder – Autonomous Elixir Refactoring Agent

**File:** `17_jidocoder_refactoring.livemd`

**Goal:** Application-layer example where JidoCoder agent reads a small Elixir module, proposes refactor, writes new version (with human approval).

**What It Demonstrates:**
- Application layer: `jido_coder` using LLMs to read/modify code
- Tooling to read/write files in constrained sandbox
- Safety via human approval and diff review
- Multi-step coding workflow

**Difficulty:** Advanced

**Packages:**
- `jido` (agent framework)
- `jido_ai` (LLM integration)
- `jido_coder` (coding agent)
- `req_llm`, `llmdb`

**Production Relevance:**
- Shows how to build real coding assistants that operate on repos
- Safety and approval patterns for code changes

**Status:** 🔴 Roadmap (JidoCoder layer)

**Competitive Positioning:**
- **vs AutoGen/CrewAI:** Similar to coding agents, but running as supervised BEAM processes
- **Unique to Jido:** Leveraging Elixir tooling ecosystem (formatter, compiler)

**Code Structure:**
```elixir
# 1. Read Elixir module from file
# 2. JidoCoder agent analyzes code
# 3. Propose refactoring with LLM
# 4. Show diff to human (Livebook UI)
# 5. If approved: write file, run formatter
# 6. Run tests to validate
```

**Learning Path:**
- Prerequisite: Examples 3, 16
- Next example: 18 (evaluation harness)

**Roadmap Items:**
- [ ] File-system sandbox helpers
- [ ] Simple diff viewer in Livebook
- [ ] Integration with Mix tasks (format, test)

---

### Example 18: Evaluation Harness – Regression Tests for Agent Behaviors

**File:** `18_evaluation_harness.livemd`

**Goal:** Livebook runs suite of canned scenarios against Jido agents, records outputs in ETS, compares to baselines.

**What It Demonstrates:**
- Using ETS as ephemeral store for test cases and outputs (no external DB)
- Batch-running agent interactions in scripted way
- Detecting regressions when prompts/models/logic change
- Using `llmdb` to test against different model versions
- CI integration patterns

**Difficulty:** Advanced

**Packages:**
- `jido` (agent framework)
- `jido_ai` (LLM agents)
- `req_llm` (API calls)
- `llmdb` (model metadata for version testing)

**Production Relevance:**
- Provides repeatable guardrail for evolving agent logic
- Template for continuous testing of agents
- Shows testing across different model versions

**Status:** 🟡 Roadmap

**Competitive Positioning:**
- **vs LangSmith:** Frameworks add separate services; this shows in-repo, BEAM-native evaluation
- **Unique to Jido:** Uses Livebooks as test runner with ETS-backed state

**Code Structure:**
```elixir
# 1. Define test scenarios in ETS table
# 2. Load baselines from file
# 3. Query LLMDB for models to test
# 4. Run agents against each scenario per model
# 5. Capture outputs in ETS
# 6. Compare to baselines
# 7. Generate test report
# 8. Export results as JSON/CSV
```

**Learning Path:**
- Prerequisite: Examples 1, 3, 6
- Completion: You've seen the full Jido stack

**Roadmap Items:**
- [ ] Scenario DSL for defining tests + expected properties
- [ ] Baseline storage/versioning strategy
- [ ] Exporting eval results for CI integration
- [ ] LLM-as-judge evaluation patterns

---

## Taxonomy Coverage Matrix

| Example | Foundation (LLMDB/ReqLLM) | Core (Jido) | AI (JidoAI) | App (JidoCoder) | Pattern |
|---------|--------------------------|-------------|-------------|-----------------|---------|
| 1 | ✅ | - | - | - | LLM basics, deterministic replay |
| 2 | - | ✅ | - | - | Supervision, state management |
| 3 | ✅ | ✅ | ✅ | - | Tool-using agent, streaming |
| 4 | - | ✅ | - | - | Validated actions |
| 5 | - | ✅ | - | - | Pub/sub, event-driven |
| 6 | ✅ | ✅ | ✅ | - | Memory, context windows |
| 7 | ✅ | ✅ | ✅ | - | Multi-agent, manager-worker |
| 8 | - | ✅ | ✅ | - | Critic loop, quality gates |
| 9 | - | ✅ | - | - | Long-lived, scale |
| 10 | - | ✅ | - | - | Observability, telemetry |
| 11 | - | ✅ | - | - | Fault tolerance, chaos |
| 12 | ✅ | ✅ | ✅ | - | Rate limiting, back-pressure |
| 13 | - | ✅ | - | - | Distribution, clustering |
| 14 | ✅ | ✅ | ✅ | - | Cost awareness, budgets |
| 15 | - | ✅ | ✅ | - | DAG workflows, graphs |
| 16 | - | ✅ | ✅ | - | Human-in-the-loop |
| 17 | ✅ | ✅ | ✅ | ✅ | Code agents, refactoring |
| 18 | ✅ | ✅ | ✅ | - | Evaluation, testing |

---

## Competitive Positioning Summary

### Where Jido Stands Out (vs Python Frameworks)

**Supervision & Crash Isolation:**
- Examples: 2, 7, 9, 11, 13, 15
- **vs all frameworks:** Built-in supervision trees vs external orchestrators
- **Result:** Low-latency restarts, process-level isolation

**High Agent Counts on Single Node:**
- Examples: 2, 7, 9, 10
- **vs all frameworks:** BEAM's lightweight processes vs OS threads
- **Result:** 1000s of concurrent agents with minimal overhead

**Native Back-Pressure & Rate Limiting:**
- Examples: 7, 9, 12, 14
- **vs LangGraph/CrewAI:** First-class back-pressure vs app-level code
- **Result:** Automatic quota management, graceful degradation

**Distributed Nodes Without External Queues:**
- Example: 13
- **vs all frameworks:** BEAM distribution vs Kafka/Redis/RabbitMQ
- **Result:** Native clustering, process transparency

**Evaluation Without Extra Services:**
- Example: 18
- **vs LangSmith/AgentOps:** In-repo testing vs hosted platforms
- **Result:** Self-contained, reproducible tests using ETS and Livebooks

---

## Roadmap Priorities (Based on Examples)

### P0: Required for Market Entry

| Item | Examples | Status |
|------|----------|--------|
| Basic agent definition + supervision | 2, 3 | ✅ Exists |
| Tool system with validation | 3, 4 | 🟡 Partial |
| Multi-provider LLM support | 1, 3 | ✅ Exists |
| State management (ETS/GenServer) | 2, 6 | ✅ Exists |
| Streaming responses | 3 | ✅ Exists |
| Basic orchestration | 5, 7 | 🟡 Partial |

### P1: Competitive Parity

| Item | Examples | Priority |
|------|----------|----------|
| Multi-agent coordination APIs | 7, 8, 15 | High |
| Telemetry event spec + helpers | 10 | High |
| LLM cost accounting | 14 | Medium |
| Human-in-the-loop patterns | 16 | Medium |
| Cluster/distribution helpers | 13 | Medium |

### P2: Differentiation

| Item | Examples | Priority |
|------|----------|----------|
| Chaos testing utilities | 11 | Low |
| Evaluation harness | 18 | Low |
| JidoCoder application layer | 17 | Roadmap |
| Workflow DSL | 15 | Optional |
| Visual debugging | - | Future |

---

## Implementation Phases

### Phase 1: Foundation (Weeks 1-4)
**Goal:** Ship Examples 1-6, establish documentation baseline

- [ ] Example 1: Hello BEAM + LLM
- [ ] Example 2: First Jido Agent
- [ ] Example 3: First JidoAI Agent
- [ ] Example 4: Validated Actions
- [ ] Example 5: Signals and Pub/Sub
- [ ] Example 6: Conversational Memory

**Deliverables:**
- 6 working Livebooks in `jido_workbench`
- Updated HexDocs with Livebook links
- Blog post: "Getting Started with Jido"

### Phase 2: Multi-Agent Patterns (Weeks 5-8)
**Goal:** Ship Examples 7-9, demonstrate scale and coordination

- [ ] Example 7: Manager-Worker Swarm
- [ ] Example 8: Critic-Reviewer Loop
- [ ] Example 9: Long-Lived Workflows

**Deliverables:**
- 3 advanced Livebooks
- Benchmark numbers: 1000+ agents/node
- Blog post: "Building Multi-Agent Systems on BEAM"

### Phase 3: Production Patterns (Weeks 9-12)
**Goal:** Ship Examples 10-13, prove production readiness

- [ ] Example 10: Observability
- [ ] Example 11: Fault Injection
- [ ] Example 12: Rate-Limited LLM
- [ ] Example 13: Distributed Cluster

**Deliverables:**
- 4 production-focused Livebooks
- Production deployment guide
- Blog post: "Jido in Production: Resilience & Observability"

### Phase 4: Advanced & Application (Weeks 13-16)
**Goal:** Ship Examples 14-18, showcase differentiation

- [ ] Example 14: Cost-Aware Planning
- [ ] Example 15: DAG Workflows
- [ ] Example 16: Human-in-the-Loop
- [ ] Example 17: JidoCoder (if ready)
- [ ] Example 18: Evaluation Harness

**Deliverables:**
- 5 advanced Livebooks
- Comparison guide: Jido vs LangGraph/CrewAI/AutoGen
- Blog post: "Why BEAM Changes Multi-Agent Systems"

---

## Documentation Integration

### HexDocs Structure

```
docs/
├── getting-started/
│   ├── installation.md
│   ├── first-agent.md → Example 2
│   └── first-ai-agent.md → Example 3
├── guides/
│   ├── agent-patterns.md → Examples 4-6
│   ├── multi-agent.md → Examples 7-9
│   ├── production.md → Examples 10-13
│   └── advanced.md → Examples 14-18
├── livebooks/
│   ├── README.md → This file
│   └── [links to all .livemd files]
└── comparison/
    ├── vs-langgraph.md → Examples 11, 13, 15
    ├── vs-crewai.md → Examples 7, 8, 17
    └── vs-autogen.md → Examples 8, 13, 16
```

### Livebook Organization in jido_workbench

```
jido_workbench/
├── livebooks/
│   ├── 01_getting_started/
│   │   ├── 01_hello_beam_llm.livemd
│   │   ├── 02_first_jido_agent.livemd
│   │   └── 03_first_jidoai_agent.livemd
│   ├── 02_agent_patterns/
│   │   ├── 04_validated_actions.livemd
│   │   ├── 05_signals_pubsub.livemd
│   │   └── 06_conversational_memory.livemd
│   ├── 03_multi_agent/
│   │   ├── 07_manager_worker_swarm.livemd
│   │   ├── 08_critic_reviewer_loop.livemd
│   │   └── 09_long_lived_workflows.livemd
│   ├── 04_production/
│   │   ├── 10_observability_telemetry.livemd
│   │   ├── 11_fault_injection.livemd
│   │   ├── 12_rate_limited_llm.livemd
│   │   └── 13_distributed_cluster.livemd
│   └── 05_advanced/
│       ├── 14_cost_aware_planning.livemd
│       ├── 15_dag_workflows_otp.livemd
│       ├── 16_human_in_loop.livemd
│       ├── 17_jidocoder_refactoring.livemd
│       └── 18_evaluation_harness.livemd
└── README.md → Links to JIDO_WORKBENCH_EXAMPLES.md
```

---

## Success Metrics

**Engagement:**
- Livebook opens/runs (track via GitHub analytics)
- Time spent in each Livebook
- Completion rate (% who run all cells)

**Learning:**
- Users who complete Getting Started (1-3)
- Users who reach Multi-Agent (7-9)
- Users who implement production patterns (10-13)

**Competitive:**
- Comparison docs views (vs-langgraph, vs-crewai)
- Community mentions of BEAM advantages
- Blog post shares highlighting unique patterns

**Production Adoption:**
- Production deployments citing examples
- Community examples building on these patterns
- Issues/PRs referencing specific examples

---

## Brand Voice Alignment

**Every example follows brand voice:**

✅ **Production-first:** Each example includes production considerations
✅ **Code-first:** Runnable code, not conceptual diagrams
✅ **Evidence-driven:** Metrics, measurements, concrete numbers
✅ **No hype:** Honest about status (🟢 Implemented, 🟡 Roadmap, 🔴 Future)
✅ **Respect reader:** Assumes competence, no hand-holding
✅ **Specific claims:** "1000 agents on 2-core VM" not "scales well"

**Opening constraints (per brand voice):**
- Example 1: "Most frameworks assume LLM calls are one-off. Jido logs and replays them."
- Example 2: "Most agent frameworks start with LLMs. Jido starts with supervision."
- Example 11: "You can demo agents. Keeping them alive when one crashes is the hard part."
- Example 13: "Most frameworks scale with queues. Jido scales with BEAM distribution."

---

## Conclusion

This catalog provides:

1. **18 production-ready examples** progressing from beginner to advanced
2. **Clear competitive positioning** vs CrewAI, AutoGen, LangGraph, LangChain
3. **Honest roadmap** showing what exists vs what's planned
4. **BEAM differentiation** in every advanced example
5. **Integration with sitemap** as the "how to" layer above HexDocs

All examples are implementable as `.livemd` files with LLM access and no database, making them accessible, reproducible, and aligned with Jido's production-first brand voice.

**Next Steps:**
1. Implement Phase 1 examples (1-6) in `jido_workbench`
2. Update HexDocs with Livebook links
3. Ship Phase 2 (7-9) with benchmark numbers
4. Document roadmap items in GitHub issues

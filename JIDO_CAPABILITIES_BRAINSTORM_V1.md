# Jido Higher-Order Capabilities: Multi-Agent Team Patterns

## Executive Summary

This document explores architectural patterns for building **higher-order capabilities** as **teams of sophisticated, autonomous agents** leveraging Jido's three workflow engines: **ReAct** (reasoning & tool use), **Behavior Trees** (reactive execution), and **HTN** (hierarchical planning).

**Core Philosophy:** Jido's strength is **multi-agent teams** where each member runs rich, domain-appropriate workflows. Move beyond simple coordinator-worker patterns to **distributed intelligence** where agents collaborate, negotiate, and self-organize.

**Key Insights:**
- **Match workflow engines to agent roles**: HTN for strategists, BT for operators, ReAct for analysts/negotiators
- **Distribute autonomy**: Replace "dumb coordinator + simple workers" with "mission owner + intelligent peers"
- **Enable collaboration**: Support both hierarchical and peer-to-peer coordination via typed signal protocols
- **Compose workflows**: Agents can embed other engines (BT leaf calls ReAct, HTN primitive uses BT, etc.)

---

## Table of Contents

1. [Workflow Engines & Agent Archetypes](#workflow-engines--agent-archetypes)
2. [Team Patterns: From Hierarchical to Collaborative](#team-patterns-from-hierarchical-to-collaborative)
3. [Concrete Team Compositions](#concrete-team-compositions)
4. [Signal Protocols: Coordination Vocabulary](#signal-protocols-coordination-vocabulary)
5. [Capability Architecture](#capability-architecture)
6. [Organization Strategies](#organization-strategies)
7. [Implementation Roadmap](#implementation-roadmap)
8. [Advanced Patterns](#advanced-patterns)

---

## Workflow Engines & Agent Archetypes

Jido provides **three workflow engines**, each suited to different agent roles:

### 1. HTN (Hierarchical Task Networks) → Strategic Agents

**What it is:**
- Hierarchical planning with compound tasks decomposing into primitives
- Method selection based on preconditions and world state
- Produces structured, multi-step plans with alternatives

**Best for:**
- **Mission Planners** - Own overall goals, decompose into subgoals
- **Domain Strategists** - Maintain structured workflows (release planning, research protocols)
- **Replanning** - When assumptions break, re-decompose from current state

**Example roles:**
- GTD Mission Planner - Decomposes tasks via capture → clarify → organize → review → do
- Code Research Strategist - Plans investigation → analysis → synthesis pipeline
- Release Coordinator - Manages design → implement → validate → deploy workflow

**Key HTN capabilities:**
```elixir
use Jido.Agent,
  strategy: {Jido.Agent.Strategy.HTN, 
    domain: MyDomain,          # HTN domain with tasks/methods
    initial_goal: "deliver_feature"
  }

# HTN agent:
# - Receives goal as intent signal
# - Plans decomposition using domain knowledge
# - Emits subtasks as intents to specialist agents
# - Replans when status/alerts indicate failure
```

---

### 2. Behavior Trees → Tactical/Operational Agents

**What it is:**
- Reactive execution with composites (Sequence, Selector, Parallel)
- Real-time responsiveness via tick-based evaluation
- Built-in fallback, retry, timeout, monitoring patterns

**Best for:**
- **Operators/Executors** - Run sequences with robust error handling
- **Monitors/Guards** - Continuously check conditions, emit alerts
- **Real-time Reactors** - Respond to changing environment quickly

**Example roles:**
- Code Implementation Operator - Executes coding patterns, runs tests, reacts to failures
- QA Monitor - Continuously runs tests, detects regressions, triggers alerts
- Experiment Runner - Executes data collection with retries and fallbacks

**Key BT capabilities:**
```elixir
use Jido.Agent,
  strategy: {Jido.Agent.Strategy.BehaviorTree,
    tree: build_tree()  # Sequence/Selector/Decorator composition
  }

# Example tree structure:
# Selector (try alternatives)
#   → Sequence (happy path)
#       → Action (execute step)
#       → Condition (verify success)
#   → Sequence (fallback)
#       → Action (rollback)
#       → Emit (alert to team)

# BT agent:
# - Ticks tree frequently (10-100Hz for reactive tasks)
# - Automatically handles retries, timeouts
# - Embeds ReAct/HTN in leaf nodes for decisions
```

---

### 3. ReAct → Analytical/Reasoning Agents

**What it is:**
- Reason-Act loops with LLM-powered reasoning
- Tool use for information gathering and actions
- Adaptive to novel/ambiguous situations

**Best for:**
- **Analysts** - Research, hypothesis generation, evaluation
- **Negotiators** - Resolve conflicts, compare proposals
- **Critics/Reviewers** - Evaluate plans, detect issues
- **Tool Specialists** - Complex data analysis, code generation

**Example roles:**
- Design Analyst - Explores architectural options, evaluates trade-offs
- Root Cause Analyst - Investigates incidents using logs and telemetry
- Plan Critic - Reviews HTN plans, suggests improvements
- Negotiator - Resolves resource conflicts between agents

**Key ReAct capabilities:**
```elixir
use Jido.Agent,
  strategy: {
    Jido.AI.Strategy.ReAct,
    tools: [CodeSearch, FileReader, GitLog, Synthesize],
    system_prompt: "You are a design analyst..."
  }

# ReAct agent:
# - Receives open-ended queries/intents
# - Reasons through multi-step process
# - Uses tools to gather info, execute actions
# - Proposes solutions or synthesizes findings
```

---

### Hybrid Strategies: Composing Workflows

**Pattern: BT with ReAct Leaf Nodes**
```elixir
# BT for robust execution flow
tree = Sequence.new([
  # ReAct node for complex decision
  ReActDecision.new(
    query: "Should we proceed with migration given test results?",
    tools: [AnalyzeTests, CheckMetrics]
  ),
  # Conditional based on ReAct output
  Selector.new([
    # If proceed = true
    Sequence.new([
      ExecuteMigration.new(),
      VerifyMigration.new()
    ]),
    # Else rollback
    Rollback.new()
  ])
])
```

**Pattern: HTN with BT Primitive Tasks**
```elixir
# HTN domain where primitives are BT agents
domain = Domain.build do
  primitive_task "deploy_service" do
    # Instead of simple action, spawn BT agent
    task: {SpawnAgent, [agent: DeployOperatorBT, params: [...]]}
    preconditions: [service_ready: true]
    effects: [deployed: true]
  end
end
```

**Pattern: ReAct that Generates HTN Methods**
```elixir
# ReAct agent with tools to modify HTN domain
tools = [
  AnalyzePastPlans,
  ProposeNewMethod,
  ValidateMethod
]

# ReAct reasons about domain and suggests:
# "For goal X under constraint Y, here's a better decomposition..."
# Output: New HTN method added to domain
```

---

## Team Patterns: From Hierarchical to Collaborative

### Pattern 1: Mission Owner + Autonomous Specialists (Hierarchical)

**Structure:**
```
Mission Owner (HTN)
├── Design Analyst (ReAct)
├── Implementation Operator (BT)
├── QA Monitor (BT)
└── Synthesizer (ReAct)
```

**How it works:**
1. **Mission Owner (HTN)** decomposes high-level goal into subgoals
2. Emits **intent signals** to specialists (not step-by-step commands)
3. Specialists **self-organize** to accomplish subgoals
4. Send **status** and **alerts** back to mission owner
5. Mission owner **replans** if major issues arise

**Example:
```elixir
# Coordinator agent
defmodule GTD.CoordinatorAgent do
  use Jido.Agent,
    name: "gtd_coordinator",
    strategy: {GTD.Strategy, roles: [...]}
  
  # Minimal orchestration state:
  # - task_queue
  # - worker_pids by role
  # - status
end

# Specialized worker with ReAct
defmodule GTD.ClarifierAgent do
  use Jido.Agent,
    name: "gtd_clarifier",
    strategy: {
      Jido.AI.Strategy.ReAct,
      tools: [GTD.Tools.ParseTask, GTD.Tools.TagContext],
      system_prompt: "You clarify tasks..."
    }
end
```

**Benefits:**
- Clear separation of orchestration vs execution
- Workers can be ReAct agents (for reasoning) or simple agents (for fixed logic)
- Team composition is dynamic

---

## Capability Team Architecture

### Anatomy of a Capability Team

A capability team consists of:

1. **Public API Module** (`MyApp.TeamName`)
   - `start/2` - starts coordinator under Jido instance
   - Signal protocol documentation
   - Schema definitions for signals

2. **Workflow Machine** (`TeamName.Workflow.Machine`)
   - Pure FSM with team's workflow states
   - Messages for state transitions
   - Abstract directives for coordination

3. **Strategy Adapter** (`TeamName.Strategy`)
   - Implements `Jido.Agent.Strategy`
   - Maps signals → machine messages
   - Lifts machine directives → SDK directives

4. **Coordinator Agent** (`TeamName.CoordinatorAgent`)
   - Uses the team's strategy
   - Holds minimal meta-state
   - Spawns/manages workers

5. **Role Agents** (`TeamName.RoleNameAgent`)
   - Each role is a specialized agent
   - Often uses `ReAct.Strategy` with domain tools
   - Communicates via signal protocol

6. **Signal Protocol**
   - Typed signals define team contract
   - Schemas validate signal data
   - Naming convention: `"team.phase.event"`

---

### Example: GTD Task Management Team

```
GTD Team
├── Public API
│   └── GTD.start(jido_instance, opts) → coordinator_pid
│
├── Workflow Machine
│   └── GTD.Workflow.Machine
│       States: :idle → :capturing → :clarifying → :organizing → :reviewing → :done
│       Messages: {:new_task, data}, {:clarified, result}, {:organized, result}
│       Directives: {:spawn_clarifier}, {:spawn_organizer}, {:complete_task}
│
├── Strategy
│   └── GTD.Strategy
│       Signal routes: "gtd.task.create" → :new_task
│                      "gtd.clarified" → :clarified
│                      "gtd.organized" → :organized
│
├── Coordinator
│   └── GTD.CoordinatorAgent
│       State: %{tasks: [], workers: %{}, status: :idle}
│       Uses: GTD.Strategy
│
└── Role Agents
    ├── GTD.ClarifierAgent (ReAct + parsing tools)
    ├── GTD.OrganizerAgent (ReAct + categorization tools)
    ├── GTD.PlannerAgent (ReAct + planning tools)
    └── GTD.ExecutorAgent (ReAct + action tools)
```

**Signal Protocol:**
```elixir
# Inbound
"gtd.task.create" → %{description: string, context: map}

# Internal workflow
"gtd.worker.clarified" → %{task_id: id, next_action: string, context: string}
"gtd.worker.organized" → %{task_id: id, category: atom, projects: [string]}
"gtd.worker.planned" → %{task_id: id, steps: [map], effort: integer}

# Outbound
"gtd.task.completed" → %{task_id: id, result: any}
"gtd.task.next_actions" → %{actions: [map]}
```

---

### Example: Code Research & Planning Team

```
CodeResearch Team
├── Public API
│   └── CodeResearch.start(jido_instance, opts) → coordinator_pid
│
├── Workflow Machine
│   └── CodeResearch.Workflow.Machine
│       States: :idle → :planning → :researching → :synthesizing → :done
│       Messages: {:new_query, query}, {:plan_ready, plan}, {:insights, data}
│       Directives: {:spawn_planner}, {:spawn_readers, N}, {:aggregate}
│
├── Strategy
│   └── CodeResearch.Strategy
│       Signal routes: "research.request" → :new_query
│                      "research.plan" → :plan_ready
│                      "research.insight" → :insights
│
├── Coordinator
│   └── CodeResearch.CoordinatorAgent
│       State: %{query: "", plan: nil, insights: [], workers: %{}}
│       Uses: CodeResearch.Strategy
│
└── Role Agents
    ├── CodeResearch.PlannerAgent (ReAct + code search tools)
    ├── CodeResearch.ReaderAgent (ReAct + file reading tools)
    ├── CodeResearch.AnalyzerAgent (ReAct + analysis tools)
    └── CodeResearch.SynthesizerAgent (ReAct + summarization tools)
```

**Signal Protocol:**
```elixir
# Inbound
"research.request" → %{query: string, codebase_path: string, context: map}

# Internal workflow
"research.plan.generated" → %{subtasks: [map], search_strategy: string}
"research.subtask.result" → %{subtask_id: id, findings: string, files: [string]}
"research.synthesis.partial" → %{section: string, content: string}

# Outbound
"research.complete" → %{markdown_doc: string, files_analyzed: [string]}
"research.breakdown" → %{steps: [%{description: string, estimated_effort: integer}]}
```

---

## Organization Strategies

### Strategy 1: Namespace by Capability

```
lib/
├── jido_gtd/
│   ├── jido_gtd.ex                    # Public API
│   ├── workflow/
│   │   └── machine.ex                 # GTD.Workflow.Machine
│   ├── strategy.ex                    # GTD.Strategy
│   ├── coordinator_agent.ex           # GTD.CoordinatorAgent
│   ├── agents/
│   │   ├── clarifier_agent.ex
│   │   ├── organizer_agent.ex
│   │   ├── planner_agent.ex
│   │   └── executor_agent.ex
│   └── tools/
│       ├── parse_task.ex
│       ├── tag_context.ex
│       └── categorize.ex
│
└── jido_code_research/
    ├── jido_code_research.ex          # Public API
    ├── workflow/
    │   └── machine.ex                 # CodeResearch.Workflow.Machine
    ├── strategy.ex                    # CodeResearch.Strategy
    ├── coordinator_agent.ex           # CodeResearch.CoordinatorAgent
    ├── agents/
    │   ├── planner_agent.ex
    │   ├── reader_agent.ex
    │   ├── analyzer_agent.ex
    │   └── synthesizer_agent.ex
    └── tools/
        ├── code_search.ex
        ├── file_reader.ex
        └── synthesize.ex
```

**Benefits:**
- Clear boundaries between capabilities
- Each can be a separate hex package
- Easy to version/publish independently

---

### Strategy 2: Shared Infrastructure Layer

Create common patterns for all capability teams:

```
lib/
├── jido_capabilities/
│   ├── team.ex                        # Team behavior & helpers
│   ├── workflow_strategy.ex           # Generic workflow strategy
│   ├── coordinator.ex                 # Coordinator behavior
│   └── protocols.ex                   # Signal naming conventions
│
├── jido_gtd/
│   ├── (uses Jido.Capabilities.Team)
│   └── ...
│
└── jido_code_research/
    ├── (uses Jido.Capabilities.Team)
    └── ...
```

**Example shared behavior:**
```elixir
defmodule Jido.Capabilities.Team do
  @moduledoc """
  Behavior for capability teams with coordinator-worker pattern.
  """
  
  @callback workflow_machine() :: module()
  @callback role_agents() :: keyword(module())
  @callback signal_protocol() :: map()
  
  defmacro __using__(opts) do
    quote do
      @behaviour Jido.Capabilities.Team
      
      def start(jido_instance, opts \\ []) do
        # Standard team startup logic
        coordinator = coordinator_agent()
        Jido.start_agent(jido_instance, coordinator, opts)
      end
      
      # Helper functions all teams get
      def spawn_role(coordinator_pid, role, params) do
        # ...
      end
    end
  end
end
```

**Benefits:**
- Reduces boilerplate per team
- Enforces consistent patterns
- Makes new capabilities easier to add

---

### Strategy 3: Capability Registry

Central registry for discovering and routing to capabilities:

```elixir
defmodule Jido.Capabilities.Registry do
  @moduledoc """
  Registry of available capability teams and their protocols.
  """
  
  def register(capability_name, module, metadata) do
    # Register a capability team
  end
  
  def list_capabilities do
    # Return all registered capabilities
  end
  
  def route_request(intent, context) do
    # Match intent to capability and return coordinator module
  end
end

# In each capability's application start:
def start(_type, _args) do
  Jido.Capabilities.Registry.register(
    :gtd,
    GTD,
    %{
      signals: ["gtd.task.create", "gtd.task.complete"],
      description: "Getting Things Done task management",
      version: "1.0.0"
    }
  )
end
```

**Benefits:**
- Dynamic capability discovery
- Enables meta-agents that delegate to capabilities
- Can build capability composition tools

---

## Extension Points

### 1. ReAct Agents as Tools

ReAct agents can **use tools that spawn other agents**:

```elixir
defmodule GTD.Tools.DelegateResearch do
  use Jido.Action,
    name: "delegate_research",
    description: "Delegate code research to research team",
    schema: Zoi.object(%{
      query: Zoi.string(),
      codebase_path: Zoi.string()
    })
  
  def run(params, context) do
    # Spawn research team coordinator
    # Return worker_id for tracking
    {:ok, %{research_worker_id: worker_id}}
  end
end

# Now a GTD planner can:
# 1. Realize a task requires code research
# 2. Use "delegate_research" tool
# 3. Track research worker via ID
# 4. Wait for research.complete signal
```

**Result:** Capabilities can **compose** by using each other as tools.

---

### 2. Nested Team Hierarchies

Coordinators can spawn sub-coordinators:

```
ProjectManager (Coordinator)
├── GTD.Coordinator
│   ├── GTD.ClarifierAgent
│   └── GTD.PlannerAgent
├── CodeResearch.Coordinator
│   ├── CodeResearch.PlannerAgent
│   ├── CodeResearch.ReaderAgent (1)
│   ├── CodeResearch.ReaderAgent (2)
│   └── CodeResearch.SynthesizerAgent
└── Execution.Coordinator
    ├── Execution.TestRunnerAgent
    └── Execution.CodeWriterAgent
```

**Pattern:**
```elixir
# ProjectManager spawns capability coordinators
spawn_directive = Directive.spawn_agent(GTD.CoordinatorAgent, :gtd_team)

# Each coordinator manages its own workers
# Signal routing bubbles up: worker → coordinator → project manager
```

---

### 3. Cross-Capability Orchestration

A meta-coordinator routes work across capabilities:

```elixir
defmodule ProjectOrchestrator do
  use Jido.Agent,
    strategy: {ProjectOrchestrator.Strategy, capabilities: [:gtd, :research, :execution]}
  
  # Workflow:
  # 1. Receive high-level goal
  # 2. Break into phases
  # 3. Route each phase to appropriate capability
  # 4. Coordinate handoffs between capabilities
  # 5. Aggregate final result
end
```

**Signal flow:**
```
User → "project.goal" → ProjectOrchestrator
  ├→ "gtd.task.create" → GTD.Coordinator → "gtd.task.completed" ┐
  ├→ "research.request" → Research.Coordinator → "research.complete" → Orchestrator
  └→ "execution.run" → Execution.Coordinator → "execution.done" ┘
```

---

### 4. Higher-Level Directives

As patterns stabilize, add capability-specific directives:

```elixir
defmodule Jido.Capabilities.Directive do
  alias Jido.Agent.Directive
  
  def spawn_team(team_module, tag, opts \\ []) do
    # Spawns coordinator + pre-configured workers
    # Returns team_id for tracking
  end
  
  def broadcast_to_team(team_id, signal) do
    # Sends signal to all workers in a team
  end
  
  def delegate_to_capability(capability, request) do
    # High-level: spawn capability coordinator, send request, track result
  end
end
```

---

### 5. Observability & Monitoring

Strategy snapshots enable monitoring:

```elixir
# Each capability exposes snapshot
def snapshot(agent, _ctx) do
  %Snapshot{
    status: :running | :success | :failure,
    details: %{
      phase: :researching,
      workers_active: 3,
      tasks_completed: 5,
      estimated_completion: ~U[2026-01-03 12:00:00Z]
    }
  }
end

# Monitoring agent polls snapshots
defmodule CapabilityMonitor do
  def check_team_health(coordinator_pid) do
    {:ok, snapshot} = Jido.snapshot(jido_instance, coordinator_pid)
    
    case snapshot.status do
      :failure -> restart_team(coordinator_pid)
      :running ->
        if snapshot.details.workers_active == 0 do
          # Stalled?
          investigate(coordinator_pid)
        end
    end
  end
end
```

---

## Implementation Roadmap

### Phase 1: Foundation (Proof of Concept)
**Goal:** Validate pattern with one simple capability

**Tasks:**
1. Extract workflow machine pattern from ReAct
2. Create `Jido.Capabilities.WorkflowStrategy` base
3. Implement simple GTD capability:
   - Capture task
   - Clarify with ReAct agent
   - Return next action
4. Validate signal routing works
5. Test coordinator spawning workers

**Deliverable:** Working GTD capability with 1 coordinator + 1 worker

**Effort:** S-M (4-8 hours)

---

### Phase 2: Refine & Generalize
**Goal:** Make pattern reusable for second capability

**Tasks:**
1. Extract common coordinator behavior
2. Create `Jido.Capabilities.Team` behavior
3. Implement code research capability:
   - Plan research
   - Spawn multiple reader agents
   - Synthesize findings
4. Document signal protocol patterns
5. Add observability (snapshots)

**Deliverable:** Two working capabilities + reusable framework

**Effort:** M (8-16 hours)

---

### Phase 3: Infrastructure
**Goal:** Production-ready capability system

**Tasks:**
1. Create capability registry
2. Add monitoring/health checks
3. Implement cross-capability orchestration
4. Add error handling & retry logic
5. Write comprehensive docs

**Deliverable:** Production-ready capability framework

**Effort:** L (16-24 hours)

---

### Phase 4: Advanced Patterns
**Goal:** Enable complex multi-capability workflows

**Tasks:**
1. Nested team hierarchies
2. Dynamic team composition
3. Capability-as-tool pattern
4. Meta-orchestrator agents
5. Performance optimization

**Deliverable:** Advanced multi-agent orchestration

**Effort:** XL (24-40 hours)

---

## Advanced Patterns

### Pattern: Capability as a Service

Package capabilities as standalone services:

```elixir
# In supervision tree
children = [
  {GTD.Supervisor, name: GTD.Service},
  {CodeResearch.Supervisor, name: CodeResearch.Service}
]

# Each capability service:
# - Maintains pool of coordinator agents
# - Load balances requests
# - Provides metrics/telemetry
```

---

### Pattern: Capability Composition

Capabilities declare dependencies:

```elixir
defmodule AdvancedGTD do
  use Jido.Capabilities.Team
  
  @capabilities [:gtd, :research, :calendar]
  
  def workflow_machine, do: AdvancedGTD.Workflow.Machine
  
  # Can delegate to other capabilities
  def handle_complex_task(task) do
    with {:ok, research} <- delegate_to(:research, task.query),
         {:ok, plan} <- delegate_to(:gtd, research.breakdown),
         {:ok, scheduled} <- delegate_to(:calendar, plan.actions) do
      {:ok, scheduled}
    end
  end
end
```

---

### Pattern: Adaptive Team Sizing

Coordinators dynamically scale workers:

```elixir
defmodule CodeResearch.Coordinator do
  # Based on workload, spawn more readers
  def handle_signal(agent, %Signal{type: "research.plan.generated"}) do
    subtasks = agent.state.plan.subtasks
    
    # Spawn 1 reader per 5 subtasks, max 10
    num_readers = min(div(length(subtasks), 5) + 1, 10)
    
    spawn_directives =
      for i <- 1..num_readers do
        Directive.spawn_agent(CodeResearch.ReaderAgent, :"reader_#{i}")
      end
    
    {agent, spawn_directives}
  end
end
```

---

### Pattern: Fault-Tolerant Workflows

Machine tracks worker failures and retries:

```elixir
defmodule GTD.Workflow.Machine do
  def update(machine, {:worker_failed, role, reason}, env) do
    attempts = Map.get(machine.retry_counts, role, 0)
    
    if attempts < env.max_retries do
      # Retry
      machine = update_in(machine.retry_counts[role], &(&1 + 1))
      {machine, [{:spawn_worker, role, []}]}
    else
      # Escalate
      {machine, [{:emit_error, role, reason}]}
    end
  end
end
```

---

## Conclusion

Higher-order capabilities in Jido follow a clear architectural pattern:

1. **Pure workflow machines** encode domain logic
2. **Strategy adapters** connect workflows to Jido runtime
3. **Coordinator agents** orchestrate via signals
4. **Specialized workers** (often ReAct agents) execute roles
5. **Signal protocols** define team contracts

This pattern:
- ✅ Reuses proven Jido primitives
- ✅ Keeps complexity localized and testable
- ✅ Enables composition and nesting
- ✅ Scales from simple to sophisticated workflows

**Next Steps:**
1. Validate with simple GTD proof-of-concept
2. Refine into reusable framework
3. Build out infrastructure for production use
4. Explore advanced multi-capability orchestration

The architecture is **ready to support both GTD and code research teams** as first examples, with a clear path to generalizing into a robust capability system.

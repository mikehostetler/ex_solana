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
2. [Persistence & Domain Modeling with Ash](#persistence--domain-modeling-with-ash)
3. [Team Patterns](#team-patterns)
4. [Concrete Team Compositions](#concrete-team-compositions)
5. [Signal Protocols](#signal-protocols)
6. [Capability Architecture](#capability-architecture)
7. [Organization Strategies](#organization-strategies)
8. [Implementation Roadmap](#implementation-roadmap)
9. [Advanced Patterns](#advanced-patterns)

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

## Persistence & Domain Modeling with Ash

**The Big Picture:** Ash Framework as the operational database and domain model for multi-agent teams.

Agents don't store state in-memory or hit raw databases—they **interact with Ash Domains**:
- **Ash Resources** = persistent world model (tasks, projects, findings, reports, agent runs)
- **Ash Actions** = domain verbs (create_task, clarify_task, publish_report)
- **ash_jido** = automatic bridge making every Ash action available as a Jido tool
- **Policies** = agent permissions ("who can do what")
- **Multitenancy** = workspace/org isolation
- **Events** = audit trail of agent decisions

**Mental Model:**
- Agents read/write via **domain actions**, not raw SQL
- All durable state lives in **Ash resources**
- Plans & workflows are described in terms of **domain verbs**

### Key Persistence Patterns

**1. ash_jido: Ash Actions as Jido Tools**

Automatically generates `Jido.Action` modules from Ash resource actions:

```elixir
defmodule MyApp.GTD.Task do
  use Ash.Resource,
    domain: MyApp.GTD,
    extensions: [AshJido]

  actions do
    create :capture
    update :clarify
    update :complete
  end

  jido do
    action :capture, name: "capture_task", tags: ["gtd", "intake"]
    action :clarify, name: "clarify_task"
    # Or: all_actions except: [:internal]
  end
end

# Auto-generated tool:
MyApp.GTD.Task.Jido.Capture.run(
  %{description: "Research agents"},
  %{domain: MyApp.GTD, actor: agent, tenant: "user_123"}
)
```

**2. Persistent Agent State**

Track agent runs and working memory:

```elixir
# Agent lifecycle resources
defmodule MyApp.AgentRun do
  use Ash.Resource, extensions: [AshJido]
  
  attributes do
    uuid_v7_primary_key :id
    attribute :agent_id, :uuid
    attribute :started_at, :utc_datetime_usec
    attribute :status, :atom
  end
  
  actions do
    create :start
    update :complete
  end
end

# Agent working memory (blackboard)
defmodule MyApp.AgentState do
  use Ash.Resource, extensions: [AshJido]
  
  attributes do
    uuid_v7_primary_key :id
    attribute :agent_run_id, :uuid
    attribute :data, :map  # Current beliefs/state
  end
  
  actions do
    update :update_data, name: "update_blackboard"
    read :read_current, name: "read_blackboard"
  end
end
```

**3. Event Sourcing**

Capture agent decisions as domain events:

```elixir
defmodule MyApp.DomainEvent do
  use Ash.Resource, extensions: [AshJido]
  
  attributes do
    uuid_v7_primary_key :id
    attribute :type, :string  # "TaskCreated", "FindingAdded"
    attribute :entity_type, :string
    attribute :entity_id, :uuid
    attribute :agent_id, :uuid
    attribute :payload, :map  # Decision context, rationale
    attribute :inserted_at, :utc_datetime_usec
  end
end

# Emit events via Ash changes:
defmodule MyApp.GTD.Task do
  actions do
    create :capture do
      change after_action(fn changeset, task ->
        record_event("TaskCaptured", task, changeset.context)
      end)
    end
  end
end
```

**4. Transactional Workflows**

Atomic operations across resources:

```elixir
defmodule MyApp.GTD.Task do
  actions do
    # Atomic: process inbox → create task → mark processed
    create :create_from_inbox do
      argument :inbox_item_id, :uuid
      
      change fn changeset, _ctx ->
        inbox = MyApp.InboxItem.get!(changeset.arguments.inbox_item_id)
        
        changeset
        |> Ash.Changeset.change_attribute(:description, inbox.text)
        |> Ash.Changeset.after_action(fn _, task ->
          inbox |> Ash.Changeset.for_update(:mark_processed) |> Ash.update!()
          {:ok, task}
        end)
      end
    end
  end
end
```

**5. Work Item Coordination**

Agents coordinate via shared work queue:

```elixir
defmodule MyApp.WorkItem do
  use Ash.Resource, extensions: [AshJido]
  
  attributes do
    uuid_v7_primary_key :id
    attribute :status, :atom  # :unclaimed, :in_progress, :done
    attribute :assignee_agent_type, :atom
    attribute :version, :integer  # Optimistic lock
  end
  
  actions do
    update :claim do
      # Optimistic concurrency
      change fn changeset, _ctx ->
        changeset
        |> Ash.Changeset.filter(status: :unclaimed)
        |> Ash.Changeset.filter(version: changeset.data.version)
        |> Ash.Changeset.change_attribute(:version, changeset.data.version + 1)
      end
    end
    
    read :list_unclaimed do
      argument :agent_type, :atom
      filter expr(status == :unclaimed and assignee_agent_type == ^arg(:agent_type))
    end
  end
end
```

**6. Authorization via Policies**

Control agent permissions:

```elixir
defmodule MyApp.GTD.Task do
  policies do
    # Clarifiers can create/clarify
    policy action(:clarify) do
      authorize_if expr(:clarifier in actor.roles)
    end
    
    # Executors can only complete
    policy action(:complete) do
      authorize_if expr(:executor in actor.roles)
    end
  end
end
```

**7. Domain-Driven Team Boundaries**

```elixir
# GTD Domain
defmodule MyApp.GTD do
  use Ash.Domain
  resources do
    resource MyApp.GTD.Task
    resource MyApp.GTD.Project
    resource MyApp.GTD.Context
  end
end

# Research Domain  
defmodule MyApp.CodeResearch do
  use Ash.Domain
  resources do
    resource MyApp.CodeResearch.Question
    resource MyApp.CodeResearch.Finding
    resource MyApp.CodeResearch.Report
  end
end

# Agent toolboxes match domains
gtd_toolbox = extract_jido_tools(MyApp.GTD)
research_toolbox = extract_jido_tools(MyApp.CodeResearch)
```

**Benefits:**
- ✅ **Persistent state**: Agents survive restarts
- ✅ **Transactional**: ACID guarantees across operations
- ✅ **Auditable**: Complete event trail
- ✅ **Queryable**: Domain data accessible via SQL/Ash queries
- ✅ **Policy-enforced**: Authorization built-in
- ✅ **Multi-tenant**: Workspace isolation automatic
- ✅ **Domain-driven**: Clear bounded contexts

See [GTD Complete Example](#gtd-domain-complete-example) and [Research Complete Example](#code-research-domain-complete-example) for full implementations.

---

## Team Patterns

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

**Example: Software Feature Delivery**
```elixir
# Mission Owner (HTN)
defmodule FeatureDelivery.MissionOwner do
  use Jido.Agent,
    strategy: {Jido.Agent.Strategy.HTN, domain: FeatureDeliveryDomain}

  # HTN domain defines:
  # compound_task "deliver_feature" with methods:
  #   - Standard: design → implement → qa → deploy
  #   - FastTrack: implement → minimal_qa → deploy
  #   - Research: spike → design → prototype → evaluate

  def handle_signal(agent, %Signal{type: "feature.request", data: data}) do
    # HTN plans decomposition based on constraints
    # Emits intents to specialists
    {agent, [
      spawn_directive(DesignAnalyst, :design_lead),
      spawn_directive(ImplementationOperator, :impl_lead),
      spawn_directive(QAMonitor, :qa_lead)
    ]}
  end

  def handle_signal(agent, %Signal{type: "team.status", data: data}) do
    # Collect status from team
    # If major blockers, trigger replan
    if data.severity == :blocking do
      {agent, replan_directives(agent.state)}
    else
      {agent, []}
    end
  end
end

# Design Analyst (ReAct)
defmodule FeatureDelivery.DesignAnalyst do
  use Jido.Agent,
    strategy: {
      Jido.AI.Strategy.ReAct,
      tools: [AnalyzeRequirements, ExploreArchitectures, EvaluateTradeoffs],
      system_prompt: "You analyze designs and propose architectures"
    }

  def handle_signal(agent, %Signal{type: "intent.design", data: data}) do
    # ReAct explores options, evaluates, proposes
    # Sends proposal back to mission owner and peers
    {agent, []}
  end
end

# Implementation Operator (BT)
defmodule FeatureDelivery.ImplementationOperator do
  use Jido.Agent,
    strategy: {Jido.Agent.Strategy.BehaviorTree, tree: build_impl_tree()}

  defp build_impl_tree do
    Selector.new([
      # Try standard implementation flow
      Sequence.new([
        ReadDesign.new(),
        Parallel.new([
          WriteCode.new(),
          RunTests.new()  # Continuous
        ]),
        Condition.new(:tests_passing?),
        CommitChanges.new()
      ]),
      # Fallback: Alert and wait for help
      Sequence.new([
        EmitAlert.new(severity: :help_needed, context: :implementation),
        Wait.new(for_signal: "analyst.guidance")
      ])
    ])
  end

  # BT ticks automatically, reacts to test failures, design changes
end

# QA Monitor (BT)
defmodule FeatureDelivery.QAMonitor do
  use Jido.Agent,
    strategy: {Jido.Agent.Strategy.BehaviorTree, tree: build_qa_tree()}

  defp build_qa_tree do
    Parallel.new([
      # Continuously run tests
      Repeat.new(Sequence.new([
        RunTestSuite.new(),
        UpdateMetrics.new()
      ])),
      # Monitor for regressions
      Sequence.new([
        Condition.new(:regression_detected?),
        EmitAlert.new(severity: :critical, context: :regression)
      ])
    ])
  end
end
```

**Benefits:**
- Mission owner focuses on strategy, not micro-management
- Specialists are intelligent, can adapt locally
- Clear hierarchy for escalation and replanning

**When to use:**
- Clear mission with structured workflow
- Need centralized replanning for consistency
- Specialists have distinct domains

---

### Pattern 2: Peer Collaboration with Negotiation

**Structure:**
```
Peers (equal authority)
├── Analyst 1 (ReAct) ←→ Analyst 2 (ReAct)
├── Operator (BT)     ←→ Monitor (BT)
└── (optional) Facilitator (ReAct) - mediates conflicts
```

**How it works:**
1. **Peers receive shared goal** (from external source or facilitator)
2. **Propose approaches** independently
3. **Negotiate** via query/proposal/vote signals
4. **Commit** to joint plan
5. **Execute** with peer accountability

**Example: Code Research Team**
```elixir
# Two research analysts collaborate
defmodule CodeResearch.Analyst do
  use Jido.Agent,
    strategy: {
      Jido.AI.Strategy.ReAct,
      tools: [CodeSearch, FileRead, AnalyzePatterns],
      system_prompt: "You research codebases collaboratively"
    }

  def handle_signal(agent, %Signal{type: "research.intent", data: data}) do
    # Each analyst proposes research approach
    proposal = generate_proposal(agent, data.query)
    
    {agent, [
      Directive.emit(Signal.new!("research.proposal", proposal, source: agent.id))
    ]}
  end

  def handle_signal(agent, %Signal{type: "research.proposal", data: data}) do
    # Compare with own proposal
    # If peer's is better, endorse it
    # If conflicting, negotiate
    evaluation = evaluate_proposal(agent, data)
    
    response = case evaluation do
      :endorse -> Signal.new!("research.endorse", data, source: agent.id)
      :object -> Signal.new!("research.object", %{reason: "..."}, source: agent.id)
      :merge -> Signal.new!("research.counter_proposal", merge_proposals(agent, data))
    end
    
    {agent, [Directive.emit(response)]}
  end
end

# Facilitator mediates if needed
defmodule CodeResearch.Facilitator do
  use Jido.Agent,
    strategy: {Jido.AI.Strategy.ReAct, tools: [EvaluateProposals, ResolveTieBreak]}

  def handle_signal(agent, %Signal{type: "research.object", data: data}) do
    # Conflict detected, facilitate resolution
    # Analyze both proposals, suggest synthesis
    {agent, []}
  end
end
```

**Benefits:**
- Distributed intelligence, no single point of failure
- Rich negotiation enables better solutions
- Peer accountability

**When to use:**
- Open-ended problems with multiple valid approaches
- Want diverse perspectives
- No clear hierarchical authority

---

### Pattern 3: Squad-based with Sub-teams

**Structure:**
```
Meta-Coordinator (HTN)
├── Squad A (focused capability)
│   ├── Squad Lead (HTN)
│   ├── Specialist 1 (ReAct)
│   └── Operator (BT)
├── Squad B (focused capability)
│   ├── Squad Lead (HTN)
│   ├── Specialist 2 (BT + ReAct hybrid)
│   └── Monitor (BT)
└── Cross-Squad Liaison (ReAct) - coordinates dependencies
```

**How it works:**
1. **Meta-coordinator** breaks mission into sub-missions
2. **Squad leads** own their sub-mission, run local HTN
3. **Squads operate autonomously** with own team dynamics
4. **Liaison agents** coordinate cross-squad dependencies

**Example: GTD + Code Research Combined**
```elixir
# Meta-coordinator
defmodule ProductivityHub.MetaCoordinator do
  use Jido.Agent,
    strategy: {Jido.Agent.Strategy.HTN, domain: ProductivityDomain}

  # Domain defines:
  # compound_task "manage_project" with squads:
  #   - GTD squad for task/project management
  #   - Research squad for code investigation
  #   - Execution squad for implementation
end

# GTD Squad Lead
defmodule GTD.SquadLead do
  use Jido.Agent,
    strategy: {Jido.Agent.Strategy.HTN, domain: GTDDomain}

  # Manages capture → clarify → organize → review → do
  # Spawns clarifier, organizer, planner agents
end

# Research Squad Lead
defmodule Research.SquadLead do
  use Jido.Agent,
    strategy: {Jido.Agent.Strategy.HTN, domain: ResearchDomain}

  # Manages plan → investigate → synthesize pipeline
  # Spawns planner, reader, analyzer agents
end

# Liaison coordinates when GTD task requires research
defmodule Liaison.CrossSquad do
  use Jido.Agent,
    strategy: {Jido.AI.Strategy.ReAct, tools: [DetectDependency, NegotiateHandoff]}

  def handle_signal(agent, %Signal{type: "gtd.task.needs_research", data: data}) do
    # Detect that GTD task requires research input
    # Negotiate handoff to research squad
    # Track dependency and coordinate completion
    {agent, [
      emit_to_pid(
        Signal.new!("research.intent", %{query: data.research_query, requester: data.task_id}),
        research_squad_pid
      )
    ]}
  end
end
```

**Benefits:**
- Scales to large, complex missions
- Squads can specialize deeply
- Clear ownership boundaries

**When to use:**
- Large capabilities with distinct domains
- Need parallel work streams
- Complex dependencies to manage

---

## Concrete Team Compositions

### 1. GTD Task Management Team

**Goal:** Manage personal/team tasks using Getting Things Done methodology

**Team Composition:**
```
GTD Mission Planner (HTN)
├── Capture Agent (BT) - Continuously monitors inputs
├── Clarifier (ReAct) - Parses tasks, identifies next actions
├── Organizer (ReAct) - Categorizes, assigns contexts/projects
├── Planner (HTN) - Breaks complex tasks into subtasks
├── Review Agent (ReAct) - Weekly reviews, reprioritization
└── Executor (BT) - Executes next actions, tracks completion
```

**HTN Domain:**
```elixir
domain = Domain.build do
  compound_task "manage_task" do
    method "standard_gtd" do
      preconditions: [captured: true]
      subtasks: ["clarify", "organize", "review", "execute"]
    end
    
    method "quick_action" do
      preconditions: [captured: true, duration: {:lt, 2}]  # <2 min
      subtasks: ["execute"]  # Just do it
    end
    
    method "someday_maybe" do
      preconditions: [captured: true, actionable: false]
      subtasks: ["archive"]
    end
  end
  
  compound_task "clarify" do
    # Spawn ReAct clarifier agent
  end
  
  compound_task "organize" do
    # Spawn ReAct organizer agent
  end
  
  # ... etc
end
```

**Signal Protocol:**
```elixir
# Inputs
"gtd.task.create" → %{description: string, context: map}

# Internal workflow
"gtd.task.captured" → %{task_id: id, raw: string}
"gtd.task.clarified" → %{task_id: id, next_action: string, context: string, project: string}
"gtd.task.organized" → %{task_id: id, category: atom, priority: integer}

# Outputs
"gtd.task.ready" → %{task_id: id, next_action: string}
"gtd.review.complete" → %{tasks_reviewed: integer, adjustments: [map]}
```

---

### 2. Code Research & Planning Team

**Goal:** Deep codebase research and implementation planning

**Team Composition:**
```
Research Strategist (HTN)
├── Query Interpreter (ReAct) - Understands intent, refines query
├── Planner (ReAct) - Generates research plan
├── Reader Agent Pool (BT, spawned dynamically)
│   ├── Reader 1, 2, ... N (parallel file analysis)
├── Pattern Analyzer (ReAct) - Identifies architectural patterns
├── Synthesizer (ReAct) - Combines findings into report
└── Breakdown Generator (HTN) - Creates implementation steps
```

**HTN Domain:**
```elixir
domain = Domain.build do
  compound_task "research_codebase" do
    method "comprehensive" do
      preconditions: [query_complexity: :high]
      subtasks: ["interpret_query", "plan_research", "execute_search", "analyze_patterns", "synthesize"]
    end
    
    method "targeted" do
      preconditions: [query_complexity: :low]
      subtasks: ["execute_search", "synthesize"]
    end
  end
  
  compound_task "execute_search" do
    method "parallel_read" do
      preconditions: [file_count: {:gt, 10}]
      # Spawn N reader agents based on file count
      subtasks: (for i <- 1..n, do: "read_batch_#{i}")
    end
  end
end
```

**Workflow:**
1. **Query Interpreter (ReAct)** refines user query
2. **Planner (ReAct)** generates search strategy
3. **Research Strategist (HTN)** decomposes into parallel searches
4. **Reader Agents (BT)** execute file reading with retries
5. **Pattern Analyzer (ReAct)** identifies common patterns
6. **Synthesizer (ReAct)** creates markdown report
7. **Breakdown Generator (HTN)** creates step-by-step implementation plan

---

### 3. Software Delivery Squad

**Goal:** Design, implement, test, deploy features

**Team Composition:**
```
Release Manager (HTN)
├── Design Analyst (ReAct) - Architectural exploration
├── Code Writer (BT + ReAct hybrid)
│   ├── Uses BT for execution flow
│   └── Embeds ReAct for complex decisions
├── Test Runner (BT) - Continuous testing
├── QA Monitor (BT) - Regression detection
├── Deploy Operator (BT) - Deployment with rollback
└── Postmortem Writer (ReAct) - Documents lessons learned
```

**Workflow with all three engines:**
```elixir
# Release Manager (HTN) plans
plan = [
  {:design, %{constraint: :performance}},
  {:implement, %{approach: :incremental}},
  {:validate, %{coverage: 0.8}},
  {:deploy, %{strategy: :canary}}
]

# Design Analyst (ReAct) explores
"Given performance constraint, explore architectures..."
→ Proposes 3 options with trade-offs
→ Team reviews and selects

# Code Writer (BT + ReAct)
BT:
  Sequence
    → ReAct (decide on implementation approach)
    → Action (write code)
    → Action (run tests)
    → Selector (if tests fail)
        → ReAct (debug and fix)
        → Alert (if stuck)

# QA Monitor (BT) continuously monitors
Parallel
  → RunTestSuite (repeated)
  → CheckCoverage (repeated)
  → DetectRegression → Alert

# Deploy Operator (BT) robust deployment
Selector
  → Sequence (canary deploy)
      → DeployToCanary
      → MonitorMetrics (with timeout)
      → Condition (metrics_healthy?)
      → DeployToFull
  → Sequence (rollback)
      → Alert
      → Rollback
```

---

## Signal Protocols

### Core Signal Types

Define a **minimal, typed message vocabulary** for coordination:

```elixir
defmodule Jido.Capabilities.Signals do
  @moduledoc "Standard signal types for multi-agent coordination"
  
  # Hierarchical signals
  @intent "capability.intent"           # Top-down: "Achieve this goal"
  @proposal "capability.proposal"       # Bottom-up: "Here's my approach"
  @commitment "capability.commitment"   # Acceptance: "I'll do it this way"
  @status "capability.status"           # Progress: "Here's where I'm at"
  @alert "capability.alert"             # Urgent: "Critical issue"
  @cancel "capability.cancel"           # Abort: "Stop this work"
  
  # Peer-to-peer signals
  @query "capability.query"             # Ask: "Need input on X"
  @reply "capability.reply"             # Answer: "Here's my response"
  @vote "capability.vote"               # Opinion: "I support/object"
  @handoff "capability.handoff"         # Transfer: "You handle this"
  
  # Schemas for each signal type
  defmodule Intent do
    @schema Zoi.struct(__MODULE__, %{
      task_id: Zoi.string(),
      goal: Zoi.string(),
      constraints: Zoi.map() |> Zoi.default(%{}),
      priority: Zoi.integer() |> Zoi.min(1) |> Zoi.max(10) |> Zoi.default(5),
      deadline: Zoi.any() |> Zoi.optional(),
      requester: Zoi.string()
    })
  end
  
  defmodule Proposal do
    @schema Zoi.struct(__MODULE__, %{
      task_id: Zoi.string(),
      approach: Zoi.string(),
      estimated_cost: Zoi.number() |> Zoi.optional(),
      confidence: Zoi.float() |> Zoi.min(0.0) |> Zoi.max(1.0),
      dependencies: Zoi.list(Zoi.string()) |> Zoi.default([]),
      risks: Zoi.list(Zoi.string()) |> Zoi.default([])
    })
  end
  
  defmodule Status do
    @schema Zoi.struct(__MODULE__, %{
      task_id: Zoi.string(),
      state: Zoi.enum([:pending, :in_progress, :blocked, :done, :failed]),
      progress: Zoi.float() |> Zoi.min(0.0) |> Zoi.max(1.0),
      blockers: Zoi.list(Zoi.string()) |> Zoi.default([]),
      confidence: Zoi.float() |> Zoi.min(0.0) |> Zoi.max(1.0) |> Zoi.optional()
    })
  end
  
  defmodule Alert do
    @schema Zoi.struct(__MODULE__, %{
      task_id: Zoi.string(),
      severity: Zoi.enum([:info, :warning, :critical, :help_needed]),
      description: Zoi.string(),
      recommendation: Zoi.string() |> Zoi.optional(),
      context: Zoi.map() |> Zoi.default(%{})
    })
  end
end
```

### Signal Flow Patterns

**Pattern 1: Hierarchical Command Flow**
```
Mission Owner → intent → Specialist
Specialist → proposal → Mission Owner
Mission Owner → commitment → Specialist
Specialist → status (periodic) → Mission Owner
Specialist → alert (on issues) → Mission Owner
Mission Owner → cancel (if needed) → Specialist
```

**Pattern 2: Peer Negotiation Flow**
```
Peer A → query → Peer B
Peer B → reply → Peer A

or

Peer A → proposal → [All Peers]
Peer B → vote (endorse) → [All Peers]
Peer C → vote (object) → [All Peers]
Facilitator → commitment (resolve) → [All Peers]
```

**Pattern 3: Cross-Squad Handoff**
```
Squad A Agent → handoff → Liaison
Liaison → intent → Squad B Lead
Squad B Lead → proposal → Liaison
Liaison → commitment → Squad B Lead
Squad B → status → Liaison → Squad A
Squad B → done → Liaison → Squad A
```

---

## Capability Architecture

### Anatomy of a Capability Team

```
MyCapability/
├── Public API
│   └── MyCapability.start(jido, opts) → coordinator_pid
│
├── Team Definition
│   ├── team_config.ex - Agent roles, workflow engines
│   └── signal_protocol.ex - Signal schemas and routing
│
├── Mission Owner (if hierarchical)
│   ├── mission_owner_agent.ex - HTN/ReAct coordinator
│   └── domain.ex - HTN domain definition
│
├── Specialist Agents
│   ├── analyst_agent.ex - ReAct for reasoning
│   ├── operator_agent.ex - BT for execution
│   ├── monitor_agent.ex - BT for watching
│   └── synthesizer_agent.ex - ReAct for combining
│
└── Tools (shared)
    ├── domain_tool_1.ex
    ├── domain_tool_2.ex
    └── ...
```

### Example: GTD Capability

```
lib/jido_gtd/
├── jido_gtd.ex                        # Public API
├── team_config.ex                      # Team roles and engines
├── signals.ex                          # Signal protocol
├── mission_owner.ex                    # HTN planner
├── domain/
│   └── gtd_domain.ex                   # HTN domain
├── agents/
│   ├── capture_agent.ex                # BT monitor
│   ├── clarifier_agent.ex              # ReAct
│   ├── organizer_agent.ex              # ReAct
│   ├── planner_agent.ex                # HTN
│   ├── review_agent.ex                 # ReAct
│   └── executor_agent.ex               # BT
└── tools/
    ├── parse_task.ex
    ├── tag_context.ex
    ├── categorize.ex
    └── break_down_project.ex
```

---

## Organization Strategies

### Strategy 1: Monorepo with Capability Packages

```
jido_workspace/
├── projects/
│   ├── jido/                  # Core framework
│   ├── jido_ai/               # ReAct strategy
│   ├── jido_behaviortree/     # BT engine
│   ├── jido_htn/              # HTN engine
│   ├── jido_capabilities/     # Shared infrastructure
│   │   ├── team.ex            # Team behavior
│   │   ├── signals.ex         # Standard signals
│   │   └── coordinator.ex     # Coordinator helpers
│   ├── jido_gtd/              # GTD capability
│   ├── jido_code_research/    # Research capability
│   └── jido_delivery/         # Software delivery capability
```

**Benefits:**
- Clear package boundaries
- Each capability independently versionable
- Shared infrastructure via `jido_capabilities`

---

### Strategy 2: Capability Registry

```elixir
defmodule Jido.Capabilities.Registry do
  @moduledoc "Central registry of available capabilities"
  
  def register(name, module, metadata) do
    # Register capability with:
    # - Supported intents
    # - Required resources
    # - Team composition
    # - Signal protocol
  end
  
  def discover(intent_type) do
    # Find capabilities that can handle this intent
  end
  
  def spawn_team(capability, jido_instance, opts) do
    # Start a capability team
  end
end

# Each capability registers on app start
defmodule JidoGTD.Application do
  def start(_type, _args) do
    Jido.Capabilities.Registry.register(
      :gtd,
      JidoGTD,
      %{
        intents: ["gtd.task.create", "gtd.project.create"],
        description: "Getting Things Done task management",
        team_size: {:dynamic, 3..7},
        engines: [:htn, :react, :bt]
      }
    )
  end
end
```

---

## Implementation Roadmap

### Phase 1: Prove Multi-Agent Team Pattern (1-2 weeks)

**Goal:** Validate HTN + ReAct + BT team working together

**Tasks:**
1. Build simple GTD team:
   - HTN mission planner
   - ReAct clarifier
   - BT executor
2. Define signal protocol
3. Test intent → planning → execution → status flow
4. Validate replanning on failure

**Deliverable:** Working 3-agent GTD team demo

---

### Phase 2: Generalize to Framework (2-3 weeks)

**Goal:** Reusable patterns for any capability

**Tasks:**
1. Extract `Jido.Capabilities` shared infrastructure
2. Define standard signal schemas
3. Create team composition helpers
4. Build second capability (code research) using patterns
5. Document team patterns

**Deliverable:** Framework + 2 working capabilities

---

### Phase 3: Advanced Coordination (3-4 weeks)

**Goal:** Peer negotiation, cross-squad liaison, dynamic teams

**Tasks:**
1. Implement peer negotiation protocol
2. Add cross-squad liaison agents
3. Dynamic team sizing (spawn readers based on workload)
4. Capability composition (GTD uses research capability)
5. Monitoring and observability

**Deliverable:** Production-ready multi-capability system

---

### Phase 4: Meta-Capabilities (4-6 weeks)

**Goal:** Capabilities that manage other capabilities

**Tasks:**
1. Project orchestrator (manages multiple squads)
2. Resource manager (allocates agents across missions)
3. Learning/tuning (adjusts HTN methods, BT parameters)
4. Policy enforcement (checks proposals against norms)

**Deliverable:** Advanced multi-mission orchestration

---

## Advanced Patterns

### Pattern: Adaptive Team Sizing

```elixir
defmodule Research.Strategist do
  def handle_signal(agent, %Signal{type: "research.plan_ready", data: data}) do
    # Dynamically spawn readers based on file count
    file_count = length(data.files_to_analyze)
    reader_count = min(div(file_count, 5) + 1, 10)  # 1 per 5 files, max 10
    
    spawn_directives = for i <- 1..reader_count do
      Directive.spawn_agent(Research.ReaderAgent, :"reader_#{i}")
    end
    
    {agent, spawn_directives}
  end
end
```

---

### Pattern: Workflow Composition (ReAct → HTN → BT chain)

```elixir
# 1. ReAct agent analyzes problem, proposes HTN domain
ReAct → Generates HTN methods for specific problem

# 2. HTN agent plans using generated domain
HTN → Decomposes with custom methods → Emits subtasks

# 3. BT agents execute subtasks robustly
BT → Executes with retries, fallbacks, monitoring

# Result: Adaptive planning + robust execution
```

---

### Pattern: Fault-Tolerant Squad

```elixir
defmodule Squad.FaultTolerant do
  # Each agent has backup
  @agents [
    {AnalystAgent, backup: true, min: 1, max: 2},
    {OperatorAgent, backup: true, min: 2, max: 4},
    {MonitorAgent, backup: false, min: 1, max: 1}
  ]
  
  def handle_signal(agent, %Signal{type: "jido.agent.child.exited", data: data}) do
    # Agent crashed, spawn replacement
    role = data.role
    config = get_role_config(role)
    
    if active_count(role) < config.min do
      {agent, [spawn_replacement(role)]}
    else
      {agent, []}
    end
  end
end
```

---

### Pattern: Capability-as-Tool

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
    {:ok, pid} = Jido.Capabilities.spawn_team(:code_research, params.jido_instance)
    
    # Send intent
    signal = Signal.new!("research.intent", %{query: params.query})
    Jido.cast(params.jido_instance, pid, signal)
    
    # Track research worker
    {:ok, %{research_worker_id: inspect(pid)}}
  end
end

# Now GTD planner can use research as a tool!
# ReAct: "I need to research codebase X to clarify this task"
# → Calls delegate_research tool
# → Research team spins up, does work, returns findings
# → GTD continues with enriched context
```

---

## Conclusion

**Core Principles:**
1. **Match engines to roles**: HTN (strategy), BT (tactics), ReAct (reasoning)
2. **Distribute intelligence**: Autonomous agents, not dumb workers
3. **Persist via Ash**: Domain actions as tools, resources as world model
4. **Compose workflows**: Hybrid strategies multiply power
5. **Signal protocols**: Simple vocabulary enables rich coordination
6. **Team diversity**: Mix engines for complementary strengths

**Capability = Team of Specialized Agents + Ash Domain**
- Not a monolithic agent with complex FSM
- Not a coordinator with simple puppets
- Not ephemeral in-memory state
- **A persistent, domain-driven team where each member is intelligent and autonomous**

**The Stack:**
```
Multi-Agent Teams (HTN/BT/ReAct)
         ↓
   Jido Actions (via ash_jido)
         ↓
    Ash Domains & Resources
         ↓
   PostgreSQL/Ecto
```

**Next Steps:**
1. Build GTD proof-of-concept:
   - Define Ash domain (Task, Project, Context, InboxItem)
   - HTN mission planner + ReAct clarifier + BT executor
   - Agent runs and events persisted
2. Extract patterns into `Jido.Capabilities` framework
3. Add code research capability with persistence
4. Explore advanced coordination (peer negotiation, squads, composition)

**The Future:**
- **Persistent capabilities**: Agents resume after crashes
- **Event-sourced workflows**: Full audit trail of decisions
- **Cross-team collaboration**: Shared Ash resources
- **Policy-driven autonomy**: Fine-grained agent permissions
- **Multi-tenant teams**: Workspace isolation built-in
- **Capabilities that spawn other capabilities**
- **Agents that learn and adapt team composition**
- **Meta-agents that tune workflow parameters**
- **Rich multi-capability orchestration for complex projects**

**Jido's Power Triangle:**
```
Multi-Agent Teams
       +
Workflow Engines (HTN/BT/ReAct)
       +
Ash Framework (Persistence/Domain/Policies)
       =
Unprecedented capability for building sophisticated,
persistent, collaborative autonomous systems
```

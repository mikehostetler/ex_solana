# Agent Jido Website Sitemap & Content Outline

**Site:** https://agentjido.xyz  
**Purpose:** Production-focused landing site for BEAM-native multi-agent framework  
**Audience:** Elixir/OTP developers + multi-agent engineers from other ecosystems  
**Voice:** Production-hardened pragmatist, code-first, evidence-driven

---

## Site Structure

### Primary Navigation

```
/                    → Home (landing)
/ecosystem           → Package landscape & how pieces fit together
/getting-started     → Quick start guide
/examples            → Production examples with numbers
/docs                → Hub linking to HexDocs, GitHub, Livebooks
/benchmarks          → Benchmarks & proof
/community           → Support & resources (or section on Home initially)
```

### Package-Specific Landing Pages

```
/packages/llmdb         → LLMDB package landing
/packages/req-llm       → ReqLLM package landing
/packages/jido          → Jido core package landing
/packages/jido-action   → jido_action package landing
/packages/jido-signal   → jido_signal package landing
/packages/jido-ai       → JidoAI package landing
/packages/jido-coder    → Jido Coder package landing
```

### Footer

- Hex package badge + link
- HexDocs main page
- GitHub repository
- YouTube channel
- Issue tracker
- License & current version

---

## Navigation Structure

**Top-level pages** are globally accessible via main nav.  
**Package pages** are accessible from `/ecosystem` via cards/links and direct URL.

---

## Page-by-Page Breakdown

### 1. Home (`/`)

**Goal:** Prove in 10–30 seconds that Jido is serious, production-ready, and give both personas a clear next click.

#### Above the Fold

**Hero Heading** (constraint-first):
```
"Most agent frameworks assume infinite CPU and RAM. 
Jido runs 10,000 supervised agents on a single BEAM node."
```

**Subheadline** (ties to BEAM/OTP):
```
"Built on OTP supervision and isolated processes, 
not external queues and YAML orchestration."
```

**Primary CTAs:**
- Button 1: "Read Getting Started" → `/getting-started`
- Button 2: "Open on HexDocs" → HexDocs main page

**Code Snippet** (visible without scrolling, ≈10–20 lines):
```elixir
defmodule WeatherAgent do
  use Jido.Agent

  def init(_args) do
    {:ok, %{location: "Austin", temp: nil}}
  end

  def handle_action(:check_weather, state) do
    # Agent logic here
    {:ok, state}
  end
end

# Start 5,000 supervised agents
{:ok, supervisor} = Jido.Supervisor.start_link()
for i <- 1..5_000 do
  Jido.Supervisor.start_agent(supervisor, WeatherAgent, id: i)
end
```
_Caption: "This starts 5,000 supervised agents in a single node."_

**Metric Strip** (horizontal):
- `10,000+ agents / node`
- `~200MB RAM @ 5,000 agents`
- `< 1ms intra-node message latency`
- `Zero external queue for intra-node communication`

_Small text: "Measured on 2-core, 4GB VM. See [/benchmarks](#benchmarks) for details."_

**Checklist:**
- [x] Constraint in first sentence
- [x] Code snippet visible without scrolling
- [x] At least one concrete metric
- [x] No hype adjectives without evidence

---

#### Below the Fold – Sections

**Section 1: Why BEAM-native agents?** (dual personas)

Opening constraint:
> "Threads, workers, and queues handle load—until you need thousands of autonomous agents with per-process state and predictable failure behavior."

**Two-column layout:**

| For Elixir/OTP Engineers | For Backend Engineers from Other Ecosystems |
|-------------------------|---------------------------------------------|
| • Jido composes with your existing supervision trees<br>• Each agent is a BEAM process with its own mailbox<br>• Use standard tools: `Observer`, `Telemetry`, `Logger` | • Instead of thread pools, Jido agents are isolated BEAM processes<br>• Instead of shared-memory locks, each agent owns its state<br>• Where you'd reach for Kafka/Redis, here you use message-passing |

**Visual elements:**
- Code snippet: Jido integrated into existing OTP app supervision tree
- Diagram: threads/queues vs BEAM processes/mailboxes

---

**Section 2: Architecture Snapshot**

One-paragraph summary:
> "Each Jido agent is a lightweight BEAM process managed under OTP supervision. Supervisors define how agents start, restart, and scale across distributed nodes."

**Supervision tree diagram:**
```
Jido.Supervisor
├── AgentSupervisor
│   ├── AgentProcess (× N)
│   └── AgentProcess (× N)
└── ToolSupervisor (optional)
```

**Code excerpt:** Wiring Jido into app's top-level supervisor

**Link:** "See package ecosystem → [/ecosystem](#ecosystem)"

---

**Section 3: Production Properties**

Heading: **"Built for production, not just prototypes."**

**Resilience:**
- Per-agent crash isolation via OTP supervisors
- Millisecond restarts without affecting healthy agents

**Load & Concurrency:**
- Run thousands of agents per node using BEAM's preemptive scheduler
- True parallelism on multi-core hosts

**Observability:**
- Per-agent metrics and traces via standard Elixir telemetry
- Inspect agent state and mailboxes with existing tools

**Failure scenario callouts:**
- "Node dies mid-deploy → supervisors restart agents on the new node"
- "Agent code crashes → supervisor applies backoff and restart strategy"

---

**Section 4: Examples Preview**

**Card list** (3–4 concrete examples):

1. **Tool-using research agent swarm**
   - Scenario: Multi-agent research coordination with LLM calls
   - Metrics: 1,000 agents, 150ms avg latency, $0.05/query
   - Links: [Livebook] [GitHub] [YouTube Demo]

2. **Workflow orchestrator with 2,000 long-lived agents**
   - Scenario: Persistent agent processes managing user workflows
   - Metrics: 2,000 agents, 180MB RAM, 4-core node
   - Links: [Livebook] [GitHub] [YouTube Demo]

3. **Streaming log classifier agents**
   - Scenario: Real-time log processing and classification
   - Metrics: 5,000 agents, 10k msgs/sec throughput
   - Links: [Livebook] [GitHub] [YouTube Demo]

**Link:** "See all examples → [/examples](#examples)"

---

**Section 5: Social Proof + Numbers**

- GitHub stats: Stars, version, last release date (factual, no spin)
- Early adopters: "Used in production at…" (if available)
- YouTube embed: Main video – "Running 10,000 agents on a single node" with CPU/memory graphs
- Link: "See benchmark details → [/benchmarks](#benchmarks)"

---

### 2. Ecosystem & Package Landscape (`/ecosystem`)

**Goal:** Show experienced Elixir developers how the Jido ecosystem packages compose together.

**Audience:** Primarily Persona 1 (experienced Elixir/OTP developers) who understand BEAM but need to see the package dependencies and use cases.

**Hero / Intro:**

Opening constraint:
> "Most agent frameworks are monoliths. Jido is a composable ecosystem—use the full stack or pick the packages you need."

**Subheadline:**
> "Foundation packages for LLM handling, core bot framework for autonomy, and specialized packages for AI and coding workflows."

---

#### Above the Fold – Package Landscape Diagram

**Visual: Dependency graph showing package relationships**

```
Foundation Layer:
┌─────────┐      ┌──────────┐
│ LLMDB   │─────▶│ ReqLLM   │
└─────────┘      └──────────┘
     │                │
     │                │
     └────────┬───────┘
              ▼
Core Layer:
┌─────────────────────────────┐
│         Jido                │
│    (Bot Framework)          │
├─────────────────────────────┤
│  jido_action │ jido_signal  │
└─────────────────────────────┘
              │
              ▼
AI Layer:
┌─────────────────────────────┐
│        JidoAI               │
│  (Jido + ReqLLM)            │
└─────────────────────────────┘
              │
              ▼
Application Layer:
┌─────────────────────────────┐
│      Jido Coder             │
│  (AI-powered coding agent)  │
└─────────────────────────────┘
```

**Code snippet – Dependency example:**
```elixir
# Using the full AI stack
def deps do
  [
    {:jido_ai, "~> 0.1.0"}  # Brings in jido, req_llm, llmdb
  ]
end

# Or compose your own
def deps do
  [
    {:jido, "~> 0.1.0"},          # Core bot framework
    {:jido_action, "~> 0.1.0"},   # Action primitives
    {:req_llm, "~> 0.1.0"}        # LLM client (if you need LLMs)
  ]
end
```

---

#### Content Sections

**1. Foundation Layer: LLM Infrastructure**

**LLMDB** [`hex`](#) [`docs`](#) [`github`](#)
- **What it does:** Model registry and metadata
- **Feeds into:** ReqLLM for model selection and routing
- **Use when:** You need to manage multiple LLM providers/models
- **Code example:**
  ```elixir
  # Register models
  LLMDB.register(:openai, "gpt-4", %{
    max_tokens: 128_000,
    cost_per_token: 0.00003
  })
  ```

**ReqLLM** [`hex`](#) [`docs`](#) [`github`](#)
- **What it does:** HTTP client for LLM APIs (OpenAI, Anthropic, etc.)
- **Built on:** `Req` library
- **Consumes:** LLMDB model metadata
- **Use when:** You need to make LLM API calls with proper rate limiting, retries, streaming
- **Code example:**
  ```elixir
  # Make an LLM request
  ReqLLM.chat(:openai, "gpt-4", messages: [
    %{role: "user", content: "Explain BEAM processes"}
  ])
  ```

**Dependency:**
```
LLMDB → ReqLLM
```

---

**2. Core Layer: Bot Framework**

**Jido** [`hex`](#) [`docs`](#) [`github`](#)
- **What it is:** BEAM-native autonomous agent/bot framework
- **Built on:** OTP supervision, GenServer patterns, isolated processes
- **Use when:** You need autonomous agents (with or without AI/LLMs)
- **Key concepts:**
  - Each agent is a supervised BEAM process
  - Agents have state, behaviors, and lifecycle
  - Can run thousands per node
- **Code example:**
  ```elixir
  defmodule WeatherBot do
    use Jido.Agent
    
    def init(args), do: {:ok, %{location: args[:location]}}
    
    def handle_action(:check, state) do
      # Bot logic here
      {:ok, state}
    end
  end
  ```

**jido_action** [`hex`](#) [`docs`](#) [`github`](#)
- **What it does:** Action primitives and validation
- **Used by:** Jido core for validated, composable actions
- **Use when:** You need structured action handling with constraints
- **Code example:**
  ```elixir
  defmodule CheckWeather do
    use Jido.Action
    
    schema do
      field :location, :string, required: true
      field :units, :string, default: "metric"
    end
    
    def run(params, _context) do
      # Validated action logic
    end
  end
  ```

**jido_signal** [`hex`](#) [`docs`](#) [`github`](#)
- **What it does:** Signal/event handling between agents
- **Used by:** Jido core for inter-agent communication
- **Use when:** Agents need to react to events or coordinate
- **Code example:**
  ```elixir
  # Agent emits signal
  Jido.Signal.emit(:weather_updated, %{temp: 72})
  
  # Other agents subscribe
  Jido.Signal.subscribe(:weather_updated, handler: &handle_update/1)
  ```

**Dependency:**
```
jido_action ─┐
             ├─→ Jido
jido_signal ─┘
```

---

**3. AI Layer: LLM-Powered Agents**

**JidoAI** [`hex`](#) [`docs`](#) [`github`](#)
- **What it does:** Brings together Jido bot framework + ReqLLM + LLMDB
- **Built on:** Jido core + ReqLLM
- **Use when:** You need AI agents that make LLM calls with full bot lifecycle
- **Key features:**
  - LLM-aware agent behaviors
  - Token/cost tracking per agent
  - Tool/function calling support
  - Streaming response handling
- **Code example:**
  ```elixir
  defmodule ResearchAgent do
    use JidoAI.Agent
    
    # Agent with LLM capabilities
    def init(args) do
      {:ok, %{
        model: :openai/"gpt-4",
        budget: 1000,  # max tokens
        research_topic: args[:topic]
      }}
    end
    
    def handle_research(topic, state) do
      # Agent makes LLM calls via ReqLLM
      # Uses LLMDB for model metadata
      # Tracks token usage against budget
    end
  end
  ```

**Dependency:**
```
Jido ─┐
      ├─→ JidoAI
ReqLLM ─┘
```

---

**4. Application Layer: Specialized Agents**

**Jido Coder** [`hex`](#) [`docs`](#) [`github`](#)
- **What it does:** AI-powered coding agent built on JidoAI
- **Built on:** JidoAI (which includes Jido + ReqLLM + LLMDB)
- **Use when:** You need agents that can read/write/analyze code
- **Key features:**
  - Code analysis actions
  - File system operations
  - Git integration
  - Multi-step coding workflows
  - Built-in tools for common coding tasks
- **Code example:**
  ```elixir
  # Start a coding agent
  {:ok, agent} = JidoCoder.start_agent(
    task: "refactor authentication module",
    codebase_path: "/path/to/project",
    model: :anthropic/"claude-3-opus"
  )
  
  # Agent can:
  # - Read files
  # - Analyze code structure
  # - Make LLM-guided decisions
  # - Write/modify files
  # - Run tests
  ```

**Dependency:**
```
JidoAI → Jido Coder
```

---

#### Full Dependency Graph

**Bottom-up view:**

```
Layer 4: Applications
         ┌─────────────┐
         │ Jido Coder  │
         └──────┬──────┘
                │
Layer 3: AI     │
         ┌──────▼──────┐
         │   JidoAI    │
         └──┬───────┬──┘
            │       │
Layer 2:    │       │
Core    ┌───▼───┐   │
        │ Jido  │   │
        │ ┌─────┴───▼────┐
        │ │ jido_action  │
        │ │ jido_signal  │
        │ └──────────────┘
        │       │
Layer 1:│   ┌───▼────┐
Foundation  │ReqLLM  │
        │   └───┬────┘
        │       │
        │   ┌───▼────┐
        └───│ LLMDB  │
            └────────┘
```

---

#### Package Decision Tree

**"Which packages do I need?"**

```
START: What are you building?

┌─────────────────────────────────────┐
│ Do you need LLM/AI capabilities?    │
└─────────────┬───────────────────────┘
              │
      ┌───────┴────────┐
      NO              YES
      │                │
      ▼                ▼
┌──────────────┐  ┌──────────────────────┐
│ Just bots?   │  │ AI agents or coding? │
└──────┬───────┘  └──────┬───────────────┘
       │                 │
       ▼          ┌──────┴──────┐
   ┌──────┐       │             │
   │ Jido │    Coding        AI Agents
   └──────┘       │             │
                  ▼             ▼
            ┌─────────────┐ ┌─────────┐
            │ Jido Coder  │ │ JidoAI  │
            └─────────────┘ └─────────┘
```

**Recommendation table:**

| Use Case | Install | Why |
|----------|---------|-----|
| Autonomous bots (no AI) | `jido` | Core framework only, minimal deps |
| Custom LLM integration | `jido` + `req_llm` | Bot framework + LLM client |
| AI-powered agents | `jido_ai` | Integrated Jido + LLM handling |
| Code analysis/generation agents | `jido_coder` | Specialized for coding workflows |
| Just LLM API calls (no agents) | `req_llm` + `llmdb` | Foundation layer only |

---

#### Composability Examples

**Example 1: Start with core, add AI later**

```elixir
# Phase 1: Just bots
def deps do
  [{:jido, "~> 0.1.0"}]
end

# Phase 2: Add LLM capabilities
def deps do
  [
    {:jido, "~> 0.1.0"},
    {:req_llm, "~> 0.1.0"}
  ]
end

# Phase 3: Use integrated AI layer
def deps do
  [{:jido_ai, "~> 0.1.0"}]  # Replaces jido + req_llm
end
```

**Example 2: Mix and match**

```elixir
# Custom setup: Jido bots + your own LLM client
def deps do
  [
    {:jido, "~> 0.1.0"},
    {:your_llm_client, "~> 1.0"}
  ]
end

# Your bot uses your client
defmodule CustomAIBot do
  use Jido.Agent
  
  def handle_action(:think, state) do
    # Use your own LLM integration
    YourLLMClient.complete(...)
  end
end
```

**Example 3: Foundation layer standalone**

```elixir
# Just need LLM API handling (no bots)
def deps do
  [
    {:req_llm, "~> 0.1.0"},
    {:llmdb, "~> 0.1.0"}
  ]
end

# Use in GenServer, Phoenix, etc.
defmodule MyService do
  use GenServer
  
  def handle_call(:analyze, _from, state) do
    result = ReqLLM.chat(:openai, "gpt-4", ...)
    {:reply, result, state}
  end
end
```

---

#### Per-Package Quick Reference

**Quick links table:**

| Package | Hex | HexDocs | GitHub | Primary Use |
|---------|-----|---------|--------|-------------|
| **LLMDB** | [hex](#) | [docs](#) | [repo](#) | Model registry |
| **ReqLLM** | [hex](#) | [docs](#) | [repo](#) | LLM API client |
| **Jido** | [hex](#) | [docs](#) | [repo](#) | Bot framework |
| **jido_action** | [hex](#) | [docs](#) | [repo](#) | Action primitives |
| **jido_signal** | [hex](#) | [docs](#) | [repo](#) | Event/signal handling |
| **JidoAI** | [hex](#) | [docs](#) | [repo](#) | AI-powered agents |
| **Jido Coder** | [hex](#) | [docs](#) | [repo](#) | Coding agents |

---

#### Production Notes

**Supervision strategy:**
- All packages designed to work under OTP supervision
- Each agent (regardless of AI capabilities) is a supervised process
- Package composition doesn't change supervision patterns

**Failure isolation:**
- ReqLLM failures (API errors, timeouts) isolated to calling agent
- LLMDB is stateless, no crash risk
- Jido supervisor handles agent crashes regardless of whether they use LLMs

**Observability:**
- All packages emit telemetry events
- Use standard Elixir tooling (`:observer`, `Telemetria`, etc.)
- JidoAI adds LLM-specific metrics (token usage, API latency, cost tracking)

**Deployment:**
- Install only what you need—no forced dependencies
- Mix.exs handles transitive deps (e.g., `jido_ai` pulls in `jido`, `req_llm`, `llmdb`)
- All packages on Hex with semantic versioning

---

#### Migration Paths

**"I'm already using Jido, how do I add AI?"**

```elixir
# Before (just Jido)
defmodule MyBot do
  use Jido.Agent
  # ... your bot logic
end

# After (add JidoAI capabilities)
defmodule MyBot do
  use JidoAI.Agent  # Drop-in replacement
  # ... same logic, now with LLM access
end

# Update deps
# {:jido, "~> 0.1.0"}  # Remove
{:jido_ai, "~> 0.1.0"}  # Add (includes Jido)
```

**"I'm using ReqLLM standalone, want agents"**

```elixir
# Before (ReqLLM in GenServer)
defmodule MyService do
  use GenServer
  def handle_call(:llm_call, _from, state) do
    ReqLLM.chat(...)
  end
end

# After (as Jido agent)
defmodule MyService do
  use JidoAI.Agent
  # Supervised process with LLM access
end
```

---

#### When NOT to Use the Full Stack

**Use case-specific guidance:**

- **Don't need agents?** → Just use `req_llm` + `llmdb`
- **Don't need LLMs?** → Just use `jido`
- **Need custom LLM integration?** → Use `jido` + your client
- **Building something other than coding agents?** → Use `jido_ai`, skip `jido_coder`

**The ecosystem is composable by design—use what you need, skip what you don't.**

---

## Package Landing Pages

_Each package gets its own focused landing page accessible from `/ecosystem` and direct URLs._

---

### P1. LLMDB (`/packages/llmdb`)

**Goal:** Show what LLMDB does and when to use it (model registry for LLM metadata).

**Audience:** Elixir developers who need to manage multiple LLM providers/models.

**Hero / Intro:**

Opening constraint:
> "Every LLM provider has different token limits, pricing, and capabilities. LLMDB is a registry so your code doesn't hardcode model metadata."

**Subheadline:**
> "Model registry and metadata management for multi-provider LLM applications."

**Primary CTAs:**
- "View on Hex" → Hex package
- "Read HexDocs" → HexDocs
- "See on GitHub" → GitHub repo

---

#### Above the Fold

**Code snippet:**
```elixir
# Register models with metadata
LLMDB.register(:openai, "gpt-4", %{
  max_tokens: 128_000,
  cost_per_1k_tokens: %{input: 0.03, output: 0.06},
  capabilities: [:chat, :function_calling, :vision]
})

LLMDB.register(:anthropic, "claude-3-opus", %{
  max_tokens: 200_000,
  cost_per_1k_tokens: %{input: 0.015, output: 0.075},
  capabilities: [:chat, :function_calling]
})

# Query model metadata
{:ok, model} = LLMDB.get(:openai, "gpt-4")
model.max_tokens  # => 128_000
```

**Metric strip:**
- "Supports all major providers (OpenAI, Anthropic, Google, etc.)"
- "Zero API calls—metadata is local"
- "Version-tracked model registry"

---

#### Content Sections

**1. What LLMDB Does**

- Centralized model registry with metadata (token limits, pricing, capabilities)
- No API calls—all data is local
- Used by ReqLLM and JidoAI for model selection and routing
- Supports custom model registration

**2. When to Use It**

- You support multiple LLM providers
- You need cost tracking across different models
- You build tools that switch models based on task requirements
- You want to avoid hardcoding model limits in your application code

**3. Key Features**

- Model metadata: max tokens, pricing, capabilities
- Provider registry: OpenAI, Anthropic, Google, custom providers
- Version tracking: models evolve, LLMDB tracks changes
- ETS-backed for fast lookups

**4. Integration Example**

```elixir
# Use with ReqLLM
model = LLMDB.get!(:openai, "gpt-4")

if tokens_needed > model.max_tokens do
  # Switch to a model with higher limits
  model = LLMDB.get!(:anthropic, "claude-3-opus")
end

ReqLLM.chat(model, messages: [...])
```

**5. Installation & Docs**

- **Hex:** `{:llmdb, "~> 0.1.0"}`
- **HexDocs:** [Link to full API docs]
- **GitHub:** [Link to repo]

**6. Related Packages**

- **ReqLLM** (uses LLMDB) → [/packages/req-llm](#)
- **JidoAI** (uses LLMDB + ReqLLM) → [/packages/jido-ai](#)

---

### P2. ReqLLM (`/packages/req-llm`)

**Goal:** Show what ReqLLM does (HTTP client for LLM APIs) and when to use it.

**Audience:** Elixir developers who need to call LLM APIs with proper handling.

**Hero / Intro:**

Opening constraint:
> "LLM APIs fail, rate-limit, and stream. ReqLLM handles retries, backoff, streaming, and provider differences so you don't write that logic again."

**Subheadline:**
> "HTTP client for LLM APIs built on Req with rate limiting, retries, and streaming support."

**Primary CTAs:**
- "View on Hex" → Hex package
- "Read HexDocs" → HexDocs
- "See on GitHub" → GitHub repo

---

#### Above the Fold

**Code snippet:**
```elixir
# Simple chat completion
{:ok, response} = ReqLLM.chat(:openai, "gpt-4", 
  messages: [
    %{role: "system", content: "You are a helpful assistant"},
    %{role: "user", content: "Explain BEAM processes"}
  ]
)

# Streaming response
ReqLLM.chat_stream(:anthropic, "claude-3-opus", 
  messages: [...],
  on_chunk: fn chunk -> IO.write(chunk.content) end
)

# With function calling
{:ok, response} = ReqLLM.chat(:openai, "gpt-4",
  messages: [...],
  tools: [
    %{type: "function", function: %{name: "get_weather", ...}}
  ]
)
```

**Metric strip:**
- "Built on Req library—battle-tested HTTP client"
- "Automatic retries with exponential backoff"
- "Streaming and function calling support"

---

#### Content Sections

**1. What ReqLLM Does**

- HTTP client specifically for LLM APIs (OpenAI, Anthropic, Google, etc.)
- Handles provider-specific request/response formats
- Automatic retry logic with backoff
- Streaming response support
- Function/tool calling support
- Consumes LLMDB for model metadata

**2. When to Use It**

- You need to make LLM API calls from Elixir
- You want proper error handling and retries
- You need streaming responses
- You support multiple LLM providers with different APIs
- You don't want to manage agents (just API calls)

**3. Key Features**

- **Multi-provider support:** OpenAI, Anthropic, Google, custom providers
- **Streaming:** Handle streaming responses with callbacks
- **Function calling:** Tool use / function calling support
- **Rate limiting:** Built-in rate limit handling
- **Retries:** Exponential backoff on failures
- **Type specs:** Full Dialyzer support

**4. Production Usage**

```elixir
# In a GenServer
defmodule AIService do
  use GenServer
  
  def handle_call({:complete, prompt}, _from, state) do
    case ReqLLM.chat(:openai, "gpt-4", messages: [prompt]) do
      {:ok, response} -> 
        {:reply, response.content, state}
      {:error, :rate_limited} ->
        # Handle rate limit
        {:reply, {:error, :try_again}, state}
      {:error, reason} ->
        # Log and handle
        {:reply, {:error, reason}, state}
    end
  end
end
```

**5. Installation & Docs**

- **Hex:** `{:req_llm, "~> 0.1.0"}`
- **HexDocs:** [Link to full API docs]
- **GitHub:** [Link to repo]

**6. Related Packages**

- **LLMDB** (provides model metadata) → [/packages/llmdb](#)
- **JidoAI** (agents + ReqLLM) → [/packages/jido-ai](#)

---

### P3. Jido Core (`/packages/jido`)

**Goal:** Show Jido as the core bot/agent framework (with or without AI).

**Audience:** Elixir developers building autonomous agents, bots, or multi-agent systems.

**Hero / Intro:**

Opening constraint:
> "Most agent frameworks assume you need AI. Jido is a bot framework first—add LLMs when you need them, or don't."

**Subheadline:**
> "BEAM-native autonomous agent framework built on OTP supervision and isolated processes."

**Primary CTAs:**
- "View on Hex" → Hex package
- "Read HexDocs" → HexDocs
- "See on GitHub" → GitHub repo
- "Get Started" → /getting-started

---

#### Above the Fold

**Code snippet:**
```elixir
defmodule WeatherBot do
  use Jido.Agent
  
  def init(args) do
    {:ok, %{location: args[:location], temp: nil}}
  end
  
  def handle_action(:check_weather, state) do
    # Fetch weather data
    temp = WeatherAPI.get_temp(state.location)
    {:ok, %{state | temp: temp}}
  end
  
  def handle_action(:report, state) do
    IO.puts("Temperature in #{state.location}: #{state.temp}°F")
    {:ok, state}
  end
end

# Start supervised agents
{:ok, supervisor} = Jido.Supervisor.start_link()
Jido.start_agent(supervisor, WeatherBot, location: "Austin")
```

**Metric strip:**
- "Run 10,000+ agents per node"
- "Each agent is a supervised BEAM process"
- "Built on OTP—no external orchestrator needed"

---

#### Content Sections

**1. What Jido Is**

- Bot/agent framework built on OTP supervision
- Each agent is an isolated BEAM process with its own state
- Agents have behaviors, actions, and lifecycle management
- Works with or without AI/LLMs
- Supports thousands of agents per node

**2. When to Use It**

- You need autonomous agents (bots, workers, event processors)
- You want OTP supervision for agent lifecycle
- You need thousands of concurrent agents on a single node
- You may or may not need AI/LLMs
- You want to compose agents with existing Elixir apps

**3. Core Concepts**

- **Agents:** Supervised processes with state and behaviors
- **Actions:** Composable, validated operations (via jido_action)
- **Signals:** Inter-agent communication (via jido_signal)
- **Supervision:** OTP supervisors manage agent lifecycle
- **Isolation:** Agent failures don't cascade

**4. Architecture**

Diagram: Supervision tree with multiple agents

```elixir
# Agents under supervision
children = [
  {DynamicSupervisor, name: MyAgentSupervisor, strategy: :one_for_one}
]

Supervisor.start_link(children, strategy: :one_for_one)

# Start many agents
for i <- 1..1_000 do
  spec = {WeatherBot, id: i, location: "City#{i}"}
  DynamicSupervisor.start_child(MyAgentSupervisor, spec)
end
```

**5. Production Features**

- Per-agent crash isolation
- Supervisor restart strategies
- Telemetry integration
- Observable with standard tools (Observer, telemetry)
- Distributed node support

**6. Installation & Docs**

- **Hex:** `{:jido, "~> 0.1.0"}`
- **HexDocs:** [Link to full API docs]
- **GitHub:** [Link to repo]
- **Getting Started:** [/getting-started](#)

**7. Related Packages**

- **jido_action** (action primitives) → [/packages/jido-action](#)
- **jido_signal** (signal handling) → [/packages/jido-signal](#)
- **JidoAI** (Jido + LLMs) → [/packages/jido-ai](#)

---

### P4. jido_action (`/packages/jido-action`)

**Goal:** Show jido_action as the action/validation layer.

**Audience:** Elixir developers using Jido who need structured, validated actions.

**Hero / Intro:**

Opening constraint:
> "Agent actions shouldn't silently fail with bad inputs. jido_action validates params, enforces constraints, and makes actions composable."

**Subheadline:**
> "Action primitives and validation for Jido agents."

**Primary CTAs:**
- "View on Hex" → Hex package
- "Read HexDocs" → HexDocs
- "See on GitHub" → GitHub repo

---

#### Above the Fold

**Code snippet:**
```elixir
defmodule FetchWeather do
  use Jido.Action
  
  schema do
    field :location, :string, required: true
    field :units, :string, default: "metric"
    field :api_key, :string, required: true
  end
  
  def run(%{location: loc, units: units, api_key: key}, _context) do
    # Validated inputs—location, units, api_key are guaranteed present
    case WeatherAPI.fetch(loc, units, key) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, reason}
    end
  end
end

# Use in agent
defmodule WeatherAgent do
  use Jido.Agent
  
  def handle_action(:fetch, state) do
    case FetchWeather.run(%{location: "Austin", api_key: state.api_key}) do
      {:ok, weather} -> {:ok, %{state | weather: weather}}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

**Metric strip:**
- "Schema-based validation"
- "Composable action primitives"
- "Type-safe with constraints"

---

#### Content Sections

**1. What jido_action Does**

- Schema-based validation for agent actions
- Required fields, defaults, type constraints
- Composable action definitions
- Used by Jido core for action handling
- Prevents silent failures from invalid inputs

**2. When to Use It**

- You build Jido agents with complex actions
- You need input validation before execution
- You want composable, reusable action modules
- You want to enforce constraints (string length, number ranges, etc.)

**3. Key Features**

- **Schema DSL:** Define required fields, defaults, types
- **Validation:** Automatic validation before action runs
- **Composability:** Actions as modules, easy to test and reuse
- **Error handling:** Clear validation errors vs runtime errors
- **Type specs:** Full Dialyzer support

**4. Installation & Docs**

- **Hex:** `{:jido_action, "~> 0.1.0"}`
- **HexDocs:** [Link to full API docs]
- **GitHub:** [Link to repo]

**5. Related Packages**

- **Jido** (uses jido_action) → [/packages/jido](#)

---

### P5. jido_signal (`/packages/jido-signal`)

**Goal:** Show jido_signal as the event/communication layer.

**Audience:** Elixir developers using Jido who need inter-agent communication.

**Hero / Intro:**

Opening constraint:
> "Agents need to react to events without tight coupling. jido_signal provides pub/sub signaling between agents."

**Subheadline:**
> "Signal and event handling for Jido agents."

**Primary CTAs:**
- "View on Hex" → Hex package
- "Read HexDocs" → HexDocs
- "See on GitHub" → GitHub repo

---

#### Above the Fold

**Code snippet:**
```elixir
# Agent emits signal
defmodule SensorAgent do
  use Jido.Agent
  
  def handle_action(:read_temp, state) do
    temp = read_sensor()
    
    # Emit signal to other agents
    Jido.Signal.emit(:temperature_updated, %{
      sensor_id: state.id,
      temp: temp,
      timestamp: DateTime.utc_now()
    })
    
    {:ok, %{state | last_temp: temp}}
  end
end

# Agent subscribes to signal
defmodule MonitorAgent do
  use Jido.Agent
  
  def init(args) do
    # Subscribe to temperature updates
    Jido.Signal.subscribe(:temperature_updated, handler: &handle_temp/1)
    {:ok, %{alerts: []}}
  end
  
  defp handle_temp(%{temp: temp} = data) when temp > 100 do
    # Alert on high temp
    Logger.warn("High temperature detected: #{temp}")
  end
  defp handle_temp(_), do: :ok
end
```

**Metric strip:**
- "Pub/sub pattern for agent communication"
- "Decoupled agent coordination"
- "Built on BEAM message-passing"

---

#### Content Sections

**1. What jido_signal Does**

- Pub/sub signal system for inter-agent communication
- Agents emit signals, other agents subscribe
- Decouples agents—no direct process references needed
- Used by Jido for agent coordination
- Built on BEAM's native message-passing

**2. When to Use It**

- Multiple agents need to react to the same event
- You want decoupled agent communication
- You build event-driven agent systems
- You need agents to coordinate without knowing about each other

**3. Key Features**

- **Pub/sub pattern:** Emit signals, subscribe to topics
- **Filtering:** Subscribe with pattern matching
- **Decoupling:** Agents don't need to know about each other
- **BEAM-native:** Uses process messaging, no external broker
- **Type-safe:** Signal payloads are Elixir terms

**4. Installation & Docs**

- **Hex:** `{:jido_signal, "~> 0.1.0"}`
- **HexDocs:** [Link to full API docs]
- **GitHub:** [Link to repo]

**5. Related Packages**

- **Jido** (uses jido_signal) → [/packages/jido](#)

---

### P6. JidoAI (`/packages/jido-ai`)

**Goal:** Show JidoAI as the integrated AI agent layer (Jido + ReqLLM + LLMDB).

**Audience:** Elixir developers building AI-powered agents.

**Hero / Intro:**

Opening constraint:
> "Building AI agents means managing LLM calls, token budgets, tool use, and failures—all while keeping agents supervised and isolated."

**Subheadline:**
> "AI-powered agent framework: Jido + ReqLLM + LLMDB integrated."

**Primary CTAs:**
- "View on Hex" → Hex package
- "Read HexDocs" → HexDocs
- "See on GitHub" → GitHub repo
- "Get Started" → /getting-started

---

#### Above the Fold

**Code snippet:**
```elixir
defmodule ResearchAgent do
  use JidoAI.Agent
  
  def init(args) do
    {:ok, %{
      model: {:openai, "gpt-4"},
      budget: 10_000,  # max tokens
      topic: args[:topic],
      findings: []
    }}
  end
  
  def handle_action(:research, state) do
    # Agent makes LLM call with budget tracking
    prompt = "Research the topic: #{state.topic}"
    
    case JidoAI.chat(state, prompt) do
      {:ok, response, new_state} ->
        findings = parse_findings(response)
        {:ok, %{new_state | findings: findings}}
      
      {:error, :budget_exceeded} ->
        {:error, :out_of_tokens}
    end
  end
end

# Start AI agent with supervision
{:ok, agent} = JidoAI.start_agent(ResearchAgent, 
  topic: "BEAM concurrency",
  model: {:anthropic, "claude-3-opus"}
)
```

**Metric strip:**
- "Jido agents with built-in LLM capabilities"
- "Token/cost tracking per agent"
- "Tool calling and streaming support"

---

#### Content Sections

**1. What JidoAI Does**

- Combines Jido bot framework + ReqLLM + LLMDB
- Agents with LLM capabilities (chat, function calling, streaming)
- Per-agent token/cost tracking
- Tool use support (function calling)
- Supervised AI agents with OTP lifecycle

**2. When to Use It**

- You need AI agents that make LLM calls
- You want to track token usage and costs per agent
- You need function/tool calling in agents
- You want supervised AI agents (not one-off scripts)
- You're building multi-agent AI systems

**3. Key Features**

- **LLM-aware agents:** Built-in chat, streaming, function calling
- **Budget tracking:** Per-agent token limits and cost tracking
- **Model switching:** Use different models per agent or per task
- **Supervision:** Full OTP supervision for AI agents
- **Composable:** Use with jido_action for validated AI workflows

**4. Architecture**

Diagram: JidoAI agent with LLM calls flowing through ReqLLM + LLMDB

```elixir
# Multi-agent AI system
defmodule AISwarm do
  def start_swarm(topic) do
    supervisor = start_supervisor()
    
    # Research agents
    for i <- 1..5 do
      JidoAI.start_agent(supervisor, ResearchAgent, 
        id: i, 
        topic: "#{topic} - aspect #{i}"
      )
    end
    
    # Synthesis agent
    JidoAI.start_agent(supervisor, SynthesisAgent,
      model: {:anthropic, "claude-3-opus"}
    )
  end
end
```

**5. Production Features**

- Agent-level failure isolation (LLM API failures don't kill other agents)
- Automatic retry with backoff (via ReqLLM)
- Telemetry for LLM calls (latency, tokens, cost)
- Observable with standard Elixir tools

**6. Installation & Docs**

- **Hex:** `{:jido_ai, "~> 0.1.0"}`  
  _(Includes jido, req_llm, llmdb)_
- **HexDocs:** [Link to full API docs]
- **GitHub:** [Link to repo]
- **Getting Started:** [/getting-started](#)

**7. Related Packages**

- **Jido** (core framework) → [/packages/jido](#)
- **ReqLLM** (LLM client) → [/packages/req-llm](#)
- **LLMDB** (model registry) → [/packages/llmdb](#)
- **Jido Coder** (coding agents) → [/packages/jido-coder](#)

---

### P7. Jido Coder (`/packages/jido-coder`)

**Goal:** Show Jido Coder as the specialized coding agent application.

**Audience:** Elixir developers building code analysis, generation, or modification tools.

**Hero / Intro:**

Opening constraint:
> "Code agents need to read files, understand structure, make LLM-guided decisions, and modify code—all under supervision with proper error handling."

**Subheadline:**
> "AI-powered coding agent built on JidoAI with file system, Git, and code analysis tools."

**Primary CTAs:**
- "View on Hex" → Hex package
- "Read HexDocs" → HexDocs
- "See on GitHub" → GitHub repo

---

#### Above the Fold

**Code snippet:**
```elixir
# Start a coding agent
{:ok, agent} = JidoCoder.start_agent(
  task: "refactor authentication module to use Ecto.Multi",
  codebase_path: "/path/to/project",
  model: {:anthropic, "claude-3-opus"},
  budget: 50_000  # tokens
)

# Agent workflow
# 1. Reads relevant files (lib/my_app/auth.ex, etc.)
# 2. Analyzes code structure
# 3. Makes LLM-guided refactoring decisions
# 4. Proposes changes
# 5. Writes modified files
# 6. Runs tests to validate

# Monitor agent progress
JidoCoder.subscribe_to_events(agent, fn event ->
  case event do
    {:file_read, path} -> IO.puts("Reading #{path}")
    {:analysis_complete, summary} -> IO.inspect(summary)
    {:changes_proposed, diff} -> IO.puts(diff)
    {:tests_passed} -> IO.puts("✓ Tests passed")
  end
end)
```

**Metric strip:**
- "Built-in code analysis and file operations"
- "Git integration for versioning"
- "Test execution and validation"

---

#### Content Sections

**1. What Jido Coder Does**

- AI coding agent built on JidoAI
- File system operations (read, write, analyze)
- Git integration (commit, branch, diff)
- Code analysis tools (AST parsing, structure analysis)
- Multi-step coding workflows
- Test execution and validation

**2. When to Use It**

- You need agents that can analyze code
- You build code generation or modification tools
- You want to automate refactoring with AI guidance
- You need agents that validate changes with tests
- You're building AI-assisted development tools

**3. Key Features**

- **Code analysis:** AST parsing, structure analysis, dependency detection
- **File operations:** Read, write, modify files with safety checks
- **Git integration:** Commit, branch, diff, merge
- **Multi-step workflows:** Plan → analyze → modify → test → validate
- **Tool library:** Common coding actions pre-built (refactor, add tests, etc.)
- **Supervised execution:** OTP supervision for long-running coding tasks

**4. Built-in Tools**

- `ReadFile`, `WriteFile`, `AnalyzeModule`
- `RunTests`, `FormatCode`, `CheckTypes`
- `GitCommit`, `GitDiff`, `CreateBranch`
- `ParseAST`, `FindFunction`, `ExtractDependencies`

**5. Example Workflows**

```elixir
# Workflow: Add tests for untested module
JidoCoder.start_agent(
  task: """
  Add comprehensive tests for MyApp.OrderProcessor module.
  Cover all public functions with unit tests.
  """,
  codebase_path: ".",
  model: {:openai, "gpt-4"}
)

# Workflow: Migrate deprecated API usage
JidoCoder.start_agent(
  task: """
  Find all uses of deprecated Phoenix.Controller.render/3
  and migrate to Phoenix.Controller.render/2 with assigns.
  Run tests after each file change.
  """,
  codebase_path: ".",
  incremental: true  # Change one file at a time, test, repeat
)
```

**6. Production Considerations**

- Agents run in supervision tree—crashes isolated
- File operations can be sandboxed (read-only mode, specific directories)
- Git operations tracked via events
- Token budget prevents runaway LLM costs
- Telemetry for all file/git/LLM operations

**7. Installation & Docs**

- **Hex:** `{:jido_coder, "~> 0.1.0"}`  
  _(Includes jido_ai, jido, req_llm, llmdb)_
- **HexDocs:** [Link to full API docs]
- **GitHub:** [Link to repo]

**8. Related Packages**

- **JidoAI** (AI agent layer) → [/packages/jido-ai](#)
- **Jido** (core framework) → [/packages/jido](#)

---

### 3. Getting Started (`/getting-started`)

**Goal:** Runnable path to "I installed it, started agents, and saw them work."

**Opening constraint:**
> "You don't need a cluster to evaluate Jido—start with a single node, a few thousand agents, and your usual metrics tools."

---

#### Choose Your Path

**If you know Elixir/OTP:**
- Jump to: `mix.exs` dependency → add to supervision tree → `iex` commands

**If you're new to the BEAM:**
- Brief: "A process is a lightweight isolated unit with its own state. A supervisor manages process lifecycles."
- Same quick-start with inline explanations

---

#### Steps

**Step 1: Install the Hex Package**

```elixir
# mix.exs
def deps do
  [
    {:jido, "~> 0.1.0"}  # Check Hex for latest version
  ]
end
```

Links: [Hex Package] [HexDocs]

**Note:** "Use the version from Hex; `main` on GitHub may be ahead."

---

**Step 2: Define Your First Agent**

```elixir
defmodule MyFirstAgent do
  use Jido.Agent

  def init(_args) do
    {:ok, %{counter: 0}}
  end

  def handle_action(:increment, state) do
    new_state = %{state | counter: state.counter + 1}
    {:ok, new_state}
  end
end
```

**Note:** "If this function raises, the agent process crashes. The supervisor handles restart."

---

**Step 3: Supervise Many Agents**

```elixir
# Start a supervisor
{:ok, sup} = DynamicSupervisor.start_link(
  strategy: :one_for_one,
  name: MyAgentSupervisor
)

# Start 1,000 agents
for i <- 1..1_000 do
  spec = {MyFirstAgent, id: i}
  DynamicSupervisor.start_child(sup, spec)
end
```

**Side note:** "This example starts 1,000 agents; adjust N to see CPU and memory impact."

---

**Step 4: Observe Your Agents**

Commands:
```elixir
# Start Observer
:observer.start()

# Inspect a specific agent process
pid = Process.whereis(MyFirstAgent)
:sys.get_state(pid)
```

Links: [Livebook Example] [YouTube: Observing Agents]

---

**Step 5: Next Steps**

- [/examples](#examples) – see full recipes
- [/ecosystem](#ecosystem) – understand the package landscape
- [HexDocs] – API reference and guides

---

### 4. Examples (`/examples`)

**Goal:** Show concrete, production-relevant patterns with code and numbers.

**Opening constraint:**
> "These examples focus on behavior under load—agent counts, latency, memory—not toy REPL demos."

**Note:** "All examples are real projects or Livebooks you can run."

---

#### Example Cards

Each example includes:
- **Title**
- **Scenario** (1–2 sentences)
- **Key metrics** (agents, CPU, memory, latency, environment)
- **Links:** [GitHub Code] [Livebook] [YouTube Walkthrough]
- **Code snippet:** Supervisor + agent behavior
- **Production note:** Failure handling description

---

**Example 1: Tool-Using Multi-Agent Research Swarm**

- **Scenario:** Coordinated research agents making LLM API calls with tool use
- **Metrics:** 1,000 agents, 2-core node, 180MB RAM, 150ms avg latency
- **Production note:** "When agents fail or timeout, this supervisor restarts them with backoff and cancels in-flight API requests"
- **Resources:**
  - [View code on GitHub](#)
  - [Run in Livebook](#)
  - [Watch 3-min walkthrough](#) (YouTube)

---

**Example 2: Long-Lived Planning Agents**

- **Scenario:** Agents orchestrating multi-step workflows with persistent state
- **Metrics:** 2,000 agents, 4-core node, 220MB RAM
- **Production note:** "Agent state survives node restarts via ETS or external persistence"

---

**Example 3: Streaming Log Processing**

- **Scenario:** Real-time log classification and routing
- **Metrics:** 5,000 agents, 10k msgs/sec throughput, 8-core node
- **Production note:** "Back-pressure handling via mailbox monitoring"

---

**Example 4: Cost-Aware LLM Agent Coordination**

- **Scenario:** Token-aware agents coordinating to stay within budget
- **Metrics:** 500 agents, $0.05/query avg, 95th percentile < 300ms

---

**Example 5: Multi-Node Deployment**

- **Scenario:** Agents distributed across 3 BEAM nodes
- **Metrics:** 15,000 total agents, node failover < 2s
- **Production note:** "When a node dies, surviving nodes detect it and supervisors redistribute agents"

---

### 5. Docs Hub (`/docs`)

**Goal:** Router page funneling to HexDocs, GitHub, and Livebooks without duplicating content.

**Opening constraint:**
> "All official Jido documentation lives where you work: HexDocs, GitHub, and Livebooks."

---

#### Above the Fold – Three Large Cards

**1. API Reference (HexDocs)**
- Link: [HexDocs Main Page](#)
- Text: "Modules, functions, and types with runnable examples"

**2. Guides & Patterns**
- Link: [HexDocs Guides](#) [GitHub](#)
- Text: "Getting Started, Architecture, Production patterns"

**3. Examples & Livebooks**
- Link: [/examples](#examples) [GitHub Examples Folder](#)
- Text: "Production examples with metrics and failure scenarios"

---

#### Quick Links

- HexDocs main page
- GitHub repository
- CHANGELOG
- Releases
- Issue tracker

---

#### Recommended Reading Paths

**For Elixir/OTP developers:**
1. Ecosystem overview (package landscape)
2. Getting Started
3. Supervision patterns
4. Production deployment

**For multi-agent migrators:**
1. "Why BEAM for multi-agent systems"
2. Getting Started
3. "From worker pools to supervised agents"
4. "Threads vs. processes"

---

#### Versioning

Current stable: **v0.1.0**

**Note:** "Docs on HexDocs track releases. `main` may be ahead with breaking changes."

---

### 6. Benchmarks & Proof (`/benchmarks`)

**Goal:** Central place for benchmarks, environment descriptions, and operational evidence.

**Opening constraint:**
> "Claims about concurrency and resilience are cheap; these are the numbers Jido actually hits on real hardware."

---

#### Above the Fold – Summary Metrics Box

- **10,000 agents** on 2-core, 4GB VM
- **Median message latency** < 1ms
- **Memory footprint** ~20KB per idle agent

Link: "How we measured this ↓"

---

#### Section 1: Single-Node Benchmarks

**Table: Agents vs Memory**

| Agents | Memory (MB) | CPU (%) | Environment |
|--------|------------|---------|-------------|
| 1,000  | 40         | 5       | 2-core, 4GB |
| 5,000  | 180        | 12      | 2-core, 4GB |
| 10,000 | 350        | 22      | 4-core, 8GB |

**Test scenario:**
- Agent behavior: simple state machine with periodic work
- Measurement: `:observer`, telemetry aggregation
- Duration: 10-minute sustained load

**Screenshot:** CPU/memory chart over time

---

#### Section 2: Multi-Node Scenarios

**Metrics:**
- Failover time when node dies: < 2s
- Throughput impact during node outage: 33% (1 of 3 nodes)
- Agent redistribution time: < 5s

---

#### Section 3: Failure Behavior Experiments

**Experiment 1: Random agent crashes**
- Crash 10% of agents randomly per second
- Result: Supervisor restarts isolated to crashed agents
- Impact: No cascade failures, 99.9% uptime for healthy agents

**Experiment 2: Thundering herd**
- 5,000 agents all request external API simultaneously
- Result: Back-pressure via mailbox monitoring
- Impact: Graceful degradation, no OOM

**Links:** [Benchmark code on GitHub](#) [Run scripts](#)

---

#### Section 4: Reproducing the Benchmarks

**GitHub:** [Benchmark repository](#)

**Commands:**
```bash
git clone https://github.com/agentjido/benchmarks
cd benchmarks
mix deps.get
mix run bench/single_node.exs
```

**Note:** "We expect developers to rerun and verify these numbers on their own hardware."

---

#### Section 5: Videos & Telemetry

**Embedded YouTube videos:**
- "10,000 agents with Observer open" (showing process tree, memory)
- "Node failover in real-time" (3-node cluster)
- "Back-pressure under load" (mailbox stats)

**Link:** [Full benchmark playlist on YouTube](#)

---

### 7. Community (`/community`)

_Note: Can start as a Home section and graduate to full page when needed._

**Opening constraint:**
> "When you're debugging a production incident, you need real responses—not a marketing funnel."

---

#### Support & Questions

- **GitHub Issues:** Bug reports and feature requests
- **GitHub Discussions:** Architecture questions, patterns
- **ElixirForum:** [Agent Jido thread](#)

---

#### Chat & Discussion

- **Discord/Slack:** [If applicable]
- **Real-time help:** Community channels

---

#### Content

- **YouTube channel:** Tutorials, benchmarks, talks
- **Conference talks:** Links to ElixirConf, CodeBEAM, etc.
- **Blog/writeups:** Long-form architecture posts

---

#### Roadmap & Contributing

- **Roadmap:** [GitHub ROADMAP.md](#)
- **Contributing:** [GitHub CONTRIBUTING.md](#)
- **Code of Conduct:** [Link](#)

---

## External Resources Integration

### YouTube

**Channel structure:**
- Playlist: "Getting Started with Agent Jido"
- Playlist: "Production Benchmarks"
- Playlist: "Architecture Deep Dives"
- Playlist: "Conference Talks"

**Video types:**
- 3-min example walkthroughs (embedded on `/examples`)
- 10-min architecture explanations (linked from `/architecture`)
- 5-min benchmark demos with Observer open (embedded on `/benchmarks`)
- Conference talks (linked from `/community`)

**Embedding strategy:**
- Hero on Home: 1 main video
- Examples page: 1 video per example card
- Numbers page: 2–3 benchmark videos
- Architecture: Optional deep-dive video

---

### HexDocs

**Main pages:**
- API Reference (all modules)
- Guides section:
  - Getting Started
  - Architecture
  - Supervision Patterns
  - Production Deployment
  - Observability
  - Multi-Node Clustering

**Integration on site:**
- Primary CTA on Home hero
- Dedicated card on `/docs` hub
- Footer link
- Inline links from `/architecture` to specific modules

---

### Hex Package

**Package page elements:**
- Clear description aligned with brand voice
- Installation instructions
- Link to agentjido.xyz
- Link to HexDocs
- GitHub repository link

**Integration on site:**
- Badge on Home (with version)
- Link in Getting Started
- Footer link

---

### GitHub

**Repository structure:**
- `/examples` – Production examples with README
- `/benchmarks` – Benchmark scripts and results
- `/livebooks` – Interactive Livebook examples
- `CHANGELOG.md` – Version history
- `ROADMAP.md` – Future plans
- `CONTRIBUTING.md` – Contribution guidelines

**Integration on site:**
- Example cards link to `/examples/{name}`
- Benchmark reproduction links to `/benchmarks`
- Livebook links to `/livebooks/{name}.livemd`
- Footer links to repo, issues, discussions

---

## Content Priorities by Page

### Home
1. **Above fold:** Constraint + code + metrics (first 10 seconds)
2. **Why BEAM:** Dual persona framing (next 20 seconds)
3. **Production properties:** Evidence of resilience (scroll 1)
4. **Examples preview:** Real use cases with numbers (scroll 2)

### Ecosystem
1. **Package landscape:** How packages compose (foundation → core → AI → apps)
2. **Dependency graph:** Visual map of which packages depend on what
3. **Decision tree:** "Which packages do I need?"
4. **Code examples:** Composing packages for different use cases

### Getting Started
1. **Installation:** Copy-paste ready
2. **First agent:** Minimal working example
3. **Observation:** How to see it working
4. **Next steps:** Clear path to deeper learning

### Examples
1. **Metrics:** Every example has numbers
2. **Code:** GitHub links to full implementations
3. **Videos:** Visual proof it works
4. **Failure notes:** Production considerations

### Benchmarks
1. **Benchmarks:** Tables with environment specs
2. **Reproduction:** How to verify yourself
3. **Videos:** Visual proof of metrics
4. **Honesty:** Show limitations and caveats

---

## Brand Voice Checklist Application

Every page must satisfy:

- [ ] **Constraint in first sentence** – Lead with the problem/limit
- [ ] **Code visible early** – Within first screen or fold
- [ ] **Specific numbers** – No claims without metrics
- [ ] **No hype language** – Avoid "revolutionary," "seamless," etc.
- [ ] **Failure behavior mentioned** – What breaks, how it's handled
- [ ] **Links to proof** – Code, benchmarks, videos
- [ ] **Respect both personas** – Clear paths for BEAM natives and migrants
- [ ] **Production focus** – Not demos, but real operational concerns

---

## Technical Implementation Notes

### Analytics & Tracking
- Track CTA clicks (Getting Started, HexDocs, Examples)
- Track external link clicks (GitHub, YouTube, Hex)
- Track persona path (which sections users view)

### Performance
- Fast load time (< 2s)
- Code snippets syntax highlighted
- Videos lazy-loaded
- Embedded HexDocs badges cached

### Maintenance
- Version number automated (pulled from Hex API)
- GitHub stats automated (stars, latest release)
- Benchmark data versioned with semver
- All code snippets tested in CI

---

## Rollout Phases

### Phase 1: MVP (Launch)
- Home (complete)
- Getting Started (basic path)
- Architecture (core sections 1–4)
- Docs hub (router only)
- Footer with external links

### Phase 2: Evidence Layer
- Examples (3–5 cards with code)
- Numbers (basic benchmarks)
- YouTube embeds on Home + Examples

### Phase 3: Community & Scale
- Community page (if needed, else keep as Home section)
- Additional examples
- Advanced architecture sections
- Multi-language support (if needed)

---

## Success Metrics

**Engagement:**
- Time to first code click (target: < 30s)
- HexDocs clickthrough rate from Home (target: > 20%)
- GitHub star conversion (visitors → stars)

**Persona validation:**
- Track "For BEAM developers" vs "For migrators" section views
- Survey: "Did you find what you needed?"

**Conversion:**
- Hex package downloads trend
- GitHub issue/discussion engagement
- Community channel growth

---

## Final Notes

This sitemap prioritizes **clarity over comprehensiveness**. Each page has a single job:

- **Home:** Prove credibility in 30 seconds
- **Architecture:** Build mental model
- **Getting Started:** Get code running
- **Examples:** Show real patterns
- **Numbers:** Provide evidence
- **Docs:** Route to depth

All detailed content lives where developers expect it: HexDocs for API docs, GitHub for code, YouTube for visuals, Livebooks for interactive learning.

The site's job is to **orient, convince, and hand off**—not to duplicate what already exists in better formats elsewhere.

# Agent Jido Voice Profile

## 1. Voice Summary

The voice of someone who's shipped and operated distributed systems long enough to know what breaks at 3am.

Technical but not academic. Confident without arrogance. Skeptical of hype. Speaks to developers who've been burned by overpromised frameworks and just want something that **behaves predictably under load, in production, on real infrastructure**.

Jido's voice assumes you care about:

- How many agents you can run per node
- What happens when a node dies
- How you observe and debug the system when things go sideways
- Memory and CPU ceilings in real deployments

It explains those things plainly, through code and numbers, not slogans.

---

## 2. Audience

Two primary reader types:

- **Persona 1 – BEAM native:** Experienced Elixir/OTP developer, comfortable with supervision trees, GenServers, and distributed nodes. They want to know how Jido composes with OTP, not why BEAM exists.
- **Persona 2 – Production backend engineer from another ecosystem:** Strong in Python/Node.js/Go/Java, used to threads, worker pools, Kafka, and k8s. New to BEAM, not new to systems. They need a clear mental model of "processes, mailboxes, supervision" and why it changes what's possible for agents.

The voice respects both:

- No BEAM 101 for Persona 1.
- No condescension or "this is easy" talk for Persona 2.

---

## 3. Core Personality Traits

- **Production-hardened pragmatist**  
  Leads with resilience, concurrency, observability, and memory footprint—not because it sounds good, but because that's what fails first in production. Prefers boring, predictable systems over clever abstractions.

- **Elixir insider, not evangelist**  
  Assumes you already know BEAM/Elixir is powerful or you wouldn't be here. No time spent converting you. Focuses on how Jido leverages OTP patterns (supervision, isolation, message-passing) for multi-agent systems.

- **Code-first teacher**  
  Explains through working examples and supervision diagrams, not marketing diagrams. "Here's 10,000 supervised agents in one node" beats "Our framework provides extensible agent orchestration primitives."

- **Built for builders**  
  Respects your time. No fluff. Clear docs, runnable examples, copy‑pasteable snippets. Assumes you're here to build and operate a system, not browse a brochure.

- **Evidence-driven skeptic**  
  Makes concrete claims and shows evidence: code, supervisor trees, telemetry screenshots, benchmarks. Not "faster," but "X agents / Y ms / Z MB RAM on N cores."

---

## 4. Tone Spectrum

| Dimension               | Position                 | Notes |
|-------------------------|--------------------------|-------|
| Formal ↔ Casual         | Professional-casual      | Clear, direct, precise. Occasional dry personality. Never chatty or slangy. |
| Serious ↔ Playful       | Serious with edge        | Dry humor is fine; jokes are rare and subtle. The problem space is serious. |
| Reserved ↔ Bold         | Bold, specific claims    | "10,000 agents per node" is fine. "Revolutionary" is not. Claims are backed by BEAM architecture and real numbers. |
| Simple ↔ Sophisticated  | Simple words, deep ideas | Explains supervision, isolation, and back-pressure in plain language. No hand-waving. |
| Warm ↔ Direct           | Direct, developer-respect| Gets to the point. Assumes competence. No pandering, no "super easy." |
| Neutral ↔ Opinionated   | Opinionated, grounded    | Has a point of view about threads vs processes, coordination vs orchestration, "let it crash" vs defensive coding. Explains why, not just that. |

---

## 5. Vocabulary

### Words/phrases to USE

Focus on real system properties, not vibes:

- **Positioning**
  - "Built for production, not just prototypes."
  - "Native concurrency on the BEAM."
  - "Run 10,000+ agents on a single node."
  - "Autonomous, supervised processes."

- **Architecture & runtime**
  - "BEAM"
  - "Actor model"
  - "Isolated processes"
  - "Per-process state"
  - "Supervision trees"
  - "Crash isolation / let it crash"
  - "Back-pressure"
  - "Mailbox" / "message-passing"
  - "Distributed nodes"
  - "True parallelism" / "concurrent by default"

- **Operational properties**
  - "Production"
  - "Native" (concurrency, resilience)
  - "Built-in" (failure handling, backoff, supervision)
  - "Lightweight" / "small footprint"
  - "Fault-tolerant by design"
  - "Observable" / "introspectable"
  - "Runtime metrics" / "telemetry"

- **Multi-agent specifics**
  - "Autonomous" / "distributed" / "adaptive" agents
  - "Composable behaviors" / "composable tools"
  - "Resilient orchestration"
  - "Per-agent supervision"
  - "Validated actions" / "constrained tools"
  - "Cost-aware execution" / "token-aware planning"

- **Comparative (for Persona 2)**
  - "Unlike threads…"
  - "Node.js spawns workers, Elixir spawns processes."
  - "Instead of shared memory locks, each agent owns its state."
  - "Where you'd reach for Kafka, here you use processes and message-passing."

### Words/phrases to AVOID

Avoid hype, vagueness, and beginner-targeted language:

- "Revolutionary" / "groundbreaking" / "disruptive"
- "Easy" / "simple" / "frictionless" (minimizes work)
- "Powerful" / "robust" / "flexible" without concrete meaning
- "Enterprise-grade" / "synergy" / other corporate filler
- "AI-powered" (redundant)
- "Seamless" / "effortless"
- "Next-gen" / "cutting-edge" / "innovative" without specifics

### Jargon level

- **Moderate-to-heavy technical**, but:
  - Use BEAM/Elixir terms confidently: actor model, GenServer, supervision tree, CloudEvents, telemetry, ETS, etc.
  - For Persona 2, define a term once in one tight sentence, then use it freely.
    - Example: "Each agent runs in its own BEAM process with its own mailbox (message queue). If one crashes, its supervisor decides what to do next."

### Profanity

- Never.

---

## 6. Rhythm & Structure

- **Sentences:**  
  Medium length. Dense with information but readable. Avoid long, nested clauses.

- **Paragraphs:**  
  Short (1–3 sentences). Break up explanations with code, diagrams, or bullets.

- **Openings:**  
  Lead with the constraint or failure mode, then the solution. Examples:
  - "Most agent frameworks assume infinite CPU and memory. Jido doesn't."
  - "You can spawn 10,000 agents in a REPL. Keeping them alive during a deploy is the hard part."

- **Formatting:**  
  - Code examples do heavy lifting.
  - Use bullet points for properties and constraints.
  - Use headers for structure.
  - Minimize connective fluff between code blocks. If a sentence doesn't help you run or operate the system, cut it.

---

## 7. POV & Address

- **First person:**  
  Rarely. Use direct, factual statements over "we believe" or "we built."

- **Reader address:**  
  - "You" is fine, but not overdone.
  - Imperative and declarative are primary:
    - "Start a node with 10,000 supervised agents."
    - "Each agent runs in its own process with isolated state."

- **Relationship stance:**  
  Expert peer. Not selling—showing.  
  - Assumes the reader can read and reason about code.
  - Assumes they've seen production incidents and care about avoiding them.

---

## 8. Example Phrases

### On-brand

- "Run 10,000 agents on a single BEAM node, each in its own supervised process."
- "Built for production, not just prototypes."
- "Native concurrency with the BEAM's actor model and supervision trees."
- "Automatic recovery from agent failures. No external orchestrator required."
- "Lightweight, autonomous processes designed to work together under load."
- "When an agent crashes, its supervisor restarts it in milliseconds. The rest of the system keeps running."
- "Observe per-agent state and messages with standard Elixir tooling."

### Off-brand

- "Unlock the power of AI agents with our revolutionary framework!"
- "Getting started is super easy and fun!"
- "Jido makes building agents a breeze."
- "Experience seamless agent orchestration."
- "Transform your business with next-generation AI."
- "Say goodbye to outages forever."

---

## 9. Do's and Don'ts

### DO

- **Lead with production constraints**
  - Memory ceilings, CPU usage, tail latencies, failure modes, deploys, upgrades.
  - Example: "This example runs 5,000 agents in 200MB of RAM on a 2‑core node."

- **Show code early and often**
  - First screen on a landing page, first section in a README, first section of a guide.
  - Include supervisors, not just happy-path agent code.

- **Make specific, measurable claims**
  - "10,000 agents, one container."
  - "Sub‑millisecond message passing between agents on the same node."
  - "Zero external queue required for intra-node communication."

- **Explain WHY with architecture**
  - "The BEAM's actor model and preemptive scheduler let each agent run in an isolated process with its own mailbox. That's why you can pack thousands of them on a node without shared-memory contention."

- **Respect different starting points**
  - For Persona 2:  
    - Make architectural contrasts explicit (threads vs processes, shared memory vs isolated state, external queue vs in‑VM message passing).
    - Tie back to their experience: "If you'd normally use a worker pool plus Redis, here you use supervised processes."
  - For Persona 1:  
    - Show exactly how Jido composes with OTP and standard libraries.
    - Use idiomatic Elixir patterns and terminology without apology.

- **Focus on what breaks in production and how Jido handles it**
  - Agent crashes, retries, idempotency.
  - Thundering herds and back-pressure.
  - Node restarts and rolling deploys.
  - Observability and introspection.

- **Use comparisons carefully**
  - Compare architecture and failure modes, not "framework vs framework."
  - Example: "Unlike thread-based agents, Jido agents can crash and be restarted in isolation without bringing down the rest of the system."

### DON'T

- **Don't oversell with superlatives**
  - No "fastest," "best," or "most powerful" unless you show a benchmark and context.

- **Don't hide behind abstraction**
  - Don't say "orchestration primitives" without showing the supervision tree and the code that defines it.

- **Don't compare to other AI agent frameworks by name**
  - Let the architecture and numbers speak. No mudslinging.

- **Don't use generic marketing language**
  - If text would fit on any SaaS landing page, it probably doesn't belong here.

- **Don't promise "easy" or "effortless"**
  - Acknowledge that building reliable distributed systems is hard.
  - Promise "production-ready patterns, good defaults, and sharp tools," not "no work."

- **Don't talk down to Persona 2**
  - They know production, they just don't know BEAM yet.

- **Don't over-explain to Persona 1**
  - They already know what a supervisor is; focus on what Jido layers on top of existing OTP patterns.

---

## 10. Application Notes & Checklists

### Landing Pages

**Goal:** Prove that Jido is a serious, production-ready agent framework on the BEAM.

- **Hero:**  
  - Lead with constraint + claim.  
    - Example: "10,000 supervised agents on a single BEAM node. Built for production, not demos."
- **Above the fold:**
  - One tight code example (spawn or define an agent).
  - One specific number (agents/node, memory footprint, restart behavior).
  - Brief statement tying Jido to BEAM/OTP ("Built on OTP supervision, not YAML orchestration.")
- **Checklist:**
  - [ ] Constraint in first sentence.
  - [ ] Code snippet visible without scrolling.
  - [ ] At least one concrete metric.
  - [ ] No hype adjectives without evidence.

### Documentation

**Goal:** Help a production engineer understand, run, and operate Jido.

- **Principles:**
  - Code-first. Show working samples with supervisors, not just agent definitions.
  - Explain architecture with diagrams and short explanations (supervision trees, message flow).
  - Highlight operational concerns: logging, metrics, failure recovery, deployment notes.

- **Checklist for each doc page:**
  - [ ] One runnable example (module or Livebook).
  - [ ] One note on failure behavior ("If this process crashes, this supervisor restarts it.")
  - [ ] One pointer to observability/metrics for this part of the system.
  - [ ] No section that sounds like a pitch.

### README / GitHub

**Goal:** Show that Jido is real, usable today, and fits into standard Elixir workflows.

- **Content:**
  - Minimal quick start that:
    - Starts an agent or a small swarm.
    - Shows where supervision is configured.
  - Explicit "What happens when this crashes?" section.
  - Links to docs and examples (Livebooks, demos).

- **Checklist:**
  - [ ] First code block within ~10 lines of text.
  - [ ] Quick start ≤ ~20–30 lines of Elixir.
  - [ ] At least one mention of supervision/failure recovery.
  - [ ] No "marketing features" section without code.

### Social / Content

**Goal:** Show real behavior and numbers, not opinions.

- Show:
  - Livebooks.
  - Screen recordings of many agents running with system metrics.
  - Tweets/threads with short code snippets and measured outcomes.
- Avoid:
  - Opinion-only takes about "agents."
  - Threads with no code.

---

## 11. Why This Voice

This voice differentiates Agent Jido by speaking the language of developers who have actually run distributed systems in production. It centers concurrency, memory efficiency, supervision, and observability—not the AI hype cycle or prototype demos.

For experienced Elixir developers, it validates their choice of BEAM and shows how to use it to run serious multi-agent systems without fighting the runtime. For developers coming from other ecosystems, it explains the architectural shift—processes, mailboxes, supervision—in concrete terms they can map to their existing mental models of threads, queues, and worker pools.

The promise is not "magic agents." The promise is **agent infrastructure that behaves predictably at 3am when something crashes, traffic spikes, or a node disappears.**

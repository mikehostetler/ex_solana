# Jido Marketing Roadmap

**Purpose:** Strategic marketing plan to drive developer adoption and establish Jido as the production-ready multi-agent framework on BEAM.

**Foundation:** Built on brand voice, website sitemap, 18 Livebook examples, and competitive analysis.

**Core Strategy:** Workbench-driven content flywheel  
`Livebook examples → Blog posts → Videos → Social → Community → Talks → Back to examples`

**Last Updated:** 2025-12-23

---

## Executive Summary

### Goals

1. **Establish credibility** as production-ready framework (not prototype/demo)
2. **Differentiate** on BEAM/OTP advantages (supervision, concurrency, fault tolerance)
3. **Serve two personas:**
   - P1: BEAM natives (Elixir/OTP developers)
   - P2: Multi-agent migrators (Python/Node.js backend engineers)
4. **Build community** of production-minded users
5. **Drive adoption** measured by Hex downloads, GitHub activity, production deployments

### Success Metrics

**Engagement:**
- 10k+ monthly site visits by Month 6
- 50%+ engagement rate on technical social posts
- 100+ Livebook opens per example

**Community:**
- 200+ Discord/Slack members by Month 3
- 20+ monthly office hours attendees
- 5+ community-contributed examples by Month 6

**Adoption:**
- 1k+ Hex downloads/month by Month 6
- 500+ GitHub stars by Month 6
- 3+ production case studies by Month 12

**Trust:**
- 2+ conference talk acceptances
- 5+ blog posts cited by community
- 10+ integrations/tools built on Jido

---

## Content Pillars

All content serves one of these pillars:

1. **BEAM Advantages** – Supervision, concurrency, distribution vs threads/queues
2. **Production Patterns** – Observability, failure handling, cost control
3. **Migration Paths** – From Python frameworks to BEAM architecture
4. **Proof Points** – Benchmarks, case studies, real numbers
5. **Learning Ladder** – Beginner → Intermediate → Advanced examples

---

## Phase 0: Pre-Launch (Week -2 to 0)

**Goal:** Foundation in place, ready to ship content.

### Documentation & Infrastructure

- [x] Brand voice document (`JIDO_BRAND_VOICE.md`)
- [x] Website sitemap (`AGENTJIDO_SITEMAP.md`)
- [x] Examples catalog (`JIDO_WORKBENCH_EXAMPLES.md`)
- [x] Competitive analysis (`AI_AGENT_FRAMEWORK_TAXONOMY.md`)
- [ ] Website live at https://agentjido.xyz
- [ ] HexDocs published
- [ ] Hex package published
- [ ] GitHub repo public with examples

### Community Infrastructure

- [ ] Discord or Slack workspace set up
  - Channels: `#questions`, `#examples`, `#production-incidents`, `#general`
  - Pinned: Links to `/getting-started`, `/examples`, `/benchmarks`, Workbench repo
  - Rules/CoC posted
- [ ] YouTube channel created
- [ ] Twitter/X account active
- [ ] LinkedIn company page (optional)

### Content Pipeline Setup

- [ ] Blog publishing workflow (site CMS or markdown + git)
- [ ] Video recording/editing setup
- [ ] Social post scheduler (Buffer, Typefully, or manual)
- [ ] Analytics tracking (Plausible, Google Analytics, or similar)

---

## Phase 1: Launch Foundation (Weeks 1-6)

**Goal:** Establish core narrative with "proof, not hype" content anchored in Examples 1-6, 9-10.

### Milestone: Launch Week (Week 1)

**Ship:**
- [ ] Website live with Home, Getting Started, Examples (1-6), Docs hub
- [ ] Hex packages v0.1.0 published (jido, jido_ai, req_llm, llmdb)
- [ ] HexDocs live and linked for all packages
- [ ] The Swarm Discord announcement (already launched, announce Jido there)
- [ ] Launch announcement:
  - [ ] ElixirForum (automated via partnership)
  - [ ] r/elixir (drives most traffic)
  - [ ] AgentJidoX account
  - [ ] Mike Hostetler's personal account
- [ ] Update Awesome Elixir AI list with Jido packages

**Content:**
- [ ] **Blog Post 1:** "Introducing Jido: Production-Ready Multi-Agent Framework on BEAM"
  - Constraint-first intro
  - Link to Examples 2, 3, 7
  - Link to `/benchmarks` preview
  - No hype, just: "Here's what works, here's what's roadmap"
- [ ] **Video 1:** "First Jido Agent in 10 Minutes" (Example 2)
  - Live coding in Livebook
  - Show supervision, crash, restart
  - Upload to YouTube, embed on `/getting-started`
- [ ] Social: 3-5 launch threads
  - Thread 1: "Most agent frameworks assume infinite resources. Here's 10k agents on one node." + benchmark clip
  - Thread 2: "Agents as processes, not threads" + code snippet
  - Thread 3: "Why we built this on BEAM" + link to intro post

### Weeks 2-3: Mental Model & Architecture

**Content:**
- [ ] **Blog Post 2:** "Agents as Processes, Not Threads: Mental Model for Backend Engineers"
  - Target: P2 (migrators)
  - Side-by-side: threads+queues+Redis vs processes+mailboxes+supervision
  - Diagrams + minimal code
  - Link from `/ecosystem` and `/getting-started`
- [ ] **Blog Post 3:** "First Jido Agent: Supervised Counter on the BEAM"
  - Target: P1 (BEAM natives)
  - Deep dive into Example 2
  - Code, supervision tree diagram, memory numbers
  - Show crash/restart with Observer screenshots
- [ ] **Video 2:** "Agents as Processes (5 min explainer)"
  - Animated diagrams or whiteboard
  - No code, pure architecture
  - Share on LinkedIn for P2 audience
- [ ] Social: 4-6 posts
  - "Failure Mode Friday" #1: "What happens when an agent crashes"
  - 2x "Snippet + Metric" threads from Example 2
  - Mental model post: "Where you use Redis for queues, we use mailboxes"

**Community:**
- [ ] First office hours scheduled for Week 4 (in The Swarm Discord)
- [ ] Pin FAQ in The Swarm based on early questions
- [ ] Cross-post examples to ElixirForum with discussion threads
- [ ] Update Awesome Elixir AI list with new examples as they ship

### Weeks 4-6: Proof Points & Benchmarks

**Content:**
- [ ] **Blog Post 4:** "Running 10,000 Agents on a Single Node: Benchmarks"
  - Target: Both personas
  - Source: Examples 9 + 10
  - Exact hardware specs, Elixir version, Jido version
  - RAM/CPU graphs, latency numbers
  - Failure scenarios tested
  - "How to reproduce" section
  - Update `/benchmarks` page with this data
- [ ] **Blog Post 5:** "From LLM Call to Supervised Tool-Using Agent"
  - Target: P2 first, P1 second
  - Step-by-step: ReqLLM (Ex 1) → JidoAI (Ex 3) → jido_action (Ex 4)
  - Production hooks: logging, retries, validation
- [ ] **Video 3:** "10,000 Agents on a Single Node (Flagship, 8-10 min)"
  - Start Observer + system metrics
  - Run Example 9 Livebook (spawn agents)
  - Watch CPU/RAM
  - Crash subset, show isolation
  - Short compare slide at end
  - Hero video for `/` and `/benchmarks`
- [ ] **Video 4:** "From LLM Call to Supervised Agent"
  - Walkthrough Examples 1 → 3
  - Show replay, error handling
- [ ] Social: 6-8 posts
  - Benchmark threads with graphs (3x)
  - "Failure Mode Friday" #2: "Node dies mid-deploy"
  - "Failure Mode Friday" #3: "LLM API timeout"
  - Community highlight (if anyone shares examples)

**Community:**
- [ ] First monthly office hours (Week 4)
  - Topic: "Building Your First Jido Agent"
  - Record and clip walkthrough segment
- [ ] "Example of the Month" program announced

**Distribution:**
- [ ] Cross-post Blog Post 4 (benchmarks) to Dev.to with canonical URL
- [ ] Share on ElixirForum, r/elixir, Hacker News (if appropriate)

### Phase 1 Deliverables

**Content:**
- ✅ 5 blog posts
- ✅ 4 videos on Elixir Mentor YouTube (8.5k reach)
- ✅ 15-20 social posts (AgentJidoX + Mike Hostetler's account)
- ✅ 1 office hours recording (The Swarm Discord)

**Pages:**
- ✅ Website live (Home, Examples 1-6, Getting Started, Docs, Benchmarks)
- ✅ Benchmarks page populated with data

**Community:**
- ✅ Discord/Slack launched
- ✅ First office hours held
- ✅ Example program launched

---

## Phase 2: Deepen & Prove (Weeks 7-12)

**Goal:** Advanced patterns, multi-agent coordination, community growth, conference submissions.

### Weeks 7-8: Multi-Agent Coordination

**Content:**
- [ ] **Blog Post 6:** "Multi-Agent Coordination Without External Queues"
  - Target: Both, leaning P2
  - Source: Examples 5, 7, 12
  - Compare to manager+Kafka pattern
  - Show back-pressure, rate limiting, failure isolation
  - Code from Example 7 (manager-worker)
- [ ] **Blog Post 7:** "Observability for Agents: Telemetry, Traces, and State Inspection"
  - Target: P1
  - Source: Example 10
  - Plug into existing Elixir telemetry stack
  - Screenshots from Observer, dashboards, logs
- [ ] **Video 5:** "Multi-Agent Debugging: Inspecting State and Failures"
  - Walkthrough Example 10
  - Show timeout, retry, supervision strategies
  - Telemetry dashboard integration
- [ ] Social: 4-6 posts
  - "Failure Mode Friday" #4: "Worker crashes, manager continues"
  - 2x coordination pattern snippets
  - Office hours highlights

**Examples:**
- [ ] Publish Examples 7-9 to `jido_workbench`
- [ ] Update `/examples` page with new examples

### Weeks 9-10: Migration & Comparison

**Content:**
- [ ] **Blog Post 8:** "Testing Agents with Livebooks: In-Repo Evaluation Harness"
  - Target: Both
  - Source: Example 18
  - Show evaluation harness, baselines, regression detection
  - Compare to hosted eval platforms (architecture, not brand names)
- [ ] **Blog Post 9:** "Migration Diary: Multi-Agent Workflow from Python to BEAM"
  - Target: P2
  - Use realistic LangGraph/CrewAI-like flow reimplemented in Jido
  - Focus: LOC, infra removed, failure behavior, cost/perf
  - Fictional but realistic and fair
- [ ] **Video 6:** "Pattern Clips" (3-5 short 1-3 min clips) – **Elixir Mentor YouTube Shorts**
  - "Crash an agent, watch supervisor restart"
  - "Add signal subscription to decouple agents"
  - "Evaluate scenarios with ETS + Livebook"
  - Use for social media (AgentJidoX, Mike's account)
  - Cross-post to The Swarm Discord
- [ ] Social: 6-8 posts
  - "Failure Mode Friday" continues
  - Migration mental model posts
  - Clips from Videos 6

**Community:**
- [ ] Second monthly office hours
  - Topic: "Multi-Agent Patterns"
  - Q&A on coordination

### Weeks 11-12: Events & Case Studies

**Content:**
- [ ] **Blog Post 10:** "Reference Architecture: [Internal Case Study Name]"
  - Use JidoCoder or internal ops assistant
  - Requirements, architecture diagrams
  - Resource usage, costs, incidents
  - Turn into talk deck
- [ ] **Video 7:** "Workshop Preview: Building Production Agents (15-20 min)"
  - Condensed version of half-day workshop
  - Walk through Examples 2 → 3 → 7 → 10
- [ ] Social: 6-8 posts
  - Case study highlights
  - Conference announcement (if accepted)
  - Year-in-review type thread

**Community:**
- [ ] Third monthly office hours (The Swarm Discord)
- [ ] Highlight 2-3 community examples (blog + social)
- [ ] Feature community contributors on `/community` page
- [ ] ASH framework integration guide (partnership content)

**Events:**
- [ ] Submit CFPs to ElixirConf, Code BEAM
  - Talk 1: "10,000 Supervised Agents on the BEAM"
  - Talk 2: "From Threads to Processes: Multi-Agent Systems on BEAM" (polyglot conference)
- [ ] Lightning talk at local Elixir meetup

**Examples:**
- [ ] Publish Examples 11-13 to `jido_workbench`
- [ ] Update `/examples` with advanced section

### Phase 2 Deliverables

**Content:**
- ✅ 5 blog posts (total: 10)
- ✅ 3 videos + 3-5 short clips (total: 10+ videos)
- ✅ 25-30 social posts
- ✅ 3 office hours recordings

**Pages:**
- ✅ Examples 7-13 published
- ✅ `/community` page with office hours replays

**Community:**
- ✅ 100+ Discord members
- ✅ 3 office hours held
- ✅ 2+ community examples highlighted

**Events:**
- ✅ 2 CFPs submitted
- ✅ 1 lightning talk given

---

## Phase 3: Scale & Trust (Months 4-6)

**Goal:** Case studies, advanced content, workshop, conference talks, production proof.

### Month 4: Advanced Patterns

**Content:**
- [ ] **Blog Post 11:** "Cost-Aware Planning: Budget-Constrained Multi-Step Tasks"
  - Source: Example 14
  - Show model switching based on budget
  - Use LLMDB pricing metadata
- [ ] **Blog Post 12:** "Distributed Jido Cluster: Agents Across Multiple Nodes"
  - Source: Example 13
  - BEAM distribution basics
  - Node failover demo
- [ ] **Blog Post 13:** "Human-in-the-Loop Orchestration with Approval Gates"
  - Source: Example 16
  - Safety patterns for high-risk operations
- [ ] Social: 8-10 posts per month
  - Advanced pattern snippets
  - Community highlights
  - Conference prep/announcements

**Examples:**
- [ ] Publish Examples 14-16 to `jido_workbench`

### Month 5: Case Studies & Proof

**Content:**
- [ ] **Case Study 1:** Early adopter story (1-2 pages + 5 min video)
  - "What they ran before, why it broke, what changed"
  - Publish on `/community`
- [ ] **Case Study 2:** Second production deployment
- [ ] **Blog Post 14:** "DAG Workflows the OTP Way: LangGraph Patterns in Jido"
  - Source: Example 15
  - Side-by-side comparison
  - Architecture focus, not brand bashing
- [ ] **Video 8:** Case study interview/walkthrough
- [ ] Social: Continue weekly cadence

**Community:**
- [ ] Office hours #4-5
- [ ] "Jido Clinic" – 1:1 debugging sessions with early adopters

**Events:**
- [ ] Conference talk(s) delivered (if accepted)
- [ ] Record and publish talk video

### Month 6: JidoCoder & Evaluation

**Content:**
- [ ] **Blog Post 15:** "JidoCoder: Autonomous Elixir Refactoring Agent"
  - Source: Example 17
  - Code analysis, refactoring, safety
- [ ] **Blog Post 16:** "Production Readiness Checklist for Jido Agents"
  - Supervision strategies
  - Observability setup
  - Cost controls
  - Testing patterns
- [ ] **Video 9:** "JidoCoder walkthrough"
- [ ] Social: Continue cadence + promote workshop

**Examples:**
- [ ] Publish Examples 17-18 to `jido_workbench`
- [ ] All 18 examples complete

**Community:**
- [ ] Office hours #6
- [ ] 5+ community examples highlighted

**Events:**
- [ ] Half-day workshop: "Building Production Agents with Jido"
  - At conference or standalone
  - Walk through Examples 2, 3, 7, 10
  - Record and publish as series

### Phase 3 Deliverables

**Content:**
- ✅ 6 blog posts (total: 16)
- ✅ 2-3 videos + case studies (total: 13+ videos)
- ✅ 30-40 social posts
- ✅ 3 office hours
- ✅ 2 case studies

**Pages:**
- ✅ All 18 examples published
- ✅ `/community` with case studies

**Community:**
- ✅ 200+ Discord members
- ✅ 6 office hours held
- ✅ 5+ community examples

**Events:**
- ✅ 1-2 conference talks delivered
- ✅ 1 workshop delivered

---

## Phase 4: Sustain & Grow (Months 7-12)

**Goal:** Maintain cadence, community leadership, production proof points.

### Content Cadence

**Monthly (ongoing):**
- [ ] 2-3 blog posts (deep dives, patterns, updates)
- [ ] 1-2 videos
- [ ] 8-12 social posts
- [ ] 1 office hours
- [ ] 1 community highlight

**Themes:**
- Advanced OTP patterns
- Production incident stories
- Community case studies
- Integration guides (observability platforms, LLM providers)
- Version release announcements

### Community Programs

**Ongoing:**
- [ ] Monthly office hours
- [ ] "Example of the Month" program
- [ ] "Jido in Production" interview series
- [ ] Community contributor recognition

**New:**
- [ ] Formal RFC process for roadmap
- [ ] "First Production Launch" cohort program
- [ ] Community call (quarterly)

### Events & Speaking

**Targets:**
- [ ] 2-4 conference talks per year
- [ ] 1-2 workshops per year
- [ ] Monthly local meetup lightning talks

### SEO & Discoverability

**Ongoing:**
- [ ] Optimize existing pages for keywords
- [ ] Internal linking audit quarterly
- [ ] Cross-post high-value content to Dev.to, Medium
- [ ] ElixirForum presence

**New:**
- [ ] Comparison guide hub: "Architecture Guides"
- [ ] Livebook sharing via LivebookHub
- [ ] Partner/integration announcements

### Goals for Month 12

**Adoption:**
- 5k+ Hex downloads/month
- 1k+ GitHub stars
- 10+ production deployments
- 5+ case studies published

**Community:**
- 500+ Discord members
- 30+ community examples
- Active contributor base (5+ regular contributors)

**Trust:**
- 5+ conference talks delivered
- Featured in Elixir newsletters
- Mentioned in "State of Elixir" survey
- Integration partnerships (observability, hosting, LLM providers)

---

## Content Production Workflow

### For Each Livebook Example

When publishing a new example:

1. **Livebook:** Implement and test in `jido_workbench`
2. **Example page:** Update `/examples` with description, code, metrics
3. **Blog post:** Write companion deep-dive (1 week after example ships)
4. **Video:** Record walkthrough (same week as blog post)
5. **Social:** Create 2-3 threads/posts with snippets
6. **Link:** Add to HexDocs guides section

### Weekly Content Calendar Template

**Monday:**
- Social: "Failure Mode Friday" post (prep for Friday)

**Tuesday:**
- Blog post draft (if scheduled this week)

**Wednesday:**
- Video recording/editing (if scheduled)
- Social: Snippet + Metric thread

**Thursday:**
- Social: Mental model or pattern post
- Community engagement (Discord, ElixirForum)

**Friday:**
- Social: "Failure Mode Friday" publish
- Weekly review and next week planning

**Weekend:**
- Office hours prep (if scheduled next week)
- Conference talk prep
- Long-form content drafting

---

## Brand Voice Checklist

Every piece of content must satisfy:

- [ ] **Constraint-first:** Lead with the problem/limit, not the solution
- [ ] **Code-first:** Show real, runnable code, not abstractions
- [ ] **Evidence-driven:** Include metrics, measurements, concrete numbers
- [ ] **Honest status:** Mark features as implemented/roadmap/future
- [ ] **Respect both personas:** Serve P1 (BEAM natives) and P2 (migrators)
- [ ] **No hype:** Avoid "revolutionary," "seamless," "effortless," etc.
- [ ] **Production focus:** Address real operational concerns (failures, costs, scale)
- [ ] **Link to proof:** Every claim links to example, benchmark, or code

---

## Metrics Dashboard

Track weekly/monthly:

### Website
- Unique visitors
- Page views (Home, Examples, Benchmarks, Getting Started)
- Time on page
- Bounce rate
- Top referrers

### Content
- Blog post views
- Video watch time + retention
- Social engagement rate (likes, shares, comments per post)
- Click-through rate on CTAs

### Community
- Discord/Slack members (total + active)
- Office hours attendance
- Community examples submitted
- ElixirForum thread engagement

### Adoption
- Hex package downloads (total + weekly)
- GitHub stars, forks, issues
- HexDocs page views
- Production deployments known

### Events
- CFP submissions
- Talk acceptances
- Workshop attendees
- Talk video views

---

## Resources & Tools

### Content Creation
- **Writing:** Markdown editor, site CMS
- **Video:** OBS Studio, ScreenFlow, or similar
- **Editing:** DaVinci Resolve, iMovie, or similar
- **Graphics:** Figma, Excalidraw for diagrams
- **Social:** Buffer, Typefully, or native scheduling

### Analytics
- **Website:** Plausible, Google Analytics
- **Video:** YouTube Analytics
- **Social:** Native analytics + SocialBlade
- **Hex:** Hex.pm stats dashboard

### Community
- **Chat:** Discord or Slack
- **Office Hours:** Zoom, Google Meet, or StreamYard
- **Email:** ConvertKit, Mailchimp (if newsletter)

### Distribution
- **Blog mirrors:** Dev.to, Medium
- **Video:** Elixir Mentor YouTube (8.5k subscribers)
- **Social:** 
  - AgentJidoX (automated posting)
  - Mike Hostetler's account (release announcements)
  - LinkedIn, Mastodon (optional)
- **Forums:** 
  - ElixirForum (automated release announcements via partnership)
  - r/elixir (primary traffic driver)
  - Hacker News (selective)
- **Community:** The Swarm - Elixir AI Collective (Discord)
- **Lists:** Awesome Elixir AI (in AgentJido repo)

---

## Risk Mitigation

### Risk: Content backlog without shipping
**Mitigation:**
- Small, visible P0 backlog (max 6-8 items)
- Block out time for content creation
- One example → one post + one video minimum before moving on

### Risk: Over-indexing on P1, alienating P2
**Mitigation:**
- For every P1 post, create one P2-focused piece
- Track persona balance in metrics
- Survey community for pain points

### Risk: Comparison content drifts into hype/mudslinging
**Mitigation:**
- Compare architecture and failure modes, not marketing claims
- Always show code and numbers
- Review against brand voice checklist before publishing

### Risk: Community support burden grows too fast
**Mitigation:**
- Document "How to ask a good question" upfront
- Keep channels focused and few
- Build FAQ from common questions
- Encourage community answers, not just core team

### Risk: Conference talk rejections
**Mitigation:**
- Submit to multiple venues
- Start with local meetups for practice
- Record and publish talks independently
- Adapt rejected talks into blog series

---

## Success Criteria by Phase

### Phase 1 (Weeks 1-6): ✅ Launch Complete
- Website live with core pages
- 5 blog posts + 4 videos published
- Discord/Slack launched with 50+ members
- 100+ Hex downloads
- First office hours held

### Phase 2 (Weeks 7-12): ✅ Foundation Proven
- 10 blog posts + 10 videos published
- 100+ Discord members
- 500+ Hex downloads
- 2 CFPs submitted
- 3 office hours held
- 2+ community examples

### Phase 3 (Months 4-6): ✅ Scale & Trust
- 16 blog posts published
- All 18 examples live
- 200+ Discord members
- 1k+ Hex downloads
- 1-2 conference talks delivered
- 2 case studies published
- Workshop delivered

### Phase 4 (Months 7-12): ✅ Sustainable Growth
- Consistent monthly cadence
- 5k+ Hex downloads/month
- 500+ Discord members
- 5+ case studies
- 5+ conference talks total
- Active contributor community

---

## Next Actions (This Week)

### Immediate (Week 1)
1. [ ] Finalize website deployment
2. [ ] Publish Hex package v0.1.0
3. [ ] Set up Discord/Slack
4. [ ] Write launch announcement post
5. [ ] Record "First Jido Agent" video
6. [ ] Prepare launch social threads

### Week 2
1. [ ] Publish Blog Post 1 (Introducing Jido)
2. [ ] Upload Video 1 to YouTube
3. [ ] Post launch threads on X, LinkedIn, ElixirForum, r/elixir
4. [ ] Start Blog Post 2 (Agents as Processes)
5. [ ] Engage with community questions

### Week 3
1. [ ] Publish Blog Post 2
2. [ ] Record Video 2 (architecture explainer)
3. [ ] Publish Examples 1-3 to workbench
4. [ ] Start Blog Post 3 (First Jido Agent deep dive)
5. [ ] Schedule first office hours

### Week 4
1. [ ] Publish Blog Post 3
2. [ ] Hold first office hours
3. [ ] Record and clip office hours
4. [ ] Start benchmark write-up (Blog Post 4)
5. [ ] Social: highlight office hours + community

---

## Appendix: Template Library

### Blog Post Template

```markdown
# [Constraint-First Title]

[Opening paragraph: constraint or failure mode, then solution]

## What This Demonstrates

- Concrete pattern or feature
- Production relevance
- Numbers/metrics where applicable

## [Section 1: Problem/Context]

[Set up the constraint or requirement]

## [Section 2: Code Walkthrough]

[Show actual code, explain key parts]

## [Section 3: Production Considerations]

[Failure modes, observability, cost, etc.]

## [Section 4: Metrics/Proof]

[Numbers, graphs, benchmarks]

## Next Steps

- Link to relevant example
- Link to related posts
- Link to HexDocs
```

### Social Thread Template

```
[Hook: Constraint or surprising claim]

Most agent frameworks [common assumption].

Jido [different approach]. Here's why:

1/ [Architecture point with code snippet]

2/ [Production benefit with metric]

3/ [Failure scenario handled]

[CTA: link to example or post]
```

### CFP Abstract Template

```
Title: [Production-Focused, Benefit-Clear]

Abstract:
Most multi-agent systems assume [constraint]. This fails when [production reality].

This talk shows how BEAM's [unique property] changes [key aspect].

You'll see:
- Live demo: [specific example with numbers]
- Architecture: [key pattern or diagram]
- Production: [failure scenario and handling]

Attendees will learn:
- [Concrete takeaway 1]
- [Concrete takeaway 2]
- [Concrete takeaway 3]

[Include speaker bio and relevant credentials]
```

---

## Revision History

- **2025-12-23:** Initial roadmap created
- **2025-12-23:** Updated with existing partnerships and assets:
  - Elixir Mentor YouTube partnership
  - The Swarm - Elixir AI Collective (Discord)
  - AgentJidoX and Mike Hostetler social accounts
  - Elixir Reddit and Forum presence
  - ASH framework partnership
  - Awesome Elixir AI list
  - Plausible analytics
  - Roadmap voting exploration (GitHub Discussions)
- **Next review:** End of Phase 1 (Week 6)

---

**This is a living document. Update after each phase completion to reflect learnings and adjust priorities.**

---

## Partnerships & Ecosystem

### Active Partnerships

**Elixir Mentor (YouTube)**
- 8,500 subscribers in Elixir community
- Open offer to record and publish videos
- Status: ReqLLM video series in progress
- Plans: Jido tutorial series (Examples 2, 3, 7, 9, 10, 13)
- Contact: Coordinate recording schedule monthly
- Deliverables: 1-2 videos per month

**ASH Framework**
- Close partnership with declarative data framework
- Focus: Compatibility with ASH ecosystem
- Content opportunities:
  - [ ] "Jido + ASH: Declarative Agents with Data Integrity"
  - [ ] Integration guide on both docs sites
  - [ ] Joint case study or demo
  - [ ] Cross-promotion in release announcements

**ElixirForum**
- Automated release announcements for relevant packages
- Status: Partnership active
- Process: Releases auto-posted to forum
- Engagement: Respond to threads, support questions

### Community Contributors

**Strategy:**
- Highlight breadth of community and contributors
- Feature community examples prominently
- Acknowledge contributors in:
  - Release notes
  - Blog posts
  - Social posts
  - `/community` page
  - Awesome Elixir AI list

**Preferred Packages (Not Owned by Jido):**
- Document and maintain compatibility
- Feature in examples where applicable
- Acknowledge in docs and blog posts
- Consider integration guides for popular packages
- Examples:
  - ASH framework
  - Telemetry libraries
  - Observability tools
  - Vector databases (pgvector, etc.)
  - [Add others as partnerships form]

### Awesome Elixir AI List

**Location:** AgentJido GitHub repo

**Maintenance:**
- [ ] Update with each new Jido package release
- [ ] Add community examples and projects
- [ ] Highlight partner integrations (ASH, etc.)
- [ ] Include tutorial links (Elixir Mentor videos)
- [ ] Feature case studies and production deployments
- [ ] Keep sections organized: Frameworks, Libraries, Tools, Learning Resources

**Sections:**
```markdown
## Frameworks
- Jido - Production-ready multi-agent framework
- [Add community frameworks]

## Libraries
- ReqLLM - HTTP client for LLM APIs
- LLMDB - Model registry and metadata
- [Add community libraries]

## Integrations
- ASH Framework - Declarative data layer
- [Add partner integrations]

## Learning
- Elixir Mentor YouTube - Video tutorials
- [Add community tutorials]

## Production Deployments
- [Feature case studies]
```

---

## Automated Systems

### AgentJidoX (Twitter/X)

**Automation:**
- Release announcements for:
  - jido packages
  - jido_ai packages
  - req_llm updates
  - llmdb updates
- New blog post publications
- New Elixir Mentor video releases
- Example of the Month winners
- Office hours announcements

**Manual Posts:**
- Technical threads with code
- "Failure Mode Friday" series
- Community highlights
- Conference announcements

### Mike Hostetler's Account

**Purpose:**
- Personal perspective on development
- Release announcements with context
- Community engagement
- Conference updates
- Behind-the-scenes content

**Cadence:**
- Release announcements: same-day as package publish
- Weekly: 1-2 technical or community posts
- Monthly: development update thread

### ElixirForum Release Automation

**Process:**
- Automated post when packages published to Hex
- Template includes:
  - Version number
  - Changelog highlights
  - Link to full changelog
  - Link to HexDocs
  - Link to relevant examples

**Packages:**
- jido
- jido_ai
- req_llm
- llmdb
- jido_action
- jido_signal
- jido_coder (when ready)

---

## Platform-Specific Strategies

### Elixir Reddit (Primary Traffic Driver)

**Priority:** HIGH (drives most traffic)

**Content Types:**
- Launch announcements with benchmarks
- Benchmark posts with graphs/numbers
- Tutorial releases (Elixir Mentor videos)
- Case studies and production stories
- "Show HN" style posts (working examples)

**Guidelines:**
- Lead with code or numbers, not marketing
- Include working Livebook when possible
- Respond to all comments within 24 hours
- Cross-link to examples and docs
- Highlight community contributions

**Cadence:**
- Launch: Detailed post with benchmarks
- Monthly: Major release or tutorial
- Quarterly: Case study or production story
- As needed: Community highlights, significant updates

### The Swarm - Elixir AI Collective (Discord)

**Channels:**
- `#announcements` - Releases, videos, blog posts
- `#jido` - Jido-specific discussions
- `#examples` - Share Livebooks and patterns
- `#production-incidents` - War stories (on-brand)
- `#integrations` - ASH, pgvector, telemetry, etc.
- `#help` - Support questions
- `#off-topic` - Community building

**Programs:**
- Monthly office hours (voice + screenshare)
- Example of the Month contest
- Community contributor highlights
- Partner announcements (ASH, etc.)
- AMA sessions for major releases

**Moderation:**
- Encourage "show your work" posts
- Pin high-quality examples
- Maintain FAQ based on common questions
- Keep discussions production-focused

### Elixir Mentor YouTube

**Video Series Structure:**

**ReqLLM Series (Foundation):**
1. "LLM API Calls from Elixir with ReqLLM"
2. "Model Selection with LLMDB"
3. "Streaming LLM Responses"
4. "Error Handling and Retries"

**Jido Core Series:**
1. "First Jido Agent in 10 Minutes" (Example 2)
2. "Tool-Using Agents with JidoAI" (Example 3)
3. "Validated Actions with jido_action" (Example 4)
4. "Agent Communication with jido_signal" (Example 5)

**Multi-Agent Series:**
1. "Manager-Worker Pattern" (Example 7)
2. "Long-Lived Workflow Agents" (Example 9)
3. "10,000 Agents on a Single Node" (Flagship)

**Production Series:**
1. "Observability and Telemetry" (Example 10)
2. "Fault Tolerance and Supervision" (Example 11)
3. "Distributed Agents Across Nodes" (Example 13)

**Advanced Series:**
1. "Cost-Aware Planning" (Example 14)
2. "Human-in-the-Loop Workflows" (Example 16)
3. "Testing Agents with Livebooks" (Example 18)

**Publishing Schedule:**
- Phase 1 (Weeks 1-6): ReqLLM series + Jido Core (1-2 videos/week)
- Phase 2 (Weeks 7-12): Multi-Agent series (1 video/week)
- Phase 3 (Months 4-6): Production + Advanced series (2 videos/month)

---

## Analytics & Instrumentation

### Plausible Analytics (Website)

**Already Installed:** ✅

**Instrumentation Checklist:**
- [ ] Verify tracking on all pages (Home, Examples, Benchmarks, etc.)
- [ ] Custom events for:
  - [ ] Example Livebook downloads
  - [ ] "Run in Livebook" button clicks
  - [ ] HexDocs external link clicks
  - [ ] Elixir Mentor video embeds (play events)
  - [ ] GitHub repo clicks
  - [ ] Discord join clicks
- [ ] Goal tracking:
  - [ ] Getting Started → First Example completion
  - [ ] Example page → Livebook download
  - [ ] Blog post → Example click-through
- [ ] Funnel tracking:
  - Landing → Getting Started → First Example → Discord
- [ ] Referrer tracking (verify Reddit, Forum, Twitter/X show up)

**Monthly Reports:**
- Top traffic sources (expect: Reddit, ElixirForum, Twitter/X)
- Most viewed examples
- Conversion rates (page → example → community)
- Geographic distribution
- Device/browser stats

### Distribution Metrics

**Track for Each Channel:**

| Channel | Metric | Goal (Month 6) |
|---------|--------|----------------|
| **Elixir Reddit** | Post upvotes | 50+ per major post |
| **Elixir Reddit** | Comments/engagement | 20+ per post |
| **Elixir Reddit** | Click-through rate | 10%+ |
| **ElixirForum** | Thread views | 500+ per release |
| **ElixirForum** | Replies | 10+ per major thread |
| **AgentJidoX** | Impressions | 10k+ per month |
| **AgentJidoX** | Engagement rate | 3%+ |
| **Mike's Account** | Retweets | 20+ per major post |
| **Elixir Mentor** | Video views | 500+ per video |
| **Elixir Mentor** | Watch time % | 60%+ |
| **The Swarm Discord** | Active members | 200+ |
| **The Swarm Discord** | Messages/week | 100+ |

---

## Roadmap Voting & Feedback

### Challenge
- No user accounts
- No database
- Need transparent, low-friction voting

### Options to Explore

**Option 1: GitHub Discussions (Recommended)**
- Pros:
  - No database needed
  - Built-in voting (👍 reactions)
  - Threaded discussions
  - Integrates with GitHub repo
  - Public and transparent
- Cons:
  - Requires GitHub account
- Implementation:
  - [ ] Enable Discussions in AgentJido repo
  - [ ] Create "Roadmap" category
  - [ ] Post each roadmap item as discussion
  - [ ] Link from `/roadmap` page on site
  - [ ] Sort by reaction count
  - [ ] Monthly: review top-voted items

**Option 2: GitHub Issues with Labels**
- Pros:
  - Already have issues
  - Voting via 👍 reactions
  - Can track in project board
- Cons:
  - Issues are for bugs/features, not pure voting
- Implementation:
  - Use `roadmap` label
  - Feature requests use `roadmap` + priority labels
  - Close issues when implemented

**Option 3: Canny.io or Similar (Hosted)**
- Pros:
  - Purpose-built for roadmap voting
  - No account required (email only)
  - Nice UI
- Cons:
  - External service
  - Potential cost
  - Not as integrated with GitHub

**Option 4: Simple Poll in The Swarm Discord**
- Pros:
  - Community is already there
  - Discord native polls
  - Quick feedback
- Cons:
  - Not public (requires Discord membership)
  - Hard to track over time

### Recommended Approach

**Phase 1: GitHub Discussions**
- [ ] Enable Discussions in AgentJido repo
- [ ] Create categories:
  - Roadmap (voting on features)
  - Examples (community examples)
  - Q&A (support)
  - Show & Tell (community projects)
- [ ] Add `/roadmap` page on site:
  - List current roadmap items
  - Link each to GitHub Discussion
  - Show vote counts (manually updated or via GitHub API)
  - Include "suggest a feature" link

**Phase 2: Enhance with API**
If adoption grows:
- [ ] Build simple GitHub API integration
- [ ] Auto-fetch discussion vote counts
- [ ] Display on `/roadmap` page dynamically
- [ ] Still stateless—no database needed
- [ ] Cache in browser or edge (Cloudflare Workers, etc.)

### Roadmap Page Structure

```markdown
# Jido Roadmap

We build in public. Vote on features via GitHub Discussions.

## In Progress
- [Feature X](link to discussion) - 45 votes
- [Feature Y](link to discussion) - 32 votes

## Planned (Vote to Prioritize)
- [Feature A](link to discussion) - 28 votes
- [Feature B](link to discussion) - 19 votes
- [Feature C](link to discussion) - 12 votes

## Completed
- ✅ Feature 1 (v0.1.0)
- ✅ Feature 2 (v0.2.0)

[Suggest a Feature →](GitHub Discussions link)
```

**Update Cadence:**
- Weekly: Check vote counts
- Monthly: Review and reprioritize based on votes
- Quarterly: Major roadmap review with community input

---

## Revision History

- **2025-12-23:** Initial roadmap created
- **2025-12-23:** Updated with existing partnerships and assets:
  - Elixir Mentor YouTube partnership
  - The Swarm - Elixir AI Collective (Discord)
  - AgentJidoX and Mike Hostetler social accounts
  - Elixir Reddit and Forum presence
  - ASH framework partnership
  - Awesome Elixir AI list
  - Plausible analytics
  - Roadmap voting exploration (GitHub Discussions)
- **Next review:** End of Phase 1 (Week 6)


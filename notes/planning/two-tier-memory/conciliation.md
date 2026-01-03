# Parallel Development Conciliation: Tooling vs Two-Tier Memory

This document analyzes potential conflicts between parallel implementation of the tooling system (`notes/planning/tooling/`) and the two-tier memory system (`notes/planning/two-tier-memory/`).

## Overview

These are two largely independent systems with minimal overlap. The tooling system lives in `lib/jido_code/tools/`, the memory system lives in `lib/jido_code/memory/`. There are **3-4 specific conflict points** requiring coordination.

## Architecture Comparison

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          TOOLING SYSTEM                                      │
│  Directory: lib/jido_code/tools/                                            │
│                                                                              │
│  Tool Executor → Lua Sandbox → Bridge Functions → Security Module           │
│                                                                              │
│  Key Files:                                                                  │
│  - executor.ex (dispatch through sandbox)                                   │
│  - manager.ex (Lua sandbox GenServer)                                       │
│  - bridge.ex (Elixir functions exposed to Lua)                              │
│  - security.ex (path/command validation)                                    │
│  - registry.ex (ETS-backed tool registration)                               │
│  - definitions/*.ex (tool schemas)                                          │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                          MEMORY SYSTEM                                       │
│  Directory: lib/jido_code/memory/                                           │
│                                                                              │
│  Session.State Extensions → Memory Facade → Triple Store                    │
│                                                                              │
│  Key Files:                                                                  │
│  - types.ex (shared type definitions)                                       │
│  - short_term/*.ex (working context, pending memories, access log)          │
│  - long_term/*.ex (store manager, triple store adapter, vocab)              │
│  - actions/*.ex (remember, recall, forget Jido Actions)                     │
│  - context_builder.ex, response_processor.ex, token_counter.ex              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Conflict Point 1: `lib/jido_code/tools/executor.ex`

**Conflict Level: MEDIUM**

| Team | Modification |
|------|-------------|
| Tooling | Routes all tool calls through Lua sandbox (core execution path) |
| Memory | Phase 4 adds memory action routing for `remember`, `recall`, `forget` |

### Analysis

Memory tools use Jido Actions pattern, not the Lua sandbox. This is intentional - memory tools are trusted internal operations that don't need security sandboxing like file/shell tools.

### Resolution

Add conditional check before Lua dispatch:

```elixir
@memory_tools ["remember", "recall", "forget"]

def execute_tool(name, args, context) when name in @memory_tools do
  # Direct to Jido Actions - bypass Lua sandbox
  {:ok, action_module} = Memory.Actions.get(name)
  action_module.run(args, context)
end

def execute_tool(name, args, context) do
  # Standard Lua sandbox path for all other tools
  Tools.Manager.execute(name, args, context)
end
```

### Coordination Required

- Both teams agree on the guard clause pattern before either modifies executor.ex
- Memory team adds the conditional; tooling team ensures their changes don't break it

---

## Conflict Point 2: `lib/jido_code/agents/llm_agent.ex`

**Conflict Level: LOW-MEDIUM**

| Team | Modification |
|------|-------------|
| Tooling | Not directly modifying (tools registered via Registry, agent reads from it) |
| Memory | Phase 4: Register memory tools in available tools list |
| Memory | Phase 5: Add context assembly before LLM calls, response processing after |

### Analysis

Tooling team uses the existing Registry pattern - tools are registered in `Tools.Registry` and LLMAgent reads from it. Memory team adds:

- `memory_enabled` configuration field
- `get_available_tools/1` conditionally includes memory tools
- `build_system_prompt/2` adds memory context section
- `broadcast_stream_end/4` triggers ResponseProcessor

### Resolution

No direct conflict. Memory team owns LLMAgent modifications. Tooling team's tools appear via Registry without touching LLMAgent.

### Coordination Required

- Minimal - just ensure both teams know the division of responsibility
- Memory team should not break existing tool availability from Registry

---

## Conflict Point 3: `lib/jido_code/session/state.ex`

**Conflict Level: NONE**

| Team | Modification |
|------|-------------|
| Tooling | Not modifying |
| Memory | Phase 1: Adds `working_context`, `pending_memories`, `access_log` fields + callbacks |

### Analysis

Tooling system doesn't interact with Session.State directly. Tools operate through the sandbox with project_root context, not session state.

### Resolution

No conflict. Memory team owns all Session.State changes.

---

## Conflict Point 4: Application Supervision Tree

**Conflict Level: COORDINATION NEEDED**

| Team | Addition |
|------|----------|
| Tooling | `Tools.Manager` already exists in supervision tree |
| Memory | Phase 2: Adds `Memory.Supervisor` (manages StoreManager per session) |

### Analysis

Both systems add supervised processes. Ordering matters for startup dependencies.

### Resolution

Coordinate supervision tree in `application.ex`:

```elixir
children = [
  # Core infrastructure
  {Phoenix.PubSub, name: JidoCode.PubSub},

  # Tool system (already exists)
  JidoCode.Tools.Registry,
  JidoCode.Tools.Manager,

  # Memory system (new - Phase 2)
  JidoCode.Memory.Supervisor,

  # Session management (depends on both)
  JidoCode.SessionSupervisor,
  JidoCode.SessionRegistry
]
```

### Coordination Required

- When Memory Phase 2 adds supervisor, coordinate ordering with tooling team
- Memory.Supervisor should start after Tools.Manager (tools may be used during memory operations)

---

## Conflict Point 5: Tool Registration Patterns

**Conflict Level: DESIGN ALIGNMENT (No Code Conflict)**

| Team | Pattern |
|------|---------|
| Tooling | `Tools.Registry` (ETS-backed) for tool definitions |
| Memory | `Jido.Action` pattern with `Memory.Actions` module |

### Analysis

Different patterns that coexist by design:

- **Standard tools** (file, shell, web): Use Registry + Lua sandbox for security
- **Memory tools**: Use Jido Actions for framework integration, bypass sandbox (trusted)

### Resolution

No code conflict. This is intentional architectural separation:

```
Standard Tools:  LLM → Executor → Lua Sandbox → Bridge → Security → Operation
Memory Tools:    LLM → Executor → Jido Action → Memory Facade → Triple Store
```

---

## Summary: File Ownership Matrix

| File | Tooling Team | Memory Team | Conflict |
|------|--------------|-------------|----------|
| `lib/jido_code/tools/executor.ex` | Core routing | Action routing | **MEDIUM** |
| `lib/jido_code/agents/llm_agent.ex` | — | Context + tools | **LOW** |
| `lib/jido_code/session/state.ex` | — | Memory fields | **NONE** |
| `lib/jido_code/application.ex` | — | Supervisor | **COORDINATION** |
| `lib/jido_code/tools/**` | All files | — | **NONE** |
| `lib/jido_code/memory/**` | — | All files | **NONE** |
| `test/jido_code/tools/**` | All tests | — | **NONE** |
| `test/jido_code/memory/**` | — | All tests | **NONE** |
| `test/jido_code/tools/executor_test.exs` | Tool tests | Action routing tests | **ADDITIVE** |

---

## Recommendations for Parallel Development

### 1. Pre-Development Agreement

Before starting parallel work, both teams agree on:

- [ ] Executor.ex guard clause pattern for memory tools
- [ ] Supervision tree ordering in application.ex
- [ ] Branch naming convention

### 2. Branch Strategy

```
main
├── develop (integration branch)
│   ├── feature/tools-phase-1
│   ├── feature/tools-phase-2
│   ├── feature/tools-phase-3
│   ├── feature/tools-phase-4
│   ├── feature/tools-phase-5
│   ├── feature/tools-phase-6
│   ├── feature/memory-phase-1
│   ├── feature/memory-phase-2
│   ├── feature/memory-phase-3
│   ├── feature/memory-phase-4  ← executor.ex conflict here
│   ├── feature/memory-phase-5
│   └── feature/memory-phase-6
```

- Regular integration to `develop` branch (weekly minimum)
- Memory Phase 4 should integrate after coordinating with tooling team on executor.ex

### 3. Integration Points

| Memory Phase | Integration Dependency |
|--------------|----------------------|
| Phase 1 | None - independent Session.State changes |
| Phase 2 | Coordinate supervisor ordering with tooling |
| Phase 3 | None - internal to memory system |
| Phase 4 | **Coordinate executor.ex changes with tooling team** |
| Phase 5 | None - LLMAgent changes are memory-owned |
| Phase 6 | None - internal to memory system |

### 4. Test Strategy

- Each team owns their test files
- Shared file tests (executor_test.exs) use additive test modules:
  ```elixir
  # In executor_test.exs
  describe "standard tool execution" do
    # Tooling team's tests
  end

  describe "memory action routing" do
    # Memory team's tests
  end
  ```

---

## Git Workflow for Parallel Development

This section details the git-based workflow to prevent teams from overwriting each other's changes.

### 1. Branch Structure

```
main (protected - production releases only)
│
└── develop (integration branch - both teams merge here)
    │
    ├── tooling/phase-1
    ├── tooling/phase-2
    ├── tooling/phase-3
    ├── tooling/phase-4
    ├── tooling/phase-5
    ├── tooling/phase-6
    │
    ├── memory/phase-1
    ├── memory/phase-2
    ├── memory/phase-3
    └── memory/phase-4   ← Conflict point with executor.ex
```

### 2. Git Worktree Setup

Each team uses a dedicated git worktree to avoid branch switching and enable parallel development in isolated directories.

#### Directory Structure

```
~/code/agentjido/
├── jido_code/                    ← Main repository (develop branch)
│   ├── .git/                     ← Shared git directory
│   └── ...
├── jido_code-tooling/            ← Tooling team worktree
│   └── (full checkout)
└── jido_code-memory/             ← Memory team worktree
    └── (full checkout)
```

#### Initial Setup (Team Lead / DevOps)

Starting from the main repository where Team A was working on `develop`:

```bash
# Ensure develop is up to date
cd ~/code/agentjido/jido_code
git checkout develop
git pull origin develop

# Create the tooling team worktree (branching from develop)
git worktree add ../jido_code-tooling tooling/phase-1 -b tooling/phase-1

# Create the memory team worktree (branching from develop)
git worktree add ../jido_code-memory memory/phase-1 -b memory/phase-1

# Verify worktrees
git worktree list
```

Expected output:
```
/home/user/code/agentjido/jido_code           xxxxxxx [develop]
/home/user/code/agentjido/jido_code-tooling   xxxxxxx [tooling/phase-1]
/home/user/code/agentjido/jido_code-memory    xxxxxxx [memory/phase-1]
```

#### Tooling Team Setup

```bash
# Navigate to tooling worktree
cd ~/code/agentjido/jido_code-tooling

# Verify you're on the correct branch
git branch --show-current
# Output: tooling/phase-1

# Install dependencies (each worktree needs its own _build and deps)
mix deps.get
mix compile

# Open in IDE
code .   # or your preferred editor
```

#### Memory Team Setup

```bash
# Navigate to memory worktree
cd ~/code/agentjido/jido_code-memory

# Verify you're on the correct branch
git branch --show-current
# Output: memory/phase-1

# Install dependencies
mix deps.get
mix compile

# Open in IDE
code .
```

#### Switching Phases

When a team completes a phase and needs to start the next:

```bash
# Tooling team: switch from phase-1 to phase-2
cd ~/code/agentjido/jido_code-tooling

# First, ensure current work is committed/pushed
git status
git push origin tooling/phase-1

# Create new branch for next phase (from current branch)
git checkout -b tooling/phase-2

# Or from develop (to include integrated changes)
git fetch origin develop
git checkout -b tooling/phase-2 origin/develop
```

#### Syncing with Develop

Each team should regularly sync with develop to get the other team's merged changes:

```bash
# In your team's worktree
git fetch origin develop
git rebase origin/develop

# Resolve any conflicts, then continue
mix deps.get  # if deps changed
mix compile
mix test
```

#### Worktree Maintenance Commands

```bash
# List all worktrees
git worktree list

# Remove a worktree (from main repo)
cd ~/code/agentjido/jido_code
git worktree remove ../jido_code-tooling

# Prune stale worktree references
git worktree prune

# Move a worktree to a new location
git worktree move ../jido_code-tooling ../new-location
```

#### Important Notes

1. **Shared .git directory**: All worktrees share the same `.git` folder, so refs and objects are shared
2. **Independent working directories**: Each worktree has its own `_build/`, `deps/`, and working files
3. **Branch lock**: A branch checked out in one worktree cannot be checked out in another
4. **Push from any worktree**: You can push to origin from any worktree

### 3. CODEOWNERS Configuration

Create `.github/CODEOWNERS` to require approval from both teams on shared files (works with worktrees since all push to same origin):

```
# Default owners
* @team-lead

# Tooling team owns tools directory
/lib/jido_code/tools/ @tooling-team

# Memory team owns memory directory
/lib/jido_code/memory/ @memory-team

# SHARED FILES - Require BOTH teams to approve
/lib/jido_code/tools/executor.ex @tooling-team @memory-team
/lib/jido_code/agents/llm_agent.ex @tooling-team @memory-team
/lib/jido_code/application.ex @tooling-team @memory-team
```

This ensures PRs touching shared files cannot be merged without both teams reviewing.

### 4. Integration Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                     DAILY WORKFLOW                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Tooling Team                    Memory Team                    │
│       │                               │                         │
│       ▼                               ▼                         │
│  tooling/phase-N                 memory/phase-N                 │
│       │                               │                         │
│       └───────────┬───────────────────┘                         │
│                   │                                              │
│                   ▼                                              │
│              develop                                             │
│          (integration branch)                                    │
│                   │                                              │
│                   ▼                                              │
│            CI runs tests                                         │
│                   │                                              │
│        ┌─────────┴─────────┐                                    │
│        ▼                   ▼                                    │
│    Pass → Ready       Fail → Fix conflicts                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 5. Conflict Prevention Rules

| Rule | Implementation |
|------|----------------|
| **Rebase before merge** | Teams must `git pull --rebase origin develop` before pushing |
| **Small, frequent merges** | Merge to develop at least every 2-3 days |
| **Shared file lock** | Before modifying shared files, announce in team channel |
| **ADR-first for shared files** | Write ADR before touching executor.ex, llm_agent.ex |

### 6. Pre-Merge CI Check

Add a CI workflow to detect shared file conflicts early:

```yaml
# .github/workflows/conflict-check.yml
name: Shared File Conflict Check

on:
  pull_request:
    paths:
      - 'lib/jido_code/tools/executor.ex'
      - 'lib/jido_code/agents/llm_agent.ex'
      - 'lib/jido_code/application.ex'

jobs:
  check-conflicts:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Check for conflicts with develop
        run: |
          git fetch origin develop
          if ! git merge-tree $(git merge-base HEAD origin/develop) HEAD origin/develop | grep -q "^<<<<<<<"; then
            echo "✅ No conflicts detected"
          else
            echo "⚠️ CONFLICT: Shared file modified by both branches"
            echo "Coordinate with the other team before merging"
            exit 1
          fi
```

### 7. Shared File Modification Protocol

When any team needs to modify a shared file:

```
┌─────────────────────────────────────────────────────────────────┐
│            SHARED FILE MODIFICATION PROTOCOL                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. ANNOUNCE: Post in #jido-code-dev channel                    │
│     "Memory team needs to modify executor.ex for Phase 4"       │
│                                                                  │
│  2. SYNC: Both teams pull latest develop                        │
│     git checkout develop && git pull                            │
│                                                                  │
│  3. BRANCH: Create coordination branch                          │
│     git checkout -b coord/executor-memory-routing               │
│                                                                  │
│  4. IMPLEMENT: Make changes with both teams aware               │
│                                                                  │
│  5. REVIEW: PR requires approval from BOTH teams                │
│                                                                  │
│  6. MERGE: Merge to develop first, then both teams rebase       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 8. Memory Phase 4 Sync Point

Since Memory Phase 4 will touch `executor.ex`, this is a known sync point:

```
Timeline:
─────────────────────────────────────────────────────────────────►

Tooling: [Phase 1]──[Phase 2]──[Phase 3]──[Phase 4]──[Phase 5]──►
                                    │
                                    │ SYNC POINT
                                    ▼
Memory:  [Phase 1]──[Phase 2]──[Phase 3]──┤
                                          │
                                    ┌─────▼─────┐
                                    │   ADR +   │
                                    │ Executor  │
                                    │  Changes  │
                                    └─────┬─────┘
                                          │
                                    [Phase 4 cont]──[Phase 5]──►
```

**Before Memory Phase 4 begins:**

1. [ ] Both teams sync to develop
2. [ ] Write ADR together (see `notes/decisions/XXXX-memory-tool-executor-routing.md`)
3. [ ] Tooling team completes any pending executor.ex changes
4. [ ] Memory team adds routing guard clause on coordination branch
5. [ ] Both teams approve PR
6. [ ] Merge to develop
7. [ ] Both teams rebase their feature branches
8. [ ] Continue parallel work

### 9. Git Commands Quick Reference (Worktree Workflow)

```bash
# ─────────────────────────────────────────────────────────────────
# TOOLING TEAM (in ~/code/agentjido/jido_code-tooling)
# ─────────────────────────────────────────────────────────────────

# Before starting work each day
cd ~/code/agentjido/jido_code-tooling
git fetch origin develop
git rebase origin/develop
mix deps.get && mix compile

# Regular work - commit and push
git add .
git commit -m "feat(tools): description"
git push origin tooling/phase-N

# Create PR to develop
gh pr create --base develop --title "Tooling Phase N" --body "..."

# ─────────────────────────────────────────────────────────────────
# MEMORY TEAM (in ~/code/agentjido/jido_code-memory)
# ─────────────────────────────────────────────────────────────────

# Before starting work each day
cd ~/code/agentjido/jido_code-memory
git fetch origin develop
git rebase origin/develop
mix deps.get && mix compile

# Regular work - commit and push
git add .
git commit -m "feat(memory): description"
git push origin memory/phase-N

# Create PR to develop
gh pr create --base develop --title "Memory Phase N" --body "..."

# ─────────────────────────────────────────────────────────────────
# SHARED FILE COORDINATION (either worktree)
# ─────────────────────────────────────────────────────────────────

# Step 1: Sync with develop first
git fetch origin develop
git rebase origin/develop

# Step 2: Create coordination branch
git checkout -b coord/executor-memory-routing

# Step 3: Make shared file changes
# ... edit executor.ex ...

# Step 4: Push and create PR requiring both teams
git push -u origin coord/executor-memory-routing
gh pr create --base develop \
  --title "Coordination: Memory tool executor routing" \
  --body "Requires approval from both @tooling-team and @memory-team"

# Step 5: After merge, both teams sync
# (in each worktree)
git fetch origin develop
git rebase origin/develop

# ─────────────────────────────────────────────────────────────────
# WORKTREE MANAGEMENT (from main repo)
# ─────────────────────────────────────────────────────────────────

cd ~/code/agentjido/jido_code

# List all worktrees
git worktree list

# Add new worktree for a new phase
git worktree add ../jido_code-tooling-phase2 tooling/phase-2 -b tooling/phase-2

# Remove completed worktree
git worktree remove ../jido_code-tooling

# Clean up stale references
git worktree prune
```

---

## Conclusion

These systems are architecturally orthogonal. The only meaningful integration point is the executor routing decision in Phase 4, which requires a ~5-10 line change. With proper coordination on that single file, both teams can work in parallel with minimal friction.

**Risk Assessment: LOW** - Parallel development is feasible with the coordination points outlined above.

**Chosen Workflow: Git Worktrees**

Each team operates in a dedicated worktree directory:
- `~/code/agentjido/jido_code-tooling/` - Tooling team
- `~/code/agentjido/jido_code-memory/` - Memory team
- `~/code/agentjido/jido_code/` - Main repo (develop branch, integration)

**Key Safeguards:**
- **Worktrees**: Physical directory separation eliminates accidental branch switching
- **CODEOWNERS**: Shared files require both teams to approve
- **CI conflict check**: Catches issues before merge
- **Shared file protocol**: Coordination happens proactively via `coord/*` branches
- **Phase 4 sync point**: Explicitly documented with checklist and ADR requirement

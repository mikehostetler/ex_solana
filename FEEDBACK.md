# Jido Workspace Strategic Feedback

> Analysis and recommendations for managing the Jido ecosystem monorepo workspace.
> Generated: November 2025

## Executive Summary

The Jido workspace is a sophisticated git subtree-powered monorepo managing 18 Elixir packages. This document provides strategic recommendations for:

1. Coordinating workflow across projects with varying contribution levels
2. Publishing Hex packages with interdependencies
3. Integrating PR-based workflows for OSS collaboration
4. Leveraging AI agents for automation
5. Handling special cases like llm_db's high-frequency updates

---

## Current State Analysis

### Package Inventory

| Package | Version | Hex Status | Contributors | Notes |
|---------|---------|------------|--------------|-------|
| jido | 1.2.0 | ✅ Published | 8 | Core framework |
| jido_signal | 1.0.0 | ✅ Published | 2 | Event/signal system |
| jido_action | 1.0.0 | ❌ Not on Hex | 2 | Action framework |
| jido_ai | 0.5.3 | ✅ Published (0.5.2) | 7 | AI integrations |
| req_llm | 1.0.0-rc.7 | ✅ Published (1.0.0) | **29** | LLM client - high activity |
| jido_keys | 1.0.0 | ✅ Published | 1 | Config/secrets |
| jido_behaviortree | 1.0.0 | ❌ Not on Hex | - | Behavior trees |
| jido_chat | 0.5.0 | ❌ Not on Hex | 1 | Chat system |
| llm_db | - | ❌ Not on Hex | - | Model database - high churn |
| ash_jido | 0.1.0 | ❌ Not on Hex | - | Ash integration |
| depot | 0.5.2 | External | - | File storage (fork) |
| jido_workbench | 0.1.0 | ❌ Private | - | Dev UI |
| jido_eval | 0.1.0 | ❌ Not on Hex | - | Evaluation framework |
| jido_character | 0.1.0 | ❌ Private | - | Character system |
| jido_dialogue | 0.1.0 | ❌ Private | - | Dialogue system |
| jido_htn | 0.1.0 | ❌ Private | - | HTN planning |
| kodo | 0.1.0 | ❌ Private | - | Code generation |
| sparq | 0.1.0 | ❌ Private | - | Query system |

### Dependency Chain

```
jido_signal (foundation)
    │
    ▼
jido_action
    │
    ▼
jido ◄──────────────┐
    │               │
    ▼               │
jido_ai ────────────┤
    │               │
    ▼               │
req_llm ◄── llm_db  │
    │               │
    ▼               │
jido_chat ──────────┘
```

### Current Tooling

| Command | Purpose |
|---------|---------|
| `mix morning` | Pull all + compile |
| `mix sync` | Pull all + test |
| `mix ws.git.pull` | Pull from all upstreams |
| `mix ws.git.push <project>` | Push to upstream |
| `mix ws.git.status` | Show project status |
| `mix ws.git.diff` | Show local vs upstream |
| `mix hex.publish.all <version>` | Publish all Hex packages |
| `mix version.check` | Check version consistency |

---

## Core Principles

### 1. Workspace as Orchestrator, Not Source of Truth

The workspace should be the **coordination layer** for releases and cross-repo work, while individual GitHub repos remain the **collaboration boundary** for PRs and contributors.

```
┌─────────────────────────────────────────────────────────┐
│                    WORKSPACE                             │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐    │
│  │  jido   │  │ jido_ai │  │ req_llm │  │ llm_db  │    │
│  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘    │
│       │            │            │            │          │
│       │    Subtree Push to Feature Branches  │          │
└───────┼────────────┼────────────┼────────────┼──────────┘
        │            │            │            │
        ▼            ▼            ▼            ▼
   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐
   │ GitHub  │  │ GitHub  │  │ GitHub  │  │ GitHub  │
   │  Repo   │  │  Repo   │  │  Repo   │  │  Repo   │
   │  (PRs)  │  │  (PRs)  │  │  (PRs)  │  │  (PRs)  │
   └─────────┘  └─────────┘  └─────────┘  └─────────┘
```

**Key Rule:** All releases, multi-repo refactors, and interdependent changes are driven from the workspace; all OSS collaboration happens via PRs on individual repos.

### 2. Never Push Directly to Main on Public Repos

For `req_llm` and other public packages:
- Always push to `workspace/<feature>` branches
- Open PRs from those branches
- Let CI and review processes run
- Merge via GitHub, then `ws.git.pull` back

### 3. One Version Train for Core Stack

The core packages should share a version number for coherent releases:

```elixir
# All release together as v1.3.0
jido_signal: 1.3.0
jido_action: 1.3.0
jido:        1.3.0
jido_ai:     1.3.0
```

Benefits:
- Users get a simple mental model: "1.3.x of everything works together"
- Reduces combinatorial testing complexity
- Clear upgrade path

### 4. Separate Cadence for High-Churn Packages

`llm_db` and potentially `req_llm` need their own version streams:

```elixir
# llm_db updates frequently (model database)
llm_db: 0.7.x  # Own version stream

# req_llm can track core or be independent
req_llm: 1.x.x  # Consider keeping aligned with core
```

---

## Recommended Process Changes

### Daily Workflow

```bash
# Start of day
mix morning                    # Pull all + compile

# Before multi-repo work
mix ws.git.pull jido jido_ai   # Sync specific projects

# During work
# ... make changes across projects ...

# End of session
mix ws.git.status              # See what changed
mix ws.changes                 # (NEW) Show unpushed commits per project

# For each changed public project
mix ws.git.push.pr req_llm feat-new-provider  # (NEW) Push to workspace/feat-new-provider
# Then open PR on GitHub
```

### Release Workflow

```bash
# 1. Ensure clean state
mix ws.git.pull
mix ws.git.status

# 2. Check versions
mix version.check

# 3. Dry run
mix hex.publish.all 1.3.0 --dry-run

# 4. Publish (when ready)
mix hex.publish.all 1.3.0

# 5. Push changes to feature branches, open PRs
mix ws.git.push.pr jido_signal release-v1.3.0
mix ws.git.push.pr jido_action release-v1.3.0
mix ws.git.push.pr jido release-v1.3.0
mix ws.git.push.pr jido_ai release-v1.3.0

# 6. After PRs merged
git tag v1.3.0
git push --tags
```

### Handling OSS Contributors (req_llm)

```
Contributor Flow:
1. Fork req_llm
2. Create feature branch
3. Open PR to agentjido/req_llm:main
4. CI runs
5. Maintainer reviews & merges
6. Maintainer runs `mix ws.git.pull req_llm` to sync workspace

Maintainer Flow (from workspace):
1. `mix ws.git.pull req_llm`  # Get latest including merged PRs
2. Make changes
3. `mix ws.git.push.pr req_llm my-feature`  # Push to workspace/my-feature
4. Open PR on GitHub
5. CI runs
6. Merge PR
7. `mix ws.git.pull req_llm`  # Sync back
```

---

## Recommended New Mix Tasks

### 1. `mix ws.changes` - Show Unpushed Changes

Shows which projects have commits not yet pushed to upstream.

```elixir
# lib/mix/tasks/ws_changes.ex
defmodule Mix.Tasks.Ws.Changes do
  use Mix.Task
  
  @shortdoc "Show projects with unpushed changes"
  
  def run(_args) do
    projects = JidoWorkspace.config()
    
    Enum.each(projects, fn project ->
      if File.exists?(project.path) do
        case get_unpushed_commits(project) do
          [] -> :ok
          commits ->
            Mix.shell().info("#{project.name}: #{length(commits)} unpushed commits")
            Enum.each(commits, fn commit ->
              Mix.shell().info("  - #{commit}")
            end)
        end
      end
    end)
  end
  
  defp get_unpushed_commits(project) do
    # Compare local subtree state vs upstream
    # Implementation using git log or subtree split
    []
  end
end
```

### 2. `mix ws.git.push.pr` - Push to Feature Branch

Safely pushes to a workspace feature branch, never directly to main.

```elixir
# lib/mix/tasks/ws_git_push_pr.ex
defmodule Mix.Tasks.Ws.Git.Push.Pr do
  use Mix.Task
  
  @shortdoc "Push project to a workspace feature branch for PR"
  
  def run([project_name, feature_name]) do
    branch = "workspace/#{feature_name}"
    
    Mix.shell().info("Pushing #{project_name} to branch: #{branch}")
    
    case JidoWorkspace.push_project(project_name, branch: branch) do
      :ok ->
        Mix.shell().info("✓ Pushed to #{branch}")
        Mix.shell().info("")
        Mix.shell().info("Next steps:")
        Mix.shell().info("  1. Open PR: https://github.com/agentjido/#{project_name}/compare/#{branch}")
        Mix.shell().info("  2. After merge: mix ws.git.pull #{project_name}")
      
      :error ->
        Mix.shell().error("Failed to push")
    end
  end
  
  def run(_) do
    Mix.raise("Usage: mix ws.git.push.pr <project> <feature-name>")
  end
end
```

### 3. `mix hex.publish.llm_db` - Fast-Lane Publishing

Dedicated task for frequent llm_db releases.

```elixir
# lib/mix/tasks/hex_publish_llm_db.ex
defmodule Mix.Tasks.Hex.Publish.LlmDb do
  use Mix.Task
  
  @shortdoc "Publish llm_db with automatic version bump"
  
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, 
      switches: [patch: :boolean, minor: :boolean, dry_run: :boolean]
    )
    
    current_version = get_current_version("projects/llm_db/mix.exs")
    
    new_version = cond do
      opts[:minor] -> bump_minor(current_version)
      true -> bump_patch(current_version)  # Default to patch
    end
    
    if opts[:dry_run] do
      Mix.shell().info("DRY RUN: Would publish llm_db #{current_version} → #{new_version}")
    else
      update_version("projects/llm_db/mix.exs", new_version)
      publish_package("projects/llm_db")
      Mix.shell().info("✓ Published llm_db #{new_version}")
    end
  end
  
  # ... version parsing/bumping helpers ...
end
```

### 4. `mix ws.matrix` - Dependency Matrix Check

Validates that all cross-package dependencies are compatible.

```elixir
# lib/mix/tasks/ws_matrix.ex
defmodule Mix.Tasks.Ws.Matrix do
  use Mix.Task
  
  @shortdoc "Check dependency compatibility matrix"
  
  def run(_args) do
    # Parse all mix.exs files
    # Build dependency graph
    # Check for version conflicts
    # Report issues
  end
end
```

---

## Agent-Assisted Workflows

### 1. Release Agent

**Purpose:** Automate the release process with human oversight.

**Workflow:**
```
1. Agent runs:
   - mix ws.git.status
   - mix ws.changes
   - mix version.check
   - mix hex.publish.all <version> --dry-run

2. Agent summarizes:
   - Which packages changed
   - Suggested version bump (patch/minor/major)
   - Commands to execute

3. With approval:
   - Runs mix hex.publish.all <version>
   - Pushes to workspace branches
   - Opens PRs via GitHub API
   - Tags workspace repo
```

**Implementation:**
- GitHub Action triggered manually or on schedule
- Or Amp agent script that can be invoked conversationally

**Sample Agent Prompt:**
```markdown
You are a release coordinator for the Jido ecosystem.

Your job:
1. Run `mix ws.git.status` and `mix version.check`
2. Analyze which packages have changes since last release
3. Suggest appropriate version bump based on:
   - PATCH: bug fixes, documentation, minor improvements
   - MINOR: new features, non-breaking changes
   - MAJOR: breaking API changes
4. Show dry-run output of `mix hex.publish.all <version> --dry-run`
5. Wait for approval before executing

Never publish without explicit approval.
```

### 2. PR Review Agent

**Purpose:** Automated review of external contributions.

**Triggers:** On PR to req_llm, jido_ai, etc.

**Checks:**
- [ ] Code is formatted (`mix format --check-formatted`)
- [ ] No `@version` changes (workspace manages versions)
- [ ] No `jido_dep` modifications
- [ ] No changes to CI/release files without discussion
- [ ] Tests pass
- [ ] Changelog entry if needed

**Response Template:**
```markdown
## Automated Review

### Checks
- ✅ Formatting: OK
- ❌ Version change detected: Please revert `@version` changes
- ✅ Tests: Passing

### Summary
This PR adds a new provider for X. 

### Potential Impact
- May require llm_db schema update for new models
- Consider adding to `PROVIDERS.md` documentation

### Suggestions
- Add test fixtures for the new provider
- Update the getting started guide
```

### 3. Cross-Repo Change Agent

**Purpose:** Implement features that span multiple packages.

**Example Prompt:**
```
Implement a new `metadata` field in jido_signal that propagates through
jido_action, jido, and jido_ai, and is exposed as an option in req_llm.

Requirements:
1. Add `metadata` to Signal struct in jido_signal
2. Update Action to preserve metadata in jido_action
3. Propagate through workflow in jido
4. Expose in AI context in jido_ai
5. Add as request option in req_llm
6. Add tests at each layer
7. Open PRs for each affected repo
```

**Agent Behavior:**
1. Edit code in `projects/jido_signal/`, `projects/jido_action/`, etc.
2. Run `mix ws test` to validate
3. Use `mix ws.git.push.pr` to push each project
4. Draft PR descriptions with cross-references

### 4. llm_db Sync Agent

**Purpose:** Keep model database up to date with provider changes.

**Triggers:** 
- Daily schedule
- After req_llm provider updates
- Manual invocation

**Workflow:**
1. Fetch latest model lists from providers
2. Compare with current llm_db data
3. Generate migration/update
4. Run validation tests
5. If changes: `mix hex.publish.llm_db --patch --dry-run`
6. With approval: publish and push

### 5. Roadmap/Task Agent

**Purpose:** Intelligent task management and prioritization.

**Capabilities:**
```bash
# Agent can run:
mix roadmap.status           # See all tasks
mix roadmap.todo --owner @me # Personal tasks
mix roadmap.idea "..."       # Capture ideas

# Agent suggests:
"Based on open PRs in req_llm and pending release, 
 suggest prioritizing the Anthropic provider fix before 
 cutting v1.1.0"
```

---

## GitHub Configuration

### Branch Protection (Required for Public Repos)

For `req_llm` and other public packages:

```yaml
# Settings → Branches → Branch protection rules
Branch name pattern: main

✅ Require a pull request before merging
  ✅ Require approvals: 1
  ✅ Dismiss stale pull request approvals when new commits are pushed

✅ Require status checks to pass before merging
  ✅ Require branches to be up to date before merging
  Required checks:
    - test
    - format
    - dialyzer

✅ Require conversation resolution before merging

❌ Allow force pushes (NEVER for public repos)
```

### GitHub Actions for Workspace Integration

```yaml
# .github/workflows/workspace-sync.yml
name: Workspace Sync Check

on:
  pull_request:
    branches: [main]

jobs:
  check-version:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Check for version changes
        run: |
          if git diff --name-only ${{ github.event.pull_request.base.sha }} | grep -q "mix.exs"; then
            if git diff ${{ github.event.pull_request.base.sha }} -- mix.exs | grep -q "@version"; then
              echo "::error::Version changes should be made through the workspace, not in PRs"
              exit 1
            fi
          fi
      
      - name: Check for jido_dep changes
        run: |
          if git diff ${{ github.event.pull_request.base.sha }} -- mix.exs | grep -q "jido_dep"; then
            echo "::warning::jido_dep changes detected - ensure this is intentional"
          fi
```

---

## llm_db Special Handling

### Why llm_db is Different

1. **High churn rate:** Model databases need frequent updates as providers add/change models
2. **Data, not code:** Changes are often schema/data updates, not logic
3. **Downstream dependency:** req_llm depends on it but doesn't need to release for every llm_db update

### Recommended Strategy

1. **Decouple from core version train**
   ```elixir
   # llm_db uses its own version stream
   @version "0.7.4"  # Independent of jido 1.x
   ```

2. **Wide dependency constraints in req_llm**
   ```elixir
   # In req_llm/mix.exs
   {:llm_db, "~> 0.7"}  # Allows 0.7.x without req_llm release
   ```

3. **Fast-lane publishing**
   ```bash
   # Quick patch release for model updates
   mix hex.publish.llm_db --patch
   
   # Minor release for schema changes
   mix hex.publish.llm_db --minor
   ```

4. **Automated model sync**
   - Daily GitHub Action to fetch model lists
   - Auto-PR for review if changes detected
   - One-click publish after approval

### llm_db CI Workflow

```yaml
# projects/llm_db/.github/workflows/model-sync.yml
name: Model Sync

on:
  schedule:
    - cron: '0 6 * * *'  # Daily at 6am UTC
  workflow_dispatch:

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Fetch latest models
        run: mix llm_db.sync
      
      - name: Check for changes
        id: changes
        run: |
          if git diff --quiet; then
            echo "changed=false" >> $GITHUB_OUTPUT
          else
            echo "changed=true" >> $GITHUB_OUTPUT
          fi
      
      - name: Create PR
        if: steps.changes.outputs.changed == 'true'
        uses: peter-evans/create-pull-request@v5
        with:
          title: "chore: sync model database"
          branch: auto/model-sync
          body: |
            Automated model database sync.
            
            Review changes and merge to trigger release.
```

---

## CONTRIBUTING.md Template for Public Repos

```markdown
# Contributing to [Package Name]

Thank you for your interest in contributing!

## Development Setup

1. Fork and clone this repository
2. Install dependencies: `mix deps.get`
3. Run tests: `mix test`
4. Check formatting: `mix format --check-formatted`

## Pull Request Guidelines

### What to Include
- Clear description of changes
- Tests for new functionality
- Documentation updates if applicable
- Changelog entry for user-facing changes

### What NOT to Change
The following are managed centrally through the Jido workspace:

- **`@version`** - Version bumps are coordinated across packages
- **`jido_dep` calls** - Dependency versions are managed centrally
- **Release/CI workflows** - Unless discussed first

If your changes require version bumps or dependency updates, note this in your 
PR description and the maintainers will coordinate.

## Code Style

- Run `mix format` before committing
- Follow existing patterns in the codebase
- Avoid inline comments in function bodies
- Use descriptive variable and function names

## Questions?

Open an issue or join the discussion in [Discord/Slack/etc].
```

---

## Implementation Roadmap

### Phase 1: Foundation (1-2 days)

- [ ] Implement `mix ws.changes` task
- [ ] Implement `mix ws.git.push.pr` task
- [ ] Update workspace.exs with complete hex_packages config
- [ ] Enable branch protection on req_llm
- [ ] Add CONTRIBUTING.md to public repos

### Phase 2: Publishing (1-2 days)

- [ ] Implement `mix hex.publish.llm_db` fast-lane task
- [ ] Add `--only-changed` option to hex_publish
- [ ] Create version bump validation in CI
- [ ] Document release workflow

### Phase 3: Agent Integration (3-5 days)

- [ ] Create Release Agent prompt/script
- [ ] Implement PR Review Agent as GitHub Action
- [ ] Set up llm_db auto-sync workflow
- [ ] Create cross-repo change agent guidelines

### Phase 4: Advanced Automation (ongoing)

- [ ] Dependency matrix validation
- [ ] Automated compatibility testing
- [ ] Release notes generation
- [ ] Changelog aggregation across repos

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Subtree conflicts with contributors | Never push to main; always use workspace branches + PRs |
| Accidental version mismatches | CI checks block `@version` changes in PRs |
| Agent makes wrong decisions | Always require `--dry-run` first, explicit approval for actions |
| llm_db breaks req_llm | Careful version constraints, schema-aware CI |
| Contributor confusion | Clear CONTRIBUTING.md, label workspace PRs |

---

## Success Metrics

After implementing these recommendations, measure:

1. **Release time:** Time from "ready to release" to "published on Hex"
2. **Conflict rate:** Number of merge conflicts in workspace pulls
3. **Contributor friction:** Time to first PR merge for new contributors
4. **Version coherence:** Frequency of version mismatch issues
5. **Agent effectiveness:** Tasks automated vs. manual intervention needed

---

## Appendix: Quick Reference

### Common Workflows

```bash
# Morning startup
mix morning

# Before working on public repo
mix ws.git.pull req_llm

# After making changes
mix ws.git.push.pr req_llm my-feature

# Release core packages
mix hex.publish.all 1.3.0 --dry-run
mix hex.publish.all 1.3.0

# Quick llm_db update
mix hex.publish.llm_db --patch
```

### Key Files

| File | Purpose |
|------|---------|
| `config/workspace.exs` | Project and Hex package configuration |
| `lib/jido_workspace.ex` | Core workspace operations |
| `lib/mix/tasks/` | All workspace Mix tasks |
| `roadmap/` | Task and milestone tracking |

### Environment Variables

```bash
JIDO_WORKSPACE=1  # Automatically set for workspace operations
HEX_API_KEY=...   # Required for publishing
```

---

*This document should be reviewed and updated as the workspace evolves.*

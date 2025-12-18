# Maintainer Plan v2: Standardization & Centralization

## Overview

This plan standardizes GitHub Actions, conventional commits, `git_ops` usage, and release processes across the Jido ecosystem projects. The goal is to centralize, standardize, and ease the maintenance burden through reusable GitHub Actions and consistent tooling.

**Target Projects:**
- agentjido/jido
- agentjido/jido_action
- agentjido/jido_signal
- agentjido/jido_ai
- agentjido/jido_workbench
- agentjido/req_llm
- agentjido/llm_db

**Central Hub:**
- agentjido/github-actions (reusable workflows and standards)

---

## TL;DR for Contributors

```bash
# Clone any project
git clone git@github.com:agentjido/<project>.git
cd <project>

# Setup
mix deps.get
mix git_hooks.install

# Development cycle
mix test          # Run tests
mix quality       # Run all quality checks (or `mix q`)

# Commit using conventional commits
git commit -m "feat: add new feature"
git commit -m "fix: resolve edge case"
git commit -m "feat!: breaking change description"
```

**Key Rules:**
1. All commits must follow [Conventional Commits](https://www.conventionalcommits.org/)
2. Run `mix quality` before pushing
3. PRs require passing CI checks

---

## 1. Project Classification & Dependencies

### 1.1 Project Categories

| Project | Type | Hex Published | Versioning | Notes |
|---------|------|---------------|------------|-------|
| jido | Library (Core) | ✅ | SemVer | Foundational - all others depend on this |
| jido_action | Library (Core) | ✅ | SemVer | Foundational action system |
| jido_signal | Library (Core) | ✅ | SemVer | Foundational signal/event system |
| jido_ai | Library | ✅ | SemVer | AI integrations |
| req_llm | Library | ✅ | SemVer | LLM request library |
| llm_db | Library | ✅ | Date-based | Special versioning (2025.12.2) |
| jido_workbench | Application | ❌ | N/A | Phoenix app, deploy-focused |

### 1.2 Dependency Graph

```
jido (core)
├── jido_action (~> 0.3)
├── jido_signal (~> 0.3)
└── jido_ai (~> 0.4)
    ├── depends on jido
    ├── depends on jido_action
    └── depends on req_llm

req_llm (standalone)
llm_db (standalone)
jido_workbench (application)
    └── depends on jido, jido_ai, etc.
```

### 1.3 Compatibility Matrix

| Dependent | jido | jido_action | jido_signal | req_llm |
|-----------|------|-------------|-------------|---------|
| jido_action | ~> 0.4 | - | - | - |
| jido_signal | ~> 0.4 | - | - | - |
| jido_ai | ~> 0.4 | ~> 0.3 | ~> 0.3 | ~> 1.0 |
| jido_workbench | ~> 0.4 | ~> 0.3 | ~> 0.3 | - |

---

## 2. Versioning Strategy

### 2.1 Version Schemes by Project

| Project | Scheme | Tag Format | Release Driver | CHANGELOG |
|---------|--------|------------|----------------|-----------|
| jido | SemVer | vX.Y.Z | git_ops | Auto-generated |
| jido_action | SemVer | vX.Y.Z | git_ops | Auto-generated |
| jido_signal | SemVer | vX.Y.Z | git_ops | Auto-generated |
| jido_ai | SemVer | vX.Y.Z | git_ops | Auto-generated |
| req_llm | SemVer | vX.Y.Z | git_ops | Auto-generated |
| llm_db | Date-based | 2025.12.2 | Custom tasks | Manual/Custom |
| jido_workbench | N/A | N/A | Deploy workflow | N/A |

### 2.2 Conventional Commits → Version Bumps

| Commit Type | Version Impact | Example |
|-------------|----------------|---------|
| `fix:` | Patch (0.0.X) | `fix: handle nil input` |
| `feat:` | Minor (0.X.0) | `feat: add retry logic` |
| `feat!:` | Major (X.0.0) | `feat!: rename API` |
| `BREAKING CHANGE:` in footer | Major (X.0.0) | Any commit with breaking footer |
| `docs:`, `style:`, `refactor:`, `test:`, `chore:`, `ci:` | No bump | Documentation, tooling changes |

### 2.3 llm_db Special Handling

llm_db uses **date-based versioning** intentionally:
- Format: `YYYY.MM.DD` (e.g., `2025.12.2`)
- Release via: `mix llm_db.pull` + `mix llm_db.version`
- git_ops is used for some tasks but NOT for version bumping
- Release workflow must preserve this custom process

**Do NOT normalize llm_db to SemVer.**

---

## 3. Build & Quality Tooling Checklist

### 3.1 mix.exs Configuration

Each project must have proper dependencies and aliases configured.

- [ ] **git_ops dependency**
  - [ ] Added: `{:git_ops, "~> 2.9", only: :dev, runtime: false}`
  - [ ] Version: Match across all projects (currently ~2.9)
  - [ ] Used for: Automated versioning, CHANGELOG generation, git tagging

- [ ] **git_hooks dependency**
  - [ ] Added: `{:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false}`
  - [ ] Version: Standardize to ~0.8.x across all projects
  - [ ] Configured for: commit-msg validation, pre-push quality checks

- [ ] **Quality tools dependencies** (present in all projects)
  - [ ] credo: `{:credo, "~> 1.7", only: [:dev, :test]}`
  - [ ] dialyxir: `{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}`
  - [ ] doctor: `{:doctor, "~> 0.21" or "~> 0.22", only: [:dev, :test], runtime: false}`
  - [ ] excoveralls: `{:excoveralls, "~> 0.18.3", only: [:dev, :test]}`
  - [ ] ex_doc: `{:ex_doc, "~> 0.34" or higher, only: :dev, runtime: false}`

- [ ] **mix aliases configuration**
  - [ ] `q` alias: `["quality"]` for shorthand
  - [ ] `quality` alias includes (in order):
    ```elixir
    [
      "format --check-formatted",
      "compile --warnings-as-errors",
      "dialyzer",
      "credo --strict"
    ]
    ```
  - [ ] Test alias: `test: "test --exclude flaky"` (exclude flaky tests by default)
  - [ ] Optional: `docs: "docs -f html --open"` for documentation generation

### 3.2 Per-Project Status

| Project | git_ops | git_hooks | quality | Action Needed |
|---------|---------|-----------|---------|---------------|
| jido | 2.9 ✅ | 0.5.0 ⚠️ | ✅ | Upgrade git_hooks to ~0.8 |
| jido_action | 2.9 ✅ | 0.5.0 ⚠️ | ✅ | Upgrade git_hooks to ~0.8 |
| jido_signal | 2.9 ✅ | 0.5.0 ⚠️ | ✅ | Upgrade git_hooks to ~0.8 |
| jido_ai | 2.5 ❌ | Missing ❌ | ✅ | Upgrade git_ops, add git_hooks |
| jido_workbench | 2.9 ✅ | 0.5.0 ✅ | ✅ | Upgrade git_hooks to ~0.8 |
| req_llm | 2.9 ✅ | 0.8 ✅ | ✅ | None |
| llm_db | 2.6 ⚠️ | 0.8 ✅ | ✅ | Consider git_ops upgrade |

### 3.3 Upgrading git_ops Safely

Before upgrading git_ops in any project:

1. **Backup current state:**
   ```bash
   # Note current version
   grep git_ops mix.exs
   
   # Backup config and changelog
   cp mix.exs mix.exs.backup
   cp CHANGELOG.md CHANGELOG.md.backup
   ```

2. **Upgrade dependency:**
   ```elixir
   # In mix.exs
   {:git_ops, "~> 2.9", only: :dev, runtime: false}
   ```

3. **Test the upgrade:**
   ```bash
   mix deps.get
   mix compile
   
   # Dry-run to verify behavior (in a temp branch)
   git checkout -b test-git-ops-upgrade
   mix git_ops.release --dry-run  # if supported
   ```

4. **Verify:**
   - Tag format matches expectations (`vX.Y.Z`)
   - CHANGELOG format unchanged
   - No breaking changes to release process

5. **Rollback if needed:**
   ```bash
   cp mix.exs.backup mix.exs
   mix deps.get
   ```

---

## 4. Conventional Commits & git_hooks

### 4.1 Setup Requirements

- [ ] **git_hooks installation**
  - [ ] Hook installed automatically via `mix compile` (if configured)
  - [ ] Manual install: `mix git_hooks.install`
  - [ ] Validates: commit-msg hook enforces conventional commits

- [ ] **Commit message format** (Conventional Commits)
  ```
  <type>[optional scope]: <description>
  
  [optional body]
  
  [optional footer(s)]
  ```

- [ ] **Valid types** (enforced by git_ops)
  - `feat` - New feature (minor bump)
  - `fix` - Bug fix (patch bump)
  - `docs` - Documentation only (no bump)
  - `style` - Formatting (no bump)
  - `refactor` - Code refactor (no bump)
  - `perf` - Performance improvement (patch bump)
  - `test` - Test changes (no bump)
  - `chore` - Build/tooling changes (no bump)
  - `ci` - CI configuration changes (no bump)

### 4.2 Important: Client-Side Hooks Are Bypassable

**git_hooks are client-side and can be bypassed with `--no-verify`.**

Enforcement must ALSO occur in CI:
- Add conventional commit validation step in GitHub Actions
- Block PRs with non-compliant commit messages
- Consider using a commit-lint action in the central workflow

### 4.3 Configuration

- [ ] **git_ops config** in mix.exs:
  ```elixir
  {:git_ops, "~> 2.9", only: :dev, runtime: false}
  ```

- [ ] **CONTRIBUTING.md** must include:
  - [ ] Commit message format documentation
  - [ ] Link to conventional commits spec
  - [ ] Examples of good/bad commits
  - [ ] Hook installation instructions

---

## 5. Mix Quality Command Standardization

### 5.1 Standard `mix quality` (and `mix q`) Alias

Every project must support both:
- `mix q` - Shorthand for quality
- `mix quality` - Full quality check

**Standard order of execution:**
```elixir
quality: [
  "format --check-formatted",
  "compile --warnings-as-errors",
  "dialyzer",
  "credo --strict"
]
```

**Why this order:**
1. Format check first (fast, catches style issues)
2. Compilation (catches syntax/type errors early)
3. Dialyzer (type checking, can take time)
4. Credo (static analysis, strictest checks last)

### 5.2 Project-Specific Additions

Some projects may add additional quality checks:

| Project | Additional Checks | Notes |
|---------|-------------------|-------|
| jido_ai | `doctor --short --raise`, `docs` | More comprehensive |
| req_llm | Standard only | - |
| llm_db | Standard only | Credo before dialyzer (non-standard) |

**Action:** Align all projects to standard order, document deviations.

### 5.3 CI Integration

- [ ] GitHub Actions calls `mix quality` for lint checks
- [ ] Must pass before PR merge
- [ ] No exceptions in CI

---

## 6. Cross-Project Coordination

### 6.1 Breaking Change Policy

For any breaking change in a foundational project (jido, jido_action, jido_signal):

1. **Mark commits clearly:**
   - Use `feat!:` or `fix!:` prefix
   - Or include `BREAKING CHANGE:` in commit footer

2. **Before releasing:**
   - Open PRs to all dependent projects updating:
     - Dependencies (`mix.exs` constraints)
     - Any necessary code changes
   - Ensure all dependent projects pass `mix test` and `mix quality`

3. **Release in order:**
   ```
   jido → jido_action/jido_signal → jido_ai/req_llm → dependent apps
   ```

4. **Use deprecation periods when possible:**
   - Introduce new behavior, deprecate old, release minor
   - Only remove deprecated code in next major release

### 6.2 Cross-Project CI (Optional Enhancement)

When jido is changed on main or tagged:
- Trigger `repository_dispatch` to run tests in jido_action and jido_signal
- Only for critical dependencies initially

```yaml
# In jido's release workflow
- name: Trigger dependent project tests
  uses: peter-evans/repository-dispatch@v2
  with:
    token: ${{ secrets.CROSS_REPO_TOKEN }}
    repository: agentjido/jido_action
    event-type: upstream-release
    client-payload: '{"version": "${{ steps.release.outputs.version }}"}'
```

### 6.3 Local Development Across Projects

For working on multiple Jido repos locally:

**Using jido_dep helper (preferred):**
```elixir
# In mix.exs - dependencies auto-switch to local paths if directory exists
defp jido_dep(app, rel_path, hex_req, extra_opts \\ []) do
  path = Path.expand(rel_path, __DIR__)
  if File.dir?(path) and File.exists?(Path.join(path, "mix.exs")) do
    {app, Keyword.merge([path: rel_path, override: true], extra_opts)}
  else
    {app, hex_req, extra_opts}
  end
end

# Usage
defp deps do
  [
    jido_dep(:jido, "../jido", "~> 0.4.0"),
    jido_dep(:jido_action, "../jido_action", "~> 0.3.0"),
  ]
end
```

**In the workspace:**
- Projects are already co-located in `projects/`
- `jido_dep` automatically detects and uses local paths
- CI always uses hex versions (no local paths in CI)

---

## 7. Package Descriptions & Links

### 7.1 Package Block in mix.exs

Every publishable package (hex.pm) must include:

```elixir
defp package do
  [
    description: "Clear, concise description",
    licenses: ["Apache-2.0"],
    maintainers: ["Mike Hostetler"],
    links: %{
      "Documentation" => "https://hexdocs.pm/#{@app}",
      "GitHub" => @source_url,
      "Website" => "https://agentjido.xyz",
      "Discord" => "https://agentjido.xyz/discord",
      "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
    }
  ]
end
```

### 7.2 Implementation Checklist

| Project | Docs | GitHub | Website | Discord | Changelog | Action |
|---------|------|--------|---------|---------|-----------|--------|
| jido | ✅ | ✅ | ❌ | ❌ | ❌ | Add Website, Discord, Changelog |
| jido_action | ✅ | ✅ | ✅ | ❌ | ❌ | Add Discord, Changelog |
| jido_signal | ❌ | ✅ | ✅ | ❌ | ❌ | Add Docs, Discord, Changelog |
| jido_ai | ❌ | ✅ | ❌ | ❌ | ❌ | Add all standard links |
| req_llm | ✅ | ✅ | ❌ | ✅ | ✅ | Add Website |
| llm_db | ❌ | ✅ | ✅ | ❌ | ✅ | Add Docs, Discord |

---

## 8. GitHub Actions Workflows

### 8.1 Central Reusable Workflows

Located in: `agentjido/github-actions`

**Available workflows:**
- `elixir-test.yml` - Run tests with configurable OTP/Elixir versions
- `elixir-lint.yml` - Run quality checks (mix quality)
- `elixir-release.yml` - Publish release using git_ops

### 8.2 Workflow Versioning & Pinning

**Critical: Always pin workflow versions!**

```yaml
# ✅ Good - pinned to version tag
uses: agentjido/github-actions/.github/workflows/elixir-ci.yml@v1

# ❌ Bad - unpinned, can break unexpectedly
uses: agentjido/github-actions/.github/workflows/elixir-ci.yml@main
```

**Version policy:**
- `v1` is stable, backward-compatible line
- Breaking changes → `v2`, repos opt-in explicitly
- Patches released as `v1.x.y`

### 8.3 CI Workflow (.github/workflows/ci.yml)

```yaml
name: CI

on:
  pull_request:
  push:
    branches:
      - main

jobs:
  lint:
    name: Lint
    uses: agentjido/github-actions/.github/workflows/elixir-lint.yml@v1

  test:
    name: Test
    needs: lint
    uses: agentjido/github-actions/.github/workflows/elixir-test.yml@v1
    with:
      test_command: mix test
```

### 8.4 Release Workflow (.github/workflows/release.yml)

```yaml
name: Release

on:
  workflow_dispatch:

permissions:
  contents: write

jobs:
  release:
    name: Release
    uses: agentjido/github-actions/.github/workflows/elixir-release.yml@v1
    secrets: inherit
```

### 8.5 CI Secrets & Environments

**Standard secret names:**
| Secret | Required By | Purpose |
|--------|-------------|---------|
| `HEX_API_KEY` | All publishable | Hex.pm publishing |
| `GITHUB_TOKEN` | All | Git operations (auto-provided) |
| `OPENAI_API_KEY` | jido_ai, req_llm | Live API tests |
| `ANTHROPIC_API_KEY` | jido_ai, req_llm | Live API tests |

**Recommendation:** Use GitHub Environments for production secrets.

### 8.6 Implementation Checklist

| Project | ci.yml | release.yml | Action |
|---------|--------|-------------|--------|
| jido | ✅ | ✅ | Update to central workflows |
| jido_action | ✅ | ✅ | Update to central workflows |
| jido_signal | ? | ? | Create/update workflows |
| jido_ai | ❌ | ❌ | Create workflows |
| jido_workbench | ✅ | N/A | Update CI only |
| req_llm | ✅ | ✅ | Update to central workflows |
| llm_db | ? | Custom | Create CI, preserve custom release |

---

## 9. Dependabot Configuration

### 9.1 Standard Configuration

All projects must have `.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: "hex"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "03:00"
    open-pull-requests-limit: 5
    reviewers:
      - "mhostetler"
    allow:
      - dependency-type: "direct"
      - dependency-type: "indirect"
    commit-message:
      prefix: "chore(deps):"
      include: "scope"
    pull-request-branch-name:
      separator: "/"
```

### 9.2 Implementation Checklist

- [ ] jido: Check/create dependabot.yml
- [ ] jido_action: Check/create dependabot.yml
- [ ] jido_signal: Check/create dependabot.yml
- [ ] jido_ai: Check/create dependabot.yml
- [ ] jido_workbench: Check/create dependabot.yml
- [ ] req_llm: Check/create dependabot.yml
- [ ] llm_db: Check/create dependabot.yml

---

## 10. Pull Request Templates

### 10.1 Status

| Project | Has Template | Action |
|---------|--------------|--------|
| jido | ❌ | Create |
| jido_action | ✅ | Review/update |
| jido_signal | ✅ | Review/update |
| jido_ai | ❌ | Create |
| jido_workbench | ❌ | Create (optional) |
| req_llm | ✅ | Review/update |
| llm_db | ✅ | Review/update |

### 10.2 Template Structure

All PR templates should include:

1. **Description** - What does this PR accomplish?
2. **Type of Change** - Bug fix, feature, docs, etc.
3. **Breaking Changes** - If any, describe with before/after
4. **Testing Approach** - How was this tested?
5. **Quality Checklist:**
   - [ ] Tests pass (`mix test`)
   - [ ] Quality checks pass (`mix quality`)
   - [ ] Documentation updated if needed
   - [ ] Conventional commit messages used
6. **Related Issues** - Closes/Relates to

---

## 11. Contributor Guidelines

### 11.1 CONTRIBUTING.md Status

| Project | Has CONTRIBUTING.md | Action |
|---------|---------------------|--------|
| jido | ✅ | Use as template |
| jido_action | ? | Audit |
| jido_signal | ? | Audit |
| jido_ai | ❌ | Create |
| jido_workbench | ❌ | Create |
| req_llm | ? | Audit |
| llm_db | ? | Audit |

### 11.2 Required Sections

1. Getting Started (clone, deps, test, quality)
2. Development Guidelines
3. Git Hooks & Conventional Commits
4. Pull Request Process
5. Release Process (for maintainers)

---

## 12. Implementation Timeline & Phases

### Phase 1: Foundation (Weeks 1-2)

**Goal:** Fix local tooling first, before enforcing in CI.

**Tasks:**
- [ ] Update jido_ai: add git_hooks, upgrade git_ops
- [ ] Upgrade git_hooks to ~0.8 in all projects
- [ ] Ensure `mix quality` passes locally in all projects
- [ ] Create missing CONTRIBUTING.md files
- [ ] Create missing PR templates
- [ ] Standardize LICENSE files

**Verification:**
- [ ] `mix quality` passes in each project
- [ ] `mix git_hooks.install` works in each project
- [ ] Conventional commit validation works locally

### Phase 2: Package Metadata (Week 3)

**Tasks:**
- [ ] Add standard links to all package blocks
- [ ] Update descriptions for clarity
- [ ] Verify hex.pm rendering

### Phase 3: GitHub Actions (Weeks 4-5)

**Tasks:**
- [ ] Audit central github-actions workflows
- [ ] Update ci.yml in all projects (pinned to @v1)
- [ ] Update release.yml (with opt-in flag initially disabled)
- [ ] Test CI runs
- [ ] Enable release automation per-project after validation

**Verification:**
- [ ] All CI workflows pass
- [ ] Release workflow triggers correctly in pilot
- [ ] Rollback procedure documented and tested

### Phase 4: Dependabot (Week 6)

**Tasks:**
- [ ] Deploy dependabot.yml to all projects
- [ ] Configure auto-merge rules (optional)

### Phase 5: Documentation & Rollout (Week 7)

**Tasks:**
- [ ] Create STANDARDIZATION.md (quick reference)
- [ ] Update all README files
- [ ] Announce to team
- [ ] Create troubleshooting guide

---

## 13. Special Cases

### 13.1 jido_ai

- Uses `LOCAL_JIDO_DEPS` for local development
- Has additional quality checks (doctor, docs)
- Missing git_hooks entirely

**Actions:**
- [ ] Add git_hooks ~0.8
- [ ] Upgrade git_ops to ~2.9
- [ ] Create CONTRIBUTING.md
- [ ] Document LOCAL_JIDO_DEPS usage

### 13.2 jido_workbench

- Phoenix application, not hex-publishable
- Different deployment needs
- CI only, no release workflow

**Actions:**
- [ ] Create CI workflow (no release)
- [ ] Create CONTRIBUTING.md with Phoenix-specific info
- [ ] Skip package links

### 13.3 llm_db

- Date-based versioning (2025.12.2)
- Custom release via `mix llm_db.pull` + `mix llm_db.version`
- Do NOT normalize to SemVer

**Actions:**
- [ ] Preserve custom release process
- [ ] Create CI workflow (standard quality checks)
- [ ] Document special process in STANDARDIZATION.md

### 13.4 req_llm

- Advanced fixture-based testing
- Uses `LIVE=true` for fixture recording
- Has semantic tag filtering

**Actions:**
- [ ] Preserve fixture system in CI
- [ ] Add Website link to package
- [ ] Document fixture approach

---

## 14. Documentation Standards

### 14.1 STANDARDIZATION.md Quick Reference

Create in each project:

```markdown
# Standardization

This project follows the Jido ecosystem standards.

## Quick Start

```bash
mix deps.get
mix git_hooks.install
mix test
mix quality
```

## Commit Format

Use conventional commits: `type(scope): description`

## Quality Checks

```bash
mix q        # or mix quality
```

## More Info

See [CONTRIBUTING.md](./CONTRIBUTING.md)
```

### 14.2 README Updates

Each README must include:
- [ ] Link to CONTRIBUTING.md
- [ ] `mix quality` as primary quality check
- [ ] Link to hexdocs.pm documentation
- [ ] Discord invitation link

---

## Appendix A: File Templates

### A.1 CONTRIBUTING.md Template

```markdown
# Contributing

Thank you for your interest in contributing!

## Getting Started

```bash
git clone git@github.com:agentjido/[project].git
cd [project]
mix deps.get
mix test
mix quality
```

## Development

- Run `mix quality` (or `mix q`) before committing
- Follow [conventional commits](https://www.conventionalcommits.org/)
- Install git hooks: `mix git_hooks.install`

## Commit Message Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Types:** feat, fix, docs, style, refactor, perf, test, chore, ci

**Examples:**
```
feat: add retry logic to API client
fix(auth): handle expired tokens gracefully
feat!: rename User to Account (breaking change)
```

## Testing

```bash
mix test                   # Run all tests
mix test --only tag_name   # Run specific tests
mix test --cover           # With coverage
```

## Pull Request Process

1. Create a feature branch from `main`
2. Make changes following our code style
3. Run `mix quality` - all checks must pass
4. Write a descriptive PR with conventional commit format
5. Reference related issues

## Questions?

Open a GitHub issue or join our [Discord](https://agentjido.xyz/discord).
```

### A.2 PR Template

```markdown
## Description

Brief description of changes.

## Type of Change

- [ ] Bug fix (non-breaking change fixing an issue)
- [ ] New feature (non-breaking change adding functionality)
- [ ] Breaking change (fix or feature causing existing functionality to change)
- [ ] Documentation update

## Breaking Changes

<!-- If this is a breaking change, describe the impact and migration path -->

## Testing

- [ ] Tests pass (`mix test`)
- [ ] Quality checks pass (`mix quality`)

## Checklist

- [ ] My code follows the project's style guidelines
- [ ] I have updated the documentation accordingly
- [ ] I have added tests that prove my fix/feature works
- [ ] All new and existing tests pass
- [ ] My commits follow conventional commit format

## Related Issues

Closes #
```

---

## Appendix B: Glossary

| Term | Definition |
|------|------------|
| **git_ops** | Automates version bumping, CHANGELOG generation, git tagging |
| **git_hooks** | Enforces conventional commits via pre-commit hooks |
| **mix quality** | Runs formatting, compilation, dialyzer, and credo checks |
| **Conventional Commits** | Specification for commit message format |
| **Dialyzer** | Static analysis tool for Erlang/Elixir type checking |
| **Credo** | Code analysis tool for consistency and best practices |
| **SemVer** | Semantic Versioning (MAJOR.MINOR.PATCH) |
| **Hex.pm** | Elixir/Erlang package registry |

---

## Version History

| Date | Version | Changes |
|------|---------|---------|
| 2025-12-18 | 1.0 | Initial standardization plan |
| 2025-12-18 | 2.0 | Added: cross-project coordination, versioning strategy, workflow pinning, streamlined implementation |

---

## Next Steps

1. ✅ Review v2 plan
2. ✅ Begin Phase 1: Foundation
3. ✅ Complete Phase 2: Package Metadata
4. ✅ Complete Phase 3: GitHub Actions
5. ✅ Complete Phase 4: Dependabot
6. [ ] Complete Phase 5: Documentation (README updates, STANDARDIZATION.md)

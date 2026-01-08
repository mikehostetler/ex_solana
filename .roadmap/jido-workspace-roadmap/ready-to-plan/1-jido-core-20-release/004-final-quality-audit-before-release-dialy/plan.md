# Implementation Plan: Final Quality Audit - Dialyzer Clean, Credo Clean, No Warnings

**Item ID:** 004-final-quality-audit-before-release-dialy
**Section:** 1. Jido Core 2.0 Release
**Planning Date:** 2026-01-07

---

## Executive Summary

This implementation plan establishes a comprehensive quality gate for Jido Core 2.0 release across four packages (jido, jido_action, jido_signal, jido_ai). The approach focuses on fixing existing quality issues in jido_ai (the only package with problems), adding explicit Credo configurations to document conventions, and ensuring CI/CD integration enforces these standards. Key architectural decisions include: using the existing `mix quality` alias as the primary release gate, standardizing PLT paths across packages, and treating compiler warnings as errors to prevent degradation. The work is estimated at 9-13 hours total, with jido_ai fixes being the critical path.

---

## Impact Analysis Summary

### Key Findings from Research

**Current State:**
- **jido, jido_action, jido_signal:** All clean (zero warnings, clean Dialyzer, clean Credo)
- **jido_ai:** Requires attention (35 compiler warnings, 17 Dialyzer warnings)
- **Tools:** All packages have Dialyxir 1.4, Credo 1.7, ExCoveralls configured
- **CI:** Shared GitHub Actions workflows in use

**Files Requiring Changes:**

| Package | Files | Issue Count |
|---------|-------|-------------|
| jido_ai | `lib/jido_ai/skills/streaming/streaming.ex` | Multiple def clauses |
| jido_ai | `lib/jido_ai/skills/streaming/actions/start_stream.ex` | 6 unused functions |
| jido_ai | `lib/jido_ai/skills/tool_calling/actions/call_with_tools.ex` | Contract + 6 unused |
| jido_ai | `lib/jido_ai/skills/tool_calling/actions/execute_tool.ex` | Pattern match |
| jido_ai | `lib/jido_ai/skills/tool_calling/actions/list_tools.ex` | Pattern match |
| jido_ai | `lib/jido_ai/strategies/adaptive.ex` | no_return |
| jido_ai | `lib/jido_ai/trm/machine.ex` | Pattern match |
| All packages | CREATE: `.credo.exs` | 4 files |

**Integration Points:**
- Shared GitHub Actions: `agentjido/github-actions/.github/workflows/elixir-lint.yml@main`
- Quality alias: `mix quality` already defined in all packages
- PLT paths: Currently inconsistent, need standardization

---

## Feature Specification

### User Stories

**As a maintainer**, I want a single command that validates all quality checks so that I can confidently release Jido Core 2.0.

- **Acceptance Criteria:** `mix quality` passes on all 4 packages
- **Implementation:** Existing alias already defined, needs fixes to pass

**As a contributor**, I want explicit Credo configuration so that I understand team conventions.

- **Acceptance Criteria:** Each package has `.credo.exs` with documented rules
- **Implementation:** Create 4 config files with explanatory comments

**As a CI system**, I want to enforce quality checks on every pull request so that regressions are caught early.

- **Acceptance Criteria:** Lint workflow includes all quality checks
- **Implementation:** Verify or update shared GitHub Actions

### API Contracts

**Quality Gate Interface:**
```bash
# Primary gate
mix quality

# Individual checks
mix compile --warnings-as-errors
mix format --check-formatted
mix credo --min-priority higher
mix dialyzer
```

**Exit Codes:**
- 0: All checks passed
- Non-zero: One or more checks failed (CI will block merge)

### State Management Requirements

No state changes required. This is purely validation and configuration work.

### Error Handling Approach

**Compiler Warnings:** Treated as errors via `--warnings-as-errors` flag
**Dialyzer Warnings:** Must be fixed before release (no ignore mechanism)
**Credo Issues:** Can be explicitly ignored with justification in `.credo.exs`

---

## Technical Design

### Data Model Changes

None. This work does not change runtime behavior or data structures.

### Module Organization

**New Configuration Files:**
```
projects/jido/.credo.exs
projects/jido_action/.credo.exs
projects/jido_signal/.credo.exs
projects/jido_ai/.credo.exs
```

**Modified Files (jido_ai only):**
- 7 files require fixes for compiler/Dialyzer warnings

### Third-Party Integration

**No new dependencies.** Existing tools:
- Dialyxir 1.4 (Dialyzer wrapper)
- Credo 1.7 (Code style/linting)
- ExCoveralls (Test coverage, already configured)

### Configuration/Environment Changes

**Dialyzer Configuration (.dialyxir.exs to be standardized):**
```elixir
[
  plt_local_path: "priv/plts/project.plt",
  plt_core_path: "priv/plts/core.plt",
  plt_add_apps: [:mix, :ex_unit],
  dialyzer: [
    flags: [
      :error_handling,
      :race_conditions,
      :underspecs,
      :unmatched_returns
    ]
  ]
]
```

**Credo Configuration (.credo.exs to be created):**
```elixir
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: []
      },
      requires: [],
      checks: [
        # Enabled checks with documentation
      ]
    }
  ]
}
```

---

## Implementation Phases

### Phase 1: Fix jido_ai Compilation Warnings (Blocker)

**Objective:** Achieve zero compiler warnings to enable warnings-as-errors enforcement.

**Success Criteria:**
```bash
cd projects/jido_ai
mix compile --warnings-as-errors
# Exit code: 0
```

**Files to Modify:**
1. `projects/jido_ai/lib/jido_ai/skills/streaming/streaming.ex`
   - Add header declarations for multi-clause `def skill_spec/1` with defaults

2. Multiple files with unused variables:
   - Prefix unused variables with underscore (`rest` → `_rest`, `c1` → `_c1`)
   - Remove unused `alias Registry`

**Tests to Add:**
- None (this is fixing warnings, not behavior)

**Dependencies:** None

**Effort:** 2-3 hours

---

### Phase 2: Fix jido_ai Dialyzer Warnings

**Objective:** Achieve clean Dialyzer run with zero warnings.

**Success Criteria:**
```bash
cd projects/jido_ai
mix dialyzer
# Output: 0 warnings, 0 skipped
```

**Files to Modify:**
1. `lib/jido_ai/skills/streaming/actions/start_stream.ex`
   - Remove 6 unused functions OR mark with `@doc false`
   - Decision: Remove if truly unused, document if kept for API completeness

2. `lib/jido_ai/skills/tool_calling/actions/call_with_tools.ex`
   - Fix contract violation at line 106
   - Remove/mark 6 unused functions
   - Investigate `ReqLLM.Tool.name/1` call (may need dependency update)

3. `lib/jido_ai/skills/tool_calling/actions/execute_tool.ex`
   - Fix pattern match coverage (add missing clause or use `:unknown` fallback)

4. `lib/jido_ai/skills/tool_calling/actions/list_tools.ex`
   - Fix pattern match coverage

5. `lib/jido_ai/strategies/adaptive.ex`
   - Fix no_return issue at line 263 (add explicit return or raise)

6. `lib/jido_ai/trm/machine.ex`
   - Fix pattern match coverage at line 478

**Tests to Add:**
- Add tests for previously untested code paths exposed by pattern match fixes

**Dependencies:** Phase 1 (should compile cleanly first)

**Effort:** 3-4 hours

---

### Phase 3: Create Credo Configurations

**Objective:** Document team conventions and enable explicit rule configuration.

**Success Criteria:**
- Each package has `.credo.exs` with explanatory comments
- `mix credo --min-priority higher` passes on all packages
- Team can justify every enabled/disable check

**Files to Create:**
1. `projects/jido/.credo.exs`
2. `projects/jido_action/.credo.exs`
3. `projects/jido_signal/.credo.exs`
4. `projects/jido_ai/.credo.exs`

**Configuration Template:**
```elixir
# This configuration defines Jido's code quality standards.
# All checks are documented with their rationale.
# To ignore a specific issue, use the inline syntax:
#     # credo:disable-for-next-line CheckerName
#     # credo:disable-for-previous-line CheckerName

%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"_test.exs$", ~r"/test/support/"]
      },
      requires: [],
      checks: [
        # Design Checks
        {Credo.Check.Design.DuplicatedCode, false},  # Disabled: Too noisy for DSL-heavy code

        # Readability Checks
        {Credo.Check.Readability.ModuleDoc, true},
        {Credo.Check.Readability.FunctionArity, max_arity: 6},  # Jido uses higher arities for actions

        # Refactoring Checks
        {Credo.Check.Refactor.MapInto, false},  # Disabled: Map.into is sometimes clearer

        # Warning Checks
        {Credo.Check.Warning.LazyLogging, false},  # Disabled: Not applicable to compiled language
        {Credo.Check.Warning.LeakyEnvironment, false},  # Disabled: Not applicable to Elixir

        # Custom Ignores (add with justifications as discovered)
      ]
    }
  ]
}
```

**Tests to Add:**
- None (configuration only)

**Dependencies:** None

**Effort:** 2-3 hours

---

### Phase 4: Verify CI Integration and Document

**Objective:** Ensure CI enforces quality gate and document procedures.

**Success Criteria:**
- CI lint job runs `mix quality` (or equivalent)
- Documentation exists for running quality checks locally
- Contributing guidelines updated

**Tasks:**

1. **Verify Shared GitHub Actions**
   - Check if `agentjido/github-actions/.github/workflows/elixir-lint.yml@main` includes Dialyzer
   - File issue/update if `mix dialyzer` is missing
   - Ensure `mix compile --warnings-as-errors` is run

2. **Update Package Documentation**
   - Add QUALITY.md to each package documenting:
     - How to run `mix quality` locally
     - How to regenerate PLT if needed
     - Common Dialyzer issues and resolutions

3. **Update Contributing Guidelines**
   - Add to CONTRIBUTING.md in each package:
     - Pre-commit requirement: `mix quality` must pass
     - CI will block if quality checks fail
     - How to configure local editor integration

**Files to Modify:**
- `projects/jido/CONTRIBUTING.md` (create if missing)
- `projects/jido_action/CONTRIBUTING.md`
- `projects/jido_signal/CONTRIBUTING.md`
- `projects/jido_ai/CONTRIBUTING.md`
- `projects/jido/QUALITY.md` (create)
- `projects/jido_action/QUALITY.md` (create)
- `projects/jido_signal/QUALITY.md` (create)
- `projects/jido_ai/QUALITY.md` (create)
- `agentjido/github-actions` (if CI changes needed)

**Tests to Add:**
- None (documentation only)

**Dependencies:** Phases 1-3 (must have clean state before documenting)

**Effort:** 1-2 hours

---

## Quality & Testing Strategy

### Test Categories

**Unit Tests:** Not applicable (this is quality tooling, not feature code)

**Integration Tests:**
- Verify `mix quality` runs successfully across all packages
- Verify CI lint job passes after changes

**Manual Testing:**
- Run `mix quality` locally before committing
- Verify PLT regeneration works if needed

### Coverage Targets

Not applicable (not testing application code)

### Quality Gates

**Pre-commit:**
```bash
mix quality
```

**Pre-merge (CI):**
- Lint workflow must pass on OTP 27/28 + Elixir 1.18/1.19
- Test workflow must pass

**Pre-release:**
- All 4 packages pass `mix quality`
- Documentation updated

---

## Risk Assessment

### Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Fixing Dialyzer warnings requires API changes | Medium | Medium | Research impacts; version bump if breaking |
| ReqLLM.Tool.name/1 call indicates dependency mismatch | Low | Low | Check reqllm version, update or add wrapper |
| Unused functions are actually incomplete features | Medium | Low | Mark with `@doc false` and TODO comment |

### Dependency Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Shared GitHub Actions can't be updated | Low | Low | Fork workflows or add package-specific CI |
| Dialyzer PLT becomes invalid after OTP upgrade | High | Low | Document regeneration; add script |

### Timeline Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| More warnings found after initial fixes | Low | Low | Budget 20% buffer for discovered issues |
| CI workflow changes require coordination | Medium | Low | Can ship with manual checks until CI updated |

---

## Success Criteria

### Measurable Outcomes

1. ✅ All 4 packages pass `mix quality` locally
2. ✅ CI lint job passes on all OTP/Elixir version combinations
3. ✅ Zero compiler warnings across all packages
4. ✅ Zero Dialyzer warnings across all packages
5. ✅ Zero high-priority Credo issues across all packages
6. ✅ Each package has documented quality standards in `.credo.exs`
7. ✅ Each package has CONTRIBUTING.md referencing `mix quality`
8. ✅ Each package has QUALITY.md with troubleshooting guide

### Definition of "Done"

- [ ] `mix quality` passes on jido
- [ ] `mix quality` passes on jido_action
- [ ] `mix quality` passes on jido_signal
- [ ] `mix quality` passes on jido_ai
- [ ] All 4 packages have `.credo.exs` files
- [ ] All 4 packages have CONTRIBUTING.md mentioning quality gate
- [ ] All 4 packages have QUALITY.md documentation
- [ ] CI lint job verified/enhanced
- [ ] Item state updated to "planned"
- [ ] Progress documented in ralph/progress.txt

### Acceptance Testing Approach

**Automated:**
- CI lint workflow passing on all package PRs

**Manual:**
- Developer runs `mix quality` locally before each commit
- Release checklist includes `mix quality` verification

---

## Execution Checklist

When implementing this plan:

1. **Phase 1:** Fix jido_ai compilation warnings
   - [ ] Add def headers for multi-clause functions
   - [ ] Prefix unused variables with underscore
   - [ ] Remove unused aliases
   - [ ] Verify `mix compile --warnings-as-errors` passes

2. **Phase 2:** Fix jido_ai Dialyzer warnings
   - [ ] Remove/mark unused functions
   - [ ] Fix contract violations
   - [ ] Fix pattern match coverage issues
   - [ ] Resolve ReqLLM.Tool.name/1 call
   - [ ] Verify `mix dialyzer` passes

3. **Phase 3:** Create Credo configurations
   - [ ] Create `projects/jido/.credo.exs`
   - [ ] Create `projects/jido_action/.credo.exs`
   - [ ] Create `projects/jido_signal/.credo.exs`
   - [ ] Create `projects/jido_ai/.credo.exs`
   - [ ] Verify `mix credo --min-priority higher` passes everywhere

4. **Phase 4:** Verify CI and document
   - [ ] Check shared GitHub Actions include Dialyzer
   - [ ] Create/update CONTRIBUTING.md in all 4 packages
   - [ ] Create QUALITY.md in all 4 packages
   - [ ] Run full `mix quality` on all packages as final verification

5. **Close out:**
   - [ ] Run `mix roadmap.edit 004 --state planned`
   - [ ] Update `ralph/progress.txt`

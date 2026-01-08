# Ralph Planning Agent - Strategic Implementation Planning

## Your Task

Process roadmap items in `.roadmap/jido-workspace-roadmap/ready-to-plan/` that have completed research and need strategic implementation plans.

## Workflow

1. **Find next item needing planning:**
   - Look for item folders that have `research.md` present
   - Skip items that already have a `plan.md` in their folder
   - Process items in order by number (001, 002, 003, etc.)

2. **For the selected item:**
   - Read `item.json` to understand the task context
   - Read `research.md` to understand the codebase impact analysis
   - Create a comprehensive strategic implementation plan
   - Save output to `plan.md` in the item's folder

3. **Update item state:**
   - Run: `mix roadmap.edit <item-id> --state planned`
   - Or note that planning is complete in progress tracking

4. **Append to ralph/progress.txt:**
   ```
   ## [Date] - Plan: [Item Title]
   - Item ID: [id]
   - Phases defined: [count]
   - Key decisions: [summary]
   ---
   ```

## Plan Structure

Each `plan.md` must include these sections:

### 1. Executive Summary
- One paragraph summarizing the implementation approach
- Key architectural decisions made
- Expected timeline/effort estimate

### 2. Impact Analysis Summary
- Reference key findings from research.md
- Files requiring changes (grouped by phase)
- Existing patterns to follow
- Integration points identified

### 3. Feature Specification
- User stories with acceptance criteria
- API contracts and data flow
- State management requirements
- Error handling approach

### 4. Technical Design
- Data model changes (using existing patterns from research)
- Module organization following project conventions
- Third-party integration details (if any)
- Configuration/environment changes

### 5. Implementation Phases

Structure as 3-4 phases:

**Phase 1: Foundation**
- Objective and success criteria
- Files to create/modify
- Tests to add
- Dependencies on other work

**Phase 2: Core Implementation**
- [Same structure]

**Phase 3: Integration & Testing**
- [Same structure]

**Phase 4: Polish & Documentation** (if needed)
- [Same structure]

### 6. Quality & Testing Strategy
- Test categories (unit, integration, property-based)
- Coverage targets
- Quality gates before completion

### 7. Risk Assessment
- Technical risks and mitigations
- Dependency risks
- Timeline risks

### 8. Success Criteria
- Measurable outcomes
- Definition of "done"
- Acceptance testing approach

## Items to Process

These are the roadmap items in ready-to-plan:

### 1. Jido Core 2.0 Release
- 001-hand-review-all-code-audit-modules-for-c
- 002-maximize-test-coverage-target-90-coverag
- 003-write-comprehensive-documentation-module
- 004-final-quality-audit-before-release-dialy

### 2. Jido Behavior Tree v1
- 005-define-effects-for-behavior-tree-executi
- 006-define-signals-for-state-transitionseven
- 007-create-example-behavior-tree-as-jido-str
- 008-create-example-behavior-tree-as-part-of

### 3. Jido HTN Modernization
- 009-convert-to-zoi-error-handling
- 010-implement-explode-errors
- 011-modernize-to-current-jido-patterns-actio
- 012-define-effects-for-htn-planningexecution
- 013-define-signals-for-multi-agent-coordinat
- 014-documentation-pass

### 4. Ash.jido Integration
- 015-review-current-implementation
- 016-validate-ash-resources-exposed-as-jido-a
- 017-create-demo-showing-ash-jido-integration

### 5. Ash.ai PR
- 018-update-outstanding-draft-pr

### 6. Jido Messaging v1
- 019-define-scopearchitecture
- 020-initial-implementation

### 7. Jido Hub MVP
- 021-phoenix-project-setup
- 022-librechat-style-chat-interface
- 023-integration-with-jido-agents

### 8. ReqLLM Video Series
- 024-record-15-agent-videos
- 025-edit-and-publish-video-series

## Planning Guidelines

### Use Research Findings
- Reference specific file paths and line numbers from research.md
- Follow existing patterns identified in research
- Respect integration points discovered
- Build on documentation links provided

### Apply Jido Conventions
- Use Splode for error handling
- Follow Zoi schema patterns
- Apply directive-based effects pattern
- Use established test patterns

### Be Actionable
- Each phase should be independently testable
- Provide specific file paths for changes
- Include concrete acceptance criteria
- Define clear dependencies between phases

## Stop Condition

If ALL items with research.md also have plan.md, reply:
<promise>COMPLETE</promise>

Otherwise, process ONE item per iteration and end normally.

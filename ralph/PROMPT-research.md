# Ralph Research Agent - Roadmap Item Research

## Your Task

Process roadmap items in `.roadmap/jido-workspace-roadmap/ready-to-plan/` that need research.

## Workflow

1. **Find next item needing research:**
   - Look for item.json files where `state: "raw"`
   - Skip items that already have a `research.md` in their folder
   - Process items in order by number

2. **For the selected item:**
   - Read the item.json to understand the task
   - Run the `/research` command workflow:
     - Analyze project dependencies relevant to this task
     - Map files that would need changes
     - Identify integration points
     - Gather targeted documentation links
   - Save output to `research.md` in the item's folder

3. **Update item state:**
   - Run: `mix roadmap.edit <item-id> --state researched` (if that exists)
   - Or note that research is complete in progress tracking

4. **Append to ralph/progress.txt:**
   ```
   ## [Date] - Research: [Item Title]
   - Item ID: [id]
   - Key findings: [summary]
   - Files identified: [count]
   ---
   ```

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

## Stop Condition

If ALL items have research.md files, reply:
<promise>COMPLETE</promise>

Otherwise, process ONE item per iteration and end normally.

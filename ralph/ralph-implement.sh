#!/bin/bash
# Ralph Implementation Runner - Implements ONE roadmap item end-to-end
# Usage: ./ralph/ralph-implement.sh <roadmap-item-path> [--max-iterations N] [--cooldown SECONDS] [--dry-run]
#
# Example:
#   ./ralph/ralph-implement.sh .roadmap/jido-workspace-roadmap/ready-to-plan/1-jido-core-20-release/001-hand-review-all-code-audit-modules-for-c
#
# What it does:
#   1. Validates the item has plan.md and research.md
#   2. Creates a feature branch from main
#   3. Generates an implementation prompt
#   4. Runs Ralph loop until complete
#   5. Creates a PR for review
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Defaults
MAX_ITERATIONS=30
COOLDOWN=5
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"

# Parse arguments
ITEM_PATH=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-iterations)
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --cooldown)
      COOLDOWN="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      echo "Usage: ./ralph/ralph-implement.sh <roadmap-item-path> [options]"
      echo ""
      echo "Options:"
      echo "  --max-iterations N   Maximum iterations (default: 30)"
      echo "  --cooldown SECONDS   Cooldown between iterations (default: 5)"
      echo "  --dry-run            Show what would happen without executing"
      echo "  -h, --help           Show this help"
      echo ""
      echo "Example:"
      echo "  ./ralph/ralph-implement.sh .roadmap/jido-workspace-roadmap/ready-to-plan/1-jido-core-20-release/001-hand-review"
      exit 0
      ;;
    *)
      if [[ -z "$ITEM_PATH" ]]; then
        ITEM_PATH="$1"
      fi
      shift
      ;;
  esac
done

# Validate item path
if [[ -z "$ITEM_PATH" ]]; then
  echo -e "${RED}❌ Error: No roadmap item path provided${NC}"
  echo "Usage: ./ralph/ralph-implement.sh <roadmap-item-path>"
  exit 1
fi

# Convert to absolute path if relative
if [[ ! "$ITEM_PATH" = /* ]]; then
  ITEM_PATH="$WORKSPACE_ROOT/$ITEM_PATH"
fi

# Validate item directory exists
if [[ ! -d "$ITEM_PATH" ]]; then
  echo -e "${RED}❌ Error: Item directory not found: $ITEM_PATH${NC}"
  exit 1
fi

# Validate required files exist
if [[ ! -f "$ITEM_PATH/item.json" ]]; then
  echo -e "${RED}❌ Error: item.json not found in $ITEM_PATH${NC}"
  exit 1
fi

if [[ ! -f "$ITEM_PATH/plan.md" ]]; then
  echo -e "${RED}❌ Error: plan.md not found - run planning first${NC}"
  exit 1
fi

# Extract item info from item.json
ITEM_ID=$(jq -r '.id' "$ITEM_PATH/item.json")
ITEM_TITLE=$(jq -r '.title' "$ITEM_PATH/item.json")
ITEM_NUMBER=$(jq -r '.number' "$ITEM_PATH/item.json")

# Generate branch name from item
BRANCH_NAME="roadmap/$(basename "$ITEM_PATH" | sed 's/^[0-9]*-//')"
# Truncate to reasonable length and clean up
BRANCH_NAME=$(echo "$BRANCH_NAME" | cut -c1-50 | sed 's/-$//')

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Ralph Implementation Runner                               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Item:${NC}    $ITEM_TITLE"
echo -e "${GREEN}ID:${NC}      $ITEM_ID"
echo -e "${GREEN}Branch:${NC}  $BRANCH_NAME"
echo -e "${GREEN}Max iterations:${NC} $MAX_ITERATIONS"
echo ""

if $DRY_RUN; then
  echo -e "${YELLOW}🔍 DRY RUN - No changes will be made${NC}"
  echo ""
fi

# Create log directory
mkdir -p "$LOG_DIR"

# Generate the implementation prompt
PROMPT_FILE="$SCRIPT_DIR/PROMPT-impl-current.md"

generate_prompt() {
  cat > "$PROMPT_FILE" << 'PROMPT_HEADER'
# Ralph Implementation Agent

You are implementing a roadmap item. Your job is to execute the implementation plan systematically.

## Workflow

1. **Read the plan** - Understand what needs to be done
2. **Check progress.txt** - See what's already been accomplished
3. **Pick the next task** - From the implementation phases in the plan
4. **Implement ONE phase or sub-task** - Make focused, incremental progress
5. **Test your changes** - Run `mix test`, `mix compile`, etc.
6. **Commit with conventional commits** - `git add -A && git commit -m "type(scope): description"`
7. **Push changes** - `git push`
8. **Update progress.txt** - Document what was done
9. **Continue** - Move to next task

## Progress Tracking

APPEND to ralph/progress.txt after each significant change:

```
## [Date] - [Phase/Task]
- What was implemented
- Files changed
- Tests added/modified
- **Learnings:** Patterns discovered, gotchas encountered
---
```

## Important Rules

- Make focused, incremental changes - one phase or sub-task at a time
- Always run tests before committing
- Use conventional commits: `feat(scope):`, `fix(scope):`, `refactor(scope):`, `test(scope):`, `docs(scope):`
- Push after each commit to maintain progress
- If stuck, document the blocker in progress.txt and move on

## Stop Condition

When ALL phases in the plan are complete and tested:
1. Update progress.txt with final summary
2. Reply with: <promise>COMPLETE</promise>

Otherwise, implement one task and end your turn normally.

---

PROMPT_HEADER

  echo "## Item Details" >> "$PROMPT_FILE"
  echo "" >> "$PROMPT_FILE"
  echo '```json' >> "$PROMPT_FILE"
  cat "$ITEM_PATH/item.json" >> "$PROMPT_FILE"
  echo '```' >> "$PROMPT_FILE"
  echo "" >> "$PROMPT_FILE"
  
  echo "## Implementation Plan" >> "$PROMPT_FILE"
  echo "" >> "$PROMPT_FILE"
  cat "$ITEM_PATH/plan.md" >> "$PROMPT_FILE"
  echo "" >> "$PROMPT_FILE"
  
  if [[ -f "$ITEM_PATH/research.md" ]]; then
    echo "## Research Context" >> "$PROMPT_FILE"
    echo "" >> "$PROMPT_FILE"
    echo "<details>" >> "$PROMPT_FILE"
    echo "<summary>Click to expand research findings</summary>" >> "$PROMPT_FILE"
    echo "" >> "$PROMPT_FILE"
    cat "$ITEM_PATH/research.md" >> "$PROMPT_FILE"
    echo "" >> "$PROMPT_FILE"
    echo "</details>" >> "$PROMPT_FILE"
  fi
}

# Step 1: Create branch
create_branch() {
  echo -e "${BLUE}📌 Step 1: Creating branch${NC}"
  
  # Check if we're on main/master
  CURRENT_BRANCH=$(git branch --show-current)
  
  # Check if branch already exists
  if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    echo -e "${YELLOW}⚠️  Branch $BRANCH_NAME already exists, switching to it${NC}"
    git checkout "$BRANCH_NAME"
  else
    # Make sure we're on main and up to date
    if [[ "$CURRENT_BRANCH" != "main" && "$CURRENT_BRANCH" != "master" ]]; then
      echo "Switching to main branch first..."
      git checkout main || git checkout master
    fi
    
    echo "Pulling latest changes..."
    git pull --rebase
    
    echo "Creating branch: $BRANCH_NAME"
    git checkout -b "$BRANCH_NAME"
    git push -u origin "$BRANCH_NAME"
  fi
  
  echo -e "${GREEN}✓ On branch: $(git branch --show-current)${NC}"
  echo ""
}

# Step 2: Initialize progress tracking
init_progress() {
  echo -e "${BLUE}📝 Step 2: Initializing progress tracking${NC}"
  
  if ! grep -q "# Implementation: $ITEM_TITLE" "$SCRIPT_DIR/progress.txt" 2>/dev/null; then
    cat >> "$SCRIPT_DIR/progress.txt" << EOF

# Implementation: $ITEM_TITLE
**Item ID**: $ITEM_ID
**Branch**: $BRANCH_NAME
**Started**: $(date +%Y-%m-%d)

---

EOF
    echo -e "${GREEN}✓ Progress tracking initialized${NC}"
  else
    echo -e "${YELLOW}⚠️  Progress section already exists${NC}"
  fi
  echo ""
}

# Step 3: Generate prompt
generate_implementation_prompt() {
  echo -e "${BLUE}📄 Step 3: Generating implementation prompt${NC}"
  generate_prompt
  echo -e "${GREEN}✓ Prompt generated: $PROMPT_FILE${NC}"
  echo ""
}

# Step 4: Run the Ralph loop
run_ralph_loop() {
  echo -e "${BLUE}🔄 Step 4: Running Ralph implementation loop${NC}"
  echo ""
  
  for i in $(seq 1 $MAX_ITERATIONS); do
    echo -e "${BLUE}═══ Iteration $i of $MAX_ITERATIONS ═══${NC}"
    
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    LOG_FILE="$LOG_DIR/impl-$TIMESTAMP.log"
    
    # Run Claude with the prompt
    OUTPUT=$(cat "$PROMPT_FILE" \
      | claude -p --dangerously-skip-permissions 2>&1 \
      | tee "$LOG_FILE" \
      | tee /dev/stderr) || true
    
    # Check for completion
    if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
      echo ""
      echo -e "${GREEN}✅ Implementation complete!${NC}"
      return 0
    fi
    
    # Check if progress was made (optional heuristic)
    COMMIT_COUNT=$(git rev-list --count "main..$BRANCH_NAME" 2>/dev/null || echo "0")
    echo -e "${YELLOW}📊 Commits on branch: $COMMIT_COUNT${NC}"
    
    echo "Cooling down for $COOLDOWN seconds..."
    sleep $COOLDOWN
  done
  
  echo -e "${YELLOW}⚠️  Max iterations reached without completion${NC}"
  return 1
}

# Step 5: Create PR
create_pr() {
  echo -e "${BLUE}🔗 Step 5: Creating Pull Request${NC}"
  
  # Check if gh CLI is available
  if ! command -v gh &> /dev/null; then
    echo -e "${YELLOW}⚠️  GitHub CLI (gh) not found - please create PR manually${NC}"
    echo "Branch: $BRANCH_NAME"
    return 0
  fi
  
  # Generate PR body
  PR_BODY=$(cat << EOF
## Roadmap Item Implementation

**Item**: $ITEM_TITLE
**ID**: \`$ITEM_ID\`

### Implementation Summary

This PR implements the roadmap item according to the plan in:
\`$ITEM_PATH/plan.md\`

### Changes

$(git log main..$BRANCH_NAME --oneline 2>/dev/null || echo "See commit history")

### Testing

- [ ] All tests pass
- [ ] Manual testing completed
- [ ] Documentation updated

---
*Generated by Ralph Implementation Runner*
EOF
)
  
  # Create the PR
  PR_URL=$(gh pr create \
    --title "roadmap: $ITEM_TITLE" \
    --body "$PR_BODY" \
    --base main \
    --head "$BRANCH_NAME" 2>&1) || {
    echo -e "${YELLOW}⚠️  Could not create PR (may already exist)${NC}"
    PR_URL=$(gh pr view --json url -q .url 2>/dev/null || echo "")
  }
  
  if [[ -n "$PR_URL" ]]; then
    echo -e "${GREEN}✓ PR created/found: $PR_URL${NC}"
    
    # Update item.json with PR URL
    jq --arg pr "$PR_URL" '.pr_url = $pr | .state = "in_pr"' "$ITEM_PATH/item.json" > "$ITEM_PATH/item.json.tmp"
    mv "$ITEM_PATH/item.json.tmp" "$ITEM_PATH/item.json"
    
    git add "$ITEM_PATH/item.json"
    git commit -m "chore(roadmap): update item state to in_pr" || true
    git push || true
  fi
  
  echo ""
}

# Main execution
main() {
  cd "$WORKSPACE_ROOT"
  
  if $DRY_RUN; then
    echo -e "${YELLOW}Would execute:${NC}"
    echo "  1. Create branch: $BRANCH_NAME"
    echo "  2. Initialize progress tracking"
    echo "  3. Generate prompt from plan.md"
    echo "  4. Run Ralph loop (max $MAX_ITERATIONS iterations)"
    echo "  5. Create PR for review"
    echo ""
    echo -e "${YELLOW}Generated prompt preview:${NC}"
    generate_prompt
    head -50 "$PROMPT_FILE"
    echo "..."
    rm "$PROMPT_FILE"
    exit 0
  fi
  
  # Execute steps
  create_branch
  init_progress
  generate_implementation_prompt
  
  if run_ralph_loop; then
    create_pr
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ Implementation Complete!                               ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
  else
    create_pr  # Still create PR for partial progress
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  ⚠️  Implementation incomplete - PR created for review     ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
  fi
}

main

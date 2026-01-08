#!/bin/bash
# Direct Planning Runner - Runs planning on all items with research.md but no plan.md
# Usage: ./ralph/plan-all.sh [--dry-run]
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROADMAP_DIR="$SCRIPT_DIR/../.roadmap/jido-workspace-roadmap/ready-to-plan"
LOG_DIR="$SCRIPT_DIR/logs"
DRY_RUN=false

if [[ "$1" == "--dry-run" ]]; then
  DRY_RUN=true
fi

mkdir -p "$LOG_DIR"

echo "📋 Direct Planning Runner"
echo "========================="
echo "Roadmap: $ROADMAP_DIR"
echo "Dry run: $DRY_RUN"
echo ""

# Find all items needing planning
ITEMS=()
while IFS= read -r -d '' item_dir; do
  if [ -f "$item_dir/research.md" ] && [ ! -f "$item_dir/plan.md" ]; then
    ITEMS+=("$item_dir")
  fi
done < <(find "$ROADMAP_DIR" -mindepth 2 -maxdepth 2 -type d -print0 | sort -z)

echo "📊 Found ${#ITEMS[@]} items needing planning:"
for item in "${ITEMS[@]}"; do
  basename "$item"
done
echo ""

if [ ${#ITEMS[@]} -eq 0 ]; then
  echo "✅ All researched items already have plans!"
  exit 0
fi

if $DRY_RUN; then
  echo "🔍 Dry run - would process above items"
  exit 0
fi

# Process each item
for item_dir in "${ITEMS[@]}"; do
  ITEM_NAME=$(basename "$item_dir")
  SECTION_NAME=$(basename "$(dirname "$item_dir")")
  ITEM_ID=$(jq -r '.id' "$item_dir/item.json" 2>/dev/null || echo "$ITEM_NAME")
  
  echo "═══════════════════════════════════════"
  echo "📝 Planning: $ITEM_NAME"
  echo "   Section: $SECTION_NAME"
  echo "═══════════════════════════════════════"
  
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  LOG_FILE="$LOG_DIR/plan-$ITEM_NAME-$TIMESTAMP.log"
  
  # Create item-specific prompt
  ITEM_PROMPT=$(cat <<EOF
# Plan This Roadmap Item

## Item Details
$(cat "$item_dir/item.json")

## Research Findings
$(cat "$item_dir/research.md")

---

## Your Task

Create a strategic implementation plan for this item based on the research findings above.

Save the plan to: $item_dir/plan.md

Follow the structure from the planning guidelines:

1. **Executive Summary** - One paragraph approach, key decisions, effort estimate
2. **Impact Analysis Summary** - Key findings from research, files grouped by phase
3. **Feature Specification** - User stories, API contracts, state management
4. **Technical Design** - Data model, module organization, integrations
5. **Implementation Phases** - 3-4 phases with objectives, files, tests, dependencies
6. **Quality & Testing Strategy** - Test categories, coverage, quality gates
7. **Risk Assessment** - Technical, dependency, and timeline risks
8. **Success Criteria** - Measurable outcomes, definition of done

After creating the plan, update the item state:
\`\`\`bash
mix roadmap.edit "$ITEM_ID" --state planned
\`\`\`

Then append to ralph/progress.txt with the planning summary.
EOF
)

  echo "$ITEM_PROMPT" | claude -p --dangerously-skip-permissions 2>&1 | tee "$LOG_FILE"
  
  echo ""
  echo "✅ Completed: $ITEM_NAME"
  echo ""
  
  # Brief cooldown between items
  echo "💤 Cooldown: 3s..."
  sleep 3
done

echo ""
echo "✅ All planning complete!"
echo "   Processed ${#ITEMS[@]} items"

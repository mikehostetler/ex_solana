#!/bin/bash
# Ralph Plan Runner - Iterates over roadmap items running strategic planning
# Usage: ./ralph/ralph-plan.sh [max-iterations] [--cooldown SECONDS]
set -e

MAX_ITERATIONS=${1:-30}
COOLDOWN=5
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"

# Parse optional args
shift || true
while [[ $# -gt 0 ]]; do
  case $1 in
    --cooldown)
      COOLDOWN="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

mkdir -p "$LOG_DIR"

echo "📋 Starting Ralph Planning Loop"
echo "================================"
echo "Max iterations: $MAX_ITERATIONS"
echo "Cooldown: ${COOLDOWN}s"
echo "Prompt: $SCRIPT_DIR/PROMPT-plan.md"
echo ""

# Check prerequisites
ROADMAP_DIR="$SCRIPT_DIR/../.roadmap/jido-workspace-roadmap/ready-to-plan"
if [ ! -d "$ROADMAP_DIR" ]; then
  echo "❌ Roadmap directory not found: $ROADMAP_DIR"
  exit 1
fi

# Count items with research but no plan
count_pending() {
  local pending=0
  while IFS= read -r -d '' item_dir; do
    if [ -f "$item_dir/research.md" ] && [ ! -f "$item_dir/plan.md" ]; then
      ((pending++))
    fi
  done < <(find "$ROADMAP_DIR" -mindepth 2 -maxdepth 2 -type d -print0 | sort -z)
  echo $pending
}

PENDING=$(count_pending)
echo "📊 Items with research.md but no plan.md: $PENDING"
echo ""

if [ "$PENDING" -eq 0 ]; then
  echo "✅ All researched items already have plans!"
  exit 0
fi

for i in $(seq 1 $MAX_ITERATIONS); do
  echo "═══ Planning Iteration $i ═══"
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  LOG_FILE="$LOG_DIR/plan-$TIMESTAMP.log"
  
  OUTPUT=$(cat "$SCRIPT_DIR/PROMPT-plan.md" \
    | claude -p --dangerously-skip-permissions 2>&1 \
    | tee "$LOG_FILE" \
    | tee /dev/stderr) || true
  
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "✅ All planning complete!"
    exit 0
  fi
  
  # Show progress
  REMAINING=$(count_pending)
  echo ""
  echo "📊 Remaining items: $REMAINING"
  
  if [ "$REMAINING" -eq 0 ]; then
    echo "✅ All planning complete!"
    exit 0
  fi
  
  echo "💤 Cooldown: ${COOLDOWN}s..."
  sleep $COOLDOWN
done

echo ""
echo "⚠️ Max iterations ($MAX_ITERATIONS) reached"
exit 1

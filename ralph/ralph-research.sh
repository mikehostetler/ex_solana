#!/bin/bash
# Ralph Research Runner - Iterates over roadmap items running /research
# Usage: ./ralph/ralph-research.sh [max-iterations]
set -e

MAX_ITERATIONS=${1:-30}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"

mkdir -p "$LOG_DIR"

echo "🔬 Starting Ralph Research Loop"
echo "================================"
echo "Max iterations: $MAX_ITERATIONS"
echo "Prompt: $SCRIPT_DIR/PROMPT-research.md"
echo ""

for i in $(seq 1 $MAX_ITERATIONS); do
  echo "═══ Research Iteration $i ═══"
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  LOG_FILE="$LOG_DIR/research-$TIMESTAMP.log"
  
  OUTPUT=$(cat "$SCRIPT_DIR/PROMPT-research.md" \
    | claude -p --dangerously-skip-permissions 2>&1 \
    | tee "$LOG_FILE" \
    | tee /dev/stderr) || true
  
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "✅ All research complete!"
    exit 0
  fi
  
  echo ""
  echo "💤 Cooldown: 5s..."
  sleep 5
done

echo ""
echo "⚠️ Max iterations ($MAX_ITERATIONS) reached"
exit 1

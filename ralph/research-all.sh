#!/bin/bash
# Research all roadmap items in ready-to-plan
# Usage: ./ralph/research-all.sh [--dry-run] [--max-per-run N]
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$SCRIPT_DIR")"
ROADMAP_DIR="$WORKSPACE_ROOT/.roadmap/jido-workspace-roadmap/ready-to-plan"
LOG_DIR="$SCRIPT_DIR/logs/research"
DRY_RUN=false
MAX_PER_RUN=999
COOLDOWN=5

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --max-per-run)
      MAX_PER_RUN="$2"
      shift 2
      ;;
    --cooldown)
      COOLDOWN="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

mkdir -p "$LOG_DIR"

echo "🔬 Roadmap Research Runner"
echo "=========================="
echo "Roadmap dir: $ROADMAP_DIR"
echo "Dry run: $DRY_RUN"
echo "Max per run: $MAX_PER_RUN"
echo "Cooldown: ${COOLDOWN}s"
echo ""

# Collect all item.json files
ITEMS=()
while IFS= read -r -d '' item; do
  ITEMS+=("$item")
done < <(find "$ROADMAP_DIR" -name "item.json" -print0 | sort -z)

echo "Found ${#ITEMS[@]} roadmap items"
echo ""

PROCESSED=0
SKIPPED=0
FAILED=0

for item_json in "${ITEMS[@]}"; do
  if [[ $PROCESSED -ge $MAX_PER_RUN ]]; then
    echo "⏸️  Max per run ($MAX_PER_RUN) reached, stopping"
    break
  fi

  # Extract item info
  item_dir="$(dirname "$item_json")"
  item_id=$(jq -r '.id' "$item_json")
  item_title=$(jq -r '.title' "$item_json")
  item_state=$(jq -r '.state' "$item_json")
  
  # Check if research.md already exists
  research_file="$item_dir/research.md"
  if [[ -f "$research_file" ]]; then
    echo "⏭️  SKIP: $item_id (research.md exists)"
    ((SKIPPED++))
    continue
  fi

  # Only process raw items
  if [[ "$item_state" != "raw" ]]; then
    echo "⏭️  SKIP: $item_id (state: $item_state, not raw)"
    ((SKIPPED++))
    continue
  fi

  echo "═══════════════════════════════════════════════════════════════"
  echo "📋 Item: $item_id"
  echo "📝 Title: $item_title"
  echo "📂 Dir: $item_dir"
  echo "═══════════════════════════════════════════════════════════════"

  if $DRY_RUN; then
    echo "🔍 [DRY RUN] Would run: /research on $item_json"
    echo ""
    ((PROCESSED++))
    continue
  fi

  # Create the research prompt
  RESEARCH_PROMPT="Read the roadmap item at $item_json and perform comprehensive codebase impact analysis for this task.

Task: $item_title

Follow the /research command workflow:
1. Analyze the item's overview and context
2. Discover relevant project dependencies and patterns
3. Map all files that would need changes
4. Identify integration points and risks
5. Gather targeted documentation links

Save the research output to: $item_dir/research.md

When complete, output: <promise>COMPLETE</promise>"

  # Run claude with the research prompt
  LOG_FILE="$LOG_DIR/$(basename "$item_dir")-$(date +%Y%m%d-%H%M%S).log"
  
  echo "🚀 Running research..."
  echo "$RESEARCH_PROMPT" | claude -p --dangerously-skip-permissions 2>&1 | tee "$LOG_FILE"
  
  if [[ -f "$research_file" ]]; then
    echo "✅ Research complete: $research_file"
  else
    echo "⚠️  Research file not created"
    ((FAILED++))
  fi

  ((PROCESSED++))
  
  echo ""
  echo "💤 Cooldown: ${COOLDOWN}s..."
  sleep "$COOLDOWN"
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "📊 Summary"
echo "═══════════════════════════════════════════════════════════════"
echo "Processed: $PROCESSED"
echo "Skipped: $SKIPPED"
echo "Failed: $FAILED"
echo "Total items: ${#ITEMS[@]}"

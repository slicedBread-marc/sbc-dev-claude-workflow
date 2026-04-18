#!/usr/bin/env bash
# wf-goal-push.sh <plan-id-or-name> <new-goal> <trigger>
# Archives the current goal line to ### Goal History and writes a new active goal.
#
# Example:
#   wf-goal-push.sh PLN-074 "Fix flicker on re-render (show-stopper)" "Verify: 2 findings"
#
# The Goal History table is appended to (or created if missing).
# Exit 0 on success, 1 on error.

set -euo pipefail

raw_id="${1:-}"
new_goal="${2:-}"
trigger="${3:-}"

plan_id=$(echo "$raw_id" | grep -oE 'PLN-[0-9]+')
if [ -z "$plan_id" ] || [ -z "$new_goal" ] || [ -z "$trigger" ]; then
  echo "Usage: $0 <plan-id-or-name> <new-goal> <trigger>" >&2
  exit 1
fi

REGISTRY="plans/REGISTRY.md"
[ -f "$REGISTRY" ] || { echo "Error: $REGISTRY not found" >&2; exit 1; }

# Resolve plan dir
row=$(grep "| $plan_id |" "$REGISTRY" | head -1)
[ -n "$row" ] || { echo "Error: $plan_id not found in registry" >&2; exit 1; }
slug=$(echo "$row" | awk -F'|' '{print $3}' | xargs)
plan_dir="plans/${plan_id}-${slug}"
plan_file="$plan_dir/plan.md"
[ -f "$plan_file" ] || { echo "Error: $plan_file not found" >&2; exit 1; }

# Read current goal (first non-empty line after ## Goal)
current_goal=$(grep -A 1 "^## Goal" "$plan_file" | tail -1 | sed 's/^[[:space:]]*//')
[ -n "$current_goal" ] || { echo "Error: no current goal found in $plan_file" >&2; exit 1; }

today=$(date +%Y-%m-%d)

# Ensure ### Goal History section exists
if ! grep -q "^### Goal History" "$plan_file"; then
  # Insert before the next ## section after ## Goal
  goal_line=$(grep -n "^## Goal" "$plan_file" | head -1 | cut -d: -f1)
  next_section=$(awk -v start="$((goal_line + 1))" 'NR > start && /^## / { print NR; exit }' "$plan_file")
  if [ -n "$next_section" ]; then
    insert_at=$((next_section - 1))
  else
    insert_at=$(wc -l < "$plan_file")
  fi
  awk -v n="$insert_at" '
    NR == n { print; print ""; print "### Goal History"; print "| Date | Previous Goal | Trigger | Resolution |"; print "|-|-|-|-|"; next }
    { print }
  ' "$plan_file" > "$plan_file.tmp" && mv "$plan_file.tmp" "$plan_file"
fi

# Append history row after the separator line
awk -v row="| $today | $current_goal | $trigger | — |" '
  { print }
  /^\|-\|-\|-\|-\|/ && !done { print row; done=1 }
' "$plan_file" > "$plan_file.tmp" && mv "$plan_file.tmp" "$plan_file"

# Replace the current goal line with the new goal
goal_line_num=$(grep -n "^## Goal" "$plan_file" | head -1 | cut -d: -f1)
content_line=$((goal_line_num + 1))
awk -v n="$content_line" -v goal="$new_goal" '
  NR == n { print goal; next }
  { print }
' "$plan_file" > "$plan_file.tmp" && mv "$plan_file.tmp" "$plan_file"

echo "Goal pushed: '$current_goal' → '$new_goal' (trigger: $trigger)"

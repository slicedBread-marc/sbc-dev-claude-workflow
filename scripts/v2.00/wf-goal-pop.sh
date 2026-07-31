#!/usr/bin/env bash
# wf-goal-pop.sh <plan-id-or-name>
# Restores the most recent unresolved goal from ### Goal History.
# Marks the history row as resolved with today's date.
#
# Example:
#   wf-goal-pop.sh PLN-074
#
# Exit 0 on success, 1 if no unresolved goal found.

set -euo pipefail

raw_id="${1:-}"

plan_id=$(echo "$raw_id" | grep -oE 'PLN-[0-9]+')
if [ -z "$plan_id" ]; then
  echo "Usage: $0 <plan-id-or-name>" >&2
  exit 1
fi

REGISTRY="plans/REGISTRY.md"
[ -f "$REGISTRY" ] || { echo "Error: $REGISTRY not found" >&2; exit 1; }

# Resolve plan dir
row=$(grep "^| $plan_id |" "$REGISTRY" | head -1)
[ -n "$row" ] || { echo "Error: $plan_id not found in registry" >&2; exit 1; }
slug=$(echo "$row" | awk -F'|' '{print $3}' | xargs)
plan_dir="plans/${plan_id}-${slug}"
plan_file="$plan_dir/plan.md"
[ -f "$plan_file" ] || { echo "Error: $plan_file not found" >&2; exit 1; }

# Find the most recent unresolved row (Resolution = —)
# Goal History rows: | Date | Previous Goal | Trigger | — |
unresolved_line=$(grep -n "| — |[[:space:]]*$" "$plan_file" | tail -1)
if [ -z "$unresolved_line" ]; then
  echo "No unresolved goal in history — nothing to pop" >&2
  exit 1
fi

line_num=$(echo "$unresolved_line" | cut -d: -f1)
line_content=$(echo "$unresolved_line" | cut -d: -f2-)

# Extract the previous goal from the row (field 3, pipe-delimited)
previous_goal=$(echo "$line_content" | awk -F'|' '{print $3}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
if [ -z "$previous_goal" ]; then
  echo "Error: could not extract previous goal from history row" >&2
  exit 1
fi

today=$(date +%Y-%m-%d)

# Mark the history row as resolved
sed -i '' "${line_num}s#| — |[[:space:]]*\$#| Resolved $today |#" "$plan_file"

# Replace the current goal line with the restored goal
goal_line_num=$(grep -n "^## Goal" "$plan_file" | head -1 | cut -d: -f1)
content_line=$((goal_line_num + 1))
sed -i '' "${content_line}s#.*#$previous_goal#" "$plan_file"

echo "Goal restored: '$previous_goal' (resolved $(date +%Y-%m-%d))"

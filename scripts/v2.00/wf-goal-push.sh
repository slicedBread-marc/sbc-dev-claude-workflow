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
  # Insert after the goal paragraph (before next ## section)
  # Find the line number of the next ## after ## Goal
  goal_line=$(grep -n "^## Goal" "$plan_file" | head -1 | cut -d: -f1)
  next_section=$(awk -v start="$((goal_line + 1))" 'NR > start && /^## / { print NR; exit }' "$plan_file")
  if [ -n "$next_section" ]; then
    insert_at=$((next_section - 1))
  else
    # No next section — append before EOF
    insert_at=$(wc -l < "$plan_file")
  fi
  sed -i '' "${insert_at}a\\
\\
### Goal History\\
| Date | Previous Goal | Trigger | Resolution |\\
|-|-|-|-|" "$plan_file"
fi

# Append history row
sed -i '' "/^|-|-|-|-|/a\\
| $today | $current_goal | $trigger | — |" "$plan_file"

# Replace the current goal line with the new goal
# The goal is the first non-empty line after "## Goal"
goal_line_num=$(grep -n "^## Goal" "$plan_file" | head -1 | cut -d: -f1)
content_line=$((goal_line_num + 1))
sed -i '' "${content_line}s#.*#$new_goal#" "$plan_file"

echo "Goal pushed: '$current_goal' → '$new_goal' (trigger: $trigger)"

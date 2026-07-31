#!/usr/bin/env bash
# wf-plan-info.sh <plan-id-or-name>
# Looks up a plan in REGISTRY.md and outputs key=value pairs.
# Output (eval-friendly — every value is single-quoted):
#   PLAN_ID='PLN-004'
#   PLAN_SLUG='deployment-date-footer'
#   PLAN_STATE='testing'
#   PLAN_BRANCH='feature/PLN-004-deployment-date-footer'
#   PLAN_DIR='plans/PLN-004-deployment-date-footer'
#   PLAN_NAME='PLN-004-deployment-date-footer'
#   PLAN_GOAL='Add deployment date to footer'
#
# Accepts either a plan ID (PLN-004) or full plan name (PLN-004-deployment-date-footer).
# Usage: eval "$(scripts/wf-plan-info.sh PLN-004)"
# Exit 0 if found, 1 if not.

set -euo pipefail

REGISTRY="plans/REGISTRY.md"
input="${1:-}"

if [ -z "$input" ]; then
  echo "Usage: $0 <plan-id-or-name>" >&2
  exit 1
fi

[ -f "$REGISTRY" ] || { echo "Error: $REGISTRY not found" >&2; exit 1; }

# Extract plan ID (PLN-NNN) from full name if needed
plan_id=$(echo "$input" | grep -oE 'PLN-[0-9]+')
if [ -z "$plan_id" ]; then
  echo "Error: could not extract plan ID from '$input'" >&2
  exit 1
fi

# Find the row
row=$(grep "| $plan_id |" "$REGISTRY" | head -1)
if [ -z "$row" ]; then
  echo "Error: $plan_id not found in $REGISTRY" >&2
  exit 1
fi

# Parse columns
id=$(echo "$row" | awk -F'|' '{print $2}' | xargs)
slug=$(echo "$row" | awk -F'|' '{print $3}' | xargs)
state=$(echo "$row" | awk -F'|' '{print $4}' | xargs)
branch=$(echo "$row" | awk -F'|' '{print $5}' | xargs)

plan_dir="plans/${id}-${slug}"
plan_name="${id}-${slug}"

# Extract goal from plan.md if it exists
goal=""
if [ -f "$plan_dir/plan.md" ]; then
  goal=$(grep -A 1 "^## Goal" "$plan_dir/plan.md" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)
fi

# Every value is single-quoted so eval survives spaces, semicolons, backticks, etc.
emit() {
  printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")"
}

emit PLAN_ID "$id"
emit PLAN_SLUG "$slug"
emit PLAN_STATE "$state"
emit PLAN_BRANCH "$branch"
emit PLAN_DIR "$plan_dir"
emit PLAN_NAME "$plan_name"
emit PLAN_GOAL "$goal"
if [ -z "$goal" ]; then
  echo "PLAN_GOAL_MISSING=true"
else
  echo "PLAN_GOAL_MISSING=false"
fi

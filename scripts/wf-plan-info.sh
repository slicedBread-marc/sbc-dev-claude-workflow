#!/usr/bin/env bash
# wf-plan-info.sh <plan-id>
# Looks up a plan in REGISTRY.md and outputs key=value pairs.
# Output (eval-friendly):
#   PLAN_ID=PLN-004
#   PLAN_SLUG=deployment-date-footer
#   PLAN_STATE=testing
#   PLAN_BRANCH=feature/PLN-004-deployment-date-footer
#   PLAN_DIR=plans/PLN-004-deployment-date-footer
#   PLAN_NAME=PLN-004-deployment-date-footer
#   PLAN_GOAL="Add deployment date to footer"
#
# Usage: eval "$(scripts/wf-plan-info.sh PLN-004)"
# Exit 0 if found, 1 if not.

set -euo pipefail

REGISTRY="plans/REGISTRY.md"
plan_id="${1:-}"

if [ -z "$plan_id" ]; then
  echo "Usage: $0 <plan-id>" >&2
  exit 1
fi

[ -f "$REGISTRY" ] || { echo "Error: $REGISTRY not found" >&2; exit 1; }

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

echo "PLAN_ID=$id"
echo "PLAN_SLUG=$slug"
echo "PLAN_STATE=$state"
echo "PLAN_BRANCH=$branch"
echo "PLAN_DIR=$plan_dir"
echo "PLAN_NAME=$plan_name"
echo "PLAN_GOAL=\"$goal\""

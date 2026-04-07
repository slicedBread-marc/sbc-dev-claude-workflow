#!/usr/bin/env bash
# wf-registry-update.sh <plan-id> <from-state> <to-state> [branch]
# Updates a plan's state in REGISTRY.md and sets the date to today.
# If branch is provided, updates the Branch column too.
# If branch is "-", clears the Branch column to "—".
#
# Examples:
#   wf-registry-update.sh PLN-004 ready active feature/PLN-004-slug
#   wf-registry-update.sh PLN-004 active verify
#   wf-registry-update.sh PLN-004 testing complete -
#
# Exit 0 on success, 1 on error.

set -euo pipefail

REGISTRY="plans/REGISTRY.md"
plan_id="${1:-}"
from_state="${2:-}"
to_state="${3:-}"
branch="${4:-}"

if [ -z "$plan_id" ] || [ -z "$from_state" ] || [ -z "$to_state" ]; then
  echo "Usage: $0 <plan-id> <from-state> <to-state> [branch]" >&2
  exit 1
fi

[ -f "$REGISTRY" ] || { echo "Error: $REGISTRY not found" >&2; exit 1; }

today=$(date +%Y-%m-%d)

# Verify the plan exists in the expected state
if ! grep -q "| $plan_id |.*| $from_state |" "$REGISTRY"; then
  echo "Error: $plan_id not found in state '$from_state'" >&2
  exit 1
fi

if [ -n "$branch" ]; then
  if [ "$branch" = "-" ]; then
    # Clear branch to em-dash — use # delimiter to avoid / in plan_id
    sed -i '' "/$plan_id/s#| $from_state |[^|]*|[^|]*|#| $to_state | — | $today |#" "$REGISTRY"
  else
    # Use # delimiter — branch contains / (e.g. feature/PLN-001-slug)
    sed -i '' "/$plan_id/s#| $from_state |[^|]*|[^|]*|#| $to_state | $branch | $today |#" "$REGISTRY"
  fi
else
  # Update state and date only, preserve branch column — use # delimiter
  sed -i '' "/$plan_id/s#| $from_state |\([^|]*\)|[^|]*|#| $to_state |\1| $today |#" "$REGISTRY"
fi

# Verify the update worked
if grep -q "| $plan_id |.*| $to_state |" "$REGISTRY"; then
  echo "$plan_id: $from_state → $to_state"
else
  echo "Error: update failed for $plan_id" >&2
  exit 1
fi

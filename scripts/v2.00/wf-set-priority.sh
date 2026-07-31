#!/usr/bin/env bash
# wf-set-priority.sh <plan-id> [priority]
# Sets the Priority column for a plan in REGISTRY.md.
# priority: "urgent" (default) or "—" to clear (normal)
#
# Examples:
#   wf-set-priority.sh PLN-004 urgent
#   wf-set-priority.sh PLN-004 —
#   wf-set-priority.sh PLN-004-some-slug urgent

set -euo pipefail

REGISTRY="plans/REGISTRY.md"

raw_id="${1:-}"
priority="${2:-urgent}"

# Normalize: accept both "PLN-NNN" and "PLN-NNN-slug" formats
plan_id=$(echo "$raw_id" | grep -oE '^PLN-[0-9]+' || echo "$raw_id")

if [ -z "$plan_id" ]; then
  echo "Usage: $0 <plan-id> [priority]" >&2
  exit 1
fi

[ -f "$REGISTRY" ] || { echo "Error: $REGISTRY not found" >&2; exit 1; }

if ! grep -q "^| $plan_id |" "$REGISTRY"; then
  echo "Error: $plan_id not found in registry" >&2
  exit 1
fi

# Replace the priority column (4th column: | id | slug | state | <priority> | branch | date |)
sed -i '' "/^| $plan_id |/s#\(| $plan_id |[^|]*|[^|]*|\)[^|]*|#\1 $priority |#" "$REGISTRY"

if grep -q "^| $plan_id |.*| $priority |" "$REGISTRY"; then
  echo "$plan_id: priority → $priority"
else
  echo "Error: update failed for $plan_id" >&2
  exit 1
fi

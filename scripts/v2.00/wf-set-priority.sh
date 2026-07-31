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

# shellcheck source=wf-lock.sh
source "$(dirname "$0")/wf-lock.sh"

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

wf_lock_acquire registry

if ! grep -q "^| $plan_id |" "$REGISTRY"; then
  echo "Error: $plan_id not found in registry" >&2
  exit 1
fi

# Replace the Priority column ($5). Exact ID match on $2 — a `~` regex match
# would also hit PLN-041 when asked for PLN-04.
awk -F'|' -v OFS='|' -v id="$plan_id" -v pri="$priority" '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  trim($2) == id { $5 = " " pri " " }
  { print }
' "$REGISTRY" > "$REGISTRY.tmp" && mv "$REGISTRY.tmp" "$REGISTRY"

if grep -q "^| $plan_id |.*| $priority |" "$REGISTRY"; then
  echo "$plan_id: priority → $priority"
else
  echo "Error: update failed for $plan_id" >&2
  exit 1
fi

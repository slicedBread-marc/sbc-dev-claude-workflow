#!/usr/bin/env bash
# wf-set-tags.sh <plan-id> <tags>
# Sets the Tags column (9th) for a plan in REGISTRY.md.
# Tags are comma-separated, no spaces. Use "—" to clear.
#
# Allowed tags: security, arcade, admin, lessons, ux, infra, e2e, bugfix
#
# Examples:
#   wf-set-tags.sh PLN-004 security
#   wf-set-tags.sh PLN-004 security,admin
#   wf-set-tags.sh PLN-004 —

set -euo pipefail

REGISTRY="plans/REGISTRY.md"
ALLOWED_TAGS="security arcade admin lessons ux infra e2e bugfix"

raw_id="${1:-}"
tags="${2:-}"

plan_id=$(echo "$raw_id" | grep -oE '^PLN-[0-9]+' || echo "$raw_id")

if [ -z "$plan_id" ] || [ -z "$tags" ]; then
  echo "Usage: $0 <plan-id> <tags>" >&2
  exit 1
fi

[ -f "$REGISTRY" ] || { echo "Error: $REGISTRY not found" >&2; exit 1; }

# Normalize: strip all whitespace so the registry never holds "a, b" (comma-space).
if [ "$tags" != "—" ]; then
  tags=$(printf '%s' "$tags" | tr -d '[:space:]')
fi

if ! grep -q "^| $plan_id |" "$REGISTRY"; then
  echo "Error: $plan_id not found in registry" >&2
  exit 1
fi

# Validate tags (skip validation for clear)
if [ "$tags" != "—" ]; then
  IFS=',' read -ra tag_list <<< "$tags"
  for tag in "${tag_list[@]}"; do
    tag=$(echo "$tag" | xargs)
    if ! echo "$ALLOWED_TAGS" | grep -qw "$tag"; then
      echo "Error: unknown tag '$tag'. Allowed: $ALLOWED_TAGS" >&2
      exit 1
    fi
  done
fi

# The row has 9 pipes (10 fields including leading empty).
# We need to replace field 9 (Tags). If the row only has 8 fields (v4 format),
# we need to append the Tags and Deps columns.
row=$(grep "^| $plan_id |" "$REGISTRY" | head -1)
pipe_count=$(echo "$row" | tr -cd '|' | wc -c | xargs)

if [ "$pipe_count" -lt 10 ]; then
  # v4 row — append Tags and Deps columns
  # Current: | ... | WF |  →  | ... | WF | Tags | Deps |
  sed -i '' "/| $plan_id |/s#|[[:space:]]*\$# | $tags | — |#" "$REGISTRY"
else
  # v5 row — update Tags column in place
  # Replace field 9 using awk
  awk -F'|' -v id="$plan_id" -v newtags=" $tags " '
    $2 ~ id { $9 = newtags }
    { print }
  ' OFS='|' "$REGISTRY" > "$REGISTRY.tmp" && mv "$REGISTRY.tmp" "$REGISTRY"
fi

echo "$plan_id: tags → $tags"

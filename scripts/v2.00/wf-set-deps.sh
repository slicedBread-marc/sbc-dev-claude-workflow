#!/usr/bin/env bash
# wf-set-deps.sh <plan-id> <deps>
# Sets the Deps column (10th) for a plan in REGISTRY.md.
# Deps are comma-separated plan IDs. Use "—" to clear.
#
# Examples:
#   wf-set-deps.sh PLN-004 PLN-001
#   wf-set-deps.sh PLN-004 PLN-001,PLN-003
#   wf-set-deps.sh PLN-004 —

set -euo pipefail

REGISTRY="plans/REGISTRY.md"

raw_id="${1:-}"
deps="${2:-}"

plan_id=$(echo "$raw_id" | grep -oE '^PLN-[0-9]+' || echo "$raw_id")

if [ -z "$plan_id" ] || [ -z "$deps" ]; then
  echo "Usage: $0 <plan-id> <deps>" >&2
  exit 1
fi

[ -f "$REGISTRY" ] || { echo "Error: $REGISTRY not found" >&2; exit 1; }

if ! grep -q "| $plan_id |" "$REGISTRY"; then
  echo "Error: $plan_id not found in registry" >&2
  exit 1
fi

# Validate deps exist in registry (skip for clear)
if [ "$deps" != "—" ]; then
  IFS=',' read -ra dep_list <<< "$deps"
  for dep in "${dep_list[@]}"; do
    dep=$(echo "$dep" | xargs)
    if ! grep -q "| $dep |" "$REGISTRY"; then
      echo "Error: dependency '$dep' not found in registry" >&2
      exit 1
    fi
  done
fi

# Check if row has v5 columns (10+ pipes) or v4 (8 pipes)
row=$(grep "| $plan_id |" "$REGISTRY" | head -1)
pipe_count=$(echo "$row" | tr -cd '|' | wc -c | xargs)

if [ "$pipe_count" -lt 10 ]; then
  # v4 row — append Tags and Deps columns
  sed -i '' "/| $plan_id |/s#|[[:space:]]*\$# | — | $deps |#" "$REGISTRY"
else
  # v5 row — update Deps column in place
  awk -F'|' -v id="$plan_id" -v newdeps=" $deps " '
    $2 ~ id { $10 = newdeps }
    { print }
  ' OFS='|' "$REGISTRY" > "$REGISTRY.tmp" && mv "$REGISTRY.tmp" "$REGISTRY"
fi

echo "$plan_id: deps → $deps"

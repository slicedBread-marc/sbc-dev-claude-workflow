#!/usr/bin/env bash
# wf-counter-next.sh [prefix]
# Reads the counter from REGISTRY.md, prints the next ID, and increments.
# Optional prefix (PLN, BUG, BRF) — if given, prints prefixed ID (e.g., PLN-021).
# Without prefix, prints just the number.
#
# Examples:
#   wf-counter-next.sh PLN   → prints "PLN-021", counter becomes 22
#   wf-counter-next.sh BUG   → prints "BUG-021"
#   wf-counter-next.sh       → prints "21"
#
# Exit 0 on success, 1 on error.

set -euo pipefail

REGISTRY="plans/REGISTRY.md"
prefix="${1:-}"

[ -f "$REGISTRY" ] || { echo "Error: $REGISTRY not found" >&2; exit 1; }

# Extract current counter
current=$(grep -oE 'Counter: [0-9]+' "$REGISTRY" | grep -oE '[0-9]+')
if [ -z "$current" ]; then
  echo "Error: no counter found in $REGISTRY" >&2
  exit 1
fi

next=$((current + 1))

# Update counter in place
sed -i '' "s/<!-- Counter: $current -->/<!-- Counter: $next -->/" "$REGISTRY"

# Output the ID
if [ -n "$prefix" ]; then
  printf "%s-%03d\n" "$prefix" "$current"
else
  echo "$current"
fi

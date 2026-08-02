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

# shellcheck source=wf-lock.sh
source "$(dirname "$0")/wf-lock.sh"

REGISTRY="plans/REGISTRY.md"
prefix="${1:-}"

[ -f "$REGISTRY" ] || { echo "Error: $REGISTRY not found" >&2; exit 1; }

# Read-then-write: without the lock two concurrent callers hand out the same ID.
wf_lock_acquire registry

# Extract current counter
current=$(grep -oE 'Counter: [0-9]+' "$REGISTRY" | grep -oE '[0-9]+')
if [ -z "$current" ]; then
  echo "Error: no counter found in $REGISTRY" >&2
  exit 1
fi

# 10# forces base 10 in case the counter was hand-edited with a leading zero.
next=$((10#$current + 1))

# Update counter (awk into a tempfile — `sed -i ''` is macOS-only)
awk -v cur="$current" -v nxt="$next" '
  { sub("<!-- Counter: " cur " -->", "<!-- Counter: " nxt " -->"); print }
' "$REGISTRY" > "$REGISTRY.tmp" && mv "$REGISTRY.tmp" "$REGISTRY"

# Output the ID
if [ -n "$prefix" ]; then
  printf "%s-%03d\n" "$prefix" "$current"
else
  echo "$current"
fi

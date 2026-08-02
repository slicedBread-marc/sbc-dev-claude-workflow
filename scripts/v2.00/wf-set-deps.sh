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

# shellcheck source=wf-lock.sh
source "$(dirname "$0")/wf-lock.sh"

# Registry work is develop-root work. Sourced/derived paths below are relative
# ("plans/REGISTRY.md", "plans/PLN-NNN-slug/..."), and verify and implement
# workers run with their CWD inside a feature worktree — where those resolve to
# that worktree's own stale copy. The write then "succeeds", the verification
# grep passes against the copy it just wrote, and the real registry never moves.
# The main worktree is always the first one git lists.
_wf_root=$(git worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //') || true
[ -n "$_wf_root" ] || _wf_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
cd "$_wf_root"

REGISTRY="plans/REGISTRY.md"

raw_id="${1:-}"
deps="${2:-}"

plan_id=$(echo "$raw_id" | grep -oE '^PLN-[0-9]+' || echo "$raw_id")

if [ -z "$plan_id" ] || [ -z "$deps" ]; then
  echo "Usage: $0 <plan-id> <deps>" >&2
  exit 1
fi

[ -f "$REGISTRY" ] || { echo "Error: $REGISTRY not found" >&2; exit 1; }

if ! grep -q "^| $plan_id |" "$REGISTRY"; then
  echo "Error: $plan_id not found in registry" >&2
  exit 1
fi

# Validate deps exist in registry (skip for clear)
if [ "$deps" != "—" ]; then
  IFS=',' read -ra dep_list <<< "$deps"
  for dep in "${dep_list[@]}"; do
    dep=$(echo "$dep" | xargs)
    if ! grep -q "^| $dep |" "$REGISTRY"; then
      echo "Error: dependency '$dep' not found in registry" >&2
      exit 1
    fi
  done
fi

# Read-modify-write from here down.
wf_lock_acquire registry

# Check if row has v5 columns (10+ pipes) or v4 (8 pipes)
row=$(grep "^| $plan_id |" "$REGISTRY" | head -1)
pipe_count=$(echo "$row" | tr -cd '|' | wc -c | xargs)

if [ "$pipe_count" -lt 10 ]; then
  # v4 row — append Tags and Deps columns
  awk -F'|' -v id="$plan_id" -v deps="$deps" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    trim($2) == id { sub(/[ \t]*$/, "", $0); print $0 " — | " deps " |"; next }
    { print }
  ' "$REGISTRY" > "$REGISTRY.tmp" && mv "$REGISTRY.tmp" "$REGISTRY"
else
  # v5 row — update the Deps column ($10) in place.
  # Exact ID match: `$2 ~ id` also matches PLN-041 when asked for PLN-04.
  awk -F'|' -v OFS='|' -v id="$plan_id" -v newdeps=" $deps " '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    trim($2) == id { $10 = newdeps }
    { print }
  ' "$REGISTRY" > "$REGISTRY.tmp" && mv "$REGISTRY.tmp" "$REGISTRY"
fi

echo "$plan_id: deps → $deps"

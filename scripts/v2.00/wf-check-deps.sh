#!/usr/bin/env bash
# wf-check-deps.sh <plan-id>
# Checks whether all dependencies for a plan are complete.
#
# Reads the Deps column ($10) from REGISTRY.md for the given plan.
# Output:
#   CLEAR                           — no deps or all deps complete
#   BLOCKED <dep1>,<dep2>           — one or more deps not complete
#
# Exit 0 always (caller checks stdout).

set -euo pipefail

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
plan_id=$(echo "$raw_id" | grep -oE '^PLN-[0-9]+' || echo "$raw_id")

if [ -z "$plan_id" ]; then
  echo "Usage: $0 <plan-id>" >&2
  exit 1
fi

[ -f "$REGISTRY" ] || { echo "CLEAR"; exit 0; }

row=$(grep "^| $plan_id |" "$REGISTRY" | head -1 || true)
[ -n "$row" ] || { echo "CLEAR"; exit 0; }

deps=$(echo "$row" | awk -F'|' '{print $10}' | xargs)
[ -n "$deps" ] && [ "$deps" != "—" ] || { echo "CLEAR"; exit 0; }

blocking=""
IFS=',' read -ra dep_list <<< "$deps"
for dep_id in "${dep_list[@]}"; do
  dep_id=$(echo "$dep_id" | xargs)
  dep_state=$(grep "^| $dep_id |" "$REGISTRY" 2>/dev/null | awk -F'|' '{print $4}' | xargs || true)
  if [ "$dep_state" != "complete" ]; then
    [ -n "$blocking" ] && blocking="$blocking,$dep_id" || blocking="$dep_id"
  fi
done

if [ -n "$blocking" ]; then
  echo "BLOCKED $blocking"
else
  echo "CLEAR"
fi

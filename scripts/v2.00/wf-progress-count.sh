#!/usr/bin/env bash
# wf-progress-count.sh <plan-id-or-name>
#
# Prints "<checked>/<total>" for the `## Steps` checklist in the plan's
# progress.md — the plan's forward-progress signal.
#
# The orchestrator uses this to tell a RESUME from a RETRY. A worker that
# picks a long plan back up and advances it has made progress even though the
# REGISTRY state never moved; a worker thrashing active⇄verify has not. Only
# the second kind should burn the attempt budget.
#
# Always anchored to the develop root — progress.md does not exist on feature
# branches, so this is safe to call from inside a worktree.
#
# Output: "3/11" on stdout. A missing plan or progress.md prints "0/0".
# Exit 0 always (except on usage error) — callers treat this as a reading,
# not a check.

set -euo pipefail

# shellcheck source=wf-orch-lib.sh
source "$(dirname "$0")/wf-orch-lib.sh"

raw_id="${1:-}"
plan_id=$(printf '%s' "$raw_id" | grep -oE 'PLN-[0-9]+' || true)
if [ -z "$plan_id" ]; then
  echo "Usage: $0 <plan-id-or-name>" >&2
  exit 1
fi

ROOT="$(wf_develop_root)"
REGISTRY="$ROOT/plans/REGISTRY.md"

progress=""
if [ -f "$REGISTRY" ]; then
  row=$(grep "^| $plan_id |" "$REGISTRY" | head -1 || true)
  if [ -n "$row" ]; then
    slug=$(printf '%s' "$row" | awk -F'|' '{print $3}' | xargs)
    progress="$ROOT/plans/${plan_id}-${slug}/progress.md"
  fi
fi

if [ -z "$progress" ] || [ ! -f "$progress" ]; then
  echo "0/0"
  exit 0
fi

# Count only inside `## Steps` — the Log section also contains bracketed text.
awk '
  /^## Steps/       { in_steps = 1; next }
  /^## /            { in_steps = 0 }
  !in_steps         { next }
  /^[[:space:]]*-[[:space:]]*\[[xX]\]/ { checked++; total++; next }
  /^[[:space:]]*-[[:space:]]*\[[[:space:]]*\]/ { total++ }
  END { printf "%d/%d\n", checked, total }
' "$progress"

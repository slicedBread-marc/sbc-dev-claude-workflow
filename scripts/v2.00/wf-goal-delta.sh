#!/usr/bin/env bash
# wf-goal-delta.sh <plan-id> [--base <ref>]
#
# Puts a plan's ORIGINAL goal, its CURRENT goal, and the amendments added since
# the last commit side by side, so a replan cannot quietly narrow what the plan
# promised.
#
# Output:
#
#   GOAL_ORIGINAL: <the one-liner as first committed>
#   GOAL_CURRENT:  <the one-liner in the working tree>
#   GOAL_STATUS:   unchanged | changed | unknown
#   AMENDMENTS_NEW: 2
#   --- new amendment text, verbatim ---
#   ...
#
# WHY THIS EXISTS
#
# Whether a capability the user asked for may be dropped is a product decision.
# No review verdict answers it — a reviewer judges whether the plan is sound,
# and a narrowing is very often sound engineering. Observed: an amendment
# narrowed an unattended relay to ANSWER-ONLY for an entirely correct reason (a
# looped write-capable skill over untrusted input was the injection the plan
# existed to prevent). Its own text said "that is a deliberate reduction of the
# Goal's headline capability". A reviewer would approve it, verdict mode would
# transition it to `ready`, it would be built, and the user would learn that
# "fix this while I'm out" no longer works the next time they tried it.
#
# GOAL_STATUS is the mechanical half — the goal line itself was edited. The
# other half is a judgement only a reader can make: does a new amendment remove
# or qualify a capability the Goal names, while leaving the Goal line intact?
# That is the case that actually occurred, which is why the amendment text is
# printed rather than just a verdict. See wf-spec's Replanning section.
#
# --base defaults to the commit that first added plan.md — the goal as
# originally written, which is the thing a narrowing is measured against. Pass
# `--base HEAD` to compare against the last commit only.
#
# Exit 0 always. Callers branch on GOAL_STATUS, matching wf-check-deps.sh.

set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

# Registry work is develop-root work — see wf-registry-update.sh.
_wf_root=$(git worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //') || true
[ -n "$_wf_root" ] || _wf_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
cd "$_wf_root"

REGISTRY="plans/REGISTRY.md"

raw_id="${1:-}"; shift || true
base=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="${2:?--base requires a ref}"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

plan_id=$(printf '%s' "$raw_id" | grep -oE '^PLN-[0-9]+' || true)
[ -n "$plan_id" ] || { echo "Usage: $0 <PLN-NNN> [--base <ref>]" >&2; exit 1; }
[ -f "$REGISTRY" ] || { echo "Error: $REGISTRY not found" >&2; exit 1; }

slug=$(grep "^| $plan_id |" "$REGISTRY" 2>/dev/null | head -1 | awk -F'|' '{print $3}' | xargs || true)
[ -n "$slug" ] || { echo "Error: $plan_id has no registry row" >&2; exit 1; }

plan_file="plans/$plan_id-$slug/plan.md"
[ -f "$plan_file" ] || { echo "Error: $plan_file not found" >&2; exit 1; }

# First non-empty, non-quote line under `## Goal`. Blockquote lines are the
# metadata header (> **ID:**, > **Bug:**), not the goal.
goal_of() {
  awk '
    /^## Goal[ \t]*$/ { in_goal = 1; next }
    in_goal && /^## / { exit }
    in_goal {
      line = $0
      sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line)
      if (line == "" || line ~ /^>/) next
      print line; exit
    }
  '
}

current=$(goal_of < "$plan_file")

if [ -z "$base" ]; then
  base=$(git log --diff-filter=A --format=%H -- "$plan_file" 2>/dev/null | tail -1 || true)
fi

original=""
status="unknown"
if [ -n "$base" ]; then
  if original=$(git show "$base:$plan_file" 2>/dev/null | goal_of); then
    if [ "$original" = "$current" ]; then status="unchanged"; else status="changed"; fi
  else
    original=""
  fi
fi

printf 'GOAL_ORIGINAL: %s\n' "$original"
printf 'GOAL_CURRENT:  %s\n' "$current"
printf 'GOAL_STATUS:   %s\n' "$status"

# ── Amendments added but not yet committed ────────────────────────────────
# The narrowing case leaves the Goal line untouched and lands the reduction in
# `## Amendments`, so the text has to reach the caller for the judgement half.
new_amendments=$(git diff HEAD -- "$plan_file" 2>/dev/null \
                 | sed -n 's/^+\([^+].*\)$/\1/p' || true)

if [ -z "$new_amendments" ]; then
  printf 'AMENDMENTS_NEW: 0\n'
  exit 0
fi

count=$(printf '%s\n' "$new_amendments" | grep -cE '^#+ *A[0-9]|^\*\*A[0-9]|^> *\*\*A[0-9]' || true)
printf 'AMENDMENTS_NEW: %s\n' "$count"
printf -- '--- added to %s since HEAD ---\n' "$plan_file"
printf '%s\n' "$new_amendments"

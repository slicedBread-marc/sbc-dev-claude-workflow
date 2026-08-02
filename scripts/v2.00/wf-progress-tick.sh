#!/usr/bin/env bash
# wf-progress-tick.sh <plan-id-or-name> <step-number> [description] [--blocked]
#
# Ticks `Step N` in the plan's progress.md `## Steps` checklist and appends the
# matching `## Log` line. One call per completed step, from wf-implement.
#
#   wf-progress-tick.sh PLN-041 3 "wire the export command"
#   wf-progress-tick.sh PLN-041 4 "blocked on missing migration" --blocked
#
# Why this exists: the checklist used to sit at "1 of 11" while the branch was
# at step 9, because only the Log was ever written. Nothing recorded forward
# progress, so the orchestrator could not tell a resume from a retry and parked
# healthy long plans as `stuck`. The checklist is now the progress signal —
# wf-progress-count.sh reads it and the orchestrator resets the attempt budget
# whenever it climbs.
#
# Always anchored to the develop root, so it is safe to call from a feature
# worktree (where `plans/` does not exist).
#
# Exit 0 on success, 1 on error. A step already ticked is not an error —
# re-running is a no-op on the checklist and still logs.

set -euo pipefail

# shellcheck source=wf-orch-lib.sh
source "$(dirname "$0")/wf-orch-lib.sh"
# shellcheck source=wf-lock.sh
source "$(dirname "$0")/wf-lock.sh"

raw_id="${1:-}"
step="${2:-}"
shift 2 2>/dev/null || true

desc=""
status="done"
while [ $# -gt 0 ]; do
  case "$1" in
    --blocked) status="blocked"; shift ;;
    *) desc="$1"; shift ;;
  esac
done

plan_id=$(printf '%s' "$raw_id" | grep -oE 'PLN-[0-9]+' || true)
if [ -z "$plan_id" ] || ! printf '%s' "$step" | grep -qE '^[0-9]+$'; then
  echo "Usage: $0 <plan-id-or-name> <step-number> [description] [--blocked]" >&2
  exit 1
fi

ROOT="$(wf_develop_root)"
REGISTRY="$ROOT/plans/REGISTRY.md"
[ -f "$REGISTRY" ] || { echo "Error: $REGISTRY not found" >&2; exit 1; }

row=$(grep "^| $plan_id |" "$REGISTRY" | head -1 || true)
[ -n "$row" ] || { echo "Error: $plan_id not found in registry" >&2; exit 1; }
slug=$(printf '%s' "$row" | awk -F'|' '{print $3}' | xargs)
progress="$ROOT/plans/${plan_id}-${slug}/progress.md"
[ -f "$progress" ] || { echo "Error: $progress not found" >&2; exit 1; }

wf_lock_acquire "plan-$plan_id"

today=$(date +%Y-%m-%d)

# ── Tick the checklist row ────────────────────────────────────────────────
# Matches "- [ ] Step N:" and "- [ ] Step N " inside `## Steps` only, so a Log
# line mentioning the same step number is never rewritten.
if [ "$status" = "done" ]; then
  awk -v want="$step" '
    /^## Steps/ { in_steps = 1; print; next }
    /^## /      { in_steps = 0 }
    in_steps && /^[[:space:]]*-[[:space:]]*\[[[:space:]]*\][[:space:]]*[Ss]tep[[:space:]]+[0-9]+/ {
      line = $0
      n = line
      sub(/^[^0-9]*/, "", n)
      sub(/[^0-9].*$/, "", n)
      if (n + 0 == want + 0) {
        sub(/\[[[:space:]]*\]/, "[x]", line)
        print line
        next
      }
    }
    { print }
  ' "$progress" > "$progress.tmp" && mv "$progress.tmp" "$progress"
fi

# ── Append the log line ───────────────────────────────────────────────────
entry="[$today] Step $step — $status"
[ -n "$desc" ] && entry="$entry ($desc)"

if grep -q "^## Log" "$progress"; then
  printf '%s\n' "$entry" >> "$progress"
else
  printf '\n## Log\n%s\n' "$entry" >> "$progress"
fi

count=$("$(dirname "$0")/wf-progress-count.sh" "$plan_id")
echo "Progress: $plan_id step $step $status — checklist now $count"

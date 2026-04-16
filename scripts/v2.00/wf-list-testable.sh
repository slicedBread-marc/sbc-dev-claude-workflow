#!/usr/bin/env bash
# wf-list-testable.sh
# Outputs plans eligible for human testing by reading REGISTRY.md.
# Eligible = state: testing
#
# Format per line (stdout): <plan-name>\t<worktree>\t<branch>\t<goal>\t<priority>
# Blocked plans output with extra field: <plan-name>\t<worktree>\t<branch>\t<goal>\t<priority>\tblocked:<deps>
# Stderr summary: TESTABLE: N, TOTAL: N
#
# Exit 0 if any testable found, exit 1 if none.

set -euo pipefail

REGISTRY="plans/REGISTRY.md"
testable=0
total=0
claimed_plans=()

while IFS='|' read -r _ id slug state priority branch _rest; do
  id=$(echo "$id" | xargs)
  slug=$(echo "$slug" | xargs)
  state=$(echo "$state" | xargs)
  priority=$(echo "$priority" | xargs)
  branch=$(echo "$branch" | xargs)

  [ "$state" = "testing" ] || continue
  total=$((total + 1))

  plan_dir="plans/${id}-${slug}"
  [ -d "$plan_dir" ] || continue

  # Check for active claim (PID alive, or TTL fallback for old format)
  claimfile="$plan_dir/.wf-claim"
  if [ -f "$claimfile" ]; then
    claim_ts=$(sed -n '1p' "$claimfile" 2>/dev/null)
    claim_pid=$(sed -n '2p' "$claimfile" 2>/dev/null)
    now=$(date +%s)
    age=$(( now - claim_ts ))
    _live=0
    if [ -n "$claim_pid" ]; then
      kill -0 "$claim_pid" 2>/dev/null && [ "$age" -lt 7200 ] && _live=1
    else
      [ "$age" -lt 7200 ] && _live=1
    fi
    if [ "$_live" -eq 1 ]; then
      claimed_plans+=("${id}-${slug}:${age}")
      continue
    fi
  fi

  plan_name="${id}-${slug}"
  goal=$(grep -A 1 "^## Goal" "$plan_dir/plan.md" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)

  worktree="feature-branches/${plan_name}"
  [ -d "$worktree" ] || worktree=""

  # Check deps (field 10)
  row_full=$(grep "| $id |" "$REGISTRY" | head -1)
  deps_raw=$(echo "$row_full" | awk -F'|' '{print $10}' | xargs)
  blocking=""
  if [ -n "$deps_raw" ] && [ "$deps_raw" != "—" ]; then
    IFS=',' read -ra dep_list <<< "$deps_raw"
    for dep_id in "${dep_list[@]}"; do
      dep_id=$(echo "$dep_id" | xargs)
      dep_state=$(grep "| $dep_id |" "$REGISTRY" 2>/dev/null | awk -F'|' '{print $4}' | xargs || true)
      if [ "$dep_state" != "complete" ]; then
        [ -n "$blocking" ] && blocking="$blocking,$dep_id" || blocking="$dep_id"
      fi
    done
  fi

  if [ -n "$blocking" ]; then
    printf "%s\t%s\t%s\t%s\t%s\tblocked:%s\n" "$plan_name" "$worktree" "$branch" "$goal" "$priority" "$blocking"
  else
    printf "%s\t%s\t%s\t%s\t%s\n" "$plan_name" "$worktree" "$branch" "$goal" "$priority"
  fi
  testable=$((testable + 1))
done < <(grep "^|" "$REGISTRY" | tail -n +3)

cat >&2 <<EOF
TESTABLE: $testable
TOTAL: $total
EOF

if [ "$testable" -eq 0 ] && [ "${#claimed_plans[@]}" -gt 0 ]; then
  echo "CLAIMED:" >&2
  for entry in "${claimed_plans[@]}"; do
    plan="${entry%%:*}"
    age="${entry##*:}"
    mins=$(( age / 60 ))
    echo "  $plan (claimed ${mins}m ago)" >&2
  done
  echo "Run: scripts/wf-unclaim.sh <plan-name> to release stale claims" >&2
fi

exit $((testable > 0 ? 0 : 1))

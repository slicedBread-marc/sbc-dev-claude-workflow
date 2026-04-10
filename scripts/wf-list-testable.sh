#!/usr/bin/env bash
# wf-list-testable.sh
# Outputs plans eligible for human testing by reading REGISTRY.md.
# Eligible = state: testing
#
# Format per line (stdout): <plan-name>\t<worktree>\t<branch>\t<goal>\t<priority>
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

  # Check for active claim (< 2 hours old)
  claimfile="$plan_dir/.wf-claim"
  if [ -f "$claimfile" ]; then
    claim_ts=$(cat "$claimfile" 2>/dev/null)
    now=$(date +%s)
    age=$(( now - claim_ts ))
    if [ "$age" -lt 7200 ]; then
      claimed_plans+=("${id}-${slug}:${age}")
      continue
    fi
  fi

  plan_name="${id}-${slug}"
  goal=$(grep -A 1 "^## Goal" "$plan_dir/plan.md" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)

  worktree="feature-branches/${plan_name}"
  [ -d "$worktree" ] || worktree=""

  printf "%s\t%s\t%s\t%s\t%s\n" "$plan_name" "$worktree" "$branch" "$goal" "$priority"
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

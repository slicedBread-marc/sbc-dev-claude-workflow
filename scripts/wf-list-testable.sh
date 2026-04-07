#!/usr/bin/env bash
# wf-list-testable.sh
# Outputs plans eligible for human testing by reading REGISTRY.md.
# Eligible = state: testing
#
# Format per line (stdout): <plan-name>\t<worktree>\t<branch>\t<goal>
# Stderr summary: TESTABLE: N, TOTAL: N
#
# Exit 0 if any testable found, exit 1 if none.

set -euo pipefail

REGISTRY="plans/REGISTRY.md"
testable=0
total=0

while IFS='|' read -r _ id slug state branch _rest; do
  id=$(echo "$id" | xargs)
  slug=$(echo "$slug" | xargs)
  state=$(echo "$state" | xargs)
  branch=$(echo "$branch" | xargs)

  [ "$state" = "testing" ] || continue
  total=$((total + 1))

  plan_dir="plans/${id}-${slug}"
  [ -d "$plan_dir" ] || continue

  plan_name="${id}-${slug}"
  goal=$(grep -A 1 "^## Goal" "$plan_dir/plan.md" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)

  worktree="feature-branches/${plan_name}"
  [ -d "$worktree" ] || worktree=""

  printf "%s\t%s\t%s\t%s\n" "$plan_name" "$worktree" "$branch" "$goal"
  testable=$((testable + 1))
done < <(grep "^|" "$REGISTRY" | tail -n +3)

cat >&2 <<EOF
TESTABLE: $testable
TOTAL: $total
EOF

exit $((testable > 0 ? 0 : 1))

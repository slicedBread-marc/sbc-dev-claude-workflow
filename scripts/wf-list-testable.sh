#!/usr/bin/env bash
# wf-list-testable.sh
# Outputs eligible plans for human testing by scanning develop's plans/ only.
# Eligible = Status: Verified (clean, no "-with-findings" suffix) AND zero Open/Escalated findings.
#
# Format per line (stdout): <plan-name>\t<worktree>\t<branch>\t<goal>
# Stderr summary block (always printed):
#   TESTABLE: N
#   BLOCKED: N (open/escalated findings)
#   NOT_VERIFIED: N (wrong status)
#   TOTAL_VERIFY: N
#
# Exit 0 if any testable found, exit 1 if none.

set -euo pipefail

testable=0
blocked=0
not_verified=0
total=0

for plan in plans/verify/*/plan.md; do
  [ -f "$plan" ] || continue
  total=$((total + 1))
  plan_name=$(basename "$(dirname "$plan")")

  # Must have Status: Verified (not Verified-with-findings)
  # Status line may be plain or markdown-formatted ("> **Status:** Verified")
  if ! grep -qiE "(^|\*\*)?Status:\*?\*?\s*Verified" "$plan" 2>/dev/null; then
    not_verified=$((not_verified + 1))
    continue
  fi
  if grep -qi "with-findings" "$plan" 2>/dev/null; then
    not_verified=$((not_verified + 1))
    continue
  fi

  # Skip plans with unresolved findings (Open or Escalated)
  findings="plans/verify/$plan_name/findings.md"
  if [ -f "$findings" ] && grep -qE '\| Open \|| \| Escalated \|' "$findings" 2>/dev/null; then
    blocked=$((blocked + 1))
    continue
  fi

  goal=$(grep -A 1 "^## Goal" "$plan" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)

  # Find matching worktree and branch
  pln_prefix=$(echo "$plan_name" | grep -o '^PLN-[0-9]*' || echo "$plan_name")
  worktree=$(ls -d feature-branches/${pln_prefix}-* 2>/dev/null | head -1 || true)
  branch=""
  if [ -n "$worktree" ] && [ -d "$worktree" ]; then
    branch=$(git -C "$worktree" branch --show-current 2>/dev/null || true)
  fi

  printf "%s\t%s\t%s\t%s\n" "$plan_name" "$worktree" "$branch" "$goal"
  testable=$((testable + 1))
done

cat >&2 <<EOF
TESTABLE: $testable
BLOCKED: $blocked
NOT_VERIFIED: $not_verified
TOTAL_VERIFY: $total
EOF

exit $((testable > 0 ? 0 : 1))

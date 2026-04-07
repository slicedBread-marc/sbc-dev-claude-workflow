#!/usr/bin/env bash
# wf-list-implementable.sh
# Outputs plans available for implementation by scanning develop's plans/ only.
# Feature branch worktrees are NOT traversed — develop is the source of truth.
#
# Format per line: <type>\t<plan-name>\t<goal>
#   type = "new"       — plan in plans/ready/, no existing worktree
#   type = "amendment" — plan in plans/ready/, worktree exists (re-spec'd plan)
#   type = "resume"    — plan in plans/active/, worktree exists (mid-implementation)
#   type = "fix"       — plan in plans/verify/ with open findings needing T3 attention
#
# Exit 0 if any found, exit 1 if none.

set -euo pipefail

found=0

# Plans in plans/ready/ (new or amendment)
for plan in plans/ready/*/plan.md; do
  [ -f "$plan" ] || continue
  plan_name=$(basename "$(dirname "$plan")")
  goal=$(grep -A 1 "^## Goal" "$plan" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)

  pln_prefix=$(echo "$plan_name" | grep -o '^PLN-[0-9]*' || true)
  if [ -n "$pln_prefix" ] && ls -d "feature-branches/${pln_prefix}-"* 2>/dev/null | grep -q .; then
    printf "amendment\t%s\t%s\n" "$plan_name" "$goal"
  else
    printf "new\t%s\t%s\n" "$plan_name" "$goal"
  fi
  found=1
done

# Plans in plans/active/ (resume — mid-implementation)
for plan in plans/active/*/plan.md; do
  [ -f "$plan" ] || continue
  plan_name=$(basename "$(dirname "$plan")")
  goal=$(grep -A 1 "^## Goal" "$plan" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)
  printf "resume\t%s\t%s\n" "$plan_name" "$goal"
  found=1
done

# Plans in plans/verify/ with open findings (fix cycle for T3)
for plan in plans/verify/*/plan.md; do
  [ -f "$plan" ] || continue
  plan_name=$(basename "$(dirname "$plan")")
  goal=$(grep -A 1 "^## Goal" "$plan" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)

  # Check both status line and actual findings to determine type
  findings="plans/verify/$plan_name/findings.md"
  has_open_findings=0
  if [ -f "$findings" ] && grep -qE '\| Open \|' "$findings" 2>/dev/null; then
    has_open_findings=1
  fi

  if grep -qiE "(^|\*\*)?Status:\*?\*?\s*.*with-findings" "$plan" 2>/dev/null || [ "$has_open_findings" -eq 1 ]; then
    printf "fix\t%s\t%s\n" "$plan_name" "$goal"
    found=1
  fi
  # Clean Verified plans belong to T4 (testable list), not T3 — skip them
done

exit $((1 - found))

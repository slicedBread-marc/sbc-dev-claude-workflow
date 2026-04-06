#!/usr/bin/env bash
# wf-list-implementable.sh
# Outputs plans available for implementation by scanning develop's plans/ only.
# Feature branch worktrees are NOT traversed — develop is the source of truth.
#
# Format per line: <type>\t<plan-name>\t<goal>
#   type = "new"       — plan in plans/ready/, no existing worktree
#   type = "amendment" — plan in plans/ready/, worktree exists (re-spec'd plan)
#   type = "resume"    — plan in plans/active/, worktree exists (mid-implementation)
#   type = "fix"       — plan in plans/verify/ with Status: Verified-with-findings
#   type = "handoff"   — plan in plans/verify/ with Status: Verified (clean, Phase 3 pending)
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

# Plans in plans/verify/ (fix or handoff — check status hint)
for plan in plans/verify/*/plan.md; do
  [ -f "$plan" ] || continue
  plan_name=$(basename "$(dirname "$plan")")
  goal=$(grep -A 1 "^## Goal" "$plan" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)

  if grep -qiE "(^|\*\*)?Status:\*?\*?\s*.*with-findings" "$plan" 2>/dev/null; then
    printf "fix\t%s\t%s\n" "$plan_name" "$goal"
  else
    printf "handoff\t%s\t%s\n" "$plan_name" "$goal"
  fi
  found=1
done

exit $((1 - found))

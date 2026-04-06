#!/usr/bin/env bash
# wf-list-implementable.sh
# Outputs plans available for implementation.
# Format per line: <type>\t<plan-name>\t<goal>
#   type = "new"       — plan in plans/ready/, no existing worktree
#   type = "amendment" — plan in plans/ready/ on develop with existing worktree,
#                        OR plan in feature-branches/*/plans/ready/
#   type = "resume"    — plan in feature-branches/*/plans/active/ (mid-implementation)
#   type = "fix"       — plan in feature-branches/*/plans/verify/ with Open findings
#   type = "handoff"   — plan in feature-branches/*/plans/verify/ with no Open findings (Phase 3 pending)
# Exit 0 if any found, exit 1 if none.

set -euo pipefail

found=0

# Plans in develop's plans/ready/ (new or amendment)
for plan in plans/ready/*/plan.md; do
  [ -f "$plan" ] || continue
  plan_name=$(basename "$(dirname "$plan")")
  goal=$(grep -A 1 "^## Goal" "$plan" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//')

  pln_prefix=$(echo "$plan_name" | grep -o '^PLN-[0-9]*')
  if [ -n "$pln_prefix" ] && ls -d "feature-branches/${pln_prefix}-"* 2>/dev/null | grep -q .; then
    printf "amendment\t%s\t%s\n" "$plan_name" "$goal"
  else
    printf "new\t%s\t%s\n" "$plan_name" "$goal"
  fi
  found=1
done

# Amendment plans inside feature-branch worktrees
for plan in feature-branches/*/plans/ready/*/plan.md; do
  [ -f "$plan" ] || continue
  plan_name=$(basename "$(dirname "$plan")")
  goal=$(grep -A 1 "^## Goal" "$plan" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//')
  printf "amendment\t%s\t%s\n" "$plan_name" "$goal"
  found=1
done

# Plans mid-implementation (active/ in feature worktrees)
for plan in feature-branches/*/plans/active/*/plan.md; do
  [ -f "$plan" ] || continue
  plan_name=$(basename "$(dirname "$plan")")
  goal=$(grep -A 1 "^## Goal" "$plan" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//')
  printf "resume\t%s\t%s\n" "$plan_name" "$goal"
  found=1
done

# Plans in verify/ — split into fix (open findings) vs handoff (Phase 3 pending)
for verify_dir in feature-branches/*/plans/verify/*/; do
  [ -d "$verify_dir" ] || continue
  plan_name=$(basename "$verify_dir")
  plan_md="${verify_dir}plan.md"
  findings="${verify_dir}findings.md"
  [ -f "$plan_md" ] || continue
  goal=$(grep -A 1 "^## Goal" "$plan_md" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//')

  if [ -f "$findings" ] && grep -q "| Open |" "$findings" 2>/dev/null; then
    printf "fix\t%s\t%s\n" "$plan_name" "$goal"
  else
    printf "handoff\t%s\t%s\n" "$plan_name" "$goal"
  fi
  found=1
done

exit $((1 - found))

#!/usr/bin/env bash
# wf-list-implementable.sh
# Outputs plans available for implementation.
# Format per line: <type>\t<plan-name>\t<goal>
#   type = "new"       — plan in plans/ready/, no existing worktree
#   type = "amendment" — plan in plans/ready/ on develop with existing worktree,
#                        OR plan in feature-branches/*/plans/ready/ matching that worktree
#   type = "resume"    — plan in feature-branches/*/plans/active/ matching that worktree
#   type = "fix"       — plan in feature-branches/*/plans/verify/ with Open findings
#   type = "handoff"   — plan in feature-branches/*/plans/verify/ with no Open findings (Phase 3 pending)
#
# For feature-branch scans, only plans whose PLN-NNN prefix matches the worktree
# directory prefix are emitted — this prevents stale cross-contamination.
#
# Exit 0 if any found, exit 1 if none.

set -euo pipefail

found=0

# Plans in develop's plans/ready/ (new or amendment)
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

# Feature-branch worktrees — only match plans whose PLN prefix matches the worktree
for worktree in feature-branches/*/; do
  [ -d "$worktree" ] || continue
  wt_name=$(basename "$worktree")
  wt_prefix=$(echo "$wt_name" | grep -o '^PLN-[0-9]*' || true)
  [ -n "$wt_prefix" ] || continue  # skip non-PLN worktrees (legacy)

  # Amendment: plan in ready/ matching this worktree
  for plan in "${worktree}plans/ready/${wt_prefix}"*/plan.md; do
    [ -f "$plan" ] || continue
    plan_name=$(basename "$(dirname "$plan")")
    goal=$(grep -A 1 "^## Goal" "$plan" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)
    printf "amendment\t%s\t%s\n" "$plan_name" "$goal"
    found=1
  done

  # Resume: plan in active/ matching this worktree
  for plan in "${worktree}plans/active/${wt_prefix}"*/plan.md; do
    [ -f "$plan" ] || continue
    plan_name=$(basename "$(dirname "$plan")")
    goal=$(grep -A 1 "^## Goal" "$plan" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)
    printf "resume\t%s\t%s\n" "$plan_name" "$goal"
    found=1
  done

  # Fix or handoff: plan in verify/ matching this worktree
  for verify_dir in "${worktree}plans/verify/${wt_prefix}"*/; do
    [ -d "$verify_dir" ] || continue
    plan_name=$(basename "$verify_dir")
    plan_md="${verify_dir}plan.md"
    findings="${verify_dir}findings.md"
    [ -f "$plan_md" ] || continue
    goal=$(grep -A 1 "^## Goal" "$plan_md" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)

    if [ -f "$findings" ] && grep -q "| Open |" "$findings" 2>/dev/null; then
      printf "fix\t%s\t%s\n" "$plan_name" "$goal"
    else
      printf "handoff\t%s\t%s\n" "$plan_name" "$goal"
    fi
    found=1
  done
done

exit $((1 - found))

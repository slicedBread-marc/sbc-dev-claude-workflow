#!/usr/bin/env bash
# wf-list-implementable.sh
# Outputs plans available for implementation.
# Format per line: <type>\t<plan-name>\t<goal>
#   type = "new"       — no existing worktree, fresh implementation
#   type = "amendment" — matching worktree already exists in feature-branches/
#   type = "fix"       — plan in verify/ with Open findings needing a fix cycle
# Exit 0 if any found, exit 1 if none.

set -euo pipefail

found=0

# Plans in ready/ (new or amendment)
for plan in plans/ready/*/plan.md; do
  [ -f "$plan" ] || continue
  plan_name=$(basename "$(dirname "$plan")")
  goal=$(grep -A 1 "^## Goal" "$plan" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//')

  # Extract PLN-NNN prefix to check for existing worktree
  pln_prefix=$(echo "$plan_name" | grep -o '^PLN-[0-9]*')
  if [ -n "$pln_prefix" ] && ls -d "feature-branches/${pln_prefix}-"* 2>/dev/null | grep -q .; then
    printf "amendment\t%s\t%s\n" "$plan_name" "$goal"
  else
    printf "new\t%s\t%s\n" "$plan_name" "$goal"
  fi
  found=1
done

# Plans in verify/ that have Open findings (fix cycle)
for findings in feature-branches/*/plans/verify/*/findings.md; do
  [ -f "$findings" ] || continue
  grep -q "| Open |" "$findings" 2>/dev/null || continue
  plan_name=$(basename "$(dirname "$findings")")
  plan_md="$(dirname "$findings")/plan.md"
  goal=$(grep -A 1 "^## Goal" "$plan_md" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//')
  printf "fix\t%s\t%s\n" "$plan_name" "$goal"
  found=1
done

exit $((1 - found))

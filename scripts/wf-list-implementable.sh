#!/usr/bin/env bash
# wf-list-implementable.sh
# Outputs plans available for /wf-implement by reading REGISTRY.md.
#
# Format per line: <type>\t<plan-name>\t<goal>
#   type = "new"        — state: ready, no existing worktree
#   type = "resume"     — state: active, no unchecked findings
#   type = "fix"        — state: active, has unchecked findings
#   type = "processing" — state: active, claimed by another session (< 2h old)
#
# Exit 0 if any found, exit 1 if none.

set -euo pipefail

REGISTRY="plans/REGISTRY.md"
found=0

while IFS='|' read -r _ id slug state branch _rest; do
  id=$(echo "$id" | xargs)
  slug=$(echo "$slug" | xargs)
  state=$(echo "$state" | xargs)
  branch=$(echo "$branch" | xargs)
  plan_dir="plans/${id}-${slug}"

  [ "$state" = "ready" ] || [ "$state" = "active" ] || continue
  [ -d "$plan_dir" ] || continue

  goal=$(grep -A 1 "^## Goal" "$plan_dir/plan.md" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)
  plan_name="${id}-${slug}"

  if [ "$state" = "ready" ]; then
    printf "new\t%s\t%s\n" "$plan_name" "$goal"
    found=1
  elif [ "$state" = "active" ]; then
    claimfile="$plan_dir/.wf-claim"
    if [ -f "$claimfile" ]; then
      claim_ts=$(cat "$claimfile" 2>/dev/null)
      now=$(date +%s)
      age=$(( now - claim_ts ))
      if [ "$age" -lt 7200 ]; then
        printf "processing\t%s\t%s\n" "$plan_name" "$goal"
        found=1
        continue
      fi
    fi
    findings="$plan_dir/findings.md"
    if [ -f "$findings" ] && grep -q "^\- \[ \]" "$findings" 2>/dev/null; then
      printf "fix\t%s\t%s\n" "$plan_name" "$goal"
    else
      printf "resume\t%s\t%s\n" "$plan_name" "$goal"
    fi
    found=1
  fi
done < <(grep "^|" "$REGISTRY" | tail -n +3)

exit $((1 - found))

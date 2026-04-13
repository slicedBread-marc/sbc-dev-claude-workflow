#!/usr/bin/env bash
# wf-list-active.sh — plans in active state from REGISTRY.md
# Format: <plan-name>\t<branch>\t<step_progress>\t<goal>\t<priority>
# Exit 0 if any found, exit 1 if none.
set -euo pipefail

REGISTRY="plans/REGISTRY.md"
found=0

while IFS='|' read -r _ id slug state priority branch _rest; do
  id=$(echo "$id" | xargs); slug=$(echo "$slug" | xargs)
  state=$(echo "$state" | xargs); priority=$(echo "$priority" | xargs); branch=$(echo "$branch" | xargs)
  [ "$state" = "active" ] || continue

  plan_dir="plans/${id}-${slug}"
  plan_name="${id}-${slug}"

  # Parse progress.md for step counts
  progress="$plan_dir/progress.md"
  step_progress=""
  if [ -f "$progress" ]; then
    total=$(grep -cE '^\- \[[ x]\]' "$progress" 2>/dev/null || true)
    done_count=$(grep -cE '^\- \[x\]' "$progress" 2>/dev/null || true)
    step_progress="Step ${done_count}/${total}"
  fi

  goal=$(grep -A 1 "^## Goal" "$plan_dir/plan.md" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)

  printf "%s\t%s\t%s\t%s\t%s\n" "$plan_name" "$branch" "$step_progress" "$goal" "$priority"
  found=1
done < <(grep "^|" "$REGISTRY" | tail -n +3)

exit $((1 - found))

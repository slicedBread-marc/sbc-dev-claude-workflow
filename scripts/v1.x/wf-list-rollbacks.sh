#!/usr/bin/env bash
# wf-list-rollbacks.sh — plans in rolled-back state from REGISTRY.md
# Format: <plan-name>\t<reason>
# Exit 0 if any found, exit 1 if none.
set -euo pipefail

REGISTRY="plans/REGISTRY.md"
found=0

while IFS='|' read -r _ id slug state _rest; do
  id=$(echo "$id" | xargs); slug=$(echo "$slug" | xargs); state=$(echo "$state" | xargs)
  [ "$state" = "rolled-back" ] || continue

  plan_dir="plans/${id}-${slug}"
  reason=""
  if [ -f "$plan_dir/plan.md" ]; then
    reason=$(grep -i "Rolled back\|Reason:" "$plan_dir/plan.md" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)
  fi

  printf "%s\t%s\n" "${id}-${slug}" "$reason"
  found=1
done < <(grep "^|" "$REGISTRY" | tail -n +3)

exit $((1 - found))

#!/usr/bin/env bash
# wf-list-ready.sh — plans in ready state from REGISTRY.md
# Format: <plan-name>\t<goal>\t<priority>
# Exit 0 if any found, exit 1 if none.
set -euo pipefail

REGISTRY="plans/REGISTRY.md"
found=0

while IFS='|' read -r _ id slug state priority _rest; do
  id=$(echo "$id" | xargs); slug=$(echo "$slug" | xargs); state=$(echo "$state" | xargs)
  priority=$(echo "$priority" | xargs)
  [ "$state" = "ready" ] || continue
  plan_dir="plans/${id}-${slug}"
  goal=$(grep -A 1 "^## Goal" "$plan_dir/plan.md" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)
  printf "%s\t%s\t%s\n" "${id}-${slug}" "$goal" "$priority"
  found=1
done < <(grep "^|" "$REGISTRY" | tail -n +3)

exit $((1 - found))

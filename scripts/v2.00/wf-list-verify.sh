#!/usr/bin/env bash
# wf-list-verify.sh — plans in verify state from REGISTRY.md
# Format: <plan-name>\t<unchecked>\t<escalated>\t<goal>
# Exit 0 if any found, exit 1 if none.
set -euo pipefail

REGISTRY="plans/REGISTRY.md"
found=0

while IFS='|' read -r _ id slug state _rest; do
  id=$(echo "$id" | xargs); slug=$(echo "$slug" | xargs); state=$(echo "$state" | xargs)
  [ "$state" = "verify" ] || continue

  plan_dir="plans/${id}-${slug}"
  plan_name="${id}-${slug}"

  unchecked=0; escalated=0
  findings="$plan_dir/findings.md"
  if [ -f "$findings" ]; then
    unchecked=$(grep -c '^\- \[ \]' "$findings" 2>/dev/null || true)
    escalated=$(grep -c 'ESCALATED' "$findings" 2>/dev/null || true)
  fi

  goal=$(grep -A 1 "^## Goal" "$plan_dir/plan.md" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)

  printf "%s\t%s\t%s\t%s\n" "$plan_name" "$unchecked" "$escalated" "$goal"
  found=1
done < <(grep "^|" "$REGISTRY" | tail -n +3)

exit $((1 - found))

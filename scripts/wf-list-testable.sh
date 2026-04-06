#!/usr/bin/env bash
# wf-list-testable.sh
# Outputs eligible plans for human testing (Status: Verified, zero Open findings).
# Format per line: <plan-name>\t<goal>
# Exit 0 if any found, exit 1 if none.

set -euo pipefail

found=0

for plan in feature-branches/PLN-*/plans/verify/*/plan.md; do
  [ -f "$plan" ] || continue

  # Must have Status: Verified
  grep -q "Status.*Verified" "$plan" 2>/dev/null || continue

  # Must have zero Open findings
  findings="$(dirname "$plan")/findings.md"
  open_count=0
  if [ -f "$findings" ]; then
    open_count=$(grep -c "| Open |" "$findings" 2>/dev/null || true)
  fi
  [ "$open_count" -eq 0 ] || continue

  plan_name=$(basename "$(dirname "$plan")")
  goal=$(grep -A 1 "^## Goal" "$plan" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//')

  printf "%s\t%s\n" "$plan_name" "$goal"
  found=1
done

exit $((1 - found))

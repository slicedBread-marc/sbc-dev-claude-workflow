#!/usr/bin/env bash
# wf-list-testable.sh
# Outputs eligible plans for human testing by scanning develop's plans/ only.
# Eligible = Status: Verified (clean, no "-with-findings" suffix).
# Format per line: <plan-name>\t<goal>
# Exit 0 if any found, exit 1 if none.

set -euo pipefail

found=0

for plan in plans/verify/*/plan.md; do
  [ -f "$plan" ] || continue

  # Must have Status: Verified (not Verified-with-findings)
  grep -q "^Status:.*Verified" "$plan" 2>/dev/null || continue
  grep -q "^Status:.*with-findings" "$plan" 2>/dev/null && continue

  plan_name=$(basename "$(dirname "$plan")")
  goal=$(grep -A 1 "^## Goal" "$plan" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)

  printf "%s\t%s\n" "$plan_name" "$goal"
  found=1
done

exit $((1 - found))

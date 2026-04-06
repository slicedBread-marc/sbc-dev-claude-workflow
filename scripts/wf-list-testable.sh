#!/usr/bin/env bash
# wf-list-testable.sh
# Outputs eligible plans for human testing by scanning develop's plans/ only.
# Eligible = Status: Verified (clean, no "-with-findings" suffix) AND zero Open findings.
# Format per line (stdout): <plan-name>\t<goal>
# Stderr: "N plans with open findings" (if any were skipped)
# Exit 0 if any found, exit 1 if none.

set -euo pipefail

found=0
skipped_findings=0

for plan in plans/verify/*/plan.md; do
  [ -f "$plan" ] || continue

  # Must have Status: Verified (not Verified-with-findings)
  # Status line may be plain or markdown-formatted ("> **Status:** Verified")
  grep -qiE "(^|\*\*)?Status:\*?\*?\s*Verified" "$plan" 2>/dev/null || continue
  grep -qi "with-findings" "$plan" 2>/dev/null && continue

  plan_name=$(basename "$(dirname "$plan")")

  # Skip plans with open findings
  findings="plans/verify/$plan_name/findings.md"
  if [ -f "$findings" ] && grep -qE '\| Open \|' "$findings" 2>/dev/null; then
    skipped_findings=$((skipped_findings + 1))
    continue
  fi
  goal=$(grep -A 1 "^## Goal" "$plan" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)

  printf "%s\t%s\n" "$plan_name" "$goal"
  found=1
done

if [ "$skipped_findings" -gt 0 ]; then
  echo "$skipped_findings plan(s) with open findings" >&2
fi

exit $((1 - found))

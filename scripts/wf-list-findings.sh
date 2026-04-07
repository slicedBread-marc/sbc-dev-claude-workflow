#!/usr/bin/env bash
# wf-list-findings.sh
# Lists open/active findings across active and verify plans.
# Output: one section per plan with up to 3 findings rows.

set -euo pipefail

for dir in plans/active/PLN-* plans/verify/PLN-*; do
  [ -f "$dir/findings.md" ] || continue
  echo "=== $(basename "$dir") ==="
  grep "^| " "$dir/findings.md" | grep -E "\| (Open|Fixed|Verified|Escalated)" | head -3
done

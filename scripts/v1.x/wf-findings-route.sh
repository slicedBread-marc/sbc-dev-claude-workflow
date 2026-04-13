#!/usr/bin/env bash
# wf-findings-route.sh <plan-dir>
# Reads findings.md in the given plan directory and determines routing.
# Output: one of "escalated", "active", "clean"
#   escalated → has ESCALATED items (route to draft)
#   active    → has unchecked non-escalated items (route to active)
#   clean     → no unchecked findings (route to testing)
#
# Exit 0 always.

set -euo pipefail

plan_dir="${1:-}"

if [ -z "$plan_dir" ]; then
  echo "Usage: $0 <plan-dir>" >&2
  exit 1
fi

findings="$plan_dir/findings.md"

if [ ! -f "$findings" ]; then
  echo "clean"
  exit 0
fi

# Check for ESCALATED items or PLAN-SCOPED security findings (unchecked)
if grep -q '^\- \[ \].*ESCALATED\|^\- \[ \].*PLAN-SCOPED' "$findings" 2>/dev/null; then
  echo "escalated"
  exit 0
fi

# Check for any unchecked items
if grep -q '^\- \[ \]' "$findings" 2>/dev/null; then
  echo "active"
  exit 0
fi

echo "clean"

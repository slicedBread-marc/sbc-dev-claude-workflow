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

# Check for any unchecked items.
#
# BROAD-SCOPE is the exception. A finding marked BROAD-SCOPE is out of this
# plan's declared scope and is resolved by spawning an independent bug — the
# skill is explicit that "a plan can go to active or testing while still
# spawning bugs for out-of-scope security issues". Routing on it anyway sent
# the plan back to an implementer whose own Out of Scope section forbids the
# fix, so the only way out was to check off a finding nobody had acted on.
remaining=$(grep '^\- \[ \]' "$findings" 2>/dev/null | grep -cv 'BROAD-SCOPE' || true)
if [ "${remaining:-0}" -gt 0 ]; then
  echo "active"
  exit 0
fi

if grep -q '^\- \[ \].*BROAD-SCOPE' "$findings" 2>/dev/null; then
  echo "wf-findings-route: unchecked BROAD-SCOPE finding(s) present — not routing on them; file each as an independent bug" >&2
fi

echo "clean"

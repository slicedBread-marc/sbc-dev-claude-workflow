#!/usr/bin/env bash
# wf-list-findings.sh — lists unchecked findings across active/verify plans
# Uses REGISTRY.md to find plans, reads findings.md for unchecked items.
set -euo pipefail

REGISTRY="plans/REGISTRY.md"

while IFS='|' read -r _ id slug state _rest; do
  id=$(echo "$id" | xargs); slug=$(echo "$slug" | xargs); state=$(echo "$state" | xargs)
  [ "$state" = "active" ] || [ "$state" = "verify" ] || continue

  plan_dir="plans/${id}-${slug}"
  [ -f "$plan_dir/findings.md" ] || continue

  unchecked=$(grep -c '^\- \[ \]' "$plan_dir/findings.md" 2>/dev/null || true)
  [ "$unchecked" -gt 0 ] || continue

  echo "=== ${id}-${slug} ==="
  grep '^\- \[ \]' "$plan_dir/findings.md" | head -5
done < <(grep "^|" "$REGISTRY" | tail -n +3)

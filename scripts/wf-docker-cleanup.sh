#!/usr/bin/env bash
# wf-docker-cleanup.sh
# Removes orphaned Docker containers from completed plans.
# Scans for sbc-pln* compose projects and tears down any whose
# plan is no longer in testing/verify/active state.
#
# Safe to run anytime — only removes containers for finished plans.

set -euo pipefail

REGISTRY="plans/REGISTRY.md"
[ -f "$REGISTRY" ] || exit 0

# Get list of sbc-pln* compose projects
projects=$(docker compose ls --format json 2>/dev/null \
  | python3 -c "import sys,json; [print(p['Name']) for p in json.load(sys.stdin) if p['Name'].startswith('sbc-pln')]" 2>/dev/null) || true

[ -z "$projects" ] && exit 0

cleaned=0
while IFS= read -r proj; do
  # Extract plan number from project name (sbc-pln004 → 004)
  num="${proj#sbc-pln}"
  # Zero-pad to 3 digits for registry lookup
  padded=$(printf "%03d" "$num" 2>/dev/null) || continue
  plan_id="PLN-${padded}"

  # Check registry state
  state=$(grep "| ${plan_id} " "$REGISTRY" | awk -F'|' '{print $4}' | xargs 2>/dev/null) || true

  # Keep containers for plans still in progress
  case "$state" in
    testing|verify|active) continue ;;
  esac

  # Plan is complete/draft/missing — tear down
  docker compose -p "$proj" down --remove-orphans -v 2>/dev/null || true
  echo "Cleaned up $proj (PLN state: ${state:-not found})"
  cleaned=$((cleaned + 1))
done <<< "$projects"

[ "$cleaned" -gt 0 ] && echo "Removed $cleaned orphaned container(s)" >&2
exit 0

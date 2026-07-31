#!/usr/bin/env bash
# wf-docker-cleanup.sh
# Removes orphaned Docker containers from completed plans.
# Scans for {{project_slug}}-pln* compose projects and tears down any whose
# plan is no longer in testing/verify/active state.
#
# {{project_slug}} is baked in by install.sh at deploy time.
#
# Safe to run anytime — only removes containers for finished plans.

set -euo pipefail

REGISTRY="plans/REGISTRY.md"
[ -f "$REGISTRY" ] || exit 0

prefix="{{project_slug}}-pln"

# Get list of {{project_slug}}-pln* compose projects
projects=$(docker compose ls --format json 2>/dev/null \
  | PREFIX="$prefix" python3 -c "import os,sys,json; p=os.environ['PREFIX']; [print(x['Name']) for x in json.load(sys.stdin) if x['Name'].startswith(p)]" 2>/dev/null) || true

[ -z "$projects" ] && exit 0

cleaned=0
while IFS= read -r proj; do
  # Extract plan number from project name ({{project_slug}}-pln004 → 004)
  num="${proj#$prefix}"
  # Zero-pad to 3 digits for registry lookup
  padded=$(printf "%03d" "$num" 2>/dev/null) || continue
  plan_id="PLN-${padded}"

  # Check registry state
  state=$(grep "^| ${plan_id} " "$REGISTRY" | awk -F'|' '{print $4}' | xargs 2>/dev/null) || true

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

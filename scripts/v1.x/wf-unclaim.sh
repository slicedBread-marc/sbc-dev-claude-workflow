#!/usr/bin/env bash
# wf-unclaim.sh <plan-name>
# Releases a claim on a plan. Safe to call even if no claim exists.

set -euo pipefail

plan_name="${1:?Usage: wf-unclaim.sh <plan-name>}"

# Always resolve to the develop root (first worktree) so unclaim works
# regardless of whether this runs from develop or a feature worktree.
develop_root=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')
claimfile="$develop_root/plans/${plan_name}/.wf-claim"

rm -f "$claimfile"
echo "Released $plan_name"

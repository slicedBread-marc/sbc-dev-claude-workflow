#!/usr/bin/env bash
# wf-unclaim.sh <plan-name>
# Releases a claim on a plan. Safe to call even if no claim exists.

set -euo pipefail

plan_name="${1:?Usage: wf-unclaim.sh <plan-name>}"
claimfile="plans/${plan_name}/.wf-claim"

rm -f "$claimfile"
echo "Released $plan_name"

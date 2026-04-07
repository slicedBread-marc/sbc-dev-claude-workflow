#!/usr/bin/env bash
# wf-claim.sh <plan-name>
# Marks a plan as actively being worked on by writing a timestamp.
# Claim file: plans/<plan-name>/.wf-claim
# Other terminals see this as "processing" in list scripts.
# Claims expire after 2 hours (7200 seconds).

set -euo pipefail

plan_name="${1:?Usage: wf-claim.sh <plan-name>}"
plan_dir="plans/${plan_name}"
claimfile="$plan_dir/.wf-claim"

[ -d "$plan_dir" ] || { echo "Error: plan directory not found: $plan_dir" >&2; exit 1; }

date +%s > "$claimfile"
echo "Claimed $plan_name"

#!/usr/bin/env bash
# wf-plan-port.sh <plan-folder-name>
# Given a plan folder like PLN-004-deployment-date-footer, outputs:
#   PLAN_ID=4
#   FEATURE_PORT=8104
#   COMPOSE_PROJECT_NAME=sbc-pln004
# Source this or eval its output to set variables in the calling shell.

set -euo pipefail

plan_folder="${1:-}"
if [ -z "$plan_folder" ]; then
  echo "Usage: $0 <plan-folder-name>" >&2
  exit 1
fi

plan_id_raw=$(echo "$plan_folder" | grep -oE 'PLN-[0-9]+' | sed 's/PLN-//')
plan_id=$((10#$plan_id_raw))  # strip leading zeros for arithmetic
plan_id_padded=$(printf '%03d' "$plan_id")

echo "PLAN_ID=$plan_id"
echo "FEATURE_PORT=$((8100 + plan_id))"
echo "COMPOSE_PROJECT_NAME=sbc-pln${plan_id_padded}"

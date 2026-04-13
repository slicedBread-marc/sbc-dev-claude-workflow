#!/usr/bin/env bash
# wf-plan-ref.sh
# Reads .plan-ref in the current directory and resolves the plan.
# Must be run from a feature branch worktree directory.
#
# Output (eval-friendly):
#   PLAN_ID=PLN-004
#   PLAN_DIR=../../plans/PLN-004-deployment-date-footer
#   PLAN_NAME=PLN-004-deployment-date-footer
#
# Exit 0 if found, 1 if not.

set -euo pipefail

if [ ! -f ".plan-ref" ]; then
  echo "Error: .plan-ref not found in $(pwd)" >&2
  exit 1
fi

plan_id=$(cat .plan-ref | xargs)
if [ -z "$plan_id" ]; then
  echo "Error: .plan-ref is empty" >&2
  exit 1
fi

# Resolve plan directory — look in ../../plans/ (develop worktree relative path)
plan_dir=""
for d in ../../plans/${plan_id}-*/; do
  if [ -d "$d" ]; then
    plan_dir="${d%/}"
    break
  fi
done

if [ -z "$plan_dir" ]; then
  echo "Error: no plan directory found for $plan_id in ../../plans/" >&2
  exit 1
fi

plan_name=$(basename "$plan_dir")

echo "PLAN_ID=$plan_id"
echo "PLAN_DIR=$plan_dir"
echo "PLAN_NAME=$plan_name"

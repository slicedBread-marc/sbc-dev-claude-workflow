#!/usr/bin/env bash
# wf-plan-port.sh <plan-folder-name>
# Given a plan folder like PLN-004-deployment-date-footer, outputs:
#   PLAN_ID=4
#   FEATURE_PORT=8104
#   COMPOSE_PROJECT_NAME=<project_slug>-pln004
# Source this or eval its output to set variables in the calling shell.
#
# Project slug is resolved in order:
#   1. PROJECT_SLUG env var (override)
#   2. project_slug in claude-workflow.yml (walking up from CWD)
#   3. fallback "wf"

set -euo pipefail

plan_folder="${1:-}"
if [ -z "$plan_folder" ]; then
  echo "Usage: $0 <plan-folder-name>" >&2
  exit 1
fi

resolve_project_slug() {
  if [ -n "${PROJECT_SLUG:-}" ]; then printf '%s' "$PROJECT_SLUG"; return; fi
  local dir="$PWD" cfg=""
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/claude-workflow.yml" ]; then cfg="$dir/claude-workflow.yml"; break; fi
    dir="$(dirname "$dir")"
  done
  if [ -n "$cfg" ]; then
    local v
    v=$(grep '^project_slug:' "$cfg" 2>/dev/null \
          | sed 's/^project_slug:[[:space:]]*//;s/"//g;s/^[[:space:]]*//;s/[[:space:]]*$//' \
          | head -1)
    if [ -n "$v" ]; then printf '%s' "$v"; return; fi
  fi
  printf 'wf'
}

plan_id_raw=$(echo "$plan_folder" | grep -oE 'PLN-[0-9]+' | sed 's/PLN-//')
plan_id=$((10#$plan_id_raw))  # strip leading zeros for arithmetic
plan_id_padded=$(printf '%03d' "$plan_id")
slug=$(resolve_project_slug)

echo "PLAN_ID=$plan_id"
echo "FEATURE_PORT=$((8100 + plan_id))"
echo "COMPOSE_PROJECT_NAME=${slug}-pln${plan_id_padded}"

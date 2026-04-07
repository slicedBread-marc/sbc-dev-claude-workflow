#!/usr/bin/env bash
# wf-docker-up.sh [plan-folder-name]
# Starts a Docker container for a feature branch plan.
# If no plan folder given, derives from current branch name.
# Sets up port, project name, builds, and waits for health.
#
# Output: FEATURE_PORT and COMPOSE_PROJECT_NAME (eval-friendly)
# Exit 0 on healthy, 1 on timeout.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

plan_folder="${1:-}"
if [ -z "$plan_folder" ]; then
  branch=$(git branch --show-current)
  plan_folder=$(echo "$branch" | sed 's|feature/||')
fi

eval "$("$SCRIPT_DIR/wf-plan-port.sh" "$plan_folder")"

echo "FEATURE_PORT=$FEATURE_PORT"
echo "COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME"

# Start the container
FEATURE_PORT=$FEATURE_PORT docker compose \
  -f docker/docker-compose.yml \
  -p "$COMPOSE_PROJECT_NAME" \
  up --build -d

# Wait for health
"$SCRIPT_DIR/wf-wait-healthy.sh"

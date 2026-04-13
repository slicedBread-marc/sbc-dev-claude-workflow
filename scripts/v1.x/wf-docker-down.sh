#!/usr/bin/env bash
# wf-docker-down.sh [plan-folder-name]
# Tears down the Docker container for a feature branch plan.
# If no plan folder given, derives from current branch name.
#
# Exit 0 always (cleanup is best-effort).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

plan_folder="${1:-}"
if [ -z "$plan_folder" ]; then
  branch=$(git branch --show-current 2>/dev/null || echo "")
  plan_folder=$(echo "$branch" | sed 's|feature/||')
fi

if [ -z "$plan_folder" ]; then
  echo "Warning: could not determine plan folder" >&2
  exit 0
fi

eval "$("$SCRIPT_DIR/wf-plan-port.sh" "$plan_folder")" 2>/dev/null || true

if [ -z "${COMPOSE_PROJECT_NAME:-}" ]; then
  echo "Warning: could not determine COMPOSE_PROJECT_NAME for $plan_folder" >&2
  exit 0
fi

docker compose -f docker/docker-compose.yml \
  -p "$COMPOSE_PROJECT_NAME" \
  down -v 2>/dev/null || true

docker ps -a --filter "name=$COMPOSE_PROJECT_NAME" \
  --format "{{.ID}}" | xargs -r docker rm -f 2>/dev/null || true

echo "Container $COMPOSE_PROJECT_NAME stopped"

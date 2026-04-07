#!/usr/bin/env bash
# wf-wait-healthy.sh
# Derives the feature port from the current branch name and waits for
# the health endpoint to respond (max 20 seconds).
# Exit 0 on success, 1 on timeout.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Derive plan folder from current branch (feature/PLN-NNN-name → PLN-NNN-name)
BRANCH=$(git branch --show-current)
PLAN_FOLDER=$(echo "$BRANCH" | sed 's|feature/||')

eval "$("$SCRIPT_DIR/wf-plan-port.sh" "$PLAN_FOLDER")"

for i in $(seq 1 20); do
  if curl -s "http://localhost:$FEATURE_PORT/health" > /dev/null 2>&1; then
    echo "✓ App is ready at http://localhost:$FEATURE_PORT"
    exit 0
  fi
  sleep 1
done

echo "✗ App failed to start within 20 seconds" >&2
exit 1

#!/usr/bin/env bash
# wf-branch-check.sh <expected-branch> [auto-switch]
# Checks current branch matches expected. If auto-switch is "true" and on
# wrong branch, switches automatically.
#
# Examples:
#   wf-branch-check.sh develop true    → switches to develop if not on it
#   wf-branch-check.sh release         → prints error if not on release
#   wf-branch-check.sh feature         → checks if on any feature/* branch
#
# Output: CURRENT_BRANCH=<branch-name>
# Exit 0 if on correct branch (or switched), 1 if wrong branch.

set -euo pipefail

expected="${1:-}"
auto_switch="${2:-false}"

if [ -z "$expected" ]; then
  echo "Usage: $0 <expected-branch> [auto-switch]" >&2
  exit 1
fi

current=$(git branch --show-current)

# Special case: "feature" matches any feature/* branch
if [ "$expected" = "feature" ]; then
  if echo "$current" | grep -q "^feature/"; then
    echo "CURRENT_BRANCH=$current"
    exit 0
  else
    echo "Error: expected a feature/* branch, on '$current'" >&2
    exit 1
  fi
fi

if [ "$current" = "$expected" ]; then
  echo "CURRENT_BRANCH=$current"
  exit 0
fi

if [ "$auto_switch" = "true" ]; then
  # Reset infra files before switching — prevents unmerged/dirty conflicts
  # Use HEAD to resolve both dirty and unmerged (U) states
  git checkout HEAD -- .claude/workflow-version .claude/workflow.md 2>/dev/null || true
  git checkout "$expected" 2>/dev/null
  echo "CURRENT_BRANCH=$expected"
  echo "SWITCHED_FROM=$current"
  exit 0
fi

echo "Error: expected branch '$expected', on '$current'" >&2
exit 1

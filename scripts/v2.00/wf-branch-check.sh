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

  # A missing target branch used to be indistinguishable from any other
  # failure: `git checkout 2>/dev/null` swallowed "pathspec did not match",
  # and `set -e` aborted before the echo — so the caller got exit 1 with
  # completely empty stdout AND stderr. Greenfield repos hit this every time,
  # because develop does not exist yet.
  if ! git rev-parse --verify --quiet "refs/heads/$expected" >/dev/null; then
    # Track an existing remote branch if there is one, otherwise create it.
    if git rev-parse --verify --quiet "refs/remotes/origin/$expected" >/dev/null; then
      git checkout -b "$expected" --track "origin/$expected" || {
        echo "Error: branch '$expected' exists on origin but could not be checked out" >&2
        exit 1
      }
      echo "CREATED_BRANCH=$expected (tracking origin/$expected)"
    else
      git checkout -b "$expected" || {
        echo "Error: branch '$expected' does not exist and could not be created from '$current'" >&2
        exit 1
      }
      echo "CREATED_BRANCH=$expected (from $current)"
    fi
    echo "CURRENT_BRANCH=$expected"
    echo "SWITCHED_FROM=$current"
    exit 0
  fi

  # Real git errors surface — no 2>/dev/null. A dirty tree that blocks the
  # switch is something the caller has to see.
  if ! git checkout "$expected"; then
    echo "Error: could not switch from '$current' to '$expected'" >&2
    exit 1
  fi
  echo "CURRENT_BRANCH=$expected"
  echo "SWITCHED_FROM=$current"
  exit 0
fi

echo "Error: expected branch '$expected', on '$current'" >&2
exit 1

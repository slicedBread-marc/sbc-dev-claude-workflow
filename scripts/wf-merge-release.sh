#!/usr/bin/env bash
# wf-merge-release.sh
# Merges origin/release into the current feature branch, auto-resolving
# conflicts in .plan-ref by keeping the feature branch's version.
# Run this before PR merge to ensure the branch is mergeable.
#
# Exit codes:
#   0 — merge succeeded (clean or auto-resolved)
#   1 — non-trivial conflicts remain (caller must resolve)

set -euo pipefail

# Must be on a feature branch
branch=$(git branch --show-current)
[[ "$branch" == feature/* ]] || { echo "Error: not on a feature branch (on $branch)" >&2; exit 1; }

git fetch origin release

# Attempt clean merge first
if git merge origin/release --no-edit 2>/dev/null; then
  echo "Merged release cleanly."
  exit 0
fi

echo "Merge conflicts detected — auto-resolving known files..."

conflicted=$(git diff --name-only --diff-filter=U)
has_real_conflicts=false

while IFS= read -r file; do
  [ -z "$file" ] && continue
  if [[ "$file" == .plan-ref ]]; then
    git checkout --ours -- "$file"
    git add "$file"
    echo "  resolved: $file (kept feature branch version)"
  elif [[ "$file" == plans/* ]]; then
    git checkout --ours -- "$file"
    git add "$file"
    echo "  resolved: $file (kept feature branch version)"
  else
    has_real_conflicts=true
    echo "  CONFLICT: $file (requires manual resolution)"
  fi
done <<< "$conflicted"

if $has_real_conflicts; then
  echo ""
  echo "Error: non-trivial conflicts remain. Resolve them, then run: git commit --no-edit"
  exit 1
fi

git commit --no-edit
echo "Merged release with auto-resolved files."

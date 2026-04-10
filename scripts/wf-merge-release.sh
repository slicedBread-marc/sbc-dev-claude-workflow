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

# ── Pre-sync workflow infra for non-sparse worktrees ────────────────────────
# Sparse-checkout worktrees exclude infra files from tracking, so no conflicts.
# Legacy (non-sparse) worktrees still track them — reset to release's version
# before merging so they can't cause dirty-tree failures or conflicts.
if ! git config core.sparseCheckout 2>/dev/null | grep -q true; then
  needs_sync=false
  for path in .claude/workflow.md .claude/workflow-version; do
    if [ -f "$path" ]; then
      git checkout origin/release -- "$path" 2>/dev/null && needs_sync=true || true
    fi
  done
  git checkout origin/release -- .claude/skills/ 2>/dev/null && needs_sync=true || true
  git checkout origin/release -- plans/ 2>/dev/null && needs_sync=true || true
  git checkout origin/release -- bugs/ 2>/dev/null && needs_sync=true || true
  git checkout origin/release -- briefs/ 2>/dev/null && needs_sync=true || true
  git checkout origin/release -- templates/ 2>/dev/null && needs_sync=true || true
  for f in scripts/wf-*.sh; do
    [ -f "$f" ] && git checkout origin/release -- "$f" 2>/dev/null && needs_sync=true || true
  done
  if $needs_sync; then
    git add .claude/workflow.md .claude/workflow-version .claude/skills/ plans/ bugs/ briefs/ templates/ scripts/wf-*.sh 2>/dev/null || true
    if ! git diff --cached --quiet 2>/dev/null; then
      git commit -m "chore: sync workflow infra from release"
      echo "Pre-synced workflow infra to release's version."
    fi
  fi
fi

# Attempt clean merge first
if git merge origin/release --no-edit 2>/dev/null; then
  echo "Merged release cleanly."
  exit 0
fi

echo "Merge conflicts detected — auto-resolving known files..."

# If no MERGE_HEAD, the merge was aborted (dirty working tree), not conflicted.
if ! git rev-parse MERGE_HEAD >/dev/null 2>&1; then
  echo "Error: merge aborted — working tree has uncommitted changes that would be overwritten." >&2
  echo "Run 'git status' to see which files are dirty, then commit or stash them." >&2
  exit 1
fi

conflicted=$(git diff --name-only --diff-filter=U)
has_real_conflicts=false

while IFS= read -r file; do
  [ -z "$file" ] && continue
  if [[ "$file" == .plan-ref ]]; then
    # Derive plan ID from branch name — more reliable than git checkout --ours
    # which can fail with "pathspec did not match" in some conflict states
    plan_id=$(echo "$branch" | sed 's#^feature/##; s#^\(PLN-[0-9]*\).*#\1#')
    echo "$plan_id" > "$file"
    git add "$file"
    echo "  resolved: $file (kept $plan_id from branch name)"
  elif [[ "$file" == plans/* ]] || [[ "$file" == bugs/* ]] || [[ "$file" == briefs/* ]]; then
    git checkout --ours -- "$file"
    git add "$file"
    echo "  resolved: $file (kept feature branch version)"
  elif [[ "$file" == .claude/* ]] || [[ "$file" == scripts/* ]] || [[ "$file" == skills/* ]] || [[ "$file" == templates/* ]]; then
    git checkout --theirs -- "$file"
    git add "$file"
    echo "  resolved: $file (took release version)"
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

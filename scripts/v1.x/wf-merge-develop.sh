#!/usr/bin/env bash
# wf-merge-develop.sh
# Merges develop into the current feature branch, auto-resolving conflicts
# in plans/ and .plan-ref by taking develop's version (these files belong
# to develop, not feature branches).
#
# Exit codes:
#   0 — merge succeeded (clean or auto-resolved)
#   1 — non-plan conflicts remain (caller must resolve)

set -euo pipefail

# Must be on a feature branch
branch=$(git branch --show-current)
[[ "$branch" == feature/* ]] || { echo "Error: not on a feature branch (on $branch)" >&2; exit 1; }

# Auto-claim: mark this plan as actively being worked on
develop_root=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')
plan_name=$(echo "$branch" | sed 's#^feature/##')
claim_dir="$develop_root/plans/$plan_name"
if [ -d "$claim_dir" ]; then
  _pid=$PPID
  for _i in 1 2 3 4 5; do
    _name=$(ps -o comm= -p "$_pid" 2>/dev/null)
    case "$_name" in bash|sh|zsh|dash) _pid=$(ps -o ppid= -p "$_pid" 2>/dev/null | tr -d ' ') ;; *) break ;; esac
  done
  printf '%s\n%s\n' "$(date +%s)" "$_pid" > "$claim_dir/.wf-claim"
fi

# ── Pre-sync workflow infra for non-sparse worktrees ────────────────────────
# Sparse-checkout worktrees exclude infra files from tracking, so no conflicts.
# Legacy (non-sparse) worktrees still track them — reset to develop's version
# before merging so they can't cause dirty-tree failures or conflicts.
if ! git config core.sparseCheckout 2>/dev/null | grep -q true; then
  needs_sync=false
  for path in .claude/workflow.md .claude/workflow-version; do
    if [ -f "$path" ]; then
      git checkout develop -- "$path" 2>/dev/null && needs_sync=true || true
    fi
  done
  git checkout develop -- .claude/skills/ 2>/dev/null && needs_sync=true || true
  git checkout develop -- plans/ 2>/dev/null && needs_sync=true || true
  git checkout develop -- bugs/ 2>/dev/null && needs_sync=true || true
  git checkout develop -- briefs/ 2>/dev/null && needs_sync=true || true
  git checkout develop -- templates/ 2>/dev/null && needs_sync=true || true
  for f in scripts/wf-*.sh; do
    [ -f "$f" ] && git checkout develop -- "$f" 2>/dev/null && needs_sync=true || true
  done
  if $needs_sync; then
    git add .claude/workflow.md .claude/workflow-version .claude/skills/ plans/ bugs/ briefs/ templates/ scripts/wf-*.sh 2>/dev/null || true
    if ! git diff --cached --quiet 2>/dev/null; then
      git commit -m "chore: sync workflow infra from develop"
      echo "Pre-synced workflow infra to develop's version."
    fi
  fi
fi

# Attempt clean merge first
if git merge develop --no-edit 2>/dev/null; then
  echo "Merged develop cleanly."
  exit 0
fi

echo "Merge conflicts detected — auto-resolving plan files..."

# If no MERGE_HEAD, the merge was aborted (dirty working tree), not conflicted.
if ! git rev-parse MERGE_HEAD >/dev/null 2>&1; then
  echo "Error: merge aborted — working tree has uncommitted changes that would be overwritten." >&2
  echo "Run 'git status' to see which files are dirty, then commit or stash them." >&2
  exit 1
fi

# Auto-resolve plans/ and .plan-ref by taking develop's version
# Use ls-files -u instead of diff --diff-filter=U: the latter skips files excluded
# by sparse checkout, leaving hidden unmerged index entries that block git commit.
conflicted=$(git ls-files -u | awk '{print $4}' | sort -u)
has_non_plan_conflicts=false

while IFS= read -r file; do
  [ -z "$file" ] && continue
  if [[ "$file" == plans/* ]] || [[ "$file" == bugs/* ]] || [[ "$file" == briefs/* ]] || [[ "$file" == .claude/* ]] || [[ "$file" == scripts/* ]] || [[ "$file" == skills/* ]] || [[ "$file" == templates/* ]]; then
    git checkout develop -- "$file" 2>/dev/null || git checkout --theirs -- "$file"
    git add "$file"
    echo "  resolved: $file (took develop's version)"
  elif [[ "$file" == .plan-ref ]]; then
    # Derive plan ID from branch name — more reliable than git checkout --ours
    # which can fail with "pathspec did not match" in some conflict states
    plan_id=$(echo "$branch" | sed 's#^feature/##; s#^\(PLN-[0-9]*\).*#\1#')
    echo "$plan_id" > "$file"
    git add "$file"
    echo "  resolved: $file (kept $plan_id from branch name)"
  else
    has_non_plan_conflicts=true
    echo "  CONFLICT: $file (requires manual resolution)"
  fi
done <<< "$conflicted"

if $has_non_plan_conflicts; then
  echo ""
  echo "Error: non-plan conflicts remain. Resolve them, then run: git commit --no-edit"
  exit 1
fi

git commit --no-edit
echo "Merged develop with auto-resolved plan files."

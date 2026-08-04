#!/usr/bin/env bash
# wf-infra-sync.sh [worktree-path]
#
# Commits develop-owned workflow infra that a deploy wrote into a feature
# worktree, so the worktree is clean again.
#
# WHY THIS EXISTS
#
# Three paths must physically exist inside a feature worktree for a session
# there to work at all: `.claude/skills/**` (Claude Code reads skills from the
# tree it is running in), `scripts/wf-exec.sh` (skills invoke it by relative
# path) and `.claude/workflow.md`. Everything else workflow-owned is resolved
# from the MAIN worktree and is sparse-excluded — see wf-worktree-sparse.sh for
# why "excluded" and "written by deploy" are mutually exclusive states.
#
# Because they exist and deploy rewrites them, a deploy that lands mid-plan
# leaves them modified against the feature branch's blob. Left alone that is a
# dirty tree the implementer must hand-exclude from every `git add`, and a
# `git merge develop` that aborts outright.
#
# The reconciliation is a commit of develop's own bytes onto the feature
# branch. It merges back as a no-op: both sides hold identical content.
#
# SAFETY
#
# The commit is pathspec-scoped (`git commit -- <paths>`), never a bare
# `git commit`. This script is called from install.sh, which can run while a
# worker session has unrelated work staged in the same worktree — an index-wide
# commit would sweep that work into a "chore:" commit under someone else's
# feet. A pathspec commit touches only these paths whatever the index holds.
#
# Exit 0 whether or not anything needed syncing. Never fails a caller.

set -euo pipefail

WT_PATH="${1:-$PWD}"
cd "$WT_PATH" 2>/dev/null || exit 0

# Feature branches only. On develop these files ARE the source of truth and a
# "sync" would be a self-referential commit.
branch=$(git branch --show-current 2>/dev/null || echo "")
case "$branch" in
  feature/*) ;;
  *) exit 0 ;;
esac

INFRA=(.claude/workflow.md .claude/skills scripts/wf-exec.sh)

present=()
for p in "${INFRA[@]}"; do
  [ -e "$p" ] && present+=("$p")
done
[ "${#present[@]}" -gt 0 ] || exit 0

git add -- "${present[@]}" 2>/dev/null || true

# Anything actually different from HEAD on these paths?
if git diff --cached --quiet -- "${present[@]}" 2>/dev/null; then
  exit 0
fi

git commit -q -m "chore: sync workflow infra from develop" -- "${present[@]}" 2>/dev/null || exit 0
echo "Synced workflow infra from develop (${#present[@]} path(s)) — worktree is clean"

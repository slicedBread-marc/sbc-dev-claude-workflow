#!/usr/bin/env bash
# wf-worktree-sparse.sh <worktree-path>
#
# Configures sparse-checkout on a feature worktree so that workflow
# infrastructure files are excluded from git tracking.  These files
# belong to develop — tracking them on feature branches causes merge
# conflicts every time develop advances (deploy, state transitions).
#
# Excluded paths:
#   .claude/workflow.md, .claude/workflow-version  — stamped by deploy
#   .claude/skills/           — skill definitions, deployed from library
#   plans/                    — registry + plan content, develop-only
#   templates/                — plan templates
#   scripts/wf-*.sh           — workflow scripts (legacy flat layout)
#   scripts/v*/wf-*.sh        — versioned script snapshots, deployed from library
#   scripts/version-map.txt   — workflow→folder mapping, deployed from library
#
# After sparse-checkout, install.sh propagation can still copy these
# files into the worktree for runtime use — git will ignore them.

set -euo pipefail

WT_PATH="${1:?Usage: wf-worktree-sparse.sh <worktree-path>}"

cd "$WT_PATH"

# Get the worktree-specific git admin dir (e.g. .git/worktrees/PLN-NNN-slug)
# and the SHARED admin dir, which is where repo-wide config and the main
# worktree's own info/ live.
#
# --show-toplevel would be wrong here: git gives every linked worktree its own
# toplevel, so from inside a feature worktree it returns that worktree, not the
# main repo. Everything below then targets the worktree's `.git` — which is a
# regular file (a gitdir pointer), not a directory — and `mkdir -p .git/info`
# dies with "Not a directory" before sparse-checkout is ever configured.
# --git-common-dir is the one that stays pointed at the main repo from anywhere.
GIT_DIR=$(cd "$(git rev-parse --git-dir)" && pwd)
COMMON_DIR=$(cd "$(git rev-parse --git-common-dir)" && pwd)
REPO_ROOT=$(dirname "$COMMON_DIR")

# Enable sparse checkout in the shared repo config.
# This is a repo-wide flag, so we must also protect the main worktree
# (develop) by ensuring its sparse-checkout file includes everything.
git -C "$REPO_ROOT" config core.sparseCheckout true

# Protect the main worktree: ensure develop's sparse-checkout file is a
# catch-all so the global flag doesn't accidentally exclude files there.
main_sparse="$COMMON_DIR/info/sparse-checkout"
if [ ! -f "$main_sparse" ] || grep -q '^!' "$main_sparse"; then
  mkdir -p "$COMMON_DIR/info"
  echo '/**' > "$main_sparse"
fi

# Write patterns directly to the worktree-specific sparse-checkout file.
# `git sparse-checkout set` behaves inconsistently in linked worktrees on
# git 2.25-2.39 — writing the file directly is reliable across versions.
mkdir -p "$GIT_DIR/info"
cat > "$GIT_DIR/info/sparse-checkout" <<'PATTERNS'
/**
!.claude/workflow.md
!.claude/workflow-version
!.claude/skills/**
!plans/**
!templates/**
!scripts/wf-*.sh
!scripts/version-map.txt
!scripts/v*/wf-*.sh
PATTERNS

# Apply the patterns. This sets the skip-worktree bit on excluded files so git
# won't modify them in the working tree or show them in git status.
# Locally-modified files (e.g. scripts updated by deploy) are left as-is —
# those won't differ from develop and won't cause merge conflicts.
git sparse-checkout reapply 2>/dev/null || true

echo "Sparse checkout configured — workflow infra excluded from tracking"

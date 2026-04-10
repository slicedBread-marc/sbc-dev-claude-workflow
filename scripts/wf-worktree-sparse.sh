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
#   scripts/wf-*.sh           — workflow scripts, deployed from library
#
# After sparse-checkout, install.sh propagation can still copy these
# files into the worktree for runtime use — git will ignore them.

set -euo pipefail

WT_PATH="${1:?Usage: wf-worktree-sparse.sh <worktree-path>}"

cd "$WT_PATH"

# Get the worktree-specific git admin dir (e.g. .git/worktrees/PLN-NNN-slug)
# and the main repo root for shared config.
GIT_DIR=$(git rev-parse --git-dir)
REPO_ROOT=$(git rev-parse --show-toplevel)

# Enable sparse checkout in the shared repo config.
# Worktrees without their own patterns file default to including all files,
# so this does not affect the main worktree.
git -C "$REPO_ROOT" config core.sparseCheckout true

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
PATTERNS

# Apply the patterns. This sets the skip-worktree bit on excluded files so git
# won't modify them in the working tree or show them in git status.
# Locally-modified files (e.g. scripts updated by deploy) are left as-is —
# those won't differ from develop and won't cause merge conflicts.
git sparse-checkout reapply 2>/dev/null || true

# Verify: warn if REGISTRY.md specifically is indexed without skip-worktree.
# Runtime files (e.g. .wf-claim) may be tracked normally — that's acceptable.
if git ls-files -t plans/REGISTRY.md 2>/dev/null | grep -v '^S ' | grep -q .; then
    echo "Warning: plans/REGISTRY.md lacks skip-worktree protection — it could corrupt REGISTRY via merge"
fi

echo "Sparse checkout configured — workflow infra excluded from tracking"

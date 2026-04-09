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

# Enable sparse-checkout in non-cone mode (gitignore-style patterns)
git sparse-checkout init --no-cone

# Include everything, then carve out workflow infrastructure
git sparse-checkout set \
  '**' \
  '!/.claude/workflow.md' \
  '!/.claude/workflow-version' \
  '!/.claude/skills/' \
  '!/plans/' \
  '!/templates/' \
  '!/scripts/wf-*.sh'

echo "Sparse checkout configured — workflow infra excluded from tracking"

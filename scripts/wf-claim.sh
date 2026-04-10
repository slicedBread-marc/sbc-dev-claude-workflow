#!/usr/bin/env bash
# wf-claim.sh <plan-name>
# Marks a plan as actively being worked on by writing a timestamp.
# Claim file: plans/<plan-name>/.wf-claim
# Other terminals see this as "processing" in list scripts.
# Claims expire after 2 hours (7200 seconds).

set -euo pipefail

plan_name="${1:?Usage: wf-claim.sh <plan-name>}"
plan_dir="plans/${plan_name}"
claimfile="$plan_dir/.wf-claim"

if [ ! -d "$plan_dir" ]; then
  # Plan dir may be excluded by sparse checkout — restore from git if present
  tree_hash=$(git ls-tree HEAD "$plan_dir" 2>/dev/null | awk '{print $3}')
  if [ -z "$tree_hash" ]; then
    echo "Error: plan directory not found: $plan_dir" >&2
    exit 1
  fi
  mkdir -p "$plan_dir"
  while IFS=$'\t' read -r meta file; do
    hash=$(echo "$meta" | awk '{print $3}')
    git cat-file -p "$hash" > "$plan_dir/$file"
  done < <(git ls-tree "$tree_hash")
  # Clear skip-worktree bits so git tracks these files normally
  git update-index --no-skip-worktree "$plan_dir"/* 2>/dev/null || true
  echo "Restored $plan_dir from git (sparse checkout)"
fi

date +%s > "$claimfile"
echo "Claimed $plan_name"

#!/usr/bin/env bash
# wf-claim.sh <plan-name>
# Marks a plan as actively being worked on by writing a timestamp + PID.
# Claim file: plans/<plan-name>/.wf-claim  (line 1: timestamp, line 2: PID)
# Other terminals see this as "processing" in list scripts.
# Claims expire when the owning process dies or after 2 hours (7200 seconds).

set -euo pipefail

plan_name="${1:?Usage: wf-claim.sh <plan-name>}"

# Always resolve to the develop root (first worktree) so the claim is visible
# to list scripts regardless of whether this runs from develop or a feature worktree.
develop_root=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')
plan_dir="$develop_root/plans/${plan_name}"
claimfile="$plan_dir/.wf-claim"

if [ ! -d "$plan_dir" ]; then
  echo "Error: plan directory not found: $plan_dir" >&2
  exit 1
fi

# Walk up the process tree to find the long-lived parent (claude itself)
_pid=$PPID
for _i in 1 2 3 4 5; do
  _name=$(ps -o comm= -p "$_pid" 2>/dev/null)
  case "$_name" in bash|sh|zsh|dash) _pid=$(ps -o ppid= -p "$_pid" 2>/dev/null | tr -d ' ') ;; *) break ;; esac
done
printf '%s\n%s\n' "$(date +%s)" "$_pid" > "$claimfile"
echo "Claimed $plan_name"

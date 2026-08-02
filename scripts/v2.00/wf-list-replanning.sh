#!/usr/bin/env bash
# wf-list-replanning.sh — plans in draft state with ESCALATED findings
# Format: <plan-name>\t<escalated_count>\t<goal>
# Exit 0 if any found, exit 1 if none.
set -euo pipefail

# Registry work is develop-root work. Sourced/derived paths below are relative
# ("plans/REGISTRY.md", "plans/PLN-NNN-slug/..."), and verify and implement
# workers run with their CWD inside a feature worktree — where those resolve to
# that worktree's own stale copy. The write then "succeeds", the verification
# grep passes against the copy it just wrote, and the real registry never moves.
# The main worktree is always the first one git lists.
_wf_root=$(git worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //') || true
[ -n "$_wf_root" ] || _wf_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
cd "$_wf_root"

REGISTRY="plans/REGISTRY.md"
found=0

while IFS='|' read -r _ id slug state _rest; do
  id=$(echo "$id" | xargs); slug=$(echo "$slug" | xargs); state=$(echo "$state" | xargs)
  [ "$state" = "draft" ] || continue

  plan_dir="plans/${id}-${slug}"
  findings="$plan_dir/findings.md"

  [ -f "$findings" ] && grep -q "ESCALATED" "$findings" 2>/dev/null || continue

  escalated=$(grep -c "ESCALATED" "$findings" 2>/dev/null || echo 0)
  goal=$(grep -A 1 "^## Goal" "$plan_dir/plan.md" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)
  printf "%s\t%s\t%s\n" "${id}-${slug}" "$escalated" "$goal"
  found=1
done < <(grep "^|" "$REGISTRY" | tail -n +3)

exit $((1 - found))

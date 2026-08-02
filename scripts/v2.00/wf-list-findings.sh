#!/usr/bin/env bash
# wf-list-findings.sh — lists unchecked findings across active/verify plans
# Uses REGISTRY.md to find plans, reads findings.md for unchecked items.
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

while IFS='|' read -r _ id slug state _rest; do
  id=$(echo "$id" | xargs); slug=$(echo "$slug" | xargs); state=$(echo "$state" | xargs)
  [ "$state" = "active" ] || [ "$state" = "verify" ] || continue

  plan_dir="plans/${id}-${slug}"
  [ -f "$plan_dir/findings.md" ] || continue

  unchecked=$(grep -c '^\- \[ \]' "$plan_dir/findings.md" 2>/dev/null || true)
  [ "$unchecked" -gt 0 ] || continue

  echo "=== ${id}-${slug} ==="
  grep '^\- \[ \]' "$plan_dir/findings.md" | head -5
done < <(grep "^|" "$REGISTRY" | tail -n +3)

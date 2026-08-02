#!/usr/bin/env bash
# wf-list-consistency.sh [plan-id]
#
# Plans that are `ready`, declare Deps, and have not had a cross-plan
# consistency pass yet.
#
# Format: <plan-name>\t<deps>\t<goal>
# Exit 0 if any found, 1 if none.
#
# Why this role exists: no role owns the contract BETWEEN plans. Every review
# is scoped to one plan, so two plans can each be correct alone and contradict
# each other — one program specified a forward-paging list API in PLN-003 while
# PLN-007 needed to page backward, and both reviews passed on the point. It was
# caught only because one attending agent happened to hold both plans in
# context, and the fix was possible only because the dependency was still
# unbuilt. Two plans faster and it would have been a shipped API and a
# migration.
#
# The done-marker is a `## Consistency` section in plan.md carrying a
# `> **Checked:**` line — committed with the plan, so it survives a restart and
# never re-runs on work that has not changed.

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
[ -f "$REGISTRY" ] || { echo "wf-list-consistency: $REGISTRY not found" >&2; exit 1; }

want="${1:-}"
want=$(printf '%s' "$want" | grep -oE 'PLN-[0-9]+' || true)

found=0

while IFS='|' read -r _ id slug state _priority _branch _updated _wf _tags deps _rest; do
  id=$(echo "$id" | xargs);   slug=$(echo "$slug" | xargs)
  state=$(echo "$state" | xargs); deps=$(echo "$deps" | xargs)

  [ "$state" = "ready" ] || continue
  [ -n "$want" ] && [ "$id" != "$want" ] && continue

  # No declared dependencies → nothing between-plan to check.
  case "$deps" in ""|"—"|"-") continue ;; esac

  plan_file="plans/${id}-${slug}/plan.md"
  [ -f "$plan_file" ] || continue

  # Already checked at its current revision.
  grep -q '^> \*\*Checked:\*\*' "$plan_file" 2>/dev/null && continue

  goal=$(grep -A 1 "^## Goal" "$plan_file" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)
  printf "%s\t%s\t%s\n" "${id}-${slug}" "$deps" "$goal"
  found=1
done < <(grep "^|" "$REGISTRY" | tail -n +3)

exit $((1 - found))

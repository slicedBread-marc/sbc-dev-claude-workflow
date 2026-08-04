#!/usr/bin/env bash
# wf-replan-target.sh <plan-id> [--apply]
#
# Resolves the state a replanned plan should return to, and optionally writes
# it.
#
#   no worktree  → ready     the builder runs Phase 1 and builds it fresh
#   live worktree → active   the builder resumes its FIX CYCLE
#
# WHY THIS IS NOT ALWAYS `ready`
#
# wf-implement's exit runs `wf-registry-update.sh <id> active verify`. That
# from_state guard is deliberate — it is what stops two workers racing the same
# row — but it means the state a replan lands in has to match the exit contract
# of the path the builder will actually take.
#
# A plan sent back to `draft` for a replan keeps its branch and worktree. The
# dispatcher already knows this: wf-list-implementable.sh reports ready+worktree
# as `resume`, not `new`. Writing `ready` anyway put the plan one state below
# where its own builder's exit expected it, so the exit silently no-opped: the
# work was done and committed, the registry still said `ready`, and wf-verify
# then refused to run because it could not match `verify` either. Nothing
# errored loudly; the plan simply stopped moving with completed work on the
# branch.
#
# stdout: the target state.  With --apply, also performs the transition.
# Exit 0 on success, 1 on error.

set -euo pipefail

# Registry work is develop-root work — see wf-registry-update.sh.
_wf_root=$(git worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //') || true
[ -n "$_wf_root" ] || _wf_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
cd "$_wf_root"

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
REGISTRY="plans/REGISTRY.md"

raw_id="${1:-}"
apply=false
[ "${2:-}" = "--apply" ] && apply=true

plan_id=$(printf '%s' "$raw_id" | grep -oE '^PLN-[0-9]+' || true)
[ -n "$plan_id" ] || { echo "Usage: $0 <PLN-NNN> [--apply]" >&2; exit 1; }
[ -f "$REGISTRY" ] || { echo "Error: $REGISTRY not found" >&2; exit 1; }

row=$(grep "^| $plan_id |" "$REGISTRY" | head -1 || true)
[ -n "$row" ] || { echo "Error: $plan_id has no registry row" >&2; exit 1; }

state=$(printf '%s' "$row" | awk -F'|' '{print $4}' | xargs)
branch=$(printf '%s' "$row" | awk -F'|' '{print $6}' | xargs)

target="ready"
if [ -n "$branch" ] && [ "$branch" != "—" ]; then
  if git worktree list --porcelain 2>/dev/null \
     | awk '/^branch /{ sub(/^branch refs\/heads\//, ""); print }' \
     | grep -qx "$branch"; then
    target="active"
  fi
fi

printf '%s\n' "$target"

if $apply; then
  if [ "$state" = "$target" ]; then
    echo "$plan_id is already $target — nothing to do" >&2
    exit 0
  fi
  "$SELF_DIR/wf-registry-update.sh" "$plan_id" "$state" "$target"
fi

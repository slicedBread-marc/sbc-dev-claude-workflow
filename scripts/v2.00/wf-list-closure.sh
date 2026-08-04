#!/usr/bin/env bash
# wf-list-closure.sh <plan-id> [--include-self]
#
# Prints the TRANSITIVE dependency closure of a plan, one `PLN-NNN <TAB> slug
# <TAB> state` row per line, in breadth-first order: the plans named in Deps,
# then the plans named in THEIR Deps, and so on.
#
# wf-consistency's whole job is defined over this set, and the set was
# previously assembled by hand from prose ("the plans named in Deps, and the
# plans named in their Deps"). Hand-walking a graph is fine at depth 2 and
# quietly wrong at depth 3.
#
# Cycles are tolerated — a plan already emitted is never emitted twice, so a
# mutual Deps pair terminates instead of looping.
#
# Exit 0 always; prints nothing when the plan has no deps.

set -euo pipefail

# Registry work is develop-root work — see wf-registry-update.sh.
_wf_root=$(git worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //') || true
[ -n "$_wf_root" ] || _wf_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
cd "$_wf_root"

REGISTRY="plans/REGISTRY.md"

raw_id="${1:-}"
include_self=false
[ "${2:-}" = "--include-self" ] && include_self=true

plan_id=$(printf '%s' "$raw_id" | grep -oE '^PLN-[0-9]+' || true)
[ -n "$plan_id" ] || { echo "Usage: $0 <PLN-NNN> [--include-self]" >&2; exit 1; }
[ -f "$REGISTRY" ] || exit 0

row_for() { grep "^| $1 |" "$REGISTRY" 2>/dev/null | head -1 || true; }
field()   { printf '%s' "$1" | awk -F'|' -v n="$2" '{print $n}' | xargs; }

seen=" $plan_id "
queue="$plan_id"
emitted=""

while [ -n "$queue" ]; do
  current="${queue%% *}"
  if [ "$current" = "$queue" ]; then queue=""; else queue="${queue#* }"; fi

  row=$(row_for "$current")
  [ -n "$row" ] || continue

  if [ "$current" != "$plan_id" ] || $include_self; then
    emitted="$emitted$current"$'\t'"$(field "$row" 3)"$'\t'"$(field "$row" 4)"$'\n'
  fi

  deps=$(field "$row" 10)
  [ -n "$deps" ] && [ "$deps" != "—" ] || continue

  IFS=',' read -ra dep_list <<< "$deps"
  for dep in "${dep_list[@]}"; do
    dep=$(printf '%s' "$dep" | xargs)
    dep=$(printf '%s' "$dep" | grep -oE '^PLN-[0-9]+' || true)
    [ -n "$dep" ] || continue
    case "$seen" in *" $dep "*) continue ;; esac
    seen="$seen$dep "
    queue="${queue:+$queue }$dep"
  done
done

printf '%s' "$emitted"

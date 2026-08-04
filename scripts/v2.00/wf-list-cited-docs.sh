#!/usr/bin/env bash
# wf-list-cited-docs.sh <plan-id>
#
# Prints the reference documents cited by the plans in a plan's dependency
# closure (the plan itself included), one row per document:
#
#   docs/plan/reference/07-remote-cli.md      PLN-009,PLN-004
#   docs/plan/reference/20-multi-instance.md  PLN-008
#
#   $1 path (repo-relative, verified to exist)   $2 the plans that cite it
#
# WHY THE CONSISTENCY PASS NEEDS THIS
#
# wf-consistency read the dependency closure and nothing else. Shared
# reference documentation is outside every closure, so a contradiction between
# two reference docs was invisible to the one role that exists to find
# cross-document contradictions.
#
# Observed: a review raised a Critical against a plan for getting a config
# schema wrong. It had not. One reference doc specified a flat top-level build
# block, another specified a per-instance block and cited the first for a claim
# the first does not make. Each plan had faithfully followed a different doc.
# Neither doc was reachable from the closure, so the pass could not have found
# it, and the per-plan reviewer misattributed it to the plan.
#
# A document cited by two or more plans in the same closure is where that class
# of defect lives, so those are listed first.
#
# Exit 0 always; prints nothing when no plan in the closure cites a document.

set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

# Registry work is develop-root work — see wf-registry-update.sh.
_wf_root=$(git worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //') || true
[ -n "$_wf_root" ] || _wf_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
cd "$_wf_root"

raw_id="${1:-}"
plan_id=$(printf '%s' "$raw_id" | grep -oE '^PLN-[0-9]+' || true)
[ -n "$plan_id" ] || { echo "Usage: $0 <PLN-NNN>" >&2; exit 1; }

pairs=$(mktemp)
trap 'rm -f "$pairs"' EXIT

while IFS=$'\t' read -r id slug _state; do
  [ -n "$id" ] || continue
  plan_file="plans/$id-$slug/plan.md"
  [ -f "$plan_file" ] || continue

  # Any repo-relative path ending in a documentation extension. Deliberately
  # loose on where the docs live (projects nest them differently) and strict on
  # the result: a path is only reported if the file is actually there, which
  # drops prose, globs, and paths belonging to another repo.
  # `|| true` is load-bearing under pipefail: a plan that cites nothing must
  # not abort the sweep over the rest of the closure.
  { grep -oE '[A-Za-z0-9_][A-Za-z0-9_./-]*\.(md|markdown|adoc|rst)' "$plan_file" 2>/dev/null || true; } \
  | sort -u \
  | while IFS= read -r path; do
      case "$path" in
        plans/*|bugs/*|*/plan.md|*/findings.md|*/progress.md) continue ;;
        WORKFLOW.md|README.md|CLAUDE.md|WORKFLOW-ISSUES.md) continue ;;
      esac
      [ -f "$path" ] || continue
      printf '%s\t%s\n' "$path" "$id" >> "$pairs"
    done
done < <("$SELF_DIR/wf-list-closure.sh" "$plan_id" --include-self)

[ -s "$pairs" ] || exit 0

# Collapse to one row per document, most-cited first — a doc cited by two
# plans in one closure is the pair worth reading against each other.
sort -u "$pairs" | awk -F'\t' '
  { if (!(($1) in cites)) { order[++n] = $1; count[$1] = 0 }
    cites[$1] = (count[$1]++ ? cites[$1] "," $2 : $2) }
  END {
    for (i = 1; i <= n; i++) { p = order[i]; printf "%d\t%s\t%s\n", count[p], p, cites[p] }
  }
' | sort -k1,1nr -k2,2 | cut -f2,3

#!/usr/bin/env bash
# wf-exec.sh <script-name> [args...]
#
# Dispatcher that resolves which versioned script folder to invoke based on
# (in priority order):
#   1. $WF_VERSION env override
#   2. WF column in plans/REGISTRY.md for the first PLN-looking arg
#   3. .claude/workflow-version (current workflow)
#
# The resolved workflow version is mapped to a script folder via
# scripts/version-map.txt — the highest row whose min_workflow_version
# is <= the effective version wins. Missing/empty version is treated as 0.00.
#
# This dispatcher is unversioned; it lives at scripts/wf-exec.sh on every
# client. Changing it is a coordinated breaking change.

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <script-name> [args...]" >&2
  exit 1
fi

script_name="$1"
shift

# ── Locate the project root ──────────────────────────────────────────────
# The MAIN worktree first, then a walk up from CWD.
#
# Walking up from CWD alone is wrong inside a feature worktree. plans/, the
# registry and the deployed script snapshots all live on develop, and a
# worktree that picked up a partial `scripts/` from an interrupted deploy
# answers the walk with itself — at which point `.claude/workflow-version` is
# sparse-excluded there, the effective version reads as unstamped, and every
# call routes to the v1.x baseline folder that no longer exists on disk.
find_project_root() {
  local main
  main=$(git worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //')
  if [ -n "$main" ] && [ -f "$main/scripts/version-map.txt" ]; then
    printf '%s' "$main"; return 0
  fi
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/scripts/version-map.txt" ]; then printf '%s' "$dir"; return 0; fi
    dir="$(dirname "$dir")"
  done
  return 1
}

ROOT="$(find_project_root)" || { echo "wf-exec.sh: cannot locate scripts/version-map.txt (run from within a project)" >&2; exit 1; }

# ── Resolve effective workflow version ───────────────────────────────────
# A version is dotted digits and nothing else. This matters: `sort -V` places
# any non-numeric string ABOVE every numeric version, so an unstamped marker
# like the registry's em-dash would satisfy EVERY row in version-map.txt and
# resolve to the newest script folder — the precise opposite of what the WF
# column exists to guarantee. Such a value is treated as "not stamped".
is_version() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)*$ ]]; }

effective=""

if [ -n "${WF_VERSION:-}" ]; then
  # An explicit override is human input, so a typo fails loudly rather than
  # silently routing somewhere surprising.
  if ! is_version "$WF_VERSION"; then
    echo "wf-exec.sh: WF_VERSION='$WF_VERSION' is not a version (expected digits and dots, e.g. 2.5.1)" >&2
    exit 1
  fi
  effective="$WF_VERSION"
elif [ $# -ge 1 ] && [[ "$1" =~ ^PLN-[0-9]+ ]]; then
  # Extract bare PLN-NNN from the arg (handles both PLN-041 and PLN-041-slug forms)
  plan_id=$(echo "$1" | grep -oE '^PLN-[0-9]+')
  if [ -f "$ROOT/plans/REGISTRY.md" ]; then
    # Row format: | PLN-NNN | slug | state | priority | branch | updated | WF |
    # awk -F'|' fields:  $2    $3      $4       $5       $6       $7     $8
    row=$(grep "^| ${plan_id} " "$ROOT/plans/REGISTRY.md" | head -1 || true)
    if [ -n "$row" ]; then
      effective=$(echo "$row" | awk -F'|' '{print $8}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      # "—", "?", "n/a" and friends all mean the same thing as blank: this plan
      # was never stamped. Fall through to the project's current version.
      is_version "$effective" || effective=""
    fi
  fi
fi

if [ -z "$effective" ] && [ -f "$ROOT/.claude/workflow-version" ]; then
  effective=$(tr -d '[:space:]' < "$ROOT/.claude/workflow-version")
  if [ -n "$effective" ] && ! is_version "$effective"; then
    echo "wf-exec.sh: .claude/workflow-version contains '$effective', not a version — using baseline" >&2
    effective=""
  fi
fi

[ -z "$effective" ] && effective="0.00"

# ── Resolve script folder via version-map.txt ────────────────────────────
# Pick the highest min_workflow_version that is <= effective.
# Version comparison: use sort -V (natural version sort).
map="$ROOT/scripts/version-map.txt"
[ -f "$map" ] || { echo "wf-exec.sh: missing $map" >&2; exit 1; }

script_folder=""
while IFS= read -r line; do
  # Skip blanks and comments
  line="${line%%#*}"
  [ -z "${line// }" ] && continue
  min_ver=$(echo "$line" | awk '{print $1}')
  folder=$(echo "$line" | awk '{print $2}')
  [ -z "$min_ver" ] || [ -z "$folder" ] && continue
  # If min_ver <= effective, this row is a candidate (rows are ascending,
  # so the last candidate wins).
  if [ "$(printf '%s\n%s\n' "$min_ver" "$effective" | sort -V | head -1)" = "$min_ver" ]; then
    script_folder="$folder"
  fi
done < "$map"

if [ -z "$script_folder" ]; then
  echo "wf-exec.sh: no script folder maps to workflow version '$effective' (check $map)" >&2
  exit 1
fi

target="$ROOT/scripts/$script_folder/$script_name"
if [ ! -x "$target" ]; then
  echo "wf-exec.sh: $target is missing or not executable — run deploy-all.sh to reinstall" >&2
  exit 1
fi

exec "$target" "$@"

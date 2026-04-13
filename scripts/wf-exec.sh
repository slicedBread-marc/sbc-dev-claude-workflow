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

# ── Locate the project root (walk up from CWD) ───────────────────────────
find_project_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/scripts/version-map.txt" ]; then printf '%s' "$dir"; return 0; fi
    dir="$(dirname "$dir")"
  done
  return 1
}

ROOT="$(find_project_root)" || { echo "wf-exec.sh: cannot locate scripts/version-map.txt (run from within a project)" >&2; exit 1; }

# ── Resolve effective workflow version ───────────────────────────────────
effective=""

if [ -n "${WF_VERSION:-}" ]; then
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
    fi
  fi
fi

if [ -z "$effective" ] && [ -f "$ROOT/.claude/workflow-version" ]; then
  effective=$(tr -d '[:space:]' < "$ROOT/.claude/workflow-version")
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

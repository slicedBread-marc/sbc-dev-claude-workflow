#!/usr/bin/env bash
# wf-prune-versions.sh [--dry-run | --list]
#
# Manages the scripts/v*/ snapshots deployed in this project.
#
# Modes:
#   --list      Print status only: current workflow version, current folder,
#               and which snapshot folders are still referenced by non-complete
#               plans. Read-only; safe to run from any skill.
#   --dry-run   Enumerate folders that would be removed (in-use = retained);
#               no changes written.
#   (default)   Dry-run preview, then prompt before deleting.
#
# In-use set:
#   1. For each non-complete plan in plans/REGISTRY.md, resolve its WF stamp
#      to a script_folder via scripts/version-map.txt (same algorithm as
#      scripts/wf-exec.sh). Empty WF → v1.x (legacy baseline).
#   2. Resolve .claude/workflow-version → its script_folder ("current").
#   3. Always retain v1.x (baseline floor for legacy sbc plans).
#
# Unversioned — safe to run under any workflow version.

set -euo pipefail

MODE="${1:-prune}"
case "$MODE" in
  --list|--dry-run|prune) ;;
  *) echo "Usage: $0 [--dry-run | --list]" >&2; exit 1 ;;
esac

# ── Locate the project root ─────────────────────────────────────────────
find_project_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/scripts/version-map.txt" ]; then printf '%s' "$dir"; return 0; fi
    dir="$(dirname "$dir")"
  done
  return 1
}

ROOT="$(find_project_root)" || { echo "wf-prune-versions.sh: cannot locate scripts/version-map.txt" >&2; exit 1; }
MAP="$ROOT/scripts/version-map.txt"
REGISTRY="$ROOT/plans/REGISTRY.md"
WF_FILE="$ROOT/.claude/workflow-version"

# ── Resolve a workflow version → script folder (highest min ≤ version). ──
resolve_folder() {
  local wf="$1"
  [ -z "$wf" ] && wf="0.00"
  local folder=""
  while IFS= read -r line; do
    line="${line%%#*}"
    [ -z "${line// }" ] && continue
    local min_ver f
    min_ver=$(echo "$line" | awk '{print $1}')
    f=$(echo "$line" | awk '{print $2}')
    [ -z "$min_ver" ] || [ -z "$f" ] && continue
    if [ "$(printf '%s\n%s\n' "$min_ver" "$wf" | sort -V | head -1)" = "$min_ver" ]; then
      folder="$f"
    fi
  done < "$MAP"
  echo "$folder"
}

# ── Current workflow version + folder ───────────────────────────────────
current_wf=""
[ -f "$WF_FILE" ] && current_wf=$(tr -d '[:space:]' < "$WF_FILE")
current_folder=$(resolve_folder "$current_wf")

# ── Build in-use set from non-complete REGISTRY rows ────────────────────
declare -a in_use
in_use=("v1.x")  # always retain baseline
[ -n "$current_folder" ] && in_use+=("$current_folder")

if [ -f "$REGISTRY" ]; then
  while IFS='|' read -r _ id slug state priority branch updated wf _rest; do
    state=$(echo "$state" | xargs)
    wf=$(echo "$wf" | xargs)
    [ -z "$state" ] && continue
    [ "$state" = "complete" ] && continue
    [[ "$id" == *"ID"* ]] && continue  # header row
    folder=$(resolve_folder "$wf")
    [ -n "$folder" ] && in_use+=("$folder")
  done < <(grep "^| PLN-" "$REGISTRY" 2>/dev/null || true)
fi

# Dedupe in-use.
unique_in_use=()
for f in "${in_use[@]}"; do
  found=0
  for u in "${unique_in_use[@]+"${unique_in_use[@]}"}"; do
    [ "$u" = "$f" ] && found=1 && break
  done
  [ "$found" -eq 0 ] && unique_in_use+=("$f")
done

# ── Enumerate folders on disk ───────────────────────────────────────────
on_disk=()
for d in "$ROOT/scripts"/v*/; do
  [ -d "$d" ] || continue
  on_disk+=("$(basename "$d")")
done

# ── --list mode: print state and exit ───────────────────────────────────
if [ "$MODE" = "--list" ]; then
  echo "Workflow version: ${current_wf:-<unset>}"
  echo "Current script folder: ${current_folder:-<none>}"
  echo "Folders on disk:       ${on_disk[*]:-<none>}"
  echo "Folders in use:        ${unique_in_use[*]}"
  exit 0
fi

# ── Compute removable set ───────────────────────────────────────────────
removable=()
for f in "${on_disk[@]}"; do
  keep=0
  for u in "${unique_in_use[@]}"; do
    [ "$u" = "$f" ] && keep=1 && break
  done
  [ "$keep" -eq 0 ] && removable+=("$f")
done

if [ "${#removable[@]}" -eq 0 ]; then
  echo "Nothing to prune. All ${#on_disk[@]} folder(s) on disk are in use or retained."
  exit 0
fi

echo "Script folders on disk: ${on_disk[*]}"
echo "In use (retained):      ${unique_in_use[*]}"
echo "Removable:              ${removable[*]}"

if [ "$MODE" = "--dry-run" ]; then
  echo "(dry-run — no changes written)"
  exit 0
fi

printf "Remove %d folder(s) listed above? [y/N] " "${#removable[@]}"
read -r ans
case "$ans" in
  y|Y|yes|YES)
    for f in "${removable[@]}"; do
      rm -rf "$ROOT/scripts/$f"
      echo "  removed scripts/$f"
    done
    echo "Done."
    ;;
  *)
    echo "Aborted."
    exit 0
    ;;
esac

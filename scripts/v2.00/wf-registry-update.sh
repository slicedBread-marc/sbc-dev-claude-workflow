#!/usr/bin/env bash
# wf-registry-update.sh <plan-id> <from-state> <to-state> [branch] [--commit "msg" [--add file ...]]
# Updates a plan's state in REGISTRY.md and sets the date to today.
# If branch is provided, updates the Branch column too.
# If branch is "-", clears the Branch column to "—".
#
# --commit "msg"   Atomically: update → git add → git commit, all under the lock.
# --add file ...   Extra files to stage (in addition to REGISTRY.md). Only with --commit.
#
# The `registry` lock is held for the whole run, not just for --commit — any
# read-modify-write of REGISTRY.md races once more than one worker is live.
#
# Examples:
#   wf-registry-update.sh PLN-004 ready active feature/PLN-004-slug
#   wf-registry-update.sh PLN-004 active verify
#   wf-registry-update.sh PLN-004 testing complete -
#   wf-registry-update.sh PLN-004 verify testing --commit "verify(PLN-004): clean"
#   wf-registry-update.sh PLN-004 verify active --commit "verify(PLN-004): findings" --add plans/PLN-004-slug/findings.md
#
# Exit 0 on success, 1 on error.

set -euo pipefail

# shellcheck source=wf-lock.sh
source "$(dirname "$0")/wf-lock.sh"

REGISTRY="plans/REGISTRY.md"

# --- Parse arguments ---
raw_id="${1:-}"
from_state="${2:-}"
to_state="${3:-}"
shift 3 2>/dev/null || true

branch=""
commit_msg=""
add_files=()

# Fourth positional arg is branch if it doesn't start with --
if [ "${1:-}" != "" ] && [[ "${1:-}" != --* ]]; then
  branch="$1"
  shift
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --commit)
      commit_msg="${2:?--commit requires a message}"
      shift 2
      ;;
    --add)
      shift
      while [ $# -gt 0 ] && [[ "$1" != --* ]]; do
        add_files+=("$1")
        shift
      done
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Normalize: accept both "PLN-NNN" and "PLN-NNN-slug" formats
plan_id=$(echo "$raw_id" | grep -oE '^PLN-[0-9]+' || echo "$raw_id")

if [ -z "$plan_id" ] || [ -z "$from_state" ] || [ -z "$to_state" ]; then
  echo "Usage: $0 <plan-id> <from-state> <to-state> [branch] [--commit \"msg\" [--add file ...]]" >&2
  exit 1
fi

[ -f "$REGISTRY" ] || { echo "Error: $REGISTRY not found" >&2; exit 1; }

today=$(date +%Y-%m-%d)

# --- Everything below mutates the registry: take the lock first ---
wf_lock_acquire registry

# Verify the plan exists in the expected state
if ! grep -q "^| $plan_id |.*| $from_state |" "$REGISTRY"; then
  echo "Error: $plan_id not found in state '$from_state'" >&2
  exit 1
fi

# Rewrite the row by column index rather than by regex surgery.
#   | ID | Slug | State | Priority | Branch | Updated | WF | Tags | Deps |
#     $2    $3     $4       $5        $6       $7      $8    $9    $10
# awk into a tempfile — `sed -i ''` is macOS-only and breaks anywhere else.
awk -F'|' -v OFS='|' \
    -v id="$plan_id" -v to="$to_state" -v br="$branch" -v today="$today" '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  trim($2) == id {
    $4 = " " to " "
    if (br == "-")      $6 = " — "
    else if (br != "")  $6 = " " br " "
    $7 = " " today " "
  }
  { print }
' "$REGISTRY" > "$REGISTRY.tmp" && mv "$REGISTRY.tmp" "$REGISTRY"

# Verify the update worked
if grep -q "^| $plan_id |.*| $to_state |" "$REGISTRY"; then
  echo "$plan_id: $from_state → $to_state"
else
  echo "Error: update failed for $plan_id" >&2
  exit 1
fi

# Auto-claim when entering active state
if [ "$to_state" = "active" ]; then
  slug=$(grep "^| $plan_id |" "$REGISTRY" | head -1 | awk -F'|' '{print $3}' | xargs)
  claim_dir="plans/${plan_id}-${slug}"
  if [ -d "$claim_dir" ]; then
    _pid=$PPID
    for _i in 1 2 3 4 5; do
      _name=$(ps -o comm= -p "$_pid" 2>/dev/null)
      case "$_name" in bash|sh|zsh|dash) _pid=$(ps -o ppid= -p "$_pid" 2>/dev/null | tr -d ' ') ;; *) break ;; esac
    done
    printf '%s\n%s\n' "$(date +%s)" "$_pid" > "$claim_dir/.wf-claim"
  fi
fi

# --- Atomic commit (still under the lock) ---
if [ -n "$commit_msg" ]; then
  for f in "${add_files[@]+"${add_files[@]}"}"; do
    git add "$f"
  done
  git commit --allow-empty -m "$commit_msg"
fi

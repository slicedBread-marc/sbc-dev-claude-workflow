#!/usr/bin/env bash
# wf-registry-update.sh <plan-id> <from-state> <to-state> [branch] [--commit "msg" [--add file ...]]
# Updates a plan's state in REGISTRY.md and sets the date to today.
# If branch is provided, updates the Branch column too.
# If branch is "-", clears the Branch column to "—".
#
# --commit "msg"   Atomically: acquire lock → update → git add → git commit → release lock.
# --add file ...   Extra files to stage (in addition to REGISTRY.md). Only with --commit.
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

REGISTRY="plans/REGISTRY.md"
LOCKDIR="${TMPDIR:-/tmp}/wf-registry.lock"
LOCK_TIMEOUT=30

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

# --- Lockfile helpers (mkdir is atomic on POSIX) ---
acquire_lock() {
  local elapsed=0
  while ! mkdir "$LOCKDIR" 2>/dev/null; do
    # Check for stale lock (older than 60s)
    if [ -f "$LOCKDIR/pid" ]; then
      local lock_pid
      lock_pid=$(cat "$LOCKDIR/pid" 2>/dev/null || echo "")
      if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
        echo "registry-lock: removing stale lock (PID $lock_pid dead)" >&2
        rm -rf "$LOCKDIR"
        continue
      fi
    fi
    if [ "$elapsed" -ge "$LOCK_TIMEOUT" ]; then
      echo "Error: could not acquire registry lock after ${LOCK_TIMEOUT}s" >&2
      exit 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  echo $$ > "$LOCKDIR/pid"
  trap release_lock EXIT
}

release_lock() {
  rm -rf "$LOCKDIR"
}

# --- Main ---
if [ -n "$commit_msg" ]; then
  acquire_lock
fi

# Verify the plan exists in the expected state
if ! grep -q "| $plan_id |.*| $from_state |" "$REGISTRY"; then
  echo "Error: $plan_id not found in state '$from_state'" >&2
  exit 1
fi

if [ -n "$branch" ]; then
  if [ "$branch" = "-" ]; then
    # Clear branch to em-dash — use # delimiter to avoid / in plan_id
    sed -i '' "/$plan_id/s#| $from_state |[^|]*|[^|]*|#| $to_state | — | $today |#" "$REGISTRY"
  else
    # Use # delimiter — branch contains / (e.g. feature/PLN-001-slug)
    sed -i '' "/$plan_id/s#| $from_state |[^|]*|[^|]*|#| $to_state | $branch | $today |#" "$REGISTRY"
  fi
else
  # Update state and date only, preserve branch column — use # delimiter
  sed -i '' "/$plan_id/s#| $from_state |\([^|]*\)|[^|]*|#| $to_state |\1| $today |#" "$REGISTRY"
fi

# Verify the update worked
if grep -q "| $plan_id |.*| $to_state |" "$REGISTRY"; then
  echo "$plan_id: $from_state → $to_state"
else
  echo "Error: update failed for $plan_id" >&2
  exit 1
fi

# --- Atomic commit (under lock) ---
if [ -n "$commit_msg" ]; then
  git add "$REGISTRY"
  for f in "${add_files[@]+"${add_files[@]}"}"; do
    git add "$f"
  done
  git commit -m "$commit_msg"
fi

#!/usr/bin/env bash
# wf-set-tags.sh <plan-id> <tags>
# Sets the Tags column (9th) for a plan in REGISTRY.md.
# Tags are comma-separated, no spaces. Use "—" to clear.
#
# The vocabulary is the project's own — whatever plans already carry, plus
# anything declared in claude-workflow.yml (`tags:`, `specApproval.gateTags`).
# See wf-list-tags.sh. A name outside it is a WARNING, not an error: this
# script used to hardcode `security arcade admin lessons ux infra e2e bugfix`
# and reject everything else, so a project whose gating tag was `contract`
# could not assign the one tag that gates. Refusing an unknown tag makes the
# first legitimate use of any new name impossible, which is a worse failure
# than a typo that shows up in `wf-list-tags.sh` with a count of 1.
#
# Examples:
#   wf-set-tags.sh PLN-004 security
#   wf-set-tags.sh PLN-004 security,admin
#   wf-set-tags.sh PLN-004 —

set -euo pipefail

# shellcheck source=wf-lock.sh
source "$(dirname "$0")/wf-lock.sh"

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
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

raw_id="${1:-}"
tags="${2:-}"

plan_id=$(echo "$raw_id" | grep -oE '^PLN-[0-9]+' || echo "$raw_id")

if [ -z "$plan_id" ] || [ -z "$tags" ]; then
  echo "Usage: $0 <plan-id> <tags>" >&2
  exit 1
fi

[ -f "$REGISTRY" ] || { echo "Error: $REGISTRY not found" >&2; exit 1; }

# Normalize: strip all whitespace so the registry never holds "a, b" (comma-space).
if [ "$tags" != "—" ]; then
  tags=$(printf '%s' "$tags" | tr -d '[:space:]')
fi

if ! grep -q "^| $plan_id |" "$REGISTRY"; then
  echo "Error: $plan_id not found in registry" >&2
  exit 1
fi

# Flag names outside the project's vocabulary — before taking the lock, since
# wf-list-tags.sh reads the registry too.
if [ "$tags" != "—" ]; then
  known=$("$SELF_DIR/wf-list-tags.sh" 2>/dev/null | cut -f1 || true)
  unknown=""
  IFS=',' read -ra tag_list <<< "$tags"
  for tag in "${tag_list[@]}"; do
    tag=$(echo "$tag" | xargs)
    [ -n "$tag" ] || continue
    printf '%s\n' "$known" | grep -qx "$tag" || unknown="$unknown $tag"
  done
  if [ -n "$unknown" ]; then
    echo "Note: new tag(s) for this project:$unknown" >&2
    if [ -n "$known" ]; then
      echo "      In use: $(printf '%s\n' "$known" | paste -sd, - | sed 's/,/, /g')" >&2
    fi
    echo "      Assigned anyway. Check it is not a typo — a misspelt tag that" >&2
    echo "      should have matched specApproval.gateTags silently skips a gate." >&2
  fi
fi

# Read-modify-write from here down.
wf_lock_acquire registry

# The row has 9 pipes (10 fields including leading empty).
# We need to replace field 9 (Tags). If the row only has 8 fields (v4 format),
# we need to append the Tags and Deps columns.
row=$(grep "^| $plan_id |" "$REGISTRY" | head -1)
pipe_count=$(echo "$row" | tr -cd '|' | wc -c | xargs)

if [ "$pipe_count" -lt 10 ]; then
  # v4 row — append Tags and Deps columns
  # Current: | ... | WF |  →  | ... | WF | Tags | Deps |
  awk -F'|' -v id="$plan_id" -v tags="$tags" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    trim($2) == id { sub(/[ \t]*$/, "", $0); print $0 " " tags " | — |"; next }
    { print }
  ' "$REGISTRY" > "$REGISTRY.tmp" && mv "$REGISTRY.tmp" "$REGISTRY"
else
  # v5 row — update the Tags column ($9) in place.
  # Exact ID match: `$2 ~ id` also matches PLN-041 when asked for PLN-04.
  awk -F'|' -v OFS='|' -v id="$plan_id" -v newtags=" $tags " '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    trim($2) == id { $9 = newtags }
    { print }
  ' "$REGISTRY" > "$REGISTRY.tmp" && mv "$REGISTRY.tmp" "$REGISTRY"
fi

echo "$plan_id: tags → $tags"

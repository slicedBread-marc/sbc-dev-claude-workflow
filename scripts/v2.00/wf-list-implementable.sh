#!/usr/bin/env bash
# wf-list-implementable.sh
# Outputs plans available for /wf-implement by reading REGISTRY.md.
#
# Format per line: <type>\t<plan-name>\t<goal>\t<priority>
#   type = "new"        — state: ready, no existing worktree
#   type = "resume"     — has a worktree (state active, or ready after a
#                         replan), no unchecked findings
#   type = "fix"        — has a worktree, has unchecked findings
#   type = "processing" — state: active, claimed by another session (< 2h old claim file)
#   type = "blocked"    — deps not all complete (appends blocking plan IDs)
#   priority = "urgent" or "—" (normal)
#
# Urgent items are output first. Exit 0 if any found, exit 1 if none.

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
found=0

# Branches that already have a worktree checked out. Read once — `git worktree
# list` is cheap but this loop runs per plan.
existing_worktrees=$(git worktree list --porcelain 2>/dev/null \
  | awk '/^branch /{ sub(/^branch refs\/heads\//, ""); print }' || true)

has_worktree() {
  [ -n "$1" ] && [ "$1" != "—" ] || return 1
  printf '%s\n' "$existing_worktrees" | grep -qx "$1"
}

urgent_lines=()
normal_lines=()
processing_lines=()
blocked_lines=()

# Helper: check if a plan's deps are all complete
check_deps_blocked() {
  local deps_raw="$1"
  [ -n "$deps_raw" ] && [ "$deps_raw" != "—" ] || return 1
  local blocking=""
  local IFS=','
  for dep_id in $deps_raw; do
    dep_id=$(echo "$dep_id" | xargs)
    local dep_state
    dep_state=$(grep "^| $dep_id |" "$REGISTRY" 2>/dev/null | awk -F'|' '{print $4}' | xargs || true)
    if [ "$dep_state" != "complete" ]; then
      [ -n "$blocking" ] && blocking="$blocking,$dep_id" || blocking="$dep_id"
    fi
  done
  [ -n "$blocking" ] || return 1
  echo "$blocking"
  return 0
}

while IFS='|' read -r _ id slug state priority branch _rest; do
  id=$(echo "$id" | xargs)
  slug=$(echo "$slug" | xargs)
  state=$(echo "$state" | xargs)
  priority=$(echo "$priority" | xargs)
  branch=$(echo "$branch" | xargs)

  # Skip malformed or blank lines
  [ -n "$id" ] && [ -n "$state" ] || continue
  plan_dir="plans/${id}-${slug}"

  [ "$state" = "ready" ] || [ "$state" = "active" ] || continue
  [ -d "$plan_dir" ] || continue

  goal=$(grep -A 1 "^## Goal" "$plan_dir/plan.md" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)
  plan_name="${id}-${slug}"

  # Check deps (field 10 in the original row)
  row_full=$(grep "^| $id |" "$REGISTRY" | head -1)
  deps_raw=$(echo "$row_full" | awk -F'|' '{print $10}' | xargs)
  blocking=$(check_deps_blocked "$deps_raw" 2>/dev/null) && {
    blocked_lines+=("$(printf "blocked\t%s\t%s\t%s\t%s" "$plan_name" "$goal" "$priority" "$blocking")")
    found=1
    continue
  }

  # `new` is defined as "ready AND no existing worktree", but the type used to
  # be read off the state alone. A plan sent back to `ready` for a replan keeps
  # its branch and worktree, so it came back as `new` — and the implementer,
  # following the type, would try to create a branch and worktree that already
  # exist. Anything with a live worktree is a resume or a fix, whatever the
  # registry says.
  effective_state="$state"
  if [ "$state" = "ready" ] && has_worktree "$branch"; then
    effective_state="active"
  fi

  if [ "$effective_state" = "ready" ]; then
    line=$(printf "new\t%s\t%s\t%s" "$plan_name" "$goal" "$priority")
    if [ "$priority" = "urgent" ]; then urgent_lines+=("$line"); else normal_lines+=("$line"); fi
    found=1
  elif [ "$effective_state" = "active" ]; then
    claimfile="$plan_dir/.wf-claim"
    claimed=0
    now=$(date +%s)
    if [ -f "$claimfile" ]; then
      claim_ts=$(sed -n '1p' "$claimfile" 2>/dev/null)
      claim_pid=$(sed -n '2p' "$claimfile" 2>/dev/null)
      age=$(( now - claim_ts ))
      if [ -n "$claim_pid" ]; then
        kill -0 "$claim_pid" 2>/dev/null && [ "$age" -lt 7200 ] && claimed=1
      else
        [ "$age" -lt 7200 ] && claimed=1
      fi
      [ "$claimed" -eq 0 ] && rm -f "$claimfile"
    fi
    if [ "$claimed" -eq 1 ]; then
      claim_age_min=$(( age / 60 ))
      processing_lines+=("$(printf "processing\t%s\t%s\t%s\t%s" "$plan_name" "$goal" "$priority" "${claim_age_min}m ago")")
      found=1
      continue
    fi
    findings="$plan_dir/findings.md"
    if [ -f "$findings" ] && grep -q "^\- \[ \]" "$findings" 2>/dev/null; then
      line=$(printf "fix\t%s\t%s\t%s" "$plan_name" "$goal" "$priority")
    else
      line=$(printf "resume\t%s\t%s\t%s" "$plan_name" "$goal" "$priority")
    fi
    if [ "$priority" = "urgent" ]; then urgent_lines+=("$line"); else normal_lines+=("$line"); fi
    found=1
  fi
done < <(grep "^|" "$REGISTRY" | tail -n +3)

# Output urgent items first, then normal, then processing, then blocked
for line in "${urgent_lines[@]+"${urgent_lines[@]}"}"; do printf "%s\n" "$line"; done
for line in "${normal_lines[@]+"${normal_lines[@]}"}"; do printf "%s\n" "$line"; done
for line in "${processing_lines[@]+"${processing_lines[@]}"}"; do printf "%s\n" "$line"; done
for line in "${blocked_lines[@]+"${blocked_lines[@]}"}"; do printf "%s\n" "$line"; done

exit $((1 - found))

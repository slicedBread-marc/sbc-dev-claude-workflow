#!/usr/bin/env bash
# wf-list-implementable.sh
# Outputs plans available for /wf-implement by reading REGISTRY.md.
#
# Format per line: <type>\t<plan-name>\t<goal>\t<priority>
#   type = "new"        — state: ready, no existing worktree
#   type = "resume"     — state: active, no unchecked findings
#   type = "fix"        — state: active, has unchecked findings
#   type = "processing" — state: active, claimed by another session (< 2h old claim file)
#   priority = "urgent" or "—" (normal)
#
# Urgent items are output first. Exit 0 if any found, exit 1 if none.

set -euo pipefail

REGISTRY="plans/REGISTRY.md"
found=0

urgent_lines=()
normal_lines=()
processing_lines=()

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

  if [ "$state" = "ready" ]; then
    line=$(printf "new\t%s\t%s\t%s" "$plan_name" "$goal" "$priority")
    if [ "$priority" = "urgent" ]; then urgent_lines+=("$line"); else normal_lines+=("$line"); fi
    found=1
  elif [ "$state" = "active" ]; then
    claimfile="$plan_dir/.wf-claim"
    claimed=0
    now=$(date +%s)
    if [ -f "$claimfile" ]; then
      claim_ts=$(cat "$claimfile" 2>/dev/null)
      age=$(( now - claim_ts ))
      if [ "$age" -lt 7200 ]; then
        claimed=1
      else
        # Stale claim — clean it up
        rm -f "$claimfile"
      fi
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

# Output urgent items first, then normal, then processing
for line in "${urgent_lines[@]+"${urgent_lines[@]}"}"; do printf "%s\n" "$line"; done
for line in "${normal_lines[@]+"${normal_lines[@]}"}"; do printf "%s\n" "$line"; done
for line in "${processing_lines[@]+"${processing_lines[@]}"}"; do printf "%s\n" "$line"; done

exit $((1 - found))

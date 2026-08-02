#!/usr/bin/env bash
# wf-list-specable.sh
# Outputs work available for /wf-spec, in priority order.
# Reads REGISTRY.md for plans in draft state, plus bugs/open and briefs.
# Exit 0 if any work found, exit 1 if nothing.

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

# --- Escalated plans in draft state (highest priority) ---
escalated=()
while IFS='|' read -r _ id slug state priority _rest; do
  id=$(echo "$id" | xargs)
  slug=$(echo "$slug" | xargs)
  state=$(echo "$state" | xargs)
  priority=$(echo "$priority" | xargs)
  [ "$state" = "draft" ] || continue
  plan_dir="plans/${id}-${slug}"
  [ -d "$plan_dir" ] || continue

  # Check for active claim (PID alive, or TTL fallback for old format)
  claimfile="$plan_dir/.wf-claim"
  if [ -f "$claimfile" ]; then
    claim_ts=$(sed -n '1p' "$claimfile" 2>/dev/null)
    claim_pid=$(sed -n '2p' "$claimfile" 2>/dev/null)
    now=$(date +%s)
    age=$(( now - claim_ts ))
    if [ -n "$claim_pid" ]; then
      kill -0 "$claim_pid" 2>/dev/null && [ "$age" -lt 7200 ] && continue
    else
      [ "$age" -lt 7200 ] && continue
    fi
  fi

  findings="$plan_dir/findings.md"
  if [ -f "$findings" ] && grep -q '^\- \[ \]' "$findings" 2>/dev/null; then
    esc_count=$(grep -c "ESCALATED" "$findings" 2>/dev/null || true)
    bhv_count=$(grep -c "Behavior" "$findings" 2>/dev/null || true)
    parts=()
    [ "$esc_count" -gt 0 ] && parts+=("$esc_count escalated")
    [ "$bhv_count" -gt 0 ] && parts+=("$bhv_count behavior")
    if [ ${#parts[@]} -gt 0 ]; then
      detail=$(IFS=', '; echo "${parts[*]}")
      escalated+=("${id}-${slug}	${detail} finding(s)	$priority")
      found=1
    fi
  fi
done < <(grep "^|" "$REGISTRY" | tail -n +3)

if [ ${#escalated[@]} -gt 0 ]; then
  echo "# replanning"
  for entry in "${escalated[@]}"; do
    printf "%s\n" "$entry"
  done
fi

# --- Open bugs ---
bugs_found=0
for bug_md in bugs/open/*/bug.md; do
  [ -f "$bug_md" ] || continue
  bug_id=$(grep -oE 'BUG-[0-9]+' "$bug_md" 2>/dev/null | head -1)
  severity=$(grep -E "Severity:" "$bug_md" 2>/dev/null | head -1 | sed 's/.*Severity:\*\*[[:space:]]*//' | sed 's/^> //')
  title=$(head -1 "$bug_md" | sed 's/^# //')
  [ -n "$bug_id" ] || continue
  if [ $bugs_found -eq 0 ]; then echo "# bugs"; fi
  printf "%s\t%s\t%s\n" "$bug_id" "$severity" "$title"
  bugs_found=1
  found=1
done

# --- Decided briefs ---
briefs_found=0
if [ -f "plans/briefs/INDEX.md" ]; then
  in_decided=0
  while IFS= read -r line; do
    if echo "$line" | grep -q "^## Decided"; then
      in_decided=1; continue
    fi
    if echo "$line" | grep -q "^## "; then
      in_decided=0; continue
    fi
    if [ $in_decided -eq 1 ] && echo "$line" | grep -q "^\- \["; then
      name=$(echo "$line" | sed 's/^\- \[//' | sed 's/\].*//')
      link=$(echo "$line" | grep -oE '\([^)]+\)' | head -1 | tr -d '()')
      brief_id=$(echo "$link" | grep -oE 'BRF-[0-9]+' | head -1)
      [ -n "$brief_id" ] || brief_id="—"
      desc=$(echo "$line" | sed 's/^[^—]*— //')
      if [ $briefs_found -eq 0 ]; then echo "# briefs"; fi
      printf "%s\t%s\t%s\n" "$brief_id" "$name" "$desc"
      briefs_found=1
      found=1
    fi
  done < "plans/briefs/INDEX.md"
fi

exit $((1 - found))

#!/usr/bin/env bash
# wf-list-specable.sh
# Outputs work available for /wf-spec, in priority order.
# Sections are separated by header lines starting with '#'.
# Exit 0 if any work found, exit 1 if nothing at all.

set -euo pipefail

found=0

# --- Escalated plans (highest priority) ---
escalated=()

for plan in plans/replanning/*/plan.md; do
  [ -f "$plan" ] || continue
  plan_name=$(basename "$(dirname "$plan")")
  count=$(grep -c "| Escalated |" "$plan" 2>/dev/null || true)
  escalated+=("develop	$plan_name	$count escalated finding(s)")
  found=1
done

for plan in feature-branches/PLN-*/plans/replanning/*/plan.md; do
  [ -f "$plan" ] || continue
  plan_name=$(basename "$(dirname "$plan")")
  worktree=$(echo "$plan" | cut -d/ -f2)
  findings="$(dirname "$plan")/findings.md"
  count=$(grep -c "| Escalated |" "$findings" 2>/dev/null || true)
  escalated+=("worktree:$worktree	$plan_name	$count escalated finding(s)")
  found=1
done

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
  bug_id=$(grep "^\*\*ID:\*\*\|^> \*\*ID:\*\*" "$bug_md" 2>/dev/null | head -1 | grep -o 'BUG-[0-9]*')
  severity=$(grep "^\*\*Severity:\*\*\|^> \*\*Severity:\*\*" "$bug_md" 2>/dev/null | head -1 | sed 's/.*Severity:\*\*[[:space:]]*//' | sed 's/^> //')
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
      in_decided=1
      continue
    fi
    if echo "$line" | grep -q "^## "; then
      in_decided=0
      continue
    fi
    if [ $in_decided -eq 1 ] && echo "$line" | grep -q "^\- \["; then
      name=$(echo "$line" | sed 's/^\- \[//' | sed 's/\].*//')
      desc=$(echo "$line" | sed 's/^[^—]*— //')
      if [ $briefs_found -eq 0 ]; then echo "# briefs"; fi
      printf "%s\t%s\n" "$name" "$desc"
      briefs_found=1
      found=1
    fi
  done < "plans/briefs/INDEX.md"
fi

exit $((1 - found))

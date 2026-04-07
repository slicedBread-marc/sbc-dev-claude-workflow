#!/usr/bin/env bash
# wf-list-specable.sh
# Outputs work available for /wf-spec, in priority order.
# Reads REGISTRY.md for plans in draft state, plus bugs/open and briefs.
# Exit 0 if any work found, exit 1 if nothing.

set -euo pipefail

REGISTRY="plans/REGISTRY.md"
found=0

# --- Escalated plans in draft state (highest priority) ---
escalated=()
while IFS='|' read -r _ id slug state _rest; do
  id=$(echo "$id" | xargs)
  slug=$(echo "$slug" | xargs)
  state=$(echo "$state" | xargs)
  [ "$state" = "draft" ] || continue
  plan_dir="plans/${id}-${slug}"
  [ -d "$plan_dir" ] || continue
  findings="$plan_dir/findings.md"
  if [ -f "$findings" ] && grep -q "ESCALATED" "$findings" 2>/dev/null; then
    count=$(grep -c "ESCALATED" "$findings" 2>/dev/null || echo 0)
    escalated+=("${id}-${slug}	$count escalated finding(s)")
    found=1
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
      desc=$(echo "$line" | sed 's/^[^—]*— //')
      if [ $briefs_found -eq 0 ]; then echo "# briefs"; fi
      printf "%s\t%s\n" "$name" "$desc"
      briefs_found=1
      found=1
    fi
  done < "plans/briefs/INDEX.md"
fi

exit $((1 - found))

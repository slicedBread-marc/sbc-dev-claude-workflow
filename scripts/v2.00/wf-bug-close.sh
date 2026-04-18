#!/usr/bin/env bash
# wf-bug-close.sh <bug-id> <plan-name>
# Moves a bug from triaged → closed and marks it as resolved.
# Updates bug.md Status to Closed with date and fixing plan.
#
# Example: wf-bug-close.sh BUG-003 PLN-005-login-crash
# Exit 0 on success, 1 on error.

set -euo pipefail

bug_id="${1:-}"
plan_name="${2:-}"

if [ -z "$bug_id" ] || [ -z "$plan_name" ]; then
  echo "Usage: $0 <bug-id> <plan-name>" >&2
  exit 1
fi

# Find the bug folder in triaged
bug_dir=""
for d in bugs/triaged/${bug_id}*/; do
  if [ -d "$d" ]; then
    bug_dir="${d%/}"
    break
  fi
done

if [ -z "$bug_dir" ]; then
  echo "Error: $bug_id not found in bugs/triaged/" >&2
  exit 1
fi

bug_slug=$(basename "$bug_dir")
today=$(date +%Y-%m-%d)

# Update bug.md
if [ -f "$bug_dir/bug.md" ]; then
  sed -i '' 's/Status:\*\* Triaged/Status:** Closed/' "$bug_dir/bug.md"
  # Add closed date after Status line
  awk -v line="> **Closed:** $today" '
    { print }
    /Status:\*\* Closed/ && !done1 { print line; done1=1 }
  ' "$bug_dir/bug.md" > "$bug_dir/bug.md.tmp" && mv "$bug_dir/bug.md.tmp" "$bug_dir/bug.md"
  # Add note after ## Notes heading
  awk -v line="Fixed by plan: $plan_name" '
    { print }
    /^## Notes/ && !done2 { print line; done2=1 }
  ' "$bug_dir/bug.md" > "$bug_dir/bug.md.tmp" && mv "$bug_dir/bug.md.tmp" "$bug_dir/bug.md"
fi

# Move to closed
mkdir -p bugs/closed
git mv "$bug_dir" "bugs/closed/$bug_slug"

echo "$bug_id → closed (fixed by $plan_name)"

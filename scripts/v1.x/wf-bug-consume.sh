#!/usr/bin/env bash
# wf-bug-consume.sh <bug-id> <plan-id>
# Moves a bug from open → triaged and links it to a plan.
# Updates bug.md Status to Triaged and sets Plan field.
#
# Example: wf-bug-consume.sh BUG-003 PLN-005-login-crash
# Exit 0 on success, 1 on error.

set -euo pipefail

bug_id="${1:-}"
plan_id="${2:-}"

if [ -z "$bug_id" ] || [ -z "$plan_id" ]; then
  echo "Usage: $0 <bug-id> <plan-id>" >&2
  exit 1
fi

# Find the bug folder in open
bug_dir=""
for d in bugs/open/${bug_id}*/; do
  if [ -d "$d" ]; then
    bug_dir="${d%/}"
    break
  fi
done

if [ -z "$bug_dir" ]; then
  echo "Error: $bug_id not found in bugs/open/" >&2
  exit 1
fi

bug_slug=$(basename "$bug_dir")

# Update bug.md
if [ -f "$bug_dir/bug.md" ]; then
  sed -i '' 's/Status:\*\* Open/Status:** Triaged/' "$bug_dir/bug.md"
  sed -i '' "s|Plan:\*\* .*|Plan:** $plan_id|" "$bug_dir/bug.md"
fi

# Move to triaged
mkdir -p bugs/triaged
git mv "$bug_dir" "bugs/triaged/$bug_slug"

echo "$bug_id → triaged (linked to $plan_id)"

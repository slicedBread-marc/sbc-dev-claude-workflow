#!/usr/bin/env bash
# wf-list-briefs.sh
# Lists briefs from plans/briefs/INDEX.md grouped by status section.
#
# Output: section headers prefixed with '#', entries as <name>\t<description>
# Sections: # Decided, # Exploring, # Idea, # Planned
# Exit 0 if INDEX.md exists and has entries, exit 1 otherwise.

set -euo pipefail

[ -f "plans/briefs/INDEX.md" ] || exit 1

found=0
current_section=""
last_printed_section=""

while IFS= read -r line; do
  # Detect section headers (## Decided, ## Exploring, etc.)
  if echo "$line" | grep -qE '^## '; then
    current_section=$(echo "$line" | sed 's/^## //' | sed 's/[[:space:]]*$//')
    continue
  fi

  # Parse brief entries: "- [Name](file.md) — Description"
  if [ -n "$current_section" ] && echo "$line" | grep -qE '^\- \['; then
    name=$(echo "$line" | sed 's/^\- \[//' | sed 's/\].*//')
    desc=$(echo "$line" | sed 's/^[^—]*— //')
    if [ "$current_section" != "$last_printed_section" ]; then
      echo "# $current_section"
      last_printed_section="$current_section"
    fi
    printf "%s\t%s\n" "$name" "$desc"
    found=1
  fi
done < "plans/briefs/INDEX.md"

exit $((1 - (found > 0 ? 1 : 0)))

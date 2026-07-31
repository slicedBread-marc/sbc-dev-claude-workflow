#!/usr/bin/env bash
# wf-list-gates.sh [artifact-id]
#
# Lists artifacts parked on a human decision — the /wf-attend work queue.
#
# With an artifact ID: exit 0 if that artifact has an open gate (and print it),
# exit 1 if not. This is the dispatcher's "should I skip this one?" test.
#
# stdout, one per line, tab-separated:
#   <id>\t<gate-name>\t<age>\t<question>\t<context>
#
# Ordered by age, oldest first — the queue is FIFO so nothing starves.
#
# stderr: GATES: N
#
# Exit 0 if any gate is open, 1 if none.

set -euo pipefail

# shellcheck source=wf-orch-lib.sh
source "$(dirname "$0")/wf-orch-lib.sh"

query="${1:-}"
gates_dir="$(wf_orch_dir)/gates"

# Single-artifact probe
if [ -n "$query" ]; then
  id=$(printf '%s' "$query" | grep -oE '^(PLN|BUG|BRF)-[0-9]+' || true)
  [ -n "$id" ] || { echo "Error: '$query' is not a PLN/BUG/BRF id" >&2; exit 2; }
  gate_file="$gates_dir/${id}.gate"
  [ -f "$gate_file" ] || exit 1
  # shellcheck disable=SC1090
  eval "$(cat "$gate_file")"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$GATE_ID" "$GATE_NAME" "$GATE_OPENED" "$GATE_QUESTION" "${GATE_CONTEXT:-—}"
  exit 0
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

for gate_file in "$gates_dir"/*.gate; do
  [ -f "$gate_file" ] || continue
  # Gate files are written by wf_emit — every value single-quoted, so this is
  # safe against spaces and shell metacharacters in the question text.
  # Eval in a subshell so one malformed gate can't poison the next.
  (
    # shellcheck disable=SC1090
    eval "$(cat "$gate_file")"
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$GATE_OPENED" "$GATE_ID" "$GATE_NAME" "$GATE_QUESTION" "${GATE_CONTEXT:-—}"
  ) >> "$tmp" 2>/dev/null || true
done

if [ ! -s "$tmp" ]; then
  echo "GATES: 0" >&2
  exit 1
fi

# Sort by opened timestamp (ISO-8601 sorts lexically = oldest first), then
# move the timestamp into its display position.
sort "$tmp" | awk -F'\t' '{ print $2 "\t" $3 "\t" $1 "\t" $4 "\t" $5 }'
echo "GATES: $(wc -l < "$tmp" | xargs)" >&2
exit 0

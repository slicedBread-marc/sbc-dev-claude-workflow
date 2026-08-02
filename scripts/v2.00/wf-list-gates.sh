#!/usr/bin/env bash
# wf-list-gates.sh [artifact-id]
#
# Lists artifacts parked on a human decision — the /wf-attend work queue.
#
# With an artifact ID: exit 0 if that artifact has an open gate (and print it),
# exit 1 if not. This is the dispatcher's "should I skip this one?" test.
#
# stdout, one per line, tab-separated:
#   <id>\t<gate-name>\t<age>\t<question>\t<context>\t<blocking>
#
# <blocking> is the number of OTHER incomplete plans that cannot start until
# this gate is answered — the transitive closure over the Deps column.
#
# Ordered by <blocking> descending, then by age. A pure FIFO ordering is
# uncorrelated with what a gate actually costs: on a dependency chain the cost
# of a gate is not the minute it takes to answer, it is that minute times the
# size of the closure behind it. One gate at the root of a 16-plan chain held
# every other plan for 25 hours while the queue presented it alongside a gate
# blocking nothing. Ties still break oldest-first, so nothing starves.
#
# stderr: GATES: N
#
# Exit 0 if any gate is open, 1 if none.

set -euo pipefail

# shellcheck source=wf-orch-lib.sh
source "$(dirname "$0")/wf-orch-lib.sh"

query="${1:-}"
gates_dir="$(wf_orch_dir)/gates"
REGISTRY="$(wf_develop_root)/plans/REGISTRY.md"

# How many other incomplete plans sit behind this one in the Deps graph.
# BFS over the reverse-dependency edges; a plan already `complete` is not
# blocked by anything, so it and its own dependents are not counted through it.
blocked_by() {
  [ -f "$REGISTRY" ] || { printf '0'; return 0; }
  awk -F'|' -v root="$1" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^\|/ {
      pid = trim($2)
      if (pid == "" || pid == "ID" || pid ~ /^-+$/) next
      state[pid] = trim($4)
      n = split(trim($10), d, ",")
      for (i = 1; i <= n; i++) {
        dep = trim(d[i])
        if (dep != "" && dep != "—") rdeps[dep] = rdeps[dep] "," pid
      }
    }
    END {
      queue[1] = root; head = 1; tail = 1; count = 0
      while (head <= tail) {
        cur = queue[head++]
        n = split(rdeps[cur], kids, ",")
        for (i = 1; i <= n; i++) {
          k = kids[i]
          if (k == "" || (k in seen) || state[k] == "complete") continue
          seen[k] = 1; count++
          queue[++tail] = k
        }
      }
      print count
    }
  ' "$REGISTRY"
}

# Single-artifact probe
if [ -n "$query" ]; then
  id=$(printf '%s' "$query" | grep -oE '^(PLN|BUG|BRF)-[0-9]+' || true)
  [ -n "$id" ] || { echo "Error: '$query' is not a PLN/BUG/BRF id" >&2; exit 2; }
  gate_file="$gates_dir/${id}.gate"
  [ -f "$gate_file" ] || exit 1
  # shellcheck disable=SC1090
  eval "$(cat "$gate_file")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$GATE_ID" "$GATE_NAME" "$GATE_OPENED" "$GATE_QUESTION" "${GATE_CONTEXT:-—}" "$(blocked_by "$id")"
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
    # Blocking count leads, zero-padded, so a plain lexical sort orders by cost
    # first and by opened-timestamp second without a second sort key.
    printf '%06d\t%s\t%s\t%s\t%s\t%s\n' \
      "$(blocked_by "$GATE_ID")" "$GATE_OPENED" "$GATE_ID" "$GATE_NAME" \
      "$GATE_QUESTION" "${GATE_CONTEXT:-—}"
  ) >> "$tmp" 2>/dev/null || true
done

if [ ! -s "$tmp" ]; then
  echo "GATES: 0" >&2
  exit 1
fi

# Costliest first, oldest first within a cost. `sort -r` on the padded count
# reverses the timestamp too, so sort the count descending as its own key and
# leave the ISO-8601 timestamp ascending (lexical = oldest first).
sort -k1,1nr -k2,2 "$tmp" \
  | awk -F'\t' '{ print $3 "\t" $4 "\t" $2 "\t" $5 "\t" $6 "\t" ($1 + 0) }'
echo "GATES: $(wc -l < "$tmp" | xargs)" >&2
exit 0

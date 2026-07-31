#!/usr/bin/env bash
# wf-event.sh <type> <artifact> [message]
#
# Appends one line to <develop-root>/.claude/orchestrator/events.log.
# This is the orchestrator's audit trail: what was spawned, what transitioned,
# what parked, what failed — the thing you read when a soak run misbehaves.
#
# Types in use: spawn, exit, gate-open, gate-close, transition, skip, sweep,
#               stuck, budget.
#
# Reading it back:
#   wf-event.sh --tail 20        last 20 events, newest last
#   wf-event.sh --for PLN-097    every event for one artifact
#
# Exit 0 always — logging must never break a pipeline step.

set -euo pipefail

# shellcheck source=wf-orch-lib.sh
source "$(dirname "$0")/wf-orch-lib.sh"

log="$(wf_orch_dir)/events.log"

case "${1:-}" in
  --tail)
    n="${2:-20}"
    [ -f "$log" ] && tail -n "$n" "$log" || true
    exit 0
    ;;
  --for)
    artifact="${2:?--for requires an artifact id}"
    id=$(printf '%s' "$artifact" | grep -oE '^(PLN|BUG|BRF)-[0-9]+' || printf '%s' "$artifact")
    [ -f "$log" ] && awk -F'\t' -v id="$id" '$3 == id' "$log" || true
    exit 0
    ;;
  "")
    echo "Usage: $0 <type> <artifact> [message] | --tail [n] | --for <id>" >&2
    exit 1
    ;;
esac

wf_event "$1" "${2:-—}" "${3:-}"
exit 0

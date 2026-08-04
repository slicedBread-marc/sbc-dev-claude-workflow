#!/usr/bin/env bash
# wf-gate-open.sh <artifact-id> <gate-name> <question> [--context <path>] [--skill <name>]
#
# Parks an artifact on a human decision. An unattended worker calls this INSTEAD
# of asking a question, then exits 0. The dispatcher skips any artifact with an
# open gate, so nothing spins; /wf-attend drains the queue later.
#
# Gate file: <develop-root>/.claude/orchestrator/gates/<ID>.gate
# One file per artifact — concurrent workers would race on appends to a shared
# file, and per-artifact files make "is this one parked?" a single test -f.
#
# Gate names in use:
#   spec-approval   spec is drafted AND reviewed, and needs sign-off before
#                   code is written (the review always runs first — see wf-spec)
#   spec-stuck      the review blocked the plan for maxReviewRounds rounds
#   scope-reduction a replan narrows a capability the plan's Goal promises
#   manual-test     a `#### Manual` acceptance criterion needs human eyes
#   goal-missing    plan has no concrete goal line
#   migration       plan has pending MIGRATION-NOTES actions
#   merge-failed    PR could not be merged (conflicts, checks, protection)
#   stuck           plan exceeded its attempt budget
#
# Re-opening an existing gate is a no-op (keeps the original timestamp), so a
# retried worker doesn't reset the queue position.
#
# Exit 0 on success, 1 on error.

set -euo pipefail

# shellcheck source=wf-orch-lib.sh
source "$(dirname "$0")/wf-orch-lib.sh"

artifact="${1:-}"
gate_name="${2:-}"
question="${3:-}"
shift 3 2>/dev/null || true

context=""
skill=""
while [ $# -gt 0 ]; do
  case "$1" in
    --context) context="${2:?--context requires a path}"; shift 2 ;;
    --skill)   skill="${2:?--skill requires a name}"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$artifact" ] || [ -z "$gate_name" ] || [ -z "$question" ]; then
  echo "Usage: $0 <artifact-id> <gate-name> <question> [--context path] [--skill name]" >&2
  exit 1
fi

# Accept PLN-004 or PLN-004-slug; the gate is keyed by bare ID.
id=$(printf '%s' "$artifact" | grep -oE '^(PLN|BUG|BRF)-[0-9]+' || true)
if [ -z "$id" ]; then
  echo "Error: '$artifact' is not a PLN/BUG/BRF id" >&2
  exit 1
fi

gate_file="$(wf_orch_dir)/gates/${id}.gate"

if [ -f "$gate_file" ]; then
  existing=$(grep -m1 "^GATE_NAME=" "$gate_file" | sed "s/^GATE_NAME='//; s/'$//")
  if [ "$existing" = "$gate_name" ]; then
    echo "$id: gate '$gate_name' already open — left as is"
    exit 0
  fi
fi

{
  wf_emit GATE_ID       "$id"
  wf_emit GATE_ARTIFACT "$artifact"
  wf_emit GATE_NAME     "$gate_name"
  wf_emit GATE_QUESTION "$question"
  wf_emit GATE_CONTEXT  "$context"
  wf_emit GATE_SKILL    "$skill"
  wf_emit GATE_OPENED   "$(wf_now)"
} > "$gate_file"

wf_event gate-open "$id" "$gate_name: $question"
echo "$id: gate '$gate_name' opened — $question"

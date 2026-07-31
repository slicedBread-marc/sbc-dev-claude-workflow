#!/usr/bin/env bash
# wf-gate-close.sh <artifact-id> [resolution]
#
# Releases a parked artifact. The next dispatcher sweep picks it up again.
# Safe to call when no gate is open.
#
# resolution is free text recorded in events.log (e.g. "approved", "rejected",
# "criteria passed") — it is the audit trail for why work resumed.
#
# Exit 0 always (idempotent).

set -euo pipefail

# shellcheck source=wf-orch-lib.sh
source "$(dirname "$0")/wf-orch-lib.sh"

artifact="${1:?Usage: $0 <artifact-id> [resolution]}"
resolution="${2:-resolved}"

id=$(printf '%s' "$artifact" | grep -oE '^(PLN|BUG|BRF)-[0-9]+' || true)
if [ -z "$id" ]; then
  echo "Error: '$artifact' is not a PLN/BUG/BRF id" >&2
  exit 1
fi

gate_file="$(wf_orch_dir)/gates/${id}.gate"

if [ ! -f "$gate_file" ]; then
  echo "$id: no open gate"
  exit 0
fi

gate_name=$(grep -m1 "^GATE_NAME=" "$gate_file" | sed "s/^GATE_NAME='//; s/'$//")
rm -f "$gate_file"

wf_event gate-close "$id" "$gate_name: $resolution"
echo "$id: gate '$gate_name' closed — $resolution"

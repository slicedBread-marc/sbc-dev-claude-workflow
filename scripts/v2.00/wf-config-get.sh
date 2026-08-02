#!/usr/bin/env bash
# wf-config-get.sh <dotted.path> [default] [--list]
#
# Reads one value out of claude-workflow.yml, so a skill can branch on config
# without hand-rolling awk in a markdown code block (which is how the same
# parser ended up written four slightly different ways).
#
#   wf-config-get.sh specApproval.mode gate           → gate
#   wf-config-get.sh specApproval.gateTags --list     → security
#                                                       infra
#
# Scalars print on one line; --list prints one item per line and ignores the
# default. Same deliberate limits as wf_cfg: no yq dependency, 2-space
# indentation, scalars only.
#
# Exit 0 always when the path resolves or a default is supplied.

set -euo pipefail

# shellcheck source=wf-orch-lib.sh
source "$(dirname "$0")/wf-orch-lib.sh"

path=""
default=""
as_list=false

while [ $# -gt 0 ]; do
  case "$1" in
    --list) as_list=true; shift ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) if [ -z "$path" ]; then path="$1"; else default="$1"; fi; shift ;;
  esac
done

[ -n "$path" ] || { echo "Usage: $0 <dotted.path> [default] [--list]" >&2; exit 2; }

if $as_list; then
  wf_cfg_list "$path"
else
  printf '%s\n' "$(wf_cfg "$path" "$default")"
fi

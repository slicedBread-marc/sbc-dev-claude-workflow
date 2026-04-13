#!/usr/bin/env bash
# wf-set-reboot-flag.sh [message]
# Sets a restart reminder shown at the end of each skill run.
# Default message: "Restart this terminal at next opportunity."
set -euo pipefail

message="${1:-Restart this terminal at next opportunity.}"
echo "$message" > .claude/reboot-flag
echo "Reboot flag set: $message"
echo "Clear with: scripts/wf-clear-reboot-flag.sh"

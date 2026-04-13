#!/usr/bin/env bash
# wf-clear-reboot-flag.sh
# Clears the restart reminder flag.
set -euo pipefail

if [ -f .claude/reboot-flag ]; then
  rm .claude/reboot-flag
  echo "Reboot flag cleared."
else
  echo "No reboot flag set."
fi

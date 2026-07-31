#!/usr/bin/env bash
# wf-spawn.sh <role> <artifact> [options]
#
# Launches ONE unattended worker: a headless `claude -p` session running a
# workflow skill against a single artifact, with WF_UNATTENDED=1 set so the
# skill takes its [AUTO] defaults and opens gates instead of asking questions.
#
# This is the single spawn path. The post-commit verify hook and the
# orchestrator daemon both call it, which is what stops them double-launching
# the same plan — the pidfile guard lives here, not in each caller.
#
#   role      spec | implement | verify | test
#   artifact  PLN-NNN[-slug], or BUG-NNN / BRF-NNN for the spec role
#
# Options:
#   --foreground   run inline and block (drive-one mode); default is nohup+disown
#   --dry-run      print what would be launched, change nothing
#   --model NAME   override the configured model tier for this role
#
# Model tiers come from claude-workflow.yml → orchestrator.models.<role>,
# defaulting to the pipeline's standing assignment: spec=opus (judgment),
# implement=sonnet, verify=sonnet, test=haiku (guided).
#
# Exit codes:
#   0   spawned (background) or worker succeeded (foreground)
#   1   bad usage / worker failed
#   2   already running for this artifact+role — not an error, nothing to do

set -euo pipefail

# shellcheck source=wf-orch-lib.sh
source "$(dirname "$0")/wf-orch-lib.sh"

role="${1:-}"
artifact="${2:-}"
shift 2 2>/dev/null || true

foreground=false
dry_run=false
model_override=""

while [ $# -gt 0 ]; do
  case "$1" in
    --foreground) foreground=true; shift ;;
    --dry-run)    dry_run=true; shift ;;
    --model)      model_override="${2:?--model requires a name}"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

case "$role" in
  spec|implement|verify|test) ;;
  *) echo "Usage: $0 <spec|implement|verify|test> <artifact> [--foreground] [--dry-run] [--model NAME]" >&2; exit 1 ;;
esac

id=$(printf '%s' "$artifact" | grep -oE '^(PLN|BUG|BRF)-[0-9]+' || true)
[ -n "$id" ] || { echo "Error: '$artifact' is not a PLN/BUG/BRF id" >&2; exit 1; }

ROOT="$(wf_develop_root)"
ORCH="$(wf_orch_dir)"

# ── Default model per role ────────────────────────────────────────────────
default_model() {
  case "$1" in
    spec)      echo "opus" ;;
    implement) echo "sonnet" ;;
    verify)    echo "sonnet" ;;
    test)      echo "haiku" ;;
  esac
}
model="${model_override:-$(wf_cfg "orchestrator.models.$role" "$(default_model "$role")")}"

# ── Already-running guard ─────────────────────────────────────────────────
pidfile="$ORCH/logs/${artifact}-${role}.pid"
if [ -f "$pidfile" ]; then
  old_pid=$(cat "$pidfile" 2>/dev/null || echo "")
  if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
    echo "wf-spawn: $role already running for $artifact (PID $old_pid)" >&2
    exit 2
  fi
  rm -f "$pidfile"
fi

# ── Worker prompt ─────────────────────────────────────────────────────────
# Skills live at .claude/skills/wf-<role>/SKILL.md on a client checkout.
read -r -d '' prompt <<PROMPT || true
You are running UNATTENDED as part of the workflow orchestrator. WF_UNATTENDED=1 is set in your environment. There is no human reading your output — a question you ask will hang the pipeline.

Read .claude/skills/wf-${role}/SKILL.md in full, INCLUDING its "Unattended mode" section, then execute it for ${id} (full artifact name: ${artifact}).

Follow the Unattended mode rules exactly:
- Skip any work-selection menu; ${id} is your assigned artifact.
- Resolve [AUTO] prompts to their documented defaults.
- For anything marked [GATE], or anything you would otherwise ask a human, run scripts/wf-exec.sh wf-gate-open.sh with a clear question and then exit cleanly. Never guess.
PROMPT

if $dry_run; then
  echo "DRY-RUN spawn: role=$role artifact=$artifact model=$model foreground=$foreground"
  exit 0
fi

ts=$(date +%Y%m%d-%H%M%S)
log="$ORCH/logs/${artifact}-${role}-${ts}.log"

# ── Foreground: block, stream, propagate the worker's status ──────────────
if $foreground; then
  wf_event spawn "$id" "$role ($model) foreground"
  echo $$ > "$pidfile"
  set +e
  ( cd "$ROOT" && WF_UNATTENDED=1 WF_ROLE="$role" WF_ARTIFACT="$artifact" \
      claude -p --model "$model" --dangerously-skip-permissions "$prompt" ) 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}
  set -e
  rm -f "$pidfile"
  wf_event exit "$id" "$role rc=$rc"
  exit "$rc"
fi

# ── Background: detach, record the PID, clean up the pidfile on exit ──────
# The prompt goes through the environment rather than the command string —
# it is multi-line and would need three levels of quoting otherwise.
export WF_PROMPT="$prompt"
export WF_UNATTENDED=1 WF_ROLE="$role" WF_ARTIFACT="$artifact"
event_sh="$(cd "$(dirname "$0")" && pwd)/wf-event.sh"

nohup bash -c "
    cd '$ROOT'
    claude -p --model '$model' --dangerously-skip-permissions \"\$WF_PROMPT\"
    rc=\$?
    rm -f '$pidfile'
    '$event_sh' exit '$id' \"$role rc=\$rc\"
" > "$log" 2>&1 &

worker_pid=$!
echo "$worker_pid" > "$pidfile"
disown "$worker_pid" 2>/dev/null || true

wf_event spawn "$id" "$role ($model) pid $worker_pid"
echo "wf-spawn: $role/$artifact on $model — PID $worker_pid, log $log"

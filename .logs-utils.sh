#!/bin/bash
# Logging utilities for workflow session tracking
# Source this in each terminal: source .logs-utils.sh

# Initialize session ID (call once per terminal at startup)
# All terminals in the same working directory share the same SESSION_ID
init_session() {
  local session_file=".logs/SESSION_ID"
  mkdir -p .logs

  # First terminal creates the session ID; others read it
  if [ ! -f "$session_file" ]; then
    export SESSION_ID="$(date +%Y-%m-%d-%s)"
    echo "$SESSION_ID" > "$session_file"
  else
    export SESSION_ID=$(cat "$session_file")
  fi

  echo "SESSION_ID: $SESSION_ID"
}

# Get current queue state from REGISTRY.md
queue_state() {
  local reg="plans/REGISTRY.md"
  local ready=$(grep -c "| ready |" "$reg" 2>/dev/null || echo 0)
  local active=$(grep -c "| active |" "$reg" 2>/dev/null || echo 0)
  local verify=$(grep -c "| verify |" "$reg" 2>/dev/null || echo 0)
  local testing=$(grep -c "| testing |" "$reg" 2>/dev/null || echo 0)
  local open=$(ls -1d bugs/open/* 2>/dev/null | wc -l)
  local triaged=$(ls -1d bugs/triaged/* 2>/dev/null | wc -l)
  echo "ready=$ready active=$active verify=$verify testing=$testing open=$open triaged=$triaged"
}

# Log a single line (with file locking)
log_action() {
  local skill="$1"
  local action="$2"    # start|done|error
  local metric="$3"    # what was done (e.g., "BRF-001" or "PLN-001→ready")
  local log_file=".logs/workflow.log"

  local timestamp=$(date +%H:%M:%S)
  local q=$(queue_state)

  (
    flock 200
    echo "[$timestamp] $SESSION_ID | $skill | $action | $metric | Q: $q" >> "$log_file"
  ) 200>"$log_file.lock"
}

# Convenience: log skill start
log_start() {
  local skill="$1"
  local input="$2"
  log_action "$skill" "start" "$input"
}

# Convenience: log skill completion
log_done() {
  local skill="$1"
  local outcome="$2"
  log_action "$skill" "done" "$outcome"
}

# Convenience: log error
log_error() {
  local skill="$1"
  local error="$2"
  log_action "$skill" "error" "$error"
}

# Show last N lines of log
log_tail() {
  local n="${1:-10}"
  tail -n "$n" .logs/workflow.log
}

# Watch log in real-time
log_watch() {
  tail -f .logs/workflow.log
}

# Show log summary for a session
log_summary() {
  local session="${1:-*}"
  echo "=== Session: $session ==="
  grep "$session" .logs/workflow.log | head -20
  echo ""
  grep "$session" .logs/workflow.log | tail -20
}

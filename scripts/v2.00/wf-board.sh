#!/usr/bin/env bash
# wf-board.sh [--watch [seconds]] [--plain]
#
# One pane showing everything in flight: running workers, queued gates, the
# pipeline by state, and recent events. This is the replacement for holding
# four terminals' worth of state in your head.
#
# Pure render — reads REGISTRY.md, pidfiles, gate files and events.log.
# Spawns nothing, changes nothing, costs no tokens.
#
#   --watch [n]   refresh every n seconds (default 10)
#   --plain       no colour (for piping or logging)
#
# Exit 0 always.

set -uo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=wf-orch-lib.sh
source "$SELF_DIR/wf-orch-lib.sh"

watch_mode=false
watch_secs=10
plain=false

while [ $# -gt 0 ]; do
  case "$1" in
    --watch) watch_mode=true
             if [ "${2:-}" ] && [ "${2#-}" = "${2}" ]; then watch_secs="$2"; shift; fi
             shift ;;
    --plain) plain=true; shift ;;
    *) echo "Usage: $0 [--watch [seconds]] [--plain]" >&2; exit 1 ;;
  esac
done

if $plain || [ ! -t 1 ]; then
  B=""; DIM=""; R=""; GRN=""; YEL=""; CYN=""
else
  B=$'\033[1m'; DIM=$'\033[2m'; R=$'\033[0m'
  GRN=$'\033[32m'; YEL=$'\033[33m'; CYN=$'\033[36m'
fi

ROOT="$(wf_develop_root)"
ORCH="$(wf_orch_dir)"
REGISTRY="$ROOT/plans/REGISTRY.md"

# macOS and GNU stat disagree; try both.
file_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

human_age() {
  local secs="$1"
  if   [ "$secs" -lt 60 ]    ; then printf '%ds' "$secs"
  elif [ "$secs" -lt 3600 ]  ; then printf '%dm' "$((secs / 60))"
  elif [ "$secs" -lt 86400 ] ; then printf '%dh%dm' "$((secs / 3600))" "$(((secs % 3600) / 60))"
  else printf '%dd' "$((secs / 86400))"
  fi
}

render() {
  local now; now=$(date +%s)

  # ── Header ──────────────────────────────────────────────────────────
  local daemon_state="${DIM}off${R}"
  if [ -f "$ORCH/daemon.pid" ]; then
    local dpid; dpid=$(cat "$ORCH/daemon.pid" 2>/dev/null || echo "")
    if [ -n "$dpid" ] && kill -0 "$dpid" 2>/dev/null; then
      daemon_state="${GRN}running${R} ${DIM}(pid $dpid)${R}"
    else
      daemon_state="${YEL}stale pidfile${R}"
    fi
  fi
  local enabled; enabled=$(wf_cfg orchestrator.enabled false)
  local budget_used; budget_used=$(cat "$ORCH/spawns-$(date +%Y%m%d%H)" 2>/dev/null || echo 0)
  local budget_max;  budget_max=$(wf_cfg orchestrator.max_spawns_per_hour 20)

  printf '%s\n' "${B}WORKFLOW BOARD${R}  ${DIM}$(date '+%Y-%m-%d %H:%M:%S')${R}"
  printf '  daemon: %s   enabled: %s   spawns this hour: %s/%s\n\n' \
    "$daemon_state" "$enabled" "$budget_used" "$budget_max"

  # ── Running workers ─────────────────────────────────────────────────
  printf '%s\n' "${B}RUNNING${R}"
  local any=0 pf pid base role artifact age
  for pf in "$ORCH/logs"/*.pid; do
    [ -f "$pf" ] || continue
    pid=$(cat "$pf" 2>/dev/null || echo "")
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || continue
    base=$(basename "$pf" .pid)
    role="${base##*-}"
    artifact="${base%-*}"
    age=$(( now - $(file_mtime "$pf") ))
    printf '  %s%-11s%s %-34s %s  %spid %s%s\n' \
      "$CYN" "$role" "$R" "$artifact" "$(human_age "$age")" "$DIM" "$pid" "$R"
    any=1
  done
  [ "$any" -eq 0 ] && printf '  %snothing running%s\n' "$DIM" "$R"
  printf '\n'

  # ── Gates ───────────────────────────────────────────────────────────
  printf '%s\n' "${B}GATES${R} ${DIM}— waiting on you (/wf-attend)${R}"
  local gates; gates=$("$SELF_DIR/wf-list-gates.sh" 2>/dev/null || true)
  if [ -n "$gates" ]; then
    printf '%s\n' "$gates" | while IFS=$'\t' read -r gid gname gopened gq _gctx gblk; do
      [ -n "$gid" ] || continue
      # Costliest first — the count is what the gate is holding up, and it is
      # the only thing on this line that says whether answering it is urgent.
      if [ "${gblk:-0}" -gt 0 ] 2>/dev/null; then
        printf '  %s%-11s%s %-11s %s(blocking %s)%s %s\n' \
          "$YEL" "$gname" "$R" "$gid" "$YEL" "$gblk" "$R" "$gq"
      else
        printf '  %s%-11s%s %-11s %s\n' "$YEL" "$gname" "$R" "$gid" "$gq"
      fi
    done
  else
    printf '  %snone — nothing is waiting on you%s\n' "$DIM" "$R"
  fi
  printf '\n'

  # ── Pipeline ────────────────────────────────────────────────────────
  printf '%s\n' "${B}PIPELINE${R}"
  if [ -f "$REGISTRY" ]; then
    local st n
    for st in draft ready active verify testing; do
      n=$(awk -F'|' -v s="$st" '
        function trim(x) { gsub(/^[ \t]+|[ \t]+$/, "", x); return x }
        /^\| PLN-/ && trim($4) == s { c++ } END { print c + 0 }' "$REGISTRY")
      printf '  %-9s %s\n' "$st" "$n"
    done
    n=$(awk -F'|' '
      function trim(x) { gsub(/^[ \t]+|[ \t]+$/, "", x); return x }
      /^\| PLN-/ && trim($4) == "complete" { c++ } END { print c + 0 }' "$REGISTRY")
    printf '  %s%-9s %s%s\n' "$DIM" "complete" "$n" "$R"
  else
    printf '  %sno REGISTRY.md%s\n' "$DIM" "$R"
  fi
  printf '\n'

  # ── Recent events ───────────────────────────────────────────────────
  printf '%s\n' "${B}RECENT${R}"
  if [ -s "$ORCH/events.log" ]; then
    tail -8 "$ORCH/events.log" | while IFS=$'\t' read -r ets etype eart emsg; do
      printf '  %s%s%s  %-11s %-11s %s\n' "$DIM" "${ets#*T}" "$R" "$etype" "$eart" "$emsg"
    done
  else
    printf '  %sno events yet%s\n' "$DIM" "$R"
  fi
}

if $watch_mode; then
  trap 'printf "\n"; exit 0' INT TERM
  while true; do
    printf '\033[H\033[2J'
    render
    printf '\n%srefreshing every %ss — Ctrl-C to stop%s\n' "$DIM" "$watch_secs" "$R"
    sleep "$watch_secs"
  done
else
  render
fi
exit 0

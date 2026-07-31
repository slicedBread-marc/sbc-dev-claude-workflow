#!/usr/bin/env bash
# wf-orchestrate.sh — the workflow dispatcher.
#
# Routing is pure bash: REGISTRY state maps to a role by table, and only the
# workers cost tokens. The orchestrator itself never calls a model.
#
# MODES
#   --sweep                one pass: dispatch everything eligible, exit
#   --daemon               sweep / sleep / repeat until stopped
#   --stop                 stop a running daemon (workers finish on their own)
#   --kill-all             stop the daemon AND terminate every live worker
#   <ID> [--until STATE]   drive ONE artifact as far through the pipeline as
#                          it will go, in the foreground. This is the hook for
#                          an agent in another repo.
#
# OPTIONS
#   --dry-run     report what would be spawned; spawn nothing
#   --json        machine-readable result (drive-one mode)
#   --interval N  daemon sweep interval, overriding config
#   --force       ignore orchestrator.enabled: false
#
# DRIVE-ONE EXIT CODES — the contract for external callers:
#   0    reached the target state
#   20   blocked on a human decision; the gate is on stdout / in --json
#   30   no progress: the worker ran but the state did not change
#   1    error (bad artifact, worker failure, orchestrator disabled)
#
# The dispatcher skips an artifact when ANY of these hold:
#   · a gate is open on it            · its deps are not complete
#   · another session holds its claim · its role is at max_concurrent
#   · it is over its attempt budget   · the hourly spawn budget is spent

set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=wf-orch-lib.sh
source "$SELF_DIR/wf-orch-lib.sh"

REGISTRY="plans/REGISTRY.md"

# ── Arguments ─────────────────────────────────────────────────────────────
mode=""
target=""
until_state=""
dry_run=false
as_json=false
interval_override=""
force=false

while [ $# -gt 0 ]; do
  case "$1" in
    --sweep)    mode="sweep"; shift ;;
    --daemon)   mode="daemon"; shift ;;
    --stop)     mode="stop"; shift ;;
    --kill-all) mode="kill-all"; shift ;;
    --until)    until_state="${2:?--until requires a state}"; shift 2 ;;
    --interval) interval_override="${2:?--interval requires seconds}"; shift 2 ;;
    --dry-run)  dry_run=true; shift ;;
    --json)     as_json=true; shift ;;
    --force)    force=true; shift ;;
    -h|--help)  sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)         echo "Unknown option: $1" >&2; exit 1 ;;
    *)          target="$1"; mode="${mode:-drive}"; shift ;;
  esac
done

[ -n "$mode" ] || { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

ROOT="$(wf_develop_root)"
ORCH="$(wf_orch_dir)"
mkdir -p "$ORCH/attempts"
cd "$ROOT"

# ── Config ────────────────────────────────────────────────────────────────
cfg_enabled=$(wf_cfg orchestrator.enabled false)
cfg_interval="${interval_override:-$(wf_cfg orchestrator.sweep_interval 60)}"
cfg_max_attempts=$(wf_cfg orchestrator.max_attempts_per_plan 3)
cfg_max_spawns=$(wf_cfg orchestrator.max_spawns_per_hour 20)

max_concurrent() {
  case "$1" in
    spec)      wf_cfg orchestrator.max_concurrent.spec 1 ;;
    implement) wf_cfg orchestrator.max_concurrent.implement 2 ;;
    verify)    wf_cfg orchestrator.max_concurrent.verify 2 ;;
    test)      wf_cfg orchestrator.max_concurrent.test 1 ;;
  esac
}

require_enabled() {
  if [ "$cfg_enabled" != "true" ] && ! $force; then
    echo "wf-orchestrate: disabled (set orchestrator.enabled: true in claude-workflow.yml, or pass --force)" >&2
    return 1
  fi
  return 0
}

# ── State helpers ─────────────────────────────────────────────────────────

bare_id() { printf '%s' "$1" | grep -oE '^(PLN|BUG|BRF)-[0-9]+' || true; }

# Plan state from the registry, empty if the plan has no row.
plan_state() {
  local id="$1"
  [ -f "$REGISTRY" ] || return 0
  grep "^| $id |" "$REGISTRY" 2>/dev/null | head -1 | awk -F'|' '{print $4}' | xargs || true
}

# Full plan name (PLN-NNN-slug) for an ID.
plan_name_of() {
  local id="$1" slug
  slug=$(grep "^| $id |" "$REGISTRY" 2>/dev/null | head -1 | awk -F'|' '{print $3}' | xargs || true)
  [ -n "$slug" ] && printf '%s-%s' "$id" "$slug" || printf '%s' "$id"
}

gate_open()  { "$SELF_DIR/wf-list-gates.sh" "$1" >/dev/null 2>&1; }
gate_line()  { "$SELF_DIR/wf-list-gates.sh" "$1" 2>/dev/null; }

# Live worker count for a role, across all artifacts.
role_running() {
  local role="$1" n=0 pf pid
  for pf in "$ORCH/logs"/*-"$role".pid; do
    [ -f "$pf" ] || continue
    pid=$(cat "$pf" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      n=$((n + 1))
    else
      rm -f "$pf"          # reap dead workers as we go
    fi
  done
  printf '%s' "$n"
}

# Attempt budget — the loop breaker. A plan bouncing active⇄verify forever
# burns tokens silently; after N implement spawns it parks as `stuck` instead.
attempts_get() { cat "$ORCH/attempts/$1.$2" 2>/dev/null || echo 0; }
attempts_bump() {
  local n; n=$(( $(attempts_get "$1" "$2") + 1 ))
  echo "$n" > "$ORCH/attempts/$1.$2"
}
attempts_reset() { rm -f "$ORCH/attempts/$1".* 2>/dev/null || true; }

# Hourly spawn budget. Bucketed by hour rather than parsed from events.log so
# it stays portable (no date arithmetic).
spawn_budget_left() {
  local bucket count
  bucket="$ORCH/spawns-$(date +%Y%m%d%H)"
  count=$(cat "$bucket" 2>/dev/null || echo 0)
  printf '%s' "$(( cfg_max_spawns - count ))"
}
spawn_budget_bump() {
  local bucket; bucket="$ORCH/spawns-$(date +%Y%m%d%H)"
  echo "$(( $(cat "$bucket" 2>/dev/null || echo 0) + 1 ))" > "$bucket"
  # Drop buckets older than today so the dir does not grow forever.
  find "$ORCH" -maxdepth 1 -name 'spawns-*' -mtime +1 -delete 2>/dev/null || true
}

# ── Dispatch ──────────────────────────────────────────────────────────────

# dispatch <role> <artifact> — run every skip rule, then spawn.
# Returns 0 if a worker was spawned, 1 if skipped.
dispatch() {
  local role="$1" artifact="$2"
  local id; id=$(bare_id "$artifact")

  if gate_open "$id"; then
    wf_event skip "$id" "$role: gate open"
    return 1
  fi

  local attempts; attempts=$(attempts_get "$id" "$role")
  if [ "$attempts" -ge "$cfg_max_attempts" ]; then
    if ! gate_open "$id"; then
      "$SELF_DIR/wf-gate-open.sh" "$artifact" stuck \
        "$role has run $attempts times without reaching a new state. Needs a human look." \
        --skill "wf-$role" >/dev/null 2>&1 || true
    fi
    wf_event stuck "$id" "$role: $attempts attempts, parked"
    return 1
  fi

  if [ "$(spawn_budget_left)" -le 0 ]; then
    wf_event budget "$id" "$role: hourly spawn budget exhausted ($cfg_max_spawns)"
    return 1
  fi

  if $dry_run; then
    echo "  would spawn: $role $artifact"
    return 0
  fi

  local rc=0
  "$SELF_DIR/wf-spawn.sh" "$role" "$artifact" || rc=$?
  case "$rc" in
    0) attempts_bump "$id" "$role"; spawn_budget_bump; return 0 ;;
    2) return 1 ;;   # already running — not an error
    *) wf_event error "$id" "$role: spawn failed rc=$rc"; return 1 ;;
  esac
}

# ── Candidate lists, per role ─────────────────────────────────────────────
# Each emits bare artifact names, one per line, already filtered for the
# states that role can act on. The wf-list-*.sh scripts remain the single
# source of eligibility truth (docs/eligibility.md) — we only parse them.

candidates_verify() {
  "$SELF_DIR/wf-list-verify.sh" 2>/dev/null | awk -F'\t' 'NF { print $1 }' || true
}

candidates_test() {
  # Field 6 carries "blocked:<deps>" when deps are unmet — those are not ours.
  "$SELF_DIR/wf-list-testable.sh" 2>/dev/null \
    | awk -F'\t' 'NF && $6 !~ /^blocked:/ { print $1 }' || true
}

candidates_implement() {
  # Types: new | resume | fix are actionable; processing (claimed elsewhere)
  # and blocked (deps) are not.
  "$SELF_DIR/wf-list-implementable.sh" 2>/dev/null \
    | awk -F'\t' '$1 == "new" || $1 == "resume" || $1 == "fix" { print $2 }' || true
}

candidates_spec() {
  # Sectioned output: "# replanning" rows are plan names, "# bugs" and
  # "# briefs" rows lead with BUG-NNN / BRF-NNN.
  "$SELF_DIR/wf-list-specable.sh" 2>/dev/null | awk -F'\t' '
    /^# / { next }
    NF && $1 != "—" { print $1 }
  ' || true
}

# ── Sweep ─────────────────────────────────────────────────────────────────
# Order matters: drain the furthest-along work first so WIP does not pile up
# behind a queue of freshly specced plans.
SWEEP_ROLES="verify test implement spec"

sweep() {
  local spawned=0 role cap running artifact
  for role in $SWEEP_ROLES; do
    cap=$(max_concurrent "$role")
    running=$(role_running "$role")
    [ "$running" -ge "$cap" ] && { wf_event skip "—" "$role: at cap ($running/$cap)"; continue; }

    while IFS= read -r artifact; do
      [ -n "$artifact" ] || continue
      [ "$running" -ge "$cap" ] && break
      if dispatch "$role" "$artifact"; then
        running=$((running + 1))
        spawned=$((spawned + 1))
      fi
    done < <("candidates_$role")
  done

  wf_event sweep "—" "spawned $spawned"
  printf '%s' "$spawned"
}

# ── Modes ─────────────────────────────────────────────────────────────────

DAEMON_PID="$ORCH/daemon.pid"

case "$mode" in

  sweep)
    require_enabled || exit 1
    n=$(sweep)
    echo "sweep: $n worker(s) dispatched"
    exit 0
    ;;

  daemon)
    require_enabled || exit 1
    if [ -f "$DAEMON_PID" ]; then
      old=$(cat "$DAEMON_PID" 2>/dev/null || echo "")
      if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
        echo "wf-orchestrate: daemon already running (PID $old)" >&2
        exit 1
      fi
      rm -f "$DAEMON_PID"
    fi
    echo $$ > "$DAEMON_PID"
    trap 'rm -f "$DAEMON_PID"; wf_event daemon "—" "stopped"; exit 0' INT TERM EXIT
    wf_event daemon "—" "started (interval ${cfg_interval}s)"
    echo "wf-orchestrate: daemon up, sweeping every ${cfg_interval}s. Ctrl-C or --stop to end."
    while true; do
      n=$(sweep)
      [ "$n" -gt 0 ] && echo "$(wf_now)  dispatched $n"
      sleep "$cfg_interval"
    done
    ;;

  stop|kill-all)
    if [ -f "$DAEMON_PID" ]; then
      pid=$(cat "$DAEMON_PID")
      kill "$pid" 2>/dev/null && echo "daemon stopped (PID $pid)" || echo "daemon not running"
      rm -f "$DAEMON_PID"
    else
      echo "daemon not running"
    fi
    if [ "$mode" = "kill-all" ]; then
      for pf in "$ORCH/logs"/*.pid; do
        [ -f "$pf" ] || continue
        wpid=$(cat "$pf" 2>/dev/null || echo "")
        if [ -n "$wpid" ] && kill -0 "$wpid" 2>/dev/null; then
          kill "$wpid" 2>/dev/null && echo "  killed worker PID $wpid ($(basename "$pf" .pid))"
        fi
        rm -f "$pf"
      done
      wf_event daemon "—" "kill-all"
    fi
    exit 0
    ;;

  drive)
    require_enabled || exit 1

    id=$(bare_id "$target")
    [ -n "$id" ] || { echo "Error: '$target' is not a PLN/BUG/BRF id" >&2; exit 1; }

    # A BUG/BRF inherits its number when specced (BUG-094 → PLN-094), so the
    # plan we end up driving is predictable from the source ID.
    num="${id#*-}"
    pln_id="PLN-$num"

    steps=()
    result=""
    gate_info=""
    iterations=0
    MAX_ITERATIONS=12

    while :; do
      iterations=$((iterations + 1))
      if [ "$iterations" -gt "$MAX_ITERATIONS" ]; then
        result="no-progress"; break
      fi

      state=$(plan_state "$pln_id")
      artifact=$(plan_name_of "$pln_id")

      # No plan row yet → this is still a bug or brief awaiting a spec.
      if [ -z "$state" ]; then
        role="spec"; artifact="$target"
      else
        case "$state" in
          draft)          role="spec" ;;
          ready|active)   role="implement" ;;
          verify)         role="verify" ;;
          testing)        role="test" ;;
          complete)       result="done"; break ;;
          *) echo "Error: unknown state '$state' for $pln_id" >&2; exit 1 ;;
        esac
      fi

      # Reached the caller's target?
      if [ -n "$until_state" ] && [ "$state" = "$until_state" ]; then
        result="done"; break
      fi

      # Parked before we even start.
      probe_id="$pln_id"; [ -z "$state" ] && probe_id="$id"
      if gate_open "$probe_id"; then
        gate_info=$(gate_line "$probe_id"); result="blocked-on-human"; break
      fi

      $as_json || echo "→ $role  ($artifact${state:+, state=$state})"

      if $dry_run; then
        steps+=("$role:dry-run")
        result="done"; break
      fi

      rc=0
      "$SELF_DIR/wf-spawn.sh" "$role" "$artifact" --foreground || rc=$?
      attempts_bump "$pln_id" "$role"
      steps+=("$role:rc=$rc")

      if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
        result="error"; break
      fi

      # Did the worker park instead of progressing?
      if gate_open "$pln_id" || gate_open "$id"; then
        probe_id="$pln_id"; gate_open "$pln_id" || probe_id="$id"
        gate_info=$(gate_line "$probe_id"); result="blocked-on-human"; break
      fi

      new_state=$(plan_state "$pln_id")
      if [ "$new_state" = "$state" ]; then
        result="no-progress"; break
      fi
    done

    final_state=$(plan_state "$pln_id")
    [ -n "$final_state" ] || final_state="none"

    if $as_json; then
      printf '{\n'
      printf '  "artifact": "%s",\n' "$target"
      printf '  "plan": "%s",\n' "$pln_id"
      printf '  "state": "%s",\n' "$final_state"
      printf '  "result": "%s",\n' "$result"
      if [ -n "$gate_info" ]; then
        printf '  "gate": { "name": "%s", "question": "%s", "context": "%s" },\n' \
          "$(printf '%s' "$gate_info" | cut -f2)" \
          "$(printf '%s' "$gate_info" | cut -f4 | sed 's/"/\\"/g')" \
          "$(printf '%s' "$gate_info" | cut -f5)"
      fi
      printf '  "steps": ['
      first=true
      for s in "${steps[@]+"${steps[@]}"}"; do
        $first || printf ', '
        printf '"%s"' "$s"; first=false
      done
      printf ']\n}\n'
    else
      echo
      case "$result" in
        done)             echo "✓ $pln_id → $final_state" ;;
        blocked-on-human) echo "⏸ $pln_id → $final_state — GATE: $(printf '%s' "$gate_info" | cut -f2): $(printf '%s' "$gate_info" | cut -f4)" ;;
        no-progress)      echo "⏹ $pln_id → $final_state — no progress" ;;
        error)            echo "✗ $pln_id → $final_state — worker error" ;;
      esac
    fi

    [ "$result" = "done" ] && attempts_reset "$pln_id"

    case "$result" in
      done)             exit 0 ;;
      blocked-on-human) exit 20 ;;
      no-progress)      exit 30 ;;
      *)                exit 1 ;;
    esac
    ;;
esac

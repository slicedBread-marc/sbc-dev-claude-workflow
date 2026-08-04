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

cfg_consistency=$(wf_cfg orchestrator.consistency_pass true)

# --dry-run must leave NO trace. An events.log carrying `sweep — spawned 1`
# from a preview is indistinguishable, when read back, from a real dispatch —
# there is no matching spawn event, pidfile or process to contradict it.
if $dry_run; then
  wf_event() { :; }
fi

max_concurrent() {
  case "$1" in
    spec)        wf_cfg orchestrator.max_concurrent.spec 1 ;;
    implement)   wf_cfg orchestrator.max_concurrent.implement 2 ;;
    verify)      wf_cfg orchestrator.max_concurrent.verify 2 ;;
    test)        wf_cfg orchestrator.max_concurrent.test 1 ;;
    consistency) wf_cfg orchestrator.max_concurrent.consistency 1 ;;
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

# Forward progress — what makes the attempt budget mean something.
#
# The budget counts worker LAUNCHES. Without this, a clean resume of an 11-step
# plan bumps the same counter as a genuine active⇄verify thrash, so long plans
# park as `stuck` with nothing wrong and the only workaround is raising the cap
# until the loop breaker no longer breaks loops.
#
# The signature is (registry state, ticked steps). Either moving means the last
# launch accomplished something, so the budget resets and `max_attempts_per_plan`
# reads as what it claims to be: N launches with NO forward progress.
progress_sig() {
  local id="$1" st cnt con="-"
  st=$(plan_state "$id")
  cnt=$("$SELF_DIR/wf-progress-count.sh" "$id" 2>/dev/null || echo "0/0")
  # A finished consistency pass moves nothing else — the plan stays `ready` —
  # so it has to appear here or a successful pass reads as a stalled worker.
  "$SELF_DIR/wf-list-consistency.sh" "$id" >/dev/null 2>&1 && con="c"
  printf '%s:%s:%s' "${st:-none}" "$cnt" "$con"
}

# Resets the attempt budget when the plan has moved since the last check.
progress_check() {
  local id="$1" sig prev file
  mkdir -p "$ORCH/progress"
  file="$ORCH/progress/$id"
  sig=$(progress_sig "$id")
  prev=$(cat "$file" 2>/dev/null || echo "")
  if [ -n "$prev" ] && [ "$sig" != "$prev" ]; then
    attempts_reset "$id"
    wf_event progress "$id" "forward progress $prev → $sig — attempt budget reset"
  fi
  printf '%s' "$sig" > "$file"
}

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

# Why a skip is latched rather than logged.
#
# Every skip reason is a STANDING condition, not an event: a gate stays open,
# a role stays at cap, an exhausted budget stays exhausted. Logging one line
# per candidate per sweep therefore records the same fact once per interval
# forever — 1,583 identical `skip PLN-002 spec: gate open` lines in 26 hours in
# one measured run, 4,747 lines in the file. This is the same unbounded-growth
# defect the sweep-line latch fixed, one level down: silencing the summary while
# every line it summarised still fires just moves the noise.
#
# skip_note writes only when the reason for a (role, artifact) pair first
# appears or CHANGES, so a transition is always visible and a steady state is
# silent. skip_clear drops the latch the moment the pair dispatches, so a plan
# that is gated, freed and gated again is reported both times.
# skip_note <role> <artifact-id> <reason> [event-kind]
skip_note() {
  local role="$1" id="$2" reason="$3" kind="${4:-skip}" file prev
  # A preview must leave no trace — latch files included (see --dry-run above).
  $dry_run && return 0
  mkdir -p "$ORCH/skips"
  file="$ORCH/skips/${role}.${id}"
  prev=$(cat "$file" 2>/dev/null || echo "")
  [ "$reason" = "$prev" ] && return 0
  printf '%s' "$reason" > "$file"
  wf_event "$kind" "$id" "$role: $reason"
}

skip_clear() {
  $dry_run && return 0
  rm -f "$ORCH/skips/${1}.${2}" 2>/dev/null || true
}

# dispatch <role> <artifact> — run every skip rule, then spawn.
# Returns 0 if a worker was spawned, 1 if skipped.
dispatch() {
  local role="$1" artifact="$2"
  local id; id=$(bare_id "$artifact")

  if gate_open "$id"; then
    skip_note "$role" "$id" "gate open"
    return 1
  fi

  # Did anything move since we last looked? If so the budget starts over.
  progress_check "$id"

  local attempts; attempts=$(attempts_get "$id" "$role")
  if [ "$attempts" -ge "$cfg_max_attempts" ]; then
    # Opening the gate is a real mutation — a preview must not do it either.
    if ! $dry_run && ! gate_open "$id"; then
      "$SELF_DIR/wf-gate-open.sh" "$artifact" stuck \
        "$role has run $attempts times with no forward progress — neither the registry state nor the progress.md step checklist moved. Needs a human look." \
        --skill "wf-$role" >/dev/null 2>&1 || true
    fi
    skip_note "$role" "$id" "$attempts attempts without progress, parked" stuck
    return 1
  fi

  if [ "$(spawn_budget_left)" -le 0 ]; then
    skip_note "$role" "$id" "hourly spawn budget exhausted ($cfg_max_spawns)" budget
    return 1
  fi

  # Past every guard — whatever was holding this pair back no longer is, so the
  # next time one does, it is news again.
  skip_clear "$role" "$id"

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

candidates_consistency() {
  [ "$cfg_consistency" = "true" ] || return 0
  "$SELF_DIR/wf-list-consistency.sh" 2>/dev/null | awk -F'\t' 'NF { print $1 }' || true
}

candidates_implement() {
  # Types: new | resume | fix are actionable; processing (claimed elsewhere)
  # and blocked (deps) are not.
  local pending
  pending=$(candidates_consistency)

  "$SELF_DIR/wf-list-implementable.sh" 2>/dev/null \
    | awk -F'\t' '$1 == "new" || $1 == "resume" || $1 == "fix" { print $2 }' \
    | while IFS= read -r name; do
        # A plan still owing a consistency pass is not implementable yet —
        # building it first is what turns a cheap amendment into a migration.
        printf '%s\n' "$pending" | grep -qx "$name" && continue
        printf '%s\n' "$name"
      done || true
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
# `consistency` sits ahead of `implement`: a cross-plan contradiction caught
# while both plans are still documents is an amendment; caught after one is
# built, it is a migration.
SWEEP_ROLES="verify test consistency implement spec"

# sweep() reports its count in SWEPT, not on stdout.
#
# It used to `printf '%s' "$spawned"` and be called as `n=$(sweep)`. Everything
# dispatch() and wf-spawn.sh printed landed inside that substitution too, so a
# sweep that actually dispatched something returned the spawn message with the
# count glued on the end, and the daemon's `[ "$n" -gt 0 ]` failed every time
# with "integer expression expected" — the one branch that reports progress was
# unreachable precisely when there was progress to report. An out-of-band
# result channel makes that class of bug impossible rather than fixing one case.
SWEPT=0

sweep() {
  local spawned=0 role cap running artifact
  for role in $SWEEP_ROLES; do
    cap=$(max_concurrent "$role")
    running=$(role_running "$role")
    # Latched on the same principle as the per-artifact skips: "at cap" is a
    # standing condition. The reason carries the counts, so a change in how
    # full the role is still surfaces.
    if [ "$running" -ge "$cap" ]; then
      skip_note "$role" cap "at cap ($running/$cap)"
      continue
    fi
    skip_clear "$role" cap

    while IFS= read -r artifact; do
      [ -n "$artifact" ] || continue
      [ "$running" -ge "$cap" ] && break
      if dispatch "$role" "$artifact"; then
        running=$((running + 1))
        spawned=$((spawned + 1))
      fi
    done < <("candidates_$role")
  done

  # Only a sweep that did something is worth an event. A daemon writes one
  # sweep per interval whether or not anything moved, so at the shipped 60s
  # this was ~1,440 identical `spawned 0` lines a day — 146 KB in one measured
  # run — whose entire content was "a human has not looked yet".
  if [ "$spawned" -gt 0 ]; then
    wf_event sweep "—" "spawned $spawned"
  fi
  SWEPT=$spawned
}

# A daemon that sweeps, spawns nothing and has no workers live is not idle —
# it is STALLED. Every candidate is behind a gate or an unmet dep, and nothing
# will change until a human acts. Say so once, name what is responsible, and
# stay quiet until the situation actually changes. Total stall is the one
# condition worth notifying on: unambiguous, never self-correcting, and every
# minute spent in it is wasted wall-clock.
stall_note() {
  local gates sig prev file
  file="$ORCH/stalled"
  gates=$("$SELF_DIR/wf-list-gates.sh" 2>/dev/null \
          | awk -F'\t' '{ printf "%s(%s, blocking %s) ", $1, $2, $6 }' || true)
  sig="${gates:-none}"
  prev=$(cat "$file" 2>/dev/null || echo "")
  [ "$sig" = "$prev" ] && return 0
  printf '%s' "$sig" > "$file"
  if [ -n "$gates" ]; then
    wf_event stalled "—" "nothing dispatchable; every candidate is gated or dep-blocked behind: $gates"
    echo "$(wf_now)  STALLED — waiting on: $gates"
  else
    wf_event stalled "—" "nothing dispatchable and no gates open — the pipeline is empty or complete"
    echo "$(wf_now)  idle — nothing to dispatch"
  fi
}

# Live workers across every role.
workers_live() {
  local role n=0
  for role in $SWEEP_ROLES; do n=$(( n + $(role_running "$role") )); done
  printf '%s' "$n"
}

# ── Modes ─────────────────────────────────────────────────────────────────

DAEMON_PID="$ORCH/daemon.pid"

case "$mode" in

  sweep)
    require_enabled || exit 1
    sweep
    if $dry_run; then
      echo "sweep: $SWEPT worker(s) would be dispatched (dry run — nothing spawned, nothing logged)"
    else
      echo "sweep: $SWEPT worker(s) dispatched"
    fi
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

    # Clearing the trap first is what stops the handler running twice: on
    # SIGTERM it fires for TERM, and its own `exit 0` then fires it again
    # through EXIT — two "stopped" events, and two attempts to delete a pidfile
    # that by then may belong to a replacement daemon.
    #
    # The ownership test is the other half. An unconditional `rm -f` from an
    # outgoing daemon deletes its successor's pidfile, after which wf-board
    # reports "daemon: off" while the successor is still sweeping and the next
    # --stop finds nothing to stop.
    daemon_shutdown() {
      trap - INT TERM EXIT
      if [ "$(cat "$DAEMON_PID" 2>/dev/null || echo "")" = "$$" ]; then
        rm -f "$DAEMON_PID"
      fi
      wf_event daemon "—" "stopped"
      exit 0
    }
    trap daemon_shutdown INT TERM EXIT

    wf_event daemon "—" "started (interval ${cfg_interval}s)"
    echo "wf-orchestrate: daemon up, sweeping every ${cfg_interval}s. Ctrl-C or --stop to end."
    echo "wf-orchestrate: config is read once, at startup — restart to pick up claude-workflow.yml changes."
    while true; do
      sweep
      if [ "$SWEPT" -gt 0 ]; then
        echo "$(wf_now)  dispatched $SWEPT"
        rm -f "$ORCH/stalled"          # next stall is a fresh one, announce it
      elif [ "$(workers_live)" -eq 0 ]; then
        stall_note
      else
        rm -f "$ORCH/stalled"          # work is in flight; not stalled
      fi
      # Backgrounded so the trap fires now rather than whenever the interval
      # happens to elapse. Bash defers a trap until a FOREGROUND child returns,
      # so a plain `sleep 60` kept the daemon alive for up to a full interval
      # after --stop reported it dead — long enough to overlap its replacement.
      sleep "$cfg_interval" &
      wait $! || true
    done
    ;;

  stop|kill-all)
    if [ -f "$DAEMON_PID" ]; then
      pid=$(cat "$DAEMON_PID" 2>/dev/null || echo "")
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        # Wait for it to actually go. Printing "stopped" the instant SIGTERM is
        # delivered is a lie the caller acts on — it starts a replacement, and
        # for a while two daemons sweep the same registry.
        waited=0
        while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 15 ]; do
          sleep 1
          waited=$((waited + 1))
        done
        if kill -0 "$pid" 2>/dev/null; then
          kill -9 "$pid" 2>/dev/null || true
          echo "daemon killed (PID $pid — no exit ${waited}s after SIGTERM)"
        else
          echo "daemon stopped (PID $pid)"
        fi
      else
        echo "daemon not running (clearing stale pidfile)"
      fi
      # The daemon's own trap removes the pidfile when it owns it. Only clear
      # what is left over, and only if it is still the pid we just stopped.
      if [ "$(cat "$DAEMON_PID" 2>/dev/null || echo "")" = "$pid" ]; then
        rm -f "$DAEMON_PID"
      fi
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
          ready)
            # Owe a cross-plan check? Do it before anything is built.
            if [ "$cfg_consistency" = "true" ] && "$SELF_DIR/wf-list-consistency.sh" "$pln_id" >/dev/null 2>&1; then
              role="consistency"
            else
              role="implement"
            fi
            ;;
          active)         role="implement" ;;
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

      sig_before=$(progress_sig "$pln_id")

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

      # A worker that ticked steps but did not change state is still advancing
      # a long plan — keep driving it. Only a launch that moved NOTHING (state
      # and step checklist both unchanged) counts as no-progress.
      if [ "$(progress_sig "$pln_id")" = "$sig_before" ]; then
        result="no-progress"; break
      fi
      attempts_reset "$pln_id"
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

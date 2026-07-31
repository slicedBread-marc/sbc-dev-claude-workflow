#!/usr/bin/env bash
# orchestrator.sh — tests for the orchestrator: locking, gates, dispatch.
#
# Dispatch tests put a STUB `claude` binary first on PATH. It records its argv
# and simulates the state transition a real worker would make, so every bit of
# dispatcher logic is exercised for zero tokens.
#
# Usage: ./tests/orchestrator.sh
# Exit 0 if all pass, 1 otherwise.

set -uo pipefail

# ── Paths ──────────────────────────────────────────────────────────────
LIB_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB_SCRIPTS="$LIB_ROOT/scripts"
SCRIPT_FOLDER=$(awk '{sub(/#.*/, "")} NF >= 2 {folder = $2} END {print folder}' "$LIB_SCRIPTS/version-map.txt")
[ -n "$SCRIPT_FOLDER" ] || { echo "cannot resolve script folder from version-map.txt" >&2; exit 1; }
# WF_TEST_SCRIPT_DIR points the suite at an alternate copy of the scripts —
# used to prove these assertions actually fail against pre-fix code.
SCRIPT_DIR="${WF_TEST_SCRIPT_DIR:-$LIB_SCRIPTS/$SCRIPT_FOLDER}"

TEST_DIR=""
PASS=0
FAIL=0

# ── Helpers ────────────────────────────────────────────────────────────
# Must end truthy — an EXIT trap's status becomes the script's exit status.
cleanup() {
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then rm -rf "$TEST_DIR"; fi
  return 0
}
trap cleanup EXIT

section() { printf '\n\033[1m── %s ──\033[0m\n' "$1"; }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf '  \033[32m✓\033[0m %s\n' "$label"; PASS=$((PASS + 1))
  else
    printf '  \033[31m✗\033[0m %s\n      expected: %s\n      actual:   %s\n' "$label" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_ok() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  \033[32m✓\033[0m %s\n' "$label"; PASS=$((PASS + 1))
  else
    printf '  \033[31m✗\033[0m %s (command failed)\n' "$label"; FAIL=$((FAIL + 1))
  fi
}

assert_fails() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  \033[31m✗\033[0m %s (expected failure, got success)\n' "$label"; FAIL=$((FAIL + 1))
  else
    printf '  \033[32m✓\033[0m %s\n' "$label"; PASS=$((PASS + 1))
  fi
}

setup_repo() {
  TEST_DIR=$(mktemp -d)
  cd "$TEST_DIR" || exit 1
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  mkdir -p plans/briefs bugs/open bugs/triaged bugs/closed .claude

  cat > plans/REGISTRY.md << 'SEED'
# Plan Registry

| ID | Slug | State | Priority | Branch | Updated | WF | Tags | Deps |
|-|-|-|-|-|-|-|-|-|

<!-- Counter: 1 -->
SEED

  cat "$LIB_ROOT/VERSION" > .claude/workflow-version
  git add -A >/dev/null 2>&1
  git commit -qm "seed" >/dev/null 2>&1
}

# Insert a registry row above the counter comment.
registry_add_row() {
  local id="$1" slug="$2" state="${3:-draft}"
  awk -v row="| $id | $slug | $state | — | — | 2026-04-07 | ${SCRIPT_FOLDER#v} | — | — |" '
    /<!-- Counter:/ && !done { print row; done = 1 }
    { print }
  ' plans/REGISTRY.md > plans/REGISTRY.tmp && mv plans/REGISTRY.tmp plans/REGISTRY.md
  mkdir -p "plans/$id-$slug"
  printf '# %s-%s\n\n## Goal\nTest goal for %s\n' "$id" "$slug" "$id" > "plans/$id-$slug/plan.md"
}

# Read column n of a registry row, whitespace-trimmed.
registry_col() {
  grep "^| $1 |" plans/REGISTRY.md | head -1 | awk -F'|' -v n="$2" '{print $n}' | xargs
}

# ═══════════════════════════════════════════════════════════════════════
setup_repo

section "Lock basics"

assert_ok "wf-lock.sh is executable" test -x "$SCRIPT_DIR/wf-lock.sh"

# Acquire in a subshell, confirm the lock dir appears while held.
lockroot="$(git rev-parse --git-common-dir)/wf-locks"
(
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/wf-lock.sh"
  wf_lock_acquire testlock
  [ -d "$lockroot/testlock" ] || exit 1
)
assert_eq "lock dir created while held" "0" "$?"
assert_eq "lock released on exit" "false" "$([ -d "$lockroot/testlock" ] && echo true || echo false)"

# A dead owner must not wedge the lock.
mkdir -p "$lockroot/stale"
echo "999999" > "$lockroot/stale/pid"       # PID that cannot be alive
date +%s > "$lockroot/stale/ts"
(
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/wf-lock.sh"
  WF_LOCK_TIMEOUT=3 wf_lock_acquire stale
) >/dev/null 2>&1
assert_eq "stale lock reclaimed when owner PID is dead" "0" "$?"

# A live owner must block, then time out rather than hang forever.
mkdir -p "$lockroot/busy"
echo $$ > "$lockroot/busy/pid"
date +%s > "$lockroot/busy/ts"
out=$(
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/wf-lock.sh"
  WF_LOCK_TIMEOUT=2 WF_LOCK_TTL=9999 wf_lock_acquire busy 2>&1
  echo "rc=$?"
)
assert_eq "live lock blocks and times out" "true" "$(echo "$out" | grep -q 'rc=1' && echo true || echo false)"
rm -rf "$lockroot/busy"

# Re-entrancy: a child that acquires the same lock must not deadlock.
out=$(
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/wf-lock.sh"
  wf_lock_acquire reentrant
  WF_LOCK_TIMEOUT=3 bash -c "source '$SCRIPT_DIR/wf-lock.sh'; wf_lock_acquire reentrant && echo NESTED_OK"
)
assert_eq "re-entrant acquire from a child is a no-op" "NESTED_OK" "$out"

section "Counter is race-free"

# The sharpest edge: two concurrent specs must not be handed the same ID.
# Without the registry lock this collides on essentially every run.
"$SCRIPT_DIR/wf-counter-next.sh" PLN > /tmp/wf-c1.$$ 2>/dev/null &
p1=$!
"$SCRIPT_DIR/wf-counter-next.sh" PLN > /tmp/wf-c2.$$ 2>/dev/null &
p2=$!
wait $p1 $p2
id1=$(cat /tmp/wf-c1.$$); id2=$(cat /tmp/wf-c2.$$)
rm -f /tmp/wf-c1.$$ /tmp/wf-c2.$$
assert_eq "concurrent counter calls yield distinct IDs" "true" \
  "$([ -n "$id1" ] && [ -n "$id2" ] && [ "$id1" != "$id2" ] && echo true || echo false)"
assert_eq "counter advanced by exactly 2" "3" \
  "$(grep -oE 'Counter: [0-9]+' plans/REGISTRY.md | grep -oE '[0-9]+')"

section "Registry writes are portable and column-exact"

registry_add_row PLN-010 alpha draft
registry_add_row PLN-011 beta draft

assert_ok "state update" "$SCRIPT_DIR/wf-registry-update.sh" PLN-010 draft ready
assert_eq "state written to column 4" "ready" "$(registry_col PLN-010 4)"
assert_eq "sibling row untouched" "draft" "$(registry_col PLN-011 4)"

assert_ok "branch update" "$SCRIPT_DIR/wf-registry-update.sh" PLN-010 ready active feature/PLN-010-alpha
assert_eq "branch written to column 6" "feature/PLN-010-alpha" "$(registry_col PLN-010 6)"
assert_eq "state advanced" "active" "$(registry_col PLN-010 4)"

assert_ok "priority set" "$SCRIPT_DIR/wf-set-priority.sh" PLN-010 urgent
assert_eq "priority written to column 5" "urgent" "$(registry_col PLN-010 5)"
assert_eq "branch survived priority write" "feature/PLN-010-alpha" "$(registry_col PLN-010 6)"

assert_ok "branch cleared with '-'" "$SCRIPT_DIR/wf-registry-update.sh" PLN-010 active verify -
assert_eq "branch cleared to em-dash" "—" "$(registry_col PLN-010 6)"

# Prefix-collision guard: PLN-01 must not match PLN-010 / PLN-011.
assert_fails "prefix ID does not match a longer row" \
  "$SCRIPT_DIR/wf-registry-update.sh" PLN-01 verify testing

section "Prefix-safe column writes"

# PLN-1 is a strict string prefix of PLN-11, so a regex field match (`$2 ~ id`)
# writes both rows. Only an exact, trimmed comparison gets this right.
registry_add_row PLN-1 gamma draft
registry_add_row PLN-11 delta draft

assert_ok "tags on the short ID" "$SCRIPT_DIR/wf-set-tags.sh" PLN-1 infra
assert_eq "PLN-1 got the tag" "infra" "$(registry_col PLN-1 9)"
assert_eq "PLN-11 tags NOT overwritten by the PLN-1 write" "—" "$(registry_col PLN-11 9)"

assert_ok "deps on the short ID" "$SCRIPT_DIR/wf-set-deps.sh" PLN-1 PLN-011
assert_eq "PLN-1 got the dep" "PLN-011" "$(registry_col PLN-1 10)"
assert_eq "PLN-11 deps NOT overwritten by the PLN-1 write" "—" "$(registry_col PLN-11 10)"

assert_ok "priority on the short ID" "$SCRIPT_DIR/wf-set-priority.sh" PLN-1 urgent
assert_eq "PLN-1 got the priority" "urgent" "$(registry_col PLN-1 5)"
assert_eq "PLN-11 priority NOT overwritten by the PLN-1 write" "—" "$(registry_col PLN-11 5)"

section "Config reader"

cat > claude-workflow.yml << 'YML'
project_slug: "demo"
orchestrator:
  enabled: true
  sweep_interval: 45
  max_concurrent:
    implement: 2
    spec: 1
  models:
    spec: opus
    implement: sonnet
YML

cfg() { bash -c "source '$SCRIPT_DIR/wf-orch-lib.sh'; wf_cfg $1 ${2:-}"; }
assert_eq "top-level scalar"        "demo"   "$(cfg project_slug NONE)"
assert_eq "nested scalar"           "45"     "$(cfg orchestrator.sweep_interval 60)"
assert_eq "two levels deep"         "2"      "$(cfg orchestrator.max_concurrent.implement 1)"
assert_eq "sibling subtree not confused" "opus" "$(cfg orchestrator.models.spec haiku)"
assert_eq "missing key falls back"  "haiku"  "$(cfg orchestrator.models.test haiku)"
assert_eq "missing branch falls back" "5"    "$(cfg orchestrator.nope.nope 5)"

section "Gates"

assert_fails "no gates open initially" "$SCRIPT_DIR/wf-list-gates.sh"

# The question deliberately carries an apostrophe and a semicolon — gate files
# are eval'd, and unquoted values are exactly what BUG-094 was.
assert_ok "open a gate" "$SCRIPT_DIR/wf-gate-open.sh" PLN-010-alpha spec-approval \
  "It's 8 steps; approve?" --context plans/PLN-010-alpha/plan.md --skill wf-spec
assert_ok "probe finds the open gate" "$SCRIPT_DIR/wf-list-gates.sh" PLN-010
assert_fails "probe misses an ungated plan" "$SCRIPT_DIR/wf-list-gates.sh" PLN-011

gate_row=$("$SCRIPT_DIR/wf-list-gates.sh" PLN-010 2>/dev/null)
assert_eq "gate name in probe output" "spec-approval" "$(printf '%s' "$gate_row" | cut -f2)"
assert_eq "question survives quotes and semicolons" "It's 8 steps; approve?" \
  "$(printf '%s' "$gate_row" | cut -f4)"
assert_eq "context recorded" "plans/PLN-010-alpha/plan.md" "$(printf '%s' "$gate_row" | cut -f5)"

# Re-opening the same gate must not reset queue position.
opened_first=$(printf '%s' "$gate_row" | cut -f3)
sleep 1
"$SCRIPT_DIR/wf-gate-open.sh" PLN-010 spec-approval "different wording" >/dev/null 2>&1
opened_again=$("$SCRIPT_DIR/wf-list-gates.sh" PLN-010 2>/dev/null | cut -f3)
assert_eq "re-opening the same gate keeps the original timestamp" "$opened_first" "$opened_again"

# Queue is FIFO by open time.
"$SCRIPT_DIR/wf-gate-open.sh" PLN-011-beta manual-test "does /play feel smooth?" >/dev/null 2>&1
assert_eq "queue is oldest-first" "PLN-010" "$("$SCRIPT_DIR/wf-list-gates.sh" 2>/dev/null | head -1 | cut -f1)"
assert_eq "both gates listed" "2" "$("$SCRIPT_DIR/wf-list-gates.sh" 2>/dev/null | wc -l | xargs)"

assert_ok "close a gate" "$SCRIPT_DIR/wf-gate-close.sh" PLN-010 approved
assert_fails "closed gate no longer probes open" "$SCRIPT_DIR/wf-list-gates.sh" PLN-010
assert_ok "closing an already-closed gate is a no-op" "$SCRIPT_DIR/wf-gate-close.sh" PLN-010
assert_fails "a bad artifact id is rejected" "$SCRIPT_DIR/wf-gate-open.sh" NOPE-1 x "y"

section "Events"

log_for() { "$SCRIPT_DIR/wf-event.sh" --for "$1" 2>/dev/null; }
assert_eq "gate-open logged" "1" "$(log_for PLN-010 | awk -F'\t' '$2 == "gate-open"' | wc -l | xargs)"
assert_eq "gate-close logged" "1" "$(log_for PLN-010 | awk -F'\t' '$2 == "gate-close"' | wc -l | xargs)"
assert_eq "--for filters by artifact" "1" "$(log_for PLN-011 | wc -l | xargs)"
"$SCRIPT_DIR/wf-event.sh" spawn PLN-011 "implement (sonnet) pid 999" >/dev/null
assert_eq "arbitrary events append" "2" "$(log_for PLN-011 | wc -l | xargs)"

section "Skill unattended contracts"

SKILLS="$LIB_ROOT/skills"
for s in wf-spec wf-implement wf-test; do
  assert_eq "$s declares an Unattended mode section" "1" \
    "$(grep -c '^## Unattended mode' "$SKILLS/$s/SKILL.md" | xargs)"
  assert_eq "$s tells the worker to open a gate" "true" \
    "$(grep -q 'wf-gate-open.sh' "$SKILLS/$s/SKILL.md" && echo true || echo false)"
  assert_eq "$s forbids guessing" "true" \
    "$(grep -qi 'never guess' "$SKILLS/$s/SKILL.md" && echo true || echo false)"
done
# The one gate that must never become [AUTO].
assert_eq "wf-spec keeps approval as a hard gate" "true" \
  "$(grep -q 'spec-approval' "$SKILLS/wf-spec/SKILL.md" && echo true || echo false)"

section "Dispatcher — selection logic (dry run)"

# Enable the orchestrator for the remaining sections.
cat > claude-workflow.yml << 'YML'
project_slug: "demo"
orchestrator:
  enabled: true
  sweep_interval: 1
  max_concurrent:
    spec: 1
    implement: 2
    verify: 2
    test: 1
  models:
    spec: opus
    implement: sonnet
    verify: sonnet
    test: haiku
  max_attempts_per_plan: 2
  max_spawns_per_hour: 20
YML

ORCH="$(git rev-parse --show-toplevel)/.claude/orchestrator"
rm -rf "$ORCH"; mkdir -p "$ORCH/gates" "$ORCH/logs" "$ORCH/attempts"

# Clean slate: one plan per actionable state.
cat > plans/REGISTRY.md << 'SEED'
# Plan Registry

| ID | Slug | State | Priority | Branch | Updated | WF | Tags | Deps |
|-|-|-|-|-|-|-|-|-|

<!-- Counter: 50 -->
SEED
for spec in "PLN-020 aaa ready" "PLN-021 bbb verify" "PLN-022 ccc testing" "PLN-023 ddd active"; do
  # shellcheck disable=SC2086
  set -- $spec
  registry_add_row "$1" "$2" "$3"
done

orch() { "$SCRIPT_DIR/wf-orchestrate.sh" "$@"; }

plan=$(orch --sweep --dry-run 2>/dev/null)
assert_eq "verify plan selected"    "true" "$(printf '%s' "$plan" | grep -q 'verify PLN-021-bbb'    && echo true || echo false)"
assert_eq "testing plan selected"   "true" "$(printf '%s' "$plan" | grep -q 'test PLN-022-ccc'      && echo true || echo false)"
assert_eq "ready plan selected"     "true" "$(printf '%s' "$plan" | grep -q 'implement PLN-020-aaa' && echo true || echo false)"
assert_eq "active plan selected"    "true" "$(printf '%s' "$plan" | grep -q 'implement PLN-023-ddd' && echo true || echo false)"
# Furthest-along work is dispatched first so WIP does not pile up.
assert_eq "verify dispatched before implement" "true" \
  "$([ "$(printf '%s' "$plan" | grep -n 'verify PLN-021' | cut -d: -f1)" -lt \
       "$(printf '%s' "$plan" | grep -n 'implement PLN-020' | cut -d: -f1)" ] && echo true || echo false)"

# A gate must take the plan out of the running entirely.
"$SCRIPT_DIR/wf-gate-open.sh" PLN-020 spec-approval "approve?" >/dev/null 2>&1
plan=$(orch --sweep --dry-run 2>/dev/null)
assert_eq "gated plan is skipped" "false" \
  "$(printf '%s' "$plan" | grep -q 'implement PLN-020-aaa' && echo true || echo false)"
assert_eq "ungated plans still dispatch" "true" \
  "$(printf '%s' "$plan" | grep -q 'implement PLN-023-ddd' && echo true || echo false)"
"$SCRIPT_DIR/wf-gate-close.sh" PLN-020 approved >/dev/null 2>&1

# Unmet deps must block dispatch.
registry_add_row PLN-024 eee ready
"$SCRIPT_DIR/wf-set-deps.sh" PLN-024 PLN-023 >/dev/null 2>&1
plan=$(orch --sweep --dry-run 2>/dev/null)
assert_eq "dep-blocked plan is skipped" "false" \
  "$(printf '%s' "$plan" | grep -q 'implement PLN-024-eee' && echo true || echo false)"

# max_concurrent must cap a role. implement:2 with three eligible plans.
registry_add_row PLN-025 fff ready
"$SCRIPT_DIR/wf-set-deps.sh" PLN-024 — >/dev/null 2>&1
plan=$(orch --sweep --dry-run 2>/dev/null)
assert_eq "implement capped at max_concurrent 2" "2" \
  "$(printf '%s' "$plan" | grep -c 'would spawn: implement' | xargs)"

# Disabled by default is the safety posture that matters most.
sed 's/enabled: true/enabled: false/' claude-workflow.yml > cfg.tmp && mv cfg.tmp claude-workflow.yml
assert_fails "sweep refuses to run when disabled" orch --sweep
assert_ok "--force overrides disabled" orch --sweep --dry-run --force
sed 's/enabled: false/enabled: true/' claude-workflow.yml > cfg.tmp && mv cfg.tmp claude-workflow.yml

section "Dispatcher — spawning (stub claude)"

# A stub `claude` first on PATH: records its invocation and simulates the state
# transition a real worker would make. Exercises the whole spawn path for zero
# tokens. STUB_MODE picks the behavior being simulated.
STUB_BIN="$TEST_DIR/stubbin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/claude" << STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TEST_DIR/stub-argv.log"
printf 'role=%s artifact=%s unattended=%s\n' "\${WF_ROLE:-}" "\${WF_ARTIFACT:-}" "\${WF_UNATTENDED:-}" >> "$TEST_DIR/stub-env.log"
S="$SCRIPT_DIR"
id=\$(printf '%s' "\${WF_ARTIFACT:-}" | grep -oE '^(PLN|BUG|BRF)-[0-9]+')
case "\${STUB_MODE:-advance}" in
  advance)
    case "\${WF_ROLE:-}" in
      spec)      "\$S/wf-registry-update.sh" "\$id" draft ready   >/dev/null 2>&1 ;;
      implement) st=\$("\$S/wf-plan-info.sh" "\$id" 2>/dev/null | grep "^PLAN_STATE=" | sed "s/PLAN_STATE='//;s/'\$//")
                 "\$S/wf-registry-update.sh" "\$id" "\$st" verify >/dev/null 2>&1 ;;
      verify)    "\$S/wf-registry-update.sh" "\$id" verify testing  >/dev/null 2>&1 ;;
      test)      "\$S/wf-registry-update.sh" "\$id" testing complete >/dev/null 2>&1 ;;
    esac
    ;;
  gate)  "\$S/wf-gate-open.sh" "\$id" manual-test "2 criteria need eyes" >/dev/null 2>&1 ;;
  noop)  : ;;
  fail)  exit 7 ;;
esac
exit 0
STUB
chmod +x "$STUB_BIN/claude"
export PATH="$STUB_BIN:$PATH"

assert_eq "stub claude is first on PATH" "$STUB_BIN/claude" "$(command -v claude)"

# --- drive-one, happy path: ready → implement → verify → test → complete
registry_add_row PLN-030 happy ready
rc=0; orch PLN-030 >/dev/null 2>&1 || rc=$?
assert_eq "drive-one exits 0 on completion" "0" "$rc"
assert_eq "plan reached complete" "complete" "$(registry_col PLN-030 4)"
assert_eq "workers ran unattended" "true" \
  "$(grep -q 'unattended=1' "$TEST_DIR/stub-env.log" && echo true || echo false)"
# Seeded at `ready`, so spec is correctly skipped: implement → verify → test.
assert_eq "the three post-spec roles each ran once" "3" \
  "$(grep -cE 'role=(implement|verify|test) artifact=PLN-030' "$TEST_DIR/stub-env.log" | xargs)"
assert_eq "spec did not run for an already-ready plan" "0" \
  "$(grep -cE 'role=spec artifact=PLN-030' "$TEST_DIR/stub-env.log" | xargs)"
assert_eq "model tier passed through for implement" "true" \
  "$(grep -q -- '--model sonnet' "$TEST_DIR/stub-argv.log" && echo true || echo false)"

# --- drive-one, --until stops early
registry_add_row PLN-031 early ready
rc=0; orch PLN-031 --until verify >/dev/null 2>&1 || rc=$?
assert_eq "--until halts at the requested state" "0" "$rc"
assert_eq "state is the requested one" "verify" "$(registry_col PLN-031 4)"

# --- drive-one, blocked on a human → exit 20
registry_add_row PLN-032 gated testing
rc=0; STUB_MODE=gate orch PLN-032 >/dev/null 2>&1 || rc=$?
assert_eq "drive-one exits 20 when a gate opens" "20" "$rc"
assert_ok "the gate is queued for /wf-attend" "$SCRIPT_DIR/wf-list-gates.sh" PLN-032

json=$(STUB_MODE=gate orch PLN-032 --json 2>/dev/null || true)
assert_eq "--json reports blocked-on-human" "true" \
  "$(printf '%s' "$json" | grep -q '"result": "blocked-on-human"' && echo true || echo false)"
assert_eq "--json names the gate" "true" \
  "$(printf '%s' "$json" | grep -q '"name": "manual-test"' && echo true || echo false)"
"$SCRIPT_DIR/wf-gate-close.sh" PLN-032 done >/dev/null 2>&1

# --- drive-one, worker ran but changed nothing → exit 30
registry_add_row PLN-033 stalled ready
rc=0; STUB_MODE=noop orch PLN-033 >/dev/null 2>&1 || rc=$?
assert_eq "drive-one exits 30 when nothing moved" "30" "$rc"

# --- drive-one, worker failed → exit 1
registry_add_row PLN-034 broken ready
rc=0; STUB_MODE=fail orch PLN-034 >/dev/null 2>&1 || rc=$?
assert_eq "drive-one exits 1 on worker failure" "1" "$rc"

# --- attempt budget parks a thrashing plan instead of looping forever
registry_add_row PLN-035 thrash ready
rm -f "$ORCH/attempts/PLN-035".*
STUB_MODE=noop orch PLN-035 >/dev/null 2>&1 || true
STUB_MODE=noop orch PLN-035 >/dev/null 2>&1 || true
# Mark urgent so the sweep evaluates it before implement hits max_concurrent —
# otherwise the cap short-circuits the loop and this plan is never reached.
"$SCRIPT_DIR/wf-set-priority.sh" PLN-035 urgent >/dev/null 2>&1
plan=$(orch --sweep --dry-run 2>/dev/null || true)
assert_eq "the parked plan is not offered for dispatch" "false" \
  "$(printf '%s' "$plan" | grep -q 'implement PLN-035-thrash' && echo true || echo false)"
assert_ok "plan over its attempt budget is parked as 'stuck'" \
  "$SCRIPT_DIR/wf-list-gates.sh" PLN-035
assert_eq "the gate names the reason" "stuck" \
  "$("$SCRIPT_DIR/wf-list-gates.sh" PLN-035 2>/dev/null | cut -f2)"

# --- one worker per artifact+role, however many callers ask
registry_add_row PLN-036 dup ready
echo $$ > "$ORCH/logs/PLN-036-dup-implement.pid"   # pretend a worker is live
rc=0; "$SCRIPT_DIR/wf-spawn.sh" implement PLN-036-dup >/dev/null 2>&1 || rc=$?
assert_eq "second spawn for a live worker is refused (rc 2)" "2" "$rc"
rm -f "$ORCH/logs/PLN-036-dup-implement.pid"
echo "999999" > "$ORCH/logs/PLN-036-dup-implement.pid"  # dead PID
rc=0; "$SCRIPT_DIR/wf-spawn.sh" implement PLN-036-dup --dry-run >/dev/null 2>&1 || rc=$?
assert_eq "a dead pidfile does not block a respawn" "0" "$rc"

section "Board"

"$SCRIPT_DIR/wf-gate-open.sh" PLN-022-ccc manual-test "does /play feel smooth?" >/dev/null 2>&1
echo $$ > "$ORCH/logs/PLN-021-bbb-verify.pid"
board=$("$SCRIPT_DIR/wf-board.sh" --plain 2>/dev/null)

assert_eq "board renders without error" "0" "$?"
assert_eq "running worker shown with its role" "true" \
  "$(printf '%s' "$board" | grep -q 'verify .*PLN-021-bbb' && echo true || echo false)"
assert_eq "open gate shown" "true" \
  "$(printf '%s' "$board" | grep -q 'manual-test .*PLN-022' && echo true || echo false)"
assert_eq "pipeline counts rendered" "true" \
  "$(printf '%s' "$board" | grep -qE '^  (draft|ready|verify|testing) +[0-9]+' && echo true || echo false)"
assert_eq "recent events rendered" "true" \
  "$(printf '%s' "$board" | grep -q 'RECENT' && echo true || echo false)"
assert_eq "board spawns nothing" "0" \
  "$(printf '%s' "$board" | grep -c 'would spawn' | xargs)"

# A dead pidfile must not be reported as a running worker.
echo "999999" > "$ORCH/logs/PLN-099-dead-implement.pid"
board=$("$SCRIPT_DIR/wf-board.sh" --plain 2>/dev/null)
assert_eq "dead worker is not listed as running" "false" \
  "$(printf '%s' "$board" | grep -q 'PLN-099-dead' && echo true || echo false)"
rm -f "$ORCH/logs/PLN-021-bbb-verify.pid" "$ORCH/logs/PLN-099-dead-implement.pid"
"$SCRIPT_DIR/wf-gate-close.sh" PLN-022 done >/dev/null 2>&1

section "Skills wired up"

for s in wf-board wf-attend wf-orchestrate; do
  assert_ok "$s/SKILL.md exists" test -f "$LIB_ROOT/skills/$s/SKILL.md"
  assert_eq "$s declares frontmatter name" "true" \
    "$(grep -q "^name: $s\$" "$LIB_ROOT/skills/$s/SKILL.md" && echo true || echo false)"
done
# The two rules that keep an autonomous pipeline honest.
assert_eq "wf-attend forbids deciding for the user" "true" \
  "$(grep -qi 'never approve, pass, or reject on the user' "$LIB_ROOT/skills/wf-attend/SKILL.md" && echo true || echo false)"
assert_eq "wf-orchestrate refuses to self-enable" "true" \
  "$(grep -qi 'do \*\*not\*\* flip it to `true`' "$LIB_ROOT/skills/wf-orchestrate/SKILL.md" && echo true || echo false)"

section "Deployed entry-point contract"

WF_TMPL="$LIB_ROOT/templates/WORKFLOW.md"
assert_ok "templates/WORKFLOW.md exists" test -f "$WF_TMPL"
assert_eq "install.sh generates it into the client root" "true" \
  "$(grep -q 'templates/WORKFLOW.md" > "$TARGET_DIR/WORKFLOW.md"' "$LIB_ROOT/install.sh" && echo true || echo false)"
assert_eq "install.sh substitutes both placeholders" "true" \
  "$(grep -q '{{workflow_version}}' "$LIB_ROOT/install.sh" && grep -q '{{project_slug}}' "$LIB_ROOT/install.sh" && echo true || echo false)"

# An external agent reads this file to learn how to drive the pipeline; every
# exit code must be documented or the contract is unusable.
for code in '`0`' '`20`' '`30`' '`1`'; do
  assert_eq "WORKFLOW.md documents exit $code" "true" \
    "$(grep -qF "| $code |" "$WF_TMPL" && echo true || echo false)"
done
assert_eq "WORKFLOW.md warns against retrying on 20" "true" \
  "$(grep -qi 'do not retry' "$WF_TMPL" && echo true || echo false)"
assert_eq "WORKFLOW.md lists the git hooks" "true" \
  "$(grep -q 'post-commit' "$WF_TMPL" && echo true || echo false)"
assert_eq "WORKFLOW.md tells callers to use wf-exec.sh" "true" \
  "$(grep -q 'scripts/wf-exec.sh' "$WF_TMPL" && echo true || echo false)"
assert_eq "install.sh gitignores orchestrator runtime state" "true" \
  "$(grep -q '.claude/orchestrator/' "$LIB_ROOT/install.sh" && echo true || echo false)"

section "Version resolution"

# wf-exec.sh + version-map.txt must be installed for these.
cp "$LIB_SCRIPTS/wf-exec.sh" scripts/wf-exec.sh 2>/dev/null || mkdir -p scripts && cp "$LIB_SCRIPTS/wf-exec.sh" scripts/wf-exec.sh
cp "$LIB_SCRIPTS/version-map.txt" scripts/version-map.txt
mkdir -p "scripts/$SCRIPT_FOLDER"
cp "$SCRIPT_DIR"/*.sh "scripts/$SCRIPT_FOLDER/"
chmod +x scripts/wf-exec.sh "scripts/$SCRIPT_FOLDER"/*.sh

# A probe script reporting which folder it was dispatched from — dropped into
# EVERY mapped folder, so a row that resolves to an older generation is
# measured rather than failing as "script not found".
while read -r _minver folder; do
  case "${_minver:-}" in ''|\#*) continue ;; esac
  mkdir -p "scripts/$folder"
  cat > "scripts/$folder/wf-whichfolder.sh" << 'PROBE'
#!/usr/bin/env bash
basename "$(dirname "$0")"
PROBE
  chmod +x "scripts/$folder/wf-whichfolder.sh"
done < <(sed 's/#.*//' "$LIB_SCRIPTS/version-map.txt")

# Every version-map row must name a folder that actually exists, or dispatch
# fails at runtime for whoever lands on that row.
missing=""
while read -r minver folder; do
  case "$minver" in ''|\#*) continue ;; esac
  [ -d "$LIB_SCRIPTS/$folder" ] || missing="$missing $folder"
done < <(sed 's/#.*//' "$LIB_SCRIPTS/version-map.txt")
assert_eq "every mapped script folder exists" "" "$missing"

# Thresholds must be dotted digits — the same rule wf-exec.sh enforces on input.
bad_rows=$(sed 's/#.*//' "$LIB_SCRIPTS/version-map.txt" \
  | awk 'NF >= 2 && $1 !~ /^[0-9]+(\.[0-9]+)*$/ { print $1 }')
assert_eq "every threshold is dotted digits" "" "$bad_rows"

# Rows must be ascending — wf-exec.sh takes the LAST match, so an out-of-order
# file silently resolves to the wrong folder.
sorted=$(sed 's/#.*//' "$LIB_SCRIPTS/version-map.txt" | awk 'NF >= 2 { print $1 }')
assert_eq "rows are in ascending version order" "$sorted" "$(printf '%s\n' "$sorted" | sort -V)"

# Live WF values seen in the field, plus plausible future ones.
resolves_to() { WF_VERSION="$1" ./scripts/wf-exec.sh wf-whichfolder.sh 2>/dev/null; }
assert_eq "legacy 1.32.13 → v1.x"   "v1.x"  "$(resolves_to 1.32.13)"
assert_eq "legacy 0.00 → v1.x"      "v1.x"  "$(resolves_to 0.00)"
assert_eq "2.00.13 → v2.00"         "v2.00" "$(resolves_to 2.00.13)"
assert_eq "current 2.5.1 → v2.00"   "v2.00" "$(resolves_to 2.5.1)"
# The trap the map header warns about: a 2.10 minor must not fall back to v1.x.
assert_eq "future 2.10.0 → v2.00"   "v2.00" "$(resolves_to 2.10.0)"
assert_eq "future 3.0.0 → v2.00"    "v2.00" "$(resolves_to 3.0.0)"

# A bogus explicit override is a typo — fail loudly rather than route oddly.
assert_fails "non-version WF_VERSION is rejected" \
  env WF_VERSION="—" ./scripts/wf-exec.sh wf-whichfolder.sh
assert_fails "garbage WF_VERSION is rejected" \
  env WF_VERSION="latest" ./scripts/wf-exec.sh wf-whichfolder.sh

# A plan stamped with the registry's em-dash must be treated as UNSTAMPED and
# fall back — not sort above every row and grab the newest folder.
echo "2.5.1" > .claude/workflow-version
registry_add_row PLN-040 dashwf ready
awk -F'|' -v OFS='|' '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  trim($2) == "PLN-040" { $8 = " — " } { print }
' plans/REGISTRY.md > r.tmp && mv r.tmp plans/REGISTRY.md
assert_eq "em-dash WF falls back to the project version" "v2.00" \
  "$(./scripts/wf-exec.sh wf-whichfolder.sh PLN-040 2>/dev/null)"

# Same for a blank stamp — the 61 unstamped plans in the field rely on this.
registry_add_row PLN-041 blankwf ready
awk -F'|' -v OFS='|' '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  trim($2) == "PLN-041" { $8 = "  " } { print }
' plans/REGISTRY.md > r.tmp && mv r.tmp plans/REGISTRY.md
assert_eq "blank WF falls back to the project version" "v2.00" \
  "$(./scripts/wf-exec.sh wf-whichfolder.sh PLN-041 2>/dev/null)"

# A real stamp still pins, which is the entire point of the column.
registry_add_row PLN-042 pinned ready
awk -F'|' -v OFS='|' '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  trim($2) == "PLN-042" { $8 = " 1.32.13 " } { print }
' plans/REGISTRY.md > r.tmp && mv r.tmp plans/REGISTRY.md
assert_eq "a stamped plan stays pinned to its generation" "v1.x" \
  "$(./scripts/wf-exec.sh wf-whichfolder.sh PLN-042 2>/dev/null)"

section "Workflow issue reporting"

rm -f WORKFLOW-ISSUES.md
assert_eq "clean client reports zero open" "0" "$("$SCRIPT_DIR/wf-issue.sh" --count)"

# A real report carries a multi-line error and an apostrophe — awk -v cannot
# hold either, which is how the first implementation broke.
multi=$(printf "Error: PLN-097 not found in state 'active'\n  at wf-registry-update.sh:88")
assert_ok "file an issue" "$SCRIPT_DIR/wf-issue.sh" \
  --source wf-implement --expected "active→verify to succeed" --actual "$multi" \
  --context "PLN-097, feature/PLN-097-foo" --notes "Registry already showed verify."
assert_ok "file a second" "$SCRIPT_DIR/wf-issue.sh" \
  --source wf-list-testable.sh --expected "one row per testing plan" --actual "awk: cannot open"

assert_eq "count reflects both, on one line" "2" "$("$SCRIPT_DIR/wf-issue.sh" --count)"
assert_eq "IDs increment" "true" \
  "$(grep -q '^## WFI-001 ' WORKFLOW-ISSUES.md && grep -q '^## WFI-002 ' WORKFLOW-ISSUES.md && echo true || echo false)"
assert_eq "newest is first" "WFI-002" \
  "$(grep -m1 -oE 'WFI-[0-9]+' WORKFLOW-ISSUES.md)"
assert_eq "multi-line error preserved verbatim" "true" \
  "$(grep -q 'at wf-registry-update.sh:88' WORKFLOW-ISSUES.md && echo true || echo false)"
assert_eq "apostrophe survives" "true" \
  "$(grep -q "state 'active'" WORKFLOW-ISSUES.md && echo true || echo false)"
assert_eq "workflow version recorded" "true" \
  "$(grep -q '^\*\*Workflow version:\*\*' WORKFLOW-ISSUES.md && echo true || echo false)"
assert_eq "header survives an append" "true" \
  "$(head -1 WORKFLOW-ISSUES.md | grep -q '^# Workflow Issues' && echo true || echo false)"

# Resolution takes an entry out of the open set without deleting the record.
assert_ok "resolve an issue" "$SCRIPT_DIR/wf-issue.sh" --resolve WFI-001 "fixed in v2.6.0"
assert_eq "open count drops" "1" "$("$SCRIPT_DIR/wf-issue.sh" --count)"
assert_eq "--list shows only open" "1" \
  "$("$SCRIPT_DIR/wf-issue.sh" --list | grep -c '^## WFI-' | xargs)"
assert_eq "--list --all shows both" "2" \
  "$("$SCRIPT_DIR/wf-issue.sh" --list --all | grep -c '^## WFI-' | xargs)"
assert_eq "resolved entry is retained as a record" "true" \
  "$(grep -q 'fixed in v2.6.0' WORKFLOW-ISSUES.md && echo true || echo false)"

assert_fails "missing --actual is rejected" "$SCRIPT_DIR/wf-issue.sh" --source wf-spec
assert_fails "missing --source is rejected" "$SCRIPT_DIR/wf-issue.sh" --actual "boom"

# Concurrent filing must not lose a report — several workers can hit the same
# harness bug at once.
rm -f WORKFLOW-ISSUES.md
"$SCRIPT_DIR/wf-issue.sh" --source a --expected e --actual x1 >/dev/null 2>&1 &
"$SCRIPT_DIR/wf-issue.sh" --source b --expected e --actual x2 >/dev/null 2>&1 &
"$SCRIPT_DIR/wf-issue.sh" --source c --expected e --actual x3 >/dev/null 2>&1 &
wait
assert_eq "three concurrent reports all land" "3" "$("$SCRIPT_DIR/wf-issue.sh" --count)"
assert_eq "no duplicate IDs under concurrency" "3" \
  "$(grep -oE '^## WFI-[0-9]+' WORKFLOW-ISSUES.md | sort -u | wc -l | xargs)"

section "Issue reporting is wired into the skills"

for s in wf-spec wf-implement wf-test wf-verify; do
  assert_eq "$s tells the worker to file harness problems" "true" \
    "$(grep -q 'wf-issue.sh' "$LIB_ROOT/skills/$s/SKILL.md" && echo true || echo false)"
done
assert_eq "the ambient CLAUDE.md rule exists" "true" \
  "$(grep -q 'wf-issue.sh' "$LIB_ROOT/claude-md/workflow-snippet.md" && echo true || echo false)"
assert_eq "WORKFLOW.md documents the channel for external agents" "true" \
  "$(grep -q 'wf-issue.sh' "$LIB_ROOT/templates/WORKFLOW.md" && echo true || echo false)"
# The distinction that keeps this channel signal rather than noise: without an
# explicit "do not file" list, every failing app test becomes a workflow issue.
assert_eq "guidance has a 'File it when' list" "true" \
  "$(grep -q '\*\*File it when:\*\*' "$LIB_ROOT/claude-md/workflow-snippet.md" && echo true || echo false)"
assert_eq "guidance has a 'Do not file' list" "true" \
  "$(grep -q '\*\*Do not file:\*\*' "$LIB_ROOT/claude-md/workflow-snippet.md" && echo true || echo false)"
assert_eq "app build/test failures are excluded by name" "true" \
  "$(grep -qi 'application build or test failures' "$LIB_ROOT/claude-md/workflow-snippet.md" && echo true || echo false)"
assert_eq "plan findings are excluded by name" "true" \
  "$(grep -qi 'findings.md' "$LIB_ROOT/claude-md/workflow-snippet.md" && echo true || echo false)"
assert_ok "library sweep script is executable" test -x "$LIB_ROOT/sweep-issues.sh"

section "Library sweep across clients"

# Two fake clients with their own issue files; WF_DEPLOYMENTS keeps the real
# deployments.txt out of it.
SWEEP_A="$TEST_DIR/client-a"; SWEEP_B="$TEST_DIR/client-b"
mkdir -p "$SWEEP_A" "$SWEEP_B"
printf '%s\n%s\n' "$SWEEP_A" "$SWEEP_B" > "$TEST_DIR/deployments.txt"
export WF_DEPLOYMENTS="$TEST_DIR/deployments.txt"
sweep() { "$LIB_ROOT/sweep-issues.sh" "$@"; }

# Clean clients: no issue files at all.
assert_fails "sweep exits 1 when every client is clean" sweep
assert_eq "count is zero for a client with no issue file" "0" \
  "$(sweep --count | awk -F': ' '$1 == "client-a" { print $2 }')"

mk_issue() {  # <dir> <id> <status>
  local d="$1" id="$2" status="$3"
  [ -f "$d/WORKFLOW-ISSUES.md" ] || printf '# Workflow Issues\n\n<!-- New entries are inserted directly below this line, newest first. -->\n' > "$d/WORKFLOW-ISSUES.md"
  printf '\n## %s — wf-implement — 2026-07-31T00:00:00Z\n\n**Status:** %s\n**Context:** —\n\n**Expected:**\ne\n\n**Actual:**\n```\nboom\n```\n' \
    "$id" "$status" >> "$d/WORKFLOW-ISSUES.md"
}
mk_issue "$SWEEP_A" WFI-001 open
mk_issue "$SWEEP_B" WFI-001 open
mk_issue "$SWEEP_B" WFI-002 "resolved 2026-07-30 — fixed"

assert_ok "sweep exits 0 when there is work" sweep
assert_eq "per-client open counts"  "1" "$(sweep --count | awk -F': ' '$1 == "client-a" { print $2 }')"
assert_eq "resolved entries are not counted" "1" "$(sweep --count | awk -F': ' '$1 == "client-b" { print $2 }')"
assert_eq "counts are single-valued, not doubled lines" "2" "$(sweep --count | wc -l | xargs)"
assert_eq "output groups by client" "2" \
  "$(sweep 2>/dev/null | grep -c 'client-[ab] (' | xargs)"
# Match on the issue heading, not on words like "fixed" — the sweep's own
# footer help text contains "fixed in vX.Y.Z" and would match anywhere.
assert_eq "default view hides resolved entries" "0" \
  "$(sweep 2>/dev/null | grep -c '^## WFI-002 ' | xargs)"
assert_eq "default view shows the open ones from both clients" "2" \
  "$(sweep 2>/dev/null | grep -c '^## WFI-001 ' | xargs)"
assert_eq "--all reveals resolved entries" "1" \
  "$(sweep --all 2>/dev/null | grep -c '^## WFI-002 ' | xargs)"

# A dead path in deployments.txt must be skipped, not fatal — clients get moved.
printf '%s\n%s\n%s\n' "$SWEEP_A" "$TEST_DIR/gone" "$SWEEP_B" > "$TEST_DIR/deployments.txt"
assert_eq "a missing client is skipped, others still counted" "2" \
  "$(sweep --count 2>/dev/null | wc -l | xargs)"
unset WF_DEPLOYMENTS

section "No BSD-only in-place sed"

# `sed -i ''` is macOS-only; it fails outright on GNU sed, so any of these
# would break the pipeline the moment it runs anywhere but a Mac.
offenders=$(grep -rln "sed -i ''" "$SCRIPT_DIR"/*.sh 2>/dev/null | while read -r f; do
  # Ignore matches that are only inside comments.
  grep -v '^[[:space:]]*#' "$f" | grep -q "sed -i ''" && basename "$f"
done)
assert_eq "no executable 'sed -i' remains in $SCRIPT_FOLDER" "" "$offenders"

# ═══════════════════════════════════════════════════════════════════════
printf '\n══════════════════════════════════════════════════════════════\n'
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mResults: %d/%d passed\033[0m\n' "$PASS" "$((PASS + FAIL))"
else
  printf '\033[31mResults: %d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
fi
printf '══════════════════════════════════════════════════════════════\n'

[ "$FAIL" -eq 0 ]

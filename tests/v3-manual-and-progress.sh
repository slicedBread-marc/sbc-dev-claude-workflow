#!/usr/bin/env bash
# v3-manual-and-progress.sh — tests for the v3.0 additions:
#
#   wf-progress-tick.sh / wf-progress-count.sh   forward-progress signal (P-007)
#   wf-manual-lint.sh                            manual criterion tags (P-002)
#   wf-manual-gate.sh                            surface-gated manual test (P-003)
#   wf-defer-criterion.sh                        deferred-criteria producer (P-004)
#   wf-list-consistency.sh                       cross-plan pass candidates (P-005)
#   wf-config-get.sh                             config reads from skills
#
# Usage: ./tests/v3-manual-and-progress.sh
# Exit 0 if all pass, 1 otherwise.

set -uo pipefail

LIB_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB_SCRIPTS="$LIB_ROOT/scripts"
SCRIPT_FOLDER=$(awk '{sub(/#.*/, "")} NF >= 2 {folder = $2} END {print folder}' "$LIB_SCRIPTS/version-map.txt")
[ -n "$SCRIPT_FOLDER" ] || { echo "cannot resolve script folder from version-map.txt" >&2; exit 1; }
SCRIPT_DIR="${WF_TEST_SCRIPT_DIR:-$LIB_SCRIPTS/$SCRIPT_FOLDER}"

TEST_DIR=""
PASS=0
FAIL=0

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

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -q -e "$needle"; then
    printf '  \033[32m✓\033[0m %s\n' "$label"; PASS=$((PASS + 1))
  else
    printf '  \033[31m✗\033[0m %s\n      expected to contain: %s\n      actual: %s\n' "$label" "$needle" "$haystack"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit() {
  local label="$1" expected="$2"; shift 2
  "$@" >/dev/null 2>&1
  local actual=$?
  if [ "$expected" -eq "$actual" ]; then
    printf '  \033[32m✓\033[0m %s\n' "$label"; PASS=$((PASS + 1))
  else
    printf '  \033[31m✗\033[0m %s (exit %d, expected %d)\n' "$label" "$actual" "$expected"; FAIL=$((FAIL + 1))
  fi
}

# ── Fixture ────────────────────────────────────────────────────────────
setup_repo() {
  TEST_DIR=$(mktemp -d)
  cd "$TEST_DIR" || exit 1
  git init -qb develop
  git config user.email "test@test.com"
  git config user.name "Test"
  mkdir -p plans feature-branches src/App/Cli

  cat > claude-workflow.yml << 'CFG'
build_command: "dotnet build"

manualTestGate:
  requireRenderingSurface: true
  minEyesCriteria: 1
  blockOnCosmetic: false
  renderingSurfaces:
    - "src/**/wwwroot/**"
    - "src/**/*.razor"

specApproval:
  mode: verdict
  maxReviewRounds: 3
  gateTags:
    - security
    - infra
CFG

  cat > plans/REGISTRY.md << 'SEED'
# Plan Registry

| ID | Slug | State | Priority | Branch | Updated | WF | Tags | Deps |
|-|-|-|-|-|-|-|-|-|
| PLN-004 | cli | testing | — | — | 2026-08-01 | 3.0.0 | infra | — |
| PLN-007 | ui | testing | — | — | 2026-08-01 | 3.0.0 | ux | — |
| PLN-011 | dep | ready | — | — | 2026-08-01 | 3.0.0 | infra | PLN-004 |
| PLN-012 | nodep | ready | — | — | 2026-08-01 | 3.0.0 | infra | — |
| PLN-013 | done | ready | — | — | 2026-08-01 | 3.0.0 | infra | PLN-004 |
| PLN-020 | legacy | active | — | — | 2026-08-01 | 3.0.0 | infra | — |

<!-- Counter: 21 -->
SEED

  mkdir -p plans/PLN-004-cli plans/PLN-007-ui plans/PLN-011-dep plans/PLN-012-nodep plans/PLN-013-done plans/PLN-020-legacy

  cat > plans/PLN-004-cli/plan.md << 'P'
> **schema_version:** 6

## Goal
Ship the CLI export command.

## Verification Checklist

### Human Test Criteria

#### Manual
- [ ] (eyes:cosmetic) doctor output is pleasant to read
- [ ] (external) push to the real remote succeeds
- [ ] (soak) the Stalled section surfaces something forgotten
P

  cat > plans/PLN-007-ui/plan.md << 'P'
> **schema_version:** 6

## Goal
Ship the timer page.

#### Manual
- [ ] (eyes:blocking) /timer — usable one-handed on a phone
- [ ] /board — output contains the file name
- [ ] (eyes) /board — reads clearly
- [ ] (eyes:blocking) a patch touching azure-pipelines.yml is refused with a message naming the file

### Code Quality
- [ ] no TODOs
P

  cat > plans/PLN-020-legacy/plan.md << 'P'
> **schema_version:** 5

## Goal
A plan drafted before tags existed.

#### Manual
- [ ] /play — animation feels smooth
- [ ] /play — output contains the build id
P

  for p in PLN-011-dep PLN-012-nodep PLN-013-done; do
    printf '> **schema_version:** 6\n\n## Goal\nGoal for %s.\n' "$p" > "plans/$p/plan.md"
  done
  cat >> plans/PLN-013-done/plan.md << 'P'

## Consistency

> **Checked:** 2026-08-01 — closure: PLN-004
> **Result:** clean
P

  cat > plans/PLN-020-legacy/progress.md << 'P'
# Progress — Legacy

## Steps
- [ ] Step 1: scaffold
- [ ] Step 2: wire it
- [ ] Step 10: polish

## Log
P

  echo x > src/App/Cli/Program.cs
  git add -A
  git commit -qm "init: seed test repo"
}

setup_repo

# ── P-007 forward progress ─────────────────────────────────────────────
section "wf-progress-count / wf-progress-tick (P-007)"

assert_eq "counts an untouched checklist" "0/3" "$("$SCRIPT_DIR/wf-progress-count.sh" PLN-020)"
assert_eq "unknown plan reads 0/0" "0/0" "$("$SCRIPT_DIR/wf-progress-count.sh" PLN-999)"

"$SCRIPT_DIR/wf-progress-tick.sh" PLN-020 2 "wired it" >/dev/null 2>&1
assert_eq "a tick moves the count" "1/3" "$("$SCRIPT_DIR/wf-progress-count.sh" PLN-020)"
assert_contains "the Log line is written" "Step 2 — done (wired it)" "$(cat plans/PLN-020-legacy/progress.md)"

"$SCRIPT_DIR/wf-progress-tick.sh" PLN-020 10 "double-digit step" >/dev/null 2>&1
assert_eq "step 10 ticks, not step 1" "2/3" "$("$SCRIPT_DIR/wf-progress-count.sh" PLN-020)"
assert_contains "step 1 is still open" "- \[ \] Step 1" "$(cat plans/PLN-020-legacy/progress.md)"

"$SCRIPT_DIR/wf-progress-tick.sh" PLN-020 1 "no migration yet" --blocked >/dev/null 2>&1
assert_eq "--blocked logs without ticking" "2/3" "$("$SCRIPT_DIR/wf-progress-count.sh" PLN-020)"
assert_contains "the blocked reason is logged" "Step 1 — blocked" "$(cat plans/PLN-020-legacy/progress.md)"

# ── P-002 manual criterion lint ────────────────────────────────────────
section "wf-manual-lint (P-002)"

assert_exit "a fully tagged plan is clean" 0 "$SCRIPT_DIR/wf-manual-lint.sh" PLN-004
assert_exit "an offending plan exits 1" 1 "$SCRIPT_DIR/wf-manual-lint.sh" PLN-007

lint_out=$("$SCRIPT_DIR/wf-manual-lint.sh" PLN-007 2>/dev/null)
assert_contains "flags an untagged criterion" "untagged" "$lint_out"
assert_contains "flags a bare (eyes) tag" "unknown-tag" "$lint_out"
assert_contains "flags an assertable verb under eyes:*" "assertable" "$lint_out"
assert_eq "does not flag the genuine eyes criterion" "0" \
  "$(printf '%s\n' "$lint_out" | grep -c 'usable one-handed')"

assert_exit "a pre-v6 plan is not linted" 0 "$SCRIPT_DIR/wf-manual-lint.sh" PLN-020

eval "$("$SCRIPT_DIR/wf-manual-lint.sh" PLN-004 --counts)"
assert_eq "counts cosmetic criteria" "1" "$MANUAL_EYES_COSMETIC"
assert_eq "counts external criteria" "1" "$MANUAL_EXTERNAL"
assert_eq "counts soak criteria" "1" "$MANUAL_SOAK"
assert_eq "no open blocking criteria" "0" "$MANUAL_OPEN_BLOCKING"

eval "$("$SCRIPT_DIR/wf-manual-lint.sh" PLN-020 --counts)"
assert_eq "pre-v6 criteria count as blocking" "2" "$MANUAL_OPEN_BLOCKING"

# ── P-003 surface-gated manual test ────────────────────────────────────
section "wf-manual-gate (P-003)"

git worktree add -q -b feature/PLN-004-cli feature-branches/PLN-004-cli develop
( cd feature-branches/PLN-004-cli && echo more >> src/App/Cli/Program.cs && git add -A && git commit -qm cli )

git worktree add -q -b feature/PLN-007-ui feature-branches/PLN-007-ui develop
( cd feature-branches/PLN-007-ui && mkdir -p src/App/wwwroot && echo y > src/App/wwwroot/app.js && git add -A && git commit -qm ui )

eval "$("$SCRIPT_DIR/wf-manual-gate.sh" PLN-004)"
assert_eq "a CLI-only diff never stops for a human" "false" "$GATE"
assert_contains "and says why" "below minEyesCriteria" "$GATE_REASON"

eval "$("$SCRIPT_DIR/wf-manual-gate.sh" PLN-007)"
assert_eq "a rendering-surface diff with open eyes gates" "true" "$GATE"
assert_eq "and names the file that decided it" "src/App/wwwroot/app.js" "$SURFACE_HIT"

git worktree remove --force feature-branches/PLN-007-ui
eval "$("$SCRIPT_DIR/wf-manual-gate.sh" PLN-007)"
assert_eq "an unreadable diff gates rather than assumes" "true" "$GATE"
assert_contains "and admits it could not read the diff" "could not read" "$GATE_REASON"

# ── P-004 deferred criteria ────────────────────────────────────────────
section "wf-defer-criterion (P-004)"

assert_exit "rejects an eyes:* tag" 1 \
  "$SCRIPT_DIR/wf-defer-criterion.sh" PLN-004 eyes:blocking "should not defer"

"$SCRIPT_DIR/wf-defer-criterion.sh" PLN-004 external "push to the real remote succeeds" >/dev/null
"$SCRIPT_DIR/wf-defer-criterion.sh" PLN-004 soak "the Stalled section surfaces something forgotten" --prereq PLN-011 >/dev/null
"$SCRIPT_DIR/wf-defer-criterion.sh" PLN-007 unbuilt "admin can revoke a key" --note "revocation not built" >/dev/null

listed=$("$SCRIPT_DIR/wf-defer-criterion.sh" --list)
assert_eq "three open rows" "3" "$(printf '%s\n' "$listed" | grep -c '^DC-')"
assert_contains "external defaults to first-real-use" "first-real-use" "$listed"
assert_contains "the note survives" "revocation not built" "$listed"

filtered=$("$SCRIPT_DIR/wf-defer-criterion.sh" --list PLN-011)
assert_eq "filters by prereq" "1" "$(printf '%s\n' "$filtered" | grep -c '^DC-')"

"$SCRIPT_DIR/wf-defer-criterion.sh" --consume DC-002 PLN-011 >/dev/null
assert_eq "a consumed row leaves the open list" "2" \
  "$("$SCRIPT_DIR/wf-defer-criterion.sh" --list | grep -c '^DC-')"
assert_contains "and stays in the file as the record" "consumed by PLN-011" \
  "$(cat plans/deferred-criteria.md)"

# Zero-padded ids must not be read as octal — the WFI-008 → WFI-009 bug class.
for i in 4 5 6 7 8 9; do
  "$SCRIPT_DIR/wf-defer-criterion.sh" PLN-004 external "filler $i" >/dev/null
done
assert_contains "DC-009 increments to DC-010, not an octal error" "DC-010" \
  "$("$SCRIPT_DIR/wf-defer-criterion.sh" PLN-004 external "the tenth")"

# ── P-005 consistency candidates ───────────────────────────────────────
section "wf-list-consistency (P-005)"

cand=$("$SCRIPT_DIR/wf-list-consistency.sh")
assert_contains "lists a ready plan with deps" "PLN-011-dep" "$cand"
assert_eq "skips a plan with no deps" "0" "$(printf '%s\n' "$cand" | grep -c 'PLN-012')"
assert_eq "skips an already-checked plan" "0" "$(printf '%s\n' "$cand" | grep -c 'PLN-013')"
assert_eq "skips plans that are not ready" "0" "$(printf '%s\n' "$cand" | grep -c '^PLN-004')"
assert_exit "filters to one plan when asked" 0 "$SCRIPT_DIR/wf-list-consistency.sh" PLN-011
assert_exit "exits 1 when the filtered plan is done" 1 "$SCRIPT_DIR/wf-list-consistency.sh" PLN-013

# ── config reads ───────────────────────────────────────────────────────
section "wf-config-get"

assert_eq "reads a nested scalar" "verdict" "$("$SCRIPT_DIR/wf-config-get.sh" specApproval.mode gate)"
assert_eq "falls back to the default" "3" "$("$SCRIPT_DIR/wf-config-get.sh" specApproval.maxReviewRounds 3)"
assert_eq "reads a sequence" "2" "$("$SCRIPT_DIR/wf-config-get.sh" specApproval.gateTags --list | wc -l | tr -d ' ')"
assert_eq "an absent key uses its default" "gate" "$("$SCRIPT_DIR/wf-config-get.sh" specApproval.nothingHere gate)"

# ── Summary ────────────────────────────────────────────────────────────
printf '\n\033[1m%d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

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

#!/usr/bin/env bash
# e2e-pipeline.sh — End-to-end smoke test for the workflow pipeline
#
# Creates a temporary git repo, exercises the full plan lifecycle:
#   draft → ready → active → verify → testing → complete
#
# Also tests: counter, findings routing, list scripts, plan-info,
#             plan-port, plan-ref, branch-check, bug lifecycle.
#
# Usage: ./tests/e2e-pipeline.sh
# Exit 0 if all pass, 1 on first failure.

set -euo pipefail

# ── Paths ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
TEMPLATE_DIR="$(cd "$(dirname "$0")/.." && pwd)/templates"
TEST_DIR=""
PASS=0
FAIL=0
TOTAL=0

# ── Helpers ────────────────────────────────────────────────────────────
cleanup() {
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    rm -rf "$TEST_DIR"
  fi
}
trap cleanup EXIT

setup_repo() {
  TEST_DIR=$(mktemp -d)
  cd "$TEST_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  # Create base structure
  mkdir -p plans/briefs bugs/open bugs/triaged bugs/closed feature-branches

  # Seed REGISTRY.md
  cat > plans/REGISTRY.md << 'SEED'
# Plan Registry

| ID | Slug | State | Branch | Updated |
|-|-|-|-|-|

<!-- Counter: 1 -->
SEED

  # Seed briefs INDEX.md
  cat > plans/briefs/INDEX.md << 'BSEED'
# Brief Index

## Decided
- [BRF-001 — e2e-smoke-test](BRF-001-e2e-smoke-test.md) — Simple test feature

## Parking Lot
BSEED

  # Create a decided brief
  cat > plans/briefs/BRF-001-e2e-smoke-test.md << 'BRIEF'
# BRF-001 — e2e-smoke-test

**Status:** Decided

## Goal
Add a data-version attribute to the HTML tag for build identification.

## Acceptance Criteria
- HTML tag includes data-version attribute
- Value matches package.json version
BRIEF

  git add -A
  git commit -q -m "init: seed test repo"

  # Create develop and release branches
  git branch -M develop
  git checkout -q -b release
  git checkout -q develop
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    printf "  ✓ %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    printf "  ✗ %s\n    expected: %s\n    actual:   %s\n" "$label" "$expected" "$actual"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -q "$needle"; then
    PASS=$((PASS + 1))
    printf "  ✓ %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    printf "  ✗ %s\n    expected to contain: %s\n    actual: %s\n" "$label" "$needle" "$haystack"
  fi
}

assert_exit() {
  local label="$1" expected="$2"
  shift 2
  TOTAL=$((TOTAL + 1))
  set +e
  "$@" >/dev/null 2>&1
  local actual=$?
  set -e
  if [ "$expected" -eq "$actual" ]; then
    PASS=$((PASS + 1))
    printf "  ✓ %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    printf "  ✗ %s (exit %d, expected %d)\n" "$label" "$actual" "$expected"
  fi
}

section() {
  printf "\n── %s ──\n" "$1"
}

# ── Setup ──────────────────────────────────────────────────────────────
printf "Setting up test repo...\n"
setup_repo
printf "Test repo: %s\n" "$TEST_DIR"

# ══════════════════════════════════════════════════════════════════════
# 1. COUNTER
# ══════════════════════════════════════════════════════════════════════
section "Counter (wf-counter-next.sh)"

id1=$("$SCRIPT_DIR/wf-counter-next.sh" PLN)
assert_eq "first PLN counter" "PLN-001" "$id1"

id2=$("$SCRIPT_DIR/wf-counter-next.sh" BUG)
assert_eq "second counter (BUG prefix)" "BUG-002" "$id2"

id3=$("$SCRIPT_DIR/wf-counter-next.sh")
assert_eq "third counter (no prefix)" "3" "$id3"

counter_val=$(grep -oE 'Counter: [0-9]+' plans/REGISTRY.md | grep -oE '[0-9]+')
assert_eq "counter incremented to 4" "4" "$counter_val"

# ══════════════════════════════════════════════════════════════════════
# 2. BRANCH CHECK
# ══════════════════════════════════════════════════════════════════════
section "Branch check (wf-branch-check.sh)"

out=$("$SCRIPT_DIR/wf-branch-check.sh" develop)
assert_contains "on develop" "CURRENT_BRANCH=develop" "$out"

assert_exit "wrong branch fails" 1 "$SCRIPT_DIR/wf-branch-check.sh" release

out=$("$SCRIPT_DIR/wf-branch-check.sh" release true)
assert_contains "auto-switch to release" "CURRENT_BRANCH=release" "$out"

# Switch back
git checkout -q develop

# ══════════════════════════════════════════════════════════════════════
# 3. PLAN LIFECYCLE: draft → ready → active → verify → testing → complete
# ══════════════════════════════════════════════════════════════════════
section "Plan lifecycle"

# Create a plan folder (simulating wf-spec)
PLAN_ID="PLN-001"
PLAN_SLUG="e2e-smoke-test"
PLAN_NAME="${PLAN_ID}-${PLAN_SLUG}"
PLAN_DIR="plans/${PLAN_NAME}"
mkdir -p "$PLAN_DIR"

cat > "$PLAN_DIR/plan.md" << 'PLAN'
> **ID:** PLN-001
> **schema_version:** 4

## Goal
Add a data-version attribute to the HTML tag for build identification.

## Steps
1. Edit index.html — add data-version to <html> tag
2. Read version from package.json

## Tests
| ID | Type | Description | Command |
|-|-|-|-|
| T1 | Manual | data-version visible in DOM | Inspect element |

## Verification Checklist

### Build & Tests
- [ ] npm run build passes
- [ ] No new lint warnings

### Code Quality
- [ ] No hardcoded values

### Human Test Criteria
- [ ] data-version attribute visible in browser inspector

## Design Decisions
- Use build-time injection, not runtime fetch

## Rollback
**Trigger:** Build fails after merge
**Steps:** Revert the commit
**Verification:** Build passes again
PLAN

cat > "$PLAN_DIR/findings.md" << 'FINDINGS'
FINDINGS

cat > "$PLAN_DIR/progress.md" << 'PROGRESS'
## Steps
- [ ] Edit index.html
- [ ] Read version from package.json

## Log
PROGRESS

# Add plan row to REGISTRY (draft state)
sed -i '' '/<!-- Counter:/i\
| PLN-001 | e2e-smoke-test | draft | — | 2026-04-07 |
' plans/REGISTRY.md

git add -A && git commit -q -m "spec: PLN-001-e2e-smoke-test"

# Verify draft state
state=$(grep "PLN-001" plans/REGISTRY.md | awk -F'|' '{print $4}' | xargs)
assert_eq "plan starts as draft" "draft" "$state"

# 3a. draft → ready
out=$("$SCRIPT_DIR/wf-registry-update.sh" PLN-001 draft ready)
assert_contains "draft→ready transition" "draft → ready" "$out"

# 3b. Verify plan-info works
eval "$("$SCRIPT_DIR/wf-plan-info.sh" PLN-001)"
assert_eq "plan-info ID" "PLN-001" "$PLAN_ID"
assert_eq "plan-info state" "ready" "$PLAN_STATE"
assert_eq "plan-info dir" "plans/PLN-001-e2e-smoke-test" "$PLAN_DIR"

# 3c. list-ready shows our plan
out=$("$SCRIPT_DIR/wf-list-ready.sh" 2>/dev/null || true)
assert_contains "list-ready finds plan" "PLN-001-e2e-smoke-test" "$out"

# 3d. list-implementable shows our plan
out=$("$SCRIPT_DIR/wf-list-implementable.sh" 2>/dev/null || true)
assert_contains "list-implementable finds plan" "PLN-001-e2e-smoke-test" "$out"

# 3e. ready → active (with branch)
BRANCH="feature/PLN-001-e2e-smoke-test"
out=$("$SCRIPT_DIR/wf-registry-update.sh" PLN-001 ready active "$BRANCH")
assert_contains "ready→active transition" "ready → active" "$out"

# Verify branch was set
branch_val=$(grep "PLN-001" plans/REGISTRY.md | awk -F'|' '{print $5}' | xargs)
assert_eq "branch set in registry" "$BRANCH" "$branch_val"

# 3f. list-active shows our plan
out=$("$SCRIPT_DIR/wf-list-active.sh" 2>/dev/null || true)
assert_contains "list-active finds plan" "PLN-001-e2e-smoke-test" "$out"

# 3g. active → verify
out=$("$SCRIPT_DIR/wf-registry-update.sh" PLN-001 active verify)
assert_contains "active→verify transition" "active → verify" "$out"

# 3h. list-verify shows our plan
out=$("$SCRIPT_DIR/wf-list-verify.sh" 2>/dev/null || true)
assert_contains "list-verify finds plan" "PLN-001-e2e-smoke-test" "$out"

# 3i. verify → testing
out=$("$SCRIPT_DIR/wf-registry-update.sh" PLN-001 verify testing)
assert_contains "verify→testing transition" "verify → testing" "$out"

# 3j. list-testable shows our plan
git add -A && git commit -q -m "wip: state transitions"
# testable needs worktree check — create a feature branch worktree
git branch "$BRANCH" 2>/dev/null || true
mkdir -p "feature-branches/$PLAN_NAME"
# Can't use real worktree in temp dir easily, but test the list script
out=$("$SCRIPT_DIR/wf-list-testable.sh" 2>&1 || true)
assert_contains "list-testable finds plan" "PLN-001-e2e-smoke-test" "$out"

# 3k. testing → complete (clear branch)
out=$("$SCRIPT_DIR/wf-registry-update.sh" PLN-001 testing complete -)
assert_contains "testing→complete transition" "testing → complete" "$out"

# Verify branch cleared
branch_val=$(grep "PLN-001" plans/REGISTRY.md | awk -F'|' '{print $5}' | xargs)
assert_eq "branch cleared on complete" "—" "$branch_val"

# ══════════════════════════════════════════════════════════════════════
# 4. FINDINGS ROUTING
# ══════════════════════════════════════════════════════════════════════
section "Findings routing (wf-findings-route.sh)"

# Clean findings
route=$("$SCRIPT_DIR/wf-findings-route.sh" "$PLAN_DIR")
assert_eq "empty findings → clean" "clean" "$route"

# Behavior findings → active
cat > "$PLAN_DIR/findings.md" << 'F1'
## Human Test — 2026-04-07

- [ ] **Behavior**: Button doesn't respond
F1
route=$("$SCRIPT_DIR/wf-findings-route.sh" "$PLAN_DIR")
assert_eq "behavior finding → active" "active" "$route"

# Escalated findings → escalated
cat > "$PLAN_DIR/findings.md" << 'F2'
## Human Test — 2026-04-07

- [ ] **Behavior**: Button doesn't respond
- [ ] **Design**: Users expect different flow ← ESCALATED
F2
route=$("$SCRIPT_DIR/wf-findings-route.sh" "$PLAN_DIR")
assert_eq "escalated finding → escalated" "escalated" "$route"

# All checked → clean
cat > "$PLAN_DIR/findings.md" << 'F3'
## Human Test — 2026-04-07

- [x] **Behavior**: Button doesn't respond
- [x] **Design**: Users expect different flow ← ESCALATED
F3
route=$("$SCRIPT_DIR/wf-findings-route.sh" "$PLAN_DIR")
assert_eq "all checked → clean" "clean" "$route"

# No findings file → clean
rm "$PLAN_DIR/findings.md"
route=$("$SCRIPT_DIR/wf-findings-route.sh" "$PLAN_DIR")
assert_eq "missing findings.md → clean" "clean" "$route"

# ══════════════════════════════════════════════════════════════════════
# 5. PLAN-PORT
# ══════════════════════════════════════════════════════════════════════
section "Plan port (wf-plan-port.sh)"

# Library source keeps the {{project_slug}} placeholder — install.sh bakes
# it in at deploy time. Simulate that here via sed before running.
assert_contains "source has slug placeholder" "{{project_slug}}-pln" "$(cat "$SCRIPT_DIR/wf-plan-port.sh")"

mkdir -p scripts
sed 's|{{project_slug}}|sbc|g' "$SCRIPT_DIR/wf-plan-port.sh" > scripts/wf-plan-port.sh
chmod +x scripts/wf-plan-port.sh

out=$(scripts/wf-plan-port.sh "PLN-001-e2e-smoke-test")
assert_contains "port derived from ID" "FEATURE_PORT=8101" "$out"
assert_contains "compose project name (templated slug)" "COMPOSE_PROJECT_NAME=sbc-pln001" "$out"

# ══════════════════════════════════════════════════════════════════════
# 6. PLAN-REF (worktree context)
# ══════════════════════════════════════════════════════════════════════
section "Plan ref (wf-plan-ref.sh)"

# Simulate a worktree at feature-branches/PLN-001-e2e-smoke-test/
wt_dir="feature-branches/$PLAN_NAME"
mkdir -p "$wt_dir"
echo "PLN-001" > "$wt_dir/.plan-ref"

# plan-ref looks for ../../plans/ relative to cwd
(
  cd "$wt_dir"
  out=$("$SCRIPT_DIR/wf-plan-ref.sh")
  # Can't use assert_* here (subshell), just check exit code
  echo "$out" | grep -q "PLAN_ID=PLN-001" || { echo "  ✗ plan-ref PLAN_ID"; exit 1; }
  echo "$out" | grep -q "PLAN_NAME=PLN-001-e2e-smoke-test" || { echo "  ✗ plan-ref PLAN_NAME"; exit 1; }
)
TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); printf "  ✓ plan-ref resolves from worktree\n"

# ══════════════════════════════════════════════════════════════════════
# 7. INVALID STATE TRANSITIONS
# ══════════════════════════════════════════════════════════════════════
section "Invalid transitions"

# Plan is now complete — can't go back to active
assert_exit "complete→active fails" 1 "$SCRIPT_DIR/wf-registry-update.sh" PLN-001 active verify

# Non-existent plan
assert_exit "unknown plan fails" 1 "$SCRIPT_DIR/wf-registry-update.sh" PLN-999 draft ready

# ══════════════════════════════════════════════════════════════════════
# 8. SECOND PLAN — FIX CYCLE (active → verify → active → verify → testing)
# ══════════════════════════════════════════════════════════════════════
section "Fix cycle (plan with findings)"

PLAN2_ID="PLN-002"
PLAN2_SLUG="fix-cycle-test"
PLAN2_NAME="${PLAN2_ID}-${PLAN2_SLUG}"
PLAN2_DIR="plans/${PLAN2_NAME}"
mkdir -p "$PLAN2_DIR"

cat > "$PLAN2_DIR/plan.md" << 'P2'
> **ID:** PLN-002
> **schema_version:** 4

## Goal
Test the fix cycle path through the pipeline.
P2
touch "$PLAN2_DIR/findings.md"
cat > "$PLAN2_DIR/progress.md" << 'PR2'
## Steps
- [ ] Step 1

## Log
PR2

# Add to registry
sed -i '' '/<!-- Counter:/i\
| PLN-002 | fix-cycle-test | draft | — | 2026-04-07 |
' plans/REGISTRY.md

# Walk through: draft → ready → active → verify
"$SCRIPT_DIR/wf-registry-update.sh" PLN-002 draft ready >/dev/null
"$SCRIPT_DIR/wf-registry-update.sh" PLN-002 ready active "feature/PLN-002-fix-cycle-test" >/dev/null
"$SCRIPT_DIR/wf-registry-update.sh" PLN-002 active verify >/dev/null

# Verify finds behavior issues → route back to active
cat > "$PLAN2_DIR/findings.md" << 'FIX'
## Verify — 2026-04-07

- [ ] **Behavior**: Missing null check in handler
FIX

route=$("$SCRIPT_DIR/wf-findings-route.sh" "$PLAN2_DIR")
assert_eq "verify findings → active route" "active" "$route"

# Simulate verify agent routing back to active
"$SCRIPT_DIR/wf-registry-update.sh" PLN-002 verify active >/dev/null
state=$(grep "PLN-002" plans/REGISTRY.md | awk -F'|' '{print $4}' | xargs)
assert_eq "plan routed back to active" "active" "$state"

# Fix applied, findings checked off, back to verify
cat > "$PLAN2_DIR/findings.md" << 'FIXED'
## Verify — 2026-04-07

- [x] **Behavior**: Missing null check in handler
FIXED

"$SCRIPT_DIR/wf-registry-update.sh" PLN-002 active verify >/dev/null
route=$("$SCRIPT_DIR/wf-findings-route.sh" "$PLAN2_DIR")
assert_eq "fixed findings → clean route" "clean" "$route"

# Clean verify → testing → complete
"$SCRIPT_DIR/wf-registry-update.sh" PLN-002 verify testing >/dev/null
"$SCRIPT_DIR/wf-registry-update.sh" PLN-002 testing complete - >/dev/null
state=$(grep "PLN-002" plans/REGISTRY.md | awk -F'|' '{print $4}' | xargs)
assert_eq "fix cycle plan completed" "complete" "$state"

# ══════════════════════════════════════════════════════════════════════
# 9. ESCALATION CYCLE (verify → draft → ready → active → verify → testing)
# ══════════════════════════════════════════════════════════════════════
section "Escalation cycle (plan with ESCALATED findings)"

PLAN3_ID="PLN-003"
PLAN3_SLUG="escalation-test"
PLAN3_NAME="${PLAN3_ID}-${PLAN3_SLUG}"
PLAN3_DIR="plans/${PLAN3_NAME}"
mkdir -p "$PLAN3_DIR"

cat > "$PLAN3_DIR/plan.md" << 'P3'
> **ID:** PLN-003
> **schema_version:** 4

## Goal
Test the escalation path through the pipeline.
P3
touch "$PLAN3_DIR/findings.md"
touch "$PLAN3_DIR/progress.md"

sed -i '' '/<!-- Counter:/i\
| PLN-003 | escalation-test | draft | — | 2026-04-07 |
' plans/REGISTRY.md

# Walk to verify
"$SCRIPT_DIR/wf-registry-update.sh" PLN-003 draft ready >/dev/null
"$SCRIPT_DIR/wf-registry-update.sh" PLN-003 ready active "feature/PLN-003-escalation-test" >/dev/null
"$SCRIPT_DIR/wf-registry-update.sh" PLN-003 active verify >/dev/null

# Verify finds escalated issue
cat > "$PLAN3_DIR/findings.md" << 'ESC'
## Verify — 2026-04-07

- [ ] **Design**: API contract needs redesign ← ESCALATED
ESC

route=$("$SCRIPT_DIR/wf-findings-route.sh" "$PLAN3_DIR")
assert_eq "escalated finding → escalated route" "escalated" "$route"

# Route to draft for replanning
"$SCRIPT_DIR/wf-registry-update.sh" PLN-003 verify draft >/dev/null
state=$(grep "PLN-003" plans/REGISTRY.md | awk -F'|' '{print $4}' | xargs)
assert_eq "escalated plan back to draft" "draft" "$state"

# After replanning, finding resolved, walk back through
cat > "$PLAN3_DIR/findings.md" << 'ESCFIX'
## Verify — 2026-04-07

- [x] **Design**: API contract needs redesign ← ESCALATED

## Amendment — 2026-04-07
Redesigned API contract per stakeholder input.
ESCFIX

"$SCRIPT_DIR/wf-registry-update.sh" PLN-003 draft ready >/dev/null
"$SCRIPT_DIR/wf-registry-update.sh" PLN-003 ready active "feature/PLN-003-escalation-test" >/dev/null
"$SCRIPT_DIR/wf-registry-update.sh" PLN-003 active verify >/dev/null

route=$("$SCRIPT_DIR/wf-findings-route.sh" "$PLAN3_DIR")
assert_eq "resolved escalation → clean" "clean" "$route"

"$SCRIPT_DIR/wf-registry-update.sh" PLN-003 verify testing >/dev/null
"$SCRIPT_DIR/wf-registry-update.sh" PLN-003 testing complete - >/dev/null
state=$(grep "PLN-003" plans/REGISTRY.md | awk -F'|' '{print $4}' | xargs)
assert_eq "escalation cycle plan completed" "complete" "$state"

# ══════════════════════════════════════════════════════════════════════
# 10. BUG LIFECYCLE
# ══════════════════════════════════════════════════════════════════════
section "Bug lifecycle"

# Create a bug
BUG_DIR="bugs/open/BUG-002-test-crash"
mkdir -p "$BUG_DIR"
cat > "$BUG_DIR/bug.md" << 'BUG'
> **ID:** BUG-002
> **Status:** Open
> **Severity:** High
> **Plan:** —

## Description
App crashes on empty input.

## Steps to Reproduce
1. Open app
2. Submit empty form

## Expected
Validation error shown.

## Actual
Unhandled exception.
BUG

git add -A && git commit -q -m "bug: BUG-002 filed"

# Consume bug (triaged by wf-spec)
"$SCRIPT_DIR/wf-bug-consume.sh" BUG-002 PLN-004-bug-002-test-crash
assert_exit "bug consumed" 0 test -d "bugs/triaged/BUG-002-test-crash"
assert_exit "bug removed from open" 1 test -d "bugs/open/BUG-002-test-crash"

# Verify bug.md updated
bug_status=$(grep "Status:" bugs/triaged/BUG-002-test-crash/bug.md | head -1)
assert_contains "bug status → Triaged" "Triaged" "$bug_status"

bug_plan=$(grep "Plan:" bugs/triaged/BUG-002-test-crash/bug.md | head -1)
assert_contains "bug linked to plan" "PLN-004-bug-002-test-crash" "$bug_plan"

git add -A && git commit -q -m "spec: consume BUG-002"

# Close bug (by wf-test on pass)
"$SCRIPT_DIR/wf-bug-close.sh" BUG-002 PLN-004-bug-002-test-crash
assert_exit "bug closed" 0 test -d "bugs/closed/BUG-002-test-crash"
assert_exit "bug removed from triaged" 1 test -d "bugs/triaged/BUG-002-test-crash"

bug_status=$(grep "Status:" bugs/closed/BUG-002-test-crash/bug.md | head -1)
assert_contains "bug status → Closed" "Closed" "$bug_status"

# ══════════════════════════════════════════════════════════════════════
# 11. LIST SCRIPTS — EMPTY STATES
# ══════════════════════════════════════════════════════════════════════
section "List scripts (empty states)"

# All plans are complete now — list scripts for active states should exit 1
assert_exit "list-drafts empty → exit 1" 1 "$SCRIPT_DIR/wf-list-drafts.sh"
assert_exit "list-ready empty → exit 1" 1 "$SCRIPT_DIR/wf-list-ready.sh"
assert_exit "list-active empty → exit 1" 1 "$SCRIPT_DIR/wf-list-active.sh"
assert_exit "list-verify empty → exit 1" 1 "$SCRIPT_DIR/wf-list-verify.sh"

# ══════════════════════════════════════════════════════════════════════
# 12. SPECABLE LIST (briefs integration)
# ══════════════════════════════════════════════════════════════════════
section "Specable list (briefs + bugs)"

# Create an open bug for specable to find
mkdir -p "bugs/open/BUG-005-another-bug"
cat > "bugs/open/BUG-005-another-bug/bug.md" << 'B5'
> **ID:** BUG-005
> **Status:** Open
> **Severity:** Medium
> **Plan:** —

## Description
Another test bug.
B5

out=$("$SCRIPT_DIR/wf-list-specable.sh" 2>/dev/null || true)
# Should find the brief and/or the bug
assert_contains "specable finds open bug" "BUG-005" "$out"

# ══════════════════════════════════════════════════════════════════════
# RESULTS
# ══════════════════════════════════════════════════════════════════════
printf "\n══════════════════════════════════════════════════════════════\n"
printf "Results: %d/%d passed" "$PASS" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then
  printf " (%d FAILED)" "$FAIL"
fi
printf "\n══════════════════════════════════════════════════════════════\n"

exit "$FAIL"

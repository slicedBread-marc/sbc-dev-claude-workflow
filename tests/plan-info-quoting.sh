#!/usr/bin/env bash
# plan-info-quoting.sh — regression test for BUG-094
#
# wf-plan-info.sh output is consumed via `eval "$(...)"`. Values were emitted
# bare, so any value containing a space (e.g. a comma-space Tags list like
# "infra, hosting, security") word-split under eval: the second word was run as
# a command, PLAN_TAGS was truncated, and every variable emitted on later lines
# was lost — which made wf-implement see PLAN_GOAL_MISSING=true for a plan that
# had a goal.
#
# Also covers wf-set-tags.sh normalizing whitespace out of the Tags column, and
# wf-plan-ref.sh quoting its output.
#
# Usage: ./tests/plan-info-quoting.sh
# Exit 0 if all pass, 1 on any failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=""
PASS=0
FAIL=0

# Must end truthy — an EXIT trap's status becomes the script's exit status.
cleanup() {
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then rm -rf "$TEST_DIR"; fi
  return 0
}
trap cleanup EXIT

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label"
    echo "      expected: [$expected]"
    echo "      actual:   [$actual]"
    FAIL=$((FAIL + 1))
  fi
}

run_suite() {
  local scripts="$1" label="$2"
  echo "── $label ──"

  TEST_DIR=$(mktemp -d)
  cd "$TEST_DIR"
  mkdir -p plans/PLN-093-subdomain-split

  # v5 registry row with a comma-SPACE Tags value — the shape that broke eval.
  cat > plans/REGISTRY.md << 'SEED'
# Plan Registry

| ID | Slug | State | Priority | Branch | Updated | WF | Tags | Deps |
|-|-|-|-|-|-|-|-|-|
| PLN-093 | subdomain-split | verify | high | feature/PLN-093-subdomain-split | 2026-07-30 | 2.00 | infra, hosting, security | — |

<!-- Counter: 93 -->
SEED

  # Goal with an apostrophe and a semicolon — the other eval hazards.
  printf '## Goal\nSplit the portal; don'"'"'t break auth\n' \
    > plans/PLN-093-subdomain-split/plan.md

  # eval must not error and must set every variable, including ones emitted
  # after PLAN_TAGS.
  local err
  err=$(eval "$("$scripts/wf-plan-info.sh" PLN-093)" 2>&1 >/dev/null || true)
  assert_eq "eval produces no errors" "" "$err"
  # The check above ran in a subshell; eval again here so the vars land in scope.
  eval "$("$scripts/wf-plan-info.sh" PLN-093)" 2>/dev/null || true
  assert_eq "PLAN_TAGS intact" "infra, hosting, security" "${PLAN_TAGS:-<unset>}"
  assert_eq "PLAN_NAME set (emitted after tags)" "PLN-093-subdomain-split" "${PLAN_NAME:-<unset>}"
  assert_eq "PLAN_GOAL intact" "Split the portal; don't break auth" "${PLAN_GOAL:-<unset>}"
  assert_eq "PLAN_GOAL_MISSING false" "false" "${PLAN_GOAL_MISSING:-<unset>}"

  cd "$REPO_ROOT"
  rm -rf "$TEST_DIR"
  TEST_DIR=""
}

# v1.x emits a subset of the fields — exercise it through the same hazards.
run_v1x_suite() {
  echo "── wf-plan-info.sh (v1.x) ──"

  TEST_DIR=$(mktemp -d)
  cd "$TEST_DIR"
  mkdir -p plans/PLN-093-subdomain-split
  cat > plans/REGISTRY.md << 'SEED'
| ID | Slug | State | Branch | Updated |
|-|-|-|-|-|
| PLN-093 | subdomain-split | verify | feature/PLN-093-subdomain-split | 2026-07-30 |
SEED
  printf '## Goal\nSplit the portal; don'"'"'t break auth\n' \
    > plans/PLN-093-subdomain-split/plan.md

  local err
  err=$(eval "$("$REPO_ROOT/scripts/v1.x/wf-plan-info.sh" PLN-093)" 2>&1 >/dev/null || true)
  assert_eq "eval produces no errors" "" "$err"
  eval "$("$REPO_ROOT/scripts/v1.x/wf-plan-info.sh" PLN-093)" 2>/dev/null || true
  assert_eq "PLAN_GOAL intact" "Split the portal; don't break auth" "${PLAN_GOAL:-<unset>}"
  assert_eq "PLAN_NAME set" "PLN-093-subdomain-split" "${PLAN_NAME:-<unset>}"

  cd "$REPO_ROOT"
  rm -rf "$TEST_DIR"
  TEST_DIR=""
}

run_set_tags_suite() {
  echo "── wf-set-tags.sh normalization ──"

  TEST_DIR=$(mktemp -d)
  cd "$TEST_DIR"
  mkdir -p plans
  cat > plans/REGISTRY.md << 'SEED'
| ID | Slug | State | Priority | Branch | Updated | WF | Tags | Deps |
|-|-|-|-|-|-|-|-|-|
| PLN-093 | subdomain-split | verify | high | feature/PLN-093-subdomain-split | 2026-07-30 | 2.00 | — | — |
SEED

  "$REPO_ROOT/scripts/v2.00/wf-set-tags.sh" PLN-093 "infra, security" >/dev/null
  local written
  written=$(grep "| PLN-093 |" plans/REGISTRY.md | awk -F'|' '{print $9}' | xargs)
  assert_eq "comma-space normalized on write" "infra,security" "$written"

  # Off-allowlist tags are still rejected, spaces or not.
  local rc=0
  "$REPO_ROOT/scripts/v2.00/wf-set-tags.sh" PLN-093 "infra, hosting" >/dev/null 2>&1 || rc=$?
  assert_eq "unknown tag rejected" "1" "$rc"

  cd "$REPO_ROOT"
  rm -rf "$TEST_DIR"
  TEST_DIR=""
}

run_suite "$REPO_ROOT/scripts/v2.00" "wf-plan-info.sh (v2.00)"
run_v1x_suite
run_set_tags_suite

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

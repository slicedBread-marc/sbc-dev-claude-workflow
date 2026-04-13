#!/usr/bin/env bash
# wf-test-scope-test.sh
# Fixture-based shell test harness for wf-test-scope.sh.
# Creates throwaway plan folders in the real plans/ directory (with temp REGISTRY entries),
# invokes wf-test-scope.sh, asserts output, then cleans up.
# Usage: ./scripts/wf-test-scope-test.sh
# Exit 0 on all pass; non-zero on any failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Walk up until we find claude-workflow.yml so this works under both flat
# (scripts/) and versioned (scripts/vN.NN/) layouts.
DEVELOP_ROOT=""
search="$SCRIPT_DIR"
while [ "$search" != "/" ]; do
  if [ -f "$search/claude-workflow.yml" ]; then DEVELOP_ROOT="$search"; break; fi
  search="$(dirname "$search")"
done
[ -n "$DEVELOP_ROOT" ] || { echo "wf-test-scope-test.sh: cannot locate claude-workflow.yml" >&2; exit 2; }
SCOPE_SCRIPT="$SCRIPT_DIR/wf-test-scope.sh"
REGISTRY="$DEVELOP_ROOT/plans/REGISTRY.md"

FIXTURE_IDS=()

pass=0
fail=0

# Cleanup: remove fixture plans and REGISTRY rows on exit.
cleanup() {
  for id in "${FIXTURE_IDS[@]+"${FIXTURE_IDS[@]}"}"; do
    rm -rf "$DEVELOP_ROOT/plans/$id"
    # Remove the REGISTRY row (temp fixture rows have a known marker comment).
    sed -i.bak "/# wf-scope-test-fixture/d" "$REGISTRY" && rm -f "$REGISTRY.bak"
  done
}
trap cleanup EXIT

# Create a fixture plan and add a REGISTRY stub entry.
make_fixture_plan() {
  local plan_id="$1" plan_name="$2" scope_content="${3:-}"
  local plan_dir="$DEVELOP_ROOT/plans/$plan_name"
  FIXTURE_IDS+=("$plan_name")
  mkdir -p "$plan_dir"
  {
    echo "# Fixture"
    echo ""
    echo "## Goal"
    echo "Fixture plan for wf-test-scope-test."
    echo ""
    echo "## Steps"
    echo ""
    if [ -n "$scope_content" ]; then
      echo "## Test Scope"
      echo "$scope_content"
      echo ""
    fi
    echo "## E2E Scope"
  } > "$plan_dir/plan.md"
  # Append a REGISTRY stub (marker comment keeps cleanup targeted).
  local slug="${plan_name#${plan_id}-}"
  echo "| $plan_id | $slug | draft | — | 2099-01-01 | # wf-scope-test-fixture" >> "$REGISTRY"
}

assert_eq() {
  local test_name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $test_name"
    pass=$((pass + 1))
  else
    echo "  FAIL: $test_name"
    echo "        expected: '$expected'"
    echo "        actual:   '$actual'"
    fail=$((fail + 1))
  fi
}

assert_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $test_name"
    pass=$((pass + 1))
  else
    echo "  FAIL: $test_name"
    echo "        expected to contain: '$needle'"
    echo "        actual: '$haystack'"
    fail=$((fail + 1))
  fi
}

run_scope() {
  local plan_name="$1"
  "$SCOPE_SCRIPT" "$plan_name" 2>/dev/null
}

run_scope_exit() {
  local plan_name="$1"
  "$SCOPE_SCRIPT" "$plan_name" >/dev/null 2>&1; echo $?
}

run_scope_stderr() {
  local plan_name="$1"
  "$SCOPE_SCRIPT" "$plan_name" 2>&1 >/dev/null || true
}

echo "=== wf-test-scope.sh test harness ==="
echo ""

# Case 1: Missing ## Test Scope → empty stdout, exit 0
echo "Case 1: No ## Test Scope section → empty stdout, exit 0"
make_fixture_plan "PLN-991" "PLN-991-fixture-no-scope" ""
actual_out=$(run_scope PLN-991-fixture-no-scope)
actual_exit=$(run_scope_exit PLN-991-fixture-no-scope)
assert_eq "empty stdout" "" "$actual_out"
assert_eq "exit 0" "0" "$actual_exit"

# Case 2: Single 'unit' category → filter contains SBC.Core.Tests and SBC.Web.Tests
echo ""
echo "Case 2: unit scope → filter contains SBC.Core.Tests and SBC.Web.Tests"
make_fixture_plan "PLN-992" "PLN-992-fixture-unit" "- unit"
filter=$(run_scope PLN-992-fixture-unit)
assert_contains "has SBC.Core.Tests" "SBC.Core.Tests" "$filter"
assert_contains "has SBC.Web.Tests" "SBC.Web.Tests" "$filter"
assert_contains "has e2e-smoke HomePageTests (mandatory)" "SBC.E2E.Tests.HomePageTests" "$filter"

# Case 3: 'unit' + 'e2e-lesson' → filter contains lesson test class names
echo ""
echo "Case 3: unit + e2e-lesson → filter contains lesson class names"
make_fixture_plan "PLN-993" "PLN-993-fixture-unit-lesson" "- unit
- e2e-lesson"
filter=$(run_scope PLN-993-fixture-unit-lesson)
assert_contains "has SBC.Core.Tests" "SBC.Core.Tests" "$filter"
assert_contains "has LessonFlowTests" "SBC.E2E.Tests.LessonFlowTests" "$filter"
assert_contains "has ProvincePuzzleTests" "SBC.E2E.Tests.ProvincePuzzleTests" "$filter"

# Case 4: Unknown category name → warning on stderr, no crash, exit 0
echo ""
echo "Case 4: unknown category → warning on stderr, no crash, exit 0"
make_fixture_plan "PLN-994" "PLN-994-fixture-unknown-cat" "- totally-unknown-cat"
stderr_out=$(run_scope_stderr PLN-994-fixture-unknown-cat)
exit_code=$(run_scope_exit PLN-994-fixture-unknown-cat)
assert_contains "warning on stderr" "warning: unknown category" "$stderr_out"
assert_eq "exit 0 (graceful)" "0" "$exit_code"

# Case 5: Mandatory e2e-smoke always present even when not declared
echo ""
echo "Case 5: mandatory e2e-smoke patterns always present (even for unit-only scope)"
filter=$(run_scope PLN-992-fixture-unit)
assert_contains "HomePageTests in mandatory smoke" "SBC.E2E.Tests.HomePageTests" "$filter"
assert_contains "LogoutTests in mandatory smoke" "SBC.E2E.Tests.LogoutTests" "$filter"

echo ""
echo "=== Results: $pass passed, $fail failed ==="

if [ "$fail" -gt 0 ]; then
  exit 1
fi
echo "ALL PASS"

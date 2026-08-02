#!/usr/bin/env bash
# wf-test-scope.sh <plan-name>
#
# Emits a test-filter expression for the given plan's test scope.
#
# stdout: filter expression (e.g. "FullyQualifiedName~Core.Tests|FullyQualifiedName~E2E.HomePageTests")
#         Empty string means "run full suite" (no filter flag needed).
# stderr: human-readable category list ("scope: unit, e2e-smoke") for logging in the verify agent.
#
# Why stdout/stderr split (diverges from wf-plan-info.sh env-var pattern):
#   wf-plan-info.sh outputs eval-friendly key=value pairs for multiple values.
#   This script outputs a single filter string that callers capture via $(...).
#   Mixing the category log line into stdout would corrupt the captured filter.
#   stderr is the correct channel for informational output that must not be captured.
#
# Exit codes:
#   0 — success (filter on stdout, possibly empty for full-suite fallback)
#   2 — bad input (plan name fails validation)
#   3 — yq missing and WF_TEST_SCOPE_FALLBACK is not set to "full"
#
# WF_TEST_SCOPE_FALLBACK=full: bypass yq requirement, emit empty stdout (full-suite fallback).

set -euo pipefail

PLAN_NAME="${1:-}"

# Input validation — close command-injection vector before plan name reaches eval.
if ! echo "$PLAN_NAME" | grep -qE '^PLN-[0-9]+-[a-z0-9-]+$'; then
  echo "wf-test-scope.sh: invalid plan name '$PLAN_NAME' — must match PLN-NNN-slug (e.g. PLN-080-tiered-test-gating)" >&2
  exit 2
fi

# Locate the script's own directory and walk up until we find claude-workflow.yml.
# Works for both flat (scripts/) and versioned (scripts/vN.NN/) layouts.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVELOP_ROOT=""
search="$SCRIPT_DIR"
while [ "$search" != "/" ]; do
  if [ -f "$search/claude-workflow.yml" ]; then DEVELOP_ROOT="$search"; break; fi
  search="$(dirname "$search")"
done
if [ -z "$DEVELOP_ROOT" ]; then
  echo "wf-test-scope.sh: cannot locate claude-workflow.yml by walking up from $SCRIPT_DIR" >&2
  exit 2
fi
CONFIG="$DEVELOP_ROOT/claude-workflow.yml"

# Check yq dependency before doing anything else.
if ! command -v yq >/dev/null 2>&1; then
  if [ "${WF_TEST_SCOPE_FALLBACK:-}" = "full" ]; then
    echo "wf-test-scope.sh: yq not found — WF_TEST_SCOPE_FALLBACK=full, returning empty filter (full suite)" >&2
    printf ""
    exit 0
  fi
  echo "wf-test-scope.sh: yq required but not found on PATH — install yq or set WF_TEST_SCOPE_FALLBACK=full to bypass" >&2
  exit 3
fi

# Resolve PLAN_DIR via sibling wf-plan-info.sh (quoted $PLAN_NAME — already validated above).
eval "$("$SCRIPT_DIR/wf-plan-info.sh" "$PLAN_NAME")"
PLAN_FILE="$DEVELOP_ROOT/$PLAN_DIR/plan.md"

if [ ! -f "$PLAN_FILE" ]; then
  echo "wf-test-scope.sh: plan file not found: $PLAN_FILE" >&2
  exit 2
fi

# Parse declared categories from "## Test Scope" section in plan.md.
declared=()
in_scope=0
while IFS= read -r line; do
  if echo "$line" | grep -qE '^## Test Scope'; then
    in_scope=1
    continue
  fi
  if [ "$in_scope" -eq 1 ] && echo "$line" | grep -qE '^## '; then
    break
  fi
  if [ "$in_scope" -eq 1 ] && echo "$line" | grep -qE '^- '; then
    cat_name=$(echo "$line" | sed 's/^- *//')
    declared+=("$cat_name")
  fi
done < "$PLAN_FILE"

# No scope section or empty → exit 0 with empty stdout (full-suite fallback).
if [ ${#declared[@]} -eq 0 ]; then
  exit 0
fi

# Length of a yq collection, as a number that is safe to loop over.
#
# yq prints the string "null" for an absent key and exits 0, so a `|| echo 0`
# fallback never fires, and `$(( null - 1 ))` is -1. That met BSD seq, which
# REVERSES a range whenever first > last: `seq 0 -1` emits 0 and -1, so the
# loop ran twice, yq died on index [-1], and `set -e` killed the script. Any
# project whose config omits testScopeMandatory or testMappings hit it.
#
# The loops below are C-style for exactly this reason — `seq` cannot express
# an empty range on macOS, in either direction.
yq_count() {
  local n
  n=$(yq e "$1" "$CONFIG" 2>/dev/null || echo 0)
  case "$n" in ''|null|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

# Auto-detect categories from git diff --name-only develop..HEAD.
auto=()
if git -C "$DEVELOP_ROOT" rev-parse --verify develop >/dev/null 2>&1; then
  changed_files=$(git -C "$DEVELOP_ROOT" diff --name-only develop..HEAD 2>/dev/null || true)
  if [ -n "$changed_files" ]; then
    mapping_count=$(yq_count '.testMappings | length')
    for (( i = 0; i < mapping_count; i++ )); do
      glob=$(yq e ".testMappings[$i].glob" "$CONFIG")
      scopes_count=$(yq_count ".testMappings[$i].scopes | length")
      matched=0
      while IFS= read -r f; do
        pattern="${glob#./}"
        case "$f" in
          $pattern) matched=1; break ;;
        esac
      done <<< "$changed_files"
      if [ "$matched" -eq 1 ]; then
        for (( j = 0; j < scopes_count; j++ )); do
          scope=$(yq e ".testMappings[$i].scopes[$j]" "$CONFIG")
          auto+=("$scope")
        done
      fi
    done
  fi
else
  echo "wf-test-scope.sh: auto-detect skipped: develop ref unavailable" >&2
fi

# Mandatory categories.
mandatory=()
mandatory_count=$(yq_count '.testScopeMandatory | length')
for (( i = 0; i < mandatory_count; i++ )); do
  cat_name=$(yq e ".testScopeMandatory[$i]" "$CONFIG")
  mandatory+=("$cat_name")
done

# Union: declared ∪ auto-detected ∪ mandatory (deduplicate).
all_cats=()
seen=()
for cat in \
  "${declared[@]+"${declared[@]}"}" \
  "${auto[@]+"${auto[@]}"}" \
  "${mandatory[@]+"${mandatory[@]}"}"; do
  skip=0
  for s in "${seen[@]+"${seen[@]}"}"; do
    [ "$s" = "$cat" ] && skip=1 && break
  done
  if [ "$skip" -eq 0 ]; then
    all_cats+=("$cat")
    seen+=("$cat")
  fi
done

# Resolve each category to FQN substrings from testScopes.
fqn_parts=()
used_cats=()
for cat in "${all_cats[@]}"; do
  count=$(yq_count ".testScopes.\"$cat\" | length")
  if [ "$count" = "0" ]; then
    echo "wf-test-scope.sh: warning: unknown category '$cat' — skipped" >&2
    continue
  fi
  used_cats+=("$cat")
  for (( i = 0; i < count; i++ )); do
    fqn=$(yq e ".testScopes.\"$cat\"[$i]" "$CONFIG")
    fqn_parts+=("FullyQualifiedName~$fqn")
  done
done

if [ ${#fqn_parts[@]} -eq 0 ]; then
  exit 0
fi

cat_list=$(IFS=", "; echo "${used_cats[*]}")

# ── Runner check ──────────────────────────────────────────────────────────
# `FullyQualifiedName~X` is VSTest syntax. A project on Microsoft.Testing
# Platform does not recognise `--filter` in native mode: it prints MTP's help,
# reports "Zero tests ran", and exits 1. That is the worst possible failure
# here — a verify agent reading only the exit code sees a fully passing plan
# fail, and routes it back to active or draft for nothing.
#
# Running everything is never wrong, only slower. So when the target is MTP,
# fall back to the full suite and say why, rather than emitting a filter this
# runner will reject. Set testFilterStyle: vstest in claude-workflow.yml to
# override the detection; a real MTP filter syntax can be added here once one
# has been confirmed against an actual `dotnet test` run.
filter_style=$(yq e '.testFilterStyle // ""' "$CONFIG" 2>/dev/null || echo "")
if [ -z "$filter_style" ] || [ "$filter_style" = "null" ]; then
  filter_style="auto"
fi

if [ "$filter_style" = "auto" ]; then
  mtp=""
  if [ -f "$DEVELOP_ROOT/global.json" ] &&
     grep -q '"runner"[[:space:]]*:[[:space:]]*"Microsoft.Testing.Platform"' "$DEVELOP_ROOT/global.json" 2>/dev/null; then
    mtp="global.json pins runner: Microsoft.Testing.Platform"
  elif grep -rlq '<TestingPlatformDotnetTestSupport>[[:space:]]*true' \
         "$DEVELOP_ROOT" --include='*.csproj' 2>/dev/null; then
    mtp="a test project sets TestingPlatformDotnetTestSupport"
  fi
  [ -n "$mtp" ] && filter_style="none"
fi

if [ "$filter_style" = "none" ]; then
  echo "wf-test-scope.sh: ${mtp:-testFilterStyle: none} — VSTest --filter syntax does not apply." >&2
  echo "wf-test-scope.sh: falling back to the FULL suite (scope would have been: $cat_list)." >&2
  exit 0
fi

echo "scope: $cat_list" >&2

filter=$(IFS="|"; echo "${fqn_parts[*]}")
printf "%s" "$filter"

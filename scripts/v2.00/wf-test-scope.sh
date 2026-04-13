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

# Auto-detect categories from git diff --name-only develop..HEAD.
auto=()
if git -C "$DEVELOP_ROOT" rev-parse --verify develop >/dev/null 2>&1; then
  changed_files=$(git -C "$DEVELOP_ROOT" diff --name-only develop..HEAD 2>/dev/null || true)
  if [ -n "$changed_files" ]; then
    mapping_count=$(yq e '.testMappings | length' "$CONFIG" 2>/dev/null || echo "0")
    for i in $(seq 0 $((mapping_count - 1))); do
      glob=$(yq e ".testMappings[$i].glob" "$CONFIG")
      scopes_count=$(yq e ".testMappings[$i].scopes | length" "$CONFIG")
      matched=0
      while IFS= read -r f; do
        pattern="${glob#./}"
        case "$f" in
          $pattern) matched=1; break ;;
        esac
      done <<< "$changed_files"
      if [ "$matched" -eq 1 ]; then
        for j in $(seq 0 $((scopes_count - 1))); do
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
mandatory_count=$(yq e '.testScopeMandatory | length' "$CONFIG" 2>/dev/null || echo "0")
for i in $(seq 0 $((mandatory_count - 1))); do
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
  count=$(yq e ".testScopes.\"$cat\" | length" "$CONFIG" 2>/dev/null || echo "0")
  if [ "$count" = "0" ] || [ "$count" = "null" ]; then
    echo "wf-test-scope.sh: warning: unknown category '$cat' — skipped" >&2
    continue
  fi
  used_cats+=("$cat")
  for i in $(seq 0 $((count - 1))); do
    fqn=$(yq e ".testScopes.\"$cat\"[$i]" "$CONFIG")
    fqn_parts+=("FullyQualifiedName~$fqn")
  done
done

if [ ${#fqn_parts[@]} -eq 0 ]; then
  exit 0
fi

cat_list=$(IFS=", "; echo "${used_cats[*]}")
echo "scope: $cat_list" >&2

filter=$(IFS="|"; echo "${fqn_parts[*]}")
printf "%s" "$filter"

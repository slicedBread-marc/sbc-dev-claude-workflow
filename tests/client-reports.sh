#!/usr/bin/env bash
# client-reports.sh — one regression per defect swept out of a client's
# WORKFLOW-ISSUES.md.
#
# Every assertion here failed in a real project before the fix that follows it.
# The comment above each block names the report, so a future change that
# reintroduces the behavior fails against the evidence rather than a guess.
#
# Usage: ./tests/client-reports.sh
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
  if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
    # Feature worktrees hold the parent repo open; drop them first.
    (cd "$TEST_DIR/main" 2>/dev/null && git worktree prune) >/dev/null 2>&1
    rm -rf "$TEST_DIR"
  fi
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

registry_add_row() {
  local id="$1" slug="$2" state="${3:-draft}" branch="${4:-—}"
  awk -v row="| $id | $slug | $state | — | $branch | 2026-08-02 | ${SCRIPT_FOLDER#v} | — | — |" '
    /<!-- Counter:/ && !done { print row; done = 1 }
    { print }
  ' plans/REGISTRY.md > plans/REGISTRY.tmp && mv plans/REGISTRY.tmp plans/REGISTRY.md
  mkdir -p "plans/$id-$slug"
  printf '# %s-%s\n\n## Goal\nTest goal for %s\n' "$id" "$slug" "$id" > "plans/$id-$slug/plan.md"
}

registry_state() {
  grep "^| $1 |" plans/REGISTRY.md | head -1 | awk -F'|' '{print $4}' | xargs
}

# ═══════════════════════════════════════════════════════════════════════
TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/main"
cd "$TEST_DIR/main" || exit 1
git init -q -b develop
git config user.email "test@test.com"
git config user.name "Test"
mkdir -p plans .claude
cp "$LIB_ROOT/templates/plans/REGISTRY.md" plans/REGISTRY.md
cat "$LIB_ROOT/VERSION" > .claude/workflow-version
git add -A >/dev/null 2>&1
git commit -qm seed >/dev/null 2>&1

# ═══════════════════════════════════════════════════════════════════════
section "Seeded REGISTRY header (git-tracker WFI-002)"

# The shipped template was still the 7-column v4 header while wf-spec had been
# writing 9-field rows since v5, so header and rows disagreed from the very
# first plan. wf-set-tags.sh patched each row on the way past, which hid the
# mismatch instead of fixing it.
assert_eq "template header carries Tags and Deps" "true" \
  "$(grep -q '^| ID | Slug | State | Priority | Branch | Updated | WF | Tags | Deps |$' plans/REGISTRY.md && echo true || echo false)"
assert_eq "separator has nine columns" "9" \
  "$(grep -m1 '^|-' plans/REGISTRY.md | tr -cd '-' | wc -c | xargs)"

# ═══════════════════════════════════════════════════════════════════════
section "Branch check on a greenfield repo (git-tracker WFI-001)"

# `git checkout <missing> 2>/dev/null` under set -e exited 1 with EMPTY stdout
# and stderr, so "develop does not exist yet" was indistinguishable from any
# other failure. Every greenfield project hit this on its first spec.
git checkout -q -b main 2>/dev/null || git checkout -q main
out=$("$SCRIPT_DIR/wf-branch-check.sh" nonexistent-branch true 2>&1)
assert_eq "a missing branch is created rather than failing silently" "true" \
  "$(printf '%s' "$out" | grep -q 'CREATED_BRANCH=nonexistent-branch' && echo true || echo false)"
assert_eq "and the caller is told what it is now on" "true" \
  "$(printf '%s' "$out" | grep -q 'CURRENT_BRANCH=nonexistent-branch' && echo true || echo false)"
git checkout -q develop
git branch -q -D nonexistent-branch main 2>/dev/null || true

# ═══════════════════════════════════════════════════════════════════════
section "Registry writes from a feature worktree (sbc WFI-002)"

# Registry scripts resolved "plans/REGISTRY.md" against the CWD. Verify and
# implement workers run inside a feature worktree, where that path is the
# worktree's own stale copy: the write landed there, the script's own
# verification grep passed against the file it had just written, and the real
# registry never moved. The plan read as stuck in `verify` with a completed
# clean round already committed.
registry_add_row PLN-101 worktree-write verify
git add -A >/dev/null 2>&1 && git commit -qm "add PLN-101" >/dev/null 2>&1
git worktree add -q -b feature/PLN-101 "$TEST_DIR/wt-101" develop 2>/dev/null

assert_ok "registry update runs from inside a feature worktree" \
  env -C "$TEST_DIR/wt-101" "$SCRIPT_DIR/wf-registry-update.sh" PLN-101 verify testing
assert_eq "the DEVELOP registry is the one that moved" "testing" "$(registry_state PLN-101)"

# The same path bug made every read report the worktree's copy.
assert_eq "reads from a worktree see develop's registry" "true" \
  "$(env -C "$TEST_DIR/wt-101" "$SCRIPT_DIR/wf-list-testable.sh" 2>/dev/null \
     | grep -q 'PLN-101-worktree-write' && echo true || echo false)"

# ═══════════════════════════════════════════════════════════════════════
section "Sparse checkout in a linked worktree (git-tracker WFI-004, sbc WFI-006)"

# REPO_ROOT came from `git rev-parse --show-toplevel`, which in a linked
# worktree returns THAT worktree. The script then ran `mkdir -p <wt>/.git/info`
# — but a linked worktree's .git is a regular file, a gitdir pointer — and died
# with "Not a directory" before configuring anything.
assert_ok "sparse-checkout configures a linked worktree" \
  "$SCRIPT_DIR/wf-worktree-sparse.sh" "$TEST_DIR/wt-101"
assert_eq "patterns landed in the worktree's own admin dir" "true" \
  "$(grep -q '^!plans/\*\*$' "$(git -C "$TEST_DIR/wt-101" rev-parse --git-dir)/info/sparse-checkout" && echo true || echo false)"
assert_eq "develop's sparse-checkout stayed a catch-all" "/**" \
  "$(head -1 "$(git rev-parse --git-common-dir)/info/sparse-checkout" 2>/dev/null)"

git worktree remove --force "$TEST_DIR/wt-101" >/dev/null 2>&1

# ═══════════════════════════════════════════════════════════════════════
section "Implementable type vs. existing worktree (git-tracker WFI-014)"

# The header documents type `new` as "state ready AND no existing worktree",
# but the type was read off the state alone. A plan sent back to `ready` for a
# replan keeps its branch and worktree, so it came back as `new` and the
# implementer tried to create both again.
registry_add_row PLN-102 replanned ready feature/PLN-102
git add -A >/dev/null 2>&1 && git commit -qm "add PLN-102" >/dev/null 2>&1
assert_eq "ready with no worktree is 'new'" "new" \
  "$("$SCRIPT_DIR/wf-list-implementable.sh" 2>/dev/null | awk -F'\t' '$2 == "PLN-102-replanned" { print $1 }')"

git worktree add -q -b feature/PLN-102 "$TEST_DIR/wt-102" develop 2>/dev/null
assert_eq "ready WITH a worktree is a resume, not a new build" "resume" \
  "$("$SCRIPT_DIR/wf-list-implementable.sh" 2>/dev/null | awk -F'\t' '$2 == "PLN-102-replanned" { print $1 }')"

printf '# Findings\n\n- [ ] Replan: implement Amendment A1\n' > plans/PLN-102-replanned/findings.md
assert_eq "…and a fix when findings are outstanding" "fix" \
  "$("$SCRIPT_DIR/wf-list-implementable.sh" 2>/dev/null | awk -F'\t' '$2 == "PLN-102-replanned" { print $1 }')"

git worktree remove --force "$TEST_DIR/wt-102" >/dev/null 2>&1

# ═══════════════════════════════════════════════════════════════════════
section "Goal history lands in its own table (git-tracker WFI-009)"

# The append matched the first `|-|-|-|-|` ANYWHERE in the file. Goal History
# ships with its header commented out, so the first LIVE four-column separator
# belongs to ## Tests — and the goal row was prepended there, giving the Tests
# table an ID column holding a date and a Command column holding an em-dash.
registry_add_row PLN-103 goal-table draft
cat > plans/PLN-103-goal-table/plan.md <<'PLAN'
# PLN-103

## Goal
Freeze the v1 capsule envelope contract

### Goal History
<!-- Managed by wf-spec via wf-goal-push.sh / wf-goal-pop.sh. Do not edit manually. -->
<!-- | Date | Previous Goal | Trigger | Resolution | -->

## Tests
| ID | Name | Command | Expected |
|-|-|-|-|
| T1 | round-trips | dotnet test | pass |
PLAN

"$SCRIPT_DIR/wf-goal-push.sh" PLN-103 "Implement Amendment A1" "Verify: 1 finding" >/dev/null 2>&1
hist=$(awk '/^### Goal History/{f=1;next} /^## /{f=0} f' plans/PLN-103-goal-table/plan.md)
assert_eq "the row is inside ### Goal History" "true" \
  "$(printf '%s' "$hist" | grep -q 'Freeze the v1 capsule envelope contract' && echo true || echo false)"
assert_eq "the Tests table is untouched" "true" \
  "$(grep -q '^| T1 | round-trips | dotnet test | pass |$' plans/PLN-103-goal-table/plan.md && echo true || echo false)"
assert_eq "no goal row leaked into Tests" "false" \
  "$(awk '/^## Tests/{f=1} f' plans/PLN-103-goal-table/plan.md | grep -q 'Verify: 1 finding' && echo true || echo false)"
assert_eq "the commented header became a real one" "1" \
  "$(grep -c '^| Date | Previous Goal | Trigger | Resolution |$' plans/PLN-103-goal-table/plan.md | xargs)"

# ═══════════════════════════════════════════════════════════════════════
section "The 'unbuilt' manual tag (git-tracker WFI-010)"

# wf-defer-criterion.sh documents and writes `unbuilt`, and the v3.0.0 response
# named it as the fourth tag — but the lint's tag switch never learned it, so
# deferring a criterion the documented way produced a plan that failed back to
# draft for an "unknown tag".
registry_add_row PLN-104 unbuilt-tag draft
cat > plans/PLN-104-unbuilt-tag/plan.md <<'PLAN'
# PLN-104

> **schema_version:** 6

## Verification Checklist

#### Manual
- [ ] (eyes:blocking) /app — the flow is completable one-handed
- [ ] (unbuilt) the export button — the screen it lives on ships in PLN-112
PLAN

assert_ok "a plan using (unbuilt) lints clean" \
  "$SCRIPT_DIR/wf-manual-lint.sh" --file plans/PLN-104-unbuilt-tag/plan.md
eval "$("$SCRIPT_DIR/wf-manual-lint.sh" --file plans/PLN-104-unbuilt-tag/plan.md --counts)"
assert_eq "unbuilt is counted as its own tag" "1" "${MANUAL_UNBUILT:-unset}"
assert_eq "and not as untagged" "0" "${MANUAL_UNTAGGED:-unset}"
assert_eq "it does not gate — only open eyes:* do" "1" "${MANUAL_OPEN_EYES:-unset}"

# A tag that really is unknown must still fail, or the lint means nothing.
printf -- '- [ ] (whenever) something vague\n' >> plans/PLN-104-unbuilt-tag/plan.md
assert_fails "an actually-unknown tag is still rejected" \
  "$SCRIPT_DIR/wf-manual-lint.sh" --file plans/PLN-104-unbuilt-tag/plan.md

# ═══════════════════════════════════════════════════════════════════════
section "BROAD-SCOPE findings do not route (sbc WFI-003)"

# A BROAD-SCOPE finding is out of the plan's declared scope and is resolved by
# spawning an independent bug. Routing on it sent the plan back to an
# implementer whose own Out of Scope section forbids the fix, so the only way
# out was to check off a finding nobody had acted on.
registry_add_row PLN-105 broad-scope verify
mkdir -p plans/PLN-105-broad-scope
printf '# Findings\n\n- [ ] SQLitePCLRaw CVE in an unrelated package ← BROAD-SCOPE\n' \
  > plans/PLN-105-broad-scope/findings.md
assert_eq "a lone BROAD-SCOPE finding leaves the plan clean" "clean" \
  "$("$SCRIPT_DIR/wf-findings-route.sh" plans/PLN-105-broad-scope 2>/dev/null)"

printf -- '- [ ] the retry loop swallows cancellation\n' >> plans/PLN-105-broad-scope/findings.md
assert_eq "an in-scope finding alongside it still routes to active" "active" \
  "$("$SCRIPT_DIR/wf-findings-route.sh" plans/PLN-105-broad-scope 2>/dev/null)"

printf -- '- [ ] the spec never said which store wins ← ESCALATED\n' >> plans/PLN-105-broad-scope/findings.md
assert_eq "escalation still wins over everything" "escalated" \
  "$("$SCRIPT_DIR/wf-findings-route.sh" plans/PLN-105-broad-scope 2>/dev/null)"

# ═══════════════════════════════════════════════════════════════════════
section "wf-verify documents its unattended contract (reported 3×)"

VERIFY_SKILL="$LIB_ROOT/skills/wf-verify/SKILL.md"
assert_eq "wf-verify has an Unattended mode section" "true" \
  "$(grep -qi '^## Unattended mode' "$VERIFY_SKILL" && echo true || echo false)"
assert_eq "it resolves prompts with [AUTO]/[GATE] like its siblings" "true" \
  "$(grep -q '\[AUTO\]' "$VERIFY_SKILL" && grep -q '\[GATE\]' "$VERIFY_SKILL" && echo true || echo false)"

# ═══════════════════════════════════════════════════════════════════════
section "wf-bug points at a template that exists (sbc WFI-005)"

# Step 5 sent the planner to bugs/_template/bug.md, which install.sh has never
# deployed. The skill's own inline format block was complete all along.
assert_eq "no reference to an undeployed template file" "false" \
  "$(grep -q 'bugs/_template' "$LIB_ROOT/skills/wf-bug/SKILL.md" && echo true || echo false)"
assert_eq "the inline bug.md format is still there" "true" \
  "$(grep -q '^## Steps to Reproduce' "$LIB_ROOT/skills/wf-bug/SKILL.md" && echo true || echo false)"

# ═══════════════════════════════════════════════════════════════════════
printf '\n'
if [ "$FAIL" -eq 0 ]; then
  printf '\033[1m%d passed, 0 failed\033[0m\n' "$PASS"
  exit 0
else
  printf '\033[1;31m%d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
  exit 1
fi

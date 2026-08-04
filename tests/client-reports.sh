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

# The frozen v1.x snapshot carried the same line and the same failure — it is a
# pure bug fix, so it propagates in place rather than forking a folder.
assert_eq "the v1.x snapshot no longer derives REPO_ROOT from --show-toplevel" "false" \
  "$(grep -q 'REPO_ROOT=$(git rev-parse --show-toplevel)' "$LIB_SCRIPTS/v1.x/wf-worktree-sparse.sh" && echo true || echo false)"

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
section "The registry is tracked (git-tracker WFI-007)"

# It was gitignored as "operational state", so plan.md, findings.md and
# progress.md were all versioned while the state machine indexing them was
# not — and the documented "row-based, so concurrent edits auto-merge"
# rationale described something that cannot happen in an untracked file.
assert_eq "install.sh does not add it to .gitignore" "false" \
  "$(grep -qE '^\s*echo "plans/REGISTRY\.md" >> "\$GITIGNORE"' "$LIB_ROOT/install.sh" && echo true || echo false)"
assert_eq "install.sh removes an existing ignore line" "true" \
  "$(grep -q 'Removed plans/REGISTRY.md from .gitignore' "$LIB_ROOT/install.sh" && echo true || echo false)"

# A transition and the findings that justify it must land in ONE commit.
registry_add_row PLN-108 tracked verify
git add -A >/dev/null 2>&1 && git commit -qm "add PLN-108" >/dev/null 2>&1
# Written after the baseline commit, so it is genuinely part of the transition.
printf '# Findings\n\n## Verify — 2026-08-02\n\n- [x] all clear\n' > plans/PLN-108-tracked/findings.md
"$SCRIPT_DIR/wf-registry-update.sh" PLN-108 verify testing \
  --commit "verify(PLN-108-tracked): clean — ready for human test" \
  --add plans/PLN-108-tracked/findings.md >/dev/null 2>&1
committed=$(git show --stat --name-only --pretty=format: HEAD | tr -d ' ')
assert_eq "the registry is in the transition commit" "true" \
  "$(printf '%s' "$committed" | grep -qx 'plans/REGISTRY.md' && echo true || echo false)"
assert_eq "so are the findings that justify it" "true" \
  "$(printf '%s' "$committed" | grep -qx 'plans/PLN-108-tracked/findings.md' && echo true || echo false)"
assert_eq "and HEAD agrees with the working tree" "testing" \
  "$(git show HEAD:plans/REGISTRY.md | grep '^| PLN-108 |' | awk -F'|' '{print $4}' | xargs)"

# Feature branches must still never carry it.
assert_eq "sparse-checkout still excludes plans/ from feature worktrees" "true" \
  "$(grep -q '^!plans/\*\*$' "$SCRIPT_DIR/wf-worktree-sparse.sh" && echo true || echo false)"

# ═══════════════════════════════════════════════════════════════════════
section "Test filter vs. Microsoft.Testing.Platform (git-tracker, unnumbered)"

# FullyQualifiedName~X is VSTest syntax. Under MTP `dotnet test --filter` is
# not recognised: it prints MTP's help, reports "Zero tests ran" and exits 1.
# A verify agent reading only that exit code fails a fully passing plan.
if command -v yq >/dev/null 2>&1; then
  SCOPE_DIR="$TEST_DIR/scope"
  mkdir -p "$SCOPE_DIR/plans/PLN-107-scoped" "$SCOPE_DIR/scripts"
  cp "$SCRIPT_DIR"/wf-test-scope.sh "$SCRIPT_DIR"/wf-plan-info.sh \
     "$SCRIPT_DIR"/wf-orch-lib.sh "$SCRIPT_DIR"/wf-lock.sh "$SCOPE_DIR/scripts/" 2>/dev/null
  cp plans/REGISTRY.md "$SCOPE_DIR/plans/REGISTRY.md"
  printf '| PLN-107 | scoped | verify | — | — | 2026-08-02 | 2.00 | — | — |\n' >> "$SCOPE_DIR/plans/REGISTRY.md"
  printf '# PLN-107\n\n## Goal\nscoped\n\n## Test Scope\n- unit\n' > "$SCOPE_DIR/plans/PLN-107-scoped/plan.md"
  cat > "$SCOPE_DIR/claude-workflow.yml" <<'YML'
testFilterStyle: auto
testScopes:
  unit:
    - Core.Tests
YML

  out=$(cd "$SCOPE_DIR" && ./scripts/wf-test-scope.sh PLN-107-scoped 2>/dev/null || true)
  assert_eq "a VSTest project still gets a filter" "true" \
    "$(printf '%s' "$out" | grep -q 'FullyQualifiedName~Core.Tests' && echo true || echo false)"

  printf '{ "test": { "runner": "Microsoft.Testing.Platform" } }\n' > "$SCOPE_DIR/global.json"
  rc=0
  out=$(cd "$SCOPE_DIR" && ./scripts/wf-test-scope.sh PLN-107-scoped 2>/dev/null) || rc=$?
  assert_eq "an MTP project gets no filter at all" "" "$out"
  assert_eq "and it is a clean exit, not a failure" "0" "$rc"

  # An explicit setting must beat the detection in both directions.
  printf 'testFilterStyle: vstest\ntestScopes:\n  unit:\n    - Core.Tests\n' > "$SCOPE_DIR/claude-workflow.yml"
  out=$(cd "$SCOPE_DIR" && ./scripts/wf-test-scope.sh PLN-107-scoped 2>/dev/null || true)
  assert_eq "testFilterStyle: vstest overrides the detection" "true" \
    "$(printf '%s' "$out" | grep -q 'FullyQualifiedName~Core.Tests' && echo true || echo false)"
else
  printf '  \033[33m—\033[0m yq not installed, skipping filter-style checks\n'
fi

# ═══════════════════════════════════════════════════════════════════════
section "local-env deploy is feature-branch only (git-tracker WFI-016)"

# Hooks live in the shared admin dir and fire from every worktree, so an
# `implement(` commit made on develop during a fix cycle deployed develop's
# tree. Under sparse-checkout that tree does not match the Dockerfile's build
# context, and the deploy failed on every such commit.
# The installer must refresh an existing hook on CONTENT. It used to skip
# whenever the hook already contained "claude-workflow: verify agent trigger",
# a one-shot migration check — which froze the hook on every client that had
# it, so this very fix reached exactly one of four projects on first deploy.
assert_eq "install.sh refreshes the hook when it differs" "true" \
  "$(grep -q 'cmp -s "$HOOK_SRC" "$HOOK"' "$LIB_ROOT/install.sh" && echo true || echo false)"
assert_eq "and no longer gates on the verify-trigger marker" "false" \
  "$(grep -q 'grep -q "claude-workflow: verify agent trigger" "$HOOK"' "$LIB_ROOT/install.sh" && echo true || echo false)"

cp "$LIB_ROOT/templates/hooks/post-commit" .git/hooks/post-commit
chmod +x .git/hooks/post-commit
cat > .claude/on-implement-commit.sh <<'STUB'
#!/bin/bash
echo "$1" >> "$(git rev-parse --show-toplevel)/.claude/deploy-ran"
STUB
chmod +x .claude/on-implement-commit.sh
rm -f .claude/deploy-ran

git checkout -q develop
echo one > marker.txt && git add marker.txt >/dev/null 2>&1
git commit -qm "implement(PLN-001-x): fix findings" >/dev/null 2>&1
assert_eq "an implement( commit on develop does NOT deploy" "false" \
  "$([ -f .claude/deploy-ran ] && echo true || echo false)"

git checkout -q -b feature/PLN-106-hooked
echo two > marker.txt && git add marker.txt >/dev/null 2>&1
git commit -qm "implement(PLN-106-hooked): step 1" >/dev/null 2>&1
assert_eq "the same commit on a feature branch still deploys" "true" \
  "$([ -f .claude/deploy-ran ] && echo true || echo false)"

git checkout -q develop
rm -f .git/hooks/post-commit .claude/on-implement-commit.sh .claude/deploy-ran

# ═══════════════════════════════════════════════════════════════════════
section "wf-bug points at a template that exists (sbc WFI-005)"

# Step 5 sent the planner to bugs/_template/bug.md, which install.sh has never
# deployed. The skill's own inline format block was complete all along.
assert_eq "no reference to an undeployed template file" "false" \
  "$(grep -q 'bugs/_template' "$LIB_ROOT/skills/wf-bug/SKILL.md" && echo true || echo false)"
assert_eq "the inline bug.md format is still there" "true" \
  "$(grep -q '^## Steps to Reproduce' "$LIB_ROOT/skills/wf-bug/SKILL.md" && echo true || echo false)"

# ═══════════════════════════════════════════════════════════════════════
section "A deploy must not dirty a feature worktree (git-tracker WFI-021)"

# A sparse-checkout exclusion holds only while the path is ABSENT from the
# working tree or byte-identical to the branch's blob. install.sh wrote fresh
# content to exactly the paths this list excluded, which clears the
# skip-worktree bit on the next index refresh — so a deploy mid-plan left 33
# files the implementer never touched showing as modified, `reapply` refused to
# re-exclude them, and `git merge develop` ABORTED with "your local changes
# would be overwritten" before reaching a real conflict.
cd "$TEST_DIR/main" || exit 1
mkdir -p scripts/v2.00 .claude/skills/wf-attend
printf 'orig\n' > scripts/v2.00/wf-sample.sh
printf 'orig\n' > scripts/version-map.txt
printf 'orig\n' > .claude/skills/wf-attend/SKILL.md
printf 'orig\n' > scripts/wf-exec.sh
git add -A >/dev/null 2>&1 && git commit -qm "seed infra" >/dev/null 2>&1

registry_add_row PLN-121 deploy-drift active feature/PLN-121-deploy-drift
git add -A >/dev/null 2>&1 && git commit -qm "add PLN-121" >/dev/null 2>&1
git worktree add -q -b feature/PLN-121-deploy-drift "$TEST_DIR/wt-103" develop 2>/dev/null
"$SCRIPT_DIR/wf-worktree-sparse.sh" "$TEST_DIR/wt-103" >/dev/null 2>&1

# What a deploy does: newer content into every path a session reads on disk,
# and — as install.sh used to — into the develop-owned ones as well.
mkdir -p "$TEST_DIR/wt-103/scripts/v2.00" "$TEST_DIR/wt-103/.claude/skills/wf-attend"
printf 'v3.4.0\n' > "$TEST_DIR/wt-103/scripts/v2.00/wf-sample.sh"
printf 'v3.4.0\n' > "$TEST_DIR/wt-103/scripts/version-map.txt"
printf 'v3.4.0\n' > "$TEST_DIR/wt-103/.claude/skills/wf-attend/SKILL.md"
printf 'v3.4.0\n' > "$TEST_DIR/wt-103/scripts/wf-exec.sh"
# ...and develop adopts the same release.
printf 'v3.4.0\n' > scripts/v2.00/wf-sample.sh
printf 'v3.4.0\n' > scripts/version-map.txt
printf 'v3.4.0\n' > .claude/skills/wf-attend/SKILL.md
printf 'v3.4.0\n' > scripts/wf-exec.sh
git add -A >/dev/null 2>&1 && git commit -qm "chore: adopt v3.4.0" >/dev/null 2>&1

# Re-running sparse configuration is what install.sh now does first. It clears
# deploy copies of develop-owned paths — identified as byte-identical to
# develop's, so a file someone actually edited here is left alone.
"$SCRIPT_DIR/wf-worktree-sparse.sh" "$TEST_DIR/wt-103" >/dev/null 2>&1
assert_eq "develop-owned script copies no longer dirty the worktree" "0" \
  "$(git -C "$TEST_DIR/wt-103" status --porcelain -- scripts/v2.00 scripts/version-map.txt | wc -l | xargs)"

# The three paths a session genuinely reads off its own disk cannot be
# excluded, so they are reconciled by committing develop's bytes.
assert_ok "infra sync commits what deploy wrote" \
  "$SCRIPT_DIR/wf-infra-sync.sh" "$TEST_DIR/wt-103"
assert_eq "the worktree is clean afterwards" "0" \
  "$(git -C "$TEST_DIR/wt-103" status --porcelain | wc -l | xargs)"
assert_eq "and the runtime files are still on disk" "v3.4.0" \
  "$(cat "$TEST_DIR/wt-103/.claude/skills/wf-attend/SKILL.md" 2>/dev/null)"

# The whole point: the merge runs.
assert_ok "git merge develop succeeds after a mid-plan deploy" \
  git -C "$TEST_DIR/wt-103" merge develop --no-edit

# A sync must never sweep a live session's staged work into a chore commit —
# install.sh calls it while a worker may be mid-edit in the same worktree.
printf 'work in progress\n' > "$TEST_DIR/wt-103/feature-work.txt"
git -C "$TEST_DIR/wt-103" add feature-work.txt >/dev/null 2>&1
printf 'v3.5.0\n' > "$TEST_DIR/wt-103/.claude/skills/wf-attend/SKILL.md"
"$SCRIPT_DIR/wf-infra-sync.sh" "$TEST_DIR/wt-103" >/dev/null 2>&1
assert_eq "someone else's staged work is left staged, not committed" "true" \
  "$(git -C "$TEST_DIR/wt-103" diff --cached --name-only | grep -qx 'feature-work.txt' && echo true || echo false)"
git -C "$TEST_DIR/wt-103" reset -q >/dev/null 2>&1

# A release adds scripts AFTER a branch is cut, so an old deploy left them in
# the worktree as UNTRACKED files. `git ls-files` cannot see those, and they sit
# in `git status` as `??` — where a `git add -A` commits develop's tooling as
# plan work.
printf 'brand new\n' > scripts/v2.00/wf-added-later.sh
git add -A >/dev/null 2>&1 && git commit -qm "add a script post-branch" >/dev/null 2>&1
mkdir -p "$TEST_DIR/wt-103/scripts/v2.00"
printf 'brand new\n' > "$TEST_DIR/wt-103/scripts/v2.00/wf-added-later.sh"
"$SCRIPT_DIR/wf-worktree-sparse.sh" "$TEST_DIR/wt-103" >/dev/null 2>&1
assert_eq "an untracked deploy leftover is cleared too" "false" \
  "$([ -f "$TEST_DIR/wt-103/scripts/v2.00/wf-added-later.sh" ] && echo true || echo false)"

# Legacy clients keep scripts flat at scripts/wf-*.sh. An untracked copy of one
# is a deploy artifact by the same reasoning — but wf-exec.sh shares the glob
# and is the one file a session inside the worktree must be able to invoke.
printf 'flat legacy\n' > scripts/wf-claim.sh
git add -A >/dev/null 2>&1 && git commit -qm "flat-layout script" >/dev/null 2>&1
printf 'flat legacy\n' > "$TEST_DIR/wt-103/scripts/wf-claim.sh"
"$SCRIPT_DIR/wf-worktree-sparse.sh" "$TEST_DIR/wt-103" >/dev/null 2>&1
assert_eq "a flat-layout leftover is cleared" "false" \
  "$([ -f "$TEST_DIR/wt-103/scripts/wf-claim.sh" ] && echo true || echo false)"
assert_eq "but wf-exec.sh survives the same glob" "true" \
  "$([ -f "$TEST_DIR/wt-103/scripts/wf-exec.sh" ] && echo true || echo false)"

# sbc gitignores `.claude/skills/*`, so that path is untracked there.
# `git commit -- <untracked path>` fails the WHOLE commit with "pathspec did
# not match any file(s) known to git" — which left the paths that HAD changed
# staged and the tree still dirty, one deploy short of the merge failing again.
git -C "$TEST_DIR/wt-103" rm -r -q --cached .claude/skills >/dev/null 2>&1
git -C "$TEST_DIR/wt-103" commit -q -m "untrack skills, as sbc does" >/dev/null 2>&1
printf 'v3.6.0\n' > "$TEST_DIR/wt-103/.claude/workflow.md"
git -C "$TEST_DIR/wt-103" add .claude/workflow.md >/dev/null 2>&1
git -C "$TEST_DIR/wt-103" commit -q -m "baseline workflow.md" >/dev/null 2>&1
printf 'v3.7.0\n' > "$TEST_DIR/wt-103/.claude/workflow.md"
assert_ok "sync survives an infra path the project does not track" \
  "$SCRIPT_DIR/wf-infra-sync.sh" "$TEST_DIR/wt-103"
assert_eq "and the tracked paths are committed, not left staged" "0" \
  "$(git -C "$TEST_DIR/wt-103" status --porcelain --untracked-files=no | wc -l | xargs)"

# The exclusion list and the propagation list are the same decision made twice;
# a path may not appear in both.
assert_eq "install.sh no longer copies versioned scripts into a worktree" "false" \
  "$(grep -q 'wt_path/scripts/\$wt_folder' "$LIB_ROOT/install.sh" && echo true || echo false)"
assert_eq "nor stamps the sparse-excluded workflow-version there" "false" \
  "$(grep -q 'wt_path/.claude/workflow-version' "$LIB_ROOT/install.sh" && echo true || echo false)"

# The pre-sync ran only for NON-sparse worktrees, so the case that actually
# breaks — a sparse one — was the one it skipped.
assert_eq "merge-develop syncs infra on every worktree, sparse or not" "true" \
  "$(awk '/wf-infra-sync.sh/ { found = NR } /sparseCheckout/ { sparse = NR }
          END { print (found && sparse && found < sparse) ? "true" : "false" }' \
     "$SCRIPT_DIR/wf-merge-develop.sh")"

git worktree remove --force "$TEST_DIR/wt-103" >/dev/null 2>&1
git branch -q -D feature/PLN-121-deploy-drift 2>/dev/null || true

# ═══════════════════════════════════════════════════════════════════════
section "State transitions reach the commit that claims them (git-tracker WFI-022)"

# Every skill's post-transition commit was written when REGISTRY.md was
# gitignored, so none of their `git add` lists names it. Since v3.2.0 it is
# tracked — and wf-implement's Phase 3 commit, documented as "this commit
# triggers the verify agent", contained no registry change at all. Staging it
# inside wf-registry-update.sh fixes every call site at once, including ones
# not yet written.
registry_add_row PLN-120 unstaged ready
git add -A >/dev/null 2>&1 && git commit -qm "add PLN-120" >/dev/null 2>&1

"$SCRIPT_DIR/wf-registry-update.sh" PLN-120 ready active >/dev/null 2>&1
assert_eq "a transition without --commit still stages the registry" "true" \
  "$(git diff --cached --name-only | grep -qx 'plans/REGISTRY.md' && echo true || echo false)"

# The caller's own commit is what must carry it — `git commit -m` commits the
# whole index, so staging here is enough for every skill's add-list.
git commit -qm "implement(PLN-120-unstaged): verified, moved to verify" >/dev/null 2>&1
assert_eq "the caller's commit carries the transition" "true" \
  "$(git show --stat --name-only HEAD | grep -qx 'plans/REGISTRY.md' && echo true || echo false)"
assert_eq "and HEAD's registry holds the new state" "active" \
  "$(git show HEAD:plans/REGISTRY.md | grep '^| PLN-120 |' | awk -F'|' '{print $4}' | xargs)"

# Phase 3 named only progress.md and findings.md, so the plan.md checklist
# ticks that step 21 writes were dropped on the floor too.
assert_eq "Phase 3 commits the whole plan folder and the registry" "true" \
  "$(grep -q 'git add plans/REGISTRY.md plans/PLN-NNN-<slug>/ &&' \
     "$LIB_ROOT/skills/wf-implement/SKILL.md" && echo true || echo false)"

# A bare `git add -A` on a feature branch commits whatever the last deploy
# wrote as if the plan had changed it.
assert_eq "no bare 'git add -A' left in the implementer" "0" \
  "$(grep -c '^\s*git add -A$' "$LIB_ROOT/skills/wf-implement/SKILL.md" | xargs)"

# ═══════════════════════════════════════════════════════════════════════
section "A replan lands where its builder's exit expects (git-tracker WFI-027, WFI-026)"

# wf-spec's replanning exit wrote `draft → ready` unconditionally. A replanned
# plan keeps its branch and worktree, so the dispatcher correctly read
# ready+worktree as a `resume` and sent it to the fix cycle — whose exit runs
# `wf-registry-update.sh <id> active verify`. That from_state does not match
# `ready`, so the transition silently no-opped: work committed on the branch,
# registry still `ready`, and verify then refused for the same reason.
registry_add_row PLN-122 replan-fresh draft
registry_add_row PLN-123 replan-resume draft feature/PLN-123-replan-resume
git add -A >/dev/null 2>&1 && git commit -qm "add replan fixtures" >/dev/null 2>&1

assert_eq "a replan with no worktree goes back to ready" "ready" \
  "$("$SCRIPT_DIR/wf-replan-target.sh" PLN-122)"

git worktree add -q -b feature/PLN-123-replan-resume "$TEST_DIR/wt-123" develop 2>/dev/null
assert_eq "a replan WITH a worktree goes to active" "active" \
  "$("$SCRIPT_DIR/wf-replan-target.sh" PLN-123)"

assert_ok "--apply performs the transition" \
  "$SCRIPT_DIR/wf-replan-target.sh" PLN-123 --apply
assert_eq "the registry agrees" "active" "$(registry_state PLN-123)"

# Which is exactly the state wf-implement's exit contract requires.
assert_ok "and the builder's exit transition now matches" \
  "$SCRIPT_DIR/wf-registry-update.sh" PLN-123 active verify

# The error that sent a worker looking for a missing row.
err=$("$SCRIPT_DIR/wf-registry-update.sh" PLN-122 active verify 2>&1 || true)
assert_eq "a from_state mismatch names the state the plan IS in" "true" \
  "$(printf '%s' "$err" | grep -q "is in state 'draft', not 'active'" && echo true || echo false)"

assert_eq "wf-spec no longer hardcodes ready on the replan exit" "true" \
  "$(grep -q 'wf-replan-target.sh PLN-NNN --apply' "$LIB_ROOT/skills/wf-spec/SKILL.md" && echo true || echo false)"

# The exit sequence must not commit a transition that was refused.
assert_eq "Phase 3 stops rather than committing a refused transition" "true" \
  "$(grep -q 'do NOT run step 26' "$LIB_ROOT/skills/wf-implement/SKILL.md" && echo true || echo false)"

git worktree remove --force "$TEST_DIR/wt-123" >/dev/null 2>&1
git branch -q -D feature/PLN-123-replan-resume 2>/dev/null || true

# ═══════════════════════════════════════════════════════════════════════
section "The fix cycle sets its own container name and port (git-tracker WFI-025)"

# The post-commit hook fires on every `implement(` commit and reads
# FEATURE_PORT / COMPOSE_PROJECT_NAME from the environment. The fix cycle had
# no equivalent of Phase 2 step 12, and these are shell variables in a NEW
# session — so docker-compose.yml fell back to its defaults, which are another
# plan's name and port. One fix-cycle commit deployed a PLN-002 build as
# ...-pln001 on 8101.
assert_eq "the fix cycle runs wf-plan-port.sh" "true" \
  "$(awk '/^## Fix cycle/, /^## Worktree workflow/' "$LIB_ROOT/skills/wf-implement/SKILL.md" \
     | grep -q 'wf-plan-port.sh' && echo true || echo false)"
assert_eq "and says why a second session cannot inherit it" "true" \
  "$(awk '/^## Fix cycle/, /^## Worktree workflow/' "$LIB_ROOT/skills/wf-implement/SKILL.md" \
     | grep -q 'COMPOSE_PROJECT_NAME' && echo true || echo false)"

# ═══════════════════════════════════════════════════════════════════════
printf '\n'
if [ "$FAIL" -eq 0 ]; then
  printf '\033[1m%d passed, 0 failed\033[0m\n' "$PASS"
  exit 0
else
  printf '\033[1;31m%d passed, %d failed\033[0m\n' "$PASS" "$FAIL"
  exit 1
fi

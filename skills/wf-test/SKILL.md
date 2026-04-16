---
name: wf-test
description: Human acceptance testing for plans that passed automated verification. Guides the user through acceptance criteria, writes findings, creates PR on pass.
user_invocable: true
model: haiku
---

# Tester Role

You are in **tester mode**. Your job is to guide a human through acceptance criteria, verify the implementation works as expected, and create a PR if all tests pass.

**You must NEVER edit source code directly.** This skill runs on haiku and is not authorized to make code changes. If you find issues, document them as findings and route back to the builder — never attempt fixes yourself.

The one exception: in [Auto-test mode](#auto-test-mode), a sonnet subagent is authorized to write and commit **test code only** (never production code). The subagent is explicitly instructed on this boundary.

## Entry (simple)

**If on `develop`:**

Spawn a **haiku subagent** to fetch and format the worklist:

```
Agent(model: haiku, prompt: "Run `scripts/wf-exec.sh wf-list-testable.sh` in the current directory.
Output is tab-separated: <plan-name>\t<worktree>\t<branch>\t<goal>\t<priority>. If a 6th field exists starting with 'blocked:', it contains comma-separated blocking plan IDs.

If exit code 1: check stderr for 'CLAIMED:' lines. If any, return them verbatim prefixed with 'CLAIMED_PLANS:'. Otherwise return 'NO_PLANS'.

If exit code 0: format as a numbered markdown table, urgent first:
| # | Priority | Plan | Goal | Status |
|-|-|-|-|-|
For plans with a 'blocked:' field, show Status as '[blocked by PLN-NNN]'. Otherwise Status is '—'.

After the table add one line: Mark a plan urgent: \`u <number>\`

Final response: ONLY the formatted table and footer line, or the CLAIMED_PLANS/NO_PLANS signal. No commentary.")
```

Display the subagent's output verbatim, then:

- If output is `NO_PLANS`: say "No plans ready for testing. Run /wf-status to see pipeline state."
- If output starts with `CLAIMED_PLANS:`: show the claimed plans and ask "These plans have stale claims from a previous session. Clear claims and continue?" On yes, run `scripts/wf-exec.sh wf-unclaim.sh <plan-name>` for each, then re-run the haiku subagent.
- If the user types `u <N>`: run `scripts/wf-exec.sh wf-set-priority.sh <plan-id> urgent`, then re-run the haiku subagent to re-display the updated menu.
- If the user types `u <N>` for an already-urgent plan: run `scripts/wf-exec.sh wf-set-priority.sh <plan-id> —` to clear it, then re-run the subagent.

Tell the user: "Run `/model sonnet`, then pick a number."

After user picks:
1. `eval "$(scripts/wf-exec.sh wf-plan-info.sh PLN-NNN)"` to get plan details
2. If `$PLAN_GOAL_MISSING` is `true`, ask the user: "This plan has no goal summary. Please provide a one-line goal." Then write their answer as the first line under `## Goal` in `$PLAN_DIR/plan.md`, stage and commit: `git add $PLAN_DIR/plan.md && git commit -m "spec($PLAN_NAME): add missing goal"`. Re-run the eval to pick up the goal.
3. `scripts/wf-exec.sh wf-claim.sh $PLAN_NAME`
4. `cd feature-branches/$PLAN_NAME/`
5. Continue to testing

**If on a feature branch:**
1. `eval "$(scripts/wf-exec.sh wf-plan-ref.sh)"` to get PLAN_ID, PLAN_DIR, PLAN_NAME
2. Read the plan from `$PLAN_DIR/plan.md`
3. Continue to testing

---

## Testing

**CWD note:** All commands in this section run from within `feature-branches/$PLAN_NAME/` — the working directory was changed in Entry step 4 and persists. Do NOT prepend `cd feature-branches/$PLAN_NAME &&` to any command here.

1. **Read the plan** — from develop worktree: `../../plans/PLN-NNN-<slug>/plan.md`
   - Read Goal and Verification Checklist sections
   - **Only present `### Human Test Criteria` items** (combine `#### Chrome-Assisted` and `#### Manual` into a single flat list) — Build & Tests and Code Quality were already handled by the verify agent
   - **Chrome-assisted detection:** If the plan contains a `#### Chrome-Assisted` subsection with criteria, display a one-line suggestion before the criteria list:
     ```
     💡 This plan has Chrome-assisted criteria. Run /wf-chrome-test for automated browser checks.
     ```
     Then continue normally — wf-test treats all criteria as manual regardless.
2. **Check for prior test progress** — look for `../../plans/PLN-NNN-<slug>/test-progress.md`. If it exists, read it to get per-criterion results and build identifiers.
3. **Deploy to local container and capture build identifier** (single bash call — already inside feature branch):
   ```bash
   eval "$(../../scripts/wf-exec.sh wf-docker-up.sh)" && BUILD=$(git log -1 --format='%ad (%h)' --date=format:'%b %d %H:%M')
   ```
   This sets FEATURE_PORT, COMPOSE_PROJECT_NAME, and BUILD.
   Also read `guest_entry_path` from `claude-workflow.yml` (root of repo). If set, store it as `GUEST_ENTRY_PATH`.
3b. **Check for injectable test parameters** — scan `appsettings.json` (and `appsettings.Development.json` if present) for numeric fields whose names suggest probability, rate, chance, or frequency. If any are found, note them and surface them before the criteria list:
   ```
   💡 Injectable parameters detected — modify these in appsettings.json to force or suppress behaviors:
      - "BonusRoundProbability": 0.9  →  set to 1.0 to always trigger, 0.0 to never trigger
   After editing, restart the container: ../../scripts/wf-exec.sh wf-docker-up.sh
   ```
   When presenting or walking through individual criteria, if a criterion tests behavior that appears controlled by one of these parameters, remind the user which parameter to set and to what value before testing that criterion.
4. **Run e2e tests** (app is now running):

   First, extract the plan's e2e scope (may be blank):
   ```bash
   E2E_SCOPE=$(awk '/^## E2E Scope/{found=1;next} found && /^## /{exit} found && /[^[:space:]]/ && !/^_/{print}' ../../plans/$PLAN_NAME/plan.md | tr '\n' ' ' | xargs)
   ```

   If `$E2E_SCOPE` is non-empty, run only those tests. Otherwise run the full suite:
   ```
   Agent(model: haiku, run_in_background: true, prompt:
     "Run `{{test_command}} {{test_only_e2e}} $E2E_SCOPE` in the current directory.
      (If E2E_SCOPE is empty, omit it — runs full suite.)
      Report: total tests, passed, failed, skipped.
      If any failed, list each failure with test name and error message.
      Final response under 1500 characters.")
   ```
   Report results to user before or during human testing. If e2e tests fail, inform the user but continue — human testing may still proceed.
5. **Classify state and display criteria:**

   Compare the current `$BUILD` against the build column in test-progress.md (if it exists) to determine which of three states applies:

   **State A — Fresh start** (no test-progress.md):
   ```
   Testing: PLN-NNN — <plan title>
   App is running at http://localhost:$FEATURE_PORT
   Login first: http://localhost:$FEATURE_PORT$GUEST_ENTRY_PATH   ← only if GUEST_ENTRY_PATH is set
   Start here: http://localhost:$FEATURE_PORT/<first criterion's route>
   Current build: Apr 08 14:32 (a1b2c3d)

   ## Acceptance Criteria
   1. criterion one
   2. criterion two
   ...

   How would you like to test?
   [**e**ach] - Walk through each criterion individually
   [**a**ll]  - Pass all criteria (assume they all passed)
   ```

   **State B — Resume from failure** (test-progress.md exists, some criteria are `—` or `FAIL`):

   Read `../../plans/PLN-NNN-<slug>/findings.md` to get the prior round's findings. Show checked-off items (builder fixed) and unchecked items (still open) as context before the criteria list:

   ```
   Testing: PLN-NNN — <plan title>
   App is running at http://localhost:$FEATURE_PORT
   Login first: http://localhost:$FEATURE_PORT$GUEST_ENTRY_PATH   ← only if GUEST_ENTRY_PATH is set
   Start here: http://localhost:$FEATURE_PORT/<resume criterion's route>
   Current build: Apr 08 14:32 (f4e5d6c)

   ## Prior Round Findings
   - [x] **Behavior**: Auth not enforced on /play route (fixed by builder)
   - [ ] **Behavior**: Loading spinner persists after timeout (still open)

   ## Acceptance Criteria
   1. criterion one — PASS (build Apr 07 09:15 (a1b2c3d))
   2. criterion two — PASS (build Apr 07 09:15 (a1b2c3d))
   3. criterion three — FAILED last session
   4. criterion four — untested
   ...

   Resuming from #3 (failed on build Apr 07 09:15 (a1b2c3d)).
   [**e**ach]    - Walk through criteria starting from #3
   [**a**ll]     - Pass all remaining criteria
   [**r**estart] - Start over from #1
   ```

   **State C — Regression sweep** (all criteria show PASS, but some on an older build):
   ```
   Testing: PLN-NNN — <plan title>
   App is running at http://localhost:$FEATURE_PORT
   Login first: http://localhost:$FEATURE_PORT$GUEST_ENTRY_PATH   ← only if GUEST_ENTRY_PATH is set
   Start here: http://localhost:$FEATURE_PORT/<first stale criterion's route>
   Current build: Apr 08 16:45 (g7h8i9j)

   ## Acceptance Criteria
   1. criterion one — PASS (build Apr 07 09:15 (a1b2c3d)) ← older build
   2. criterion two — PASS (build Apr 07 09:15 (a1b2c3d)) ← older build
   ...
   8. criterion eight — PASS (build Apr 08 16:45 (g7h8i9j)) ✓ current
   9. criterion nine — PASS (build Apr 08 16:45 (g7h8i9j)) ✓ current

   All criteria have passed, but #1-7 passed on older builds.
   Recommend a regression sweep to confirm on current build.
   [**s**weep] - Retest #1-7 on current build
   [**a**ll]   - Trust prior results, mark complete
   [**e**ach]  - Walk through all 9 criteria
   ```

6. **Mode handling:**

   - **[each]** (fresh): Test all criteria from #1.
   - **[each]** (resume): Start at the resume point (the "Last failure" criterion). Proceed forward through remaining untested/failed criteria. After the last one, if stale-build passes exist → trigger the regression sweep prompt (State C).
   - **[sweep]**: Walk through only criteria whose last pass is on an older build. On pass → update build. On fail → real regression, capture as finding.
   - **[all]**: Stamps the current build on all criteria. Works in all three states.
   - **[restart]**: Ignore prior progress, test all from #1, overwrite all rows with current build.

6b. **Read auto-test config** (runs once, before entering the criterion loop). This determines whether the per-criterion mode menu is shown. Do NOT skip — if you're about to enter step 7 and haven't run this yet, run it now:
   ```bash
   DEVELOP_ROOT=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')
   CFG="$DEVELOP_ROOT/claude-workflow.yml"
   AUTO_TEST_ENABLED=$(awk '/^  enabled:/{print $2; exit}' "$CFG" 2>/dev/null)
   ```
   If `AUTO_TEST_ENABLED=true`, the menu in step 7 is **mandatory** on every criterion (fresh, resume, and sweep). If blank or `false`, skip the menu and go straight to the manual flow.

7. **For each criterion being tested — MANDATORY sequence:**

   **7.1 Display the criterion** (text, route, expected behavior).

   **7.2 Mode menu** — only when `AUTO_TEST_ENABLED=true`. This is a hard gate: you MUST display this menu and wait for the user's response before showing the deeplink or asking "what do you see?". Applies equally to fresh, resume, and sweep flows — never skip because the criterion previously failed or passed.
   ```
   [m] manual test   [a] auto test   [s] skip
   ```
   - `[a]` (or natural phrasings like "auto", "run auto-test", "automate this") → go to [Auto-test mode](#auto-test-mode). On PASS/EXISTS mark PASS and continue to next criterion. On FAIL fall through to 7.3.
   - `[s]` → mark SKIP and continue to next criterion.
   - `[m]` (default) → continue with 7.3.

   **7.3 Manual flow:**
   - **Prefer deeplinks**: If the criterion mentions a route (e.g., `/play`, `/login`, `/`) or a specific page, display the full clickable URL: `http://localhost:$FEATURE_PORT/play`. If no route is explicitly mentioned but you can infer the page from context (e.g., "on the lesson page" → the route used in prior criteria), include the deeplink. Only fall back to the base URL when no route can be determined.
   - If the user seems unclear about context (asks "what should I be seeing?" or similar), offer to show the preceding criteria as context: "Want me to show the steps leading up to this one?" Then display the prior 2-3 criteria so the user can retrace the expected path.
   - **Let the user describe what they see** — accept natural descriptions
   - Classify their response:
     - **Pass**: note it and continue
     - **Fail**: capture description. Classify:
       - **ESCALATED** (design): new behavior not in plan, scope addition, UX change
       - **Behavior** (code fix): bug in specified behavior
       All findings route to wf-spec (Opus) for review before returning to builder.
       If unsure: "Is this a new behavior you want added, or something that should work but doesn't?"
       **Do NOT stop testing.** Ask: "Want to add details, continue, pass the rest and file this as a separate bug, or stop?"
     - **Skip**: note it and continue. If the user's reason indicates the prerequisite feature doesn't exist yet (e.g. "not built", "not enforced", "system doesn't do this yet"), ask: "Want to defer this criterion? It will be saved to `plans/deferred-criteria.md` so it gets picked up when the prerequisite is built." If yes, go to [Deferring a criterion](#deferring-a-criterion).
     - **Scope reduction**: If the user says things like "mark the rest as passed", "skip this and pass", "can't test beyond this", "pass the rest", or otherwise asks to reduce scope — go to the **scope reduction** flow below. Do NOT create findings.

### Auto-test mode

Entered from step 7 when the user picks `[a]`. Active only when `autoTestGrowth.enabled: true` in `claude-workflow.yml`.

**Why this exists:** instead of walking the user through a manual check, spawn a sonnet subagent that writes (or locates) a real automated test, runs it, and commits it on pass. The test ships with the PR and runs in every subsequent verify — that's how the automated base grows. If a future plan's change makes the assertion wrong, verify fails naturally and the user learns of it without ceremony.

**Read config** (first `[a]` only — cache afterward):

```bash
CFG="$DEVELOP_ROOT/claude-workflow.yml"
AUTO_TEST_MODEL=$(awk '/^  agentModel:/{print $2; exit}' "$CFG")
AUTO_TEST_LOG_CANDIDATES=$(awk '/^  logCandidatesOnFail:/{print $2; exit}' "$CFG")
AUTO_TEST_LOG=$(awk '/^  logFile:/{print $2; exit}' "$CFG")
TEST_CMD=$(awk '/^test_command:/{sub(/^test_command: */,""); gsub(/^"|"$/,""); print; exit}' "$CFG")
TEST_FILTER=$(awk '/^test_filter_flag:/{sub(/^test_filter_flag: */,""); gsub(/^"|"$/,""); print; exit}' "$CFG")
NAMESPACE=$(awk '/^namespace_convention:/{sub(/^namespace_convention: */,""); gsub(/^"|"$/,""); print; exit}' "$CFG")
```

**Build context and spawn the agent** (per criterion):

```bash
CHANGED_FILES=$(git diff --name-only develop...HEAD | head -50)
PLAN_GOAL_BLOCK=$(awk '/^## Goal/{f=1;next} /^## /{f=0} f' "$DEVELOP_ROOT/plans/$PLAN_NAME/plan.md")
```

```
Agent(model: $AUTO_TEST_MODEL, prompt: "
Write or locate an automated test for this acceptance criterion.

Criterion:
  <criterion text>

Plan goal:
  $PLAN_GOAL_BLOCK

Files changed on this branch (diff vs develop):
  $CHANGED_FILES

Project conventions:
  - Test command: $TEST_CMD
  - Single-test filter flag: $TEST_FILTER
  - Namespace: $NAMESPACE

Procedure:
  1. Grep existing tests for something matching the criterion's intent. If one exists, run it via '$TEST_CMD $TEST_FILTER <name>'. On clean pass, output: EXISTS:<test name>
  2. Otherwise write a new test in the test file that sits next to the production code that changed. Follow the project's existing test style and namespace convention. Run it. On pass, git add + commit with message 'test($PLAN_NAME): auto-test — <short criterion>'. Output: PASS:<test name>
  3. After one honest fix attempt, if it still fails, leave the working tree clean (git restore anything you added) and output: FAIL:<reason under 300 chars>

Do NOT modify production code. Tests only. Final response under 800 characters — one of EXISTS:/PASS:/FAIL: followed by the name or reason.")
```

**Handle the agent's response:**

- **`EXISTS:<name>`** or **`PASS:<name>`** — mark the criterion PASS on the current build. Append a row to the **Realized** section of `$DEVELOP_ROOT/$AUTO_TEST_LOG` (create file with headers if absent — see format below). Note the test name alongside the criterion in session memory (it surfaces in the test-progress.md "Notes" column on exit). Continue to the next criterion.
- **`FAIL:<reason>`** —
  - If `AUTO_TEST_LOG_CANDIDATES=true`: append a row to the **Candidates** section of `$DEVELOP_ROOT/$AUTO_TEST_LOG`. Tell the user: "Auto-test couldn't produce a passing test: `<reason>`. Falling back to manual." Then continue with the manual flow below (display deeplink, let user describe, classify response).
  - Else: silently fall through to the manual flow.

Always sanity-check the tree after the agent exits: `git status --short` should be clean except for a possible new committed test. If it's dirty, the agent left junk — `git restore .` and treat as FAIL.

### Log format

Path: `$AUTO_TEST_LOG` (default `plans/auto-test-log.md`), resolved relative to the develop worktree root.

**Realized entries prove what shape of criterion can be auto-tested** — wf-spec reads them during planning and wf-implement reads them for test-style reference. Every Realized entry is direct feedback that a future plan with a similar criterion should classify it as automated up front.

**Candidate entries** are the agent-failed cases, reviewed by a human later.

Header (create file only if absent — write both section headers at creation time so each always exists):

```markdown
# Auto-test log

Every `[a]` flag hit in `/wf-test` is appended here. `### Realized` entries are
proofs — criteria that a past plan classified as manual but were successfully
automated at test time. Treat each as a signal that a similar criterion in a
future plan should be classified automated from the start.

## Realized

| Plan | Criterion | Test | File | Date |
|-|-|-|-|-|

## Candidates

Agent couldn't produce a passing test. Review during spec work — convert
manually if feasible, or keep as human-tested.

| Plan | Criterion | Reason | Date |
|-|-|-|-|
```

Rows to append:

```
# Realized (PASS or EXISTS)
| PLN-NNN | <criterion text> | <test name> | <test file path> | YYYY-MM-DD |

# Candidates (FAIL)
| PLN-NNN | <criterion text> | <agent reason> | YYYY-MM-DD |
```

Commit the log update as part of the normal test-exit commit (findings or completion path) — no separate commit.

### Completion gate

**The skill only proceeds to the "all pass" exit path when every criterion shows PASS with the current build identifier.** This is the single rule that drives the system. If some criteria passed on older builds and the user hasn't retested them via [sweep], [each], or [all], the plan is not complete.

### Completion confirmation

When all criteria show PASS on the current build, **do not proceed to the exit path automatically**. First prompt the user:

```
All criteria passed on current build.

Before completing:
- Any notes or issues to add?
- Spotted anything that should be filed as a separate bug?
- Ready to create PR and close out this plan?

[**c**omplete] - Proceed to PR and merge
[**b**ug]      - File a related bug first, then complete
[**e**scalate] - Flag a design concern (routes back to planner)
```

- **[complete]**: proceed to the "If all pass" exit path.
- **[bug]**: let the user describe the issue, capture it as a note in the completion message, then proceed to the "If all pass" exit path. After completion, remind: "File the bug with `/wf-bug`."
- **[escalate]**: treat as a finding with ESCALATED severity — proceed to the "If findings" exit path instead.

### Saving test progress

Test progress is saved once at exit, not during testing. The LLM holds in-memory state during the session and writes it all at the end.

**Format** — `../../plans/PLN-NNN-<slug>/test-progress.md`:
```markdown
## Test Progress — PLN-NNN-slug

| # | Criterion | Build | Result |
|-|-|-|-|
| 1 | criterion one text | Apr 07 09:15 (a1b2c3d) | PASS |
| 2 | criterion two text | Apr 07 09:15 (a1b2c3d) | PASS |
| 3 | criterion three text | Apr 08 14:32 (f4e5d6c) | FAIL |
| 4 | criterion four text | — | — |

Last failure: #3 on build Apr 08 14:32 (f4e5d6c)
```

- One row per criterion, always present. Result: `PASS`, `FAIL`, `SKIP`, or `—` (untested).
- Only the most recent result per criterion is stored — overwrite on retest.
- "Last failure" line records the resume point for the next session.

**On findings (failure exit):** write test-progress.md with current state. Include in the findings commit:
```bash
git add plans/PLN-NNN-<slug>/findings.md plans/PLN-NNN-<slug>/test-progress.md
# If any criteria were deferred this session:
git add plans/deferred-criteria.md
# If the auto-test agent logged any outcomes this session:
git add plans/auto-test-log.md
```

**On complete (all pass on current build):** delete the progress file as part of cleanup:
```bash
rm -f plans/PLN-NNN-<slug>/test-progress.md
git add plans/PLN-NNN-<slug>/test-progress.md
# If any criteria were deferred this session:
git add plans/deferred-criteria.md
# If the auto-test agent logged any outcomes this session:
git add plans/auto-test-log.md
```
(Include in the final completion commit.)

**On early abort** (user quits mid-test): save progress like findings exit so the next session can resume. If no criteria were tested this session, do not overwrite the file.

### Scope reduction (edge cases filed separately)

**IMPORTANT: This is a pass, not a failure. Use the "If all pass" exit path.**

Trigger conditions (any one is sufficient):
- The user explicitly asks to pass remaining criteria or reduce scope
- Most criteria pass but one or two edge cases fail, and the core fix works
- The same criterion has failed across multiple fix cycles

When triggered:
1. Mark the failing/untestable criteria as **skip** (not fail)
2. **Use the "If all pass" exit** — create PR, merge to develop, mark complete
3. After the plan completes, tell the user: "File the remaining edge case with `/wf-bug` so it gets its own plan."

**When NOT to use:** The core behavior specified in the plan doesn't work — that's a real failure.

---

### Deferring a criterion

When the user confirms they want to defer a skipped criterion, append it to `../../plans/deferred-criteria.md`. If the file doesn't exist, create it with the header first.

**Header (create only if file is absent):**
```markdown
# Deferred Criteria

Criteria that couldn't be tested because the required feature wasn't built yet. Reviewed by wf-spec when creating or amending related plans.

| ID | Criterion | Prerequisite | Prereq Plan | Source Plan | Deferred On |
|-|-|-|-|-|-|
```

**Row to append:**
```
| DC-NNN | <criterion text> | <what the user said isn't built yet> | PLN-NNN or — | PLN-NNN-<slug> | YYYY-MM-DD |
```

- `DC-NNN`: auto-increment by counting existing rows (DC-001, DC-002, …)
- `Prereq Plan`: if the missing feature is associated with a known plan ID, record it here — ask the user "Is this related to a specific plan? (e.g. PLN-022, or leave blank)". Otherwise `—`.
- Do **not** commit this file separately — it is committed as part of the normal test-exit commit (findings or completion).

---

## Exit (complex)

### If all pass

All steps below run from the **worktree** (`feature-branches/PLN-NNN-<slug>/`) unless noted.

1. Push feature branch and create PR to release:
   ```bash
   CURRENT_BRANCH=$(git branch --show-current)
   PLAN_NAME=$(echo "$CURRENT_BRANCH" | sed 's|feature/||')
   PLAN_GOAL=$(grep -A 1 "^## Goal" ../../plans/$PLAN_NAME/plan.md | tail -1)
   ```
   **Commit any dirty files before merging** (workflow infra may have been updated by deploy):
   ```bash
   git add -u -- ':(exclude)plans/' ':(exclude)bugs/' ':(exclude)briefs/' 2>/dev/null; git diff --cached --quiet || git commit -m "test($PLAN_NAME): wip before release merge"
   ```
   **Merge release into feature branch** to ensure it's up-to-date (auto-resolves `.plan-ref` and `plans/` conflicts):
   ```bash
   ../../scripts/wf-exec.sh wf-merge-release.sh
   ```
   If this fails with non-trivial conflicts, route back to builder (same as merge-blocked path below).

   Push to remote. If push fails, display the error and **stop** — ask the user to resolve manually.
   ```bash
   git push -u origin "$CURRENT_BRANCH"
   ```
   Then check if there's a diff from release before creating PR:
   ```bash
   if git log release.."$CURRENT_BRANCH" --oneline | head -1 | grep -q .; then
   ```
   Create PR (skip if one already exists for this branch):
   ```bash
     EXISTING_PR=$(gh pr view "$CURRENT_BRANCH" --json url -q .url 2>/dev/null || echo "")
     if [ -z "$EXISTING_PR" ]; then
       gh pr create \
         --base release \
         --head "$CURRENT_BRANCH" \
         --title "feat: $PLAN_NAME" \
         --body "## Feature
   $PLAN_GOAL
   
   ## Test Results
   All acceptance criteria passed in human test
   
   **Plan:** plans/$PLAN_NAME/
   
   Ready for staging validation."
     fi
   ```
   **Merge the PR.** If merge fails (conflicts, branch protection, required checks), **stop and route to builder:**
   ```bash
     if ! gh pr merge --merge 2>/tmp/wf-pr-merge-err; then
       PR_URL=$(gh pr view --json url -q .url)
       echo "MERGE FAILED: PR $PR_URL — see error above."
       echo "Routing back to builder."
   ```
   - Destroy container: `../../scripts/wf-exec.sh wf-docker-down.sh $PLAN_NAME`
   - Switch to project root
   - Write findings to `plans/$PLAN_NAME/findings.md`:
     ```markdown
     ## Merge Blocked — YYYY-MM-DD
     
     - [ ] **Merge blocked**: PR cannot merge into release. Likely cause: merge conflicts. Rebase feature branch onto release, resolve conflicts, then re-trigger verify.
     ```
   - Route back to active:
     ```bash
     scripts/wf-exec.sh wf-registry-update.sh $PLAN_NAME testing active --commit "test($PLAN_NAME): merge blocked — back to builder" --add plans/$PLAN_NAME/findings.md
     ```
   - Display: "PR merge failed. Routed back to builder (testing → active). Findings written."
   - **Stop here — do not continue with remaining steps.**

   ```bash
     fi
   else
     echo "No new commits vs release — skipping PR (branch already merged or fast-forward)"
   fi
   ```
2. Destroy container:
   ```bash
   ../../scripts/wf-exec.sh wf-docker-down.sh $PLAN_NAME
   ```

Steps below run from **project root** — use absolute path `cd /absolute/path/to/project`:

3. Switch to develop and merge feature branch:
   ```bash
   cd /absolute/path/to/project
   git checkout develop
   git checkout HEAD -- .claude/workflow-version .claude/workflow.md 2>/dev/null || true
   git stash --include-untracked -m "wf-test: stash before merge"
   ```
   ```bash
   if ! git merge "$CURRENT_BRANCH" --no-edit; then
     git merge --abort
     git stash pop 2>/dev/null || true
     echo "ERROR: Feature branch has conflicts with develop. Routing back to builder."
   ```
   - Write findings to `plans/$PLAN_NAME/findings.md` about the develop merge conflict
   - Route back: `scripts/wf-exec.sh wf-registry-update.sh $PLAN_NAME testing active --commit "test($PLAN_NAME): develop merge conflict — back to builder" --add plans/$PLAN_NAME/findings.md`
   - Display: "Develop merge conflict. PR was merged to release but develop merge failed. Routed back to builder."
   - **Stop here.**

   On success:
   ```bash
   fi
   git stash pop 2>/dev/null || true
   # Auto-resolve infra conflicts from stash pop (infra files always match develop)
   git checkout HEAD -- .claude/workflow-version .claude/workflow.md 2>/dev/null || true
   # Commit any pending plan/brief changes restored from stash (e.g. from interrupted prior sessions)
   if ! git diff --quiet -- plans/ plans/briefs/ 2>/dev/null || git ls-files --others --exclude-standard -- plans/ plans/briefs/ | grep -q .; then
     git add -u -- plans/ plans/briefs/
     git add -- plans/ plans/briefs/
     git commit -m "plans: commit pending changes (restored from stash)"
   fi
   ```
4. Release claim and update REGISTRY:
   ```bash
   scripts/wf-exec.sh wf-unclaim.sh PLN-NNN-<slug>
   scripts/wf-exec.sh wf-registry-update.sh PLN-NNN testing complete -
   ```
5. Close linked bugs (if plan Goal has `**Bug:** BUG-NNN`):
   ```bash
   scripts/wf-exec.sh wf-bug-close.sh BUG-NNN PLN-NNN-<slug>
   ```
6. Clean up feature branch and worktree:
   ```bash
   git worktree remove feature-branches/PLN-NNN-<slug> --force 2>/dev/null || true
   git branch -d "$CURRENT_BRANCH" 2>/dev/null || true
   ```
7. Clean up test progress and commit REGISTRY/bug changes:
   ```bash
   rm -f plans/PLN-NNN-<slug>/test-progress.md
   git add plans/PLN-NNN-<slug>/test-progress.md plans/auto-test-log.md plans/deferred-criteria.md bugs/ 2>/dev/null || true
   git commit --allow-empty -m "test(PLN-NNN-<slug>): complete — merged to develop"
   ```
8. Display:
   ```
   Human test passed
   PR created: [PR URL]  (or "No PR needed — already on release")
   Feature merged to develop
   Plan moved to complete
   
   Next: Run /wf-release to merge to staging, then /wf-deploy to promote to main.
   ```
   Then run `scripts/wf-exec.sh wf-check-reboot-flag.sh` and append any output to the message above.

### If findings (failures)

1. Write findings to `plans/PLN-NNN-<slug>/findings.md` on develop (from worktree, path is `../../plans/PLN-NNN-<slug>/findings.md`):
   ```markdown
   ## Human Test — YYYY-MM-DD
   
   - [ ] **Behavior**: Button doesn't respond on mobile
   - [ ] **Design**: Users expect different flow ← ESCALATED
   ```
2. Destroy container (from worktree):
   ```bash
   ../../scripts/wf-exec.sh wf-docker-down.sh $PLAN_NAME
   ```

Steps below run from **project root** — use absolute path `cd /absolute/path/to/project`:

3. Switch to develop:
   ```bash
   cd /absolute/path/to/project
   git checkout HEAD -- .claude/workflow-version .claude/workflow.md 2>/dev/null || true
   git stash --include-untracked -m "wf-test: stash before checkout" 2>/dev/null || true
   git checkout develop
   git stash pop 2>/dev/null || true
   # Auto-resolve infra conflicts from stash pop (infra files always match develop)
   git checkout HEAD -- .claude/workflow-version .claude/workflow.md 2>/dev/null || true
   # Commit any pending plan/brief changes restored from stash (e.g. from interrupted prior sessions)
   if ! git diff --quiet -- plans/ plans/briefs/ 2>/dev/null || git ls-files --others --exclude-standard -- plans/ plans/briefs/ | grep -q .; then
     git add -u -- plans/ plans/briefs/
     git add -- plans/ plans/briefs/
     git commit -m "plans: commit pending changes (restored from stash)"
   fi
   ```
4. Release claim and determine route:
   ```bash
   scripts/wf-exec.sh wf-unclaim.sh PLN-NNN-<slug>
   route=$(scripts/wf-exec.sh wf-findings-route.sh plans/PLN-NNN-<slug>)
   ```
   - **`escalated`** → route to draft:
     ```bash
     scripts/wf-exec.sh wf-registry-update.sh PLN-NNN testing draft
     git add plans/PLN-NNN-<slug>/findings.md plans/PLN-NNN-<slug>/test-progress.md plans/auto-test-log.md plans/deferred-criteria.md 2>/dev/null || true
     git commit -m "test(PLN-NNN-<slug>): escalated findings — needs replanning"
     ```
     Display: "N escalated findings require design decisions. Run /wf-spec."
   - **`active`** → route to draft (Opus reviews all findings before sending to builder):
     ```bash
     scripts/wf-exec.sh wf-registry-update.sh PLN-NNN testing draft
     git add plans/PLN-NNN-<slug>/findings.md plans/PLN-NNN-<slug>/test-progress.md plans/auto-test-log.md plans/deferred-criteria.md 2>/dev/null || true
     git commit -m "test(PLN-NNN-<slug>): N findings from human test — routing to spec"
     ```
     Display: "N findings written. Run /wf-spec to review and route to builder."

---

## Container cleanup

Always destroy the container before leaving the worktree — on pass, fail, or early abort. From the worktree:
```bash
../../scripts/wf-exec.sh wf-docker-down.sh $PLAN_NAME
```
If you hit an error and need to stop early, **destroy the container first** before routing back or displaying the error.

## Bug reference model

**Pre-existing bugs** (in plan Goal): accept BUG-NNN as truth — don't look it up.
**New bugs during testing**: write as findings immediately, file formally with `/wf-bug` after testing.

## Rules

- **Do NOT** use `git add -A` or `git add .` — only stage specific files by name
- **Do NOT** edit source code — only read the plan and write findings
- **Do NOT** skip user input — let the user describe what they see
- **Do NOT** break testing context — write findings immediately, never tell user to switch branches mid-test
- **Accept natural language** — interpret user descriptions, don't force rigid prompts
- Severity for human-test findings is either `Behavior` (code fix) or `ESCALATED` (design) — never Critical. Both route to wf-spec (draft) for Opus review.
- Only one testing worktree at a time

## Notes

| Range | Use |
|-|-|
| 8000-8099 | Static site, staging (8081) |
| 8100+ | Feature branches (8100 + plan ID) |
| 8080 | Default local dev |

Project name: `{{project_slug}}-pln<id>` (e.g., `{{project_slug}}-pln004`)

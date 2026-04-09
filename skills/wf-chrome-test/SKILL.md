---
name: wf-chrome-test
description: Browser-assisted acceptance testing. Uses Chrome to automate navigable/interactive criteria, falls back to human for subjective checks. Creates PR on pass.
user_invocable: true
model: haiku
---

# Chrome-Assisted Tester Role

You are in **tester mode with browser automation**. Your job is to drive Chrome through acceptance criteria, verify the implementation works, escalate subjective checks to the human, and create a PR if all tests pass.

**You must NEVER edit source code.** If you find issues, document them as findings and route back to the builder.

**Requires:** Claude in Chrome extension installed and connected. If Chrome is not available, tell the user: "Chrome not connected. Run `/chrome` to connect, or use `/wf-test` for manual testing." Then stop.

## Entry (simple)

**If on `develop`:**

First, clean up orphaned containers from completed plans (silent, best-effort):
```bash
scripts/wf-docker-cleanup.sh 2>/dev/null || true
```

Then list testable plans:
```bash
scripts/wf-list-testable.sh
```

Show menu from script output as a **numbered table** — always use table format, never paragraphs:

```
| # | Plan | Goal |
|-|-|-|
| 1 | PLN-006-bug-008-responsive-notice-dismiss | Fix responsive notice dismiss |
| 2 | PLN-007-bug-006-province-puzzle-bleedthrough | Fix province puzzle bleedthrough |
```

If exit code 1: check stderr for "CLAIMED:" lines. If stale claims are listed, show them and ask: "These plans have stale claims from a previous session. Clear claims and continue?" On yes, run `scripts/wf-unclaim.sh <plan-name>` for each, then re-run `scripts/wf-list-testable.sh`. If no claimed plans in stderr, say "No plans ready for testing. Run /wf-status to see pipeline state."

Then switch to sonnet: `/model sonnet`. Ask the user to pick a number.

After user picks:
1. `eval "$(scripts/wf-plan-info.sh PLN-NNN)"` to get plan details
2. If `$PLAN_GOAL_MISSING` is `true`, ask the user: "This plan has no goal summary. Please provide a one-line goal." Then write their answer as the first line under `## Goal` in `$PLAN_DIR/plan.md`, stage and commit: `git add $PLAN_DIR/plan.md && git commit -m "spec($PLAN_NAME): add missing goal"`. Re-run the eval to pick up the goal.
3. `scripts/wf-claim.sh $PLAN_NAME`
4. `cd feature-branches/$PLAN_NAME/`
5. Continue to testing

**If on a feature branch:**
1. `eval "$(scripts/wf-plan-ref.sh)"` to get PLAN_ID, PLAN_DIR, PLAN_NAME
2. Read the plan from `$PLAN_DIR/plan.md`
3. Continue to testing

---

## Testing

1. **Read the plan** — from develop worktree: `../../plans/PLN-NNN-<slug>/plan.md`
   - Read Goal and Verification Checklist sections
   - **Only present `### Human Test Criteria` items** — Build & Tests and Code Quality were already handled by the verify agent
2. **Check for prior test progress** — look for `../../plans/PLN-NNN-<slug>/test-progress.md`. If it exists, read it to get per-criterion results and build identifiers.
3. **Deploy to local container and capture build identifier:**
   ```bash
   eval "$(../../scripts/wf-docker-up.sh)"
   BUILD=$(git log -1 --format='%ad (%h)' --date=format:'%b %d %H:%M')
   ```
   This sets FEATURE_PORT, COMPOSE_PROJECT_NAME, and BUILD.
   Also read `guest_entry_path` from `claude-workflow.yml` (root of repo). If set, store it as `GUEST_ENTRY_PATH`.
4. **Run e2e tests** (app is now running):
   ```
   Agent(model: haiku, run_in_background: true, prompt:
     "Run `{{test_command}} {{test_only_e2e}}` in the current directory.
      Report: total tests, passed, failed, skipped.
      If any failed, list each failure with test name and error message.
      Final response under 1500 characters.")
   ```
   Report results to user before or during human testing. If e2e tests fail, inform the user but continue.

5. **Load criteria from the two subsections** under `### Human Test Criteria` in the plan:
   - `#### Chrome-Assisted` — these are driven by Chrome automatically. Each has a route prefix and objectively verifiable behavior.
   - `#### Manual` — these need human eyes. Chrome navigates and screenshots, but the human decides pass/fail.

   If a plan uses the older flat format (no subsections), fall back to classifying by text — see the inference table below.

   **Inference table** (fallback for plans without subsections):

   | Type | Signal | Automation |
   |-|-|-|
   | `chrome` | "redirects to", "shows X", "click", "submit", "error shown when", "persists after", "should not" | Chrome drives |
   | `manual` | "layout", "looks correct", "animation", "feels", "responsive", or no clear signal | Human confirms |

6. **Display criteria with classifications and state:**

   Determine state (A/B/C) using the same logic as wf-test, then display with type tags:

   **State A — Fresh start** (no test-progress.md):
   ```
   App is running at http://localhost:$FEATURE_PORT
   Login first: http://localhost:$FEATURE_PORT$GUEST_ENTRY_PATH   ← only if GUEST_ENTRY_PATH is set
   Current build: Apr 08 14:32 (a1b2c3d)

   ## Acceptance Criteria
   | # | Criterion | Type |
   |-|-|-|
   | 1 | `/login` — redirects to /dashboard | chrome |
   | 2 | `/form` — submit button saves form data | chrome |
   | 3 | `/form` — error shown for invalid email | chrome |
   | 4 | `/settings` — layout correct on mobile viewport | manual |
   | 5 | `/onboarding` — multi-step flow feels natural | manual |

   How would you like to test?
   [**a**uto]    - Automate what I can, pause for visual/human checks
   [**e**ach]    - Walk through each criterion manually (like wf-test)
   [**a**ll]     - Pass all criteria (assume they all passed)
   ```

   **State B — Resume from failure** and **State C — Regression sweep**: Same as wf-test but with type column added and `[auto]` option included.

7. **Mode handling:**

   - **[auto]**: The primary mode. See "Automated testing flow" below.
   - **[each]**: Manual walk-through identical to wf-test behavior — display criterion, let user describe, classify response.
   - **[sweep]**: Walk through only stale-build criteria. Use `[auto]` logic for automatable ones.
   - **[all]**: Stamps the current build on all criteria.
   - **[restart]**: Ignore prior progress, test all from #1.

---

## Automated testing flow (`[auto]` mode)

Process criteria in order. For each criterion:

### Chrome-assisted criteria (`chrome` type)

1. **Announce** what you're about to do:
   ```
   #3 [navigate] Checking: "Login page redirects to /dashboard"
   → Navigating to http://localhost:$FEATURE_PORT/login ...
   ```

2. **Drive Chrome:**
   - Navigate to the relevant URL
   - Perform any required interactions (click, type, submit)
   - Take a screenshot after the action completes
   - Read relevant DOM state if needed (check for elements, text content, URL)

3. **Evaluate the result** against the criterion. Be strict — the criterion must clearly pass:
   - **PASS**: briefly state what you observed that confirms it. Mark and continue.
     ```
     #3 PASS — navigated to /login, page redirected to /dashboard (URL confirmed)
     ```
   - **UNCERTAIN**: if the result is ambiguous, show the screenshot to the user and ask for confirmation. Treat as `visual` (human confirms).
     ```
     #3 UNCERTAIN — page loaded but URL shows /dashboard?redirect=true.
     Does this meet the criterion? [pass/fail]
     ```
   - **FAIL**: screenshot + describe what you observed vs expected. Continue testing (don't stop).
     ```
     #3 FAIL — navigated to /login, stayed on /login (no redirect).
     Expected: redirect to /dashboard
     ```

4. **For interactions** (click, submit, type): after performing the action, wait briefly for the page to update (take a second screenshot if needed to capture the result state).

5. **For state persistence** (persists after refresh, session survives): perform the action, then verify persistence (refresh the page, navigate away and back, etc.) before evaluating.

6. **For negative checks** (should not, blocked from, error shown when): attempt the forbidden action and verify the app correctly blocks it (error message shown, redirect to login, form validation, etc.).

### Manual criteria (`manual` type)

1. **Announce** and navigate to the relevant page:
   ```
   #5 [visual] Need your eyes: "Layout correct on mobile viewport"
   → Opening http://localhost:$FEATURE_PORT/page ...
   ```

2. **Take a screenshot** and present it to the user.

3. **Ask the user** to evaluate:
   ```
   Screenshot above shows the current state.
   Does this meet the criterion? Describe what you see.
   ```

4. Classify their response as pass/fail/skip using the same logic as `[each]` mode.

### Between criteria

- Show a running tally after each criterion:
  ```
  Progress: 3/8 — 2 PASS, 1 FAIL (#3)
  ```
- Continue automatically between automatable criteria — don't wait for user input.
- Only pause when a criterion needs human input or when a failure needs acknowledgment on the first failure of the session. Subsequent auto-failures can be noted without pausing.

### After all criteria

Show a summary:
```
## Test Summary
| # | Criterion | Type | Result |
|-|-|-|-|
| 1 | `/login` — redirects to /dashboard | chrome | PASS |
| 2 | `/form` — submit saves form data | chrome | PASS |
| 3 | `/form` — error on invalid email | chrome | PASS |
| 4 | `/settings` — layout on mobile | manual | PASS (confirmed) |
| 5 | `/onboarding` — multi-step flow | manual | FAIL |

Chrome-assisted: 3/3 passed
Manual: 1/2 passed
```

Then proceed to the completion gate or findings flow as appropriate.

---

## Completion gate

**The skill only proceeds to the "all pass" exit path when every criterion shows PASS with the current build identifier.** If some criteria passed on older builds and the user hasn't retested them, the plan is not complete.

## Completion confirmation

When all criteria show PASS on the current build, prompt the user:

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
- **[bug]**: let the user describe the issue, capture it as a note, then proceed. After completion, remind: "File the bug with `/wf-bug`."
- **[escalate]**: treat as ESCALATED finding — proceed to the "If findings" exit path.

### Saving test progress

Test progress is saved once at exit, not during testing. The LLM holds in-memory state during the session and writes it all at the end.

**Format** — `../../plans/PLN-NNN-<slug>/test-progress.md`:
```markdown
## Test Progress — PLN-NNN-slug

| # | Criterion | Type | Build | Result |
|-|-|-|-|-|
| 1 | criterion one text | navigate | Apr 07 09:15 (a1b2c3d) | PASS |
| 2 | criterion two text | interact | Apr 07 09:15 (a1b2c3d) | PASS |
| 3 | criterion three text | visual | Apr 08 14:32 (f4e5d6c) | FAIL |
| 4 | criterion four text | human | — | — |

Last failure: #3 on build Apr 08 14:32 (f4e5d6c)
```

- One row per criterion, always present. Result: `PASS`, `FAIL`, `SKIP`, or `—` (untested).
- Only the most recent result per criterion is stored — overwrite on retest.
- "Last failure" line records the resume point for the next session.

**On findings (failure exit):** write test-progress.md with current state. Include in the findings commit:
```bash
git add plans/PLN-NNN-<slug>/findings.md plans/PLN-NNN-<slug>/test-progress.md
```

**On complete (all pass on current build):** delete the progress file as part of cleanup:
```bash
rm -f plans/PLN-NNN-<slug>/test-progress.md
git add plans/PLN-NNN-<slug>/test-progress.md
```

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

## Exit (complex)

### If all pass

All steps below run from the **worktree** (`feature-branches/PLN-NNN-<slug>/`) unless noted.

1. Push feature branch and create PR to release:
   ```bash
   CURRENT_BRANCH=$(git branch --show-current)
   PLAN_NAME=$(echo "$CURRENT_BRANCH" | sed 's|feature/||')
   PLAN_GOAL=$(grep -A 1 "^## Goal" ../../plans/$PLAN_NAME/plan.md | tail -1)
   ```
   **Merge release into feature branch** to ensure it's up-to-date:
   ```bash
   ../../scripts/wf-merge-release.sh
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
   All acceptance criteria passed (browser-assisted + human verification)
   
   **Plan:** plans/$PLAN_NAME/
   
   Ready for staging validation."
     fi
   ```
   **Merge the PR.** If merge fails (conflicts, branch protection, required checks), **stop and route to builder:**
   ```bash
     if ! gh pr merge --merge --delete-branch 2>/tmp/wf-pr-merge-err; then
       PR_URL=$(gh pr view --json url -q .url)
       echo "MERGE FAILED: PR $PR_URL — see error above."
       echo "Routing back to builder."
   ```
   - Destroy container: `../../scripts/wf-docker-down.sh`
   - Switch to project root
   - Write findings to `plans/$PLAN_NAME/findings.md`:
     ```markdown
     ## Merge Blocked — YYYY-MM-DD
     
     - [ ] **Merge blocked**: PR cannot merge into release. Likely cause: merge conflicts. Rebase feature branch onto release, resolve conflicts, then re-trigger verify.
     ```
   - Route back to active:
     ```bash
     scripts/wf-registry-update.sh $PLAN_NAME testing active --commit "test($PLAN_NAME): merge blocked — back to builder" --add plans/$PLAN_NAME/findings.md
     ```
   - Display: "PR merge failed. Routed back to builder (testing -> active). Findings written."
   - **Stop here — do not continue with remaining steps.**

   ```bash
     fi
   else
     echo "No new commits vs release — skipping PR (branch already merged or fast-forward)"
   fi
   ```
2. Destroy container:
   ```bash
   ../../scripts/wf-docker-down.sh
   ```

Steps below run from **project root** — use absolute path `cd /absolute/path/to/project`:

3. Switch to develop and merge feature branch:
   ```bash
   cd /absolute/path/to/project
   git checkout develop
   git stash --include-untracked -m "wf-chrome-test: stash before merge"
   ```
   ```bash
   if ! git merge "$CURRENT_BRANCH" --no-edit; then
     git merge --abort
     git stash pop 2>/dev/null || true
     echo "ERROR: Feature branch has conflicts with develop. Routing back to builder."
   ```
   - Write findings to `plans/$PLAN_NAME/findings.md` about the develop merge conflict
   - Route back: `scripts/wf-registry-update.sh $PLAN_NAME testing active --commit "test($PLAN_NAME): develop merge conflict — back to builder" --add plans/$PLAN_NAME/findings.md`
   - Display: "Develop merge conflict. PR was merged to release but develop merge failed. Routed back to builder."
   - **Stop here.**

   On success:
   ```bash
   fi
   git stash pop 2>/dev/null || true
   ```
4. Release claim and update REGISTRY:
   ```bash
   scripts/wf-unclaim.sh PLN-NNN-<slug>
   scripts/wf-registry-update.sh PLN-NNN testing complete -
   ```
5. Close linked bugs (if plan Goal has `**Bug:** BUG-NNN`):
   ```bash
   scripts/wf-bug-close.sh BUG-NNN PLN-NNN-<slug>
   ```
6. Clean up feature branch and worktree:
   ```bash
   git worktree remove feature-branches/PLN-NNN-<slug> --force 2>/dev/null || true
   git branch -d "$CURRENT_BRANCH" 2>/dev/null || true
   ```
7. Clean up test progress and commit REGISTRY/bug changes:
   ```bash
   rm -f plans/PLN-NNN-<slug>/test-progress.md
   git add plans/REGISTRY.md plans/PLN-NNN-<slug>/test-progress.md bugs/
   git commit -m "test(PLN-NNN-<slug>): complete — merged to develop"
   ```
8. Display:
   ```
   Human test passed
   PR created: [PR URL]  (or "No PR needed — already on release")
   Feature merged to develop
   Plan moved to complete
   
   Next: Run /wf-release to merge to staging, then /wf-deploy to promote to main.
   ```

### If findings (failures)

1. Write findings to `plans/PLN-NNN-<slug>/findings.md` on develop (from worktree, path is `../../plans/PLN-NNN-<slug>/findings.md`):
   ```markdown
   ## Chrome-Assisted Test — YYYY-MM-DD
   
   - [ ] **Behavior**: Button doesn't respond on mobile
   - [ ] **Design**: Users expect different flow <- ESCALATED
   ```
2. Destroy container (from worktree):
   ```bash
   ../../scripts/wf-docker-down.sh
   ```

Steps below run from **project root** — use absolute path `cd /absolute/path/to/project`:

3. Switch to develop:
   ```bash
   cd /absolute/path/to/project
   git stash --include-untracked -m "wf-chrome-test: stash before checkout" 2>/dev/null || true
   git checkout develop
   git stash pop 2>/dev/null || true
   ```
4. Release claim and determine route:
   ```bash
   scripts/wf-unclaim.sh PLN-NNN-<slug>
   route=$(scripts/wf-findings-route.sh plans/PLN-NNN-<slug>)
   ```
   - **`escalated`** -> route to draft:
     ```bash
     scripts/wf-registry-update.sh PLN-NNN testing draft
     git add plans/REGISTRY.md plans/PLN-NNN-<slug>/findings.md plans/PLN-NNN-<slug>/test-progress.md
     git commit -m "test(PLN-NNN-<slug>): escalated findings — needs replanning"
     ```
     Display: "N escalated findings require design decisions. Run /wf-spec."
   - **`active`** -> route to active:
     ```bash
     scripts/wf-registry-update.sh PLN-NNN testing active
     git add plans/REGISTRY.md plans/PLN-NNN-<slug>/findings.md plans/PLN-NNN-<slug>/test-progress.md
     git commit -m "test(PLN-NNN-<slug>): N findings from chrome-assisted test"
     ```
     Display: "N findings written. Run /wf-implement to fix them."

---

## Container cleanup

Always destroy the container before leaving the worktree — on pass, fail, or early abort. From the worktree:
```bash
../../scripts/wf-docker-down.sh
```
If you hit an error and need to stop early, **destroy the container first** before routing back or displaying the error.

## Bug reference model

**Pre-existing bugs** (in plan Goal): accept BUG-NNN as truth — don't look it up.
**New bugs during testing**: write as findings immediately, file formally with `/wf-bug` after testing.

## Rules

- **Do NOT** use `git add -A` or `git add .` — only stage specific files by name
- **Do NOT** edit source code — only read the plan and write findings
- **Do NOT** skip user input on `visual` or `human` criteria — the human must confirm
- **Do NOT** break testing context — write findings immediately, never tell user to switch branches mid-test
- **Accept natural language** — interpret user descriptions, don't force rigid prompts
- Severity for findings is either `Behavior` (code fix) or `ESCALATED` (design) — never Critical
- Only one testing worktree at a time
- **Chrome failures are not test failures** — if Chrome can't navigate or click, fall back to manual for that criterion, don't mark it as FAIL

## Notes

| Range | Use |
|-|-|
| 8000-8099 | Static site, staging (8081) |
| 8100+ | Feature branches (8100 + plan ID) |
| 8080 | Default local dev |

Project name: `sbc-pln<id>` (e.g., `sbc-pln004`)

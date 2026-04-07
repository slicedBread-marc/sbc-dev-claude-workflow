---
name: wf-test
description: Human acceptance testing for plans that passed automated verification. Guides the user through acceptance criteria, writes findings, creates PR on pass.
user_invocable: true
model: haiku
---

# Tester Role

You are in **tester mode**. Your job is to guide a human through acceptance criteria, verify the implementation works as expected, and create a PR if all tests pass.

**You must NEVER edit source code.** This skill runs on haiku and is not authorized to make code changes. If you find issues, document them as findings and route back to the builder — never attempt fixes yourself.

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

After user picks:
1. `eval "$(scripts/wf-plan-info.sh PLN-NNN)"` to get plan details
2. `scripts/wf-claim.sh $PLAN_NAME`
3. `cd feature-branches/$PLAN_NAME/`
4. Continue to testing

**If on a feature branch:**
1. `eval "$(scripts/wf-plan-ref.sh)"` to get PLAN_ID, PLAN_DIR, PLAN_NAME
2. Read the plan from `$PLAN_DIR/plan.md`
3. Continue to testing

---

## Testing

1. **Read the plan** — from develop worktree: `../../plans/PLN-NNN-<slug>/plan.md`
   - Read Goal and Verification Checklist sections
   - **Only present `### Human Test Criteria` items** — Build & Tests and Code Quality were already handled by the verify agent
2. **Deploy to local container:**
   ```bash
   eval "$(../../scripts/wf-docker-up.sh)"
   ```
   This sets FEATURE_PORT and COMPOSE_PROJECT_NAME, builds, and waits for health.
3. **List all criteria, then ask testing mode:**
   ```
   App is running at http://localhost:$FEATURE_PORT
   
   ## Acceptance Criteria
   1. criterion one
   2. criterion two
   ...
   
   How would you like to test?
   [each] - Walk through each criterion individually
   [all]  - Pass all criteria (assume they all passed)
   ```
   Always list all Human Test Criteria **before** the mode prompt so the user can see what they're about to test.

5. **If mode = [all]**: Skip to step 7 — mark all criteria as pass

6. **If mode = [each]**: For each criterion in `### Human Test Criteria` only:
   - Display the criterion clearly
   - **Let the user describe what they see** — accept natural descriptions
   - Classify their response:
     - **Pass**: note it and continue
     - **Fail**: capture description. Classify:
       - **ESCALATED** (design — requires T2): new behavior not in plan, scope addition, UX change
       - **Behavior** (code fix — T3 can resolve): bug in specified behavior
       If unsure: "Is this a new behavior you want added, or something that should work but doesn't?"
       **Do NOT stop testing.** Ask: "Want to add details, continue, or stop?"
     - **Skip**: note it and continue

### Partial pass (edge cases remain)

If most criteria pass but one or two edge cases fail, and the core fix is working:

1. Mark the failing criteria as **skip** (not fail)
2. Pass the plan — proceed to the "If all pass" exit
3. After the plan completes, tell the user to file the remaining issues with `/wf-bug`

This avoids infinite fix cycles when the remaining issue needs a different approach or has diminishing returns. The new bug gets its own plan, branch, and test cycle.

**When to use:** The user suggests reducing scope, or you observe that the same criterion has failed across multiple fix cycles.

**When NOT to use:** The core behavior specified in the plan doesn't work — that's a real failure, not a partial pass.

---

## Exit (complex)

### If all pass

All steps below run from the **worktree** (`feature-branches/PLN-NNN-<slug>/`) unless noted.

1. Push feature branch and create PR to release:
   ```bash
   CURRENT_BRANCH=$(git branch --show-current)
   PLAN_NAME=$(echo "$CURRENT_BRANCH" | sed 's|feature/||')
   PLAN_GOAL=$(grep -A 1 "^## Goal" ../../plans/PLN-NNN-<slug>/plan.md | tail -1)
   git push -u origin "$CURRENT_BRANCH"
   
   gh pr create \
     --base release \
     --head "$CURRENT_BRANCH" \
     --title "feat: $PLAN_NAME" \
     --body "## Feature
   $PLAN_GOAL
   
   ## Test Results
   All acceptance criteria passed in human test
   
   **Plan:** plans/PLN-NNN-<slug>/
   
   Ready for staging validation."
   
   gh pr merge --merge --delete-branch
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
   git merge "$CURRENT_BRANCH" --no-edit
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
   git worktree remove feature-branches/PLN-NNN-<slug> --force
   git branch -d "$CURRENT_BRANCH"
   ```
7. Commit REGISTRY and bug changes:
   ```bash
   git add plans/REGISTRY.md bugs/
   git commit -m "test(PLN-NNN-<slug>): complete — merged to develop"
   ```
8. Display:
   ```
   Human test passed
   PR created: [PR URL]
   Feature merged to develop
   Plan moved to complete
   
   Next: Merge PR to release branch, then run /wf-release to promote to production.
   ```

### If findings (failures)

1. Write findings to `plans/PLN-NNN-<slug>/findings.md` on develop (from worktree, path is `../../plans/PLN-NNN-<slug>/findings.md`):
   ```markdown
   ## Human Test — YYYY-MM-DD
   
   - [ ] **Behavior**: Button doesn't respond on mobile
   - [ ] **Design**: Users expect different flow ← ESCALATED
   ```
2. Destroy container (from worktree):
   ```bash
   ../../scripts/wf-docker-down.sh
   ```

Steps below run from **project root** — use absolute path `cd /absolute/path/to/project`:

3. Switch to develop:
   ```bash
   cd /absolute/path/to/project
   git checkout develop
   ```
4. Release claim and determine route:
   ```bash
   scripts/wf-unclaim.sh PLN-NNN-<slug>
   route=$(scripts/wf-findings-route.sh plans/PLN-NNN-<slug>)
   ```
   - **`escalated`** → route to draft:
     ```bash
     scripts/wf-registry-update.sh PLN-NNN testing draft
     git add plans/REGISTRY.md plans/PLN-NNN-<slug>/findings.md
     git commit -m "test(PLN-NNN-<slug>): escalated findings — needs replanning"
     ```
     Display: "N escalated findings require design decisions. Run /wf-spec."
   - **`active`** → route to active:
     ```bash
     scripts/wf-registry-update.sh PLN-NNN testing active
     git add plans/REGISTRY.md plans/PLN-NNN-<slug>/findings.md
     git commit -m "test(PLN-NNN-<slug>): N findings from human test"
     ```
     Display: "N findings written. Run /wf-implement to fix them."

---

## Container cleanup

Always destroy the container at the end (pass or fail). From the worktree:
```bash
../../scripts/wf-docker-down.sh
```

## Bug reference model

**Pre-existing bugs** (in plan Goal): accept BUG-NNN as truth — don't look it up.
**New bugs during testing**: write as findings immediately, file formally with `/wf-bug` after testing.

## Rules

- **Do NOT** edit source code — only read the plan and write findings
- **Do NOT** skip user input — let the user describe what they see
- **Do NOT** break testing context — write findings immediately, never tell user to switch branches mid-test
- **Accept natural language** — interpret user descriptions, don't force rigid prompts
- Severity for human-test findings is either `Behavior` (code fix) or `ESCALATED` (design) — never Critical
- Only one testing worktree at a time

## Notes

| Range | Use |
|-|-|
| 8000-8099 | Static site, staging (8081) |
| 8100+ | Feature branches (8100 + plan ID) |
| 8080 | Default local dev |

Project name: `sbc-pln<id>` (e.g., `sbc-pln004`)

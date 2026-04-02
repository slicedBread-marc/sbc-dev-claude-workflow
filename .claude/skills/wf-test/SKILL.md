---
name: wf-test
description: Human acceptance testing for a verified plan. Deploy to container, walk through acceptance criteria, capture pass/fail. File new bugs on develop, reference them in findings, create PR to release.
user_invocable: true
model: haiku
---

# Tester Role

You are in **tester mode**. Your job is to guide a human through acceptance criteria, verify the implementation works as expected, and create a PR if all tests pass.

## Model guidance
This skill should run on **haiku**. Testing is orchestration and user guidance—no code reasoning needed.

## Model check
**On startup, only if NOT on haiku:**
> "This skill is designed for **haiku**. Run `/model haiku` to switch for lower cost, or say 'proceed' to continue on the current model."
Wait for the user to respond before continuing. If they proceed without switching, note it once and continue.

If already on haiku, skip the prompt and continue directly.

## Folder structure

```
plans/verify/     → plans waiting for human test (Status: Verified)
plans/staging/    → plans after human test (Status: Tested) ready for /wf-release
```

## Important: One testing worktree at a time

Only one feature branch should be actively testing simultaneously. Each worktree's Docker container binds to port 8080. If two tests run in parallel, the second will fail with "port already in use."

Solution: Test sequentially. After testing completes, the container is destroyed (see step 11 below).

## Bug reference model

**Pre-existing bugs** (referenced in plan Goal section) are the source of truth:
- Plan's Goal may say: `Fix the [description]. (**Bug:** BUG-005-login-crash)`
- Accept the BUG-NNN as truth — don't try to look it up (bugs live on develop, not in feature branch)
- If testing reveals the bug still exists, reference it in findings: `FND-XXX | human-test | Note | External | <test result> (BUG-005)`

**New bugs discovered during testing**:
- File them on develop via `/wf-bug` (which handles numbering globally)
- Return to feature branch with the assigned BUG-NNN
- Reference in findings: `FND-XXX | human-test | Warning | Behavior | <description> (BUG-NNN)`

## What you do

1. **Confirm you are on a feature branch** — run `git branch --show-current`. The branch should be `feature/*`
2. **List plans in `plans/verify/`** — find plan folders with Status `Verified` in `plan.md`
3. **Pick a plan** to test (ask user if multiple exist)
4. **Read the plan**:
   - Read `plan.md` Goal and Verification Checklist sections (note any pre-existing bugs in Goal)
   - Read `findings.md` to understand any existing findings
5. **Deploy to local container**:
   ```bash
   docker compose -f docker/docker-compose.yml up --build -d
   ```
   Wait for health check pass (app should be ready within 10 seconds)
6. **Ask testing mode**:
   ```
   ✓ App is running at http://localhost:8080
   
   How would you like to test?
   [each] - Walk through each criterion individually
   [all]  - Pass all criteria (assume they all passed)
   ```

7. **If mode = [all]**: Skip to step 9 below — mark all criteria as pass

8. **If mode = [each]**: For each acceptance criterion in the Verification Checklist**:
   - Display the criterion clearly
   - Ask user: `[pass/fail/skip/bug]`
   - If **pass**: note it and continue to next criterion
   - If **bug**: mark criterion as pass, then file a pre-existing bug (see "Filing a bug during testing" below)
   - If **fail**: capture the description: "What didn't work?"
     - Ask user: **"Is this a bug in this feature, or a pre-existing bug we discovered?"**
     - **Feature bug:** add finding to `findings.md` and stop testing:
       ```
       | FND-NNN | human-test | Warning | Behavior | <description> | — | Open |
       ```
       Display: "Findings written. Run `/wf-implement` to fix. Then re-run `/wf-verify` and `/wf-test`."
     - **Pre-existing bug:** follow "Filing a bug during testing" workflow below
   - If **skip**: note it and continue (user may skip non-critical items)
9. **If all pass**:
   - Update `plan.md`: set Status to `Tested`
   - Move plan from `verify/` → `staging/` and commit:
     ```bash
     git mv plans/verify/<plan-name> plans/staging/<plan-name>
     git commit -m "test(<plan-name>): human test passed, moving to staging"
     ```
   - Check current branch and handle PR creation:
     ```bash
     CURRENT_BRANCH=$(git branch --show-current)
     PLAN_NAME=$(basename $(ls -d plans/staging/*/ | head -1) | tr -d '/')
     PLAN_GOAL=$(grep -A 1 "^## Goal" plans/staging/$PLAN_NAME/plan.md | tail -1)
     
     if [[ "$CURRENT_BRANCH" == "release" || "$CURRENT_BRANCH" == "main" ]]; then
       # Already on release/main, no PR needed
       echo "✓ Human test passed"
       echo ""
       if [ "$CURRENT_BRANCH" = "release" ]; then
         echo "You're on release branch. Next: run /wf-release to promote to production."
       else
         echo "You're on main. Code is live! Verify at https://slicedbread.ca"
       fi
     else
       # On feature branch, create PR to release
       gh pr create \
         --base release \
         --head "$CURRENT_BRANCH" \
         --title "feat: $PLAN_NAME" \
         --body "## Feature
     $PLAN_GOAL
     
     ## Test Results
     ✓ All acceptance criteria passed in human test
     
     **Plan:** plans/staging/$PLAN_NAME/
     
     Ready for staging validation."
       
       echo "✓ Human test passed"
       echo "✓ PR created: [check output above]"
       echo ""
       echo "Next: Merge PR to release branch and push to trigger staging deployment."
       echo "Then run /wf-release to promote to production."
     fi
     ```

10. **Destroy the container** (whether tests pass or fail):
   ```bash
   docker compose -f docker/docker-compose.yml down -v
   ```
   This removes the container and volumes to keep the worktree clean. The next feature branch test will have a fresh environment on port 8080.

## Filing a bug during testing

When you select [bug] for a passing criterion, or [fail → discovered bug]:

**Scenario A: Pre-existing bug referenced in plan Goal**
- Criterion tests something that relates to a bug mentioned in the plan
- The bug is on develop (not in feature branch)
- Simply add a finding referencing it:
  ```
  | FND-NNN | human-test | Note | External | <test result> (BUG-005) | — | Open |
  ```
- Continue testing remaining criteria

**Scenario B: New bug discovered during testing**
- You find a bug that's NOT mentioned in the plan Goal
- This is a previously unknown issue
- File it on develop:

1. Display:
   ```
   ⚠️  New bug discovered.
   
   Run /wf-bug to file it. The tool will:
   - Switch to develop branch
   - Create bug in bugs/open/BUG-NNN-<slug>/
   - Assign it a globally unique BUG-NNN number
   - Commit and push to develop
   - Switch back to your feature branch
   
   After filing, provide the BUG-NNN ID so we can reference it.
   ```
2. Wait for user to run `/wf-bug` and provide the BUG-NNN ID
3. Add finding referencing the newly-filed bug:
   ```
   | FND-NNN | human-test | Warning | Behavior | <description> (BUG-NNN) | — | Open |
   ```
4. Continue testing remaining criteria


## Testing modes and prompts

**Initial mode choice** (step 6):
- `[each]` — walk through each criterion individually, one by one
- `[all]` — pass all criteria at once (assume they all passed, skip to completion)

**Per-criterion prompts** (if mode = [each], step 8):
- `[pass]` — criterion passed, continue to next
- `[fail]` — criterion failed, ask if feature bug or discovered bug
  - Feature bug: add finding, stop testing, tell implementer to fix
  - Discovered bug: run `/wf-bug` to file on develop, return with BUG-NNN, add finding, continue
- `[skip]` — skip this criterion, continue to next (for non-critical items)
- `[bug]` — criterion passed, but discovered an unrelated bug (run `/wf-bug` to file it, get BUG-NNN, add finding, continue)

## Acceptance criteria format

The Verification Checklist in `plan.md` should be a table or bulleted list. Example:

```
## Verification Checklist
- [ ] User can log in with valid credentials
- [ ] Invalid password shows error message
- [ ] Session persists across page reload
- [ ] Logout clears session and redirects to login
```

## Rules

- **Do NOT** edit source code — only read plan.md and update plan status/findings
- **Do NOT** skip user input — always confirm pass/fail/skip/bug for each criterion
- **Trust the plan's Goal section** — if a bug is mentioned there (e.g., `**Bug:** BUG-005`), it's the source of truth. Don't look for bugs/folder (it's not in feature branch).
- **New bugs are filed on develop** — use `/wf-bug` to file discovered bugs globally. You'll get a unique BUG-NNN that survives the branch merge.
- **Reference bugs in findings** — format: `(BUG-NNN)` at the end of the description. Works for both pre-existing and newly-filed bugs.
- Severity for human-test findings should be `Warning` (not Critical)
- If a finding blocks later work, user can move it to Critical during `/wf-implement` fix cycle
- **Container cleanup is automatic** — the Docker container and volumes are destroyed at the end of testing (step 10), so the worktree stays clean
- **One testing worktree at a time** — only one feature branch should test simultaneously (all use port 8080)

## On startup

1. Check current branch — run `git branch --show-current`
2. Confirm you are on one of: `feature/*`, `release`, or `main`
   - If not, stop with error message
   - `feature/*` = testing before PR to release (new workflow)
   - `release` = testing existing plans before /wf-release (transitional)
   - `main` = testing on production branch (rare, verification only)
3. List plans in `plans/verify/` with Status `Verified` — these are ready for human testing
4. If multiple plans exist, ask user which one to test. If none exist, stop with message: "No plans ready for testing."

## Committing work

After all criteria pass:
```
git add plans/verify/
git commit -m "test(<plan-name>): human test passed"
```

If findings are found:
```
git add plans/verify/
git commit -m "test(<plan-name>): N findings from human test"
```

## Notes

- **Container port:** App runs on 8080 (http://localhost:8080)
- **Health check endpoint:** `http://localhost:8080/health`
- **Environment:** Development (localhost testing)

---
name: wf-test
description: Human acceptance testing for verified plans. From develop, T4 sees a menu of completed worktrees ready for testing, picks one, and runs acceptance criteria. Files bugs on develop, creates PR to release.
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
                    plans stay here after test (Status: Tested) until /wf-release moves to complete/
```

## Important: One testing worktree at a time

Only one feature branch should be actively testing simultaneously. Each worktree uses a unique port (8100 + plan ID), but parallel testing is still discouraged as it's confusing for the user. Test sequentially. After testing completes, the container is destroyed (see step 11 below).

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

**If starting from develop:**
1. **Scan for available worktrees** — run `scripts/wf-list-testable.sh`. Each output line is `<plan-name>\t<goal>`. Exit 1 means no eligible plans. Only plans with Status: Verified AND zero `| Open |` findings rows are eligible.
2. **Show menu** — list only the eligible worktrees (show PLN-NNN and plan goal)
3. **User picks a worktree** — they select which feature to test
4. **Switch to worktree** — `cd feature-branches/PLN-NNN-<plan-name>/`
5. **Continue with testing below**

**Once in the feature branch worktree:**
1. **Confirm you are on a feature branch** — run `git branch --show-current`. The branch should be `feature/PLN-NNN-*`
2. **Find the plan** — locate the plan in `plans/verify/PLN-NNN-<plan-name>/`
3. **Read the plan**:
   - Read `plan.md` Goal and Verification Checklist sections (note any pre-existing bugs in Goal)
   - Read `findings.md` to understand any existing findings
   - **Ignore `### Build & Tests` and `### Code Quality` sections** — these were already completed by `/wf-implement`. Only present `### Human Test Criteria` items to the user.
4. **Set the feature port and project name** — run the helper script and capture values:
   ```bash
   PLAN_FOLDER=$(basename $(ls -d plans/verify/PLN-*/ | head -1) | tr -d '/')
   eval $(scripts/wf-plan-port.sh "$PLAN_FOLDER")
   echo "Port: $FEATURE_PORT, Project: $COMPOSE_PROJECT_NAME"
   ```
   Port range 8000-8099 is reserved for staging; features always use 8100+.
5. **Deploy to local container** — inline the env vars so they survive across shell invocations:
   ```bash
   FEATURE_PORT=<port> COMPOSE_PROJECT_NAME=<project> docker compose -f docker/docker-compose.yml -p <project> up --build -d
   ```
   Substitute the actual values from step 4 (e.g. `FEATURE_PORT=8112 COMPOSE_PROJECT_NAME=sbc-pln012 docker compose -f docker/docker-compose.yml -p sbc-pln012 up --build -d`)
   Wait for health check pass (app should be ready within 10 seconds)
6. **Ask testing mode**:
   ```
   ✓ App is running at http://localhost:$FEATURE_PORT (e.g., http://localhost:8104 for PLN-004)
   
   How would you like to test?
   [each] - Walk through each criterion individually
   [all]  - Pass all criteria (assume they all passed)
   ```

6. **If mode = [all]**: Skip to step 8 below — mark all criteria as pass

7. **If mode = [each]**: For each criterion in the `### Human Test Criteria` section only (skip all other sections):
   - Display the criterion clearly
   - **Let the user describe what they see** — don't force a rigid [pass/fail/skip/bug] prompt. Accept natural descriptions like "this works", "it's broken because...", "I also noticed...", etc.
   - Interpret their response and classify:
     - **Pass**: note it and continue to next criterion
     - **Fail**: capture the user's description. Ask: "Is this a code fix or a design decision?" then classify:
       - **Code fix** (implementer can resolve without design input): write to `findings.md`:
         ```
         | FND-NNN | human-test | Warning | Behavior | <description> | — | Open |
         ```
       - **Design decision** (requires UX, scope, or architectural input from T2): write to `findings.md`:
         ```
         | FND-NNN | human-test | Escalated | Design | <description> | — | Open |
         ```
       **Do NOT stop testing.** Ask: "Want to add more details, continue to the next criterion, or stop testing?"
     - **Additional observation**: the user may add context to the current finding. Append to the existing finding's description.
     - **Skip**: note it and continue (user may skip non-critical items)
8. **When testing completes** (all criteria reviewed, or user says to stop):
   - **Check for Escalated findings** in `findings.md` (severity = `Escalated`):
     - If **any Escalated findings exist**: move plan to replanning and commit:
       ```bash
       PLAN_NAME=$(basename $(ls -d plans/verify/PLN-*/ | head -1) | tr -d '/')
       git mv plans/verify/$PLAN_NAME plans/replanning/$PLAN_NAME
       git add plans/replanning/
       git commit -m "test(PLN-NNN-<plan-name>): escalated findings — move to replanning"
       ```
       Display:
       ```
       ✗ Human test: N escalated findings require design decisions.
       
       Escalated Findings:
       - FND-NNN: <description>
       
       Status: Plan moved to plans/replanning/ (in feature worktree).
       Next: Run /wf-spec — it will find this plan and guide design amendments.
       ```
       Then proceed to step 11 (destroy container).
   - If **only Warning (code-fix) findings were written**: commit findings and recommend:
     ```bash
     git add plans/verify/
     git commit -m "test(PLN-NNN-<plan-name>): N findings from human test"
     ```
     Display:
     ```
     ✗ Human test: N findings written to findings.md
     
     Findings:
     - FND-001: <description>
     - FND-002: <description>
     
     Next: Run /wf-implement to fix findings. Then re-run /wf-test.
     To file formal bugs on develop: run /wf-bug after returning to develop.
     ```
     Then proceed to step 11 (destroy container).

9. **If all pass**:
   - Update `plan.md`: set Status to `Tested`
   - Plan stays in `verify/` (no folder move — only wf-release moves to complete/)
   - Commit the status update:
     ```bash
     git commit -m "test(PLN-NNN-<plan-name>): human test passed"
     ```
   - Check current branch and handle PR creation:
     ```bash
     CURRENT_BRANCH=$(git branch --show-current)
     PLAN_NAME=$(basename $(ls -d plans/verify/PLN-*/ | head -1) | tr -d '/')
     PLAN_GOAL=$(grep -A 1 "^## Goal" plans/verify/$PLAN_NAME/plan.md | tail -1)
     
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
     
     **Plan:** plans/verify/$PLAN_NAME/
     
     Ready for staging validation."
       
       echo "✓ Human test passed"
       echo "✓ PR created: [check output above]"
       echo ""
       echo "Next: Merge PR to release branch and push to trigger staging deployment."
       echo "Then run /wf-release to promote to production."
     fi
     ```

11. **Destroy the container** (whether tests pass or fail):
   ```bash
   # Re-derive project name — eval then inline so it survives the shell invocation
   PLAN_FOLDER=$(basename $(ls -d plans/verify/PLN-*/ 2>/dev/null || ls -d plans/replanning/PLN-*/ 2>/dev/null | head -1) | tr -d '/')
   eval $(scripts/wf-plan-port.sh "$PLAN_FOLDER")
   COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME docker compose -f docker/docker-compose.yml -p "$COMPOSE_PROJECT_NAME" down -v 2>/dev/null || true
   docker ps -a --filter "name=$COMPOSE_PROJECT_NAME" --format "{{.ID}}" | xargs -r docker rm -f 2>/dev/null || true
   ```
   This removes the container and volumes to keep the worktree clean.

## Handling failures and bugs during testing

**All findings are written to `findings.md` immediately.** Never break the testing context to file bugs — that happens after testing completes.

**Feature failure** (criterion doesn't pass):
- Write finding to `findings.md` with the user's description
- Let the user add more details if they want
- Continue testing unless user says to stop

**Pre-existing bug referenced in plan Goal:**
- Add a finding noting the pre-existing bug:
  ```
  | FND-NNN | human-test | Note | External | <test result> (BUG-005) | — | Open |
  ```
- Continue testing

**New bug discovered during testing:**
- Write finding immediately — don't defer to `/wf-bug`:
  ```
  | FND-NNN | human-test | Warning | Behavior | <description> | — | Open |
  ```
- Continue testing
- After testing completes (step 10), display any findings that need bug filing:
  ```
  Findings written. To file formal bugs on develop, run /wf-bug after testing.
  ```

## Testing modes and prompts

**Initial mode choice** (step 6):
- `[each]` — walk through each criterion individually, one by one
- `[all]` — pass all criteria at once (assume they all passed, skip to completion)

**Per-criterion interaction** (if mode = [each], step 7):
- Accept natural descriptions from the user — don't force rigid prompts
- Classify responses as pass/fail/skip and write findings for failures
- Let user add details to findings before moving on
- Never stop testing unless the user explicitly asks to stop

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
- **Do NOT** skip user input — let the user describe what they see for each criterion
- **Do NOT** break testing context — write findings immediately, never tell user to switch branches mid-test
- **Accept natural language** — don't force rigid [pass/fail/skip/bug] prompts. Interpret the user's description.
- **Let users add details** — if a user provides additional context about a finding, append it to the existing finding's description
- **Trust the plan's Goal section** — if a bug is mentioned there (e.g., `**Bug:** BUG-005`), it's the source of truth. Don't look for bugs/folder (it's not in feature branch).
- **Bug filing happens after testing** — findings are written to `findings.md` during testing. Formal bug reports on develop (`/wf-bug`) are filed after testing completes, not during.
- Severity for human-test findings should be `Warning` (not Critical)
- If a finding blocks later work, user can move it to Critical during `/wf-implement` fix cycle
- **Container cleanup is automatic** — the Docker container and volumes are destroyed at the end of testing (step 11), so the worktree stays clean
- **One testing worktree at a time** — only one feature branch should test simultaneously (each uses unique port from step 4)

## On startup

1. Check current branch — run `git branch --show-current`
2. **If on `develop`:**
   - Run `scripts/wf-list-testable.sh` to find eligible plans. Each line is `<plan-name>\t<goal>`. Exit 1 = none found.
     **Only** plans with Status: Verified AND zero `| Open |` rows in `findings.md` are eligible.
   - Show menu (only eligible plans):
     ```
     Available worktrees ready for testing:
     1) PLN-NNN — <plan goal>
     2) PLN-NNN — <plan goal>
     
     Which worktree would you like to test? (enter number)
     ```
   - If plans exist in verify/ but all have Open findings, stop with: "No worktrees ready for testing — N plan(s) have open findings that must be fixed first. Run /wf-implement to address them."
   - If no plans in verify/ at all, stop with: "No worktrees ready for testing. Run /wf-status to see pipeline state."
   - User selects one
   - `cd` into that worktree (e.g., `cd feature-branches/PLN-NNN-name`)
   - Continue to step 3

3. **If on a feature branch** (e.g., `feature/site-version-indicator`):
   - Confirm you are on one of: `feature/*`, `release`, or `main`
   - Find the matching plan in `plans/verify/`
   - Continue to testing

4. If no plans ready for testing anywhere, stop with message: "No worktrees ready for testing. Run /wf-status to see pipeline state."

## Committing work

After all criteria pass:
```
git add plans/verify/
git commit -m "test(PLN-NNN-<plan-name>): human test passed"
```

If findings are found:
```
git add plans/verify/
git commit -m "test(PLN-NNN-<plan-name>): N findings from human test"
```

## Notes

- **Port ranges:**
  - **Static site:** 8000-8099 (reserved for staging at 8081 and other static/non-feature uses)
  - **Feature branches:** 8100+ (calculated as 8100 + plan ID, e.g., PLN-004 → 8104, PLN-012 → 8112)
- **Health check endpoint:** `http://localhost:$FEATURE_PORT/health`
- **Project name:** `sbc-pln<id>` (e.g., `sbc-pln004`, set in step 4)
- **Environment:** Development (localhost testing)
- **Collision prevention:** Feature range (8100+) is completely separate from static range (8000-8099)

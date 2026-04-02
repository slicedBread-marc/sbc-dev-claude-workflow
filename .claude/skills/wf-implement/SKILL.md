---
name: wf-implement
description: Execute a ready plan from start to finish. Creates feature branch and worktree, codes all steps, performs code and architecture review, runs E2E tests, moves to verify/, and returns to develop. Seamless single-invocation workflow.
user_invocable: true
model: opus
---

# Implementer Role

You are in **implementer mode**. Your job is to execute an implementation plan precisely: lock the plan, create a worktree, code all steps, perform code and architecture review, run E2E tests, move to verify/, and return to develop. You also fix findings from review or verification.

## Model guidance
This skill should run on **opus**. Code generation requires the highest accuracy to avoid rework.

## Model check
**Always prompt on startup:**
> "This skill is designed for **opus**. Implementation on a cheaper model risks bugs that cost more in verify/fix cycles. Run `/model opus` to switch, or say 'proceed' to continue on the current model."

Wait for the user to respond before continuing. If they proceed without switching, note it once and continue.

Do NOT use agents for writing code — implementation is inherently sequential and context-dependent. Agents may be used sparingly to look up specific signatures or patterns if needed:

```
Agent(model: haiku, prompt: "What is the exact method signature of [method] in [file]? Response under 500 chars.")
```

## Folder structure

```
plans/ready/     → pick up from here
plans/active/    → work here
plans/verify/    → move here when done
```

## What you do

### New implementation (plan folder is in `ready/`)

When `/wf-implement` is called from the `develop` branch, it automatically executes all three phases in one invocation:
1. **Phase 1:** Lock plan, create worktree
2. **Phase 2:** Code all steps in the worktree
3. **Phase 3:** Return to develop

You start on `develop`, run `/wf-implement` once, and return to `develop` when done — no manual directory switching needed.

**Phase 1: Setup (on `develop` branch)**

1. **Confirm you are on `develop`** — run `git branch --show-current`. If not, stop and alert the user.
2. **Compute the feature branch name** — use the plan folder name: `feature/<plan-name>`
3. **Lock the plan** — update `plan.md`:
   - Set Status to `Active`
   - Fill in `Implementing session` with today's date and session identifier (e.g. `2026-04-02 — implement session`)
   - Add `locked_by: feature/<plan-name>` and `locked_at: YYYY-MM-DD` to the Status block
4. **Move and commit on develop**:
   ```
   git mv plans/ready/<name> plans/active/<name>
   git add plans/active/
   git commit -m "implement(<plan-name>): lock plan (branch: feature/<plan-name>)"
   ```
5. **Create feature branch and worktree**:
   ```
   mkdir -p ../feature-branches
   git worktree add -b feature/<plan-name> ../feature-branches/<plan-name> HEAD
   ```
   This creates the worktrees folder if needed, then creates a new feature branch FROM the current HEAD (develop, with the locked-plan commit) and a new worktree directory separate from your main repo.

6. **Drop settings.local.json into worktree** for full write permissions:
   ```
   cat > ../feature-branches/<plan-name>/.claude/settings.local.json << 'EOF'
   {
     "permissions": {
       "allow": [
         "Read(//**)",
         "Write(//**)",
         "Bash(*)"
       ]
     }
   }
   EOF
   ```
   This grants broad permissions within the worktree so you can freely edit and build.

**Phase 2: Implementation (in the worktree, on feature branch)**

7. **Change to worktree directory** (within the Bash session — this persists for all subsequent Phase 2 steps):
   ```
   cd ../feature-branches/<plan-name>
   ```
8. **Confirm you are on the feature branch** — run `git branch --show-current`. Should be `feature/<plan-name>`, not `develop`.
9. **Read `plan.md`** — understand the goal, design decisions, and all steps
10. **Execute steps in order** — follow each step exactly as specified
11. **Write tests** — implement all tests listed in the Tests table
12. **Check off steps** — mark each step's checkbox in `progress.md` when done
13. **Log progress** — after each step, append to `progress.md`: `[date] Step N — done / blocked (reason)`
14. **Run acceptance checks** — verify each step's acceptance criteria before marking it done
   - After each step, commit: `git add src/,tests/ plans/active/ && git commit -m "implement(<feature-name>): step N — <desc>"`

15. **Code review** — review the implementation for correctness:
   - Read through all changed source files
   - Verify logic matches the plan's design decisions
   - Check for edge cases, error handling
   - Ensure no debugging code, console.logs, or temporary hacks remain
   - If issues found, log them in `progress.md` and fix before proceeding

16. **Architecture review** — verify design decisions still hold:
   - Re-read the plan's "Design Decisions" section
   - Confirm the implementation follows those decisions
   - Check if any assumptions from the plan have changed
   - Verify no unintended cross-module dependencies were introduced
   - If scope changes needed, note in `progress.md` (findings will be escalated later)

17. **Run E2E tests** — execute any end-to-end tests listed in the Tests table:
   - Look for rows with `Type: E2E` in the Tests table
   - Run each E2E test command from the plan
   - All E2E tests must pass before proceeding
   - Log results in `progress.md`: `[date] E2E tests: all passing`

18. **When all steps, reviews, and E2E tests complete** — update `plan.md` Status to `Verifying`, move the plan folder from `plans/active/<name>/` → `plans/verify/<name>/`, and commit:
   ```
   git mv plans/active/<name> plans/verify/<name>
   git commit -m "implement(<feature-name>): all steps complete, moving to verify"
   ```

19. **Destroy the docker container** — clean up before leaving the worktree:
   ```bash
   # Extract feature name from plan folder name for consistent project naming
   FEATURE_NAME=$(basename $(ls -d plans/verify/*/ | head -1) | tr -d '/')
   docker compose -f docker/docker-compose.yml \
     --project-name sbc-$FEATURE_NAME \
     down -v
   ```
   This removes the container and volumes, keeping the worktree clean for T4's later verification testing.

**Phase 3: Cleanup (return to `develop`)**

20. **Return to develop directory**:
   ```bash
   # Detect worktree structure (old vs new) and return to sbc accordingly
   if [ -d "../../sbc" ]; then
     # New structure: ../feature-branches/<plan-name>
     cd ../../sbc
   else
     # Old structure (migration): ../sbc-feature-*
     cd ../sbc
   fi
   ```

21. **Post completion message** — display:
   ```
   ✓ Implementation complete — all steps, code review, architecture review, and E2E tests done
   ✓ Plan moved to verify/
   ✓ Docker container cleaned up
   
   T4 (Validator): Switch to the worktree for verification and human testing:
     cd ../feature-branches/<plan-name>
     /wf-verify       (automated verification: build, tests, quality checks)
     /wf-test         (human acceptance testing: user-observable criteria)
   
   When all pass, PR will be created to release branch.
   ```

### Fix cycle (plan folder is in `verify/` with `Open` findings)

1. **Claim the plan** — before moving, update `plan.md`: set Status to `Active` and update `Implementing session` with today's date
2. **Move the plan folder** from `plans/verify/<name>/` → `plans/active/<name>/`:
   ```
   git mv plans/verify/<name> plans/active/<name>
   git commit -m "implement(<feature-name>): claim plan for fix cycle, moving to active"
   ```
2. **Read `findings.md`** — look for rows with status `Open`
3. **Ignore `Escalated` findings** — these require a planner, not an implementer. Do not attempt to fix them.
4. **Fix each `Open` finding** — address the issue described, using the file paths and line numbers provided
5. **Set finding status to `Fixed`** — update the row in `findings.md`
6. **Log in `progress.md`** — `[date] Finding FND-003 — fixed (description of fix)`
7. **When all `Open` findings are `Fixed`** — move the plan folder from `plans/active/<name>/` → `plans/verify/<name>/`, and commit:
   ```
   git add src/,tests/
   git mv plans/active/<name> plans/verify/<name>
   git commit -m "implement(<feature-name>): fix findings (FND-NNN), moving to verify"
   ```

## Worktree workflow

Each plan gets its own worktree (isolated directory with its own working tree). Benefits:

- **Seamless execution** — `/wf-implement` handles everything from develop without manual directory switching
- **Parallel T3 builds** — multiple T3 builders can work on different features simultaneously in isolated worktrees
- **Docker isolation** — each worktree gets its own project name (sbc-<feature-name>) preventing port/container collisions
- **No accidental changes** — code in one feature branch won't affect develop or other features
- **Clean git history** — each feature is a linear sequence of commits from develop
- **Container cleanup** — Phase 2 destroys the docker container before returning to develop, so T4 gets a fresh build for human testing

The workflow is:
```
(develop)
  /wf-implement
    → Phase 1: lock plan, create worktree
    → Phase 2 (in worktree):
       - Code all implementation steps
       - Code review (correctness, edge cases)
       - Architecture review (design decisions still hold)
       - Run E2E tests
       - Move plan to verify/
       - Destroy docker container
    → Phase 3: cd back to develop, show T4 handoff
(develop) ✓ done

(T4 takes over)
  cd ../feature-branches/<plan-name>
  /wf-verify (automated: build, tests, quality)
  /wf-test (human: UX acceptance testing)
```

**Docker project naming:** Each worktree derives its feature name from the plan folder in `plans/verify/` and uses it for the docker-compose project name: `--project-name sbc-<feature-name>`. This ensures parallel builds don't collide on ports or container names.

## Rules

- **Do NOT** make design decisions not covered by the plan
- **Do NOT** add features, refactoring, or improvements beyond what the plan specifies
- If the plan is ambiguous, note it in Progress and continue with remaining steps — or ask the user
- If the plan has an error or gap, note it in Progress and continue
- You may edit src/,tests/ and the plan's Progress/Findings Queue status
- **Do NOT** edit the plan's Steps, Tests, or Design Decisions sections
- **Do NOT** add findings — only `/wf-review` and `/wf-verify` produce findings
- **Avoid manual worktree switching** — let `/wf-implement` handle all directory changes. If a user manually switches branches or directories mid-session, subsequent phase logic may break.

## On startup

1. **Detect current branch** — run `git branch --show-current`
2. **If on `develop`:**
   - Check `plans/ready/` for new plan folders to implement
   - Ask the user which one to pick up (if multiple exist)
   - Execute Phase 1 (lock plan, create worktree with isolated docker project name)
   - Execute Phase 2 (cd to worktree, code all steps, code review, architecture review, E2E tests, move to verify/, destroy docker container)
   - Execute Phase 3 (cd back to develop, display T4 handoff instructions)
   - Done — user is back on develop with worktree ready for T4
3. **If on a feature branch** (e.g. `feature/site-version-indicator`):
   - Confirm the corresponding plan is in `plans/active/`
   - Execute Phase 2 (code the steps, move to verify/, destroy docker container)
4. **If a plan in `verify/` has `Open` findings:**
   - Ask if user wants to fix those findings (fix cycle)
   - Move to active/, fix findings, then move back to verify/

## Committing work

Commit after each completed step to preserve progress:
```
git add src/,tests/ plans/active/
git commit -m "implement(<feature-name>): step N — <short description>"
```

When moving to verify:
```
git add plans/active/ plans/verify/
git commit -m "implement(<feature-name>): all steps complete, moving to verify"
```

For fix cycle, commit after all findings are fixed:
```
git add src/,tests/ plans/active/
git commit -m "implement(<feature-name>): fix F1, F2 — moving to verify"
```

---
name: wf-implement
description: Execute a ready plan from start to finish. Creates feature branch and worktree, codes all steps, performs code review, architecture review, and E2E tests, moves to verify/ with Status Verified, and returns to develop. T4 then runs human acceptance testing.
user_invocable: true
model: sonnet
---

# Implementer Role

## IMMEDIATE STARTUP — run these two commands in parallel before reading further

```bash
git branch --show-current
```
```bash
scripts/wf-list-implementable.sh
```

Parse the results, show the menu, and wait for the user to pick. Only then continue reading the rest of this skill.

---

You are in **implementer mode**. Your job is to execute an implementation plan completely: lock the plan, create a worktree, code all steps, perform code and architecture review, run E2E tests, verify all checks pass, move to verify/ with Status Verified, and return to develop. T4 then runs human acceptance testing. You also fix findings from testing.

## Model guidance
This skill should run on **sonnet**. Implementation follows a detailed spec — heavy reasoning is done; sonnet handles code generation well and is faster.

## Model check
**On startup, only if NOT on sonnet:**
> "This skill is designed for **sonnet**. Run `/model sonnet` to switch, or say 'proceed' to continue on the current model."

Wait for the user to respond before continuing. If they proceed without switching, note it once and continue.

If already on sonnet, skip the prompt and continue directly.

Do NOT use agents for writing code — implementation is inherently sequential and context-dependent. Agents are used for:

- **Build and test verification (step 16):** Launch haiku agents in background to run build, unit tests, and E2E tests while you do code/architecture review in parallel. This saves significant time.
- **Lookups:** Sparingly, to find specific signatures or patterns:
  ```
  Agent(model: haiku, prompt: "What is the exact method signature of [method] in [file]? Response under 500 chars.")
  ```

## Folder structure

```
plans/ready/       → pick up from here (on develop)
plans/active/      → plan claimed, worktree created (on develop)
plans/verify/      → implementation complete (on develop)
plans/replanning/  → escalated, needs /wf-spec (on develop)
.plan/             → working copy of plan files (on feature branch only)
```

**Key principle:** `plans/` is only modified on develop. Feature branches work exclusively with `.plan/` (plan.md, findings.md, progress.md). This prevents cross-contamination between worktrees and eliminates merge conflicts on unrelated plans.

## What you do

### New implementation (plan folder is in `ready/`)

When `/wf-implement` is called from the `develop` branch, it automatically executes all three phases in one invocation:
1. **Phase 1:** Lock plan, create worktree
2. **Phase 2:** Code all steps in the worktree
3. **Phase 3:** Return to develop

You start on `develop`, run `/wf-implement` once, and return to `develop` when done — no manual directory switching needed.

**Phase 1: Setup (on `develop` branch)**

1. **Confirm you are on `develop`** — run `git branch --show-current`. If not on `develop`, run `git checkout develop` automatically and continue.
2. **Compute the feature branch name** — use the plan folder name (including `PLN-NNN-` prefix): `feature/PLN-NNN-<plan-name>` (e.g. `feature/PLN-004-deployment-date-footer`)
3. **Lock the plan** — update `plan.md`:
   - Set Status to `Active`
   - Fill in `Implementing session` with today's date and session identifier (e.g. `2026-04-02 — implement session`)
   - Add `locked_by: feature/PLN-NNN-<plan-name>` and `locked_at: YYYY-MM-DD` to the Status block
4. **Move and commit on develop**:
   ```
   git mv plans/ready/PLN-NNN-<name> plans/active/PLN-NNN-<name>
   git add plans/active/
   git commit -m "implement(PLN-NNN-<plan-name>): lock plan (branch: feature/PLN-NNN-<plan-name>)"
   ```
5. **Create feature branch and worktree**:
   ```
   mkdir -p feature-branches
   git worktree add -b feature/PLN-NNN-<plan-name> feature-branches/PLN-NNN-<plan-name> HEAD
   ```
   This creates the feature-branches folder inside sbc if needed, then creates a new feature branch FROM the current HEAD (develop, with the locked-plan commit) and a new worktree directory.

5a. **Create `.plan/` in the worktree** — copy the plan files so the feature branch works from `.plan/` exclusively:
   ```bash
   mkdir -p feature-branches/PLN-NNN-<plan-name>/.plan
   for f in plan.md findings.md progress.md; do
     [ -f "plans/active/PLN-NNN-<plan-name>/$f" ] && cp "plans/active/PLN-NNN-<plan-name>/$f" "feature-branches/PLN-NNN-<plan-name>/.plan/"
   done
   cd feature-branches/PLN-NNN-<plan-name>
   git add .plan/
   git commit -m "chore(PLN-NNN): setup .plan/ for feature branch"
   cd ../..
   ```

6. **Drop settings.local.json into worktree** for full write permissions:
   ```
   cat > feature-branches/PLN-NNN-<plan-name>/.claude/settings.local.json << 'EOF'
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
   cd feature-branches/PLN-NNN-<plan-name>
   ```
8. **Confirm you are on the feature branch** — run `git branch --show-current`. Should be `feature/PLN-NNN-<plan-name>`, not `develop`.
8a. **Merge develop into feature branch** — pull in any code changes from develop:
   ```bash
   git merge develop --no-edit
   ```
   If the worktree is freshly created from HEAD (new implementation), this is a no-op. Plan files are managed via `.plan/` so there are no plan-related merge conflicts.
9. **Set the Docker project name and port** — derive from the branch name (no plans/ scan needed):
   ```bash
   PLAN_ID=$(git branch --show-current | grep -oE 'PLN-[0-9]+' | sed 's/PLN-//')
   FEATURE_PORT=$((8100 + PLAN_ID))
   export COMPOSE_PROJECT_NAME="sbc-pln$(printf '%03d' $PLAN_ID)"
   export FEATURE_PORT
   ```
   This ensures:
   - Container name: `sbc-pln<id>` (e.g., `sbc-pln004`, isolated from `sbc-staging`)
   - Port: 8100 + plan ID (e.g., PLN-004 → 8104, PLN-012 → 8112)
   - **Port ranges:** 8000-8099 reserved (static site, staging at 8081); 8100+ for features (no collisions)
   - All `docker compose up` commands in plan steps use these values automatically
10. **Read `.plan/plan.md`** — understand the goal, design decisions, and all steps
11. **Execute steps in order** — follow each step exactly as specified. Update any `docker compose up` commands to use the port variable:
    - If the plan includes `docker compose up`, ensure it maps `$FEATURE_PORT:8080` (or adjust internal port as needed): `docker compose -f docker/docker-compose.yml up --build -d` (ports are controlled via `docker-compose.yml` using `${FEATURE_PORT:-8080}:8080`)
    - The project name is already set, so no need to add `--project-name` flags
12. **Write tests** — implement all tests listed in the Tests table
13. **Check off steps** — mark each step's checkbox in `.plan/progress.md` when done
14. **Log progress** — after each step, append to `.plan/progress.md`: `[date] Step N — done / blocked (reason)`
15. **Run acceptance checks** — verify each step's acceptance criteria before marking it done
   - After each step, commit: `git add src/ tests/ .plan/ && git commit -m "implement(<feature-name>): step N — <desc>"`

16. **Deploy to local container for testing** — build and start the container using the isolated project name and port from step 9:
   ```bash
   docker compose -f docker/docker-compose.yml up --build -d
   ```
   Wait for health check to pass:
   ```bash
   # Poll until healthy (up to 60 seconds)
   for i in $(seq 1 12); do
     wget --no-verbose --tries=1 --spider "http://localhost:$FEATURE_PORT/health" 2>/dev/null && break
     sleep 5
   done
   ```
   The container runs at `http://localhost:$FEATURE_PORT` (e.g., `http://localhost:8104` for PLN-004) with project name `$COMPOSE_PROJECT_NAME` (e.g., `sbc-pln004`). Both were exported in step 9.

17. **Launch build and test agents in background** — spawn these immediately so they run in parallel with code review:
   ```
   # Launch all three in parallel as background agents:
   Agent(model: haiku, run_in_background: true, prompt:
     "Run `~/.dotnet/dotnet build SBC.slnx` in the current directory.
      Report: success or failure. If failure, list all errors (not warnings).
      Final response under 1000 characters.")

   Agent(model: haiku, run_in_background: true, prompt:
     "Run `~/.dotnet/dotnet test SBC.slnx --no-build` in the current directory.
      Report: total tests, passed, failed, skipped.
      If any failed, list each failure with test name and error message.
      Final response under 1500 characters.")

   # Only if plan has E2E tests in the Tests table:
   Agent(model: haiku, run_in_background: true, prompt:
     "Run [E2E test command from plan] in the current directory.
      Report: pass or fail. If fail, include the error output.
      Final response under 1000 characters.")
   ```
   These agents run in background while you proceed to code and architecture review (steps 18-19). You will be notified when they complete — do NOT wait for them.

18. **Code review** (while agents run) — review the implementation for correctness:
   - Read through all changed source files
   - Verify logic matches the plan's design decisions
   - Check for edge cases, error handling
   - Ensure no debugging code, console.logs, or temporary hacks remain
   - If issues found, log them in `progress.md` and fix before proceeding

19. **Architecture review** (while agents run) — verify design decisions still hold:
   - Re-read the plan's "Design Decisions" section
   - Confirm the implementation follows those decisions
   - Check if any assumptions from the plan have changed
   - Verify no unintended cross-module dependencies were introduced
   - If scope changes are needed that **cannot be resolved by editing code alone** (design decision conflicts, missing requirements, architectural incompatibilities):
     1. Write `Escalated` findings to `.plan/findings.md`:
        ```
        | FND-NNN | implement | Critical | Design | <description of design issue> | path/to/file.ext:NN | Escalated |
        ```
     2. Update `.plan/plan.md` Status to `Replanning`
     3. Commit on the feature branch:
        ```
        git add .plan/
        git commit -m "implement(PLN-NNN-<name>): escalated findings, needs replanning"
        ```
     4. Destroy the docker container (step 22) and return to develop (Phase 3)
     5. On develop, move the plan and commit:
        ```
        git mv plans/active/PLN-NNN-<name> plans/replanning/PLN-NNN-<name>
        git commit -m "implement(PLN-NNN-<name>): escalated to replanning"
        ```
     6. Display: "Design issue found. Run `/wf-spec` to amend the plan."
   - If issues are minor (code-level fixes), fix them and note in `progress.md`

20. **Collect agent results** — by now the background agents should have completed. Check each result:
   - **Build agent:** If build failed, fix errors on Sonnet (you are Sonnet), then re-verify via a haiku agent: `Agent(model: haiku, prompt: "Run ~/.dotnet/dotnet build SBC.slnx. Report: success or failure. Errors only, under 500 chars.")`
   - **Test agent:** If tests failed, fix failures on Sonnet, then re-verify via a haiku agent: `Agent(model: haiku, prompt: "Run ~/.dotnet/dotnet test SBC.slnx --no-build. Report: total, passed, failed. List failures with name and error. Under 1000 chars.")`
   - **E2E agent:** If E2E tests failed, fix on Sonnet, then re-verify via a haiku agent with the same E2E command
   - Never re-run build or test commands inline — always delegate verification runs to haiku agents
   - Log results in `progress.md`: `[date] Build: pass | Tests: N passed, 0 failed | E2E: pass`
   - If code review (step 18) found issues that required fixes, re-launch a haiku build+test agent to verify the fixes didn't break anything
   - **Tick off all automated checklist sections** in `.plan/plan.md` — mark every item in `### Build & Tests`, `### Code Quality`, and `### Regression Scope` as `[x]`. These sections are fully owned by `/wf-implement` and must be complete before the plan moves to verify.

21. **When all steps, reviews, and tests pass** — update `.plan/plan.md` Status to `Verified` and commit on the feature branch:
   ```
   git add .plan/
   git commit -m "implement(PLN-NNN-<name>): all steps complete, verified, ready for human test"
   ```
   Note: the plan folder move to `plans/verify/` on develop happens in Phase 3.

22. **Destroy the docker container** — clean up before leaving the worktree:
   ```bash
   PLAN_ID=$(git branch --show-current | grep -oE 'PLN-[0-9]+' | sed 's/PLN-//')
   COMPOSE_PROJECT_NAME="sbc-pln$(printf '%03d' $PLAN_ID)"
   
   # Stop and remove containers
   docker compose -f docker/docker-compose.yml \
     --project-name "$COMPOSE_PROJECT_NAME" \
     down -v 2>/dev/null || true
   
   # Force remove any remaining containers with this project name
   docker ps -a --filter "name=$COMPOSE_PROJECT_NAME" --format "{{.ID}}" | xargs -r docker rm -f 2>/dev/null || true
   ```
   This removes the container and volumes, keeping the worktree clean for T4's later human acceptance testing.

**Phase 3: Cleanup (return to `develop`)**

23. **Return to develop directory**:
   ```bash
   # Detect worktree structure and return to sbc accordingly
   if [ -f "../../.dockerignore" ]; then
     # Current structure: sbc/feature-branches/<plan-name>
     cd ../..
   elif [ -d "../../sbc" ]; then
     # Old structure (migration): ../feature-branches/<plan-name>
     cd ../../sbc
   else
     # Legacy structure: ../sbc-feature-*
     cd ../sbc
   fi
   ```

23a. **Update develop's pipeline** — move the plan to the correct stage on develop and sync the status:
   ```bash
   PLAN_NAME=PLN-NNN-<plan-name>
   # Copy updated plan files from the worktree's .plan/ to develop's plans/ entry
   cp feature-branches/$PLAN_NAME/.plan/plan.md plans/active/$PLAN_NAME/plan.md
   cp feature-branches/$PLAN_NAME/.plan/findings.md plans/active/$PLAN_NAME/findings.md 2>/dev/null || true
   cp feature-branches/$PLAN_NAME/.plan/progress.md plans/active/$PLAN_NAME/progress.md 2>/dev/null || true
   # Move to verify/ on develop
   git mv plans/active/$PLAN_NAME plans/verify/$PLAN_NAME
   git add plans/verify/$PLAN_NAME/
   git commit -m "implement($PLAN_NAME): verified, moved to verify/ on develop"
   ```
   If the plan was escalated (Replanning), the move to `plans/replanning/` was already done in step 19.

24. **Post completion message** — display:
   ```
   ✓ Implementation complete — all steps, code review, architecture review, and E2E tests passed
   ✓ Plan moved to verify/ with Status: Verified
   ✓ Docker container cleaned up
   
   T4 (Tester): Switch to the worktree for human acceptance testing:
     cd feature-branches/PLN-NNN-<plan-name>
     /wf-test         (human acceptance testing: user-observable criteria)
   
   When all criteria pass, PR will be created to release branch.
   ```

### Fix cycle (plan in `verify/` on develop with `Verified-with-findings` status)

1. **cd to the feature worktree** — `cd feature-branches/PLN-NNN-<plan-name>`
2. **Update `.plan/plan.md`** — set Status to `Active` and update `Implementing session` with today's date
3. **On develop**, move plan back to active:
   ```
   cd ../..
   git mv plans/verify/PLN-NNN-<name> plans/active/PLN-NNN-<name>
   git commit -m "implement(PLN-NNN-<name>): claim plan for fix cycle"
   cd feature-branches/PLN-NNN-<name>
   ```
4. **Read `.plan/findings.md`** — look for rows with status `Open`
5. **Ignore `Escalated` findings** — these require a planner, not an implementer. Do not attempt to fix them.
6. **Fix each `Open` finding** — address the issue described, using the file paths and line numbers provided
7. **Set finding status to `Fixed`** — update the row in `.plan/findings.md`
8. **Log in `.plan/progress.md`** — `[date] Finding FND-003 — fixed (description of fix)`
9. **When all `Open` findings are `Fixed`** — update `.plan/plan.md` Status to `Verified` and commit:
   ```
   git add src/ tests/ .plan/
   git commit -m "implement(PLN-NNN-<name>): fix findings (FND-NNN)"
   ```
10. **Update develop** — return to develop and move plan back to verify with updated status:
   ```
   cd ../..
   cp feature-branches/PLN-NNN-<name>/.plan/{plan.md,findings.md,progress.md} plans/active/PLN-NNN-<name>/
   git mv plans/active/PLN-NNN-<name> plans/verify/PLN-NNN-<name>
   git add plans/verify/
   git commit -m "implement(PLN-NNN-<name>): findings fixed, back to verify"
   ```

### Amendment cycle (plan was replanned on develop, feature branch needs update)

When a plan goes through replanning (escalated finding → wf-spec amends → back to ready → re-locked to active on develop), the feature branch worktree needs the amended plan.

1. **On develop:** lock the plan as normal (Phase 1 steps 3-4: set Status Active, move ready/ → active/, commit)
2. **Update `.plan/` in the worktree** — copy the amended plan files from develop:
   ```bash
   cp plans/active/PLN-NNN-<name>/{plan.md,findings.md,progress.md} feature-branches/PLN-NNN-<name>/.plan/ 2>/dev/null || true
   cd feature-branches/PLN-NNN-<name>
   git add .plan/
   git commit -m "chore(PLN-NNN): update .plan/ with amended plan"
   ```
3. **Read the amended plan** — re-read `.plan/plan.md`, focusing on the Amendments section to understand what changed
4. **Continue with Phase 2** — execute the amended steps as specified

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
       - Deploy container for testing
       - Launch build/test agents in background
       - Code review + architecture review (parallel with agents)
       - Collect agent results, fix any failures
       - Move plan to verify/
       - Destroy docker container
    → Phase 3: cd back to develop, show T4 handoff
(develop) ✓ done

(T4 takes over)
  cd feature-branches/<plan-name>
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
- **Do NOT** add findings — only `/wf-review` and `/wf-test` produce findings
- **Avoid manual worktree switching** — let `/wf-implement` handle all directory changes. If a user manually switches branches or directories mid-session, subsequent phase logic may break.

## On startup

1. **Detect current branch** — run `git branch --show-current`
2. **If on `develop`:**
   - Run `scripts/wf-list-implementable.sh` to find available work. Each line is `<type>\t<plan-name>\t<goal>` where type is `new` or `amendment`. Exit 1 means nothing available.
   - Show the user a numbered list. Label entries by type:
     - `new` → `(new plan)`
     - `amendment` → `(amendment — plan ready in worktree)`
     - `resume` → `(resume — mid-implementation, plan in active/)`
     - `fix` → `(fix cycle — open findings in verify/)`
   - If the script exits 1, stop with: "No plans ready to implement. Run /wf-status to see pipeline state."
   - Do not produce a general worktree status table; that is /wf-status's job.
   - **If user picks `new`**: Execute Phase 1 (lock plan, create worktree), then Phase 2, then Phase 3
   - **If user picks `amendment`**: follow the Amendment cycle section — lock plan on develop, cd to the existing worktree, merge develop, continue with Phase 2
   - **If user picks `resume`**: cd to the feature worktree, confirm plan is in active/, continue with Phase 2 from the last completed step in progress.md
   - **If user picks `fix`**: follow the Fix cycle section — cd to the feature worktree and fix open findings
   - Done — user is back on develop with worktree ready for T4
3. **If on a feature branch** (e.g. `feature/site-version-indicator`):
   - Confirm `.plan/plan.md` exists — this is the working plan
   - Read `.plan/plan.md` Status to determine current state
   - Execute Phase 2 (code the steps, update `.plan/`, destroy docker container)

## Docker port configuration

For feature branches to use unique ports in the 8100+ range, `docker-compose.yml` must reference the `FEATURE_PORT` environment variable:

```yaml
services:
  web:
    ports:
      - "${FEATURE_PORT:-8080}:8080"  # Default 8080 if FEATURE_PORT not set; otherwise use the env var (e.g., 8104 for PLN-004)
```

**Port ranges:**
- **8000-8099:** Static site (reserved). Staging uses 8081 via `wf-stage` script.
- **8100+:** Feature branches (8100 + plan ID). E.g., PLN-004 → 8104, PLN-012 → 8112.
- **8080:** Default for local development (when `FEATURE_PORT` not set).

**Project naming:**
- Feature project names use plan ID only: `sbc-pln<id>` (e.g., `sbc-pln004`, `sbc-pln012`)
- Staging always: `sbc-staging` (set via `--project-name sbc-staging` in wf-stage script)
- Keeps container names short and readable

This ensures:
- Zero collisions between features (each gets a unique port)
- Staging always at 8081 (never conflicts with features)
- Clear separation of concerns (static range vs. feature range)
- Short, readable container names

## Committing work

Commit after each completed step to preserve progress (on feature branch):
```
git add src/ tests/ .plan/
git commit -m "implement(<feature-name>): step N — <short description>"
```

When implementation is complete (on feature branch):
```
git add .plan/
git commit -m "implement(<feature-name>): all steps complete, verified"
```

For fix cycle (on feature branch):
```
git add src/ tests/ .plan/
git commit -m "implement(<feature-name>): fix F1, F2"
```

Pipeline stage changes happen on develop only (Phase 3 / fix cycle step 10).

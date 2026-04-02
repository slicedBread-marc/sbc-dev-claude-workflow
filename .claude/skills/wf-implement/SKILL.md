---
name: wf-implement
description: Execute a ready plan from start to finish. Creates feature branch and worktree, codes all steps, performs code review, architecture review, and E2E tests, moves to verify/ with Status Verified, and returns to develop. T4 then runs human acceptance testing.
user_invocable: true
model: opus
---

# Implementer Role

You are in **implementer mode**. Your job is to execute an implementation plan completely: lock the plan, create a worktree, code all steps, perform code and architecture review, run E2E tests, verify all checks pass, move to verify/ with Status Verified, and return to develop. T4 then runs human acceptance testing. You also fix findings from testing.

## Model guidance
This skill should run on **opus**. Code generation requires the highest accuracy to avoid rework.

## Model check
**Always prompt on startup:**
> "This skill is designed for **opus**. Implementation on a cheaper model risks bugs that cost more in verify/fix cycles. Run `/model opus` to switch, or say 'proceed' to continue on the current model."

Wait for the user to respond before continuing. If they proceed without switching, note it once and continue.

Do NOT use agents for writing code — implementation is inherently sequential and context-dependent. Agents are used for:

- **Build and test verification (step 16):** Launch haiku agents in background to run build, unit tests, and E2E tests while you do code/architecture review in parallel. This saves significant time.
- **Lookups:** Sparingly, to find specific signatures or patterns:
  ```
  Agent(model: haiku, prompt: "What is the exact method signature of [method] in [file]? Response under 500 chars.")
  ```

## Folder structure

```
plans/ready/       → pick up from here
plans/active/      → work here
plans/verify/      → move here when done
plans/replanning/  → escalate here if design issues found (picked up by /wf-spec)
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
8a. **Merge develop into feature branch** — pull in the locked plan (and any amendments):
   ```bash
   git merge develop -X theirs --no-edit
   ```
   The `-X theirs` bias ensures develop's plan files win (locked/amended state) while preserving feature branch source code. If the worktree is freshly created from HEAD (new implementation), this is a no-op. If this is an amendment cycle, clean up stale plan copies:
   ```bash
   # Remove stale replanning/ copy if it exists (plan is now in active/ from develop)
   git rm -rf plans/replanning/ 2>/dev/null && git commit -m "implement: consolidate plan after merge" || true
   ```
9. **Set the Docker project name and port** — export both as environment variables so all docker compose commands use an isolated container on a unique port:
   ```bash
   PLAN_FOLDER=$(basename $(ls -d plans/active/PLN-*/ | head -1) | tr -d '/')
   # Extract the plan ID number (e.g., "004" from "PLN-004-deployment-date-footer")
   PLAN_ID=$(echo $PLAN_FOLDER | grep -oE 'PLN-[0-9]+' | sed 's/PLN-//')
   # Calculate port: 8100 + NNN (e.g., PLN-004 → 8104, PLN-012 → 8112)
   # Port range 8000-8099 is reserved for static site (includes staging at 8081)
   FEATURE_PORT=$((8100 + PLAN_ID))
   export COMPOSE_PROJECT_NAME="sbc-pln$(printf '%03d' $PLAN_ID)"
   export FEATURE_PORT
   ```
   This ensures:
   - Container name: `sbc-pln<id>` (e.g., `sbc-pln004`, isolated from `sbc-staging`)
   - Port: 8100 + plan ID (e.g., PLN-004 → 8104, PLN-012 → 8112)
   - **Port ranges:** 8000-8099 reserved (static site, staging at 8081); 8100+ for features (no collisions)
   - All `docker compose up` commands in plan steps use these values automatically
10. **Read `plan.md`** — understand the goal, design decisions, and all steps
11. **Execute steps in order** — follow each step exactly as specified. Update any `docker compose up` commands to use the port variable:
    - If the plan includes `docker compose up`, ensure it maps `$FEATURE_PORT:8080` (or adjust internal port as needed): `docker compose -f docker/docker-compose.yml up --build -d` (ports are controlled via `docker-compose.yml` using `${FEATURE_PORT:-8080}:8080`)
    - The project name is already set, so no need to add `--project-name` flags
12. **Write tests** — implement all tests listed in the Tests table
13. **Check off steps** — mark each step's checkbox in `progress.md` when done
14. **Log progress** — after each step, append to `progress.md`: `[date] Step N — done / blocked (reason)`
15. **Run acceptance checks** — verify each step's acceptance criteria before marking it done
   - After each step, commit: `git add src/,tests/ plans/active/ && git commit -m "implement(<feature-name>): step N — <desc>"`

16. **Launch build and test agents in background** — spawn these immediately so they run in parallel with code review:
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
   These agents run in background while you proceed to code and architecture review (steps 17-18). You will be notified when they complete — do NOT wait for them.

17. **Code review** (while agents run) — review the implementation for correctness:
   - Read through all changed source files
   - Verify logic matches the plan's design decisions
   - Check for edge cases, error handling
   - Ensure no debugging code, console.logs, or temporary hacks remain
   - If issues found, log them in `progress.md` and fix before proceeding

18. **Architecture review** (while agents run) — verify design decisions still hold:
   - Re-read the plan's "Design Decisions" section
   - Confirm the implementation follows those decisions
   - Check if any assumptions from the plan have changed
   - Verify no unintended cross-module dependencies were introduced
   - If scope changes are needed that **cannot be resolved by editing code alone** (design decision conflicts, missing requirements, architectural incompatibilities):
     1. Write `Escalated` findings to `findings.md`:
        ```
        | FND-NNN | implement | Critical | Design | <description of design issue> | path/to/file.ext:NN | Escalated |
        ```
     2. Update `plan.md` Status to `Replanning`
     3. Move the plan and stop implementation:
        ```
        git mv plans/active/PLN-NNN-<name> plans/replanning/PLN-NNN-<name>
        git commit -m "implement(PLN-NNN-<name>): escalated findings, needs replanning"
        ```
     4. Destroy the docker container (step 21) and return to develop (Phase 3)
     5. Display: "Design issue found. Run `/wf-spec` to amend the plan."
   - If issues are minor (code-level fixes), fix them and note in `progress.md`

19. **Collect agent results** — by now the background agents should have completed. Check each result:
   - **Build agent:** If build failed, fix errors and re-run build inline before proceeding
   - **Test agent:** If tests failed, fix failures and re-run tests inline. All tests must pass.
   - **E2E agent:** If E2E tests failed, fix and re-run inline. All must pass.
   - Log results in `progress.md`: `[date] Build: pass | Tests: N passed, 0 failed | E2E: pass`
   - If code review (step 17) found issues that required fixes, re-launch a haiku build+test agent to verify the fixes didn't break anything

20. **When all steps, reviews, and tests pass** — update `plan.md` Status to `Verified` (verification is complete within /wf-implement), move the plan folder from `plans/active/PLN-NNN-<name>/` → `plans/verify/PLN-NNN-<name>/`, and commit:
   ```
   git mv plans/active/PLN-NNN-<name> plans/verify/PLN-NNN-<name>
   git commit -m "implement(PLN-NNN-<name>): all steps complete, verified, ready for human test"
   ```

21. **Destroy the docker container** — clean up before leaving the worktree:
   ```bash
   # Extract plan ID from the verified plan folder
   PLAN_FOLDER=$(basename $(ls -d plans/verify/PLN-*/ | head -1) | tr -d '/')
   PLAN_ID=$(echo $PLAN_FOLDER | grep -oE 'PLN-[0-9]+' | sed 's/PLN-//')
   COMPOSE_PROJECT_NAME="sbc-pln$(printf '%03d' $PLAN_ID)"
   
   # Stop and remove containers
   docker compose -f docker/docker-compose.yml \
     --project-name "$COMPOSE_PROJECT_NAME" \
     down -v 2>/dev/null || true
   
   # Force remove any remaining containers with this project name
   docker ps -a --filter "name=$COMPOSE_PROJECT_NAME" --format "{{.ID}}" | xargs -r docker rm -f 2>/dev/null || true
   ```
   This removes the container and volumes, keeping the worktree clean for T4's later human acceptance testing. Uses explicit project name and fallback force-kill to ensure cleanup succeeds.

**Phase 3: Cleanup (return to `develop`)**

22. **Return to develop directory**:
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

23. **Post completion message** — display:
   ```
   ✓ Implementation complete — all steps, code review, architecture review, and E2E tests passed
   ✓ Plan moved to verify/ with Status: Verified
   ✓ Docker container cleaned up
   
   T4 (Tester): Switch to the worktree for human acceptance testing:
     cd feature-branches/PLN-NNN-<plan-name>
     /wf-test         (human acceptance testing: user-observable criteria)
   
   When all criteria pass, PR will be created to release branch.
   ```

### Fix cycle (plan folder is in `verify/` with `Open` findings)

1. **Claim the plan** — before moving, update `plan.md`: set Status to `Active` and update `Implementing session` with today's date
2. **Move the plan folder** from `plans/verify/PLN-NNN-<name>/` → `plans/active/PLN-NNN-<name>/`:
   ```
   git mv plans/verify/PLN-NNN-<name> plans/active/PLN-NNN-<name>
   git commit -m "implement(PLN-NNN-<name>): claim plan for fix cycle, moving to active"
   ```
3. **Read `findings.md`** — look for rows with status `Open`
4. **Ignore `Escalated` findings** — these require a planner, not an implementer. Do not attempt to fix them.
5. **Fix each `Open` finding** — address the issue described, using the file paths and line numbers provided
6. **Set finding status to `Fixed`** — update the row in `findings.md`
7. **Log in `progress.md`** — `[date] Finding FND-003 — fixed (description of fix)`
8. **When all `Open` findings are `Fixed`** — move the plan folder from `plans/active/PLN-NNN-<name>/` → `plans/verify/PLN-NNN-<name>/`, and commit:
   ```
   git add src/,tests/
   git mv plans/active/PLN-NNN-<name> plans/verify/PLN-NNN-<name>
   git commit -m "implement(PLN-NNN-<name>): fix findings (FND-NNN), moving to verify"
   ```

### Amendment cycle (plan was replanned on develop, feature branch needs update)

When a plan goes through replanning (escalated finding → wf-spec amends → back to ready → re-locked to active on develop), the feature branch worktree needs the amended plan.

1. **On develop:** lock the plan as normal (Phase 1 steps 3-4: set Status Active, move ready/ → active/, commit)
2. **In the worktree:** merge develop into the feature branch with `-X theirs` bias:
   ```bash
   cd feature-branches/PLN-NNN-<name>
   git merge develop -X theirs --no-edit
   ```
   The `-X theirs` bias accepts develop's plan files (which have the amendment) over the feature branch's stale copies. Source code on the feature branch is preserved because develop doesn't have those files.
3. **Consolidate plan location** — after merge, the plan may exist in both `plans/active/` (from develop) and `plans/replanning/` (stale feature branch copy). Remove the stale copy:
   ```bash
   git rm -rf plans/replanning/PLN-NNN-<name> 2>/dev/null || true
   git rm -rf plans/replanning/<name> 2>/dev/null || true
   git commit -m "implement(PLN-NNN-<name>): consolidate plan after amendment merge" --allow-empty
   ```
4. **Read the amended plan** — re-read `plans/active/<name>/plan.md`, focusing on the Amendments section to understand what changed
5. **Continue with Phase 2** — execute the amended steps as specified

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
   - Check `plans/ready/` for new plan folders to implement
   - Ask the user which one to pick up (if multiple exist)
   - Execute Phase 1 (lock plan, create worktree with isolated docker project name)
   - Execute Phase 2 (cd to worktree, code all steps, code review, architecture review, E2E tests, move to verify/, destroy docker container)
   - Execute Phase 3 (cd back to develop, display T4 handoff instructions)
   - Done — user is back on develop with worktree ready for T4
3. **If on a feature branch** (e.g. `feature/site-version-indicator`):
   - Confirm the corresponding plan is in `plans/active/`
   - If plan is in `plans/replanning/` instead, this is an amendment cycle — merge develop first (see Amendment cycle section)
   - Execute Phase 2 (code the steps, move to verify/, destroy docker container)
4. **If a plan in `verify/` has `Open` findings:**
   - Ask if user wants to fix those findings (fix cycle)
   - Move to active/, fix findings, then move back to verify/

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

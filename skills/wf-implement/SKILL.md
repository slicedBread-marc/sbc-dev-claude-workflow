---
name: wf-implement
description: Execute a ready plan from start to finish. Creates feature branch and worktree, codes all steps, performs code review and architecture review, updates REGISTRY to verify (triggering the verify agent), and returns to develop.
user_invocable: true
model: sonnet
---

# Implementer Role

**This skill requires sonnet.** If you are not running on sonnet, tell the user: "Switch to sonnet with `/model sonnet` then re-run `/wf-implement`." Do not proceed on any other model.

## IMMEDIATE STARTUP — run these two commands in parallel before reading further

```bash
scripts/wf-branch-check.sh develop true
```
```bash
scripts/wf-list-implementable.sh
```

Parse the results, show the menu, and wait for the user to pick. Only then continue reading the rest of this skill.

---

You are in **implementer mode**. Your job is to execute an implementation plan completely: lock the plan, create a worktree, code all steps, perform code and architecture review, run tests, then update the REGISTRY to `verify` — which triggers the autonomous verify agent. You also handle fix cycles when the verify agent sends a plan back.

Do NOT use agents for writing code — implementation is inherently sequential and context-dependent. Agents are used for:

- **Build and test verification (step 16):** Launch haiku agents in background to run build, unit tests, and E2E tests while you do code/architecture review in parallel.
- **Lookups:** Sparingly, to find specific signatures or patterns:
  ```
  Agent(model: haiku, prompt: "What is the exact method signature of [method] in [file]? Response under 500 chars.")
  ```

---

## Entry (simple)

**If on `develop`:**

Run `scripts/wf-list-implementable.sh` — output is tab-separated: `<type>\t<plan-name>\t<goal>`.
**This script is the ONLY source of truth for plan availability. Do NOT write your own detection logic, check worktree ages, or query claim files manually. Run the script and use its output verbatim.**

Show results as **two tables** — actionable items (numbered) and processing items (no numbers, informational only):

| Type | Table | Action |
|-|-|-|
| `new` | Actionable (numbered) | Phase 1 → Phase 2 → Phase 3 |
| `resume` | Actionable (numbered) | cd to worktree, continue Phase 2 |
| `fix` | Actionable (numbered) | cd to worktree, fix findings |
| `processing` | Processing (no numbers) | Non-selectable — another session is working on it |

```
## Ready to implement

| # | Plan | Type | Goal |
|-|-|-|-|
| 1 | PLN-040-user-admin-page | fix | Replace hardcoded claim string |

## In progress (other sessions)

| Plan | Goal |
|-|-|
| PLN-042-lessons-page-infinite-spinner | Fix infinite loading spinner |
```

If there are no actionable items, say "No plans ready to implement. Run /wf-status to see pipeline state." If there are no processing items, omit the second table.
If exit code 1: "No plans ready to implement. Run /wf-status to see pipeline state."

**If on a feature branch:**
- Run `eval "$(scripts/wf-plan-ref.sh)"` to get PLAN_ID, PLAN_DIR, PLAN_NAME
- Read the plan from `$PLAN_DIR/plan.md`
- Continue Phase 2

---

## Phase 1: Setup (on `develop` branch)

1. **Confirm you are on `develop`** — `scripts/wf-branch-check.sh develop true`
2. **Read the plan** — `eval "$(scripts/wf-plan-info.sh PLN-NNN)"` then read `$PLAN_DIR/plan.md`
3. **Goal check** — if `$PLAN_GOAL_MISSING` is `true`, ask the user: "This plan has no goal summary. Please provide a one-line goal describing what this achieves." Write their answer as the first line under `## Goal` in `$PLAN_DIR/plan.md`, stage the file, and commit: `git add $PLAN_DIR/plan.md && git commit -m "spec($PLAN_NAME): add missing goal"`. Re-run `eval "$(scripts/wf-plan-info.sh $PLAN_NAME)"` to pick up the goal.
4. **Update REGISTRY.md** — lock the plan:
   ```bash
   scripts/wf-registry-update.sh PLN-NNN ready active feature/PLN-NNN-<slug>
   ```
5. **Commit on develop:**
   ```
   git add plans/REGISTRY.md
   git commit -m "implement(PLN-NNN-<slug>): lock plan"
   ```
6. **Create feature branch and worktree:**
   ```bash
   mkdir -p feature-branches
   git worktree add -b feature/PLN-NNN-<slug> feature-branches/PLN-NNN-<slug> HEAD
   ```
7. **Write `.plan-ref` in the worktree:**
   ```bash
   echo "PLN-NNN" > feature-branches/PLN-NNN-<slug>/.plan-ref
   cd feature-branches/PLN-NNN-<slug>
   git add .plan-ref
   git commit -m "chore(PLN-NNN): add .plan-ref"
   cd ../..
   ```
8. **Drop settings.local.json into worktree** for full write permissions:
   ```
   mkdir -p feature-branches/PLN-NNN-<slug>/.claude
   cat > feature-branches/PLN-NNN-<slug>/.claude/settings.local.json << 'EOF'
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

---

## Phase 2: Implementation (in the worktree)

9. **Set develop root, claim the plan, and change to worktree:**
   ```bash
   DEVELOP_ROOT=$(pwd)
   scripts/wf-claim.sh PLN-NNN-<slug>
   cd feature-branches/PLN-NNN-<slug>
   ```
   Use `$DEVELOP_ROOT` for all paths to `plans/` throughout implementation.
10. **Confirm you are on the feature branch** — run `git branch --show-current`
11. **Merge develop into feature branch:**
    ```bash
    $DEVELOP_ROOT/scripts/wf-merge-develop.sh
    ```
    This auto-resolves conflicts in `plans/` and `.plan-ref` by taking develop's version (those files belong to develop, not feature branches). If non-plan conflicts remain, resolve them manually.
12. **Set the Docker project name and port:**
    ```bash
    eval "$($DEVELOP_ROOT/scripts/wf-plan-port.sh PLN-NNN-<slug>)"
    ```
13. **Read the plan** — from develop worktree: `$DEVELOP_ROOT/plans/PLN-NNN-<slug>/plan.md`
14. **Execute steps in order** — follow each step exactly as specified
    - After each step, commit: `git add src/ tests/ && git commit -m "implement(PLN-NNN-<slug>): step N — <desc>"`
15. **Write tests** — implement all tests listed in the Tests table
16. **Log progress** — after each step, append to `$DEVELOP_ROOT/plans/PLN-NNN-<slug>/progress.md`: `[date] Step N — done / blocked (reason)`. **Never use relative paths** — `plans/` only exists on the develop worktree.
17. **Deploy to local container for testing:**
    ```bash
    $DEVELOP_ROOT/scripts/wf-docker-up.sh PLN-NNN-<slug>
    ```
18. **Launch build and test agents in background:**
    ```
    Agent(model: haiku, run_in_background: true, prompt:
      "Run `{{build_command}}` in the current directory.
       Report: success or failure. If failure, list all errors (not warnings).
       Final response under 1000 characters.")

    Agent(model: haiku, run_in_background: true, prompt:
      "Run `{{test_command}} {{test_exclude_e2e}}` in the current directory.
       Report: total tests, passed, failed, skipped.
       If any failed, list each failure with test name and error message.
       Final response under 1500 characters.")
    ```
19. **Code review** (while agents run):
    - Read through all changed source files
    - Verify logic matches the plan's design decisions
    - Check for edge cases, error handling
    - Ensure no debugging code, console.logs, or temporary hacks remain
    - If issues found, fix before proceeding
20. **Architecture review** (while agents run):
    - Re-read the plan's "Design Decisions" section
    - Confirm the implementation follows those decisions
    - If scope changes are needed that **cannot be resolved by editing code alone**:
      1. Write `ESCALATED` findings to `$DEVELOP_ROOT/plans/PLN-NNN-<slug>/findings.md`:
         ```markdown
         ## Implement — YYYY-MM-DD
         
         - [ ] **Design**: <description of design issue> ← ESCALATED
         ```
      2. Destroy the docker container (step 23)
      3. Return to develop (Phase 3) and update REGISTRY state to `draft`
      4. Display: "Design issue found. Run `/wf-spec` to amend the plan."
    - If issues are minor (code-level fixes), fix them and note in `progress.md`
21. **Collect agent results** — check each result:
    - **Build failed:** fix errors, re-verify via haiku agent
    - **Tests failed:** fix failures, re-verify via haiku agent
    - Log results in `progress.md`
    - **Tick off automated checklist sections** in `plan.md` — mark `### Build & Tests`, `### Code Quality`, `### Regression Scope` items as `[x]`
22. **When all steps, reviews, and tests pass** — commit on feature branch:
    ```
    git add -A
    git commit -m "implement(PLN-NNN-<slug>): all steps complete"
    ```
23. **Destroy the docker container:**
    ```bash
    $DEVELOP_ROOT/scripts/wf-docker-down.sh PLN-NNN-<slug>
    ```

---

## Phase 3: Exit (complex) — return to develop

**IMPORTANT:** All commands in this phase must run from the develop root (`DEVELOP_ROOT`). Set this once and use it for every command:
```bash
DEVELOP_ROOT=$(git worktree list | head -1 | awk '{print $1}')
```

24. **Return to develop and release claim:**
    ```bash
    cd "$DEVELOP_ROOT"
    scripts/wf-unclaim.sh PLN-NNN-<slug>
    ```
25. **Update REGISTRY.md** — change state from `active` to `verify`:
    ```bash
    cd "$DEVELOP_ROOT" && scripts/wf-registry-update.sh PLN-NNN active verify
    ```
26. **Commit on develop:**
    ```bash
    cd "$DEVELOP_ROOT" && git add plans/REGISTRY.md plans/PLN-NNN-<slug>/progress.md plans/PLN-NNN-<slug>/findings.md && git commit -m "implement(PLN-NNN-<slug>): verified, moved to verify"
    ```

    **This commit triggers the verify agent automatically** (via hook on REGISTRY state change to `verify`).

27. **Post completion message:**
    ```
    Implementation complete — all steps, code review, architecture review, and tests passed.
    Plan moved to verify — the verify agent will run automated checks.
    
    If the verify agent finds issues, the plan will return to active (check /wf-status).
    If clean, it moves to testing for T4 human acceptance test.
    ```

---

## Fix cycle (plan returned to `active` by verify agent)

The verify agent found code/test/spec issues and set the REGISTRY state back to `active`.

1. **Entry** — `grep "| active |" plans/REGISTRY.md` shows the plan
2. **Read findings** — `plans/PLN-NNN-<slug>/findings.md` has unchecked items
3. **Set develop root, claim the plan, and cd to the feature worktree:**
   ```bash
   DEVELOP_ROOT=$(pwd)
   scripts/wf-claim.sh PLN-NNN-<slug>
   cd feature-branches/PLN-NNN-<slug>
   ```
4. **Merge develop** — `$DEVELOP_ROOT/scripts/wf-merge-develop.sh`
5. **Fix each unchecked finding** — address the issue, then check it off in `$DEVELOP_ROOT/plans/PLN-NNN-<slug>/findings.md`:
   ```markdown
   - [x] **Code**: Login endpoint returns 500 on empty password (src/auth.ts:42)
   ```
6. **Re-run build/tests** via haiku agents
7. **When all findings are checked off** — commit and return to Phase 3 exit:
   ```bash
   git add src/ tests/
   git commit -m "implement(PLN-NNN-<slug>): fix findings"
   # Then follow Phase 3 steps 23-26 (uses $DEVELOP_ROOT)
   ```
   This re-triggers the verify agent.

---

## Worktree workflow

```
(develop)
  /wf-implement
    → Phase 1: lock plan (REGISTRY ready→active), create worktree
    → Phase 2 (in worktree): code all steps, review, test
    → Phase 3: REGISTRY active→verify (triggers verify agent), return to develop
(develop) done

(verify agent runs automatically)
  → clean: REGISTRY verify→testing (T4 picks up)
  → findings: REGISTRY verify→active (T3 fix cycle)
  → escalated: REGISTRY verify→draft (T2 replans)
```

## Docker port configuration

| Range | Use |
|-|-|
| 8000-8099 | Static site, staging (8081) |
| 8100+ | Feature branches (8100 + plan ID) |
| 8080 | Default local dev |

Project name: `sbc-pln<id>` (e.g., `sbc-pln004`)

## Rules

- **Do NOT** make design decisions not covered by the plan
- **Do NOT** add features, refactoring, or improvements beyond what the plan specifies
- If the plan is ambiguous, note it in progress.md and continue — or ask the user
- You may edit src/, tests/ and update progress.md / check off findings
- **Do NOT** edit the plan's Steps, Tests, or Design Decisions sections
- **Do NOT** add findings — only the verify agent and `/wf-test` produce findings

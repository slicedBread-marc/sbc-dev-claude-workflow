---
name: wf-implement
description: Execute a ready plan from start to finish. Creates feature branch and worktree, codes all steps, performs code review and architecture review, updates REGISTRY to verify (triggering the verify agent), and returns to develop.
user_invocable: true
model: haiku
---

# Implementer Role

## IMMEDIATE STARTUP — run in parallel before reading further

1. Run branch check (do not prompt the user):
   ```bash
   scripts/wf-branch-check.sh develop true
   ```

2. Spawn a **haiku subagent** to fetch and format the worklist:

```
Agent(model: haiku, prompt: "Run `scripts/wf-list-implementable.sh` in the current directory.
Output is tab-separated: <type>\t<plan-name>\t<goal>\t<priority>. Processing type has a 5th field: <claim-age>.
Exit code 1 means no plans.

You MUST format output as markdown tables using pipe syntax. Do NOT use paragraphs, bullet lists, or plain text.

Table 1 — Ready to implement (types: new/resume/fix, numbered, urgent first):

| # | Priority | Plan | Type | Goal |
|-|-|-|-|-|
| 1 | urgent | PLN-001-example | new | Example goal |

Table 2 — In progress (types: processing only, no row numbers):

| Priority | Plan | Goal | Claimed |
|-|-|-|-|
| — | PLN-002-example | Example goal | 15m ago |

Omit Table 2 if no processing items. After the tables add:
Mark a plan urgent: \`u <number>\`
Force-take a stale claim: \`force <plan-id>\` (e.g. \`force PLN-022-lesson-deeplink-urls\`)

If no actionable items (or exit code 1), output: 'No plans ready to implement. Run /wf-status to see pipeline state.'

Final response: ONLY the formatted tables. No commentary. No paragraphs.")
```

Display the subagent's output verbatim, then tell the user: "Run `/model sonnet`, then pick a number."

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

Display the subagent output from IMMEDIATE STARTUP. **`wf-list-implementable.sh` is the ONLY source of truth for plan availability. Do NOT write your own detection logic, check worktree ages, or query claim files manually.**

Wait for the user to pick a number. Then check the **Type** column for that row:

| Type | Action |
|-|-|
| `new` | **Phase 1** (setup) → Phase 2 → Phase 3 |
| `resume` | **Skip Phase 1 entirely** → jump to Phase 2 step 9 |
| `fix` | **Skip Phase 1 entirely** → jump to Fix Cycle |
| `processing` | Not selectable — claimed by another session |

**CRITICAL — resume/fix plans already have a worktree and branch.** Do NOT run Phase 1 for them. Do NOT run `git worktree add`, `wf-registry-update.sh ready active`, or create a new branch. Jump directly to Phase 2 step 9 (which claims the plan, cd's to the existing worktree, and merges develop).

If the user types `u <N>`: run `scripts/wf-set-priority.sh <plan-id> urgent`, then re-run the haiku subagent to re-display the updated menu.
If the user types `u <N>` for an already-urgent plan: run `scripts/wf-set-priority.sh <plan-id> —` to clear it, then re-run the subagent.

If the user types `force <plan-id>`:
```bash
scripts/wf-unclaim.sh <plan-id>
scripts/wf-claim.sh <plan-id>
```
Then treat the plan as a `fix` entry (has unchecked findings) or `resume` entry, and proceed to Phase 2.

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
   scripts/wf-worktree-sparse.sh feature-branches/PLN-NNN-<slug>
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

**CWD RULE: After step 9 runs `cd` into the worktree, you are INSIDE the worktree for the rest of Phase 2. The path `feature-branches/...` does not exist from inside the worktree. Never `cd feature-branches/...` again. Use `$DEVELOP_ROOT` (resolved via `git worktree list`) for any path back to develop.**

9. **Set develop root, claim the plan, change to worktree, confirm branch, and merge develop — all in a single bash call:**
   Workflow scripts may appear modified after a deploy — they are sparse-checkout excluded and **must NOT be committed**. The pathspec exclusions below handle this.
   ```bash
   DEVELOP_ROOT=$(pwd)
   scripts/wf-claim.sh PLN-NNN-<slug>
   cd $DEVELOP_ROOT/feature-branches/PLN-NNN-<slug>
   git branch --show-current
   git add -u -- ':(exclude)scripts/wf-*.sh' ':(exclude).claude/' ':(exclude)plans/' ':(exclude)templates/' 2>/dev/null; git diff --cached --quiet || git commit -m "implement(PLN-NNN-<slug>): wip before merge"
   $DEVELOP_ROOT/scripts/wf-merge-develop.sh
   ```
   Shell variables do NOT persist across bash calls — run these together so `DEVELOP_ROOT` and `cd` stay in scope. In any later bash call that needs develop paths, re-resolve: `DEVELOP_ROOT=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')`
12. **Set the Docker project name and port:**
    ```bash
    eval "$($DEVELOP_ROOT/scripts/wf-plan-port.sh PLN-NNN-<slug>)"
    ```
13. **Read the plan** — from develop worktree: `$DEVELOP_ROOT/plans/PLN-NNN-<slug>/plan.md`
14. **Execute steps in order** — follow each step exactly as specified
    - After each step, commit and refresh the claim:
      ```bash
      git add src/ tests/ && git commit -m "implement(PLN-NNN-<slug>): step N — <desc>"
      $DEVELOP_ROOT/scripts/wf-claim.sh PLN-NNN-<slug>
      ```
      Refreshing the claim on every commit means the claim age reflects time since last activity. Sessions that crash without committing will have their claims auto-expire (TTL: 2 hours).
    - **Config-driven randomness**: If a step introduces probabilistic or random behavior (e.g., a spawn chance, drop rate, trigger probability), store the controlling value in `appsettings.json` (or equivalent config) rather than as a hardcoded constant. This lets testers force or suppress the behavior via override values (e.g., `1.0` to always trigger, `0.0` to never trigger) without modifying source code.
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
22. **When all steps, reviews, and tests pass** — commit on feature branch (skip if nothing to commit — all changes may already be committed per-step):
    ```
    git add -A
    git diff --cached --quiet || git commit -m "implement(PLN-NNN-<slug>): all steps complete"
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
    Then run `scripts/wf-check-reboot-flag.sh` and append any output to the message above.

---

## Fix cycle (plan returned to `active` by verify agent)

The verify agent found code/test/spec issues and set the REGISTRY state back to `active`.

**The worktree and branch already exist. Do NOT run Phase 1. Do NOT create a branch or worktree.**

1. **Entry** — `grep "| active |" plans/REGISTRY.md` shows the plan
2. **Read findings** — `plans/PLN-NNN-<slug>/findings.md` has unchecked items
3. **Set develop root, claim the plan, cd to the feature worktree, and merge develop — all in a single bash call:**
   Workflow scripts may appear modified after a deploy — they are sparse-checkout excluded and **must NOT be committed**. The pathspec exclusions below handle this.
   ```bash
   DEVELOP_ROOT=$(pwd)
   scripts/wf-claim.sh PLN-NNN-<slug>
   cd $DEVELOP_ROOT/feature-branches/PLN-NNN-<slug>
   git add -u -- ':(exclude)scripts/wf-*.sh' ':(exclude).claude/' ':(exclude)plans/' ':(exclude)templates/' 2>/dev/null; git diff --cached --quiet || git commit -m "implement(PLN-NNN-<slug>): wip before merge"
   $DEVELOP_ROOT/scripts/wf-merge-develop.sh
   ```
   Shell variables do NOT persist across bash calls — keep these together so `DEVELOP_ROOT` stays in scope. After this call, you are INSIDE the worktree — never `cd feature-branches/...` again.
5. **Fix each unchecked finding** — address the issue, then check it off in `$DEVELOP_ROOT/plans/PLN-NNN-<slug>/findings.md`:
   ```markdown
   - [x] **Code**: Login endpoint returns 500 on empty password (src/auth.ts:42)
   ```
6. **Re-run build/tests** via haiku agents
7. **When all findings are checked off** — commit and return to Phase 3 exit:
   ```bash
   git add src/ tests/
   git commit -m "implement(PLN-NNN-<slug>): fix findings"
   $DEVELOP_ROOT/scripts/wf-claim.sh PLN-NNN-<slug>
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

---
name: wf-implement
description: Execute an implementation plan step by step. Builds code and tests from a plan. Fixes findings from the queue. Use when the user wants to implement a ready plan.
user_invocable: true
model: opus
---

# Implementer Role

You are in **implementer mode**. Your job is to execute an implementation plan precisely, and to fix any findings from review or verification.

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
   git worktree add -b feature/<plan-name> ../sbc-feature-<plan-name> HEAD
   ```
   This creates a new feature branch FROM the current HEAD (develop, with the locked-plan commit) and a new worktree directory separate from your main repo.
6. **Display next steps**:
   ```
   ✓ Feature branch created: feature/<plan-name>
   ✓ Worktree created at: ../sbc-feature-<plan-name>
   
   T3/T4 terminals: Start implementation with:
     ! cd ../sbc-feature-<plan-name> && /wf-implement
   
   This switches to the worktree and begins Phase 2 (coding).
   ```

**Phase 2: Implementation (in the worktree, on feature branch)**

When you run `/wf-implement` again from the worktree directory:

7. **Confirm you are on the feature branch** — run `git branch --show-current`. Should be `feature/<plan-name>`, not `develop`.
8. **Read `plan.md`** — understand the goal, design decisions, and all steps
9. **Execute steps in order** — follow each step exactly as specified
10. **Write tests** — implement all tests listed in the Tests table
11. **Check off steps** — mark each step's checkbox in `progress.md` when done
12. **Log progress** — after each step, append to `progress.md`: `[date] Step N — done / blocked (reason)`
13. **Run acceptance checks** — verify each step's acceptance criteria before marking it done
   - After each step, commit: `git add src/,tests/ plans/active/ && git commit -m "implement(<feature-name>): step N — <desc>"`
14. **When all steps complete** — update `plan.md` Status to `Verifying`, move the plan folder from `plans/active/<name>/` → `plans/verify/<name>/`, and commit:
   ```
   git mv plans/active/<name> plans/verify/<name>
   git commit -m "implement(<feature-name>): all steps complete, moving to verify"
   ```
15. **Post completion message** — after the commit succeeds, display:
   ```
   ✓ Implementation complete — all steps done, plan moved to verify/
   
   NEXT: Run /wf-verify for automated checks
         Then run /wf-test for human acceptance testing
   
   When done testing, your PR will be created to the release branch.
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

## Worktree isolation

Each plan gets its own worktree (isolated directory with its own working tree). Benefits:

- **T3 and T4 work in the same directory** — no need to switch branches
- **No accidental changes** — code in one feature branch won't affect develop or other features
- **Clean git history** — each feature is a linear sequence of commits from develop
- **Easy cleanup** — when testing completes, delete the worktree: `git worktree remove ../sbc-feature-<name>`

## Rules

- **Do NOT** make design decisions not covered by the plan
- **Do NOT** add features, refactoring, or improvements beyond what the plan specifies
- If the plan is ambiguous, note it in Progress and continue with remaining steps — or ask the user
- If the plan has an error or gap, note it in Progress and continue
- You may edit src/,tests/ and the plan's Progress/Findings Queue status
- **Do NOT** edit the plan's Steps, Tests, or Design Decisions sections
- **Do NOT** add findings — only `/wf-review` and `/wf-verify` produce findings
- **Worktree discipline** — always work in the worktree directory once created; do NOT switch back to develop for implementation

## On startup

1. **Detect current branch** — run `git branch --show-current`
2. **If on `develop`:**
   - Check `plans/ready/` for new plan folders to implement
   - Ask the user which one to pick up (if multiple exist)
   - Execute Phase 1 (setup: lock plan, create worktree)
   - Instruct user to switch to the worktree directory and run `/wf-implement` again
3. **If on a feature branch** (e.g. `feature/site-version-indicator`):
   - Confirm the corresponding plan is in `plans/active/`
   - Execute Phase 2 (implementation: code the steps)
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

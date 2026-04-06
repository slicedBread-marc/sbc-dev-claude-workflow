---
name: wf-verify
description: Verify a completed implementation against its plan. Runs tests, checks behavior, reviews code quality. Writes findings to the plan's queue for the implementer to fix.
user_invocable: true
model: sonnet
---

# Verifier Role

You are in **verifier mode**. Your job is to independently confirm that an implementation matches its plan. You diagnose problems but do NOT fix code.

## Model guidance
This skill should run on **sonnet**. Diagnostic work — run commands, compare expected vs actual.

## Model check
**On startup, only if NOT on sonnet:**
> "This skill is designed for **sonnet**. Run `/model sonnet` to switch for lower cost, or say 'proceed' to continue on the current model."
Wait for the user to respond before continuing. If they proceed without switching, note it once and continue.

If already on sonnet, skip the prompt and continue directly.

Spawn **haiku agents in parallel** to gather data before making assessments:

```
# Spawn all of these in parallel:
Agent(model: haiku, prompt: "Run `{{build_command}}` and report: success/failure, any errors or warnings. Response under 1000 chars.")
Agent(model: haiku, prompt: "Run `{{test_command}}` and report: total tests, passed, failed, skipped. List any failures with test name and error. Response under 1500 chars.")
Agent(model: haiku, prompt: "Read [file] and check: does it follow the project conventions? Are there TODO/HACK markers? Hardcoded values that should be constants? Response under 1000 chars.")
```

Then synthesize the agent results into findings.

## Folder structure

```
plans/verify/      → pipeline stage on develop (source of truth for what needs verification)
.plan/             → working copy on feature branch (plan.md, findings.md, progress.md)
plans/replanning/  → plan has design-scope findings (on develop)
plans/complete/    → all findings resolved (on develop)
```

**Key principle:** `plans/` is only modified on develop. Feature branches work exclusively with `.plan/`.

## What you do

1. **Pick a plan** — from develop, check `plans/verify/` for plans needing verification. Then `cd` to the feature branch worktree: `cd feature-branches/PLN-NNN-<plan-name>`
2. **Claim the plan** — update `.plan/plan.md`: set Status to `Verifying` and fill in `Verifying session` with today's date and a brief session identifier (e.g. `2026-04-01 — verify session`)
3. **Read `.plan/plan.md`** — understand the goal, steps, design decisions, and verification checklist
3. **Read `.plan/findings.md`** — review any existing findings and their status
4. **Spawn parallel agents** to run checks:
   - Build agent (haiku): run build, report errors/warnings
   - Test agent (haiku): run tests, report pass/fail
   - Code quality agents (haiku): one per new/changed file, check conventions
5. **Check behavior yourself** — work through Behavioral Checks (these need reasoning, not agents)
6. **Check rollback readiness** — read `## Rollback` in `plan.md` and verify:
   - No TBD placeholders remain in trigger conditions, steps, or verification
   - Steps are specific commands, not general descriptions
   - If data migrations exist, reversibility is explicitly assessed (not assumed)
   - If the rollback section is incomplete, raise a `Warning` finding: `Rollback section incomplete — [missing field]`
7. **Synthesize results** — combine agent reports into findings
7. **Write findings** — append rows to `.plan/findings.md`
8. **Verify fixes** — for findings with status `Fixed`, confirm the fix and set to `Verified` in `.plan/findings.md`

## Writing Findings

Add rows to the **Findings Queue** table in the plan:

```markdown
| FND-003 | verify | Critical | Behavior | Endpoint returns 500 instead of expected response | path/to/file.ext:42 | Open |
| FND-004 | verify | Critical | Design | Auth model doesn't support multi-tenant scope — requires plan change | path/to/file.ext:18 | Escalated |
```

- Use the next available finding ID (FND-001, FND-002, FND-003...)
- Set source to `verify` (or `review` if from review gate)
- Include the specific file and line number when possible
- Set status to `Open` for code-level issues the implementer can fix
- Set status to `Escalated` for issues that require a design decision or plan change

### When to Escalate vs. Open

Use `Escalated` when the finding cannot be resolved by editing code alone — it requires rethinking the approach, changing the plan's design decisions, or clarifying scope. Examples:
- The plan's chosen approach is fundamentally incompatible with a discovered constraint
- Fixing the issue would require changing the design of multiple components
- The scope needs to expand or contract to address the problem correctly
- A security or architectural issue stems from a decision in the plan itself

Use `Open` for everything else: bugs, missing tests, convention violations, performance issues that have a clear code fix.

## Determining Completion

After running all checks and verifying all fixes:

- **No `Open` or `Fixed` findings remain, no `Escalated`** → update `.plan/plan.md` Status to `Complete`, commit on feature branch, then return to develop and move the plan:
  ```bash
  # On feature branch:
  git add .plan/
  git commit -m "verify: <feature-name> — clean, complete"
  # Return to develop:
  cd ../..
  cp feature-branches/<plan-name>/.plan/{plan.md,findings.md,progress.md} plans/verify/<name>/
  git mv plans/verify/<name> plans/complete/<name>
  git add bugs/
  git commit -m "verify: <feature-name> — complete"
  ```
  Close the linked bug (see [Bug closing](#bug-closing)) before committing on develop.
- **Any new `Open` findings** → update `.plan/plan.md` Status to `Verified-with-findings`; commit on feature branch; then update develop's status hint:
  ```bash
  # On feature branch:
  git add .plan/
  git commit -m "verify: <feature-name> — N open findings"
  # Return to develop:
  cd ../..
  cp feature-branches/<plan-name>/.plan/{plan.md,findings.md} plans/verify/<name>/
  sed -i '' 's/^Status:.*/Status: Verified-with-findings/' plans/verify/<name>/plan.md
  git add plans/verify/
  git commit -m "verify: <feature-name> — N open findings"
  ```
- **Any `Escalated` findings** → update `.plan/plan.md` Status to `Replanning`, commit on feature branch, then move on develop:
  ```bash
  # On feature branch:
  git add .plan/
  git commit -m "verify: <feature-name> — escalated findings"
  # Return to develop:
  cd ../..
  cp feature-branches/<plan-name>/.plan/{plan.md,findings.md} plans/verify/<name>/
  git mv plans/verify/<name> plans/replanning/<name>
  git commit -m "verify: <feature-name> — escalated, needs replanning"
  ```
- **Any `Fixed` findings that fail re-verification** → set back to `Open` with a note in `.plan/findings.md`
- A plan with both `Open` and `Escalated` findings should move to `plans/replanning/` on develop — the planner will address the design issues first, then the implementer will fix the rest

## Bug closing

When a plan reaches `Complete` and `plan.md` contains a `**Bug:**` line in the Goal section:

1. **Parse the bug reference** — extract the BUG-NNN ID and slug
2. **Read `bug.md`** in `bugs/triaged/BUG-NNN-<slug>/`
3. **Update `bug.md`**:
   - Set `Status` to `Closed`
   - Add a note under `## Notes`: `Closed YYYY-MM-DD — fixed by plan: <plan-folder-path>`
4. **Move the bug folder** from `bugs/triaged/BUG-NNN-<slug>/` → `bugs/closed/BUG-NNN-<slug>/`

If no bug is linked, skip this step.

## Severity Guide

- **Critical** — security vulnerability, broken functionality, data loss risk, build failure
- **Warning** — performance concern, missing edge case, convention violation
- **Note** — informational suggestion, alternative approach worth considering

## Rules

- **Do NOT** edit source code files ({{source_dirs}})
- **Do NOT** fix problems — only diagnose and write findings
- **Do NOT** write implementation steps, code samples, or solutions — describe what is wrong and why, not how to fix it. If you find yourself writing a fix, stop and write a finding instead.
- You may write to `.plan/findings.md` and check off items in `.plan/plan.md`'s Verification Checklist
- Work in the feature branch worktree, using `.plan/` for all plan files
- Pipeline stage changes (`plans/` moves) happen on develop only

## On startup

Check `plans/verify/` on develop for plan folders to verify. Ask the user which one if multiple exist. Then `cd` to the corresponding feature branch worktree.

## Committing work

After writing findings (on feature branch):
```
git add .plan/
git commit -m "verify: <feature-name> — <findings>"
```

Pipeline stage changes happen on develop (see Determining Completion above).

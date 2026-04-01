# Plan Folder Structure

Each implementation plan lives in its own folder named after the feature:

```
plans/<stage>/<feature-name>/
  plan.md        — static spec: goal, steps, tests, design decisions
  findings.md    — shared queue: /review and /verify append; /implement updates status
  progress.md    — implementer log: step completions, notes
  debug.md       — (optional) debug session log: reproduction steps, screenshots, observations
```

The feature name should be a short kebab-case slug describing the work (e.g. `user-auth`, `payment-webhook`, `audit-log-export`).

---

## plan.md

```markdown
# [Feature Name]

> **ID:** PLN-NNN
> **Status:** Draft | Ready | Active | Verifying | Replanning | Complete
> **Created:** YYYY-MM-DD
> **Bug:** BUG-NNN — <title> _(optional, only if fixing a bug)_
> **Brief:** ../briefs/<brief-name>.md _(optional, only if from a brief)_

## Goal
One paragraph: what this achieves and why it matters.

## Prerequisites
- What must be true before implementation starts (merged PRs, running services, etc.)
- List any files the implementer should read first for context.

## Steps
Each step must be independently completable and verifiable.

### Step N: [Short title]
- **Files:** exact paths to create or modify
- **What:** specific changes — name new classes/methods/components, describe signatures
- **Acceptance:** how to verify this step is done (test command, UI behavior, build passes)

### Step N+1: ...

## Tests
Tests the **implementer** must write. The **verifier** will run and evaluate these independently.

| ID | Type | Description | Command |
|-|-|-|-|
| T1 | Unit | ... | `{{test_command}} {{test_filter_flag}} T1` |

## Verification Checklist
Structured checks for the **verifier** session to execute after implementation.

### Build & Tests
- [ ] `{{build_command}}` — no errors or new warnings
- [ ] `{{test_command}}` — all tests pass, including new tests from this plan
- [ ] No unrelated test regressions

### Behavioral Checks
- [ ] [Describe observable behavior and how to trigger it]

### Code Quality
- [ ] New files follow project conventions (namespaces, folder structure)
- [ ] No TODO/HACK markers left without a tracking note
- [ ] No hardcoded values that should be config/constants

### Regression Scope
- [ ] [Area] — [what to check]

## Design Decisions
Anything the implementer should NOT decide themselves — choices already made and why.
- **Decision:** [what] — **Why:** [reason]

## Out of Scope
Explicitly list things that might seem related but should NOT be done in this plan.

## Rollback

### Trigger conditions
Symptoms or thresholds that should trigger a rollback rather than a fix-forward.
- [ ] [e.g. error rate > X%, critical feature broken, data corruption detected]

### Safety assessment
- **Data migrations:** Reversible | Irreversible | N/A — [brief explanation]
- **Breaking changes:** Yes — [describe impact] | No
- **Downstream impact:** [systems, services, or users affected by a rollback]

### Steps
Ordered steps to revert this change. Be specific — include exact commands.

1. [e.g. `git revert <commit-sha>` and push to trigger redeploy]
2. [e.g. `dotnet ef database update PreviousMigration`]
3. [e.g. Clear cache / notify affected users]

### Verification
How to confirm the rollback succeeded.
- [ ] [e.g. Feature X returns expected behavior]
- [ ] [e.g. Error rate returns to baseline]
- [ ] Build passes and tests are green

## Review
> Filled by the planner's review gate before status is set to Ready.
> Can also be populated by an independent `/review` invocation.
>
> **[date] — Plan Review / Code Review**
> **Result:** Approved | Approved with notes | Blocked
> | # | Severity | Category | Finding | Recommendation |
> |-|-|-|-|-|

## Amendments
> Append-only. Added by /spec when a plan in active/ or beyond needs a design change.
> Format: `[date] — description of change and why`
```

---

## findings.md

```markdown
# Findings — [Feature Name]

> Written by `/wf-review` and `/wf-verify`. Status updated by `/wf-implement`.
> `/wf-review` and `/wf-verify` append rows with status `Open` or `Escalated`.
> `/wf-implement` sets `Open` → `Fixed`. `/wf-verify` sets `Fixed` → `Verified`.
> Plan cannot reach Complete while any finding is Open, Fixed, or Escalated.

| ID | Source | Severity | Category | Description | Files | Status |
|-|-|-|-|-|-|-|
<!-- FND-001 | review | Critical | Security | ... | path/file.cs:42 | Open -->
<!-- FND-002 | verify | Warning  | Behavior | ... | path/file.cs:18 | Fixed -->
<!-- FND-003 | verify | Critical | Design   | ... | path/file.cs:7  | Escalated -->
```

**Status values:**
- `Open` — code-level issue, implementer can fix
- `Fixed` — implementer addressed it, awaiting verification
- `Verified` — verifier confirmed the fix
- `Escalated` — design/scope issue, requires planner to amend the plan

---

## progress.md

```markdown
# Progress — [Feature Name]

> Written by `/implement` only. Append-only.

## Steps
- [ ] Step 1: [title]
- [ ] Step 2: [title]
- [ ] Step 3: [title]

## Log
> Format: `[date] Step N — done / blocked (reason)`
> Format: `[date] Finding FN — fixed (description of fix)`
```

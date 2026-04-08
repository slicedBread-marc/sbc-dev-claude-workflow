# Plan Folder Structure

Each implementation plan lives in its own immovable folder:

```
plans/PLN-NNN-<slug>/
  plan.md        — static spec: goal, steps, tests, design decisions
  findings.md    — append-only log from verify agent and human testing
  progress.md    — implementer log: step completions, notes
```

Plans are created once at `plans/PLN-NNN-<slug>/` and **never move**. State is tracked in `plans/REGISTRY.md`, not by folder location.

Feature branches contain **no plan content** — only a `.plan-ref` file with the plan ID (e.g. `PLN-003`). Skills read plan content from the develop worktree.

---

## plan.md

```markdown
# [Feature Name]

> **ID:** PLN-NNN
> **schema_version:** 4
> **Created:** YYYY-MM-DD
> **Bug:** BUG-NNN — <title> _(optional, only if fixing a bug)_
> **Brief:** briefs/<brief-name>.md _(optional, only if from a brief)_

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

Maximize automated tests. Only mark a test as `Manual` when it genuinely cannot be machine-verified (visual rendering, subjective UX, complex physical interactions). API responses, data correctness, markup structure, auth gates, redirects — all automatable.

| ID | Type | Description | Command |
|-|-|-|-|
| T1 | Unit | ... | `{{test_command}} {{test_filter_flag}} T1` |
| T2 | API | ... | `curl ...` or inline script |
| T3 | Manual | [only if not automatable] | Manual — [what to observe] |

## Verification Checklist
Structured checks for the **verifier** session to execute after implementation.

### Build & Tests
- [ ] `{{build_command}}` — no errors or new warnings
- [ ] `{{test_command}}` — all tests pass, including new tests from this plan
- [ ] No unrelated test regressions

### Behavioral Checks
- [ ] [Describe observable behavior and how to verify it — prefer automated check, use manual only when necessary]

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

> Appended by the verify agent and human testing (`/wf-test`).
> T3 checks off items as they fix them. ESCALATED items route to T2.
```

Each verify/test session appends a dated section with a flat checklist:

```markdown
## Verify — YYYY-MM-DD

- [ ] **Code**: Description of issue (path/to/file.ext:42)
- [ ] **Code**: Missing test for X
- [ ] **Spec**: Rollback section has TBD placeholder
- [ ] **Design**: Approach incompatible with constraint — needs plan change ← ESCALATED

## Human Test — YYYY-MM-DD

- [ ] **Behavior**: Button doesn't respond on mobile (observed by tester)
- [ ] **Design**: Users expect different flow than specified ← ESCALATED
```

**Routing rules** (applied by verify agent / wf-test exit logic):
- Any `ESCALATED` item → state goes to `draft` (T2 replans)
- Any unchecked non-escalated items → state goes to `active` (T3 fix cycle)
- All items checked → state advances (verify→testing, testing→complete)

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

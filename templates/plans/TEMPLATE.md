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
> **schema_version:** 6
> **Created:** YYYY-MM-DD
> **Bug:** BUG-NNN — <title> _(optional, only if fixing a bug)_
> **Brief:** briefs/<brief-name>.md _(optional, only if from a brief)_

## Goal
One-line summary of what this achieves.

Why it matters and any additional context (optional paragraph).

### Goal History
<!-- Managed by wf-spec via wf-goal-push.sh / wf-goal-pop.sh. Do not edit manually. -->
<!-- | Date | Previous Goal | Trigger | Resolution | -->

## Prerequisites
- What must be true before implementation starts (merged PRs, running services, etc.)
- List any files the implementer should read first for context.

## Steps
Each step must be independently completable and verifiable.

**Every entity this plan requires must name the step that creates it.** Accounts the acceptance criteria log in as, tables a query reads, config keys a guard compares against, columns a client must populate, sessions an endpoint resumes, records a `--list` enumerates — for each one, either a step here creates it or the plan names the dependency that does. *A required entity with no provisioning path* is the most repeated defect class in this pipeline's history: it appeared in 6 of 7 plans in one closure, and passed a per-plan architecture review every time, because from inside a single plan the thing simply reads as already present.

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

## Test Scope
_Read by `wf-verify` to decide which tests run on the feature branch. The actual scope is the union of: (1) categories declared here, (2) auto-detected categories from `git diff` file changes, and (3) mandatory smoke (always included). Leave blank only if the change truly affects nothing testable — verify falls back to the full suite._

_Valid category names are defined in `claude-workflow.yml → testScopes`. Declare generously; auto-detect adds more at verify time._

_Example:_
```
- unit
- integration
- e2e-lesson
```

## E2E Scope
_Optional. List e2e test file paths or patterns (one per line) that cover this plan. If blank, wf-test runs the full suite._

## Verification Checklist
Structured checks for the **verifier** session to execute after implementation.

### Build & Tests
- [ ] `{{build_command}}` — no errors or new warnings
- [ ] `{{test_command}}` — all tests pass, including new tests from this plan
- [ ] No unrelated test regressions
- [ ] Accessibility: any new routes covered by accessibility assertions in E2E tests

### Human Test Criteria

#### Chrome-Assisted
- [ ] `/route` — [objectively verifiable behavior: redirects, content appears, form submits, error shown, state persists]

#### Manual
_Every criterion carries a reason tag, written first on the line. Legal tags — and nothing else:_

_`(eyes:blocking)` subjective judgment; failing it blocks the merge._
_`(eyes:cosmetic)` subjective judgment; failing it files a bug and the plan ships._
_`(external)` needs a real third-party system, real credentials, or a physical act._
_`(soak)` needs real elapsed calendar time._
_`(unbuilt)` the prerequisite feature does not exist yet — written by `wf-defer-criterion.sh`, not by hand._

_A criterion that fits none of them belongs in the Tests table. `wf-manual-lint.sh` enforces this and fails the plan back to `draft`._

- [ ] (eyes:blocking) `/route` — [can the user complete the task at all]
- [ ] (eyes:cosmetic) `/route` — [layout, spacing, copy tone, animation feel]

### Code Quality
- [ ] New files follow project conventions (namespaces, folder structure)
- [ ] No TODO/HACK markers left without a tracking note
- [ ] No hardcoded values that should be config/constants
- [ ] Every entity the plan requires is created by a step here, or by a named dependency

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

## Consistency
> Filled by the cross-plan consistency pass (`wf-consistency`) when this plan
> declares Deps. Its presence is the done-marker — do not write it by hand.
>
> **Checked:** YYYY-MM-DD — closure: PLN-NNN, PLN-MMM
> **Result:** clean | amended PLN-NNN (<what and why>) | escalated (<migration>)

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

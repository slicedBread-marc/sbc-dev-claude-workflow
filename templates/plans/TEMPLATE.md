# [Plan Title]

> **Status:** Draft | Ready | In Progress | Verifying | Complete
> **Created:** YYYY-MM-DD
> **Implementing session:** (filled by implementer)
> **Verifying session:** (filled by verifier)

## Goal
One paragraph: what this achieves and why it matters.

## Prerequisites
- What must be true before implementation starts (merged PRs, running services, etc.)
- List any files the implementer should read first for context.

## Steps
Each step must be independently completable and verifiable. Use this format:

### Step N: [Short title]
- **Files:** exact paths to create or modify
- **What:** specific changes — name new classes/methods/components, describe signatures
- **Acceptance:** how to verify this step is done (test command, UI behavior, build passes)
- [ ] Not started

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
> List specific things the verifier should manually confirm (UI flows, API responses, etc.)
- [ ] [Describe observable behavior and how to trigger it]

### Code Quality
- [ ] New files follow project conventions (namespaces, folder structure)
- [ ] No TODO/HACK markers left without a tracking note
- [ ] No hardcoded values that should be config/constants

### Regression Scope
> List areas of the app that could be affected by these changes, so the verifier knows where to spot-check.
- [ ] [Area] — [what to check]

## Design Decisions
Anything the implementer should NOT decide themselves — choices already made and why.
- **Decision:** [what] — **Why:** [reason]

## Out of Scope
Explicitly list things that might seem related but should NOT be done in this plan.

## Review
> Filled automatically by the planner's review gate before status is set to Ready.
> Can also be populated by an independent `/review` invocation.
>
> **[date] — Plan Review / Code Review**
> **Result:** Approved | Approved with notes | Blocked
> | # | Severity | Category | Finding | Recommendation |
> |-|-|-|-|-|

## Findings Queue
Shared queue written by `/review` and `/verify`, consumed by `/implement`.

| # | Source | Severity | Category | Description | Files | Status |
|-|-|-|-|-|-|-|
<!-- F1 | review | Critical | Security | ... | path/file.cs:42 | Open -->
<!-- F2 | verify | Warning | Behavior | ... | path/file.cs:18 | Fixed -->

> **Status values:** `Open` → `Fixed` → `Verified`
> - `/review` and `/verify` add rows with status `Open`
> - `/implement` sets status to `Fixed` after addressing a finding
> - `/verify` sets status to `Verified` after confirming the fix
> - Plan cannot reach `Complete` while any finding is `Open` or `Fixed` (unverified)

## Amendments
> Append-only section. Never rewrite steps above once implementation has started.
> Format: `[date] — description of change`

## Progress
> Filled by implementing session as work proceeds.
> Format: `[date] Step N — done / blocked (reason)`

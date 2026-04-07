# Plan Eligibility Rules

Canonical reference for what makes an artifact eligible at each workflow stage.
Scripts in `scripts/wf-list-*.sh` implement these rules. Skills reference this document.

---

## wf-spec (T2 — Planner)

**Script:** `scripts/wf-list-specable.sh`

Sources checked in priority order:

| Priority | Source | Eligible when |
|-|-|-|
| 1 | `plans/replanning/*/plan.md` | Folder exists. Count of `\| Escalated \|` rows in `findings.md` shown for context. |
| 2 | `bugs/open/*/bug.md` | Folder exists, `bug.md` has a `**ID:**` field with a `BUG-NNN` value. |
| 3 | `plans/briefs/INDEX.md` | Line is under the `## Decided` heading and matches `- [name]` (unchecked item). |

**Not eligible:** Briefs under other headings (Parked, Ideas). Bugs in `triaged/` or `closed/`.

---

## wf-implement (T3 — Builder)

**Script:** `scripts/wf-list-implementable.sh`

| Type | Source | Eligible when |
|-|-|-|
| `new` | `plans/ready/*/plan.md` | Plan exists and no matching worktree in `feature-branches/` (by PLN prefix). |
| `amendment` | `plans/ready/*/plan.md` | Plan exists and a matching worktree already exists (re-spec'd plan). |
| `resume` | `plans/active/*/plan.md` | Plan exists (mid-implementation, worktree should exist). |
| `fix` | `plans/verify/*/plan.md` | Status line contains `with-findings` (case-insensitive). |
| `handoff` | `plans/verify/*/plan.md` | Status line is `Verified` (no `with-findings` suffix) AND zero `\| Open \|` rows in `findings.md`. This is a clean plan ready for T4 handoff — Phase 3 only. |

**Not eligible:**
- Plans in `plans/verify/` with Status `Verified` but open findings in `findings.md` — these need verification or a status correction, not implementation.
- Plans in `plans/complete/`, `plans/drafts/`, or `plans/replanning/`.

---

## wf-verify (T4 — Verifier)

**Script:** none (skill scans `plans/verify/` directly)

| Source | Eligible when |
|-|-|
| `plans/verify/*/plan.md` | Folder exists on develop. Skill asks the user which plan if multiple exist. |

**Not eligible:** Plans in other pipeline stages. Plans already at Status `Complete`.

**Note:** wf-verify does not currently distinguish between plans needing first verification and plans with existing findings. The verifier reads `.plan/findings.md` in the worktree to understand state.

---

## wf-test (T4 — Human Testing)

**Script:** `scripts/wf-list-testable.sh`

| Source | Eligible when |
|-|-|
| `plans/verify/*/plan.md` | Status line matches `Verified` (case-insensitive, supports markdown formatting) AND does NOT contain `with-findings` AND `findings.md` has zero `\| Open \|` or `\| Escalated \|` rows. |

**Not eligible:**
- Plans with Status `Verified-with-findings` — need fix cycle via wf-implement first.
- Plans with Status `Verified` but Open or Escalated findings in `findings.md`.
- Plans in any other pipeline stage (Active, Tested, etc.).

**Note:** Plans with only `Fixed` findings ARE eligible — the fixes have been addressed.

**Output format:**
- **stdout:** `<plan-name>\t<worktree-path>\t<branch>\t<goal>` per eligible plan (worktree/branch may be empty)
- **stderr:** structured summary: `TESTABLE: N`, `BLOCKED: N`, `NOT_VERIFIED: N`, `TOTAL_VERIFY: N`

---

## Summary: Status + Findings Matrix

How a plan in `plans/verify/` is routed based on its status and findings state:

| Status | Open findings? | Routed to |
|-|-|-|
| `Verified` | No | wf-test (human testing) or wf-implement as `handoff` |
| `Verified` | Yes | wf-implement as `fix` (status is stale — should be `Verified-with-findings`) |
| `Verified-with-findings` | Yes | wf-implement as `fix` |
| `Verified-with-findings` | No | wf-implement as `handoff` (findings resolved — status is stale) |
| `Verifying` | — | wf-verify (in progress) |
| `Replanning` | — | Should be in `plans/replanning/`, not `verify/` |
| `Complete` | — | Should be in `plans/complete/`, not `verify/` |

# Plan Eligibility Rules

Canonical reference for what makes an artifact eligible at each workflow stage.
All eligibility is determined by `plans/REGISTRY.md` state. Scripts in `scripts/wf-list-*.sh` implement these rules.

> **Gap:** there is no terminal state for work that is *dropped*. A plan abandoned mid-flight stays eligible forever, and — because four dependency checks read `!= complete` as unsatisfied — permanently blocks anything that depends on it. Proposed in [abandoned-plans.md](abandoned-plans.md); already hit in production by `sbc`.

**The orchestrator does not reimplement any of this.** `wf-orchestrate.sh` parses the same list scripts a human terminal does, then applies its own *additional* skip rules on top — see [orchestrator.md](orchestrator.md#skip-rules). An artifact eligible here may still not be dispatched, because a gate is open on it, its role is at `max_concurrent`, it's over its attempt budget, or the hourly spawn budget is spent. Eligibility and dispatchability are different questions; this file only answers the first.

---

## wf-spec (T2 — Planner)

**Script:** `scripts/wf-list-specable.sh`

| Priority | Source | Eligible when |
|-|-|-|
| 1 | REGISTRY.md `draft` state | Plan has `ESCALATED` items in `findings.md` (returned from verify/test) |
| 2 | `bugs/open/*/bug.md` | Bug exists with `BUG-NNN` ID |
| 3 | `plans/briefs/INDEX.md` | Entry under `## Decided` heading |

**Not eligible:** Briefs under other headings. Bugs in `triaged/` or `closed/`. Draft plans without ESCALATED findings (new plans being written — T2 is already on them).

---

## wf-implement (T3 — Builder)

**Script:** `scripts/wf-list-implementable.sh`

| Type | REGISTRY State | Eligible when |
|-|-|-|
| `new` | `ready` | Plan exists, **no existing worktree** for its branch |
| `resume` | `active`, or `ready` with a worktree | No unchecked findings in `findings.md` |
| `fix` | `active`, or `ready` with a worktree | Has unchecked (non-ESCALATED) findings in `findings.md` |

A plan sent back to `ready` for a replan keeps its branch and worktree, so state
alone does not distinguish a new build from a resumed one. The worktree does:
if one exists, there is nothing left to create and the implementer picks up
where it left off.

**Not eligible:**
- Plans in `draft`, `verify`, `testing`, or `complete` state.
- Plans in `active` with only ESCALATED findings — these need T2 (wf-spec).

---

## Verify Agent (automatic)

**Trigger:** REGISTRY.md state change to `verify`

| Source | Eligible when |
|-|-|
| REGISTRY.md `verify` state | Automatic — triggered by hook |

The verify agent runs autonomously and auto-routes:
- Clean → `testing`
- Code/spec findings → `active` (back to T3)
- ESCALATED findings → `draft` (back to T2)

---

## wf-test (T4 — Human Testing)

**Script:** `scripts/wf-list-testable.sh`

| Source | Eligible when |
|-|-|
| REGISTRY.md `testing` state | Plan has passed automated verification |

**Not eligible:**
- Plans in any other state.
- Plans that haven't been through the verify agent yet.

**Output format:**
- **stdout:** `<plan-name>\t<worktree-path>\t<branch>\t<goal>` per eligible plan
- **stderr:** `TESTABLE: N`, `TOTAL: N`

---

## Summary: State Routing

| REGISTRY State | Who acts | Skill/Agent |
|-|-|-|
| `draft` (no findings) | T2 | wf-spec (new plan) |
| `draft` (ESCALATED findings) | T2 | wf-spec (replanning) |
| `ready` | T3 | wf-implement (new) |
| `active` (no findings) | T3 | wf-implement (resume) |
| `active` (unchecked findings) | T3 | wf-implement (fix cycle) |
| `verify` | Agent | wf-verify (automatic) |
| `testing` | T4 | wf-test (human acceptance) |
| `complete` | — | Done |
| `rolled-back` | — | Reverted |

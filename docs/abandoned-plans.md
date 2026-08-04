# Abandoned plans — a terminal state for work that is dropped, not finished

> **Status: proposed, not implemented.** Nothing in this repo supports `abandoned` today.
> Filed from the field: `sbc` drained 11 feature worktrees on 2026-08-04 and had to invent
> the state to record the outcome. Reported as `sbc` WFI-008; this is the design behind it.

## The gap

The state machine is `draft → ready → active → verify → testing → complete`. Every state
except `complete` means *someone still owes work*, and `complete` means *it shipped*. There
is no way to say **"this was dropped on purpose"**.

That matters more than it sounds. A plan that is abandoned but left at `verify` is
indistinguishable from one that is genuinely mid-verify: it shows up in `/wf-board`, the
orchestrator dispatches a worker at it, and `wf-list-*` keeps offering it as available work.
The only alternatives available to an operator today are both lies — leave it in a working
state (and be re-dispatched forever), or mark it `complete` (and claim shipped code that
never shipped).

## What `sbc` actually did, and what broke

Six live plans were written as `state = abandoned` via `wf-registry-update.sh`. It worked —
which is itself the first defect.

| Surface | Behaviour with `abandoned` in the registry | File |
|-|-|-|
| State write | **Accepted silently.** No validation against the documented state set, so any typo becomes a live state value. | `scripts/v2.00/wf-registry-update.sh` |
| Orchestrator | **Hard fail:** `Error: unknown state 'abandoned' for PLN-NNN`, `exit 1`. | `wf-orchestrate.sh:570` |
| Dependency checks | **Blocks dependents forever.** Four sites test `dep_state != "complete"` and treat the result as unsatisfied; an abandoned plan named in a `Deps` column can never be cleared. | `wf-check-deps.sh:47`, `wf-list-implementable.sh:56`, `wf-list-testable.sh:76`, `wf-plan-info.sh:94` |
| Board | Silently invisible — the counter only tallies `complete`, so abandoned plans appear in no column. | `wf-board.sh:130` |

`sbc` got away with it because no plan depended on any of the six — verified before the
transition, not by luck. A project with a real dependency edge would have been wedged.

## Proposed semantics

`abandoned` is **terminal, like `complete`, but not successful**. The distinction is the
whole point: `complete` asserts the work landed, `abandoned` asserts it never will.

1. **Terminal.** No skill has it as an entry state; no `wf-list-*` offers it; the
   orchestrator treats it as `result="done"` rather than an error.
2. **Does not satisfy a dependency.** A dependent plan is *blocked and must be replanned* —
   its dependency is never arriving. That is different from today's silent forever-block:
   `wf-check-deps.sh` should report it distinctly ("dep PLN-NNN is abandoned — amend or drop
   the dependency") so the operator gets an actionable message instead of a stall.
3. **Reachable from any state**, unlike every other transition. Work is dropped from
   wherever it happened to be — `sbc`'s six were at `draft`, `active`, `verify` and
   `testing`.
4. **Reversible by explicit revival** — `abandoned → draft` only. Never straight back to a
   working state, because the branch may be years stale.
5. **Visible.** `/wf-board` counts it in its own dim column. A dropped plan that vanishes
   from every view is how `sbc` ended up with an unregistered plan folder (WFI-009).

## Change surface

- `wf-registry-update.sh` — **validate `to_state` against the state set** and reject
  anything else. This is worth doing on its own merits, independent of `abandoned`; the
  absence of validation is what let an undocumented state into a production registry.
- `wf-orchestrate.sh:570` — `abandoned)` → `result="done"` (arguably `result="abandoned"`,
  so an external driver can tell the two terminals apart via exit code).
- The four dep-check sites — distinguish *not yet complete* from *never will be*.
- `wf-board.sh` — count and display it.
- Docs that publish the state machine: `README.md`, `CLAUDE.md`, `docs/schema.md`,
  `docs/eligibility.md`, `claude-md/workflow-snippet.md`, `templates/WORKFLOW.md`,
  `skills/wf-init/SKILL.md`.
- `tests/e2e-pipeline.sh` — cover the transition and the dependent-blocked path.
- Consider a `wf-abandon.sh <ID> --reason "..."` so the reason is captured at the point of
  decision rather than lost. `sbc` had to write its reasons into a hand-authored
  `docs/worktree-detach-record.md` because the registry had nowhere to put them.

## Worktree and branch handling

Deliberately **out of scope for the state change**. `git worktree remove` deletes a checkout
and never a branch — the two are independent, and conflating them is what kept `sbc`'s
rename blocked for two days on the theory that draining worktrees required finishing plans.

The convention `sbc` used and that this proposal endorses: tag the branch `abandoned/<dir>`
before removing the worktree, retain the branch, and leave the plan folder in place. Recovery
is then `git checkout -b <name> abandoned/<dir>` plus `git worktree add`. A `wf-abandon.sh`
should do the tagging, and should **warn loudly when the branch has no upstream** — all eight
of `sbc`'s tags are a single local copy of roughly 6,500 lines.

## Migration

Existing registries may already contain the invented value — `sbc` has eight rows at
`abandoned` as of 2026-08-04 (PLN-035, 037, 051, 064-session-telemetry, 074, 075, 076, 088).
Implementing this ratifies them rather than requiring a rewrite, which is the main argument
for `abandoned` over `cancelled` or `dropped` as the spelling.

## Open questions

- Should `abandoned` plans stay in `REGISTRY.md` forever, or be archived once they age out?
  Retaining them is what keeps a plan ID from being reissued — see the duplicate PLN-064 in
  WFI-009.
- Do bugs need the same thing? `bugs/{open,triaged,closed}` has no "won't fix", and `sbc`
  now carries three triaged bugs (BUG-074, 076, 088) whose plans were abandoned while the
  bugs stayed true. Same gap, different artifact.

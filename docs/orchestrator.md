# Orchestrator

The pipeline had a complete state machine and no dispatcher. Every transition
needed a human to notice it and trigger the next skill — four terminals, constant
attention, and the whole board held in your head.

The orchestrator is the dispatcher. It watches `plans/REGISTRY.md` and launches
unattended workers by state, so the only thing left for a human is the set of
decisions a machine shouldn't make.

## Design

```
                    ┌─ wf-orchestrate.sh ─┐
   post-commit ────▶│  --sweep  (one pass)│──▶ wf-spawn.sh <role> <artifact>
   (low-latency     │  --daemon (loop)    │      └─ claude -p --model <tier>
    nudge)          │  <ID>     (drive-1) │         WF_UNATTENDED=1
                    └──────────┬──────────┘
                               │ reads                 writes
              wf-list-*.sh ────┘                 .claude/orchestrator/
              gates, claims, deps                  gates/  logs/  events.log
```

Three properties worth stating, because they're the reason it's cheap and safe:

1. **Routing is pure bash.** State → role is a table lookup. The orchestrator
   never calls a model; only workers cost tokens, each on its cheapest
   sufficient tier.
2. **Eligibility is not reimplemented.** The existing `wf-list-*.sh` scripts
   (spec'd in [eligibility.md](eligibility.md)) remain the single source of truth
   for what's actionable. The dispatcher parses them and adds skip rules.
3. **One spawn path.** The post-commit hook and the daemon both call
   `wf-spawn.sh`, so the pidfile guard lives in one place and they cannot
   double-launch a plan.

## Roles and tiers

| State | Role | Default model | Why |
|-|-|-|-|
| `draft`, open bugs, decided briefs | spec | opus | Planning is where judgment lives |
| `ready` with unchecked `Deps` | consistency | sonnet | Nothing else reads across plans |
| `ready`, `active` | implement | sonnet | Bulk of the work |
| `verify` | verify | sonnet | Already autonomous before this existed |
| `testing` | test | haiku | Guided by the plan's criteria |

Sweep order is **verify → test → consistency → implement → spec**: drain the
furthest-along work first so WIP doesn't pile up behind freshly specced plans.
`consistency` sits immediately ahead of `implement`, and a plan still owing a
pass is filtered out of the implement candidates — a cross-plan contradiction
caught while both plans are still documents is an amendment; caught after one is
built, it is a migration.

### The consistency pass

Every review in the pipeline is scoped to one plan, so two plans can each be
correct alone and contradict each other. One program specified a forward-paging
list API in PLN-003 while PLN-007 needed to page backward; both reviews passed on
the point, and it surfaced only because an attending human happened to hold both
plans at once. The same missing-provisioning-path defect appeared independently
in 7 of 16 plans — a pattern no per-plan reviewer is scoped to see.

`wf-consistency` reads a plan plus its full dependency closure and checks only
inter-plan claims: consumed APIs exist with the assumed shape, required entities
have a provisioning path somewhere, no two plans define the same artifact
incompatibly, and no dependency's prohibition has outlived its purpose to the
point of making a downstream plan unbuildable. Findings against an **unbuilt** dependency become amendments to it;
findings against a **built** one open a `consistency-migration` gate.

It writes `## Consistency` into the plan, which is the done-marker
`wf-list-consistency.sh` reads — so it runs once per plan, not once per sweep.
Turn it off with `orchestrator.consistency_pass: false`, but read the note under
`specApproval` first: it is the compensating control for verdict-mode spec
approval.

## Skip rules

An artifact is not dispatched when any of these hold:

| Condition | Detected by |
|-|-|
| A gate is open on it | `wf-list-gates.sh <ID>` |
| Another session holds its claim | `.wf-claim` (via the list scripts) |
| Its deps are not `complete` | `PLAN_BLOCKED` / list-script `blocked` rows |
| Its role is at `max_concurrent` | live pidfiles under `.claude/orchestrator/logs/` |
| It's over `max_attempts_per_plan` | `.claude/orchestrator/attempts/<ID>.<role>` |
| The hourly spawn budget is spent | `.claude/orchestrator/spawns-<YYYYMMDDHH>` |
| It still owes a consistency pass (implement only) | `wf-list-consistency.sh` |

The attempt budget is the loop breaker. A plan bouncing `active ⇄ verify`
forever burns tokens silently; after N implement spawns it parks as a `stuck`
gate instead of retrying.

### Resume is not retry

The budget counts worker **launches**, which for a while made it useless: a clean
resume of an 11-step plan spent the same budget as a genuine `active ⇄ verify`
thrash, so long plans parked as `stuck` with nothing wrong and the only
workaround was raising the cap until the loop breaker no longer broke loops.
Nothing recorded forward progress — `wf-implement` kept `progress.md`'s Log
current but never ticked its Steps checklist, which read *1 of 11* while the
branch sat at step 9.

Both halves are fixed together:

- `wf-progress-tick.sh` ticks the checklist and writes the Log line in one call,
  and `wf-implement` calls it on every step commit.
- The dispatcher records a progress signature per plan —
  `<state>:<ticked>/<total>:<consistency-pending>` — and **resets the attempt
  budget whenever it changes.**

So `max_attempts_per_plan: 3` now means what it claims: three launches with *no
forward progress*. If a plan still parks mid-build, the implementer is not
calling `wf-progress-tick.sh`; raising the cap hides that rather than fixing it.

## Gates

A gate is how an unattended worker says *"a human has to decide this"* without
hanging. Instead of asking a question it writes
`.claude/orchestrator/gates/<ID>.gate` and exits 0. The dispatcher skips gated
artifacts; `/wf-attend` drains the queue.

| Gate | Opened when |
|-|-|
| `spec-approval` | A spec is drafted, under `specApproval.mode: gate` (the default) — writing a spec unattended is fine, approving one is not. Also opened in `verdict` mode for plans tagged in `specApproval.gateTags` |
| `spec-stuck` | `verdict` mode only: the review blocked the plan for `maxReviewRounds` rounds running |
| `consistency-migration` | A plan contradicts an **already-built** dependency — an amendment can't fix it |
| `manual-test` | `wf-manual-gate.sh` says a human is needed: the diff touches a rendering surface **and** unresolved `(eyes:*)` criteria remain |
| `goal-missing` | No concrete goal line; it's quoted in PRs and by the tester, so it isn't invented |
| `migration` | Pending `MIGRATION-NOTES.md` actions for the plan |
| `merge-failed` | `git push` was rejected |
| `stuck` | Attempt budget exhausted |
| `needs-input` | Catch-all — anything a skill would otherwise have asked |

One file per artifact rather than a shared `GATES.md`: concurrent workers would
race on appends, and "is this parked?" becomes a single `test -f`. Values are
single-quoted (`wf_emit`) so a question containing an apostrophe survives `eval`
— the lesson from BUG-094. The queue is ordered by **blocked-closure size**,
costliest first: a gate at the root of a dependency chain holds everything
behind it, and that cost is invisible from the gate itself. Ties break
oldest-first, and re-opening an existing gate keeps its original timestamp, so
nothing starves.

Gates live under the **develop root**, not the current worktree — a worker inside
`feature/PLN-097-foo` must open a gate that `/wf-attend` on develop can see.

## Unattended mode

Skills are written for a human. Under `claude -p` every prompt is either a hang
or an improvisation. Each of `wf-spec`, `wf-implement` and `wf-test` carries an
`## Unattended mode` section: a table tagging every existing prompt `[AUTO]`
(resolve to a documented default) or `[GATE]` (park, never guess), plus inline
markers at the gates themselves.

Judgment calls encoded there worth knowing:

- **wf-spec** flips auto-test promotion to `[AUTO] yes`, overriding step 7c's
  "never auto-promote". Maximizing automation is the standing direction.
- **wf-spec**'s review gate is `[GATE]` or `[AUTO]` depending on
  `specApproval.mode` — see below.
- **wf-test** does *not* gate on the first Manual criterion, and does not decide
  the question at all: `wf-manual-gate.sh` does, and its answer is final in both
  directions.
- **wf-test** treats an unverified criterion as *not* a PASS. A false PASS ships.
- **wf-consistency** may amend an unbuilt dependency unattended; against a built
  one it must gate, because that is a migration.

### Which gates are actually worth a human

Two of them were measured and found empty, and both were removed on evidence
rather than taste.

**Spec approval** (`specApproval.mode`). In a 16-plan program, 15 plans parked as
`spec-approval`. The architecture review found Critical findings in 8 of 8 gates
drained with a human present — not one plan was approvable as drafted — so the
human's decision was never *"is this good?"* but *"proceed with the fix loop the
reviewer just specified."* Total human input across those 8: the word "approve",
then the word "all". Under `mode: verdict` the review runs unattended and its
verdict is the gate; every plan in that run converged in 2 rounds, and a plan
still Blocked after `maxReviewRounds` parks as `spec-stuck`. Ships as `gate` —
switching is a deliberate grant, and it should not be switched without the
consistency pass running.

**Manual test** (`manualTestGate`). The old rule stopped on any `#### Manual`
criterion, and every plan has some. Sorted by surface, CLI-only plans had 14 of
15 "manual" criteria that were plain shell assertions; browser-UI plans had 12 of
14 that genuinely needed eyes. The gate now keys on whether the diff touches a
configured rendering surface — something the planner does not control when
classifying criteria — so a plan that renders nothing to a human never stops for
one. `(external)` and `(soak)` criteria never gate under any condition: they
cannot be satisfied at gate time either, so gating on them buys a stop and
nothing else.

## Concurrency

Running workers in parallel makes every read-modify-write of `REGISTRY.md` a
race — previously avoided only because humans are slow. `wf-lock.sh` provides
named, repo-scoped advisory locks (`mkdir` as the atomic primitive; macOS ships
no `flock`). The mutators are **self-locking**, so no SKILL.md call site changed:

| Lock | Held by |
|-|-|
| `registry` | `wf-registry-update.sh`, `wf-set-tags.sh`, `wf-set-deps.sh`, `wf-set-priority.sh`, `wf-counter-next.sh` |
| `plan-<ID>` | `wf-goal-push.sh`, `wf-goal-pop.sh` |

`wf-counter-next.sh` was the sharpest edge: two concurrent specs were handed the
same artifact ID.

Acquiring exports `WF_LOCK_HELD_<NAME>`, so a child process taking the same lock
is a no-op rather than a deadlock. Stale locks are reclaimed when the owning PID
is dead or after `WF_LOCK_TTL` seconds.

## Driving one item

The hook for an agent in another repo. Accepts a bug, brief, or plan — the shared
counter makes `BUG-094 → PLN-094` predictable.

```bash
scripts/wf-exec.sh wf-orchestrate.sh BUG-094 --json
```

| Exit | Meaning |
|-|-|
| 0 | Reached the target state |
| 20 | Blocked on a human. **Normal outcome — never auto-retry** |
| 30 | Worker ran, state unchanged |
| 1 | Error (bad ID, or orchestrator disabled) |

## Safety

Everything below is configurable in `claude-workflow.yml → orchestrator`:

- `enabled: false` by default. Workers run with
  `--dangerously-skip-permissions`; turning this on is a deliberate human grant,
  and `/wf-orchestrate` is explicitly forbidden from flipping it for you.
- `--dry-run` on `--sweep` reports what would be spawned and spawns nothing. It
  is a pure read: no workers, no gates opened, and nothing written to
  `events.log` — a preview that left entries behind would be indistinguishable
  from a real dispatch when the log is read back later.
- The daemon logs a sweep only when it dispatched something. A sweep that
  spawns nothing while no worker is live is a **stall**: it emits one `stalled`
  event naming the gates responsible and their blocked-closure sizes, then
  stays quiet until that situation changes. Total stall is the one condition
  worth notifying on — unambiguous, never self-correcting, and every minute in
  it is wasted wall-clock.
- Skip lines are **latched, not logged**. Every skip reason is a standing
  condition — a gate stays open, a role stays at cap, a spent budget stays
  spent — so one line per candidate per sweep records the same fact forever:
  1,583 identical `skip PLN-002 spec: gate open` lines in 26 hours in one
  measured run. A skip is written when the reason for a (role, artifact) pair
  first appears or changes, and the latch clears the moment that pair
  dispatches, so a plan gated → freed → gated again is reported both times.
- `wf-list-gates.sh` ranks the queue by **blocked-closure size**, not by age.
  A gate's cost is the time until someone looks times the number of plans
  behind it, and the second term is invisible from the gate itself. Column 6 is
  that count; ties break oldest-first so nothing starves.
- Config is read **once, at startup**. Changing `sweep_interval`,
  `max_attempts_per_plan` or any other `orchestrator.*` key needs a daemon
  restart to take effect.
- Per-role `max_concurrent` caps.
- `max_attempts_per_plan` parks thrashing plans.
- `max_spawns_per_hour` is the hard ceiling on a runaway pipeline.
- `--stop` ends the daemon; `--kill-all` also terminates live workers.
- `events.log` is the audit trail: every spawn, exit, gate, skip and sweep.

## Testing

`tests/orchestrator.sh` puts a **stub `claude` first on `PATH`** that records its
argv and simulates the state transition a real worker would make. The entire
dispatch path — selection, caps, gates, attempt budgets, exit codes — is covered
for zero tokens.

Run it with `WF_TEST_SCRIPT_DIR=<path>` to point the suite at an alternate copy
of the scripts; that's how the locking and prefix-collision assertions were
proven to fail against pre-fix code.

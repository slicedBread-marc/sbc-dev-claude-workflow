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
| `ready`, `active` | implement | sonnet | Bulk of the work |
| `verify` | verify | sonnet | Already autonomous before this existed |
| `testing` | test | haiku | Guided by the plan's criteria |

Sweep order is **verify → test → implement → spec**: drain the furthest-along
work first so WIP doesn't pile up behind freshly specced plans.

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

The attempt budget is the loop breaker. A plan bouncing `active ⇄ verify`
forever burns tokens silently; after N implement spawns it parks as a `stuck`
gate instead of retrying.

## Gates

A gate is how an unattended worker says *"a human has to decide this"* without
hanging. Instead of asking a question it writes
`.claude/orchestrator/gates/<ID>.gate` and exits 0. The dispatcher skips gated
artifacts; `/wf-attend` drains the queue.

| Gate | Opened when |
|-|-|
| `spec-approval` | A spec is drafted. **The hard stop** — writing a spec unattended is fine, approving one is not |
| `manual-test` | `#### Manual` criteria remain after everything testable has been cleared |
| `goal-missing` | No concrete goal line; it's quoted in PRs and by the tester, so it isn't invented |
| `migration` | Pending `MIGRATION-NOTES.md` actions for the plan |
| `merge-failed` | `git push` was rejected |
| `stuck` | Attempt budget exhausted |
| `needs-input` | Catch-all — anything a skill would otherwise have asked |

One file per artifact rather than a shared `GATES.md`: concurrent workers would
race on appends, and "is this parked?" becomes a single `test -f`. Values are
single-quoted (`wf_emit`) so a question containing an apostrophe survives `eval`
— the lesson from BUG-094. The queue is FIFO by open time; re-opening an
existing gate keeps its original timestamp so nothing starves.

Gates live under the **develop root**, not the current worktree — a worker inside
`feature/PLN-097-foo` must open a gate that `/wf-attend` on develop can see.

## Unattended mode

Skills are written for a human. Under `claude -p` every prompt is either a hang
or an improvisation. Each of `wf-spec`, `wf-implement` and `wf-test` carries an
`## Unattended mode` section: a table tagging every existing prompt `[AUTO]`
(resolve to a documented default) or `[GATE]` (park, never guess), plus inline
markers at the gates themselves.

Three judgment calls encoded there are worth knowing:

- **wf-spec** flips auto-test promotion to `[AUTO] yes`, overriding step 7c's
  "never auto-promote". Maximizing automation is the standing direction.
- **wf-test** does *not* gate on the first Manual criterion. It clears everything
  testable without eyes (Chrome-Assisted, recurring auto-testable shapes), then
  parks **once** with the remainder. Otherwise a human gets pulled back for one
  item at a time.
- **wf-test** treats an unverified criterion as *not* a PASS. A false PASS ships.

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
- `--dry-run` on `--sweep` reports what would be spawned and spawns nothing.
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

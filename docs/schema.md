# Workflow Document Schema Versions

All workflow artifacts (plans, bugs, briefs) carry a `schema_version` field in their header. Skills use this field to handle documents correctly.

## Version History

### v1 (legacy)
- `schema_version` field is **absent**
- Each type has its own independent counter — numbers are not globally unique
- Plans move between stage folders (`drafts/` → `ready/` → `active/` → etc.)

### v2 (legacy)
- `schema_version: 2`
- **Global counter:** `plans/.counter` file, shared across all artifact types
- Plans still move between stage folders

### v3 (legacy)
- `schema_version: 3`
- `.plan/` isolation on feature branches, `plans/` on develop only for pipeline stages
- Plans still move between stage folders on develop

### v4 (legacy)
- `schema_version: 4`
- **Registry-based model** — plans never move. State is tracked in `plans/REGISTRY.md`.
- **Counter embedded** in REGISTRY.md as `<!-- Counter: N -->` — no separate `.counter` file
- **No folder movement** — each plan lives at `plans/PLN-NNN-<slug>/` forever
- **No plan content on feature branches** — only a `.plan-ref` file containing the plan ID
- **Verify agent** replaces manual wf-verify skill — triggered automatically on state change to `verify`
- **Simplified findings** — flat checklists instead of FND-NNN tables with status columns

### v5 (legacy)
- `schema_version: 5`
- **Tags column** in REGISTRY.md — comma-separated category tags per plan (e.g. `security,admin`)
- **Deps column** in REGISTRY.md — comma-separated plan IDs that must be `complete` before this plan is workable (e.g. `PLN-045,PLN-073`)
- **Goal stack** in `plan.md` — `### Goal History` table tracks goal overrides during fix cycles. When findings come back, wf-spec pushes a focused sub-goal; when resolved, the original goal is restored.
- Allowed tags (extensible): `security`, `arcade`, `admin`, `lessons`, `ux`, `infra`, `e2e`, `bugfix`

### v6 (current)
- `schema_version: 6`
- **Tagged manual criteria** — every `#### Manual` criterion in `plan.md` declares why a machine cannot check it, using exactly one of `(eyes:blocking)`, `(eyes:cosmetic)`, `(external)`, `(soak)`, `(unbuilt)`. Enforced by `wf-manual-lint.sh` at spec time and again at verify; an untagged or misclassified criterion routes the plan back to `draft`. See [Manual criterion tags](#manual-criterion-tags-v6).
- **Deferred criteria have a producer** — `plans/deferred-criteria.md` is written by `wf-defer-criterion.sh` when a plan completes with `external` / `soak` criteria outstanding. It was read by `wf-spec` step 1a in v5 but nothing ever created it.
- **Progress checklist is live** — `progress.md`'s `## Steps` checklist is ticked per step by `wf-progress-tick.sh` and read by `wf-progress-count.sh`. It is the pipeline's forward-progress signal; the orchestrator resets a plan's attempt budget when it climbs.
- **Consistency section** — `plan.md` gains `## Consistency`, written by the cross-plan consistency pass for plans with declared `Deps`.

**Registry tracking (workflow v3.2.0, no schema bump).** Nothing in the plan document changed, so `schema_version` stays at 6. What changed is where the registry lives:

- **`plans/REGISTRY.md` is tracked.** It was gitignored as "operational state", which left the pipeline's single source of truth as the one artifact in `plans/` that git did not hold: `plan.md`, `findings.md` and `progress.md` were versioned while the state machine indexing them was not, and a lost develop worktree took the whole pipeline's state with it. It also made the documented row-based auto-merge rationale describe a mechanism that could not occur in an untracked file.
- `wf-registry-update.sh --commit` stages the registry itself, so a transition and the findings that justify it land in one commit.
- Feature branches are unaffected: `wf-worktree-sparse.sh` already excludes `plans/**` from every feature worktree, so registry churn never reaches a feature branch or arrives as a conflict when one merges back.
- **Migration:** `install.sh` removes the `plans/REGISTRY.md` line from `.gitignore` and tells the project to commit the file. Nothing else changes.

## Manual criterion tags (v6)

`#### Manual` criteria are the only checks in the pipeline a machine never runs, so each one states the reason it is exempt:

| Tag | Means | Can a machine ever check it? | On failure |
|-|-|-|-|
| `eyes:blocking` | Subjective judgment about whether the user can complete the task | No | Findings written, plan routes to `active` |
| `eyes:cosmetic` | Subjective judgment about layout, spacing, copy tone, animation feel | No | Files a `BUG-NNN`, criterion checks off, plan completes |
| `external` | Needs a real third-party system, real credentials, or a physical act | Not in CI | Deferred to `plans/deferred-criteria.md` |
| `soak` | Needs real elapsed calendar time | Not at gate time | Deferred to `plans/deferred-criteria.md` |
| `unbuilt` | The prerequisite feature does not exist yet | Once it is built | Deferred to `plans/deferred-criteria.md` |

```markdown
#### Manual
- [ ] (eyes:blocking) /app/time — the timer is usable one-handed on a phone
- [ ] (eyes:cosmetic) /app/board — column spacing is even at 1280px
- [ ] (external) trx ticket pull <real id> — every image in the DevOps web UI is present
- [ ] (soak) trx work — the Stalled section surfaces something genuinely forgotten
- [ ] (unbuilt) the export button — the screen it lives on ships in PLN-112
```

`unbuilt` is the one tag a planner does not write by hand: `wf-defer-criterion.sh` stamps it when `wf-test` defers a criterion whose prerequisite has not shipped. It is listed here because the plan still has to lint afterwards.

A criterion fitting none of the five is misclassified and belongs in the Tests table. `wf-manual-lint.sh` also flags an `eyes:*` criterion written with an assertable verb (*is refused, returns, contains, exists, stops for, prints, matches, resolves*) unless the same line carries a subjective marker (*reads, feels, legible, usable, at a glance*).

**Migration from v5.** No migration script is needed and no in-flight plan changes behavior. `wf-manual-lint.sh` reads the plan's `schema_version` and skips linting anything below 6, so a v5 plan already in the pipeline is never failed back to `draft` for lacking tags. When counting criteria (for the manual-test gate) a v5 plan falls back to v5 semantics: every unchecked manual criterion counts as `eyes:blocking`, which is what "any Manual criterion gates" already meant. Plans drafted or re-drafted after the upgrade are written as v6 and must carry tags.

## Skill Behaviour

| `schema_version` | Model | State tracking | Plan on feature branch | Counter |
|-|-|-|-|-|
| absent | v1 | Folder location | `plans/{stage}/` | Per-type files |
| `2` | v2 | Folder location | `plans/{stage}/` | `plans/.counter` |
| `3` | v3 | Folder location | `.plan/` | `plans/.counter` |
| `4` | v4 | REGISTRY.md row | `.plan-ref` (ID only) | REGISTRY.md comment |
| `5` | v5 | REGISTRY.md row + Tags/Deps | `.plan-ref` (ID only) | REGISTRY.md comment |
| `6` | v6 | REGISTRY.md row + Tags/Deps | `.plan-ref` (ID only) | REGISTRY.md comment |

When creating new artifacts, always write `schema_version: 6`.

## REGISTRY.md

Single source of truth for plan state. Lives at `plans/REGISTRY.md` on develop, **tracked and committed** with the plan folders it indexes.

Only develop carries it. `wf-worktree-sparse.sh` excludes `plans/**` from every feature worktree, so there is exactly one writer at a time and a state transition never turns into a merge conflict. Write to it only through the `wf-*.sh` scripts — they take the `registry` lock for the whole read-modify-write and commit the transition atomically.

```markdown
| ID | Slug | State | Priority | Branch | Updated | WF | Tags | Deps |
|-|-|-|-|-|-|-|-|-|
| PLN-001 | user-auth | complete | — | — | 2026-04-01 | 1.33 | security | — |
| PLN-003 | payment-hook | active | urgent | feature/PLN-003-payment-hook | 2026-04-06 | 2.00 | infra | PLN-001 |

<!-- Counter: 4 -->
```

The `Priority` column is optional per-plan. Default value is `—` (normal). Set to `urgent` to surface plans at the top of workable item menus. Use `scripts/wf-set-priority.sh <plan-id> urgent` to mark a plan urgent, or `scripts/wf-set-priority.sh <plan-id> —` to clear it.

The `WF` column stamps the workflow version the plan was spec'd against. `scripts/wf-exec.sh` uses it to dispatch to the matching `scripts/v*/` snapshot (see `scripts/version-map.txt`), so a plan keeps running the scripts it was built against. Empty WF routes to `v1.x` (pre-v2.00 baseline).

The `Tags` column holds comma-separated category tags (no spaces). Default `—`. Use `scripts/wf-set-tags.sh <plan-id> <tags>` to set, and `scripts/wf-list-tags.sh` to read the vocabulary.

**The vocabulary is the project's, not the schema's.** It is derived from the tags plans already carry, plus anything declared in `claude-workflow.yml` (`tags:`, `specApproval.gateTags`). A name outside it is accepted with a warning — this was once a hardcoded allowlist, and a project whose gating tag was not on it could not assign the one tag that gates. Tags are free-form labels; the only one with mechanical meaning is a match against `specApproval.gateTags`.

The `Deps` column holds comma-separated plan IDs that must reach `complete` state before this plan is workable. Default `—`. A plan with incomplete deps shows `[blocked]` in worklist menus. Use `scripts/wf-set-deps.sh <plan-id> <deps>` to set.

### States

| State | Meaning | Who acts next |
|-|-|-|
| `draft` | Being written or needs replanning | T2 (wf-spec) |
| `ready` | Spec approved, waiting for builder | T3 (wf-implement) |
| `active` | Being implemented or in fix cycle | T3 |
| `verify` | Verify agent running automated checks | (automatic) |
| `testing` | Passed automated checks, needs human test | T4 (wf-test) |
| `complete` | Done | — |
| `rolled-back` | Reverted | — |

### State machine

```
draft → ready → active → verify ──[agent]──→ testing → complete
                  ↑          |
                  |          ├→ active  (fix cycle)
                  |          └→ draft   (escalation)
                  └→ draft  (implementer escalation)
```

## Findings Format (v4)

Flat checklist appended per session:

```markdown
## Verify — 2026-04-06

- [ ] **Code**: Description (file:line)
- [ ] **Spec**: Description
- [ ] **Design**: Description ← ESCALATED
```

Routing rules:
- Any `ESCALATED` → state goes to `draft`
- Any unchecked non-escalated → state goes to `active`
- All checked or no findings → state advances

## Goal Stack (v5)

Plans track goal overrides during fix cycles via `### Goal History` in `plan.md`:

```markdown
## Goal
Fix flicker on re-render after viewport resize (show-stopper from verify)

### Goal History
| Date | Previous Goal | Trigger | Resolution |
|-|-|-|-|
| 2026-04-16 | Fix bonus round to reactively suppress arcade games on mobile viewports | Verify: 2 findings (1 show-stopper) | — |
```

- **Push**: when findings return a plan to `draft`, wf-spec calls `wf-goal-push.sh` to archive the current goal and write a new one summarizing pending items. If a finding is a show-stopper, it becomes the goal's focus.
- **Pop**: when replanning resolves all findings and the plan returns to `ready`, wf-spec calls `wf-goal-pop.sh` to restore the original goal and mark the history row resolved.
- `wf-plan-info.sh` always reads the first non-empty line after `## Goal` — downstream consumers (wf-implement, wf-test, wf-status) see the active goal automatically.

## Counter

Embedded in `plans/REGISTRY.md` as `<!-- Counter: N -->`. To allocate a new number (briefs and bugs only):
1. Read N from the comment
2. Use N as the new artifact ID
3. Write N+1 back in the same commit

**Number inheritance:** When a brief or bug is converted to a plan, the plan reuses the same number — no new counter allocation. BRF-041 → PLN-041, BUG-043 → PLN-043. The counter is only incremented when creating new briefs or bugs.

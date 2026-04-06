# Project Purpose

This project is a development workflow library. All `wf-*` skills are designed to be deployed to other projects — they form a reusable workflow harness that can be dropped into any codebase to provide a structured, multi-terminal development pipeline.

Work in this repo is about building, improving, and maintaining that library, not about implementing features for this repo itself.

## Clients

- `/Users/marcblais/dev/sbc/` — the only current client. It consumes the library via symlinks pointing back to the skills in this repo.

---

## Process Flow

### Terminal Roles

The workflow is designed to run across 4 terminal sessions, each with a dedicated role:

| Terminal | Role | Primary Skills | Model |
|-|-|-|-|
| T1 | Intake | `/wf-status`, `/wf-brainstorm`, `/wf-bug` | Sonnet |
| T2 | Planner | `/wf-spec` | Opus |
| T3 | Builder | `/wf-implement` | Sonnet |
| T4 | Validator | `/wf-verify`, `/wf-test` | Sonnet |

Each terminal runs `/wf-init` once per session to establish its role. `/wf-next` auto-routes to the correct skill based on `TERMINAL_ROLE`.

---

### Plan Pipeline (folder stages)

Plans move through these folders on **develop** (the pipeline source of truth):

```
plans/briefs/       → ideas and decided briefs (T1/T2 input)
plans/drafts/       → plan being written by T2
plans/ready/        → reviewed and approved, waiting for T3
plans/active/       → claimed and in progress by T3
plans/verify/       → implementation complete, waiting for T4
plans/replanning/   → escalated findings requiring T2 design decisions
plans/complete/     → accepted by T4, merged to release
plans/rolled-back/  → reverted plans
```

On **feature branches**, the working plan lives in `.plan/` (plan.md, findings.md, progress.md). Feature branches never modify `plans/` — pipeline stage moves only happen on develop. This prevents cross-contamination between worktrees and eliminates merge conflicts on unrelated plans.

Bugs move through: `bugs/open/` → `bugs/triaged/` → `bugs/closed/`

---

### Full Workflow

1. **T1 (Intake)** runs `/wf-status` to see the pipeline. Files bugs with `/wf-bug`. Brainstorms and decides briefs with `/wf-brainstorm`.

2. **T2 (Planner)** runs `/wf-spec` to convert a decided brief or open bug into a plan. Writes steps, tests, rollback, design decisions. A sonnet review agent gates the plan before it moves to `ready/`.

3. **T3 (Builder)** runs `/wf-implement` to claim a plan from `ready/`, create a feature branch worktree with `.plan/`, execute each step, and update develop's pipeline stage to `verify/`.

4. **T4 (Validator)** runs `/wf-verify` to check the implementation against `.plan/` in the worktree. Appends findings to `.plan/findings.md`. Open findings go back to T3 (fix cycle). Escalated findings go back to T2 (replanning). Clean plans move to `complete/` on develop and get a PR to `release`.

5. **T4** runs `/wf-test` for human acceptance testing before release.

6. **Release** — completed plans are promoted from `release` to `main`. `/wf-stage` spins up a staging container on port 8081 for final checks.

---

### Branch Strategy

```
main        → production
release     → staging / pre-production
develop     → integration branch (all plans land here)
feature/*   → one branch per plan (e.g. feature/PLN-005-bug-002-guest-logout)
```

T3 creates a `feature/<plan-name>` branch and worktree from `develop`. On completion, the worktree merges back to `develop` and the feature branch is deleted.

---

### Artifact ID System

All artifacts (plans, bugs, briefs) use a **global shared counter** stored in `plans/.counter`.

- The file contains a single integer — the next number to allocate.
- When creating any artifact, read the counter, use it, write `N+1` back.
- IDs are type-prefixed for readability: `PLN-NNN`, `BUG-NNN`, `BRF-NNN`.
- Numbers are globally unique across all types — no two artifacts share a number.

**Schema versions** (see `docs/schema.md`):

| `schema_version` | Meaning |
|-|-|
| absent | Legacy (v1) — independent per-type counters, pre-global system |
| `2` | Global counter, all new artifacts |
| `3` | Current — `.plan/` on feature branches, `plans/` on develop only for pipeline stages |

Skills check `schema_version` to handle legacy documents gracefully. New artifacts always write `schema_version: 3`. Plans in worktrees with `plans/verify/` (v2) are supported alongside `.plan/` (v3) during transition.

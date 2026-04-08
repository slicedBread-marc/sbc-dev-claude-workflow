# Project Purpose

This project is a development workflow library. All `wf-*` skills are designed to be deployed to other projects — they form a reusable workflow harness that can be dropped into any codebase to provide a structured, multi-terminal development pipeline.

Work in this repo is about building, improving, and maintaining that library, not about implementing features for this repo itself.

## Interaction Rules

- When given content, **diagnose and correct** issues in skills (`SKILL.md`) or associated scripts.
- **Never run skills** directly.
- Fixing pipeline data (registry, plan files, etc.) is secondary — **always prompt the user** before modifying data.

## Clients

- `/Users/marcblais/dev/sbc/` — the only current client. It receives copies of skills and scripts via `deploy-all.sh`.

---

## Process Flow

### Terminal Roles

The workflow is designed to run across 4 terminal sessions, each with a dedicated role:

| Terminal | Role | Primary Skills | Model |
|-|-|-|-|
| T1 | Intake | `/wf-status`, `/wf-brainstorm`, `/wf-bug` | Sonnet |
| T2 | Planner | `/wf-spec` | Opus |
| T3 | Builder | `/wf-implement` | Sonnet |
| T4 | Tester | `/wf-test` | Haiku |
| Agent | Verifier | `wf-verify` (auto-triggered) | Sonnet |

Each terminal runs `/wf-init` once per session to establish its role. `/wf-next` auto-routes to the correct skill based on `TERMINAL_ROLE`.

---

### Design Principles

1. **Immovable plans** — each plan lives at `plans/PLN-NNN-<slug>/` forever. No folder movement.
2. **Registry as state machine** — `plans/REGISTRY.md` is the single source of truth for plan state.
3. **Simple entry, complex exit** — every skill starts with one `grep` on REGISTRY.md. Exit logic handles state transitions, commits, and handoffs.
4. **No plan content on feature branches** — only a `.plan-ref` file (one line: the plan ID). Skills read plan content from the develop worktree.

---

### Plan Pipeline

State is tracked in `plans/REGISTRY.md`, not by folder location:

```
draft → ready → active → verify ──[agent]──→ testing → complete
                  ↑          |
                  |          ├→ active  (fix cycle)
                  |          └→ draft   (escalation)
                  └→ draft  (implementer escalation)
```

| State | Meaning | Who acts next |
|-|-|-|
| `draft` | Being written or needs replanning | T2 (wf-spec) |
| `ready` | Spec approved, waiting for builder | T3 (wf-implement) |
| `active` | Being implemented or in fix cycle | T3 |
| `verify` | Verify agent running automated checks | (automatic) |
| `testing` | Passed automated checks, needs human test | T4 (wf-test) |
| `complete` | Done | — |

Bugs move through: `bugs/open/` → `bugs/triaged/` → `bugs/closed/`

---

### Full Workflow

1. **T1 (Intake)** runs `/wf-status` to see the pipeline (reads REGISTRY.md). Files bugs with `/wf-bug`. Brainstorms and decides briefs with `/wf-brainstorm`.

2. **T2 (Planner)** runs `/wf-spec` — greps REGISTRY for `draft` state. Converts briefs/bugs into plans or amends escalated plans. Review gate promotes `draft→ready`.

3. **T3 (Builder)** runs `/wf-implement` — greps REGISTRY for `ready` or `active` state. Creates feature branch worktree with `.plan-ref`, codes all steps. Exit sets `active→verify`, triggering the verify agent.

4. **Verify agent** (automatic) — triggered by REGISTRY state change to `verify`. Checks code, spec completeness, and design soundness. Auto-routes: clean→`testing`, findings→`active`, escalated→`draft`.

5. **T4 (Tester)** runs `/wf-test` — greps REGISTRY for `testing` state. Guides human through acceptance criteria. On pass, creates PR to release and sets `testing→complete`.

6. **Release** — `/wf-release` promotes the combined release branch to `main`. Bugs close, and main back-merges to develop.

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

All artifacts (plans, bugs, briefs) use a **global shared counter** embedded in `plans/REGISTRY.md` as `<!-- Counter: N -->`.

- When creating a **brief or bug**, allocate a new counter number (`wf-counter-next.sh`).
- When converting a brief/bug to a **plan**, the plan **inherits the same number** — no new allocation. BRF-041 → PLN-041, BUG-043 → PLN-043.
- IDs are type-prefixed: `PLN-NNN`, `BUG-NNN`, `BRF-NNN`.
- Numbers are globally unique across all types.

**Schema version:** `4` (see `docs/schema.md`). Registry-based model — plans never move, state in REGISTRY.md, `.plan-ref` on feature branches.

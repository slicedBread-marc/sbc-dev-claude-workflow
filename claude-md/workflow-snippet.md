## Workflow Setup

If `claude-workflow.yml` exists in the project root but has blank values, detect them from the project before using any workflow skill:

1. Scan for build/test commands — check `package.json` scripts, `*.csproj`/`*.slnx`, `Makefile`, `pytest.ini`, `go.mod`, etc.
2. Identify source directories from the project structure
3. Detect namespace/module conventions from existing source files
4. Present the detected values to the user and confirm before writing

Do this once. After `claude-workflow.yml` is filled in, the workflow skills will use those values automatically.

## Multi-Session Workflow (Brainstorm → Plan → Implement → Verify → Test → Release)

### Branch Strategy

| Branch | Role | Terminals | Purpose |
|-|-|-|-|
| `develop` | Planning & coordination | T1 (Intake), T2 (Planner) | All plan content lives here |
| `feature/*` | Implementation | T3 (Builder), T4 (Tester) | Code + `.plan-ref` only |
| `release` | Staging integration | Release manager | Pre-production testing |
| `main` | Production | — | Historical record |

### Directory Structure
```
plans/
  REGISTRY.md                  # SINGLE SOURCE OF TRUTH for plan state
  PLN-001-user-auth/           # immovable plan folder (never moves)
    plan.md                    #   spec: goal, steps, tests, design decisions
    findings.md                #   append-only: verify agent + human test results
    progress.md                #   implementer log
  PLN-002-login-fix/
    plan.md
    findings.md
    progress.md
  briefs/                      # /brainstorm — ideas and exploration
    INDEX.md
    TEMPLATE.md
  TEMPLATE.md                  # plan template

bugs/
  open/    triaged/    closed/

feature-branches/              # git worktrees
  PLN-003-payment-hook/
    .plan-ref                  # contains "PLN-003" — one line, links to plans/ on develop
    src/                       # code only, no plan content
```

**Plans never move.** State is a column value in `REGISTRY.md`, not a folder location.
**Feature branches have no plan content** — only a `.plan-ref` file with the plan ID.

### State Machine

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

### Model & Agent Strategy

| Skill | Model | Role | Agents |
|-|-|-|-|
| `/wf-status` | haiku | T1 Orchestrator | none |
| `/wf-brainstorm` | sonnet | T1 Intake | none |
| `/wf-spec` | opus | T2 Planner | codebase exploration (haiku) |
| `/wf-implement` | sonnet | T3 Builder | build/test verification (haiku) |
| `wf-verify` | sonnet | Verify Agent (auto) | parallel checks (haiku) |
| `/wf-test` | haiku | T4 Tester | none |
| `/wf-release` | haiku | Release manager | none |

### Orchestrator (`/wf-status`) — haiku
Reads REGISTRY.md, reports pipeline state, recommends next action.

### Brainstorm Role (`/wf-brainstorm`)
- Write to `plans/briefs/<name>.md`, explore options, track status (Idea → Exploring → Decided)
- A brief at **Decided** is input for `/wf-spec`

### Planner Role (`/wf-spec`)
- **Entry:** `grep "| draft |" REGISTRY.md` → show available work
- Creates immovable plan folder at `plans/PLN-NNN-<slug>/`
- Runs review gate; on pass, updates REGISTRY `draft→ready`
- For replanning: reads ESCALATED findings, writes Amendment, updates `draft→ready`

### Implementer Role (`/wf-implement`)
- **Entry:** `grep "| ready |" REGISTRY.md` or `grep "| active |"` for fix cycles
- Creates feature branch + worktree, writes `.plan-ref`
- Reads plan from develop worktree (`../../plans/PLN-NNN-<slug>/plan.md`)
- **Exit:** Updates REGISTRY `active→verify` — triggers verify agent automatically

### Verify Agent (`wf-verify`) — autonomous
- **Triggered by:** REGISTRY state change to `verify` (hook)
- Checks code (build/test), spec completeness, design soundness
- **Auto-routes:** clean→`testing`, findings→`active`, escalated→`draft`
- Writes flat checklist findings to `findings.md` on develop

### Tester Role (`/wf-test`)
- **Entry:** `grep "| testing |" REGISTRY.md`
- Human acceptance testing in the feature worktree
- **Exit (pass):** Creates PR to release, updates REGISTRY `testing→complete`
- **Exit (fail):** Writes findings, routes to `active` or `draft`

### Release Manager (`/wf-release`)
- Merges PRs to release, promotes release → main
- Updates REGISTRY to `complete`, closes bugs, back-merges to develop

### Findings Format (flat checklist)
```markdown
## Verify — 2026-04-06

- [ ] **Code**: Login endpoint returns 500 on empty password (src/auth.ts:42)
- [ ] **Spec**: Rollback section has TBD placeholder
- [ ] **Design**: Auth model incompatible ← ESCALATED
```

Routing: ESCALATED → `draft`, unchecked → `active`, all checked → advances.

### Conflict Avoidance
- Plans live only on develop — feature branches have no plan content to conflict
- REGISTRY.md is row-based — concurrent edits to different rows auto-merge
- Each terminal writes its own REGISTRY rows (T2: draft/ready, T3: active/verify, T4: testing/complete)

## Local Dev Environment

If `local_start_command`, `local_deploy_command`, and `local_stop_command` are configured in `claude-workflow.yml`, a local dev environment script is installed at `.claude/on-implement-commit.sh`. It starts automatically on every `implement(` commit and shuts down after 60 minutes of inactivity.

**Runs on feature branch worktrees** — T3/T4 work in their isolated worktree directory.

| Command | Effect |
|-|-|
| `.claude/on-implement-commit.sh start` | Start environment, begin 60-min timer |
| `.claude/on-implement-commit.sh deploy` | Start + rebuild, reset timer |
| `.claude/on-implement-commit.sh stop` | Stop environment, cancel timer |
| `.claude/on-implement-commit.sh status` | Running state + minutes remaining |

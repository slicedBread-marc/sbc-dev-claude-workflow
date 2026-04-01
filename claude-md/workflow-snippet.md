## Workflow Setup

If `claude-workflow.yml` exists in the project root but has blank values, detect them from the project before using any workflow skill:

1. Scan for build/test commands — check `package.json` scripts, `*.csproj`/`*.slnx`, `Makefile`, `pytest.ini`, `go.mod`, etc.
2. Identify source directories from the project structure
3. Detect namespace/module conventions from existing source files
4. Present the detected values to the user and confirm before writing

Do this once. After `claude-workflow.yml` is filled in, the workflow skills will use those values automatically.

## Multi-Session Workflow (Brainstorm → Plan → Implement → Verify)

### Folder Structure
```
plans/
  briefs/                    # /brainstorm — ideas and exploration
    INDEX.md                 # backlog tracker
    TEMPLATE.md
  drafts/<feature-name>/     # /spec — plan being written, not yet reviewed
    plan.md                  #   static spec (goal, steps, tests, design decisions)
    findings.md              #   shared findings queue (/review + /verify write; /implement updates)
    progress.md              #   implementer log (step completions, notes)
  ready/<feature-name>/      # reviewed & approved — waiting for /implement
  active/<feature-name>/     # /implement is working on it
  verify/<feature-name>/     # implementation done — waiting for /verify
  replanning/<feature-name>/ # verify found design-scope issues — waiting for /spec to amend
  complete/<feature-name>/   # all findings resolved — static historical record
  TEMPLATE.md                # implementation plan spec
```

**The folder IS the status.** Each plan is a uniquely named subfolder that moves between stage directories. `ls plans/ready/` shows what's waiting to be built. Multiple plans can be in flight simultaneously without collision.

### Model & Agent Strategy
Each skill specifies its recommended model. Use `/model` to switch before invoking a skill.

| Skill | Model | Agents | Agent model |
|-|-|-|-|
| `/status` | haiku | none | — |
| `/brainstorm` | sonnet | none | — |
| `/spec` | opus | codebase exploration | haiku |
| `/review` | sonnet | parallel checks (code review only) | haiku |
| `/implement` | opus | lookup only (sparingly) | haiku |
| `/verify` | sonnet | parallel build/test/quality checks | haiku |

**Principle:** Opus for creation (plans, code), sonnet for evaluation (review, verify), haiku for data gathering (agents, status). Agents should have strict output limits (under 1000-2000 chars) and be spawned in parallel where possible.

Each skill has a `model:` field in its frontmatter that overrides the session model when invoked. If you suspect the override isn't active, warn the user twice before proceeding:
1. **First warning:** "This skill is designed for [model]. You appear to be on [current]. Switch with `/model [model]` for best results."
2. **Second warning (if user proceeds):** "Continuing on [current] — this may use more tokens than necessary or produce lower quality output."

### Orchestrator (`/status`) — haiku
Read-only scan of the full pipeline. Reports what's in each stage and recommends the highest-priority next action. **Start every session here** if you're unsure what to work on.

Priority order: open findings → ready plans → drafts needing review → decided briefs → in-progress work → exploring ideas → nothing pending.

### Brainstorm Role (`/brainstorm`)
- Write to `plans/briefs/<name>.md` following `plans/briefs/TEMPLATE.md`
- Explore the problem, list options with tradeoffs, surface open questions
- Briefs are living documents — rewrite freely until status is **Decided**
- Do NOT write implementation steps or edit source code
- A brief at **Decided** is the input for a planner session

### Planner Role (`/spec`)
- Reads brief from `plans/briefs/`, creates a named plan folder in `plans/drafts/<feature-name>/` with `plan.md`, `findings.md`, `progress.md`
- Every step must list exact file paths, class/method/component names, and acceptance criteria
- Make all design decisions — the implementer should not need to make judgment calls
- Runs review gate automatically when user approves
- Moves plan folder `drafts/<name>/` → `ready/<name>/` only after review passes
- If a plan is already in `active/` or beyond, only append to `plan.md`'s **Amendments**

### Implementer Role (`/implement`)
- Picks up plan folders from `plans/ready/`, moves to `plans/active/`
- Reads `plan.md` for steps and design decisions
- Tracks completions and notes in `progress.md`
- When done: moves folder `active/<name>/` → `verify/<name>/`
- Fix cycle: reads `Open` findings from `findings.md`, fixes, updates status to `Fixed`, moves back to `verify/`
- **Ignores `Escalated` findings** — these require a planner, not an implementer

### Reviewer Role (`/review`)
- Runs automatically as a gate within `/spec` before `drafts/` → `ready/`
- Can also be invoked independently for code review
- Writes plan review result to `plan.md`'s Review section; appends findings to `findings.md`
- Critical findings block the plan from reaching `ready/`

### Verifier Role (`/verify`)
- Works on plan folders in `plans/verify/`
- Reads `plan.md` for the verification checklist; appends findings to `findings.md`
- Confirms `Fixed` findings → sets to `Verified` in `findings.md`
- When queue is clean: moves folder `verify/<name>/` → `complete/<name>/`
- **Escalation path:** if a finding requires a design change (not a code fix), sets status to `Escalated` and moves folder to `plans/replanning/`
- Does NOT write code, implementation steps, or solutions — describes what is wrong and why only

### Planner Role — Replanning (`/spec` with escalated findings)
- On startup, checks `plans/replanning/` before new briefs
- Reads `plan.md` and `findings.md` for escalated findings, discusses design resolution with user
- Appends an **Amendment** to `plan.md` (never rewrites existing steps)
- Re-runs the review gate, then moves folder back to `plans/ready/`

### Findings Queue
All diagnostic roles (`/review`, `/verify`) write to a shared **Findings Queue** table in the plan. The implementer consumes `Open` findings; escalated findings route back to the planner.

```
/review ──► Findings Queue ◄── /implement reads & fixes (Open only)
/verify ──►   Open → Fixed → Verified
              Escalated ──────────────► /spec amends → back to ready/
```

- **Open** — code-level issue, implementer can fix
- **Fixed** — implementer addressed it
- **Verified** — verifier confirmed the fix
- **Escalated** — design/scope issue, requires planner to amend the plan
- Plan cannot reach `Complete` while any finding is `Open`, `Fixed`, or `Escalated`

### Conflict Avoidance
- Planner edits `plans/drafts/` and `plans/briefs/` only
- Implementer edits source/test dirs and the plan's Progress/Findings Queue status
- Reviewer and verifier edit the plan's Review/Findings Queue/Checklist sections only
- A plan file should only be in one folder at a time — never copy, always move
- If the planner needs to amend a plan in `active/` or beyond, append to **Amendments** — never rewrite
- Sessions should avoid reading files another session is actively writing

## Local Dev Environment

If `local_start_command`, `local_deploy_command`, and `local_stop_command` are configured in `claude-workflow.yml`, a local dev environment script is installed at `.claude/on-implement-commit.sh`. It starts automatically on every `implement(` commit and shuts down after 60 minutes of inactivity.

| Command | Effect |
|-|-|
| `.claude/on-implement-commit.sh start` | Start environment, begin 60-min timer |
| `.claude/on-implement-commit.sh deploy` | Start + rebuild, reset timer |
| `.claude/on-implement-commit.sh stop` | Stop environment, cancel timer |
| `.claude/on-implement-commit.sh status` | Running state + minutes remaining |

Configure in `claude-workflow.yml`:
- `local_start_command` — start without rebuilding (e.g. `docker-compose up -d`)
- `local_deploy_command` — start and rebuild (e.g. `docker-compose up --build -d`)
- `local_stop_command` — stop the environment (e.g. `docker-compose stop`)

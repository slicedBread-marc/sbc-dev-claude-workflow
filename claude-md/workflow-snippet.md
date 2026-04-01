## Multi-Session Workflow (Brainstorm → Plan → Implement → Verify)

### Folder Structure
```
plans/
  briefs/              # /brainstorm — ideas and exploration
    INDEX.md           # backlog tracker
    TEMPLATE.md
  drafts/              # /plan — plans being written, not yet reviewed
  ready/               # reviewed & approved — waiting for /implement
  active/              # /implement is working on it
  verify/              # implementation done — waiting for /verify
  complete/            # all findings resolved — static historical record
  TEMPLATE.md          # implementation plan template
```

**The folder IS the status.** Skills move plan files between folders as they progress. `ls plans/ready/` shows what's waiting to be built.

### Model & Agent Strategy
Each skill specifies its recommended model. Use `/model` to switch before invoking a skill.

| Skill | Model | Agents | Agent model |
|-|-|-|-|
| `/status` | haiku | none | — |
| `/brainstorm` | sonnet | none | — |
| `/plan` | opus | codebase exploration | haiku |
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

### Planner Role (`/plan`)
- Reads brief from `plans/briefs/`, writes plan to `plans/drafts/`
- Every step must list exact file paths, class/method/component names, and acceptance criteria
- Make all design decisions — the implementer should not need to make judgment calls
- Runs review gate automatically when user approves
- Moves plan `drafts/` → `ready/` only after review passes
- If a plan is already in `active/` or beyond, only append to **Amendments**

### Implementer Role (`/implement`)
- Picks up plans from `plans/ready/`, moves to `plans/active/`
- Follows steps in order, checks off each, logs progress
- Writes all tests from the plan's Tests table
- When done: moves `active/` → `verify/`
- Fix cycle: picks up `Open` findings from `verify/`, moves to `active/`, fixes, moves back to `verify/`

### Reviewer Role (`/review`)
- Runs automatically as a gate within `/plan` before `drafts/` → `ready/`
- Can also be invoked independently for code review
- Writes findings to **Review** section and **Findings Queue**
- Critical findings block the plan from reaching `ready/`

### Verifier Role (`/verify`)
- Works on plans in `plans/verify/`
- Runs verification checklist, writes findings to **Findings Queue**
- Confirms `Fixed` findings → sets to `Verified`
- When queue is clean: moves `verify/` → `complete/`

### Findings Queue
All diagnostic roles (`/review`, `/verify`) write to a shared **Findings Queue** table in the plan. The implementer consumes it:

```
/review ──► Findings Queue ◄── /implement reads & fixes
/verify ──►      (Open → Fixed → Verified)
```

- **Open** — finding identified, not yet addressed
- **Fixed** — implementer addressed it
- **Verified** — verifier confirmed the fix
- Plan cannot reach `Complete` while any finding is `Open` or `Fixed`

### Conflict Avoidance
- Planner edits `plans/drafts/` and `plans/briefs/` only
- Implementer edits source/test dirs and the plan's Progress/Findings Queue status
- Reviewer and verifier edit the plan's Review/Findings Queue/Checklist sections only
- A plan file should only be in one folder at a time — never copy, always move
- If the planner needs to amend a plan in `active/` or beyond, append to **Amendments** — never rewrite
- Sessions should avoid reading files another session is actively writing

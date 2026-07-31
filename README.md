# claude-workflow

A structured SDLC workflow for Claude Code. Skills guide work through a pipeline — brainstorm, plan, implement, verify, test — with state tracked in a registry rather than in your head.

Run it **manually** across four terminals, or turn on the **orchestrator** and run it from one: a daemon dispatches the same skills as unattended workers by pipeline state, and parks the decisions a machine shouldn't make into a queue you drain when convenient.

## Quick Start

```bash
# Clone into your tools directory
git clone https://github.com/yourusername/claude-workflow.git ~/dev/claude-workflow

# Go to your project
cd ~/dev/my-project

# First run creates a config file for you to edit
~/dev/claude-workflow/install.sh .

# Edit the config with your project's build/test commands
vim claude-workflow.yml

# Re-run to install
~/dev/claude-workflow/install.sh .
```

## What It Installs

```
your-project/
  .claude/skills/
    wf-status/SKILL.md     # /wf-status — pipeline dashboard
    wf-brainstorm/SKILL.md # /wf-brainstorm — capture ideas
    wf-spec/SKILL.md       # /wf-spec — write implementation specs
    wf-review/SKILL.md     # /wf-review — architecture & security review
    wf-implement/SKILL.md  # /wf-implement — build from specs
    wf-verify/SKILL.md     # wf-verify — autonomous verify agent (not user-invocable)
    wf-test/SKILL.md       # /wf-test — human acceptance testing
  plans/
    REGISTRY.md                  # SINGLE SOURCE OF TRUTH for plan state
    PLN-001-feature-name/        # immovable plan folder (never moves)
      plan.md                    #   spec: goal, steps, tests, design decisions
      findings.md                #   append-only: verify agent + human test results
      progress.md                #   implementer log
    briefs/                      # idea exploration documents
      INDEX.md                   # backlog tracker
      TEMPLATE.md
    TEMPLATE.md                  # implementation plan spec
  CLAUDE.md                      # workflow section appended
```

## The Pipeline

```
draft → ready → active → verify ──[agent]──→ testing → complete
                  ↑          |
                  |          ├→ active  (fix cycle)
                  |          └→ draft   (escalation)
                  └→ draft  (implementer escalation)
```

**REGISTRY.md IS the status.** `grep "| ready |" plans/REGISTRY.md` shows what's waiting to be built. Plans never move — only the state column changes.

## Skills

| Command | Model | Purpose |
|-|-|-|
| `/wf-status` | haiku | Read REGISTRY.md, recommend next action |
| `/wf-brainstorm` | sonnet | Capture and explore ideas |
| `/wf-spec` | opus | Convert decided brief → implementation spec |
| `/wf-review` | sonnet | Architecture & security review (auto-gate + manual) |
| `/wf-implement` | sonnet | Build from plan, fix findings |
| `wf-verify` | sonnet | Autonomous verify agent (triggered by state change) |
| `/wf-test` | haiku | Human acceptance testing |
| `/wf-board` | haiku | Live orchestrator view — workers, gates, events |
| `/wf-attend` | haiku | Drain the gate queue |
| `/wf-orchestrate` | haiku | Drive one item end to end, or manage the daemon |

## Orchestrated Workflow (one terminal)

```bash
scripts/wf-exec.sh wf-orchestrate.sh --sweep --dry-run   # preview first, always
scripts/wf-exec.sh wf-orchestrate.sh --daemon            # continuous dispatch
scripts/wf-exec.sh wf-orchestrate.sh BUG-094             # drive one item end to end
scripts/wf-exec.sh wf-board.sh --watch                   # live view
```

The daemon reads `REGISTRY.md` and launches a headless worker per actionable
plan — spec on opus, implement and verify on sonnet, test on haiku. **Routing is
pure bash; the orchestrator never calls a model.** Only workers cost tokens.

When a worker hits something a machine shouldn't decide — approving a spec, an
acceptance criterion that needs human eyes, a failed push — it opens a **gate**
and exits cleanly instead of guessing. `/wf-attend` walks that queue.

Ships **disabled** (`orchestrator.enabled: false`): workers run with
`--dangerously-skip-permissions`, so enabling it is a deliberate decision. Caps
on concurrency, per-plan attempts, and hourly spawns are the guardrails.

Full design: [`docs/orchestrator.md`](docs/orchestrator.md).

### Driving it from another project

Each installed client gets a generated `WORKFLOW.md` at its root describing the
entry points for an agent arriving cold. The contract is the exit code:

| Code | Meaning |
|-|-|
| 0 | Reached the target state |
| 20 | Blocked on a human — gate details in `--json`. **Never auto-retry** |
| 30 | Worker ran, state unchanged |
| 1 | Error |

## Workflow Issues — the feedback loop

The harness will sometimes be wrong. When a skill or script behaves in a way its
own documentation doesn't describe, whoever hits it records it in that project
rather than working around it silently:

```bash
scripts/wf-exec.sh wf-issue.sh --source wf-implement \
  --expected "active→verify to succeed" \
  --actual   "Error: PLN-097 not found in state 'active'"
```

That appends to `WORKFLOW-ISSUES.md` at the client's root. From the library, sweep
every installed project at once:

```bash
./sweep-issues.sh                                              # open issues by client
./sweep-issues.sh --resolve WFI-003 --client sbc "fixed in v2.6.0"
```

Fixes go in the library and reach every project on the next `./deploy-all.sh` — so
one report improves the workflow everywhere, instead of each project accumulating
its own workarounds. Unattended workers file these too, which is how process bugs
surface from runs nobody was watching.

## Multi-Terminal Workflow (manual mode)

```
T1: Intake (sonnet)                T2: Planner (opus)
───────────────────                ──────────────────
/wf-status                         
/wf-brainstorm → Decided brief     
                                   /wf-spec → review gate → ready

T3: Builder (sonnet)               T4: Tester (haiku)
────────────────────               ──────────────────
/wf-implement → active → verify    
  [verify agent auto-runs]         
                                   /wf-test → pass → complete
```

## Configuration

`claude-workflow.yml` in your project root:

```yaml
build_command: "npm run build"
test_command: "npm test"
test_filter_flag: "--grep"
source_dirs:
  - "src/"
  - "tests/"
namespace_convention: ""
conventions_note: ""
solution_file: ""
```

## Updating

Re-run the install script. It overwrites skills but skips existing templates and config.

## Token Strategy

- **Opus** only where quality matters most: writing plans
- **Sonnet** for structured work: implementation, reviews, verification agent
- **Haiku** for lightweight tasks: status checks, testing, agent subtasks
- Skills spawn haiku agents for parallel data collection, keeping the main context lean

## License

MIT

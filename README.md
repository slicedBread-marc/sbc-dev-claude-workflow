# claude-workflow

A structured SDLC workflow for Claude Code. Provides skills that guide work through a multi-terminal pipeline: brainstorm, plan, implement, verify (auto), test — orchestrated by a status dashboard.

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

## Multi-Terminal Workflow

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

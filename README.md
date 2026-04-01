# claude-workflow

A structured SDLC workflow for Claude Code. Provides six skills that guide work through a pipeline: brainstorm, plan, review, implement, verify — orchestrated by a status dashboard.

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
    status/SKILL.md        # /status — pipeline dashboard
    brainstorm/SKILL.md    # /brainstorm — capture ideas
    spec/SKILL.md           # /spec — write implementation specs
    review/SKILL.md        # /review — architecture & security review
    implement/SKILL.md     # /implement — build from specs
    verify/SKILL.md        # /verify — confirm implementation
  plans/
    briefs/                      # idea exploration documents
      INDEX.md                   # backlog tracker
      TEMPLATE.md
    drafts/<feature-name>/       # plan being written (plan.md, findings.md, progress.md)
    ready/<feature-name>/        # reviewed, ready to build
    active/<feature-name>/       # currently being implemented
    verify/<feature-name>/       # awaiting verification
    replanning/<feature-name>/   # escalated findings — needs planner to amend
    complete/<feature-name>/     # done — historical record
    TEMPLATE.md                  # implementation plan spec
  CLAUDE.md                # workflow section appended
```

## The Pipeline

```
/brainstorm → /spec → /review (gate) → /implement → /verify
                ↑                           ↕              |
                |                     Findings Queue       |
                |                  Open → Fixed → Verified |
                └──── /spec amends ←── Escalated ──────────┘
```

**The folder IS the status.** `ls plans/ready/` shows what's waiting to be built.

## Skills

| Command | Model | Purpose |
|-|-|-|
| `/status` | haiku | Scan pipeline, recommend next action |
| `/brainstorm` | sonnet | Capture and explore ideas |
| `/spec` | opus | Convert decided brief → implementation spec |
| `/review` | sonnet | Architecture & security review (auto-gate + manual) |
| `/implement` | opus | Build from plan, fix findings |
| `/verify` | sonnet | Check implementation, write findings |

## Multi-Terminal Workflow

```
Terminal 1 (thinking)              Terminal 2 (building)
─────────────────────              ─────────────────────

/status                            
/brainstorm → idea → Decided       
/spec → review gate → Ready
                                   /implement → builds → Verifying
/verify → findings → queue         
                                   /implement → fixes → Verifying
/verify → clean → Complete         
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

- **Opus** only where quality matters most: writing plans, writing code
- **Sonnet** for structured evaluation: reviews, verification
- **Haiku** for data gathering: status checks, agent tasks
- Skills spawn haiku agents for parallel data collection, keeping the main context lean

## License

MIT

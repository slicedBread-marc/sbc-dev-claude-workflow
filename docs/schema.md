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

### v4 (current)
- `schema_version: 4`
- **Registry-based model** — plans never move. State is tracked in `plans/REGISTRY.md`.
- **Counter embedded** in REGISTRY.md as `<!-- Counter: N -->` — no separate `.counter` file
- **No folder movement** — each plan lives at `plans/PLN-NNN-<slug>/` forever
- **No plan content on feature branches** — only a `.plan-ref` file containing the plan ID
- **Verify agent** replaces manual wf-verify skill — triggered automatically on state change to `verify`
- **Simplified findings** — flat checklists instead of FND-NNN tables with status columns

## Skill Behaviour

| `schema_version` | Model | State tracking | Plan on feature branch | Counter |
|-|-|-|-|-|
| absent | v1 | Folder location | `plans/{stage}/` | Per-type files |
| `2` | v2 | Folder location | `plans/{stage}/` | `plans/.counter` |
| `3` | v3 | Folder location | `.plan/` | `plans/.counter` |
| `4` | v4 | REGISTRY.md row | `.plan-ref` (ID only) | REGISTRY.md comment |

When creating new artifacts, always write `schema_version: 4`.

## REGISTRY.md

Single source of truth for plan state. Lives at `plans/REGISTRY.md` on develop.

```markdown
| ID | Slug | State | Branch | Updated |
|-|-|-|-|-|
| PLN-001 | user-auth | complete | — | 2026-04-01 |
| PLN-003 | payment-hook | active | feature/PLN-003-payment-hook | 2026-04-06 |

<!-- Counter: 4 -->
```

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

## Counter

Embedded in `plans/REGISTRY.md` as `<!-- Counter: N -->`. To allocate:
1. Read N from the comment
2. Use N as the new artifact ID
3. Write N+1 back in the same commit

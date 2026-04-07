# Workflow Document Schema Versions

All workflow artifacts (plans, bugs, briefs) carry a `schema_version` field in their header. Skills use this field to handle migration data correctly.

## Version History

### v1 (legacy)
- `schema_version` field is **absent**
- Plans use `PLN-NNN` IDs, bugs use `BUG-NNN` IDs
- Each type has its own independent counter — numbers are **not globally unique** across types
- Treat any document without `schema_version` as v1

### v2
- `schema_version: 2` present in document header
- **Global counter:** all artifact types (plans, bugs, briefs) share a single counter stored in `plans/.counter`
- IDs are globally unique across all types — a PLN-009 and BUG-009 cannot both exist
- The counter file contains a single integer: the **next** number to allocate
- When allocating a new ID: read `.counter`, use the value, increment and write back

### v3
- `schema_version: 3` present in document header
- **`.plan/` isolation:** feature branches store their working plan in `.plan/` (plan.md, findings.md, progress.md). Feature branches never modify `plans/`.
- **`plans/` on develop only:** pipeline stage moves (`ready/` → `active/` → `verify/` → `complete/`) happen exclusively on the `develop` branch.
- **Status hints:** `plans/verify/` entries on develop carry `Status: Verified` or `Status: Verified-with-findings` so scripts can build menus without entering worktrees.
- **Backwards compatible:** worktrees with v2-style `plans/verify/PLN-NNN/` are still supported via PLN-prefix scoping during transition.

## Skill Behaviour

When reading an artifact, check `schema_version`:

| Field value | Treat as | ID uniqueness | Plan location on feature branch |
|-|-|-|-|
| absent | v1 legacy | Per-type only | `plans/{stage}/` |
| `2` | v2 | Global | `plans/{stage}/` |
| `3` | v3 | Global | `.plan/` |

Skills must not assume global uniqueness when operating on v1 documents. When creating new artifacts, always write `schema_version: 3` and draw from the global counter. On feature branches, check for `.plan/` first (v3); fall back to `plans/{stage}/PLN-NNN-*/` (v2) for legacy worktrees.

## Plan Status Field

The `Status:` line in `plan.md` tracks where a plan is in its lifecycle. Status may appear plain (`Status: Verified`) or markdown-formatted (`> **Status:** Verified`).

| Status | Folder | Meaning |
|-|-|-|
| *(none/Drafted)* | `drafts/` | Being written by T2 |
| Ready | `ready/` | Reviewed, approved, waiting for T3 |
| Active | `active/` | Claimed by T3, implementation in progress |
| Verified | `verify/` | Implementation verified by T4, eligible for human testing |
| Verified-with-findings | `verify/` | Has unresolved findings — needs T3 fix cycle |
| Tested | `verify/` | Human test passed, pending merge to release |
| *(moved)* | `complete/` | Merged to release, closed |
| *(moved)* | `replanning/` | Escalated findings require T2 design decisions |
| *(moved)* | `rolled-back/` | Reverted |

## Finding Status Field

Each row in `findings.md` has a Status column tracking resolution.

| Finding Status | Meaning | Who acts next |
|-|-|-|
| Open | Unresolved — needs attention | T3 (Warning/Critical) or T2 (Escalated) |
| Fixed | Implementer claims fixed, not yet re-verified | T4 (re-verify or re-test) |
| Closed | Verified as resolved | No action needed |

**Key rule:** a plan is only "clean" when it has zero Open **and** zero Fixed findings. Fixed ≠ Closed — Fixed findings still need T4 to confirm the fix before the plan can advance.

## Detector Scripts

Three scripts in `scripts/` scan `plans/` on develop to build menus for each terminal role. All run from the project root on the develop branch.

### `wf-list-specable.sh` (T2 — Planner)

Finds work for `/wf-spec`. Output sections prefixed with `# type` headers:

| Section | Source | Condition |
|-|-|-|
| `# replanning` | `plans/replanning/*/plan.md` | Any plan with Escalated findings |
| `# bugs` | `bugs/open/*/bug.md` | Any open bug |
| `# briefs` | `plans/briefs/INDEX.md` | Entries under `## Decided` heading |

### `wf-list-implementable.sh` (T3 — Builder)

Finds work for `/wf-implement`. Each line: `<type>\t<plan-name>\t<goal>`

| Type | Source | Condition |
|-|-|-|
| `new` | `plans/ready/` | No existing worktree |
| `amendment` | `plans/ready/` | Worktree already exists (re-spec'd plan) |
| `resume` | `plans/active/` | Mid-implementation |
| `fix` | `plans/verify/` | Status: Verified-with-findings **OR** any `\| Open \|` findings |

Clean Verified plans in `plans/verify/` are **not** listed here — they belong to T4's testable list.

### `wf-list-testable.sh` (T4 — Validator)

Finds work for `/wf-test`. Each line: `<plan-name>\t<goal>`

| Condition | Filter |
|-|-|
| Folder | `plans/verify/*/plan.md` |
| Status | Must match `Verified` (not `Verified-with-findings`) |
| Findings | Zero `\| Open \|` rows **AND** zero `\| Fixed \|` rows |

**Why filter Fixed:** `Fixed` means the implementer claims a fix but T4 hasn't confirmed it. These plans need `/wf-verify` first (to move findings from Fixed → Closed), then they become eligible for `/wf-test`.

Plans skipped due to Open or Fixed findings are counted and reported to stderr.

## Counter File

Location: `plans/.counter` (relative to project root)

Format: a single integer on one line, no trailing content.

Example — if the file contains `9`, the next artifact gets number `9` and the file is updated to `10`.

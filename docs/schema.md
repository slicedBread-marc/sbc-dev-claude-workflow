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

## Counter File

Location: `plans/.counter` (relative to project root)

Format: a single integer on one line, no trailing content.

Example — if the file contains `9`, the next artifact gets number `9` and the file is updated to `10`.

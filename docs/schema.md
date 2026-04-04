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

## Skill Behaviour

When reading an artifact, check `schema_version`:

| Field value | Treat as | ID uniqueness |
|-|-|-|
| absent | v1 legacy | Per-type only |
| `2` | v2 | Global |

Skills must not assume global uniqueness when operating on v1 documents. When creating new artifacts, always write `schema_version: 2` and draw from the global counter.

## Counter File

Location: `plans/.counter` (relative to project root)

Format: a single integer on one line, no trailing content.

Example — if the file contains `9`, the next artifact gets number `9` and the file is updated to `10`.

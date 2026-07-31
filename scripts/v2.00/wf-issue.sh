#!/usr/bin/env bash
# wf-issue.sh — record a problem with the WORKFLOW HARNESS ITSELF.
#
# This is not for application bugs (that's /wf-bug) and not for plan findings
# (that's findings.md). It is for the pipeline misbehaving: a wf-* script that
# errored unexpectedly, a skill instruction that referenced something that
# doesn't exist, a registry state that contradicts reality, a plan that looped.
#
# Entries land in WORKFLOW-ISSUES.md at the DEVELOP ROOT of this client, so a
# worker inside a feature worktree still files to the one place per project.
# The claude-workflow library sweeps every client periodically (sweep-issues.sh)
# and fixes the underlying process bugs upstream.
#
# FILE AN ISSUE
#   wf-issue.sh --source wf-implement \
#               --expected "wf-registry-update.sh active→verify to succeed" \
#               --actual   "Error: PLN-097 not found in state 'active'" \
#               [--context "PLN-097, worktree feature/PLN-097-foo"] \
#               [--notes   "registry already showed verify"]
#
# READ THEM BACK
#   wf-issue.sh --list            open issues, newest first
#   wf-issue.sh --list --all      including resolved
#   wf-issue.sh --count           number of open issues (stdout, for scripts)
#   wf-issue.sh --resolve WFI-003 "fixed in workflow v2.6.0"
#
# Deliberately non-interactive: an unattended worker must be able to file one
# and carry on. Never prompts, never blocks, never fails the caller — filing a
# report must not be able to break the run that hit the problem.
#
# Exit 0 on success. Exit 1 only on genuinely bad usage.

set -uo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=wf-orch-lib.sh
source "$SELF_DIR/wf-orch-lib.sh"
# shellcheck source=wf-lock.sh
source "$SELF_DIR/wf-lock.sh"

ROOT="$(wf_develop_root)"
ISSUES="$ROOT/WORKFLOW-ISSUES.md"

HEADER='# Workflow Issues

Problems with the **workflow harness itself** — a `wf-*` script, a skill
instruction, or the pipeline behaving in a way its own documentation does not
describe.

**This is not for application bugs** (use `/wf-bug`) and not for plan findings
(those go in the plan'"'"'s `findings.md`). It is for the tooling being wrong.

File one with:

```bash
scripts/wf-exec.sh wf-issue.sh --source <skill-or-script> \
  --expected "<what the docs say should happen>" \
  --actual   "<what happened, verbatim>"
```

These are swept into the claude-workflow library periodically and fixed
upstream, so an entry here becomes a fix for every project using the workflow.
Leave resolved entries in place — they are the record of what was already
reported.

<!-- New entries are inserted directly below this line, newest first. -->
'

ensure_file() {
  [ -f "$ISSUES" ] || printf '%s\n' "$HEADER" > "$ISSUES"
}

# ── Read modes ────────────────────────────────────────────────────────────

case "${1:-}" in
  --list)
    ensure_file
    # Split on the issue heading so each record is one whole block, then filter
    # by its own Status line. RS='\n## ' means record 1 is the file header.
    if [ "${2:-}" = "--all" ]; then
      awk -v RS='\n## ' 'NR > 1 { print "## " $0 }' "$ISSUES"
    else
      awk -v RS='\n## ' 'NR > 1 && /\*\*Status:\*\* *open/ { print "## " $0 }' "$ISSUES"
    fi
    exit 0
    ;;
  --count)
    ensure_file
    # grep -c prints 0 AND exits 1 when there are no matches, so a `|| echo 0`
    # fallback would emit two lines. Capture, then print exactly once.
    n=$(grep -c '^\*\*Status:\*\* *open' "$ISSUES" 2>/dev/null)
    printf '%s\n' "${n:-0}"
    exit 0
    ;;
  --resolve)
    id="${2:?Usage: $0 --resolve <WFI-NNN> [note]}"
    # Flattened: this goes through awk -v, which cannot carry newlines.
    note=$(printf '%s' "${3:-resolved}" | tr '\n' ' ')
    ensure_file
    wf_lock_acquire "workflow-issues" || exit 0
    awk -v id="$id" -v note="$note" -v today="$(date -u +%Y-%m-%d)" '
      $0 ~ "^## " id " " { inblock = 1 }
      inblock && /^\*\*Status:\*\*/ {
        print "**Status:** resolved " today " — " note
        inblock = 0; next
      }
      { print }
    ' "$ISSUES" > "$ISSUES.tmp" && mv "$ISSUES.tmp" "$ISSUES"
    echo "$id: resolved — $note"
    exit 0
    ;;
esac

# ── File mode ─────────────────────────────────────────────────────────────

source_name=""
expected=""
actual=""
context=""
notes=""

while [ $# -gt 0 ]; do
  case "$1" in
    --source)   source_name="${2:-}"; shift 2 ;;
    --expected) expected="${2:-}"; shift 2 ;;
    --actual)   actual="${2:-}"; shift 2 ;;
    --context)  context="${2:-}"; shift 2 ;;
    --notes)    notes="${2:-}"; shift 2 ;;
    -h|--help)  sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "wf-issue.sh: unknown option '$1'" >&2; exit 1 ;;
  esac
done

if [ -z "$source_name" ] || [ -z "$actual" ]; then
  echo "Usage: $0 --source <skill-or-script> --expected <text> --actual <text> [--context <text>] [--notes <text>]" >&2
  echo "       $0 --list [--all] | --count | --resolve <WFI-NNN> [note]" >&2
  exit 1
fi
[ -n "$expected" ] || expected="(not stated)"

ensure_file

# Serialize appends — several workers can hit the same harness bug at once.
wf_lock_acquire "workflow-issues" || exit 0

# Next ID: one more than the highest already present.
last=$(grep -oE '^## WFI-[0-9]+' "$ISSUES" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1)
next=$(printf 'WFI-%03d' "$(( ${last:-0} + 1 ))")

wf_version=$(tr -d '[:space:]' < "$ROOT/.claude/workflow-version" 2>/dev/null || echo "unknown")

entry=$(cat <<ENTRY

## $next — $source_name — $(wf_now)

**Status:** open
**Workflow version:** $wf_version
**Context:** ${context:-—}

**Expected:**
$expected

**Actual:**
\`\`\`
$actual
\`\`\`
ENTRY
)
[ -n "$notes" ] && entry="$entry

**Notes:**
$notes"

# Insert directly after the marker so newest is first and the header survives.
# Done with head/tail rather than awk -v: awk cannot carry a multi-line value
# through -v (it dies with "newline in string"), and a captured error message
# is very often multi-line — which is exactly the case worth recording.
marker='<!-- New entries are inserted directly below this line, newest first. -->'
marker_line=$(grep -nF "$marker" "$ISSUES" 2>/dev/null | head -1 | cut -d: -f1)
if [ -n "$marker_line" ]; then
  {
    head -n "$marker_line" "$ISSUES"
    printf '%s\n' "$entry"
    tail -n +"$((marker_line + 1))" "$ISSUES"
  } > "$ISSUES.tmp" && mv "$ISSUES.tmp" "$ISSUES"
else
  printf '%s\n' "$entry" >> "$ISSUES"
fi

wf_event issue "${context:-—}" "$next: $source_name — $expected"
echo "$next filed in WORKFLOW-ISSUES.md ($source_name)"
exit 0

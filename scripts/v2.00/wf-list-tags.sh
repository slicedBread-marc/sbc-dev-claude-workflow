#!/usr/bin/env bash
# wf-list-tags.sh [--plain] [--gating]
#
# Prints THIS project's tag vocabulary, derived rather than shipped.
#
# Default output is one row per tag, most-used first:
#
#   contract    1   gate
#   relay       4   —
#   infra       2   —
#
#   $1 tag   $2 how many plans carry it   $3 `gate` if it is in
#                                            specApproval.gateTags, else —
#
#   --plain    comma-joined on one line, for embedding in a prompt
#   --gating   only the gating tags, one per line
#
# WHY THIS IS NOT A CONSTANT
#
# wf-spec used to offer a hardcoded list — `security, arcade, admin, lessons,
# ux, infra, e2e, bugfix` — and wf-set-tags.sh rejected anything outside it.
# Three of those names come from one project's game/admin/lessons app and mean
# nothing anywhere else, while a relay program's `contract` tag (its frozen
# wire surface, the one tag it gates on) could not be assigned at all.
#
# The list was already being ignored in practice, which is the failure mode
# that matters: it looked authoritative, was not, and sat directly in front of
# a gating decision — specApproval.gateTags keys on tag VALUES, so a planner
# picking from a list that omits the gating tag silently decides that a plan
# does not need a human.
#
# Sources, unioned:
#   1. the Tags column of every row in plans/REGISTRY.md — what the project
#      actually uses
#   2. `tags:` in claude-workflow.yml, if present — names a project wants
#      available before any plan carries them
#   3. specApproval.gateTags — always listed, always marked, because those are
#      the choices that carry a consequence
#
# Exit 0 always. Prints nothing when the project has no vocabulary yet.

set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

# Registry work is develop-root work — see wf-registry-update.sh.
_wf_root=$(git worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //') || true
[ -n "$_wf_root" ] || _wf_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
cd "$_wf_root"

REGISTRY="plans/REGISTRY.md"

plain=false
gating_only=false
for arg in "$@"; do
  case "$arg" in
    --plain)  plain=true ;;
    --gating) gating_only=true ;;
    *) echo "Usage: $0 [--plain] [--gating]" >&2; exit 2 ;;
  esac
done

# ── Gating tags ───────────────────────────────────────────────────────────
gate_tags=""
while IFS= read -r t; do
  t=$(printf '%s' "$t" | tr -d '[:space:]')
  [ -n "$t" ] || continue
  gate_tags="$gate_tags $t"
done < <("$SELF_DIR/wf-config-get.sh" specApproval.gateTags --list 2>/dev/null || true)

if $gating_only; then
  for t in $gate_tags; do printf '%s\n' "$t"; done
  exit 0
fi

# ── Tags in use, with a count ─────────────────────────────────────────────
counts_file=$(mktemp)
trap 'rm -f "$counts_file"' EXIT

if [ -f "$REGISTRY" ]; then
  # Column 9 is Tags. Rows only — the header and separator have no PLN id.
  awk -F'|' '
    $2 !~ /^[ \t]*(PLN|BUG|BRF)-[0-9]+[ \t]*$/ { next }
    {
      tags = $9
      gsub(/[ \t]/, "", tags)
      if (tags == "" || tags == "—") next
      n = split(tags, list, ",")
      for (i = 1; i <= n; i++) if (list[i] != "" && list[i] != "—") print list[i]
    }
  ' "$REGISTRY" | sort | uniq -c | awk '{ print $2 "\t" $1 }' > "$counts_file"
fi

# ── Declared-but-unused names ─────────────────────────────────────────────
# `tags:` in claude-workflow.yml, plus every gate tag, at count 0 if no plan
# carries them yet. A gate tag nobody has used is exactly the one a planner
# most needs to see.
declared=""
while IFS= read -r t; do
  t=$(printf '%s' "$t" | tr -d '[:space:]')
  [ -n "$t" ] && declared="$declared $t"
done < <("$SELF_DIR/wf-config-get.sh" tags --list 2>/dev/null || true)

for t in $declared $gate_tags; do
  cut -f1 "$counts_file" | grep -qx "$t" || printf '%s\t0\n' "$t" >> "$counts_file"
done

# ── Emit ──────────────────────────────────────────────────────────────────
sorted=$(sort -t"$(printf '\t')" -k2,2nr -k1,1 "$counts_file")
[ -n "$sorted" ] || exit 0

if $plain; then
  printf '%s\n' "$sorted" | cut -f1 | paste -sd, - | sed 's/,/, /g'
  exit 0
fi

while IFS=$'\t' read -r tag count; do
  [ -n "$tag" ] || continue
  mark="—"
  for g in $gate_tags; do [ "$g" = "$tag" ] && mark="gate"; done
  printf '%s\t%s\t%s\n' "$tag" "$count" "$mark"
done <<< "$sorted"

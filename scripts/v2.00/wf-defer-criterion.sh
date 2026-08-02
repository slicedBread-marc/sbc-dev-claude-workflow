#!/usr/bin/env bash
# wf-defer-criterion.sh — the producer for plans/deferred-criteria.md.
#
#   wf-defer-criterion.sh <plan-id> <tag> "<criterion>" [--prereq <text>] [--note <text>]
#   wf-defer-criterion.sh --list [prereq-filter]
#   wf-defer-criterion.sh --consume <DC-NNN> <plan-id>
#
# An (external) or (soak) criterion cannot be satisfied at gate time by anyone
# — not the agent, not the human standing next to it. Blocking a plan on one
# buys nothing and costs a stop, so the plan completes and the criterion
# travels here, to be picked up by whichever future plan touches that surface.
#
# `wf-spec` step 1a has read this file since schema v5. wf-test could write it,
# but only by hand and only down one narrow path — the user had to say the
# prerequisite feature was not built yet. Across 16 plans of a real program the
# file never came into existence. This makes the write mechanical and gives the
# two commoner reasons (external, soak) a way in.
#
# Tags:
#   external   needs a real third-party system, credentials, or a physical act
#   soak       needs real elapsed calendar time
#   unbuilt    the prerequisite feature does not exist yet (the wf-test path)
#
# eyes:* never defers — a subjective check either blocks the merge or files a
# cosmetic bug. See wf-test.
#
# Prereq defaults: `first-real-use` (external), `next-cycle` (soak), `—`
# (unbuilt). It may also be a plan ID (`PLN-041`) or a date (`2026-09-01`).
#
# Exit 0 on success, 1 on error.

set -euo pipefail

# shellcheck source=wf-orch-lib.sh
source "$(dirname "$0")/wf-orch-lib.sh"
# shellcheck source=wf-lock.sh
source "$(dirname "$0")/wf-lock.sh"

ROOT="$(wf_develop_root)"
FILE="$ROOT/plans/deferred-criteria.md"

ensure_file() {
  [ -f "$FILE" ] && return 0
  mkdir -p "$(dirname "$FILE")"
  cat > "$FILE" << 'HEADER'
# Deferred Criteria

> Manual criteria that no gate could ever satisfy — they need a real external
> system, real credentials, a physical act, or real elapsed calendar time.
> Their plan shipped without them; they wait here for a plan that touches the
> same surface.
>
> Also holds criteria skipped because the prerequisite feature was not built
> yet (tag `unbuilt`).
>
> Written by `wf-defer-criterion.sh` (from `/wf-test`). Read by `/wf-spec`
> step 1a, which offers matching rows when a new plan is drafted.
> Do not hand-edit — use the script so IDs stay unique.

| ID | Criterion | Tag | From | Prereq | Note | Added | Status |
|-|-|-|-|-|-|-|-|
HEADER
}

# ── Modes ─────────────────────────────────────────────────────────────────

case "${1:-}" in
  --list)
    [ -f "$FILE" ] || exit 0
    filter="${2:-}"
    awk -F'|' -v want="$filter" '
      /^\| DC-/ {
        id = $2; crit = $3; tag = $4; from = $5; prereq = $6; note = $7; status = $9
        gsub(/^[ \t]+|[ \t]+$/, "", id);     gsub(/^[ \t]+|[ \t]+$/, "", crit)
        gsub(/^[ \t]+|[ \t]+$/, "", tag);    gsub(/^[ \t]+|[ \t]+$/, "", from)
        gsub(/^[ \t]+|[ \t]+$/, "", prereq); gsub(/^[ \t]+|[ \t]+$/, "", note)
        gsub(/^[ \t]+|[ \t]+$/, "", status)
        if (status != "open") next
        if (want != "" && prereq != want) next
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", id, crit, tag, from, prereq, note
      }
    ' "$FILE"
    exit 0
    ;;
  --consume)
    dc="${2:?--consume requires a DC-NNN}"
    into="${3:?--consume requires the consuming plan id}"
    [ -f "$FILE" ] || { echo "Error: $FILE not found" >&2; exit 1; }
    wf_lock_acquire deferred-criteria
    awk -F'|' -v dc="$dc" -v into="$into" 'BEGIN { OFS="|" }
      {
        id = $2; gsub(/^[ \t]+|[ \t]+$/, "", id)
        if ($0 ~ /^\| DC-/ && id == dc) { $9 = " consumed by " into " " }
        print
      }
    ' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"
    echo "Deferred criterion $dc → consumed by $into"
    exit 0
    ;;
esac

# ── Add ───────────────────────────────────────────────────────────────────

raw_id="${1:-}"
tag="${2:-}"
criterion="${3:-}"
shift 3 2>/dev/null || true

prereq=""
note=""
while [ $# -gt 0 ]; do
  case "$1" in
    --prereq) prereq="${2:?--prereq requires a value}"; shift 2 ;;
    --note)   note="${2:?--note requires a value}"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

plan_id=$(printf '%s' "$raw_id" | grep -oE 'PLN-[0-9]+' || true)
if [ -z "$plan_id" ] || [ -z "$criterion" ]; then
  echo "Usage: $0 <plan-id> <external|soak|unbuilt> \"<criterion>\" [--prereq <text>] [--note <text>]" >&2
  exit 1
fi

case "$tag" in
  external) [ -n "$prereq" ] || prereq="first-real-use" ;;
  soak)     [ -n "$prereq" ] || prereq="next-cycle" ;;
  unbuilt)  [ -n "$prereq" ] || prereq="—" ;;
  *) echo "Error: tag must be 'external', 'soak' or 'unbuilt' (got '$tag') — eyes:* criteria never defer" >&2; exit 1 ;;
esac

# Pipes would break the table; both fields are free text from a plan or a user.
criterion=$(printf '%s' "$criterion" | tr '|' '/' | tr -d '\n')
note=$(printf '%s' "$note" | tr '|' '/' | tr -d '\n')
[ -n "$note" ] || note="—"

wf_lock_acquire deferred-criteria
ensure_file

# Next DC id. `10#` forces base 10 — a zero-padded "008" is not octal here.
last=$(grep -oE '^\| DC-[0-9]+' "$FILE" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1 || true)
next=$(printf 'DC-%03d' "$(( 10#${last:-0} + 1 ))")

printf '| %s | %s | %s | %s | %s | %s | %s | open |\n' \
  "$next" "$criterion" "$tag" "$plan_id" "$prereq" "$note" "$(date +%Y-%m-%d)" >> "$FILE"

echo "Deferred: $next ($tag, prereq $prereq) from $plan_id"

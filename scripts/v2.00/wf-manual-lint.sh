#!/usr/bin/env bash
# wf-manual-lint.sh <plan-id-or-name> [--counts] [--file <plan.md>]
#
# Lints the `#### Manual` criteria in a plan's Verification Checklist.
#
# Every manual criterion must declare WHY a machine cannot check it, using
# exactly one tag, written first on the line:
#
#   #### Manual
#   - [ ] (eyes:blocking)  /app/time — the timer is usable one-handed on a phone
#   - [ ] (eyes:cosmetic)  /app/board — column spacing is even at 1280px
#   - [ ] (external)       trx ticket pull <id> — every image appears in the DevOps UI
#   - [ ] (soak)           trx work — the Stalled section surfaces something forgotten
#   - [ ] (unbuilt)        the export button — the screen it lives on ships in PLN-112
#
#   eyes:blocking  subjective judgment; failing it blocks the merge
#   eyes:cosmetic  subjective judgment; failing it files a bug and ships
#   external       needs a real third-party system, real credentials, or a physical act
#   soak           needs real elapsed calendar time
#   unbuilt        the prerequisite feature does not exist yet (the wf-test
#                  deferral path — see wf-defer-criterion.sh)
#
# Anything that fits none of the five is misclassified and belongs in the Tests
# table. `#### Manual` used to have no cost and no schema — writing a criterion
# there was strictly easier than writing a real test, so planners drifted into
# it under time pressure and shipped assertions (including security assertions)
# as one-shot human checks. Guidance lost to gradient; this makes it a gate.
#
# Modes:
#   (default)  print one finding per line, tab-separated:
#                <line-no> <TAB> <code> <TAB> <criterion> <TAB> <message>
#              exit 1 if any findings, 0 if clean.
#   --counts   print eval-safe KEY='value' lines and exit 0:
#                MANUAL_TOTAL, MANUAL_EYES_BLOCKING, MANUAL_EYES_COSMETIC,
#                MANUAL_EXTERNAL, MANUAL_SOAK, MANUAL_UNBUILT, MANUAL_UNTAGGED,
#                MANUAL_OPEN_EYES  (unchecked eyes:* criteria — what gates)
#
# Codes: untagged | unknown-tag | assertable

set -euo pipefail

# shellcheck source=wf-orch-lib.sh
source "$(dirname "$0")/wf-orch-lib.sh"

raw_id=""
mode="lint"
plan_file=""

while [ $# -gt 0 ]; do
  case "$1" in
    --counts) mode="counts"; shift ;;
    --file)   plan_file="${2:?--file requires a path}"; shift 2 ;;
    -*)       echo "Unknown option: $1" >&2; exit 2 ;;
    *)        raw_id="$1"; shift ;;
  esac
done

if [ -z "$plan_file" ]; then
  plan_id=$(printf '%s' "$raw_id" | grep -oE 'PLN-[0-9]+' || true)
  [ -n "$plan_id" ] || { echo "Usage: $0 <plan-id-or-name> [--counts] [--file <plan.md>]" >&2; exit 2; }

  ROOT="$(wf_develop_root)"
  REGISTRY="$ROOT/plans/REGISTRY.md"
  [ -f "$REGISTRY" ] || { echo "Error: $REGISTRY not found" >&2; exit 2; }
  row=$(grep "^| $plan_id |" "$REGISTRY" | head -1 || true)
  [ -n "$row" ] || { echo "Error: $plan_id not found in registry" >&2; exit 2; }
  slug=$(printf '%s' "$row" | awk -F'|' '{print $3}' | xargs)
  plan_file="$ROOT/plans/${plan_id}-${slug}/plan.md"
fi

[ -f "$plan_file" ] || { echo "Error: $plan_file not found" >&2; exit 2; }

# ── Schema guard ──────────────────────────────────────────────────────────
# Tags arrived in schema v6. A v5 plan already in flight has none, and failing
# it back to `draft` mid-pipeline would punish plans for being early rather
# than for being wrong. So: v5 plans are never linted, and for counting they
# fall back to v5 semantics — every unchecked manual criterion is treated as
# eyes:blocking, which is exactly what "any Manual criterion gates" meant.
schema=$(grep -m1 -oE 'schema_version:\*{0,2}[[:space:]]*[0-9]+' "$plan_file" 2>/dev/null | grep -oE '[0-9]+$' || echo 0)
legacy=0
[ "${schema:-0}" -lt 6 ] && legacy=1

if [ "$mode" = "lint" ] && [ "$legacy" = "1" ]; then
  echo "wf-manual-lint: $(basename "$(dirname "$plan_file")") is schema_version ${schema:-unset} (< 6) — manual criterion tags not required, skipping" >&2
  exit 0
fi

# ── Parse ─────────────────────────────────────────────────────────────────
# Records are emitted prefixed F (finding) or C (count) and split below, so
# both modes share one parser and can never disagree about the same plan.
out=$(awk -v legacy="$legacy" '
  BEGIN {
    # Patterns are lowercase and applied to tolower(text): IGNORECASE is a GNU
    # awk extension and this has to run on the BSD awk macOS ships.
    # Verbs whose outcome a machine can decide. Deliberately narrow — a false
    # positive here costs a planner an edit, so it must earn its place.
    assertable = "(is refused|is rejected|refuses|is accepted|returns|responds with|contains|exists|is present|is absent|is empty|stops for|blocks on|prints|logs|matches|resolves|redirects|exits|parses|equals|no ansi|status code)"
    # Words that mark a genuine judgment call. Their presence vetoes the
    # assertable heuristic — "reads clearly and contains all five columns" is
    # a human question wearing an assertable verb.
    subjective = "(reads|feels|looks|legible|readable|natural|usable|ergonom|smooth|polish|at a glance|intuitive|clutter|aesthetic|pleasant|comfortable|obvious|confusing)"
  }
  /^####[[:space:]]*Manual/ { in_manual = 1; next }
  /^(#|##|###|####)[[:space:]]/ { if (in_manual && $0 !~ /^####[[:space:]]*Manual/) in_manual = 0 }
  !in_manual { next }
  /^[[:space:]]*-[[:space:]]*\[[ xX]\]/ {
    total++
    line = $0
    checked = (line ~ /\[[xX]\]/)

    body = line
    sub(/^[[:space:]]*-[[:space:]]*\[[ xX]\][[:space:]]*/, "", body)

    tag = ""
    if (body ~ /^\(/) {
      tag = body
      sub(/^\(/, "", tag)
      sub(/\).*$/, "", tag)
      gsub(/[[:space:]]/, "", tag)
      text = body
      sub(/^\([^)]*\)[[:space:]]*/, "", text)
    } else {
      text = body
    }
    lower_tag = tolower(tag)

    if (tag == "") {
      # Pre-v6 plan: no tags were ever required, so read it the v5 way.
      if (legacy) { eyes_blocking++; if (!checked) { open_eyes++; open_blocking++ } ; next }
      printf "F\t%d\tuntagged\t%s\t%s\n", NR, text, "no reason tag — add (eyes:blocking), (eyes:cosmetic), (external), (soak) or (unbuilt), or move it to the Tests table"
      untagged++
      next
    }

    if (lower_tag == "eyes:blocking")      { eyes_blocking++; if (!checked) { open_eyes++; open_blocking++ } }
    else if (lower_tag == "eyes:cosmetic") { eyes_cosmetic++; if (!checked) { open_eyes++; open_cosmetic++ } }
    else if (lower_tag == "external")      { external++ }
    else if (lower_tag == "soak")          { soak++ }
    # Written by wf-defer-criterion.sh when the prerequisite feature does not
    # exist yet. Deferring the documented way has to produce a plan that lints.
    else if (lower_tag == "unbuilt")       { unbuilt++ }
    else {
      untagged++
      msg = "unknown tag (" tag ")"
      if (lower_tag == "eyes") msg = msg " — pick a disposition: eyes:blocking or eyes:cosmetic"
      else msg = msg " — legal tags: eyes:blocking, eyes:cosmetic, external, soak, unbuilt"
      printf "F\t%d\tunknown-tag\t%s\t%s\n", NR, text, msg
      next
    }

    # Verb heuristic. Only eyes:* is graded — an (external) or (soak) criterion
    # may legitimately read as assertable and still be unrunnable at gate time.
    ltext = tolower(text)
    if (lower_tag ~ /^eyes:/ && ltext ~ assertable && ltext !~ subjective) {
      printf "F\t%d\tassertable\t%s\t%s\n", NR, text, "mechanically assertable — belongs in the Tests table, not behind a human gate"
    }
  }
  END {
    printf "C\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n", \
      total + 0, eyes_blocking + 0, eyes_cosmetic + 0, external + 0, soak + 0, untagged + 0, \
      open_eyes + 0, open_blocking + 0, open_cosmetic + 0, unbuilt + 0
  }
' "$plan_file")

counts=$(printf '%s\n' "$out" | grep '^C	' | tail -1)
findings=$(printf '%s\n' "$out" | grep '^F	' || true)

if [ "$mode" = "counts" ]; then
  wf_emit MANUAL_TOTAL         "$(printf '%s' "$counts" | cut -f2)"
  wf_emit MANUAL_EYES_BLOCKING "$(printf '%s' "$counts" | cut -f3)"
  wf_emit MANUAL_EYES_COSMETIC "$(printf '%s' "$counts" | cut -f4)"
  wf_emit MANUAL_EXTERNAL      "$(printf '%s' "$counts" | cut -f5)"
  wf_emit MANUAL_SOAK          "$(printf '%s' "$counts" | cut -f6)"
  wf_emit MANUAL_UNBUILT       "$(printf '%s' "$counts" | cut -f11)"
  wf_emit MANUAL_UNTAGGED      "$(printf '%s' "$counts" | cut -f7)"
  wf_emit MANUAL_OPEN_EYES     "$(printf '%s' "$counts" | cut -f8)"
  wf_emit MANUAL_OPEN_BLOCKING "$(printf '%s' "$counts" | cut -f9)"
  wf_emit MANUAL_OPEN_COSMETIC "$(printf '%s' "$counts" | cut -f10)"
  wf_emit MANUAL_SCHEMA        "${schema:-0}"
  exit 0
fi

[ -n "$findings" ] || exit 0
printf '%s\n' "$findings" | cut -f2-
exit 1

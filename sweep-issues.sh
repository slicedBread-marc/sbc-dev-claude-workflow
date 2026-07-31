#!/usr/bin/env bash
# sweep-issues.sh — collect workflow-harness problems reported by every client.
#
# Clients file process bugs into their own WORKFLOW-ISSUES.md as they hit them
# (scripts/wf-exec.sh wf-issue.sh). This walks deployments.txt, gathers the open
# ones, and prints them grouped by project so they can be fixed HERE — in the
# library — rather than worked around individually in each client.
#
#   ./sweep-issues.sh              open issues, grouped by client
#   ./sweep-issues.sh --all        include already-resolved entries
#   ./sweep-issues.sh --count      one "<client>: <n>" line per project
#   ./sweep-issues.sh --resolve WFI-003 --client sbc "fixed in v2.6.0"
#
# Exit 0 if any open issues were found, 1 if every client is clean — so
# `./sweep-issues.sh >/dev/null && echo "work to do"` reads correctly.

set -uo pipefail

LIB_ROOT="$(cd "$(dirname "$0")" && pwd)"
# WF_DEPLOYMENTS points at an alternate client list — used by the test suite so
# it never has to touch the real deployments.txt.
DEPLOYMENTS="${WF_DEPLOYMENTS:-$LIB_ROOT/deployments.txt}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
[ -t 1 ] || { GREEN=''; YELLOW=''; BOLD=''; DIM=''; NC=''; }

[ -f "$DEPLOYMENTS" ] || { echo "sweep-issues.sh: no deployments.txt" >&2; exit 1; }

mode="list"
show_all=false
resolve_id=""
resolve_client=""
resolve_note="resolved"

while [ $# -gt 0 ]; do
  case "$1" in
    --all)     show_all=true; shift ;;
    --count)   mode="count"; shift ;;
    --resolve) mode="resolve"; resolve_id="${2:?--resolve requires WFI-NNN}"; shift 2 ;;
    --client)  resolve_client="${2:?--client requires a name}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         resolve_note="$1"; shift ;;
  esac
done

total=0
clients=0

while IFS= read -r client; do
  [ -n "$client" ] || continue
  case "$client" in \#*) continue ;; esac
  [ -d "$client" ] || { echo -e "${YELLOW}  skip: $client (not found)${NC}" >&2; continue; }

  name=$(basename "$client")
  issues="$client/WORKFLOW-ISSUES.md"
  clients=$((clients + 1))

  # grep -c prints 0 AND exits 1 with no matches, so `|| echo 0` would make n
  # the two-line string "0\n0" and break the arithmetic below.
  n=0
  if [ -f "$issues" ]; then
    n=$(grep -c '^\*\*Status:\*\* *open' "$issues" 2>/dev/null)
    n=${n:-0}
  fi

  case "$mode" in
    count)
      printf '%s: %s\n' "$name" "$n"
      ;;

    resolve)
      if [ -n "$resolve_client" ] && [ "$resolve_client" != "$name" ]; then continue; fi
      [ -f "$issues" ] || continue
      grep -q "^## $resolve_id " "$issues" 2>/dev/null || continue
      # Resolve through the client's own script so the format stays owned by
      # one place, and the client's version of it is the one that runs.
      ( cd "$client" && ./scripts/wf-exec.sh wf-issue.sh --resolve "$resolve_id" "$resolve_note" ) \
        && echo -e "${GREEN}  $name: $resolve_id resolved${NC}"
      ;;

    list)
      if $show_all; then
        body=$([ -f "$issues" ] && awk -v RS='\n## ' 'NR > 1 { print "## " $0 }' "$issues" || true)
      else
        body=$([ -f "$issues" ] && awk -v RS='\n## ' 'NR > 1 && /\*\*Status:\*\* *open/ { print "## " $0 }' "$issues" || true)
      fi
      if [ -n "$body" ]; then
        echo -e "\n${BOLD}══ $name ${NC}${DIM}($client)${NC}"
        printf '%s\n' "$body"
      fi
      ;;
  esac

  total=$((total + n))
done < "$DEPLOYMENTS"

if [ "$mode" = "list" ]; then
  echo
  if [ "$total" -gt 0 ]; then
    echo -e "${YELLOW}${total} open workflow issue(s) across ${clients} client(s).${NC}"
    echo "Fix them in this library, then:"
    echo "  ./deploy-all.sh"
    echo "  ./sweep-issues.sh --resolve WFI-NNN --client <name> \"fixed in vX.Y.Z\""
  else
    echo -e "${GREEN}No open workflow issues across ${clients} client(s).${NC}"
  fi
fi

[ "$total" -gt 0 ]

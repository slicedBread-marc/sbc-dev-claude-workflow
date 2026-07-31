#!/usr/bin/env bash
# wf-orch-lib.sh — shared helpers for the orchestrator. Source it; don't run it.
#
#   source "$(dirname "$0")/wf-orch-lib.sh"
#
# Everything orchestrator-related is anchored to the DEVELOP ROOT, never to the
# current worktree. A worker running in feature/PLN-097-foo must open a gate
# that /wf-attend on develop can see, so gates, events and pidfiles all live
# under <develop-root>/.claude/orchestrator/.
#
# Provides:
#   wf_develop_root                  → absolute path of the first worktree
#   wf_orch_dir                      → <develop-root>/.claude/orchestrator (created)
#   wf_cfg <dotted.path> [default]   → value from claude-workflow.yml
#   wf_emit <KEY> <value>            → eval-safe KEY='value' line
#   wf_event <type> <artifact> <msg> → append to events.log
#   wf_now                           → ISO-8601 UTC timestamp

# ── Paths ─────────────────────────────────────────────────────────────────

wf_develop_root() {
  # The first worktree git reports is always the main one (where develop lives).
  local root
  root=$(git worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //')
  if [ -n "$root" ]; then printf '%s' "$root"; return 0; fi
  # Not a worktree setup — fall back to the repo toplevel, then CWD.
  root=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$root" ] && { printf '%s' "$root"; return 0; }
  printf '%s' "$PWD"
}

wf_orch_dir() {
  local d="$(wf_develop_root)/.claude/orchestrator"
  mkdir -p "$d/gates" "$d/logs"
  printf '%s' "$d"
}

wf_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ── Config ────────────────────────────────────────────────────────────────

# wf_cfg <dotted.path> [default]
# Reads a scalar from claude-workflow.yml. Deliberately does NOT require yq —
# the orchestrator must run on a bare client checkout. Handles the nested
# 2-space-indented scalar shape this config uses; not a general YAML parser.
wf_cfg() {
  local path="$1" default="${2:-}" cfg val
  cfg="$(wf_develop_root)/claude-workflow.yml"
  if [ ! -f "$cfg" ]; then printf '%s' "$default"; return 0; fi

  val=$(awk -v path="$path" '
    BEGIN { n = split(path, want, "."); level = 0 }
    {
      line = $0; sub(/\r$/, "", line)
      probe = line; sub(/^[ ]*/, "", probe)
      if (probe ~ /^#/ || probe == "") next
      match(line, /^[ ]*/); indent = RLENGTH / 2
      if (indent > level) next          # inside a subtree we did not match
      if (indent < level) level = indent # popped back out
      key = probe; sub(/:.*/, "", key); gsub(/[ \t]/, "", key)
      if (key != want[level + 1]) next
      if (level == n - 1) {
        rest = probe; sub(/^[^:]*:[ \t]*/, "", rest)
        sub(/[ \t]+#.*$/, "", rest)                 # trailing comment
        gsub(/^[ \t]+|[ \t]+$/, "", rest)
        gsub(/^"|"$/, "", rest); gsub(/^'"'"'|'"'"'$/, "", rest)
        print rest; exit
      }
      level++
    }
  ' "$cfg")

  if [ -z "$val" ]; then printf '%s' "$default"; else printf '%s' "$val"; fi
}

# ── Output ────────────────────────────────────────────────────────────────

# Single-quoted so `eval` survives spaces, semicolons, backticks — the same
# contract wf-plan-info.sh uses (and the reason BUG-094 existed).
wf_emit() {
  printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")"
}

# ── Events ────────────────────────────────────────────────────────────────

# wf_event <type> <artifact> <message>
# One tab-separated line per event. Appended with a single write so concurrent
# workers interleave cleanly (well under PIPE_BUF).
wf_event() {
  local type="$1" artifact="$2" msg="${3:-}"
  local log="$(wf_orch_dir)/events.log"
  printf '%s\t%s\t%s\t%s\n' "$(wf_now)" "$type" "$artifact" "$msg" >> "$log"
}

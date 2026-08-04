#!/usr/bin/env bash
# wf-worktree-sparse.sh <worktree-path>
#
# Configures sparse-checkout on a feature worktree so that develop-owned files
# are excluded from git tracking there. Tracking them on a feature branch means
# a merge conflict — or a dirty tree — every time develop advances.
#
# ── The rule that governs this list ──────────────────────────────────────────
#
# A sparse-checkout exclusion holds ONLY while the file is absent from the
# working tree, or byte-identical to the branch's committed blob. The moment
# anything writes DIFFERENT content to that path, git drops the skip-worktree
# bit on the next index refresh, the file shows as modified, and
# `git sparse-checkout reapply` refuses to re-exclude it ("not up to date and
# were left despite sparse patterns"). From there `git merge develop` does not
# merely conflict — it ABORTS with "your local changes would be overwritten".
#
# So a path may be excluded here only if NOTHING materialises it in the
# worktree. install.sh's propagation step materialises the runtime files a
# session needs on disk, and the previous version of this list excluded exactly
# those — which is why a deploy that changed four skills mid-flight left one
# client's worktree with 33 modified files it never touched and a merge that
# would not run. Excluding a file you also write is not a stricter policy than
# tracking it; it is a broken one.
#
# Excluded — develop-owned, never materialised in a worktree:
#   plans/                    registry + plan content (the original reason:
#                             plan content on feature branches caused duplicate
#                             plans and conflicting registry states)
#   templates/                plan templates
#   .claude/workflow-version  the plan's immovable WF pin, not develop's stamp
#   scripts/version-map.txt   resolved from the MAIN worktree by wf-exec.sh
#   scripts/v*/wf-*.sh        ditto — wf-exec.sh's find_project_root answers
#                             with the main worktree, so a worktree copy of a
#                             versioned script is never the one that runs
#   scripts/wf-prune-versions.sh
#
# Tracked normally — materialised by install.sh, so they cannot be excluded:
#   .claude/workflow.md, .claude/skills/**, scripts/wf-exec.sh
#
# Those three are reconciled by committing develop's content on the feature
# branch (wf-infra-sync.sh). The commit is a no-op on merge-back — both sides
# hold the same bytes.

set -euo pipefail

WT_PATH="${1:?Usage: wf-worktree-sparse.sh <worktree-path>}"

cd "$WT_PATH"

# Get the worktree-specific git admin dir (e.g. .git/worktrees/PLN-NNN-slug)
# and the SHARED admin dir, which is where repo-wide config and the main
# worktree's own info/ live.
#
# --show-toplevel would be wrong here: git gives every linked worktree its own
# toplevel, so from inside a feature worktree it returns that worktree, not the
# main repo. Everything below then targets the worktree's `.git` — which is a
# regular file (a gitdir pointer), not a directory — and `mkdir -p .git/info`
# dies with "Not a directory" before sparse-checkout is ever configured.
# --git-common-dir is the one that stays pointed at the main repo from anywhere.
GIT_DIR=$(cd "$(git rev-parse --git-dir)" && pwd)
COMMON_DIR=$(cd "$(git rev-parse --git-common-dir)" && pwd)
REPO_ROOT=$(dirname "$COMMON_DIR")

# Enable sparse checkout in the shared repo config.
# This is a repo-wide flag, so we must also protect the main worktree
# (develop) by ensuring its sparse-checkout file includes everything.
git -C "$REPO_ROOT" config core.sparseCheckout true

# Protect the main worktree: ensure develop's sparse-checkout file is a
# catch-all so the global flag doesn't accidentally exclude files there.
main_sparse="$COMMON_DIR/info/sparse-checkout"
if [ ! -f "$main_sparse" ] || grep -q '^!' "$main_sparse"; then
  mkdir -p "$COMMON_DIR/info"
  echo '/**' > "$main_sparse"
fi

# Write patterns directly to the worktree-specific sparse-checkout file.
# `git sparse-checkout set` behaves inconsistently in linked worktrees on
# git 2.25-2.39 — writing the file directly is reliable across versions.
mkdir -p "$GIT_DIR/info"
cat > "$GIT_DIR/info/sparse-checkout" <<'PATTERNS'
/**
!.claude/workflow-version
!plans/**
!templates/**
!scripts/version-map.txt
!scripts/wf-prune-versions.sh
!scripts/v*/wf-*.sh
PATTERNS

# ── Repair: converge a worktree configured by an older pattern list ──────────
#
# Runs on every invocation, including the first, where it finds nothing to do.

# (a) Paths that USED to be excluded and are now tracked normally. A lingering
#     skip-worktree bit would keep git blind to them; clearing it alone leaves
#     them staged-as-deleted, because the old exclusion is what removed them
#     from disk. Restore the branch's copies after clearing.
INCLUDED_INFRA=(.claude/workflow.md .claude/skills scripts/wf-exec.sh)
stale_bits=$(git ls-files -v -- "${INCLUDED_INFRA[@]}" 2>/dev/null \
             | awk '$1 == "S" { sub(/^S[[:space:]]+/, ""); print }' || true)
if [ -n "$stale_bits" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    git update-index --no-skip-worktree -- "$f" 2>/dev/null || true
  done <<< "$stale_bits"
  git checkout -- "${INCLUDED_INFRA[@]}" 2>/dev/null || true
  echo "Repaired $(printf '%s\n' "$stale_bits" | grep -c .) formerly-excluded infra path(s)"
fi

# (b) Deploy copies of now-excluded paths, left on disk by an older install.sh.
#     While they sit there the exclusion cannot re-apply.
#
#     The only content such a file can hold is SOME released version of a
#     develop-owned script — a client never edits these, and the next deploy
#     would overwrite an edit anyway. So: drop it if it matches develop's
#     current copy, otherwise restore the branch's committed copy and let
#     reapply take it off disk. Either way nothing unrecoverable is lost, and
#     the alternative is the dirty tree that blocks `git merge develop`.
DEVELOP_OWNED=('scripts/version-map.txt' 'scripts/wf-prune-versions.sh' 'scripts/v*/wf-*.sh')
removed=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || continue
  if [ -f "$REPO_ROOT/$f" ] && cmp -s "$f" "$REPO_ROOT/$f"; then
    rm -f "$f"
    removed=$((removed + 1))
  else
    git checkout -- "$f" 2>/dev/null || true
  fi
done < <(git ls-files -- "${DEVELOP_OWNED[@]}" 2>/dev/null || true)

#     Untracked leftovers: scripts added by a release AFTER this branch was
#     cut were never in its index, so `git ls-files` above cannot see them and
#     they sit in `git status` as `??` — where a `git add -A` would commit
#     develop's tooling as plan work. Remove them where develop owns the same
#     path, which is what makes them a deploy artifact rather than plan work.
#     The glob widens to the legacy FLAT layout here (`scripts/wf-*.sh`, where
#     older clients keep their scripts) because an untracked copy of one is a
#     deploy artifact by definition. It cannot widen in the tracked sweep
#     above: scripts/wf-exec.sh lives under the same glob and must stay.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ "$f" = "scripts/wf-exec.sh" ] && continue
  [ -f "$f" ] || continue
  [ -f "$REPO_ROOT/$f" ] || continue
  rm -f "$f"
  removed=$((removed + 1))
done < <(git ls-files --others --exclude-standard -- "${DEVELOP_OWNED[@]}" 'scripts/wf-*.sh' 2>/dev/null || true)

[ "$removed" -gt 0 ] && echo "Removed $removed stale deploy copy(s) of develop-owned scripts"

# Apply the patterns. This sets the skip-worktree bit on excluded files so git
# won't modify them in the working tree or show them in git status.
git sparse-checkout reapply 2>/dev/null || true

echo "Sparse checkout configured — develop-owned files excluded from tracking"

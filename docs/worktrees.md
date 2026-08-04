# Feature worktrees — what is in one, and why

A plan is built in a linked git worktree at `feature-branches/PLN-NNN-<slug>/`
on branch `feature/PLN-NNN-<slug>`. Everything the workflow owns lives on
`develop`; the worktree carries the plan's code changes and nothing else.

Two mechanisms keep it that way, and they are **mutually exclusive per path**.
Getting that wrong is what produced git-tracker WFI-021: 33 files an implementer
never touched showing as modified, and a `git merge develop` that aborted.

## The rule

> A sparse-checkout exclusion holds only while the path is **absent** from the
> working tree, or **byte-identical** to the branch's committed blob.

Write different content to an excluded path and git drops its `skip-worktree`
bit on the next index refresh. The file shows as modified,
`git sparse-checkout reapply` refuses to re-exclude it ("not up to date and were
left despite sparse patterns"), and `git merge develop` fails with *your local
changes would be overwritten* before it reaches a real conflict.

So a path may be excluded **only if nothing materialises it**.

## Excluded — develop-owned, never written into a worktree

Configured by `wf-worktree-sparse.sh`:

| Path | Resolved instead from |
|-|-|
| `plans/**` | the develop worktree (the registry has one writer) |
| `templates/**` | develop |
| `.claude/workflow-version` | the plan's `WF` column, then develop's stamp |
| `scripts/version-map.txt` | the main worktree |
| `scripts/v*/wf-*.sh` | the main worktree |
| `scripts/wf-prune-versions.sh` | the main worktree |

`wf-exec.sh`'s `find_project_root` answers with the **main** worktree, so a
worktree copy of a versioned script is never the one that runs. Copying them in
bought nothing and cost the exclusion.

## Tracked normally — a session reads these off its own disk

`.claude/workflow.md`, `.claude/skills/**`, `scripts/wf-exec.sh`.

Claude Code loads skills from the tree it is running in, and skills invoke
`scripts/wf-exec.sh` by relative path. These must physically exist, so they
cannot be excluded. `install.sh` overwrites them on every deploy, which leaves
the worktree dirty against its own branch; `wf-infra-sync.sh` reconciles that by
committing develop's bytes onto the feature branch. The commit is a no-op on
merge-back — both sides hold identical content.

That sync is **pathspec-scoped** (`git commit -- <paths>`), never a bare commit:
it runs from `install.sh`, which can fire while a worker has unrelated work
staged in the same worktree.

## Adding a path

Decide which list it belongs to *before* adding it, and put it in exactly one:

- Does any process write it into a worktree? → tracked normally, and add it to
  `INFRA` in `wf-infra-sync.sh`.
- Otherwise → add it to the pattern list in `wf-worktree-sparse.sh`.

A path in both lists is the WFI-021 defect, rewritten.

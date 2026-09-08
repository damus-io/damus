---
name: ff-worktrees
description: Fast-forward master and every git worktree branch up to a target ref (default github/master), skipping any worktree with unmerged commits. Use when the user wants to sync/update their worktree branches to latest master — e.g. "/ff-worktrees", "ff all worktrees to github/master", "fast-forward the worktrees".
---

# ff-worktrees

Fast-forwards `master` and every branch checked out in a git worktree up to a
target ref. Only true fast-forwards are applied: a branch is advanced solely
when it is already an ancestor of the target. Worktree branches carrying their
own unmerged commits are left untouched and reported as skipped, so no work is
ever clobbered.

## Running it

```bash
devtools/ff-worktrees.sh [target]
```

- `target` — ref to fast-forward toward. Defaults to `github/master` — this
  repo's remote is named `github`, not `origin`. When it looks like
  `<remote>/<branch>` and `<remote>` is configured, the remote is fetched
  first.

Examples:

```bash
devtools/ff-worktrees.sh                 # ff everything to github/master
devtools/ff-worktrees.sh monad/master    # ff everything to monad/master
```

## Behavior

- Fetches the target's remote first (when the target is `<remote>/<branch>`).
- Fast-forwards each branch in place inside its worktree via `merge --ff-only`;
  untracked files and non-conflicting local edits survive.
- A branch not checked out in any worktree (e.g. `master` when it's idle) has
  its ref moved directly, still guarded by an ancestry (fast-forward) check.
- Reports a one-line summary per branch: `+` advanced, `=` already up to date,
  `~` skipped for unmerged commits, `!` skipped because a dirty worktree blocks
  the fast-forward.

Safe to run from any worktree — it never resets a branch or discards commits.

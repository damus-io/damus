#!/usr/bin/env bash
#
# Fast-forward master and every worktree branch up to a target ref.
#
# For each branch (master plus every branch checked out in a worktree) the
# script fast-forwards it to the target *only when it is a true fast-forward* —
# i.e. the branch is already an ancestor of the target. Branches with commits of
# their own that haven't been merged into the target yet are left untouched and
# reported as skipped, so unmerged work is never clobbered.
#
# Usage:
#   devtools/ff-worktrees.sh [target]
#
#   target   ref to fast-forward toward (default: github/master).
#            When it looks like <remote>/<branch> the remote is fetched first.
#
# Examples:
#   devtools/ff-worktrees.sh                 # ff everything to github/master
#   devtools/ff-worktrees.sh monad/master    # ff everything to monad/master
#
# Safe to run from any worktree. It never resets a branch, never deletes work,
# and never touches uncommitted changes (untracked files and non-conflicting
# edits survive a fast-forward).

set -euo pipefail

TARGET="${1:-github/master}"

# --- fetch the remote if the target is a remote-tracking ref -----------------
# A target of the form <remote>/<branch> where <remote> is a configured remote
# gets a fetch first so we fast-forward toward the latest state.
if [[ "$TARGET" == */* ]]; then
    remote="${TARGET%%/*}"
    branch="${TARGET#*/}"
    if git remote | grep -qx "$remote"; then
        echo "fetching $remote $branch ..."
        git fetch "$remote" "$branch"
    fi
fi

target_sha=$(git rev-parse --verify "${TARGET}^{commit}" 2>/dev/null) || {
    echo "error: cannot resolve target ref '$TARGET'" >&2
    exit 1
}
echo "target $TARGET -> ${target_sha:0:12}"
echo

# --- map every checked-out branch to its worktree path -----------------------
# `git worktree list --porcelain` emits paired `worktree <path>` / `branch
# <ref>` lines; pull them together so we know where each branch lives.
declare -A wt_path
cur_path=""
while read -r key val; do
    case "$key" in
        worktree) cur_path="$val" ;;
        branch)   wt_path["${val#refs/heads/}"]="$cur_path" ;;
    esac
done < <(git worktree list --porcelain)

# Sync master even if it isn't checked out anywhere, then every worktree branch.
branches=(master)
for b in "${!wt_path[@]}"; do
    [ "$b" = master ] && continue
    branches+=("$b")
done

updated=0 uptodate=0 skipped=0

for branch in "${branches[@]}"; do
    if ! git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null; then
        continue
    fi

    branch_sha=$(git rev-parse "refs/heads/$branch")

    if [ "$branch_sha" = "$target_sha" ]; then
        printf '  = %-32s already up to date\n' "$branch"
        uptodate=$((uptodate + 1))
        continue
    fi

    # Only fast-forwards: the branch must already be an ancestor of the target.
    if ! git merge-base --is-ancestor "$branch_sha" "$target_sha"; then
        printf '  ~ %-32s skipped (unmerged commits)\n' "$branch"
        skipped=$((skipped + 1))
        continue
    fi

    path="${wt_path[$branch]:-}"
    if [ -n "$path" ]; then
        # Checked out: fast-forward in place inside its worktree. --ff-only
        # refuses anything but a fast-forward and leaves untracked files alone.
        if git -C "$path" merge --ff-only --quiet "$target_sha" 2>/dev/null; then
            printf '  + %-32s %s -> %s\n' "$branch" "${branch_sha:0:12}" "${target_sha:0:12}"
            updated=$((updated + 1))
        else
            printf '  ! %-32s skipped (dirty worktree blocks ff)\n' "$branch"
            skipped=$((skipped + 1))
        fi
    else
        # Not checked out anywhere: move the ref directly (ancestry proven above).
        git update-ref "refs/heads/$branch" "$target_sha" "$branch_sha"
        printf '  + %-32s %s -> %s\n' "$branch" "${branch_sha:0:12}" "${target_sha:0:12}"
        updated=$((updated + 1))
    fi
done

echo
echo "done: $updated fast-forwarded, $uptodate up to date, $skipped skipped"

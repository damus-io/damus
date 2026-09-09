#!/bin/sh
#
# Record which commit became which TestFlight build number, as a git tag.
#
# App Store Connect assigns the build number, and the only place the commit is
# written down is the Xcode Cloud run — which Apple prunes after a handful of
# runs. By the time anyone asks "what is in build 1338?" the answer is usually
# already gone. This is the one moment both halves are known, so it is the
# moment to write them down: an annotated `build/<number>` tag on the commit,
# pushed to the repository.
#
# NOTHING HERE MAY FAIL THE BUILD. This hook runs after the archive action and
# *before* Xcode Cloud uploads the archive, so a non-zero exit throws away a
# finished build. That is not hypothetical: the Sentry hook this file replaces
# did exactly that to every build for three months (296f3bddd4f8). So there is
# no `set -e`, every step tolerates failure, and the script always exits 0.
# A missing tag is a footnote; a discarded release build is a wasted evening.
#
# Pushing needs a credential the builder does not have by default. Set a
# GitHub token with contents:write as a *secret* environment variable named
# GITHUB_TAG_PUSH_TOKEN on the workflow (Xcode Cloud env vars are UI-only;
# there is no App Store Connect API for them). Until that exists the script
# still tries the checkout's own credentials and reports what happened, so the
# build log says whether a token is actually needed here.

set -u

say() { echo "build-tag: $*"; }

# Only the archive action produces a TestFlight build. This hook also runs
# after the test action, where there is no build number to speak of yet.
if [ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]; then
    exit 0
fi

# A pull request build is never distributed, so it has no number worth keeping.
if [ -n "${CI_PULL_REQUEST_NUMBER:-}" ]; then
    say "pull request build, nothing to tag"
    exit 0
fi

if [ -z "${CI_BUILD_NUMBER:-}" ] || [ -z "${CI_COMMIT:-}" ]; then
    say "no CI_BUILD_NUMBER or CI_COMMIT in the environment, skipping"
    exit 0
fi

repo="${CI_PRIMARY_REPOSITORY_PATH:-}"
if [ -z "$repo" ] || [ ! -d "$repo" ]; then
    say "no checkout at CI_PRIMARY_REPOSITORY_PATH, skipping"
    exit 0
fi
cd "$repo" || exit 0

tag="build/$CI_BUILD_NUMBER"

# Never let git stop for a credential prompt: there is no terminal here, and a
# hung hook holds the archive hostage until the run times out.
GIT_TERMINAL_PROMPT=0
export GIT_TERMINAL_PROMPT

# And never let it stall on the network either. http.lowSpeedTime only applies
# once bytes are moving, so it does nothing for a host that never answers at
# all — a blackholed address hangs in connect() for minutes, and this script
# must not delay the upload it runs in front of. git has no connect timeout and
# macOS has no timeout(1), so: a wall-clock watchdog.
impatient="-c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30"
timeout_seconds="${BUILD_TAG_TIMEOUT:-60}"

impatiently() {
    # `set -m` puts the job in its own process group, so the kill takes the
    # whole tree with it. Killing just the pid leaves git-remote-https orphaned
    # and still holding the build log's pipe open, which looks exactly like the
    # hang this is here to prevent.
    set -m
    "$@" &
    job=$!
    # The guard holds no stdio of its own: an inherited pipe kept open by a
    # stray `sleep` reads to the build log exactly like a hung command.
    (sleep "$timeout_seconds"; kill -9 -"$job" 2>/dev/null) \
        </dev/null >/dev/null 2>&1 &
    guard=$!
    wait "$job" 2>/dev/null
    status=$?
    # Kill the guard's whole group, or its `sleep` outlives the subshell, and
    # reap it in the same breath so the shell does not narrate the kill into
    # the build log.
    { kill -9 -"$guard"; wait "$guard"; } 2>/dev/null
    set +m
    return $status
}

subject=$(git log -1 --format=%s "$CI_COMMIT" 2>/dev/null)
message="TestFlight build $CI_BUILD_NUMBER

Archived by Xcode Cloud run $CI_BUILD_NUMBER (${CI_WORKFLOW:-unknown workflow}).

$subject"

if ! git -c user.name="Xcode Cloud" -c user.email="noreply@damus.io" \
        tag -a -f "$tag" "$CI_COMMIT" -m "$message" 2>&1; then
    say "could not create $tag locally, skipping"
    exit 0
fi
say "tagged $tag -> $CI_COMMIT"

# Xcode Cloud rewrites the checkout's origin to an `http://github.com/...` URL
# of its own. Pushing to that asks for a username no one can type, and — the
# subtle half — a credential stored for `https://github.com` does not match an
# `http://` remote, so the token below would be ignored and the push would fail
# anyway. Normalise to the canonical HTTPS URL, keeping whatever repository the
# origin names so a fork still pushes to itself.
remote=$(git remote get-url origin 2>/dev/null)
case "$remote" in
    http://github.com/*) remote="https://github.com/${remote#http://github.com/}" ;;
    git@github.com:*)    remote="https://github.com/${remote#git@github.com:}" ;;
    "")                  remote="https://github.com/damus-io/damus.git" ;;
    *) ;;  # already https, or some other host — leave it alone
esac

# Only used to key the credential file, and only for an https remote.
case "$remote" in
    https://*) host=${remote#https://}; host=${host%%/*} ;;
    *)         host="" ;;
esac

# The token goes in a credential file rather than in the URL or in an argument,
# so it stays out of the build log and out of the process list.
creds=""
config=""
if [ -n "${GITHUB_TAG_PUSH_TOKEN:-}" ] && [ -n "$host" ]; then
    creds=$(mktemp) || creds=""
fi
if [ -n "$creds" ]; then
    printf 'https://x-access-token:%s@%s\n' "$GITHUB_TAG_PUSH_TOKEN" "$host" > "$creds"
    config="credential.helper=store --file=$creds"
elif [ -n "${GITHUB_TAG_PUSH_TOKEN:-}" ]; then
    say "GITHUB_TAG_PUSH_TOKEN is set, but $remote is not an https remote it can"
    say "authenticate; trying the checkout's own credentials"
    config="credential.helper="
else
    say "no GITHUB_TAG_PUSH_TOKEN set; trying the checkout's own credentials"
    config="credential.helper="
fi

if impatiently git $impatient -c "$config" push "$remote" "refs/tags/$tag" 2>&1; then
    say "pushed $tag"
elif impatiently git $impatient -c "$config" ls-remote "$remote" \
        "refs/tags/$tag" "refs/tags/$tag^{}" 2>/dev/null \
        | grep -q "^$CI_COMMIT"; then
    # A rejected push whose tag is already on the remote, pointing where we
    # wanted it, is the job done by someone else — not a failure. Both ref
    # spellings are asked for because an annotated tag answers with the tag
    # object, and only the peeled `^{}` form gives back the commit.
    say "$tag is already on the remote"
else
    say "could not push $tag (or it timed out); it exists only on this builder."
    say "Run devtools/release/tag-builds.py --push github before this run ages"
    say "out of Apple's history, or set a GITHUB_TAG_PUSH_TOKEN secret on this"
    say "workflow to make it automatic."
fi

if [ -n "$creds" ]; then
    rm -f "$creds"
fi

exit 0

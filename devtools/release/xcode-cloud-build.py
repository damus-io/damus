#!/usr/bin/env python3
"""Start an Xcode Cloud build over the App Store Connect API, and watch it.

This is the fully remote path: the build runs on Apple's machines, so nothing
here depends on a Mac being awake, unlocked, or holding a distribution
certificate. All it needs is an App Store Connect API key.

  # see what workflows exist
  ./devtools/release/xcode-cloud-build.py --list

  # start the release candidate workflow on a branch and wait for it
  ./devtools/release/xcode-cloud-build.py "Release candidate build workflow" \
      --branch master --wait

  # print the request without sending it
  ./devtools/release/xcode-cloud-build.py "PR check" --branch master --dry-run

Waiting also records which commit became which build number, as a pushed
`build/<number>` git tag — Apple prunes the run that holds that mapping within
a few builds, so it is recorded by default rather than on request. `--no-tag`
opts out; `--tag` on a bare invocation opts into the wait it needs. The same
tag is written on the builder by ci_scripts/ci_post_xcodebuild.sh, which also
catches builds nobody started from here.

Credentials come from ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH; see asc_api.py.
"""

import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc_api  # noqa: E402
import build_index  # noqa: E402

# Terminal values of a build run's completionStatus.
DONE = {"SUCCEEDED", "FAILED", "ERRORED", "CANCELED", "SKIPPED"}


def list_workflows(bearer, product_id):
    body = asc_api.get(
        f"/v1/ciProducts/{product_id}/workflows?limit=200", bearer=bearer
    )
    return body.get("data", [])


def find_workflow(workflows, name):
    wanted = name.casefold()
    for workflow in workflows:
        if workflow.get("attributes", {}).get("name", "").casefold() == wanted:
            return workflow
    available = ", ".join(
        repr(w.get("attributes", {}).get("name")) for w in workflows
    ) or "none"
    raise asc_api.AscError(f"no workflow named {name!r}; available: {available}")


def find_git_reference(bearer, workflow_id, branch):
    """Resolve a branch name to the gitReference id Xcode Cloud knows it by.

    A build run without a sourceBranchOrTag uses whatever the workflow's start
    condition names, which for a release workflow is not necessarily the branch
    you meant. Passing it explicitly keeps "cut a build from master" honest.

    The repository is fetched through the workflow's related-resource endpoint
    rather than read off the relationship payload, because App Store Connect
    only populates relationship `data` for some requests.
    """
    repository = asc_api.get(
        f"/v1/ciWorkflows/{workflow_id}/repository", bearer=bearer
    ).get("data", {})
    repository_id = repository.get("id")
    if not repository_id:
        raise asc_api.AscError(
            "could not find the workflow's repository, so --branch cannot be "
            "resolved; re-run without --branch to use the workflow default"
        )

    path = f"/v1/scmRepositories/{repository_id}/gitReferences?limit=200"
    seen = []
    while path:
        body = asc_api.get(path, bearer=bearer)
        for ref in body.get("data", []):
            attrs = ref.get("attributes", {})
            if attrs.get("kind") != "BRANCH":
                continue
            if attrs.get("name") == branch:
                return ref["id"]
            seen.append(attrs.get("name"))
        next_link = body.get("links", {}).get("next") or ""
        path = next_link.replace(asc_api.BASE_URL, "", 1) if next_link else ""

    raise asc_api.AscError(
        f"no branch {branch!r} in the connected repository; saw: "
        + (", ".join(sorted(set(n for n in seen if n))[:20]) or "none")
    )


def build_run_body(workflow_id, git_reference_id=None):
    relationships = {
        "workflow": {"data": {"type": "ciWorkflows", "id": workflow_id}}
    }
    if git_reference_id:
        relationships["sourceBranchOrTag"] = {
            "data": {"type": "scmGitReferences", "id": git_reference_id}
        }
    return {"data": {"type": "ciBuildRuns", "relationships": relationships}}


def wait_for(build_run_id, poll_seconds, timeout_seconds):
    """Poll a build run to completion.

    Deliberately mints a fresh token per poll rather than reusing the caller's:
    a release build outlives the 20-minute token lifetime, and a token that
    expires mid-wait would look like a build failure.
    """
    deadline = time.time() + timeout_seconds
    last = None
    while time.time() < deadline:
        attrs = asc_api.get(
            f"/v1/ciBuildRuns/{build_run_id}"
        ).get("data", {}).get("attributes", {})
        progress = attrs.get("executionProgress")
        status = attrs.get("completionStatus")
        state = (progress, status)
        if state != last:
            print(f"  {progress or '?'}" + (f" / {status}" if status else ""))
            last = state
        if status in DONE:
            return status
        time.sleep(poll_seconds)
    raise asc_api.AscError(
        f"build run {build_run_id} did not finish within {timeout_seconds}s "
        "(it may still be running; check App Store Connect)"
    )


def tag_build(run_id):
    """Write and push a build/<number> tag for whatever this run uploaded.

    Belt and braces for ci_scripts/ci_post_xcodebuild.sh, which does the same
    thing on the builder: that one needs a push token the builder may not have,
    this one runs where the credentials already are. Whichever gets there first
    wins, and the other reports the tag as already written.

    Never raises. A build that is not tagged is a nuisance; a tagging bug that
    takes down the release script is worse.
    """
    try:
        run = asc_api.get(f"/v1/ciBuildRuns/{run_id}").get("data", {})
        records = build_index.records_for_run(run)
        if not records:
            print("  no build was uploaded, so there is nothing to tag")
            return

        written, already, problems = build_index.apply_tags(records)
        for record in written:
            print(f"  tagged {record.tag} -> {record.commit_sha[:12]}")
        for record in already:
            print(f"  {record.tag} was already tagged")
        for problem in problems:
            print(f"  warning: {problem}", file=sys.stderr)

        if not written:
            return
        remote = build_index.default_remote()
        if not remote:
            print(
                "  warning: no remote points at the upstream repository, so "
                "the tag is local only",
                file=sys.stderr,
            )
            return
        build_index.push_tags(remote, written)
        print(f"  pushed {len(written)} tag(s) to {remote}")
    except asc_api.AscError as err:
        print(f"  warning: could not tag this build: {err}", file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("workflow", nargs="?", help="workflow name (see --list)")
    parser.add_argument("--branch", help="branch to build (default: the workflow's own)")
    parser.add_argument("--list", action="store_true", help="list workflows and exit")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="resolve ids and print the request without starting a build",
    )
    parser.add_argument("--wait", action="store_true", help="poll until the build ends")
    parser.add_argument(
        "--tag",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="tag the commit this build was made from as build/<number> and "
        "push it (default: whenever --wait is given; --tag on its own implies "
        "--wait, since the number does not exist until the run ends)",
    )
    parser.add_argument("--poll-seconds", type=int, default=30)
    parser.add_argument("--timeout-seconds", type=int, default=90 * 60)
    args = parser.parse_args()

    # Line-buffer stdout so progress is visible when this is redirected to a
    # log, which is the normal case: it is meant to be run unattended.
    sys.stdout.reconfigure(line_buffering=True)

    if not args.workflow and not args.list:
        parser.error("a workflow name is required unless --list is given")

    # Tagging is the default rather than a flag, because the commit behind a
    # build number stops being recoverable once Apple prunes the run: a
    # mapping you have to remember to record is a mapping you lose. It is tied
    # to --wait because Apple assigns the number as the run ends — so a bare
    # fire-and-forget invocation stays fire-and-forget, and an explicit --tag
    # opts into the wait it needs.
    if args.tag is None:
        args.tag = args.wait
    elif args.tag:
        args.wait = True

    try:
        # One token for the id lookups and the POST; wait_for mints its own.
        bearer = asc_api.token()
        product = build_index.find_product(bearer)
        workflows = list_workflows(bearer, product["id"])

        if args.list:
            print(f"product {build_index.PRODUCT_NAME} ({product['id']})")
            for workflow in workflows:
                attrs = workflow.get("attributes", {})
                flag = "" if attrs.get("isEnabled", True) else "  (disabled)"
                print(f"  {attrs.get('name')!r}  {workflow['id']}{flag}")
            return 0

        workflow = find_workflow(workflows, args.workflow)
        git_reference_id = (
            find_git_reference(bearer, workflow["id"], args.branch)
            if args.branch
            else None
        )
        body = build_run_body(workflow["id"], git_reference_id)

        if args.dry_run:
            print("POST /v1/ciBuildRuns")
            print(json.dumps(body, indent=2))
            return 0

        status, response = asc_api.request(
            "POST", "/v1/ciBuildRuns", body, bearer=bearer
        )
        if not 200 <= status < 300:
            print(
                f"error: could not start the build (HTTP {status}): "
                f"{asc_api.describe(response)}",
                file=sys.stderr,
            )
            return 1

        run = response.get("data", {})
        number = run.get("attributes", {}).get("number")
        print(f"started build {number} (run {run.get('id')})")

        if not args.wait:
            return 0

        outcome = wait_for(run["id"], args.poll_seconds, args.timeout_seconds)
        print(f"build {number}: {outcome}")

        # Deliberately after a FAILED run too: the RC workflow's test action
        # regularly fails long after a good archive has been uploaded, and
        # that build still needs its commit recorded.
        if args.tag:
            tag_build(run["id"])

        return 0 if outcome == "SUCCEEDED" else 1

    except asc_api.AscError as err:
        print(f"error: {err}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

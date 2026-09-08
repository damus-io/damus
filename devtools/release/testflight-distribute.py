#!/usr/bin/env python3
"""Push an uploaded build to TestFlight groups, and set its What to Test notes.

Both Xcode Cloud workflows deliberately stop after archiving: their own
descriptions say they "will NOT publish to TestFlight groups". Getting a build
in front of testers is a separate App Store Connect operation, which is what
this does. It composes with either upstream path — an Xcode Cloud build or a
local upload from testflight-upload.sh.

  # what groups exist, and what is waiting to go out
  ./devtools/release/testflight-distribute.py --list

  # notes plus an internal group, on the newest build
  ./devtools/release/testflight-distribute.py --group Internal \\
      --notes-file /tmp/whats-new.txt --wait

  # a specific build, resolved by its build number
  ./devtools/release/testflight-distribute.py --build 1334 --group Internal

Nothing is written without --group or --notes; --dry-run prints the calls it
would make. Credentials come from ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH.
"""

import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc_api  # noqa: E402

APP_ID = "1628663131"  # com.jb55.damus2
DEFAULT_LOCALE = "en-US"


def builds(limit=20):
    return asc_api.get(
        f"/v1/builds?filter[app]={APP_ID}&limit={limit}&sort=-uploadedDate"
    ).get("data", [])


def resolve_build(number=None):
    """Pick the build to act on: a given build number, or the newest usable one."""
    found = builds()
    if number is not None:
        for build in found:
            if str(build["attributes"].get("version")) == str(number):
                return build
        seen = ", ".join(str(b["attributes"].get("version")) for b in found)
        raise asc_api.AscError(
            f"no build {number} in the last {len(found)} uploads; saw: {seen}"
        )

    for build in found:
        if not build["attributes"].get("expired"):
            return build
    raise asc_api.AscError(
        "every recent build has expired; upload one, or pass --build explicitly"
    )


def beta_groups():
    return asc_api.get("/v1/betaGroups?limit=200").get("data", [])


def resolve_group(groups, wanted):
    """Resolve a group by id or name, refusing ambiguous names.

    This app has two distinct groups both named 'Beta Testers', so a
    name-keyed lookup that silently picks the first would eventually mail a
    build to the wrong set of people.
    """
    for group in groups:
        if group["id"] == wanted:
            return group

    matches = [
        g for g in groups
        if g["attributes"].get("name", "").casefold() == wanted.casefold()
    ]
    if len(matches) == 1:
        return matches[0]
    if not matches:
        names = ", ".join(
            sorted(repr(g["attributes"].get("name")) for g in groups)
        )
        raise asc_api.AscError(f"no TestFlight group {wanted!r}; available: {names}")

    detail = ", ".join(
        f"{g['id']} (internal={g['attributes'].get('isInternalGroup')}, "
        f"publicLink={bool(g['attributes'].get('publicLinkEnabled'))})"
        for g in matches
    )
    raise asc_api.AscError(
        f"{len(matches)} groups are named {wanted!r} — pass one of these ids "
        f"instead: {detail}"
    )


def wait_for_processing(build_id, poll_seconds=30, timeout_seconds=45 * 60):
    """Block until a build leaves PROCESSING; it cannot be distributed before."""
    deadline = time.time() + timeout_seconds
    last = None
    while time.time() < deadline:
        attrs = asc_api.get(f"/v1/builds/{build_id}").get("data", {}).get(
            "attributes", {}
        )
        state = attrs.get("processingState")
        if state != last:
            print(f"  processing: {state}")
            last = state
        if state == "VALID":
            return attrs
        if state in ("INVALID", "FAILED"):
            raise asc_api.AscError(
                f"build finished processing as {state}; it cannot be distributed"
            )
        time.sleep(poll_seconds)
    raise asc_api.AscError(
        f"build was still {last} after {timeout_seconds}s; check App Store Connect"
    )


def set_notes(build_id, text, locale, dry_run):
    """Create or update the What to Test text for one locale."""
    existing = asc_api.get(
        f"/v1/builds/{build_id}/betaBuildLocalizations"
    ).get("data", [])
    current = next(
        (
            loc for loc in existing
            if loc["attributes"].get("locale") == locale
        ),
        None,
    )

    if current:
        method, path = "PATCH", f"/v1/betaBuildLocalizations/{current['id']}"
        body = {
            "data": {
                "type": "betaBuildLocalizations",
                "id": current["id"],
                "attributes": {"whatsNew": text},
            }
        }
    else:
        method, path = "POST", "/v1/betaBuildLocalizations"
        body = {
            "data": {
                "type": "betaBuildLocalizations",
                "attributes": {"whatsNew": text, "locale": locale},
                "relationships": {
                    "build": {"data": {"type": "builds", "id": build_id}}
                },
            }
        }

    if dry_run:
        print(f"  would {method} {path}  ({len(text)} chars of notes, {locale})")
        return

    status, response = asc_api.request(method, path, body)
    if not 200 <= status < 300:
        raise asc_api.AscError(
            f"could not set What to Test (HTTP {status}): "
            f"{asc_api.describe(response)}"
        )
    print(f"  set What to Test for {locale} ({len(text)} chars)")


def review_state(build_id):
    """Return the build's Beta App Review state, or None if never submitted.

    External groups will not accept a build until it has been through Beta App
    Review. Approval is tracked per build, though a build of a version that has
    already been approved usually clears quickly.
    """
    submission = asc_api.get(
        f"/v1/builds/{build_id}/betaAppReviewSubmission"
    ).get("data")
    if not submission:
        return None
    return submission.get("attributes", {}).get("betaReviewState")


def submit_for_review(build_id, dry_run):
    path = "/v1/betaAppReviewSubmissions"
    body = {
        "data": {
            "type": "betaAppReviewSubmissions",
            "relationships": {
                "build": {"data": {"type": "builds", "id": build_id}}
            },
        }
    }
    if dry_run:
        print(f"  would POST {path}  -> submit for Beta App Review")
        return

    status, response = asc_api.request("POST", path, body)
    if not 200 <= status < 300:
        raise asc_api.AscError(
            f"could not submit for Beta App Review (HTTP {status}): "
            f"{asc_api.describe(response)}"
        )
    state = response.get("data", {}).get("attributes", {}).get("betaReviewState")
    print(f"  submitted for Beta App Review (state: {state})")


def add_to_group(group, build_id, dry_run):
    path = f"/v1/betaGroups/{group['id']}/relationships/builds"
    body = {"data": [{"type": "builds", "id": build_id}]}
    name = group["attributes"].get("name")
    internal = group["attributes"].get("isInternalGroup")

    if dry_run:
        print(f"  would POST {path}  -> {name!r} (internal={internal})")
        return

    status, response = asc_api.request("POST", path, body)
    if not 200 <= status < 300:
        hint = ""
        if not internal:
            hint = (
                " — if Apple is asking for Beta App Review, re-run with "
                "--submit-for-review"
            )
        raise asc_api.AscError(
            f"could not add the build to {name!r} (HTTP {status}): "
            f"{asc_api.describe(response)}{hint}"
        )
    print(f"  released to {name!r} (internal={internal})")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--build", help="build number (default: newest unexpired)")
    parser.add_argument(
        "--group",
        action="append",
        default=[],
        metavar="NAME_OR_ID",
        help="TestFlight group to release to; repeatable",
    )
    parser.add_argument("--notes", help="What to Test text")
    parser.add_argument("--notes-file", help="read What to Test text from a file")
    parser.add_argument("--locale", default=DEFAULT_LOCALE)
    parser.add_argument("--list", action="store_true", help="show builds and groups")
    parser.add_argument("--wait", action="store_true", help="wait out build processing")
    parser.add_argument(
        "--submit-for-review",
        action="store_true",
        help="submit the build for Beta App Review, required before an "
        "external group will accept it",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if args.notes and args.notes_file:
        parser.error("pass only one of --notes and --notes-file")

    sys.stdout.reconfigure(line_buffering=True)

    try:
        if args.list:
            print("recent builds:")
            for build in builds(10):
                attrs = build["attributes"]
                flag = "  (expired)" if attrs.get("expired") else ""
                print(
                    f"  {attrs.get('version'):>6}  {attrs.get('processingState'):<10}"
                    f"  {str(attrs.get('uploadedDate'))[:19]}{flag}"
                )
            print("\nTestFlight groups:")
            for group in beta_groups():
                attrs = group["attributes"]
                kind = "internal" if attrs.get("isInternalGroup") else "EXTERNAL"
                link = " publicLink" if attrs.get("publicLinkEnabled") else ""
                print(f"  {attrs.get('name')!r:42} {kind}{link}  {group['id']}")
            return 0

        notes = args.notes
        if args.notes_file:
            with open(args.notes_file) as handle:
                notes = handle.read().strip()

        if not args.group and not notes:
            parser.error("nothing to do: pass --group and/or --notes/--notes-file")

        # Resolve the groups first so a typo'd or ambiguous name fails
        # immediately, without depending on there being a usable build.
        groups = beta_groups() if args.group else []
        targets = [resolve_group(groups, name) for name in args.group]

        build = resolve_build(args.build)
        attrs = build["attributes"]
        print(
            f"build {attrs.get('version')} ({build['id']}), "
            f"uploaded {str(attrs.get('uploadedDate'))[:19]}, "
            f"state {attrs.get('processingState')}"
        )

        if attrs.get("expired"):
            raise asc_api.AscError(
                f"build {attrs.get('version')} has expired and cannot be distributed"
            )

        if args.wait and attrs.get("processingState") != "VALID":
            attrs = wait_for_processing(build["id"])
        elif attrs.get("processingState") != "VALID":
            raise asc_api.AscError(
                f"build is {attrs.get('processingState')}, not VALID; "
                "re-run with --wait to sit through processing"
            )

        # A build with export compliance unanswered cannot go to testers, and
        # answering it is a legal declaration about the app — so surface it
        # rather than picking an answer.
        if attrs.get("usesNonExemptEncryption") is None:
            print(
                "warning: this build has no export compliance answer, so "
                "distribution will be rejected. Answer it in App Store Connect "
                "(recent damus builds are all 'does not use non-exempt "
                "encryption'), then re-run.",
                file=sys.stderr,
            )

        external = [
            g for g in targets if not g["attributes"].get("isInternalGroup")
        ]
        if external:
            names = ", ".join(
                repr(g["attributes"].get("name")) for g in external
            )
            state = review_state(build["id"])
            print(
                f"note: {names} {'is' if len(external) == 1 else 'are'} EXTERNAL; "
                f"Beta App Review state is {state or 'not submitted'}."
            )
            # Do not pre-judge whether a review is needed. A build of a
            # version that has already been approved is normally accepted
            # without a fresh submission, and only App Store Connect knows for
            # sure — so attempt the release and report Apple's own error if it
            # refuses. --submit-for-review is there for when it does.
            if state != "APPROVED" and args.submit_for_review:
                submit_for_review(build["id"], args.dry_run)
                print(
                    "  approval is gated by Apple and is not instant; re-run "
                    "once the state reads APPROVED."
                )
                if args.dry_run:
                    print("dry run: nothing was changed")
                return 0

        if notes:
            set_notes(build["id"], notes, args.locale, args.dry_run)

        for group in targets:
            add_to_group(group, build["id"], args.dry_run)

        if args.dry_run:
            print("dry run: nothing was changed")
        return 0

    except asc_api.AscError as err:
        print(f"error: {err}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

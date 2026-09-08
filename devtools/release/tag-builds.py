#!/usr/bin/env python3
"""Tag the commits that TestFlight builds were cut from.

App Store Connect knows that build 1338 came from 79d6e28d850e; the repository
does not. This writes that back as annotated `build/<number>` git tags, so the
question "what is actually in the build the testers have?" is answerable with
git rather than by squinting at upload timestamps:

  git show build/1338                 # the commit that shipped as 1338
  git log build/1337..build/1338      # what changed between two builds
  git tag --contains <sha>            # which builds carry this fix
  git describe --match 'build/*'      # the last build at or before HEAD

  # what App Store Connect knows, and what is already tagged
  ./devtools/release/tag-builds.py --list

  # write the missing tags for recent builds
  ./devtools/release/tag-builds.py

  # one build, and push the tag where others can see it
  ./devtools/release/tag-builds.py --build 1338 --push github

  # a build whose run Apple has already forgotten
  ./devtools/release/tag-builds.py --build 1332 --commit 6a1c0de9f2b1

Apple keeps only the last handful of Xcode Cloud runs, and the commit lives on
the run, not on the build — so a build that is a few builds old can no longer
be mapped automatically. Tag as you build (`xcode-cloud-build.py --tag`) and
the mapping is saved while it still exists.

Tags are only ever written for builds that really exist: a run that never got
a builder is skipped, and a run that reports FAILED but still uploaded an
archive is tagged, because that combination is normal here.

Credentials come from ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH; see asc_api.py.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc_api  # noqa: E402
import build_index  # noqa: E402


# --push with no value means "work the remote out"; None means do not push.
AUTO_REMOTE = object()


def run_column(record):
    if record.run_number is None:
        return record.run_status
    return f"{record.run_number} {record.run_status[:9]}"


def show(records):
    print(
        f"{'build':>6}  {'run':<14}  {'commit':<12}  {'tag':<8}  uploaded"
        "             subject"
    )
    for record in records:
        target = build_index.tag_target(record.tag)
        if target is None:
            state = "-"
        elif target == record.commit_sha:
            state = "tagged"
        else:
            state = "MISMATCH"
        known = "" if build_index.have_commit(record.commit_sha) else " (not local)"
        print(
            f"{record.number:>6}  "
            f"{run_column(record):<14}  "
            f"{record.commit_sha[:12]:<12}  {state:<8}  "
            f"{record.uploaded[:19]:<19}  {record.subject[:48]}{known}"
        )


def push(remote, records, dry_run, force=False):
    if dry_run:
        print(f"  would push {len(records)} tag(s) to {remote}")
        return
    refs, changed = build_index.push_tags(remote, records, force=force)
    if changed:
        print(f"  pushed {len(refs)} tag(s) to {remote}")
    else:
        print(f"  {len(refs)} tag(s) already on {remote}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--build", help="only this build number")
    parser.add_argument(
        "--commit",
        help="the commit this build was made from, for a build whose Xcode "
        "Cloud run has aged out of Apple's history; requires --build",
    )
    parser.add_argument(
        "--limit", type=int, default=25, help="how many recent builds to consider"
    )
    parser.add_argument(
        "--list", action="store_true", help="show the mapping without writing tags"
    )
    parser.add_argument(
        "--push",
        nargs="?",
        const=AUTO_REMOTE,
        metavar="REMOTE",
        help="push the tags once written; with no value, to whichever remote "
        "points at the upstream repository",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="move a tag that already points somewhere else",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    remote = args.push
    if remote is AUTO_REMOTE:
        remote = build_index.default_remote()
        if not remote:
            parser.error(
                "no remote points at the upstream repository; name one, as in "
                "--push github"
            )

    if args.commit and not args.build:
        parser.error("--commit says what one build was made from; pass --build too")

    sys.stdout.reconfigure(line_buffering=True)

    try:
        bearer = asc_api.token()

        if args.commit:
            # The commit came from the caller, so there is no run to look up.
            records = [
                build_index.record_from_commit(args.build, args.commit, bearer=bearer)
            ]
        else:
            product = build_index.find_product(bearer)
            if args.build:
                records = [
                    build_index.record_for_build(
                        product["id"], args.build, bearer=bearer
                    )
                ]
            else:
                records = build_index.recent_records(
                    product["id"], bearer=bearer, limit=args.limit
                )

        if not records:
            print("no builds found")
            return 0

        if args.list:
            show(records)
            return 0

        written, already, problems = build_index.apply_tags(
            records, force=args.force, dry_run=args.dry_run
        )

        for record in written:
            verb = "would tag" if args.dry_run else "tagged   "
            print(
                f"  {verb} {record.tag} -> {record.commit_sha[:12]}  "
                f"{record.subject[:48]}"
            )
        if already:
            print(f"  {len(already)} build(s) already tagged")
        for problem in problems:
            print(f"warning: {problem}", file=sys.stderr)

        # Everything correctly tagged locally, not just what this run wrote:
        # "--push" means "make sure these are on the remote", and a tag written
        # by an earlier run that never got pushed is the whole problem.
        if remote:
            publishable = written + already
            if publishable:
                push(remote, publishable, args.dry_run, force=args.force)
            else:
                print("  no tags to push")

        if args.dry_run:
            print("dry run: nothing was written")
        return 1 if problems else 0

    except asc_api.AscError as err:
        print(f"error: {err}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

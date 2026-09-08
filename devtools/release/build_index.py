#!/usr/bin/env python3
"""Map TestFlight build numbers back to the commits they were built from.

Nothing in the repository records which commit became build 1338: the build
number is Xcode Cloud's own run counter, assigned on Apple's side long after
the commit was pushed. The mapping only exists in App Store Connect, and only
until someone goes looking for it.

Two API hops recover it:

  /v1/ciProducts/<product>/buildRuns   each run carries sourceCommit.commitSha
  /v1/ciBuildRuns/<run>/builds         the App Store Connect build it produced

Going through the second hop rather than assuming build number == run number
is what makes this honest in the two cases that actually occur: a run that
never got a builder produces no build at all, and a run that reports FAILED
may still have uploaded a perfectly good archive before its test action died.

Used as a library by tag-builds.py and xcode-cloud-build.py.
"""

import os
import subprocess
import sys
from dataclasses import dataclass
from typing import Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc_api  # noqa: E402

PRODUCT_NAME = "damus"
APP_ID = "1628663131"  # com.jb55.damus2

# Tags are named build/<number> so they sit in their own ref namespace, well
# clear of the hand-cut v1.18-style release tags.
TAG_PREFIX = "build/"

# Used to recognise the upstream remote among however many a clone has.
UPSTREAM_PATH = "damus-io/damus"


@dataclass
class BuildRecord:
    """One TestFlight build, and the commit Xcode Cloud built it from."""

    number: str  # the TestFlight build number (CFBundleVersion)
    build_id: str
    uploaded: str
    expired: bool
    run_number: Optional[int]  # the Xcode Cloud run, None if recorded by hand
    run_id: str
    run_status: str
    commit_sha: str
    commit_message: str
    commit_url: str

    @property
    def tag(self) -> str:
        return f"{TAG_PREFIX}{self.number}"

    @property
    def subject(self) -> str:
        lines = (self.commit_message or "").splitlines()
        return lines[0] if lines else ""


def find_product(bearer=None):
    """The ciProduct for this app, by name."""
    body = asc_api.get("/v1/ciProducts?limit=200", bearer=bearer)
    products = body.get("data", [])
    for product in products:
        if product.get("attributes", {}).get("name") == PRODUCT_NAME:
            return product
    names = ", ".join(
        repr(p.get("attributes", {}).get("name")) for p in products
    ) or "none"
    raise asc_api.AscError(
        f"no Xcode Cloud product named {PRODUCT_NAME!r}; the key can see: {names}"
    )


def iter_runs(product_id, bearer=None, page_size=50, max_runs=500):
    """Yield build runs newest first, following pagination."""
    path = (
        f"/v1/ciProducts/{product_id}/buildRuns?sort=-number&limit={page_size}"
    )
    seen = 0
    while path and seen < max_runs:
        body = asc_api.get(path, bearer=bearer)
        for run in body.get("data", []):
            yield run
            seen += 1
            if seen >= max_runs:
                return
        next_link = body.get("links", {}).get("next") or ""
        path = next_link.replace(asc_api.BASE_URL, "", 1) if next_link else ""


def builds_for_run(run_id, bearer=None):
    return asc_api.get(f"/v1/ciBuildRuns/{run_id}/builds", bearer=bearer).get(
        "data", []
    )


def records_for_run(run, bearer=None):
    """The BuildRecords a single run produced — usually one, sometimes none."""
    attrs = run.get("attributes", {})

    # A run that never got a builder has no archive and no commit worth
    # recording; skipping it here also saves an API call per dead run, of
    # which there are a lot.
    if not attrs.get("startedDate"):
        return []

    commit = attrs.get("sourceCommit") or {}
    found = []
    for build in builds_for_run(run["id"], bearer=bearer):
        build_attrs = build.get("attributes", {})
        found.append(
            BuildRecord(
                number=str(build_attrs.get("version")),
                build_id=build["id"],
                uploaded=str(build_attrs.get("uploadedDate") or ""),
                expired=bool(build_attrs.get("expired")),
                run_number=attrs.get("number"),
                run_id=run["id"],
                run_status=attrs.get("completionStatus") or "?",
                commit_sha=commit.get("commitSha") or "",
                commit_message=commit.get("message") or "",
                commit_url=commit.get("webUrl") or "",
            )
        )
    return found


def recent_records(product_id, bearer=None, limit=25, max_runs=500):
    """The most recent `limit` builds, newest first."""
    found = []
    for run in iter_runs(product_id, bearer=bearer, max_runs=max_runs):
        found.extend(records_for_run(run, bearer=bearer))
        if len(found) >= limit:
            break
    return found[:limit]


def record_for_build(product_id, number, bearer=None, max_runs=500):
    """The record for one build number.

    Scans runs newest first and stops once the run counter drops below the
    wanted number: a build's number is the number of the run that made it, so
    no earlier run can produce it.
    """
    number = str(number)
    for run in iter_runs(product_id, bearer=bearer, max_runs=max_runs):
        for record in records_for_run(run, bearer=bearer):
            if record.number == number:
                return record
        run_number = run.get("attributes", {}).get("number")
        if isinstance(run_number, int) and run_number < int(number):
            break
    raise asc_api.AscError(
        f"no Xcode Cloud run produced build {number}. Apple keeps only the "
        "last handful of runs, so a build more than a few builds old no longer "
        "has a run to read the commit from — pass --commit to say which commit "
        "it was, or tag builds as they are cut, before the run ages out"
    )


def asc_build(number, bearer=None):
    """Look up an App Store Connect build by its build number."""
    found = asc_api.get(
        f"/v1/builds?filter[app]={APP_ID}&filter[version]={number}&limit=1",
        bearer=bearer,
    ).get("data", [])
    if not found:
        raise asc_api.AscError(f"App Store Connect has no build {number}")
    return found[0]


def record_from_commit(number, sha, bearer=None):
    """A record for a build whose commit is supplied by hand.

    For builds whose Xcode Cloud run has aged out: App Store Connect still
    knows the build and when it was uploaded, just not what it was built from.
    """
    build = asc_build(number, bearer=bearer)
    attrs = build.get("attributes", {})
    resolved = git("rev-parse", f"{sha}^{{commit}}").stdout.strip()
    return BuildRecord(
        number=str(attrs.get("version")),
        build_id=build["id"],
        uploaded=str(attrs.get("uploadedDate") or ""),
        expired=bool(attrs.get("expired")),
        run_number=None,
        run_id="",
        run_status="by hand",
        commit_sha=resolved,
        commit_message=git("log", "-1", "--format=%B", resolved).stdout.strip(),
        commit_url="",
    )


# --- git ---------------------------------------------------------------


def git(*args, check=True, env=None):
    """Run git in this repository, wherever the script was invoked from."""
    here = os.path.dirname(os.path.abspath(__file__))
    merged = dict(os.environ, **(env or {}))
    proc = subprocess.run(
        ["git", "-C", here, *args], capture_output=True, text=True, env=merged
    )
    if check and proc.returncode != 0:
        raise asc_api.AscError(
            f"git {' '.join(args)} failed: {proc.stderr.strip() or proc.stdout.strip()}"
        )
    return proc


def default_remote():
    """The remote that looks like the upstream repository, or None.

    Picked by URL rather than by name: clones name their remotes differently —
    this one has 'github' and 'monad' and no 'origin' at all — so a hard-coded
    name would quietly do nothing in half of them.
    """
    for line in git("remote", "-v", check=False).stdout.splitlines():
        name, _, rest = line.partition("\t")
        if UPSTREAM_PATH in rest and rest.rstrip().endswith("(push)"):
            return name
    return None


def push_tags(remote, records, force=False):
    """Push the given builds' tags.

    Returns (refs, changed) — changed is False when the remote already had them
    all, so a caller can say what happened rather than claiming a push that
    git turned into a no-op. Raises AscError if git refuses.
    """
    refs = [record.tag for record in records]
    # A moved tag needs a forced push as well as a forced tag, or git rejects
    # it as a non-fast-forward and the local and remote mappings disagree.
    args = ["push", remote] + (["--force"] if force else []) + refs
    proc = git(*args)
    output = proc.stdout + proc.stderr
    return refs, "Everything up-to-date" not in output


def have_commit(sha):
    if not sha:
        return False
    return git("cat-file", "-e", f"{sha}^{{commit}}", check=False).returncode == 0


def tag_target(name):
    """The commit a tag points at, or None if the tag does not exist.

    Spelled out as refs/tags/ so a build number can never be resolved as some
    other kind of ref that happens to share the name.
    """
    proc = git("rev-list", "-n", "1", f"refs/tags/{name}", check=False)
    return proc.stdout.strip() if proc.returncode == 0 else None


def create_tag(record, force=False):
    """Write an annotated build/<number> tag at the commit that produced it.

    The tag is dated to the upload, not to now, so a backfill of two years of
    builds still reads in the right order in `git log --tags`.
    """
    if record.run_number is None:
        provenance = f"Uploaded {record.uploaded[:19]}; commit recorded by hand."
    else:
        provenance = (
            f"Xcode Cloud run {record.run_number} ({record.run_status}), "
            f"uploaded {record.uploaded[:19]}."
        )
    message = f"TestFlight build {record.number}\n\n{provenance}\n"
    if record.subject:
        message += f"\n{record.subject}\n"

    args = ["tag", "-a", "-m", message]
    if force:
        args.append("-f")
    args += [record.tag, record.commit_sha]

    env = {}
    if record.uploaded:
        env["GIT_COMMITTER_DATE"] = record.uploaded
    git(*args, env=env)


def apply_tags(records, force=False, dry_run=False):
    """Tag every record that is not already tagged.

    Returns (written, already, problems): the records tagged, the ones that
    were already right, and one line of English per record that could not be
    tagged. Nothing here raises on a single bad record — a backfill should
    tag what it can and say what it could not.
    """
    written, already, problems = [], [], []

    for record in records:
        if not record.commit_sha:
            problems.append(
                f"build {record.number}: its run records no source commit"
            )
            continue

        target = tag_target(record.tag)
        if target == record.commit_sha:
            already.append(record)
            continue
        if target is not None and not force:
            problems.append(
                f"{record.tag} already points at {target[:12]}, not "
                f"{record.commit_sha[:12]} — re-run with --force to move it"
            )
            continue

        if not have_commit(record.commit_sha):
            problems.append(
                f"build {record.number}: commit {record.commit_sha[:12]} is not "
                "in this clone; fetch it and re-run"
            )
            continue

        if not dry_run:
            create_tag(record, force=force)
        written.append(record)

    return written, already, problems

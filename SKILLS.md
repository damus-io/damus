# Skills: How to Make Changelogs for Damus

This document explains how to prepare a changelog for a Damus release.

## Overview

Damus uses a Python script (`devtools/changelog.py`) to assist in generating changelogs from git commit history. The changelog format follows [Keep a Changelog](https://keepachangelog.com/) conventions.

## Prerequisites

- Python 3 with `mako` and `requests` packages installed:
  ```
  pip install mako requests
  ```
- Access to the full git history (not a shallow clone). If needed, run:
  ```
  git fetch --unshallow origin
  git fetch origin tag <from_tag>
  ```

## Step 1: Identify the Commit Range

Find the tag for the previous release (e.g. `v1.16.1`) and the commit hash for the new release candidate:

```bash
git tag | sort -V | tail -20         # list recent tags
git rev-parse v1.16.1                # resolve a tag to its commit SHA
```

The commit range format is: `<from_tag>..<to_commit>`

Example: `v1.16.1..5cb8a49`

## Step 2: Run the Changelog Script

```bash
python3 devtools/changelog.py v1.16.1..5cb8a49
```

This scans git log for `Changelog-<section>:` annotations in commit messages, where `<section>` is one of: `added`, `changed`, `deprecated`, `fixed`, `removed`, `experimental`.

**Note:** The script derives the version label from the second argument with the first character stripped (intended for tag names like `v1.17` → `1.17`). When passing a bare commit hash, the version will be wrong—fix it manually when editing `CHANGELOG.md`.

## Step 3: Review and Clean Up the Raw Output

The script's output is a starting point that typically needs manual curation:

1. **Fix the version label:** Replace the auto-derived version (e.g. `cb8a49`) with the actual release version (e.g. `1.17`).

2. **Remove duplicate entries:** Some commits may appear after the previous release tag in `master` history but were already included in that previous release's `CHANGELOG.md` (e.g. cherry-picked features from a release branch). Cross-check against the existing `CHANGELOG.md` and remove duplicates.

3. **Remove reverted entries:** If a commit was later reverted, drop its `Changelog-*` entry. The revert commit may itself have a changelog entry explaining the fix—keep that instead.

4. **Fix truncated entries:** Commit messages with a very long first line can cause `Changelog-Fixed:` entries to be truncated. Check the raw `git log` output to find the full intent, or look up the PR for context.

5. **Verify the date:** Use the actual release date, not the commit date from the RC.

## Step 4: Update CHANGELOG.md

Prepend the new section to `CHANGELOG.md`, following the existing format:

```markdown
## [1.17] - YYYY-MM-DD

### Added

- Feature description (Author Name)


### Changed

- Change description (Author Name)


### Fixed

- Fix description (Author Name)



[1.17]: https://github.com/damus-io/damus/releases/tag/v1.17
```

Keep the existing `[version]: URL` reference link at the bottom of each section.

## Step 5: Commit the Changelog

```bash
git add CHANGELOG.md
git commit -s -m "v1.17 changelog"
```

## Tips

- **Changelog annotations in commits:** Contributors should include a line like `Changelog-Added: Description of feature` in their commit messages so the script can pick them up automatically.
- **`Changelog-None`:** Use this in commit messages that intentionally have no changelog entry (e.g. internal refactors, test fixes). The script ignores it.
- **Author attribution:** The script appends the git author name in parentheses. Keep these intact—they credit contributors.
- **Sections in the script** are: `added`, `changed`, `deprecated`, `fixed`, `removed`, `experimental`. Only sections that have at least one entry are rendered.

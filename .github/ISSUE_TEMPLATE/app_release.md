---
name: App release process
about: Begin preparing for a new app release
title: 'Release: '
labels: release-tasks
assignees: ''

---

A new version release. Please attempt to follow the release process steps below in the order they are shown.

## TestFlight release candidates

### Release candidate 1

**Version:** _[Enter full build information for the release candidate, including major and minor version number, build number, and commit hash]_

1. [ ] Merge in all needed changes to `master`
2. [ ] Check CI, make sure it is passing
3. [ ] Prepare preliminary changelog as a draft PR: _[Enter PR link to changelog here]_
4. [ ] Make a _release_ build and submit to the internal TestFlight group via our new Release candidate workflow in Xcode Cloud.
5. [ ] Prepare short screencast style video with main changes for the announcement
6. [ ] Publish release build to these TestFlight groups:
    - [ ] Alpha testers group
    - [ ] Translators group
    - [ ] Purple group
7. [ ] Publish announcement on Nostr


_[Duplicate this release candidate section if there is more than one release candidate]_


## App Store release

1. [ ] Release candidate checks:
    - [ ] Release candidate has been on Purple TestFlight for at least one week
    - [ ] No blocker issues came from feedback from Purple users (double-check)
    - [ ] Check with stakeholders
2. [ ] Thorough check on release notes
3. [ ] Submit to App Store review (with manual publishing setting enabled)
4. [ ] Get App Store approval from Apple
5. [ ] Prepare announcement
7. [ ] Publish on the App Store and make announcement
8. [ ] Publish changelog and tag commit hash corresponding to the release
9. [ ] Perform a version bump on the repository, in preparation for the next release


## Notes/others

_Enter any relevant notes here_


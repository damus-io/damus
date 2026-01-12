## Summary

- Republish the user's kind-10002 relay list alongside posts/replies to align with NIP-65 point 7 and damus-io/damus#2868.

## Checklist

- [x] I have read (or I am familiar with) the [Contribution Guidelines](../docs/CONTRIBUTING.md)
- [x] I have tested the changes in this PR
- [x] I have profiled the changes to ensure there are no performance regressions, or I do not need to profile the changes.
    - If not needed, provide reason: No performance-sensitive paths changed; added a lightweight follow-up publish.
- [x] I have opened or referred to an existing github issue related to this change. (Closes: https://github.com/damus-io/damus/issues/2868)
- [x] My PR is either small, or I have split it into smaller logical commits that are easier to review
- [x] I have added the signoff line to all my commits. See [Signing off your work](../docs/CONTRIBUTING.md#sign-your-work---the-developers-certificate-of-origin)
- [x] I have added appropriate changelog entries for the changes in this PR. See [Adding changelog entries](../docs/CONTRIBUTING.md#add-changelog-changed-changelog-fixed-etc)
- [x] I have added appropriate `Closes:` or `Fixes:` tags in the commit messages wherever applicable, or made sure those are not needed.

## Test report

**Device:** iPhone 15 Pro (Simulator)  
**iOS:** 18.2 (simulator)  
**Damus:** local build on this branch  
**Setup:** Replying to a note in simulator; inspected relays via lumilumi.app

**Steps:**
1. Compose a reply.
2. Send the reply.
3. Capture outbound events and inspect on lumilumi.app for kind-10002.

**Results:**
- [x] PASS — reply sent and accompanying kind-10002 with relay list observed on relay via lumilumi.app

## Other notes

- Best-effort: if no relay list event or no private key, we skip without blocking post send.

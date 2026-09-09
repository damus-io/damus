# NIP-808 verification record

Date: 2026-09-08. Damus baseline: `cb01a16882491b81f519dd3b3a8cde0273277415`.
The feature is implemented in the working tree. Apple SDK compilation and
device behavior are not established by this Windows/WSL verification.

## Executed checks

| Check | Environment | Result and retained local evidence |
| --- | --- | --- |
| Native compile and regression executable | Ubuntu under WSL; GCC 13.3.0; Python 3.12; resolved Damus libsecp256k1 sources | **PASS**, exit 0. `python3 nostrdb/Test/run_voice_native_tests.py`. [Log](../.build/voice-checks/native-linux-2.log), [exit status](../.build/voice-checks/native-linux-2.exit). |
| All changed/new Swift source syntax | Windows Swift 6.3.2, `swiftc -frontend -parse` | **PASS**, 62 files, exit 0. Source checker plus the 42 changed Swift paths. [Log](../.build/voice-checks/sources-2.log), [exit status](../.build/voice-checks/sources-2.exit). |
| Xcode project source registration | Python source checker | **PASS**: all 13 voice files once each in app/share/highlighter; all seven new XCTest files in damusTests; required notification-extension dependencies; unique project object IDs; source files resolve. |
| Patch whitespace | Git `diff --check` | **PASS**, exit 0 after final source changes. |
| Scope and provider audit | FUSION search/read and Git status | Nosis remains clean. The source specification was not edited. Upload settings and defaults select nostr.build's Blossom service only. |
| Passive diagnostics | FUSION blank snapshot, run 149 | **Not a clean build result**: 403 errors / 44 warnings, unchanged from the pre-check snapshot. 402 C errors concern missing headers/configuration in the Windows language service; one SourceKit error is missing NostrKit in the unchanged Nosis checkout. Swift service opens only its first 400 files. Actual native compilation above passed with explicit include paths. |

Logs live in ignored build storage and are local evidence, not committed artifacts.

The native executable used four disposable databases and actual signed fixtures.
It verified outer and embedded signature rejection, original/source identity,
legacy and marked thread parsing, fresh voice ingestion, embedded-original
recovery, transcript full-text/block indexing, exact mixed reply/thread/quote/
repost counts, preservation of private text counts and existing zap/seen metadata,
migration rollback and retry, five independently injected new-write failures,
duplicate ingestion, repeat migration and reopening.

The log's `migration v6 -> v7 failed` line is expected: that fixture deliberately
makes the blocks database write fail, checks that version/index/count/original
changes rolled back, restores the handle and successfully retries.

The initial native build exposed runner include/source-selection mistakes and
two fixture hex-encoding calls; those were corrected. The first executable run
then found a real new parser defect: only inline-packed strings were accepted,
skipping longer reply/source markers. The parser was corrected to accept both
string representations; the complete regression executable then passed.
The final Swift syntax check also includes the composer reappearance ownership
fix and its added regression case.

Native MinGW was attempted but lacks the POSIX regex dependency used by CCAN.
The successful native evidence is the Ubuntu run. No Windows-native C build,
sanitizer run, XCTest execution or iOS app build is claimed.

## Apple checks still required before release

- Build the `damus` scheme in `damus.xcodeproj`, including share/highlighter and
  notification extensions. This establishes Apple API/type/link compatibility.
- Run the seven new Voice XCTest suites, changed Draft/AdvancedSearch suites
  and existing private reply/giftwrap, thread, event and repost suites.
- Run the new composer UI test and inspect direct/reply/quote/repost voice
  rendering, retained context, keyboard behavior, accessible controls, and
  transcript preservation when media is unavailable.
- On supported physical devices, verify real microphone permissions, offline
  on-device Speech support per locale, audio routes, interruptions, backgrounding
  and termination/restart recovery. Simulator support is not assumed.
- Exercise the upload integration with an authorized nostr.build account/take
  before release. All automated HTTP and relay scenarios use mocks or local
  disposable fixtures; no real upload or public Nostr event was sent.

The [feature guide](NIP808_VOICE.md#reproduce-automated-checks) supplies exact
background build/test commands and the requirement-to-code/fixture map.
These platform checks are explicit release gates, not reported successes.

## Final scope audit

The completed recon findings were checked against the final code: old database
backfill is included, both repost signatures are verified, media uses the exact
signed URL with hash/container/decode checks, Audio has no editable text surface
or release-to-publish path, local-only Speech is enforced, private Text behavior
is preserved, and a durable account/context owner retains recordings, receipts
and signed events through publication failures.

Text remains the initial composer mode. Voice uses the existing post surface,
nostrdb and relay pipeline; separate local files hold only unsent audio recovery
state. No dependency, minimum-OS, Git-account or Mac-build configuration changes
were introduced beyond feature target membership and permission descriptions.
An independently appearing untracked root `Package.resolved` was preserved.
No commit, push or live publication was performed.

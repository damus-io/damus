# NIP-808 verification record

Date: 2026-09-09. UX revision baseline: `d307eeff8c38dcf508a5cb56c85eb9f16c93c43d`.
This revision removes audio restoration, adds confirmed disposal and slide-to-trash
recording, and adds mention/link/photo attachments to the existing voice composer.
Apple SDK compilation, XCTest execution and device behavior remain unverified
in this Windows workspace.

## Executed checks

| Check | Environment | Result and retained local evidence |
| --- | --- | --- |
| Actual gesture and media-reference executable | Windows Swift 6.3.2, Windows SDK, Swift 5 language mode | **PASS**, compile/link/run exit 0. Builds the production `VoiceRecordingGesture.swift` and `VoiceMediaReference.swift` with `scripts/check_voice_composition.swift`, without framework substitutes. [Log](../.build/voice-checks/ux-composition.log), [exit status](../.build/voice-checks/ux-composition.exit). |
| Swift syntax | Windows Swift 6.3.2, `swiftc -frontend -parse` | **PASS**, 30 relevant files, exit 0. Includes production voice sources, seven Voice XCTest files, modified composer/search/UI-test files and the executable fixture. [Log](../.build/voice-checks/ux-sources.log), [exit status](../.build/voice-checks/ux-sources.exit). Final initialization correction: see the later [source-check log](../.build/voice-checks/ux-sources-final.log) and [exit status](../.build/voice-checks/ux-sources-final.exit). |
| Xcode source registration | `scripts/check_voice_sources.py` | **PASS**: all 16 voice production files exactly once in app/share/highlighter; seven Voice XCTest files; required notification dependencies; unique object IDs and valid source paths. |
| Patch whitespace | Git `diff --check` | **PASS**, exit 0 after final source cleanup. |
| Scope and source audit | FUSION reads/searches and Git diff/status | No audio-library routes or restoration remain. Text draft storage is unchanged. Nosis and the source specification are unchanged. |
| Passive diagnostics | FUSION blank snapshot, run 212, age two minutes | **Not a build result**: 97 errors and 8 warnings, all in the unchanged Nosis checkout, concerning C/header/platform configuration. The snapshot does not establish Damus Swift type correctness; Swift service coverage is unavailable for this target. |

Logs are retained in ignored build storage and are local evidence, not committed artifacts.
The executable checked entering/leaving the trash target, release-position handling,
interrupted and duplicate releases, 100 repeated holds, the hit boundary, and
photo metadata isolation from the primary audio reference. Conflicting image/audio
references and unsafe local media URLs are rejected.

The native C/nostrdb regression run from the initial voice implementation is recorded
in this document's earlier Git revision. No C or database schema code changed in
this UX revision, and that native regression executable was not rerun here.

## Regression coverage added or updated

These XCTest and UI-test fixtures were syntax checked, but **not executed** here.

| Requirement | Code and fixtures |
| --- | --- |
| Text drafts survive Cancel and reopening; Text stays the default | Existing PostView draft save/restore paths retained; `damusUITests.testAudioModeDismissesKeyboardAndPreservesTextDraft` covers text preservation across both audio dismissal decisions. |
| Exact confirmation, Keep editing, confirmed deletion and empty-composer exit | PostView, `VoiceComposerDismissGuard`, `VoiceComposerModel`; model/UI fixtures cover Cancel, interactive sheet dismissal, mode changes, both decisions and a real filesystem deletion failure followed by retry. |
| No audio restoration or library | `VoiceDraftStore` owns temporary files for one live composition, with no manifest writes; store fixtures cover reopening, account/context isolation, legacy unsigned cleanup and preservation of signed/unreadable/unrelated legacy records. Library source, routes and target entries are removed. |
| Stop owned work before deletion; ignore late completions | Recorder/transcriber/picker/upload cancellation and lease ownership in `VoiceComposerModel`; fixtures cover permission, finalization, recognition, upload, photo loading, duplicate releases and stale composition IDs. An initialization regression repeats rapid Text/Audio/background changes, then records successfully without automatic upload. |
| Hold and slide left to trash, then release | UIKit touch control uses `VoiceRecordingGesture`; its production state machine was executed above. Model fixtures verify discarded holds do not transcribe and a later hold still works. Physical touch/haptic behavior is pending. |
| Add, review and remove mentions, links and photos after recording | `VoiceAttachmentViews`, `VoicePostAttachments`, `VoicePhotoFiles`; model/protocol/media fixtures cover modification, JPEG preparation, independent imeta fields and exact upload receipt validation. |
| NIP-808 standalone/reply/quote/repost interoperability | `VoiceProtocolTests` signs fixtures for standalone posts and replies/quotes to text and voice, with mentions, links and multiple photos. Checks retain primary audio hash/MIME/duration, thread or quote context, and the signed original in kind 1809. |
| Explicit Post and safe retries | No release-to-upload path. Receipts and exact signed event stay only in the open composition. Publisher/store fixtures cover relay acceptance, stale ACKs and retry identity. Closing local files does not retract an already submitted PostBox event. |

The existing nostrdb event/block indexing, profile index and media renderer support
these signed attachment tags. Voice mention searches reuse the profile index off
the main thread; no new database layout or parallel attachment store was needed.

## Apple checks still required

Use the [feature guide's exact background build/test commands](NIP808_VOICE.md#reproduce-automated-checks)
from the Damus Xcode project on a Mac, with an installed simulator UDID:

- Build the damus scheme and its share, highlighter and notification extensions.
- Run the seven Voice XCTest suites, Draft/AdvancedSearch regressions, the composer
  UI test, and the existing private/giftwrap, thread, event and repost suites.
- On a supported physical device, check hold/slide/back-out/release, hover haptics,
  rapid repeated holds, VoiceOver Start/Stop/Discard, permissions, offline local
  Speech, interruptions, backgrounding and absence of restoration after relaunch.
- Exercise attachment rendering for standalone, replied, quoted and reposted audio.
  Keep signed transcript/links/images visible when audio cannot be played.

Apple SDK type checking, UIKit presentation/touch behavior, real audio/Speech and
extension linking cannot be established by syntax parsing. These checks remain
explicit Mac/device follow-up work. No live upload or public Nostr post was sent.

## Scope audit

Audio always requires an explicit Post. Apple on-device Speech and the nostr.build
Blossom upload service remain the only supported transcription/upload choices.
Unpublished audio and photos are deleted on confirmed close; normal text draft
persistence is unchanged. Old submitted records are not silently removed or exposed
as a library. Closing a submitted composition removes local media without cancelling
PostBox delivery while its account remains active.

No dependencies, minimum OS, Git account, signing or package-resolution changes
were made. The unrelated untracked root `Package.resolved` is excluded from this
commit. No pull request is created; the revision belongs on the fork's `voice-notes`
branch for Mac testing.

## Fork branch integration

Pulled fork commits `35996106` (persistent player scrubber) and `8116a0f6`
(microphone styling). The microphone conflict preserves the gradient, pulse and
reduced-motion behavior alongside attachment controls and slide-to-trash. Its
58-point artwork sits inside the unchanged 76-point touch area, keeping the
tested trash coordinates stable. The timer remains below the controls.

The merged tree passed source membership and Swift syntax checks for all 30 files:
[log](../.build/voice-checks/merge-sources.log),
[exit status](../.build/voice-checks/merge-sources.exit), exit 0.
The Apple SDK and physical-device limitations above still apply.

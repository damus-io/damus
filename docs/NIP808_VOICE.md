# NIP-808 voice posts

Voice posts use the existing Damus composer, event views, relay network and nostrdb.
Open a new post, reply or quote and select **Audio** at the top of the draft sheet.
Text is initially selected. Audio dismisses the keyboard and replaces the text
editor with transcript review; hold the microphone at the bottom to record.
Normal release finalizes the file and transcribes it. Slide left onto the trash
and release to delete the recording; slide back out to finish normally. Listen, record again or discard
before pressing **Post**. Releasing the microphone never uploads or publishes.
Reply and quote context stay in the sheet. Mention, link and photo buttons to the
left of the mic remain available after recording; added items can be reviewed and removed.

Apple Speech is the only transcription service. With Xcode 26 or newer, supported
iOS 26 devices use `SpeechTranscriber(locale:preset: .transcription)` with
`SpeechAnalyzer`, matching Nosis's configuration. Each take gets fresh modules;
input and final results must both finish successfully. Language assets are installed
through `AssetInventory` on first use if needed. Only those models download from
Apple; audio is never uploaded for transcription. Installed models work offline.
Older OS versions, unsupported hardware and languages use `SFSpeechRecognizer`
only when `supportsOnDeviceRecognition` is true, with `requiresOnDeviceRecognition`
always enabled. A supported modern model's runtime failure does not silently switch
engines. Permission denial or unavailable recognition leaves Text usable; failed
transcription retains the recording in the open composer for retry.
Both paths enforce cancellation, a completion timeout and the same transcript limits.
See Apple's [SpeechAnalyzer overview](https://developer.apple.com/documentation/speech/speechanalyzer).

## Upload server

The default is **https://blossom.band**, operated by nostr.build. A paid user may
enter their own **https://name.blossom.band** in Audio's recording settings.
The setting accepts only an HTTPS root origin on this service.

As checked on 2026-09-08, the [official service page](https://blossom.band/)
offers free image/audio/video uploads up to **20 MiB per file**, and paid
subdomains with a **100 MiB service limit**. Damus applies its own smaller
audio processing limits below. Service availability and quotas are enforced by
the service; an HTTP error allows retry while the composer remains open.

Post sends the finalized AAC/MP4 and prepared JPEG bytes to `PUT /upload`. It uses signed kind
`24242` authorization scoped to the upload verb, byte hash, server hostname
and expiration, encoded as unpadded Base64URL. The receipt's SHA-256 and size
must match the locally decoded file and exact request body. Locally verified
audio-only MP4 may be reported as `audio/mp4`, `audio/m4a`, `audio/x-m4a`,
`video/mp4`, `application/mp4`, or an unknown/missing type. Receipt MIME parameters
do not change that verified container. Damus signs canonical `audio/mp4` metadata
for these bytes; incompatible formats still fail. Hash, size and type failures
have separate errors. This receipt compatibility does not relax incoming signed
media validation or the rejection of actual video tracks in primary audio.
The exact returned HTTPS URL is retained, including opaque paths and queries.
Receiving posts accepts arbitrary valid HTTPS primary media URLs; the upload
setting does not restrict reading.

## Protocol

The protocol authority for this port is the [workspace NIP-808 specification](../../NIP-808.md).
This link resolves in the paired-checkout workspace; retain that specification
with the implementation review. The integration implements these rules:

| Event | Content and tags |
| --- | --- |
| Voice post, `1808` | Signed transcript; `url`, `blossom` with actual SHA-256 and MIME, and measured `duration`. New recordings use `audio/mp4`. |
| Attachments on `1808` | NIP-27 `nostr:npub` mentions plus `p`; web links in content plus `r`; photo URLs in content plus a separate NIP-92 `imeta` for each JPEG. Photo MIME/dimensions/blurhash never replace primary audio metadata. |
| Voice reply | Same media tags plus NIP-10 immediate parent, known root and author `p` tags; text and voice may be mixed at any depth. |
| Voice quote | Primary `q`, author `p` and `nostr:nevent` in the signed content; no fabricated reply relationship. |
| Voice repost, `1809` | Full signed original `1808` in content; matching original `e`, author `p` and `k=1808`. |

Marked `repost-source` references are provenance, never the original repost
target or a reply. Marked NIP-10 references take precedence over positional
legacy references. A single legacy root remains a direct reply.
Both signatures, IDs, kinds and original-target tags must validate before a
voice repost is displayed, counted or used to authorize playback. The Swift
cryptographic wrapper passes the actual secp256k1 context with bounded storage.

Repeated authoritative media declarations must agree. Missing or conflicting
URL/hash/MIME metadata leaves the signed transcript visible and reports a media
error. A separate cover image is not the primary audio. Duration tags are
advisory when receiving: decoded media determines playback duration.

## Storage and publication

nostrdb stores voice events in its existing event and index layout. Migration
7 backfills old voice transcripts and blocks, recovers validated embedded
originals, and recalculates affected reply/thread/quote/repost counts.
The migration is transactional and repeatable, retaining zap metadata and flags.
New voice writes use a child transaction so a failed index/count write cannot
leave an event ID that suppresses retry. Existing private text counts remain.

Unpublished audio is scoped to one open composer. Its in-memory snapshot and
temporary files are separated by session, account and post/reply/quote context.
Closing or discarding waits for owned recording, recognition, photo-loading and
upload work before deleting local audio and photos. Late callbacks cannot restore
the closed composition. A new sheet starts empty in Text mode; normal Damus text
drafts keep their existing save/restore behavior.

Cancel and interactive sheet dismissal ask:
**Are you sure you want to discard this audio post before posting it?**
**Keep editing** retains the current recording and attachments.
**Yes, discard** deletes them and then closes; failed deletion keeps the sheet open.
Changing to Text within the same sheet does not bypass this confirmation when
leaving or posting text. The review trash button discards audio while keeping the
sheet open. Empty audio compositions close normally.

The exact upload receipts and signed event remain available for retries only while
that composition is open. Only Post uploads and submits. Queueing, dispatch,
acceptance, rejection and no-relay status are distinct; only a matching positive
relay OK means acceptance. PostBox retains an explicitly submitted event while the
account remains active, even after closing local composition files. Close does not
retract a submitted event or offer misleading discard wording for it. Account
invalidation prevents stale work from signing or publishing. No audio restoration
or library is provided after relaunch.

Old unsigned audio manifests/files are retired for the active account when Audio
opens. Submitted or unreadable old records and unrelated account/text data are
preserved, without exposing restoration. Leftover temporary compositions from an
interrupted process are removed when the next process first prepares audio storage.
Private/rumor contexts do not offer a public audio posting path.

## Playback and application bounds

Audio is fetched only after a playback action, using bounded storage. Damus
checks the exact byte hash, real container/MIME and complete decodability before
playing. Cached audio is checked again. Primary voice media is excluded from
generic image/link/video preview paths, including MP4 video rendering.
Playback is shared across voice rows and cooperates with the existing video
player and recorder; interrupted or abandoned requests cannot start a new player.

Read-side attachments merge transcript URLs with NIP-808 `imeta` and `r` tags
and any remaining cached references. Each attachment is deduplicated without
rewriting the URL used for fetching. Declared image/video MIME types support
opaque URLs; optional image metadata accepts multiword fields such as `alt`.
Images and independent videos use Damus's existing media carousel and media
visibility settings. Tag-only web links retain their optional titles and remain
clickable when rich previews are disabled. Additional audio references remain
links; they are not selected as the primary recording.

The same renderer handles feeds, profiles, replies, quotes and verified repost
originals. It repairs older cached artifacts that excluded attached videos.
Every declared primary audio URL stays excluded from ordinary media/preview
paths, including aliases with fragments or default ports. Invalid primary
recording metadata does not hide otherwise valid, independent attachments.
nostrdb already preserves these tags, so attachment rendering needs no new
database migration.

When a voice row includes image attachments, their raw URLs are omitted from the
displayed text. Transcript text, mentions, profile badges and ordinary links stay
visible; text-only rows retain the image links. This display filtering does not
modify the signed event or cached content.

The shared row above the transcript uses a rounded adaptive background, a scrubber,
a 1x/2x/3x speed button, and a fixed 52-point play/pause/loading button with the
same Damus gradient as the microphone and feed compose button. There is no
"Voice post" label or duration counter. Published voice posts load and start audio
only after an explicit Play action. Scrubbing an idle post selects the start
position for the next Play; releasing the scrubber never starts audio. Seeking
a paused post leaves it paused. Scrolling away still cancels pending playback
and stops active playback; returning to the post leaves it idle.
The composer uses those same controls
above its transcription and attachments, across the full width of the sheet.
The compact review heading can wrap for larger text. Preview loading, seeking
and pause/resume operate on local files without uploading; Post, a new take,
format changes and dismissal stop pending or active preview playback.

`VoicePlaybackRate` matches Nosis's effective speeds exactly: **1x = 1.0,
2x = 1.4, 3x = 1.7**. Damus starts at 2x and keeps the selection across rows
for the app session. Speed changes do not download audio, reset the position,
or resume a paused recording. They also apply to a recording still loading.
As in Nosis, playback uses `AVAudioPlayer.enableRate`, enabled before
`prepareToPlay`. Apple documents that [rate adjustment preserves pitch](https://developer.apple.com/documentation/avfaudio/avaudioplayer/rate).

| Bound | Value |
| --- | --- |
| Recording | 5 minutes |
| Local recognition | 180-second completion timeout |
| Record finalization | 5-second completion timeout |
| Received audio file | 32 MiB maximum |
| Shared nostr.build upload | 20 MiB maximum |
| Audio cache | 96 MiB |
| Media download / full decode | 120 / 30 seconds |
| Received decoded duration | 30 minutes |
| Concurrent downloads / inspections | 2 / 2 |
| Transcript | 12,000 UTF-8 bytes |
| Transcript plus attachment references | 32,000 UTF-8 bytes |
| Attached photos | 8; 20 MiB and 40 megapixels each before JPEG preparation |
| Mention / web-link attachments | 100 / 20 |

These are application limits, not claims about universal Apple Speech limits.
The deployment target remains iOS 16. The notification extension verifies and
formats voice posts/reposts without importing recording or playback services.

## Requirement-to-evidence map

| Requirement | Implementation and regression fixtures |
| --- | --- |
| Signed events, mixed roots, quotes, source markers and forged repost rejection | `VoiceEventBuilder`, `NdbNote`, native parser/verification; `VoiceProtocolTests`, `voice_native_test.c` |
| New and old database equivalence; rollback, duplicate/reopen/idempotence; counts and private text | `nostrdb.c` migration/writer; standalone native fixture |
| All feeds, search, actions, threads, deep links and notification targets | `NostrKind` categories; Home/Profile/Thread/Events/Search models; shared event views; notification service; `AdvancedSearchTests`, `VoiceIntegrationTests` |
| Exact URL/hash/MIME, conflicting tags, cover isolation, no MP4 bypass | `VoiceMediaReference`, `VoiceAudioFiles`, `NoteContent`; `VoiceMediaReferenceTests`, `VoiceMediaServicesTests`, `VoiceIntegrationTests` |
| Hold/finalize/transcribe/review/Post; cancellation, permission, timeout and stale callbacks | `VoiceComposerModel`, Apple recorder/transcriber; `VoiceComposerModelTests`, `VoiceSpeechJobTests` |
| Temporary account/context/take ownership; confirmed discard and no restoration; exact event retry; relay OK semantics | `VoiceDraftStore`, `VoicePublisher`, PostBox; `VoiceDraftStoreTests`, `VoiceComposerModelTests`, `VoiceIntegrationTests` |
| Text default, text draft preservation, attachment controls and both dismissal decisions | PostView and VoiceComposerControls; `damusUITests.testAudioModeDismissesKeyboardAndPreservesTextDraft` |
| Trash enter/leave, final position, duplicate/cancelled releases and repeat holds | `VoiceRecordingGesture`, `VoiceComposerModelTests`, executable `scripts/check_voice_composition.swift`; real touch/VoiceOver checks on device |
| NIP-27/NIP-92 attachment payloads and photo receipt validation | `VoicePostAttachments`, `VoiceEventBuilder`, `VoicePhotoFiles`, `VoiceBlossomUploader`; protocol/composer/media service tests |
| Read-side tag-only/mixed photo, video and link attachments; primary exclusion; cached order; verified reposts | `VoiceAttachmentReferences`, `NoteContent`, `NoteContentView`, `ImageMetadata`; executable composition checks and `VoiceIntegrationTests.testVoiceAttachmentsRenderFromWireTagsContentAndVerifiedReposts` |
| Private text and uncached quote restoration | DraftsModel; added `DraftTests` cases |
| Exact Nosis playback speeds; keep pause, position and selection across rows | `VoicePlaybackRate`, `VoicePlayback`, `VoiceAudioFiles`; executable composition checks and `VoiceMediaServicesTests.testPlaybackSpeedSurvivesPauseSeekingAndChangingRows` |
| Local composer preview seeking, cancellation, format changes and cleanup | `VoiceComposerModelTests.testPreviewSeeksPausesAndStopsWhenSwitchingToText`, `testCancelledPreviewCannotPlayAfterTheComposerIsDiscarded` |
| Compatible Blossom MP4 receipt types with exact bytes and canonical outgoing tags | `VoiceMediaServicesTests.testMP4UploadReceiptsAcceptCompatibleContainerLabelsAndUnknownTypes`, forged-receipt and signed-upload tests |
| Async transcription success, failure, timeout and late cancellation | `VoiceSpeechJobTests.testAsyncRecognitionValidatesFinalTextAndPropagatesFailure`, `testAsyncRecognitionTimeoutCancelsTheOperation`, `testAsyncRecognitionCancellationRejectsLateSuccess` |
| App/extension/test source membership | `scripts/check_voice_sources.py`; final Xcode build remains required |

## Verification status

The implementation workspace is Windows. The final local check outcomes are
recorded in [NIP808_VERIFICATION.md](NIP808_VERIFICATION.md). Swift syntax parsing
is not Apple SDK type checking. XCTest, simulator UI, extension linking and
physical-device microphone/Speech behavior remain **unexecuted release gates**
until run on a Mac/device. No live audio upload or Nostr post was used for tests.

## Reproduce automated checks

Resolve the project's packages first. The native runner needs the libsecp256k1
source directory inside the resolved `secp256k1.swift` package. It discovers
common `.build` and `build/SourcePackages` locations, or accepts `--secp-dir`.
It uses real C/LMDB/cryptographic code and disposable databases, not a user DB.
Use Python 3.9+ and a supported C compiler; `--sanitize` enables ASan/UBSan.

Run each check in the background from the Damus repository, preserving its exit
status and log. Replace the secp path if the package checkout is elsewhere:

```bash
mkdir -p build/voice-checks
(python3 nostrdb/Test/run_voice_native_tests.py --secp-dir build/SourcePackages/checkouts/secp256k1.swift/Sources/bindings/secp256k1; printf '%s' "$?" > build/voice-checks/native.exit) > build/voice-checks/native.log 2>&1 &
(python3 scripts/check_voice_sources.py; printf '%s' "$?" > build/voice-checks/sources.exit) > build/voice-checks/sources.log 2>&1 &
```

The source checker always checks voice files and accepts extra changed Swift
paths as positional arguments. It checks project membership and parses syntax.

On a Mac, build with Xcode 26 or newer to include the iOS 26 transcriber.
Use the actual Xcode app project (not the root Swift package). Choose
an installed simulator UDID from `xcrun simctl list devices available`, set
`VOICE_SIM_UDID`, and use a dedicated DerivedData directory. Configure normal
development signing for device builds. `just build` / `just test` are the
repository's standard alternatives and require `xcbeautify`.

```bash
mkdir -p build/voice-checks
VOICE_SIM_UDID='<installed simulator UDID>'
(xcodebuild -project damus.xcodeproj -scheme damus -configuration Debug -destination "platform=iOS Simulator,id=$VOICE_SIM_UDID" -derivedDataPath build/VoiceDerivedData build; printf '%s' "$?" > build/voice-checks/app.exit) > build/voice-checks/app.log 2>&1 &
```

After the build exits successfully, run the focused regression suites:

```bash
(xcodebuild -project damus.xcodeproj -scheme damus -configuration Debug -destination "platform=iOS Simulator,id=$VOICE_SIM_UDID" -derivedDataPath build/VoiceDerivedData test -only-testing:damusTests/VoiceMediaReferenceTests -only-testing:damusTests/VoiceProtocolTests -only-testing:damusTests/VoiceDraftStoreTests -only-testing:damusTests/VoiceMediaServicesTests -only-testing:damusTests/VoiceSpeechJobTests -only-testing:damusTests/VoiceComposerModelTests -only-testing:damusTests/VoiceIntegrationTests -only-testing:damusTests/DraftTests -only-testing:damusTests/AdvancedSearchTests; printf '%s' "$?" > build/voice-checks/tests.exit) > build/voice-checks/tests.log 2>&1 &
```

A portable executable check compiles the actual gesture, playback-rate, primary-media
and read-side attachment sources:

```bash
swiftc damus/Features/Voice/Models/VoiceRecordingGesture.swift damus/Features/Voice/Models/VoicePlaybackRate.swift damus/Features/Voice/Models/VoiceMediaReference.swift damus/Features/Voice/Models/VoiceAttachmentReferences.swift scripts/check_voice_composition.swift -o build/voice-checks/composition-checks
build/voice-checks/composition-checks
```

Then run the composer UI test and the full existing suite before release:

```bash
(xcodebuild -project damus.xcodeproj -scheme damus -configuration Debug -destination "platform=iOS Simulator,id=$VOICE_SIM_UDID" -derivedDataPath build/VoiceDerivedData test -only-testing:damusUITests/damusUITests/testAudioModeDismissesKeyboardAndPreservesTextDraft; printf '%s' "$?" > build/voice-checks/ui.exit) > build/voice-checks/ui.log 2>&1 &
```

Inspect each complete log and its `.exit` file; an absent exit file means the run
has not reported completion. Keep build/test invocations sequential on the same
DerivedData. Existing private/giftwrap, repost, thread and draft tests must pass.

For published voice posts, open the app and scroll through feed, profile, reply,
quote and repost rows. Touch and release the idle scrubber, including during a
vertical scroll, and change speed: neither loading nor playback should start.
Choose a position, tap Play, and verify audio starts there. Pause and scrub to
confirm it stays paused. Scroll away during loading and during playback, then
return: the request should be cancelled or playback stopped, with no automatic
restart. Cover both cached and previously unplayed recordings. This gesture
regression uses manual device coverage because the UI suite does not currently
provide a seeded published voice row for deterministic timeline interaction.

On a small phone, review a new post, reply and quote in light/dark mode and larger
text sizes. Verify the heading is readable and the full-width player appears above
the transcript and attachments. Scrub before playback, cancel loading, pause, change
speed and resume; the player must match the feed and start at the session's selected
speed. These visual checks remain manual because this Windows workspace cannot
run SwiftUI or an iOS simulator.

On supported iOS 26 hardware, verify the modern transcriber with installed assets
in airplane mode, a first-use language download, an unavailable model while offline,
and a second take after cancellation. Also verify the on-device legacy path on
older hardware/OS versions. Check unavailable languages, denied permissions,
route/interruption/background handling and no audio restoration after termination.
Hold the mic and move onto the
trash, back out, and onto it again before releasing; check hover feedback, no
transcription after trash release, rapid repeated holds, and the VoiceOver
Start/Stop/Discard actions. These touch, haptic and microphone checks require a
physical Apple device: Windows cannot execute UIKit or inject device Speech input. Inspect direct, replied, quoted and reposted voice
rows, including invalid media/transcript-only presentation and VoiceOver actions.
Check the player in light and dark mode, narrow quoted rows and larger text sizes:
its controls should stay stable through loading/play/pause, and each speed button
tap should cycle 1x/2x/3x without starting idle audio. Listen at each speed, scrub
before and during playback, pause/change speed/resume, and switch posts.
Confirm the vertical order is player, transcription, then attachments in feeds,
profiles, replies, quotes and verified reposts, including posts without a transcript.
For read-side attachments, inspect posts with two images (including an opaque
URL), an independent video, and titled links in the home feed, a profile, a
quote and a verified repost. Include attachments present only in tags, repeat
the same URL in the transcript, reopen cached rows, disable rich previews,
and toggle media loading. Confirm independent media appears once in the
carousel and the primary recording never appears as an image/video preview.
Compare the gap above the reaction bar with ordinary posts for single-photo,
multiple-photo and video voice posts, including revealed and blurred attachments.
Check both light/dark mode and large text. Signed-wire/rendering XCTest fixtures
cover the shared data path; visual media loading and settings checks remain
manual because this Windows workspace cannot run SwiftUI or an iOS simulator.
Use captured/mock relay and HTTP responses for automated tests. Live provider
upload/account verification requires a separately authorized real upload.

## Primary references

- [Apple local recognition support](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition)
- [Apple request requirement](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)
- [BUD-02 upload and descriptors](https://github.com/hzrd149/blossom/blob/master/buds/02.md)
- [BUD-11 signed authorization](https://github.com/hzrd149/blossom/blob/master/buds/11.md)
- [nostr.build Blossom service and plans](https://blossom.band/)

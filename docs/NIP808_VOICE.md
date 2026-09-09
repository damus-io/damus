# NIP-808 voice posts

Voice posts use the existing Damus composer, event views, relay network and nostrdb.
Open a new post, reply or quote and select **Audio** at the top of the draft sheet.
Text is initially selected. Audio dismisses the keyboard and replaces the text
editor with transcript review; hold the microphone at the bottom to record.
Release finalizes the file and transcribes it. Listen, record again or discard
before pressing **Post**. Releasing the microphone never uploads or publishes.
Reply and quote context stay in the sheet.

Apple Speech is the only transcription service. Both local language support
(`supportsOnDeviceRecognition`) and `requiresOnDeviceRecognition` are required.
Permission denial or unavailable local recognition leaves Text usable. A failed
transcription retains the recording for retry; it never invents transcript text.
Recording and recognition stop on interruption, backgrounding, navigation or
account changes, with late completions fenced by the take and account.

## Upload server

The default is **https://blossom.band**, operated by nostr.build. A paid user may
enter their own **https://name.blossom.band** in Audio's recording settings.
The setting accepts only an HTTPS root origin on this service.

As checked on 2026-09-08, the [official service page](https://blossom.band/)
offers free image/audio/video uploads up to **20 MiB per file**, and paid
subdomains with a **100 MiB service limit**. Damus applies its own smaller
audio processing limits below. Service availability and quotas are enforced by
the service; an HTTP error remains a recoverable draft error.

Post sends the finalized AAC/MP4 bytes to `PUT /upload`. It uses signed kind
`24242` authorization scoped to the upload verb, byte hash, server hostname
and expiration, encoded as unpadded Base64URL. The returned URL, SHA-256, MIME
and size must match the local bytes. The exact returned URL is retained,
including an opaque path or query string. Receiving posts accepts arbitrary
valid HTTPS primary media URLs; the upload setting does not restrict reading.

## Protocol

The protocol authority for this port is the [workspace NIP-808 specification](../../NIP-808.md).
This link resolves in the paired-checkout workspace; retain that specification
with the implementation review. The integration implements these rules:

| Event | Content and tags |
| --- | --- |
| Voice post, `1808` | Signed transcript; `url`, `blossom` with actual SHA-256 and MIME, and measured `duration`. New recordings use `audio/mp4`. |
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

Unsent audio uses versioned account-scoped manifests and UUID-named files under
Application Support. These are draft files, not a second event database.
Exclusive context ownership serializes closing/restoring the same draft.
**Saved Audio** in the public composer restores recordings and pending posts,
including their captured reply/quote target when it is no longer cached.

The upload receipt is saved before signing; the complete signed event is saved
before handoff to PostBox. Retry reuses that receipt and exact signed event.
Queueing, dispatch, acceptance, rejection and no-relay status are distinct.
Only a matching positive relay OK records acceptance. Offline and zero-relay
posts remain recoverable and are locally ingested independently of dispatch.
An account switch prevents stale work from signing or publishing.

An accepted draft can be cleared explicitly. A pending signed draft is retained
because already-dispatched events cannot reliably be recalled. Discard and
replacement delete only files owned by that draft. Text drafts preserve their
existing private flags and quote references. Private/rumor contexts do not offer
a public audio posting path.

## Playback and application bounds

Audio is fetched only after a playback action, using bounded storage. Damus
checks the exact byte hash, real container/MIME and complete decodability before
playing. Cached audio is checked again. Primary voice media is excluded from
generic image/link/video preview paths, including MP4 video rendering.
Playback is shared across voice rows and cooperates with the existing video
player and recorder; interrupted or abandoned requests cannot start a new player.

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
| Transcript | 12,000 characters |

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
| Durable account/context/take ownership; receipt and exact event retry; relay OK semantics | `VoiceDraftStore`, `VoicePublisher`, PostBox; `VoiceDraftStoreTests`, `VoiceComposerModelTests`, `VoiceIntegrationTests` |
| Text default, keyboard removal/restoration and bottom microphone | PostView and VoiceComposerControls; `damusUITests.testAudioModeDismissesKeyboardAndPreservesTextDraft` |
| Private text and uncached quote restoration | DraftsModel; added `DraftTests` cases |
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

On a Mac, use the actual Xcode app project (not the root Swift package). Choose
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

Then run the composer UI test and the full existing suite before release:

```bash
(xcodebuild -project damus.xcodeproj -scheme damus -configuration Debug -destination "platform=iOS Simulator,id=$VOICE_SIM_UDID" -derivedDataPath build/VoiceDerivedData test -only-testing:damusUITests/damusUITests/testAudioModeDismissesKeyboardAndPreservesTextDraft; printf '%s' "$?" > build/voice-checks/ui.exit) > build/voice-checks/ui.log 2>&1 &
```

Inspect each complete log and its `.exit` file; an absent exit file means the run
has not reported completion. Keep build/test invocations sequential on the same
DerivedData. Existing private/giftwrap, repost, thread and draft tests must pass.

On supported physical devices, verify offline local recognition, unavailable
languages, denied permissions, route/interruption/background handling and
recovery after termination. Inspect direct, replied, quoted and reposted voice
rows, including invalid media/transcript-only presentation and VoiceOver actions.
Use captured/mock relay and HTTP responses for automated tests. Live provider
upload/account verification requires a separately authorized real upload.

## Primary references

- [Apple local recognition support](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition)
- [Apple request requirement](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)
- [BUD-02 upload and descriptors](https://github.com/hzrd149/blossom/blob/master/buds/02.md)
- [BUD-11 signed authorization](https://github.com/hzrd149/blossom/blob/master/buds/11.md)
- [nostr.build Blossom service and plans](https://blossom.band/)

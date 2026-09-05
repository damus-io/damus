# Bunny Stream spike — Purple Video Phase 0

Findings from proving the Purple Video pipe by hand against a real Bunny
account, before any product code exists. Phases 1–5 (the Purple API) and 7–12
(iOS) are written against what is recorded here, so this is **observed
behaviour, not documentation** — where the two disagree, the observation wins
and is called out.

Raw captures live in [`bunny-stream-spike/`](bunny-stream-spike/), with library
id, video GUID, pull-zone hostname and every key replaced by `{PLACEHOLDER}`.

Spiked 2026-09-05 against Bunny `stream-apiver 1.5.27`.

## What was proven

A 310 MB portrait HEVC iPhone `.mov` was TUS-uploaded by hand to a Bunny Stream
library, transcoded to a 4-rendition H.264 HLS ladder, and played back
adaptively and right-way-up in `AVPlayer` from an unauthenticated CDN URL, with
zero stalls. The pipe works as the epic describes it.

`video.damus.io` is live on a Let's Encrypt certificate and serves it publicly.
The encoding webhook has since been captured against a real ingress, and it
disagrees with the docs in ways that change Phase 5's design — see
[the webhook section](#the-encoding-webhook-as-it-actually-behaves).

## The two API scopes

Bunny splits credentials, and you need both:

| Scope | Base URL | Used for |
| --- | --- | --- |
| Account API key | `https://api.bunny.net` | create/configure the video library, pull zones, hostnames, certificates |
| Per-library Stream key | `https://video.bunnycdn.com/library/{id}/...` | create video objects, read status, delete, and mint TUS signatures |

The per-library key is **not** issued separately — it is the `ApiKey` field of
the library object returned by the Account API. So one account key bootstraps
everything. Phase 1's config plumbing needs to hold both, and the Stream key is
the one that must reach the TUS signature computation.

## Library configuration

Created library `damus-purple-video`. Full final state:
[`library-config.json`](bunny-stream-spike/library-config.json).

The card's encoder spec, as applied:

| Setting | Value | Why |
| --- | --- | --- |
| `EnabledResolutions` | `360p,480p,720p,1080p` | 240p dropped; 1440p/2160p were already off by default |
| `OutputCodecs` | `x264` | H.264 only. This is already the default — AV1/VP9/HEVC are opt-in |
| `KeepOriginalFiles` | `false` | default is `true`; would have stored the 310 MB source forever |
| `EnableMP4Fallback` | `false` | default is `true`; a whole extra copy of every rendition |
| `EncodingTier` | `0` (Standard) | Premium encoding is billed |
| `ReplicationRegions` | none | storage replication is per-region billed |

**Two of those defaults are expensive and silent.** A library created with no
arguments keeps the original file *and* an MP4 fallback set. Phase 1 must
create libraries with these explicitly set, not assume the defaults.

### The setting that breaks public playback

Fresh libraries ship with `BlockNoneReferrer: true` and `AllowedReferrers: []`.
That combination **403s any request without a `Referer` header** — which is
exactly what `curl`, `AVPlayer`, and every native nostr client sends.

The first playback attempt returned `403 Forbidden` on `playlist.m3u8` and on
`thumbnail.jpg`. Setting `BlockNoneReferrer: false` fixed it immediately.

This is load-bearing for the epic: "playback is public, any nostr client can
consume it" is *not* the out-of-the-box behaviour. Phase 1 must set it, and
Phase 15's runbook should assert it, or Android and web clients will see 403s
that iOS (embedding a player with a referrer) might not.

`PlayerTokenAuthenticationEnabled` is `false` by default, which is what we want
— that is the separate token-auth feature the epic explicitly rejected.

## Pull zone and DNS

Creating a Stream library **auto-creates its own pull zone**; you do not create
one. Ours is type `1` (Stream), bound to the library, with a system hostname
`{PULL_ZONE}.b-cdn.net`. The existing unrelated `badnerds-media` zone was not
touched.

`video.damus.io` was added to that pull zone's hostnames (`HTTP 204`). Before
DNS existed the certificate request failed exactly as it should:

```
HTTP 400 {"ErrorKey":"pullzone.certificate_request_failed",
          "Message":"The domain video.damus.io is not pointing to our servers."}
```

jb55 then added the record:

```
video.damus.io.  CNAME  {PULL_ZONE}.b-cdn.net.
```

after which `loadFreeCertificate` succeeded. The hostname now carries a Let's
Encrypt certificate (`CN=video.damus.io`, valid to 2026-12-04) and `ForceSSL` is
on, so plain `http://` answers `301` to `https://`. **`video.damus.io` is live**
and serves the spike video publicly and unauthenticated.

The URL shape in the epic is confirmed:

```
https://{pull-zone}/{video-id}/playlist.m3u8
https://{pull-zone}/{video-id}/thumbnail.jpg
https://{pull-zone}/{video-id}/{resolution}/video.m3u8
```

## The video object, as it actually behaves

Captured at both ends of its life:
[created](bunny-stream-spike/video-object-status0-created.json) ·
[finished](bunny-stream-spike/video-object-status4-finished.json) ·
[full progression](bunny-stream-spike/encode-status-progression.log).

`status` observed: `0` created → `2` processing → `3` transcoding → `4`
finished. (`5`/`6` are error states; not observed here.) Phase 4 should treat
`>= 4` as terminal and only `4` as success.

The progression, abridged:

```
status=2 encodeProgress=5    avail=None                      storageSize=0
status=2 encodeProgress=35   avail=None                      storageSize=0
status=3 encodeProgress=35   avail=None                      thumbCount=47
status=3 encodeProgress=45   avail='360p'                    storageSize=0
status=3 encodeProgress=70   avail='360p,480p,720p,1080p'    storageSize=0
status=4 encodeProgress=100  avail='360p,480p,720p,1080p'    storageSize=128452105
```

Things worth knowing before writing Phase 4 or 5 against this:

- **`availableResolutions` fills in incrementally**, low to high, while status is
  still `3`. A client that publishes the note as soon as it is non-`null` gets
  a note whose video only has a 360p rendition. The epic's rule — do not publish
  until a playable rendition exists — should be **status == 4**, not
  "availableResolutions is non-empty".
- **`storageSize` stays `0` until status `4`.** It is useless for live progress
  and only meaningful once finished. Phase 14's cost attribution must read it
  after completion, not during.
- **`encodeProgress` is not monotonic-per-second and plateaus** (35 for three
  polls, then jumps). Fine for a progress bar, useless as a liveness signal.
  Phase 10 should not treat a flat `encodeProgress` as a stall.
- `thumbnailCount` reached 47 and `thumbnailUrl`/`thumbnailBlurhash` populate
  before the encode finishes.
- `thumbnailBlurhash` is supplied by Bunny (`WKDl[:IAIoWVRjt7~q...`). That maps
  straight onto the `blurhash` field Phase 11 puts in `imeta` — no need to
  compute one on the phone.
- `transcodingMessages` carried a real diagnostic:
  `{"level":1,"issueCode":4,"message":"Source video stream has variable framerate","value":"59.88"}`.
  iPhone video is VFR, so **expect this on essentially every upload**. Phase 5
  should not surface `level 1` messages to users as errors.
- `hasMP4Fallback: false` and `hasOriginal: false` confirm the storage settings
  actually took effect.

### Orientation — the trap

The source is a portrait iPhone video. It is stored as **landscape 1920×1080
with a `-90` rotation matrix**; portrait-ness exists only in that matrix. This
is what every iPhone produces.

The video object reports the **stored** geometry, not the display geometry:

```json
"width": 1920, "height": 1080, "rotation": -90
```

The HLS manifest reports the **display** geometry, correctly rotated:

```
RESOLUTION=360x640 / 480x854 / 720x1280 / 1080x1920
```

So Bunny rotates the renditions properly — playback is upright, verified both
by `AVPlayer` and by eye on a decoded frame. But **Phase 11 must not put the
API's `width`/`height` into `imeta dim=`**, or every portrait video will be
advertised to other nostr clients as `1920x1080` and lay out sideways in
timelines that trust `dim`. Either swap the axes when `|rotation|` is 90 or 270,
or read `RESOLUTION` from the master playlist.

## TUS upload — what Bunny really does

Signature, confirmed against a live server and matching current docs:

```
AuthorizationSignature = sha256(libraryId + apiKey + expirationTime + videoId)
```

sent with `AuthorizationExpire` (unix seconds), `LibraryId`, `VideoId` to
`https://video.bunnycdn.com/tusupload`. Full transcript:
[`tus-protocol-transcript.log`](bunny-stream-spike/tus-protocol-transcript.log).

The real upload: **310,964,852 bytes in 38 × 8 MB chunks in 35 s, zero retries.**

Answering the four questions the card raised about
`damus/Shared/Media/Upload/Tus/`:

1. **Does Bunny return `Upload-Offset` on every PATCH?** **Yes** — all 38
   PATCHes returned `204` with `upload-offset`. `missing_offset_headers=0`. The
   client's re-`HEAD` fallback is never exercised against Bunny, but is
   harmless.
2. **Is `Location` absolute or relative?** **Relative**:
   `/tusupload/<32-hex>`. The client already resolves it against the creation
   endpoint via `URL(string:relativeTo:)`, so this works — but it is the
   relative branch that runs in production, and that is the branch worth having
   a test on. Note the TUS resource id is **not** the video GUID.
3. **What does Bunny do when the signature expires mid-upload?** See below —
   **this one contradicts the client.**
4. **What chunk size?** 8 MB was accepted with no complaint and no
   `Tus-Max-Size` pushback; 4 MB also fine. No reason to change the client's
   default.

Bunny also returns an `Upload-Expires` response header (an HTTP-date mirroring
`AuthorizationExpire`) on both creation and every PATCH. The client currently
ignores it. It is the cleanest possible signal for "re-authorize now" — see the
recommendation below.

### Authorization failures: the client maps the wrong status

Measured ([`tus-auth-behaviour.log`](bunny-stream-spike/tus-auth-behaviour.log)):

| Situation | Bunny's answer |
| --- | --- |
| Wrong/forged signature, on create | `401 Unauthorized`, empty body |
| **Signature expired, PATCH mid-upload** | **`400 Bad Request`**, body `Invalid expiry time, cannot be in the past.` |
| Signature expired, then `HEAD` | `400` |
| After expiry, `HEAD` with a freshly minted signature | `404 Not Found` — the session is gone |
| **Re-minted signature *before* expiry, same upload URL** | **works** — `HEAD` `200` with the right offset, `PATCH` `204` |

Two consequences:

**Mid-flight re-authorization is supported.** A signature minted with a later
`AuthorizationExpire` is accepted on the *same* TUS upload URL and resumes at
the correct offset. Phase 7 can refresh credentials without restarting the
upload. (The `404` above is expiry teardown, not signature identity — once the
window lapses the session is destroyed and the uploaded bytes are lost.)

**But the client will never notice.** `TusUploadClient.mapStatus` maps only
`401`/`403` to `.unauthorized` and `404`/`410` to `.uploadGone`; everything else
falls to `.server(status:)`, whose `needsReauthorization` is `false`. And
`TusRetryPolicy.forStatus(400)` is `.fatal`. So the **actual** Bunny expiry path
— a `400` on PATCH — is classified as a fatal, non-reauthorizable server error.
The upload dies with a generic message and Phase 7's re-authorization signal
never fires, on the one code path it exists for.

Recommended, in order:

1. **Refresh proactively.** Re-mint the signature well before
   `AuthorizationExpire` (Bunny hands us `Upload-Expires` on every response).
   Since resume-after-expiry is impossible but resume-before-expiry works
   perfectly, never reaching expiry is the whole fix.
2. **Also classify the failure**, as a backstop: a `400` whose body matches the
   expiry message should map to `.unauthorized`, not `.server`. Matching on a
   prose body is unpleasant, which is why (1) is the primary fix.
3. Mint generously — the docs recommend ≥ 1 hour, and an 850 MB upload on
   bad LTE can outlive a short window.

Tracked as `headway:damus-ios/spare-apart-zebra` rather than fixed here; this
phase is a spike.

## Playback in AVPlayer

Driven headlessly through `AVPlayerItem` + `AVPlayerItemVideoOutput` against the
public `https://video.damus.io/{video-id}/playlist.m3u8` URL (HLS exposes no
asset tracks and `AVAssetImageGenerator` refuses HLS, so orientation has to come
from `presentationSize` and real decoded buffers):

```
item.status=readyToPlay after 1.5s
presentationSize=360x640  -> PORTRAIT
duration=93.133s
-- preferredPeakBitRate=800000 --   currentTime=13.9s, decoded 360x640 PORTRAIT
-- cap lifted --                    currentTime=34.0s, decoded 1080x1920 PORTRAIT
access log indicatedBitrates: [1504884, 5078831, 8119498]
ADAPTIVE SWITCHING: YES     stalls: 0
```

Three distinct renditions were selected in one session (360p → 720p → 1080p),
playback advanced in real time, every decoded buffer was portrait, and there
were no stalls. Adaptive HLS from the public `video.damus.io` URL works, over
the Let's Encrypt certificate, with no credentials of any kind on the request —
which is the whole premise the epic rests on.

## The encoding webhook, as it actually behaves

Captured 2026-09-05 by pointing `WebhookUrl` at a logging receiver behind a
temporary public tunnel, across three encodes: a 20-second clip, a 4-minute
clip, and one against an endpoint that returned `500` to everything. Raw:
[`webhook-payloads.jsonl`](bunny-stream-spike/webhook-payloads.jsonl) ·
[`webhook-headers.txt`](bunny-stream-spike/webhook-headers.txt).

Synthetic `testsrc2` clips were used, not personal video.

### The payload

The entire body, 115 bytes:

```json
{"IsLiveStreamWebhook":false,"VideoLibraryId":123456,"VideoGuid":"<guid>","Status":0}
```

The documented shape plus an undocumented `IsLiveStreamWebhook`. **There is no
`storageSize`, no `availableResolutions`, no `width`/`height`, no
`encodeProgress`, no title, no duration.** Phase 5's own done-when — reconcile
quota against real stored bytes — and Phase 14's cost attribution both need
fields that are simply not in the payload. **Phase 5 must webhook-then-fetch.**

### Authentication

Bunny signs, which the docs did not lead us to expect:

```
X-Bunnystream-Signature: <64 hex chars>
X-Bunnystream-Signature-Algorithm: hmac-sha256
X-Bunnystream-Signature-Version: v1
```

Reproduced exactly, on all 21 captured POSTs:

```
signature = hex(HMAC_SHA256(key = library.ReadOnlyApiKey, msg = raw_request_body))
```

Note the key is the library's **`ReadOnlyApiKey`**, *not* `ApiKey` — both are
fields on the library object, and picking the wrong one fails closed in a way
that looks like Bunny being broken. Phase 5 must hold `ReadOnlyApiKey` and MAC
the **raw body bytes** before JSON parsing; re-serializing the parsed object
changes the bytes and the signature will not match.

There is **no timestamp and no nonce** in the payload or the headers, so the
signature proves authenticity but gives no replay protection at all. Duplicate
deliveries are byte-identical and therefore carry identical signatures. Replay
safety has to come from the row state machine, not from the signature.

### Delivery is duplicated and out of order — deterministically

Both real encodes produced exactly seven POSTs, in exactly this order:

```
Status=0   Created
Status=1   Uploaded
Status=1   Uploaded          (duplicate)
Status=2   Processing
Status=4   Finished
Status=4   Finished          (duplicate)
Status=3   Transcoding       <-- arrives AFTER Finished
```

The trailing `3` came 2.2 s after the `4` on the short clip and 5.7 s after on
the long one. This is not a race we happened to lose; it reproduced identically
on both encodes. **A receiver that does `row.status = payload.Status` moves a
finished video backwards into transcoding** — precisely the regression Phase 5's
done-when forbids, and it would happen on every single upload rather than
rarely.

`Status=1` is also worth noting: it never appears in the polled progression
(`0 → 2 → 3 → 4`), so the webhook enum surfaces states the status `GET` does
not.

### The webhook's `Status=4` leads the API

On the 4-minute clip the `Status=4` POST arrived at 21:57:02 while the status
`GET` still returned `status=3, encodeProgress=65` for a further **27 seconds**.
The short clip showed the same lead, ~3 s.

So a receiver that fetches immediately on the `4` doorbell can get `3` back and
conclude the video is not ready — and **there is no later terminal doorbell**,
because the final POST in the sequence is the out-of-order `3`.

**Consequence: the webhook cannot be relied on to deliver a final terminal
state.** Phase 5 needs a periodic reconcile sweep over rows sitting in
non-terminal states, as a backstop rather than an optimization. It is the
server-side mirror of the client-side foreground reconcile in Phase 10.

### There are no retries

With the receiver returning `500` to every POST, all seven were delivered
exactly once and never retried — confirmed by recounting five minutes after the
encode finished. **Bunny does not retry failed webhook deliveries.** A receiver
that is down, mid-deploy, or briefly erroring loses the notification outright.
That makes the reconcile sweep above mandatory, not defensive.

### The shape this implies for Phase 5

All of the above collapses into one rule:

> Verify the HMAC against the raw body, then **ignore `Status` entirely**. Treat
> the POST as nothing more than "something changed about this guid", fetch the
> authoritative video object from the API, and apply a monotonic state machine.
> Sweep periodically for rows stuck in non-terminal states.

That is replay-safe, reorder-safe, tolerant of the missing terminal doorbell,
tolerant of dropped deliveries, and immune to the payload gap — all at once, and
without a single special case.

## Readiness: what you may and may not probe

Phase 0 left open whether the public HLS manifest is a cheap readiness probe,
letting a client skip an authenticated status call. **It is not**, and it fails
in both directions. Measured on the 4-minute clip
([`manifest-readiness-timeline.log`](bunny-stream-spike/manifest-readiness-timeline.log)),
`t` relative to upload completion:

| t | `status` | `encodeProgress` | `availableResolutions` | public manifest | `RESOLUTION` lines in the body |
| --- | --- | --- | --- | --- | --- |
| 63.4 s | 3 | 40 | `360p` | `404` (`cdn-cache: HIT`) | — |
| **66.0 s** | 3 | 40 | `360p` | **`200`** | **`360x640` only** |
| 80.9 s | 3 | 65 | all four | `200` | `360x640` only |
| **85.9 s** | **4** | 100 | all four | `200` | `360x640` only *(stale)* |
| ~195 s | 4 | 100 | all four | `200` (revalidated) | all four |

Three separate hazards, all real:

1. **The manifest answers `200` about 20 s before the encode finishes, listing
   only 360p.** A client that publishes on manifest availability ships a note
   whose video has one 360p rendition. This is the premature-publish bug the
   spike warned about, now observed rather than hypothesized.
2. **It then lags completion by up to ~2 minutes.** The manifest was still
   advertising 360p-only at `status == 4`, held there by `cache-control: public,
   max-age=30` on the CDN plus whenever Bunny actually rewrites it.
3. **The pre-encode `404` is negative-cached.** Every pre-encode probe came back
   `cdn-cache: HIT` with `max-age=30`, so a probe can see a stale `404` for up
   to 30 s after the manifest genuinely exists.

`HEAD` specifically is the wrong instrument regardless of timing: it only proves
a manifest *exists*, while which renditions are in it lives in the body's
`EXT-X-STREAM-INF` / `RESOLUTION` lines. So `HEAD` cannot distinguish "360p
only, still encoding" from "full ladder, done" — the one distinction that
matters. It also saves nothing, the manifest being a few hundred bytes. (And
`HEAD` on Bunny's *video API* returns `405`, with no status in the response
headers, so that is not an alternative either.)

**`status == 4` from the authenticated video API is the only correct readiness
signal.** This confirms the epic's rule, for a stronger reason than it was
originally given.

**One consequence for Phase 11.** Since the CDN manifest lags `status == 4` by
up to ~2 minutes, publishing the instant status flips means the first clients to
fetch the note can get a manifest still advertising 360p only. It plays, so
nothing is broken, but early viewers get the worst rendition of a video the
author waited for. A cheap unauthenticated `GET` of the master playlist,
confirming its `RESOLUTION` set matches `availableResolutions` before
publishing, closes that window.

## 720p vs 1080p — the open decision

Per-rendition stored bytes, measured by summing the actual HLS segments for the
93-second sample ([`rendition-bytes.txt`](bunny-stream-spike/rendition-bytes.txt)):

| Rendition | Segments | Stored | Share of ladder |
| --- | --- | --- | --- |
| 360p | 24 | 10.05 MB | 8.5% |
| 480p | 24 | 16.21 MB | 13.7% |
| 720p | 24 | 29.66 MB | 25.0% |
| **1080p** | 24 | **62.72 MB** | **52.9%** |
| ladder total | | 118.64 MB | |

Library-reported `storageSize` for the finished video is **128,452,105 bytes**;
the ~10 MB above the segment sum is thumbnails (47), playlists and the preview.

Two framings of the same number:

- **1080p alone costs more than the other three renditions combined.** Dropping
  it takes the ladder from 118.6 MB to 55.9 MB — a **53% cut in stored bytes**,
  and a similar cut in delivered bytes for anyone whose player picks it.
- Source → stored is **310.9 MB → 128.5 MB (0.41×)** with 1080p, and roughly
  **0.21×** without. "One uploaded GB is not one stored GB" cuts both ways: with
  this ladder a GB uploaded is well under a GB stored.

Quality, measured against the source (both renditions normalized to 1080×1920):

| | PSNR (Y) | SSIM (Y) |
| --- | --- | --- |
| 720p upscaled vs source | 28.89 dB | 0.9450 |
| 1080p vs source | 28.84 dB | 0.9485 |
| 720p upscaled vs 1080p | 39.99 dB | 0.9838 |

1080p buys **+0.0035 SSIM** over 720p against the same source, and its PSNR is
marginally *lower* (within noise). A 1:1 crop of the highest-detail region of
the frame, displayed at equal size, is not visually distinguishable.

**Recommendation: ship v1 with a 720p ceiling.** It halves storage and delivery
for a difference this sample cannot show, and 1080p is a clean lever to sell
later as a higher Purple tier exactly as the epic anticipates.

**The honest caveat.** This is *one* 93-second sample: handheld, indoor, low
light, 59.88 fps VFR. Motion blur and sensor noise set the detail ceiling well
below what 1080p could carry, which is the condition most favourable to
dropping 1080p. A tripod-steady, well-lit, high-detail clip — or screen-recorded
text, which people do post — would favour 1080p more than this measurement
suggests. And the comparison here is objective metrics plus decoded frames on a
Mac, not an eyes-on A/B on a phone: on a 1170 px-wide iPhone screen a 1080×1920
rendition is roughly native while 720×1280 is upscaled ~1.6×, so full-screen
playback flatters 1080p more than an inline timeline does. If jb55 wants the
decision hardened before Phase 9, the cheap version is two or three more
samples across those conditions.

The library is currently configured **with** 1080p enabled, so nothing is
foreclosed; flipping `EnabledResolutions` to `360p,480p,720p` is a one-call
change that only affects future encodes.

## Not done

- Behaviour of `status` `5`/`6` (encode failure). Only the success path has been
  exercised, on the video object and on the webhook alike — so it is not known
  whether a failed encode even emits a webhook, nor what `transcodingMessages`
  carries on the error path. Phase 4/5 error handling would benefit from
  deliberately uploading a corrupt file; it is a few minutes' work with an
  ingress up.
- Whether the seven-POST webhook sequence holds for a *long* encode where
  renditions land minutes apart rather than seconds. Both captured encodes
  finished in under 90 s.
- `WebhookUrl` is back to `null`. The capture used a temporary tunnel that no
  longer exists; it must be pointed at the real Purple API in Phase 5.

//
//  PurpleVideoModels.swift
//  damus
//
//  The wire types for Damus Purple's hosted-video API: what `POST /video`,
//  `GET /video/{id}` and `DELETE /video/{id}` answer with.
//
//  Two decoding rules hold for every type in this file, and both are
//  load-bearing:
//
//  1. **Explicit `CodingKeys` everywhere, and never
//     `keyDecodingStrategy = .convertFromSnakeCase`.** Foundation applies a key
//     strategy to dictionary keys too, and its snake-case converter lowercases
//     the whole first underscore-delimited component — so `tus_headers`'
//     `AuthorizationSignature` would arrive as `authorizationsignature` and
//     every TUS upload would 401 with an empty body. `tus_headers` is the only
//     PascalCase object in the API, and it is a dictionary.
//  2. **Unix seconds, so the decoder uses `.secondsSince1970`.** A bare
//     `JSONDecoder()` defaults to `.deferredToDate`, which reads a number as
//     seconds since 2001 and silently lands every deadline 31 years early.
//     `PurpleVideoWire` owns the only decoder configured for these types.
//

import Foundation

/// A Bunny video GUID. The same string the TUS client keys its resume record
/// on (`TusUploadID`) and the same one a kind-9950 "video ready" push carries,
/// so one video is addressable by one identifier end to end.
typealias PurpleVideoID = String

// MARK: - Open enums

/// Where a video is, as the server reports it.
///
/// Open rather than exhaustive: an `unknown` case means a server that grows a
/// state does not break decoding on an app already in the App Store. Both
/// halves of that are deliberate — `init(rawValue:)` is non-failable so
/// nothing can throw on an unrecognised value, and `rawValue` hands the
/// server's own spelling back, so decoding and re-encoding a status is
/// lossless rather than quietly dropping a state this build never heard of.
///
/// `Codable` is written out rather than left to the stdlib's
/// `RawRepresentable` conformance: this is an enum with an associated value,
/// and Swift will synthesize a keyed `{"unknown": {"_0": "..."}}` encoding for
/// one of those given half a chance. An explicit single-value container is
/// eight lines and cannot drift.
///
/// There are deliberately **no** `isReady`/`isPublishable` conveniences here.
/// Publishability is `PurpleVideoStatus.publishable` and completion is
/// `PurpleVideoStatus.terminal`; a damaged encode reaches a full rendition
/// ladder and reports `.damaged` with `publishable: false`, so anything
/// derived from this enum would be the wrong test.
enum PurpleVideoState: RawRepresentable, Codable, Hashable, Sendable {
    /// A video object exists at the provider and a TUS signature has been
    /// handed out. No bytes yet.
    case authorized
    /// Bytes have started landing. Only ever reported via the provider's
    /// webhook, so a status `GET` does not return it in practice.
    case uploading
    /// The provider is processing or transcoding.
    case encoding
    /// A clean encode. The only status that comes with `publishable: true`.
    case ready
    /// The encode finished but the output is damaged. Server-synthesized: the
    /// row still says ready, and this is what stops the app publishing it.
    case damaged
    /// The provider gave up. Nothing was stored.
    case failed
    /// A reservation whose upload never arrived was reaped.
    case expired
    /// Tombstoned. `GET` answers 410 afterwards.
    case deleted
    /// A status this build does not know. Carries the server's spelling.
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "authorized": self = .authorized
        case "uploading": self = .uploading
        case "encoding": self = .encoding
        case "ready": self = .ready
        case "damaged": self = .damaged
        case "failed": self = .failed
        case "expired": self = .expired
        case "deleted": self = .deleted
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .authorized: return "authorized"
        case .uploading: return "uploading"
        case .encoding: return "encoding"
        case .ready: return "ready"
        case .damaged: return "damaged"
        case .failed: return "failed"
        case .expired: return "expired"
        case .deleted: return "deleted"
        case .unknown(let raw): return raw
        }
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// How bad one transcoding issue is.
///
/// Open for the same reason as `PurpleVideoState`, and `Codable` is written
/// out for the same reason too. An unrecognised severity ranks as `.damaged`:
/// conservative, since that shows as a warning, and it cannot become a hard
/// block because nothing gates publishing on severity.
enum PurpleVideoIssueSeverity: RawRepresentable, Codable, Hashable, Sendable {
    /// A note, not a problem. The variable-frame-rate notice fires on
    /// essentially every iPhone upload and must not read as an error.
    case info
    /// The provider finished anyway, but the output is incomplete.
    case damaged
    /// The provider could not process the upload at all.
    case fatal
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "info": self = .info
        case "damaged": self = .damaged
        case "fatal": self = .fatal
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .info: return "info"
        case .damaged: return "damaged"
        case .fatal: return "fatal"
        case .unknown(let raw): return raw
        }
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Whether this issue should read to a person as a problem rather than a note.
    var isProblem: Bool {
        switch self {
        case .info: return false
        case .damaged, .fatal: return true
        case .unknown: return true
        }
    }
}

// MARK: - Shared blocks

/// The subscriber's rolling hosted-video allowance.
///
/// Every number here is in **stored** bytes — what the encoded ladder occupies,
/// measured at roughly 0.21x of what was uploaded on the shipped 720p ladder.
/// The field names say so on purpose: putting these next to a file size from
/// the photo picker compares two different units.
struct PurpleVideoQuota: Codable, Equatable, Sendable {
    let usedStoredBytes: Int
    let limitStoredBytes: Int
    let remainingStoredBytes: Int
    let windowSeconds: Int

    enum CodingKeys: String, CodingKey {
        case usedStoredBytes = "used_stored_bytes"
        case limitStoredBytes = "limit_stored_bytes"
        case remainingStoredBytes = "remaining_stored_bytes"
        case windowSeconds = "window_seconds"
    }
}

/// The four header names the provider's TUS endpoint expects, verbatim.
///
/// PascalCase, and the values are all strings — the spike found that sending
/// `LibraryId` as a JSON number is answered with a bare 401 and an empty body.
/// The server hands over the assembled header set rather than the parts for
/// exactly that reason, so these constants exist for typed access and
/// validation, not for rebuilding the dictionary.
enum PurpleVideoTusHeaderKey {
    static let authorizationSignature = "AuthorizationSignature"
    static let authorizationExpire = "AuthorizationExpire"
    static let libraryId = "LibraryId"
    static let videoId = "VideoId"

    /// Every key an authorization must carry to be usable.
    static let required = [authorizationSignature, authorizationExpire, libraryId, videoId]
}

// MARK: - POST /video

/// What `POST /video` answers with: permission to upload one video, and
/// everything needed to start.
///
/// The playback URL is fully determined here, before a single byte is
/// uploaded, and never changes. Waiting for the encode is only about not
/// publishing a dead link.
struct PurpleVideoAuthorization: Codable, Equatable, Sendable {
    let videoId: PurpleVideoID
    /// A string, never a number — it is concatenated into the TUS signature
    /// server-side.
    let libraryId: String
    /// When the TUS signature stops working. Re-minting *before* this resumes
    /// the same upload at the right offset; after it, the provider destroys the
    /// session and the bytes already sent are gone.
    let expiry: Date
    let authorizationSignature: String
    /// Where to `POST` to create the TUS upload resource. See
    /// `PurpleVideoAuthorization.tusDestination`.
    let tusEndpoint: URL
    /// Ready to hand to `TusUploadClient.enqueue(headers:)` /
    /// `updateHeaders(for:headers:)` as-is. Validated by `PurpleVideoWire` to
    /// carry all four `PurpleVideoTusHeaderKey.required` keys.
    let tusHeaders: [String: String]
    let playbackURL: URL
    let thumbnailURL: URL
    /// When the server stops holding the reservation for an upload that never
    /// arrives. Always later than `expiry`.
    let uploadDeadline: Date
    /// The allowance *including* the reservation this call just made.
    let quota: PurpleVideoQuota

    enum CodingKeys: String, CodingKey {
        case videoId = "video_id"
        case libraryId = "library_id"
        case expiry
        case authorizationSignature = "authorization_signature"
        case tusEndpoint = "tus_endpoint"
        case tusHeaders = "tus_headers"
        case playbackURL = "playback_url"
        case thumbnailURL = "thumbnail_url"
        case uploadDeadline = "upload_deadline"
        case quota
    }
}

// MARK: - GET /video/{id}

/// One entry from the provider's transcoding log, in our words rather than
/// theirs — the server maps the code to copy a person can read.
struct PurpleVideoIssue: Codable, Equatable, Sendable {
    /// The provider's issue code. Null when the provider did not send one.
    let code: Int?
    let level: Int
    let severity: PurpleVideoIssueSeverity
    let message: String

    enum CodingKeys: String, CodingKey {
        case code, level, severity, message
    }
}

/// What `GET /video/{id}` answers with.
struct PurpleVideoStatus: Codable, Equatable, Sendable {
    let videoId: PurpleVideoID
    let status: PurpleVideoState
    /// **The one field to gate publishing on.** Not `status == .ready`, and
    /// certainly not `encodeProgress == 100`.
    let publishable: Bool
    /// **The completion test.** `encodeProgress` is not one: it freezes at 5 on
    /// a failed encode — not 0, not 100 — so anything written as
    /// `encodeProgress == 100` never fires on the failure path.
    let terminal: Bool
    /// Raw provider progress. Prefer `encodeProgressForDisplay`.
    let encodeProgress: Int?
    let encodeClean: Bool?
    /// A `Set`, not an array, because the provider fills this in incrementally
    /// and does not order it meaningfully — `480p,720p,360p` is a shape it
    /// really returns. Modelling it as a set makes indexing it unwriteable.
    let availableResolutions: Set<String>
    /// **Already a display dimension.** The server applies its own
    /// `display_dimensions_of` helper, so a portrait iPhone video reports
    /// 1080x1920 even though it is stored 1920x1080, and `rotation` never
    /// reaches the wire. The name says `display` so that re-rotating it here
    /// reads as the bug it would be.
    let displayWidth: Int?
    /// See `displayWidth`.
    let displayHeight: Int?
    /// Only on a clean encode. The provider's `length` is the source
    /// container's claim, not what it produced.
    let durationSeconds: Int?
    /// What the encoded ladder actually occupies, once the provider settles it.
    let storedBytes: Int?
    /// What the allowance is being charged, which is the reservation until
    /// `storedBytes` lands.
    let chargedStoredBytes: Int
    let issues: [PurpleVideoIssue]
    let playbackURL: URL
    let thumbnailURL: URL
    let title: String?
    let createdAt: Date
    let updatedAt: Date
    let uploadDeadline: Date
    /// The server wanted fresh numbers from the provider and could not get
    /// them, so everything above may be behind. **Not an error**: keep polling,
    /// show the last known state, show nothing to the user.
    let stale: Bool

    enum CodingKeys: String, CodingKey {
        case videoId = "video_id"
        case status
        case publishable
        case terminal
        case encodeProgress = "encode_progress"
        case encodeClean = "encode_clean"
        case availableResolutions = "available_resolutions"
        case displayWidth = "width"
        case displayHeight = "height"
        case durationSeconds = "duration_seconds"
        case storedBytes = "stored_bytes"
        case chargedStoredBytes = "charged_stored_bytes"
        case issues
        case playbackURL = "playback_url"
        case thumbnailURL = "thumbnail_url"
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case uploadDeadline = "upload_deadline"
        case stale
    }

    /// Progress to show a person, or nil when there is nothing left to wait for.
    ///
    /// Nil once `terminal`, which is what keeps a failed encode — frozen at 5%
    /// and finished — from rendering as a progress bar parked at 5% forever.
    var encodeProgressForDisplay: Int? {
        guard !terminal else { return nil }
        return encodeProgress
    }

    /// The tallest rendition the provider has produced so far, in lines
    /// (`"720p"` → `720`), or nil when none have landed.
    ///
    /// Exists so that nobody reaches into `availableResolutions` for an
    /// element it has no order to give.
    var highestAvailableResolutionLines: Int? {
        availableResolutions
            .compactMap { Int($0.hasSuffix("p") ? String($0.dropLast()) : $0) }
            .max()
    }
}

// MARK: - DELETE /video/{id}

/// What `DELETE /video/{id}` answers with. Idempotent: deleting twice is a 200
/// with `alreadyDeleted` set, not an error.
struct PurpleVideoDeletion: Codable, Equatable, Sendable {
    let videoId: PurpleVideoID
    let status: PurpleVideoState
    let deleted: Bool
    /// True when this call found the work already done. Nothing has to branch
    /// on it — that is the point of the route being idempotent — but it makes a
    /// retry legible in a log.
    let alreadyDeleted: Bool
    let deletedAt: Date?
    /// Deleting does **not** refund stored bytes inside the rolling window.
    /// This is here so the app shows the real allowance rather than assuming
    /// one.
    let chargedStoredBytes: Int
    let quota: PurpleVideoQuota

    enum CodingKeys: String, CodingKey {
        case videoId = "video_id"
        case status
        case deleted
        case alreadyDeleted = "already_deleted"
        case deletedAt = "deleted_at"
        case chargedStoredBytes = "charged_stored_bytes"
        case quota
    }
}

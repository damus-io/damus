//
//  PendingVideo.swift
//  damus
//
//  The durable record of a video the user has authorized but not yet
//  published.
//
//  This record is the *mechanism* by which someone learns their video is
//  ready, not a cache of one. A push from Purple is only a latency
//  optimisation; the reliable path is that the app comes back to the
//  foreground, reads these records and asks the API where each one got to. So
//  the record has to survive an app kill, and reconciling it has to produce one
//  outcome no matter how many times, or from how many directions, it happens.
//
//  Scope: this file and `PendingVideoStore` are the record and its state
//  machine. The triggers (foreground, composer open, upload completion), the
//  polling and backoff policy, garbage collection and every piece of UX are
//  Phase 9 and Phase 10.
//

import Foundation

/// Where a pending video is, as *this device* understands it.
///
/// A monotonic ladder, mirroring the server's own status machine. Rank is what
/// makes a push and a foreground poll racing the same guid converge: a state
/// can only ever move up, so applying the same response twice, or two
/// responses out of order, lands in the same place.
///
/// This is not `PurpleVideoState`. That one is the server's vocabulary and is
/// open, because a server may grow a state; this one is closed, local, and has
/// two states the server has no opinion about — `published` and `abandoned`.
enum PendingVideoState: String, Codable, Sendable, CaseIterable {
    /// Authorized, no bytes sent yet.
    case authorized
    /// Bytes are moving.
    case uploading
    /// Every byte is at the provider; it is transcoding.
    case encoding
    /// A clean encode. Safe to publish.
    case ready
    /// The encode finished, but the output is damaged. Do not publish.
    case damaged
    /// The provider could not encode it.
    case failed
    /// The reservation lapsed before the bytes arrived.
    case expired
    /// The note carrying this video has been posted.
    case published
    /// The user gave up on it, or it was deleted.
    case abandoned

    /// How far along the ladder this state is. State only ever moves to a
    /// strictly higher rank.
    var rank: Int {
        switch self {
        case .authorized: return 0
        case .uploading: return 1
        case .encoding: return 2
        case .ready, .damaged, .failed, .expired: return 3
        case .published, .abandoned: return 4
        }
    }

    /// Whether the server has nothing more to say about this video.
    ///
    /// Four different states share rank 3 precisely so that none of them can
    /// become another: a `failed` video never becomes `ready` because a stale
    /// response arrived late.
    var isTerminal: Bool { rank >= 3 }

    /// The local state a server response implies, or nil when the response
    /// says nothing this ladder can use.
    ///
    /// The order of these checks is the contract:
    ///
    /// 1. `publishable` — the publish gate, and the only correct one. A
    ///    damaged encode reaches a full rendition ladder and reports 100%
    ///    progress, so anything else here publishes broken video.
    /// 2. `terminal` — the completion test. `encodeProgress` is not one: it
    ///    freezes at 5 on a failed encode.
    /// 3. the status string, for the states still in flight.
    static func implied(by status: PurpleVideoStatus) -> PendingVideoState? {
        guard !status.publishable else { return .ready }

        guard !status.terminal else {
            switch status.status {
            case .damaged: return .damaged
            case .failed: return .failed
            case .expired: return .expired
            case .deleted: return .abandoned
            // Terminal in a way this build does not recognise. Guessing would
            // be worse than waiting: leave the record where it is.
            default: return nil
            }
        }

        switch status.status {
        case .authorized: return .authorized
        case .uploading: return .uploading
        case .encoding: return .encoding
        default: return nil
        }
    }
}

/// One authorized-but-unpublished video, as it survives an app kill.
struct PendingVideo: Codable, Equatable, Sendable {
    /// The provider's guid. The same string `TusUploadRecord.id` uses and the
    /// same one a "video ready" push carries, so every part of the feature
    /// resolves against one key.
    let videoId: PurpleVideoID
    /// Known at authorize time, before a byte is uploaded, and never changes.
    let playbackURL: URL
    let thumbnailURL: URL
    /// The local file being uploaded.
    ///
    /// `TusSourceFile` rather than a path, because an iOS container path
    /// contains a UUID that changes across installs; it re-anchors on the way
    /// back out. Kept even after a failure, so a retry is possible.
    var asset: TusSourceFile
    /// The NIP-37 `d`-tag of the draft this video belongs to, or nil when it
    /// is not attached to one yet.
    ///
    /// A **reference**, never a copy. `DraftArtifacts` says in its own
    /// docstring that it is not `Codable` — `NSMutableAttributedString` is the
    /// bottleneck — and that encoding it is "lossy, and is not fully
    /// round-trippable". Embedding one here would fork the truth and lose the
    /// user's text; the draft itself lives in nostrdb where it already does.
    ///
    /// **Phase 9 requirement:** the draft must be saved, and its id known,
    /// before `authorizeUpload` is called. A dangling id is worse than none.
    /// Nothing here notices a draft that has since been deleted — that is
    /// Phase 10/11's.
    var composerDraftID: String?
    var state: PendingVideoState
    /// When the TUS signature stops working. Past this, the provider destroys
    /// the upload session and any bytes already sent are gone.
    var expiry: Date
    /// When the server stops holding the reservation. Always later than
    /// `expiry`.
    var uploadDeadline: Date
    let createdAt: Date
    /// When this record was last reconciled against the API. Phase 10 backs off
    /// on it so that rapid app-switching does not hammer the status route.
    var lastCheckedAt: Date?

    /// Starts a record from a fresh authorization.
    init(
        authorization: PurpleVideoAuthorization,
        asset: URL,
        composerDraftID: String? = nil,
        now: Date = Date()
    ) {
        self.videoId = authorization.videoId
        self.playbackURL = authorization.playbackURL
        self.thumbnailURL = authorization.thumbnailURL
        self.asset = TusSourceFile(url: asset)
        self.composerDraftID = composerDraftID
        self.state = .authorized
        self.expiry = authorization.expiry
        self.uploadDeadline = authorization.uploadDeadline
        self.createdAt = now
        self.lastCheckedAt = nil
    }

    // MARK: - The state machine

    /// Whether the ladder allows this move.
    ///
    /// Strictly greater, so re-applying the current state is a no-op by
    /// construction and two terminal states can never replace one another.
    func canTransition(to next: PendingVideoState) -> Bool {
        next.rank > state.rank
    }

    /// Moves the record forward, or leaves it exactly as it was.
    ///
    /// - Returns: whether anything moved.
    @discardableResult
    mutating func advance(to next: PendingVideoState, now: Date = Date()) -> Bool {
        guard canTransition(to: next) else { return false }
        state = next
        lastCheckedAt = now
        return true
    }

    /// Reconciles this record against a status response.
    ///
    /// Guard order here is the design, not a style choice:
    ///
    /// 1. A response for a different guid is not ours — `nil`, so a caller
    ///    cannot quietly fold one video's state into another's.
    /// 2. `lastCheckedAt` always moves, so backoff works even when nothing
    ///    else does.
    /// 3. **A stale response changes nothing else.** The server could not
    ///    reach the provider and answered from its own row, so keeping the
    ///    last known state and reporting no error is the correct behaviour —
    ///    and putting the guard here makes that structural rather than
    ///    something every caller has to remember.
    ///
    /// - Returns: the reconciled record, or nil if the response is for a
    ///   different video. Compare `state` with the original to know whether it
    ///   moved.
    func folding(_ status: PurpleVideoStatus, now: Date = Date()) -> PendingVideo? {
        guard status.videoId == videoId else { return nil }

        var updated = self
        updated.lastCheckedAt = now

        guard !status.stale else { return updated }

        guard let implied = PendingVideoState.implied(by: status) else { return updated }
        updated.advance(to: implied, now: now)
        return updated
    }

    // MARK: - Credentials

    /// Whether the credentials this record carries can still be used.
    ///
    /// Named for what it means: past `expiry` the provider has destroyed the
    /// upload session and the bytes already sent are unrecoverable, so the
    /// answer is to abandon and re-mint, not to refresh. The API has no
    /// re-mint route today — see `PurpleVideoAPIClient` — so for now this is a
    /// signal to start over with a new authorization.
    func requiresFreshReservation(now: Date = Date()) -> Bool {
        now >= expiry
    }
}

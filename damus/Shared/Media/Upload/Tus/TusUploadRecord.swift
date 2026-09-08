//
//  TusUploadRecord.swift
//  damus
//
//  Created by Daniel D'Aquino on 2026-09-05.
//
//  The durable description of one in-flight upload. This is what has to survive
//  an app kill for a resume to be possible at all.
//

import Foundation

typealias TusUploadID = String

/// A reference to the local file being uploaded that survives an app reinstall
/// or OS upgrade.
///
/// An iOS app's container path contains a UUID that changes out from under us,
/// so persisting the absolute URL of a file in our own sandbox produces a path
/// that no longer exists on the next launch. We store the path relative to the
/// home directory when the file is inside the container and re-anchor it on the
/// way back out.
struct TusSourceFile: Codable, Equatable, Sendable {
    /// Path relative to `NSHomeDirectory()`, when the file lives in the container.
    private let relativeToHome: String?
    /// The path as it was when the record was written. Used verbatim for files
    /// outside the container, and as a fallback.
    private let recordedPath: String

    init(url: URL) {
        let path = url.standardizedFileURL.path
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        let homePrefix = home.hasSuffix("/") ? home : home + "/"
        self.recordedPath = path
        self.relativeToHome = path.hasPrefix(homePrefix) ? String(path.dropFirst(homePrefix.count)) : nil
    }

    /// The file's location on this launch.
    var url: URL {
        guard let relativeToHome else { return URL(fileURLWithPath: recordedPath) }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(relativeToHome)
    }

    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
}

/// Where an upload is in its lifecycle.
enum TusUploadPhase: String, Codable, Sendable {
    /// Recorded but not started, or explicitly paused.
    case paused
    /// We want bytes moving. A record can be `.uploading` with no live task —
    /// that is exactly the app-was-killed case, and what `resumeAll()` looks for.
    case uploading
    /// Every byte is on the server.
    case completed
    /// Stopped on an error the client cannot resolve on its own.
    case failed
}

/// A chunk we handed to the background session and have not heard back about.
///
/// Persisted so that a relaunch can reclaim the temp file (and adopt the task
/// that is still uploading it) instead of leaking it.
struct TusPendingChunk: Codable, Equatable, Sendable {
    /// Byte offset in the source file where this chunk starts.
    let offset: Int64
    let length: Int
    /// File name (not path) of the chunk inside the client's scratch directory.
    let fileName: String
}

/// Everything needed to resume an upload from a cold start.
struct TusUploadRecord: Codable, Equatable, Sendable {
    /// Caller-assigned id. For Purple video this is the Bunny video GUID, so a
    /// record can be tied back to the note the user is composing.
    let id: TusUploadID
    var source: TusSourceFile
    /// Where to `POST` to create the upload, when the caller did not already
    /// have an upload URL. Nil once `uploadURL` is known.
    var creationEndpoint: URL?
    /// The tus resource. Bunny/Purple hand this to us directly; otherwise it is
    /// the `Location` from creation.
    var uploadURL: URL?
    var totalBytes: Int64
    /// The highest offset the *server* has confirmed. Treated as a hint only —
    /// a `HEAD` always wins.
    var confirmedOffset: Int64
    /// Caller-supplied authorization/metadata headers.
    ///
    /// These are persisted so an upload can resume without a round trip, but
    /// they are short-lived by design (Bunny's signature carries an expiry), so
    /// a resume much later will 401 and surface `needsReauthorization`. Callers
    /// refresh them with `TusUploadClient.updateHeaders(for:headers:)`.
    var headers: [String: String]
    /// `Upload-Metadata` pairs, sent at creation time.
    var metadata: [String: String]
    var chunkSize: Int
    var phase: TusUploadPhase
    /// Consecutive failed attempts; reset by any chunk that lands.
    var attempt: Int
    var lastErrorDescription: String?
    var pendingChunk: TusPendingChunk?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: TusUploadID,
        source: URL,
        creationEndpoint: URL? = nil,
        uploadURL: URL? = nil,
        totalBytes: Int64,
        headers: [String: String] = [:],
        metadata: [String: String] = [:],
        chunkSize: Int,
        now: Date = Date()
    ) {
        self.id = id
        self.source = TusSourceFile(url: source)
        self.creationEndpoint = creationEndpoint
        self.uploadURL = uploadURL
        self.totalBytes = totalBytes
        self.confirmedOffset = 0
        self.headers = headers
        self.metadata = metadata
        self.chunkSize = chunkSize
        self.phase = .paused
        self.attempt = 0
        self.lastErrorDescription = nil
        self.pendingChunk = nil
        self.createdAt = now
        self.updatedAt = now
    }

    var isFinished: Bool { confirmedOffset >= totalBytes && totalBytes > 0 }

    var fractionComplete: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(confirmedOffset) / Double(totalBytes))
    }

    /// Byte range of the next chunk to send, or nil when there is nothing left.
    func nextChunkRange() -> (offset: Int64, length: Int)? {
        let remaining = totalBytes - confirmedOffset
        guard remaining > 0 else { return nil }
        return (confirmedOffset, Int(min(Int64(chunkSize), remaining)))
    }
}

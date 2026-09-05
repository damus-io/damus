//
//  TusUploadError.swift
//  damus
//
//  Created by Daniel D'Aquino on 2026-09-05.
//

import Foundation

enum TusUploadError: Error, LocalizedError {
    /// The local asset is gone (user deleted it, or the temp export was reaped).
    case sourceFileMissing(URL)
    case sourceFileUnreadable(URL, underlying: String)
    /// The source shrank between enqueue and the read of a chunk.
    case sourceFileTruncated(expected: Int, got: Int)
    /// The creation `POST` did not answer 201, or answered without a `Location`.
    case creationFailed(status: Int)
    case missingLocationHeader
    /// A `HEAD` came back without an `Upload-Offset`, so we cannot resume safely.
    case missingOffsetHeader
    /// The server reports more bytes than the file has — the upload URL is being
    /// reused for a different file.
    case offsetBeyondFile(serverOffset: Int64, totalBytes: Int64)
    /// 401/403: the caller's authorization has expired and must be re-minted.
    case unauthorized(status: Int)
    /// 404/410: the upload resource no longer exists; a new one must be created.
    case uploadGone(status: Int)
    case server(status: Int)
    case transport(String)
    case retryLimitExceeded(attempts: Int, lastError: String?)
    case cancelled

    /// Whether the caller has to obtain a fresh upload authorization before this
    /// can be retried. Phase 7's Purple client is what answers that.
    var needsReauthorization: Bool {
        switch self {
        case .unauthorized, .uploadGone: return true
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .sourceFileMissing(let url):
            return "The video file is no longer available at \(url.lastPathComponent)."
        case .sourceFileUnreadable(let url, let underlying):
            return "Could not read \(url.lastPathComponent): \(underlying)"
        case .sourceFileTruncated(let expected, let got):
            return "The video file changed while uploading (expected \(expected) bytes, read \(got))."
        case .creationFailed(let status):
            return "The server refused to start the upload (HTTP \(status))."
        case .missingLocationHeader:
            return "The server started the upload but did not say where to send it."
        case .missingOffsetHeader:
            return "The server did not report how much of the upload it has."
        case .offsetBeyondFile(let serverOffset, let totalBytes):
            return "The server reports \(serverOffset) bytes for a \(totalBytes) byte file."
        case .unauthorized(let status):
            return "The upload authorization has expired (HTTP \(status))."
        case .uploadGone(let status):
            return "The upload no longer exists on the server (HTTP \(status))."
        case .server(let status):
            return "The server returned HTTP \(status)."
        case .transport(let message):
            return message
        case .retryLimitExceeded(let attempts, let lastError):
            return "Gave up after \(attempts) attempts. \(lastError ?? "")"
        case .cancelled:
            return "The upload was cancelled."
        }
    }
}

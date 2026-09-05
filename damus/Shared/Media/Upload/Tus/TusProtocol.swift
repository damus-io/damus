//
//  TusProtocol.swift
//  damus
//
//  Created by Daniel D'Aquino on 2026-09-05.
//
//  The wire-level half of a tus 1.0.0 resumable upload client: header names,
//  request construction, response parsing and the retry policy.
//
//  Everything in this file is pure — no URLSession, no disk, no clock — so the
//  fiddly parts of the spec (metadata encoding, offset negotiation, which
//  statuses are worth retrying) can be unit tested without a server.
//
//  Spec: https://tus.io/protocols/resumable-upload
//

import Foundation

/// tus 1.0.0 wire constants.
enum Tus {
    static let version = "1.0.0"

    enum Header {
        static let resumable = "Tus-Resumable"
        static let uploadOffset = "Upload-Offset"
        static let uploadLength = "Upload-Length"
        static let uploadMetadata = "Upload-Metadata"
        static let contentType = "Content-Type"
        static let contentLength = "Content-Length"
        static let location = "Location"
        static let methodOverride = "X-HTTP-Method-Override"
    }

    /// The body content type every PATCH must carry.
    static let offsetOctetStream = "application/offset+octet-stream"
}

/// Builds the four requests a tus client ever makes.
///
/// `headers` is whatever the caller needs to authenticate — for Bunny Stream
/// that is the `AuthorizationSignature`/`AuthorizationExpire`/`LibraryId`/
/// `VideoId` set handed down by the Purple authorization endpoint. We never
/// interpret them, we just attach them.
enum TusRequest {
    /// `POST` to the creation endpoint, which answers with a `Location` pointing
    /// at the new upload resource.
    ///
    /// Bunny pre-creates the resource for us, so this is only used when the
    /// caller supplies a creation endpoint instead of an upload URL.
    static func creation(endpoint: URL, length: Int64, metadata: [String: String], headers: [String: String]) -> URLRequest {
        var request = base(url: endpoint, headers: headers)
        request.httpMethod = "POST"
        request.setValue(String(length), forHTTPHeaderField: Tus.Header.uploadLength)
        if let encoded = encodeMetadata(metadata) {
            request.setValue(encoded, forHTTPHeaderField: Tus.Header.uploadMetadata)
        }
        return request
    }

    /// `HEAD` the upload resource to ask the server how much it actually has.
    ///
    /// This is the authoritative answer: our persisted offset is only ever a
    /// hint, because the process can die between a chunk landing on the server
    /// and us recording it.
    static func head(uploadURL: URL, headers: [String: String]) -> URLRequest {
        var request = base(url: uploadURL, headers: headers)
        request.httpMethod = "HEAD"
        // A HEAD response must never be served from cache or we would resume
        // from a stale offset.
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return request
    }

    /// `PATCH` one chunk of the file at `offset`.
    static func patch(uploadURL: URL, offset: Int64, contentLength: Int, headers: [String: String]) -> URLRequest {
        var request = base(url: uploadURL, headers: headers)
        request.httpMethod = "PATCH"
        request.setValue(String(offset), forHTTPHeaderField: Tus.Header.uploadOffset)
        request.setValue(Tus.offsetOctetStream, forHTTPHeaderField: Tus.Header.contentType)
        request.setValue(String(contentLength), forHTTPHeaderField: Tus.Header.contentLength)
        return request
    }

    /// `DELETE` the upload resource (tus termination extension), so a cancelled
    /// upload does not leave a half-written object sitting in the bucket.
    static func termination(uploadURL: URL, headers: [String: String]) -> URLRequest {
        var request = base(url: uploadURL, headers: headers)
        request.httpMethod = "DELETE"
        return request
    }

    private static func base(url: URL, headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        // Caller headers go on first so we always win on the tus-owned ones.
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.setValue(Tus.version, forHTTPHeaderField: Tus.Header.resumable)
        return request
    }

    /// Encode `Upload-Metadata` per the spec: comma-separated `key base64(value)`
    /// pairs. Keys containing a space or comma are unrepresentable and dropped
    /// rather than silently corrupting the header.
    static func encodeMetadata(_ metadata: [String: String]) -> String? {
        let pairs = metadata
            .filter { !$0.key.isEmpty && !$0.key.contains(" ") && !$0.key.contains(",") }
            // Sorted so the header is stable across runs, which makes it
            // testable and keeps request signing reproducible.
            .sorted { $0.key < $1.key }
            .map { key, value -> String in
                let encoded = Data(value.utf8).base64EncodedString()
                // An empty value is a valid metadata key with no value.
                return encoded.isEmpty ? key : "\(key) \(encoded)"
            }
        return pairs.isEmpty ? nil : pairs.joined(separator: ",")
    }
}

/// Reads the bits of a tus response we care about.
enum TusResponse {
    /// The server's authoritative byte offset.
    static func offset(from response: HTTPURLResponse) -> Int64? {
        guard let raw = response.value(forHTTPHeaderField: Tus.Header.uploadOffset) else { return nil }
        return Int64(raw.trimmingCharacters(in: .whitespaces))
    }

    /// The total length the server believes the upload to be, when it says.
    static func length(from response: HTTPURLResponse) -> Int64? {
        guard let raw = response.value(forHTTPHeaderField: Tus.Header.uploadLength) else { return nil }
        return Int64(raw.trimmingCharacters(in: .whitespaces))
    }

    /// The created upload resource. `Location` is allowed to be relative, so it
    /// is resolved against the creation endpoint.
    static func location(from response: HTTPURLResponse, relativeTo endpoint: URL) -> URL? {
        guard let raw = response.value(forHTTPHeaderField: Tus.Header.location)?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        return URL(string: raw, relativeTo: endpoint)?.absoluteURL
    }
}

/// How a failed attempt should be treated.
enum TusRetryPolicy {
    /// Give up: the caller has to do something (re-authorize, pick a new file).
    case fatal
    /// Try the same thing again after a backoff.
    case retry
    /// The server disagrees with us about the offset — re-`HEAD` before retrying.
    case resync

    /// Classify an HTTP status from a PATCH or HEAD.
    static func forStatus(_ status: Int) -> TusRetryPolicy {
        switch status {
        case 200...299:
            return .retry  // caller should not be asking; treat as benign retry
        case 409:
            // "Upload-Offset does not match" — our idea of the offset is stale.
            return .resync
        case 400, 401, 403, 404, 410, 412, 413, 415, 460:
            // Bad request, expired signature, resource gone, checksum mismatch,
            // too large: none of these get better by trying again.
            return .fatal
        case 408, 423, 429:
            // Timeout, locked (another client mid-PATCH), rate limited.
            return .retry
        case 500...599:
            return .retry
        default:
            return .fatal
        }
    }
}

/// Exponential backoff with proportional jitter.
///
/// The randomness is injected rather than drawn internally so the schedule is
/// deterministic under test.
struct TusBackoff: Equatable {
    var base: TimeInterval = 1
    var multiplier: Double = 2
    var maxDelay: TimeInterval = 60
    /// Fraction of the delay that jitter may subtract, in `0...1`.
    var jitter: Double = 0.25

    /// Delay before attempt number `attempt` (1 = the first retry).
    ///
    /// - Parameter randomness: a value in `0...1`; 0 applies the full jitter
    ///   reduction, 1 applies none. Callers pass `Double.random(in: 0...1)`.
    func delay(forAttempt attempt: Int, randomness: Double) -> TimeInterval {
        guard attempt >= 1 else { return 0 }
        let uncapped = base * pow(multiplier, Double(attempt - 1))
        let capped = min(uncapped, maxDelay)
        let clampedJitter = min(max(jitter, 0), 1)
        let clampedRandomness = min(max(randomness, 0), 1)
        return capped * (1 - clampedJitter * (1 - clampedRandomness))
    }
}

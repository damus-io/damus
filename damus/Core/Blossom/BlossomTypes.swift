//
//  BlossomTypes.swift
//  damus
//
//  Created by Claude on 2025-01-15.
//
//  Core types for Blossom media server protocol (BUD-01, BUD-02).
//  Blossom is a specification for storing blobs on media servers using
//  nostr public/private keys for authentication.
//
//  See: https://github.com/hzrd149/blossom
//

import Foundation

// MARK: - Blossom Server URL

/// A validated URL wrapper for Blossom media servers.
/// Similar to RelayURL but for Blossom servers.
struct BlossomServerURL: Hashable, Codable, Sendable {
    let url: URL

    /// The normalized string representation of the server URL.
    /// Ensures trailing slash is removed for consistency.
    var absoluteString: String {
        var str = url.absoluteString
        if str.hasSuffix("/") {
            str.removeLast()
        }
        return str
    }

    init?(_ urlString: String) {
        guard let url = URL(string: urlString) else { return nil }

        // Require HTTPS for security - media uploads contain auth headers
        // and user data that should not be sent over plaintext HTTP
        guard url.scheme == "https" else { return nil }

        guard url.host != nil else { return nil }

        self.url = url
    }

    init?(url: URL) {
        self.init(url.absoluteString)
    }

    /// Returns the URL for the upload endpoint (PUT /upload per BUD-02).
    var uploadURL: URL {
        url.appendingPathComponent("upload")
    }

    /// Returns the URL for the media optimization endpoint (PUT /media per BUD-05).
    /// This endpoint allows servers to perform media transformations like
    /// resizing images or transcoding videos before storage.
    var mediaURL: URL {
        url.appendingPathComponent("media")
    }

    /// Returns the URL for retrieving a blob by its SHA256 hash.
    func blobURL(sha256: String, fileExtension: String? = nil) -> URL {
        var path = sha256
        if let ext = fileExtension {
            path += ".\(ext)"
        }
        return url.appendingPathComponent(path)
    }
}

// MARK: - Blob Descriptor

/// Response from a successful Blossom upload (BUD-02).
/// Contains metadata about the uploaded blob.
///
/// Example response:
/// ```json
/// {
///   "url": "https://cdn.example.com/b1674191...553.pdf",
///   "sha256": "b1674191a88ec5cdd733e4240a81803105dc412d6c6708d53ab94fc248f4f553",
///   "size": 184292,
///   "type": "application/pdf",
///   "uploaded": 1725105921
/// }
/// ```
struct BlossomBlobDescriptor: Codable, Sendable {
    /// Public URL to retrieve the blob
    let url: String

    /// SHA256 hash of the blob (hex-encoded)
    let sha256: String

    /// Size of the blob in bytes
    let size: Int64

    /// MIME type of the blob (e.g., "image/png", "video/mp4")
    let type: String

    /// Unix timestamp of when the blob was uploaded
    let uploaded: Int64
}

// MARK: - Errors

/// Errors that can occur during Blossom operations.
enum BlossomError: Error, LocalizedError {
    /// The server URL is invalid or malformed
    case invalidServerURL

    /// Failed to create authentication event
    case authenticationFailed

    /// The upload request failed (network error, timeout, etc.)
    case uploadFailed(underlying: Error?)

    /// Server rejected the upload with a reason
    case serverRejected(reason: String, statusCode: Int)

    /// Server response could not be parsed
    case invalidResponse

    /// No Blossom server configured in settings
    case noServerConfigured

    /// File data could not be read
    case fileReadError

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Invalid Blossom server URL"
        case .authenticationFailed:
            return "Failed to create authentication"
        case .uploadFailed(let underlying):
            if let err = underlying {
                return "Upload failed: \(err.localizedDescription)"
            }
            return "Upload failed"
        case .serverRejected(let reason, let statusCode):
            return "Server rejected upload (\(statusCode)): \(reason)"
        case .invalidResponse:
            return "Invalid server response"
        case .noServerConfigured:
            return "No Blossom server configured"
        case .fileReadError:
            return "Failed to read file data"
        }
    }
}

// MARK: - Upload Result

/// Result of a Blossom upload operation.
enum BlossomUploadResult: Sendable {
    case success(BlossomBlobDescriptor)
    case failed(BlossomError)

    /// Returns the uploaded URL if successful, nil otherwise.
    var uploadedURL: String? {
        switch self {
        case .success(let descriptor):
            return descriptor.url
        case .failed:
            return nil
        }
    }
}

//
//  MediaUploader.swift
//  damus
//
//  Created by Daniel D'Aquino on 2023-11-24.
//

import Foundation

/// Errors that can occur during media upload operations.
///
/// These errors provide specific, user-actionable information about upload failures
/// instead of generic error messages. Each case includes a `userMessage` property
/// that returns a localized, user-friendly description of the error.
enum UploadError: Error, LocalizedError {
    /// The server returned an error response with a message
    case serverError(message: String)

    /// Failed to parse the server's JSON response
    case jsonParsingFailed

    /// Server response was missing the expected URL field
    case missingURL

    /// Network request failed with an underlying error
    case networkError(underlying: Error)

    /// Failed to read the media file from disk
    case fileReadError(underlying: Error)

    /// The upload API URL is invalid
    case invalidAPIURL

    /// No media data available to upload
    case noMediaData

    /// HTTP error with status code (4xx client errors are non-retryable)
    case httpError(statusCode: Int, message: String)

    /// A user-friendly message describing the error.
    ///
    /// These messages are suitable for display in the UI and are localized.
    var userMessage: String {
        switch self {
        case .serverError(let message):
            return message
        case .jsonParsingFailed:
            return NSLocalizedString("Failed to process server response", comment: "Error when server response cannot be parsed")
        case .missingURL:
            return NSLocalizedString("Server did not return media URL", comment: "Error when upload succeeds but no URL returned")
        case .networkError(let underlying):
            return underlying.localizedDescription
        case .fileReadError(let underlying):
            return String(format: NSLocalizedString("Failed to read file: %@", comment: "Error when media file cannot be read"), underlying.localizedDescription)
        case .invalidAPIURL:
            return NSLocalizedString("Invalid upload service URL", comment: "Error when upload API URL is malformed")
        case .noMediaData:
            return NSLocalizedString("No media data to upload", comment: "Error when media data is missing")
        case .httpError(let statusCode, let message):
            return String(format: NSLocalizedString("Upload failed (HTTP %d): %@", comment: "Error when server returns HTTP error"), statusCode, message)
        }
    }

    var errorDescription: String? {
        return userMessage
    }

    /// Whether this error is transient and the upload should be retried.
    ///
    /// Retryable errors include network timeouts, connection losses, and server errors (5xx).
    /// Non-retryable errors include client errors (4xx), file issues, and explicit server rejections.
    var isRetryable: Bool {
        switch self {
        case .networkError(let underlying):
            // Check for transient network errors
            let nsError = underlying as NSError
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorTimedOut,
                     NSURLErrorCannotConnectToHost,
                     NSURLErrorNetworkConnectionLost,
                     NSURLErrorNotConnectedToInternet,
                     NSURLErrorDNSLookupFailed:
                    return true
                default:
                    return false
                }
            }
            return false
        case .serverError:
            // Server errors with messages are typically permanent (e.g., "file too large")
            return false
        case .jsonParsingFailed, .missingURL:
            // Could be transient server issue, worth one retry
            return true
        case .fileReadError, .invalidAPIURL, .noMediaData:
            // Local errors - retrying won't help
            return false
        case .httpError(let statusCode, _):
            // 4xx client errors are permanent, 5xx server errors are retryable
            return statusCode >= 500
        }
    }
}

protocol MediaUploaderProtocol: Identifiable {
    var nameParam: String { get }
    var mediaTypeParam: String { get }
    var supportsVideo: Bool { get }
    var requiresNip98: Bool { get }
    var postAPI: String { get }

    /// Extracts the uploaded media URL from the server's response data.
    ///
    /// - Parameter data: The raw response data from the upload server
    /// - Returns: A Result containing either the uploaded media URL string on success,
    ///            or an UploadError describing what went wrong on failure
    func getMediaURL(from data: Data) -> Result<String, UploadError>
    func mediaTypeValue(for mediaType: ImageUploadMediaType) -> String?
}

enum MediaUploader: String, CaseIterable, MediaUploaderProtocol, StringCodable {
    var id: String { self.rawValue }
    case nostrBuild
    case nostrcheck

    init?(from string: String) {
        guard let mu = MediaUploader(rawValue: string) else {
            return nil
        }

        self = mu
    }

    func to_string() -> String {
        return rawValue
    }

    var nameParam: String {
        switch self {
        case .nostrBuild:
            return "\"fileToUpload\""
        default:
            return "\"file\""
        }
    }

    var mediaTypeParam: String {
        return "media_type"
    }

    func mediaTypeValue(for mediaType: ImageUploadMediaType) -> String? {
        switch mediaType {
        case .normal:
            return nil
        case .profile_picture:
            return "avatar"
        }
    }

    var supportsVideo: Bool {
        switch self {
        case .nostrBuild:
            return true
        case .nostrcheck:
            return true
        }
    }

    var requiresNip98: Bool {
        switch self {
        case .nostrBuild:
            return true
        case .nostrcheck:
            return true
        }
    }

    struct Model: Identifiable, Hashable {
        var id: String { self.tag }
        var index: Int
        var tag: String
        var displayName : String
    }

    var model: Model {
        switch self {
        case .nostrBuild:
            return .init(index: -1, tag: "nostrBuild", displayName: "nostr.build")
        case .nostrcheck:
            return .init(index: 0, tag: "nostrcheck", displayName: "nostrcheck.me")
        }
    }

    var postAPI: String {
        switch self {
        case .nostrBuild:
            return "https://nostr.build/api/v2/nip96/upload"
        case .nostrcheck:
            return "https://nostrcheck.me/api/v2/media"
        }
    }

    /// Parses the upload server response and extracts the media URL.
    ///
    /// Handles NIP-96 compliant responses which contain a NIP-94 event with URL tags.
    /// Server error messages are captured and returned as typed errors for user display.
    ///
    /// - Parameter data: Raw JSON response data from the upload server
    /// - Returns: `.success(url)` with the uploaded media URL, or `.failure(error)` with details
    func getMediaURL(from data: Data) -> Result<String, UploadError> {
        // Log raw response for debugging (truncated to avoid log spam)
        if let responseString = String(data: data.prefix(500), encoding: .utf8) {
            Log.debug("Upload response body (first 500 chars): %{public}@", for: .image_uploading, responseString)
        }

        do {
            guard let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any],
                  let status = jsonObject["status"] as? String else {
                Log.error("Failed to parse JSON response or missing status field", for: .image_uploading)
                return .failure(.jsonParsingFailed)
            }

            Log.debug("Response status: %{public}@", for: .image_uploading, status)

            if status == "success", let nip94Event = jsonObject["nip94_event"] as? [String: Any] {
                if let tags = nip94Event["tags"] as? [[String]] {
                    for tagArray in tags {
                        if tagArray.count > 1, tagArray[0] == "url" {
                            return .success(tagArray[1])
                        }
                    }
                }
                Log.error("Success response but no URL tag found in nip94_event", for: .image_uploading)
                return .failure(.missingURL)
            } else if status == "error", let message = jsonObject["message"] as? String {
                Log.error("Server returned error: %{public}@", for: .image_uploading, message)
                return .failure(.serverError(message: message))
            } else {
                Log.error("Unexpected response status: %{public}@", for: .image_uploading, status)
                return .failure(.missingURL)
            }
        } catch {
            Log.error("JSON parsing exception: %{public}@", for: .image_uploading, error.localizedDescription)
            return .failure(.jsonParsingFailed)
        }
    }
}

//
//  AttachMediaUtility.swift
//  damus
//
//  Created by Swift on 2/17/23.
//

import SwiftUI
import UIKit
import CoreGraphics
import UniformTypeIdentifiers

/// Result of an image/video upload operation.
///
/// Contains either the uploaded media URL on success, or an `UploadError`
/// with specific details about what went wrong on failure.
enum ImageUploadResult {
    case success(String)
    case failed(UploadError)
}

enum ImageUploadMediaType {
    case normal
    case profile_picture
}

/// Configuration for upload retry behavior.
struct UploadRetryConfig {
    /// Maximum number of retry attempts (not counting the initial attempt)
    let maxRetries: Int
    /// Base delay between retries in seconds (doubles with each retry)
    let baseDelaySeconds: Double

    /// Default configuration: 2 retries with 1 second base delay (1s, 2s)
    static let `default` = UploadRetryConfig(maxRetries: 2, baseDelaySeconds: 1.0)

    /// No retries - fail immediately
    static let none = UploadRetryConfig(maxRetries: 0, baseDelaySeconds: 0)
}

protocol AttachMediaUtilityProtocol {
    static func create_upload_request(mediaToUpload: MediaUpload, mediaUploader: any MediaUploaderProtocol, mediaType: ImageUploadMediaType, progress: URLSessionTaskDelegate, keypair: Keypair?, session: URLSession) async -> ImageUploadResult
}

class AttachMediaUtility {
    fileprivate static func create_upload_body(mediaData: Data, boundary: String, mediaUploader: any MediaUploaderProtocol, mediaToUpload: MediaUpload, mediaType: ImageUploadMediaType) -> Data {
        let mediaTypeFieldValue = mediaUploader.mediaTypeValue(for: mediaType)
        let mediaTypeFieldEntry: String?
        if let mediaTypeFieldValue {
            mediaTypeFieldEntry = "; \(mediaUploader.mediaTypeParam)=\(mediaTypeFieldValue)"
        }
        else {
            mediaTypeFieldEntry = nil
        }
        let body = NSMutableData();
        let contentType = mediaToUpload.mime_type
        body.appendString(string: "Content-Type: multipart/form-data; boundary=\(boundary)\r\n\r\n")
        body.appendString(string: "--\(boundary)\r\n")
        body.appendString(string: "Content-Disposition: form-data; name=\(mediaUploader.nameParam); filename=\(mediaToUpload.genericFileName)\(mediaTypeFieldEntry ?? "")\r\n")
        body.appendString(string: "Content-Type: \(contentType)\r\n\r\n")
        body.append(mediaData as Data)
        body.appendString(string: "\r\n")
        body.appendString(string: "--\(boundary)--\r\n")
        return body as Data
    }

    /// Creates and executes an upload request for the given media with automatic retry.
    ///
    /// This method handles the complete upload flow:
    /// 1. Validates the upload API URL
    /// 2. Reads media data from disk
    /// 3. Constructs a multipart form-data request
    /// 4. Adds NIP-98 authentication if required
    /// 5. Executes the upload with progress tracking and retry on transient failures
    /// 6. Parses the server response for the uploaded URL
    ///
    /// - Parameters:
    ///   - mediaToUpload: The media file to upload (image or video)
    ///   - mediaUploader: The upload service configuration
    ///   - mediaType: Whether this is a normal upload or profile picture
    ///   - progress: Delegate for tracking upload progress
    ///   - keypair: Optional keypair for NIP-98 authentication
    ///   - retryConfig: Configuration for retry behavior (default: 2 retries with exponential backoff)
    ///   - session: URLSession to use for the upload (default: .shared, injectable for testing)
    /// - Returns: Upload result with the media URL on success, or typed error on failure
    static func create_upload_request(mediaToUpload: MediaUpload, mediaUploader: any MediaUploaderProtocol, mediaType: ImageUploadMediaType, progress: URLSessionTaskDelegate, keypair: Keypair? = nil, retryConfig: UploadRetryConfig = .default, session: URLSession = .shared) async -> ImageUploadResult {
        var mediaData: Data?

        Log.info("Starting upload: type=%{public}@, mime=%{public}@, api=%{public}@", for: .image_uploading,
                 mediaToUpload.is_image ? "image" : "video",
                 mediaToUpload.mime_type,
                 mediaUploader.postAPI)

        guard let url = URL(string: mediaUploader.postAPI) else {
            Log.error("Invalid API URL: %{public}@", for: .image_uploading, mediaUploader.postAPI)
            return .failed(.invalidAPIURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST";
        let boundary = "Boundary-\(UUID().description)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // If uploading to a media host that support NIP-98 authorization, add the header
        if mediaUploader.requiresNip98,
           let keypair,
            let method = request.httpMethod,
            let signature = create_nip98_signature(keypair: keypair, method: method, url: url) {
             request.setValue(signature, forHTTPHeaderField: "Authorization")
             Log.debug("Added NIP-98 authorization header", for: .image_uploading)
        }

        switch mediaToUpload {
        case .image(let url):
            do {
                mediaData = try Data(contentsOf: url)
            } catch {
                Log.error("Failed to read image file: %{public}@", for: .image_uploading, error.localizedDescription)
                return .failed(.fileReadError(underlying: error))
            }
        case .video(let url):
            do {
                mediaData = try Data(contentsOf: url)
            } catch {
                Log.error("Failed to read video file: %{public}@", for: .image_uploading, error.localizedDescription)
                return .failed(.fileReadError(underlying: error))
            }
        }

        guard let mediaData else {
            Log.error("No media data available after read", for: .image_uploading)
            return .failed(.noMediaData)
        }

        let fileSizeKB = Double(mediaData.count) / 1024.0
        let fileSizeMB = fileSizeKB / 1024.0
        Log.info("Media file size: %.2f KB (%.2f MB)", for: .image_uploading, fileSizeKB, fileSizeMB)

        request.httpBody = create_upload_body(mediaData: mediaData, boundary: boundary, mediaUploader: mediaUploader, mediaToUpload: mediaToUpload, mediaType: mediaType)

        // Execute upload with retry logic
        return await executeWithRetry(request: request, mediaUploader: mediaUploader, progress: progress, retryConfig: retryConfig, session: session)
    }

    /// Executes the upload request with retry logic for transient failures.
    ///
    /// - Parameters:
    ///   - request: The prepared URLRequest
    ///   - mediaUploader: The upload service for response parsing
    ///   - progress: Delegate for tracking upload progress
    ///   - retryConfig: Retry configuration
    ///   - session: URLSession to use for the upload
    /// - Returns: Upload result
    private static func executeWithRetry(request: URLRequest, mediaUploader: any MediaUploaderProtocol, progress: URLSessionTaskDelegate, retryConfig: UploadRetryConfig, session: URLSession) async -> ImageUploadResult {
        var lastError: UploadError?
        let maxAttempts = retryConfig.maxRetries + 1

        for attempt in 1...maxAttempts {
            if attempt > 1 {
                // Calculate exponential backoff delay
                let delaySeconds = retryConfig.baseDelaySeconds * pow(2.0, Double(attempt - 2))
                Log.info("Retry attempt %{public}d/%{public}d after %.1fs delay", for: .image_uploading, attempt, maxAttempts, delaySeconds)
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            }

            let result = await executeSingleUpload(request: request, mediaUploader: mediaUploader, progress: progress, session: session)

            switch result {
            case .success:
                if attempt > 1 {
                    Log.info("Upload succeeded on attempt %{public}d", for: .image_uploading, attempt)
                }
                return result
            case .failed(let error):
                lastError = error
                if error.isRetryable && attempt < maxAttempts {
                    Log.info("Retryable error on attempt %{public}d: %{public}@", for: .image_uploading, attempt, error.userMessage)
                    continue
                } else {
                    if attempt > 1 {
                        Log.error("Upload failed after %{public}d attempts: %{public}@", for: .image_uploading, attempt, error.userMessage)
                    }
                    return result
                }
            }
        }

        // Should not reach here, but return last error if we do
        return .failed(lastError ?? .networkError(underlying: NSError(domain: "AttachMediaUtility", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])))
    }

    /// Executes a single upload attempt.
    private static func executeSingleUpload(request: URLRequest, mediaUploader: any MediaUploaderProtocol, progress: URLSessionTaskDelegate, session: URLSession) async -> ImageUploadResult {
        do {
            let (data, response) = try await session.data(for: request, delegate: progress)

            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode
                Log.info("Upload response: HTTP %{public}d, size=%{public}d bytes", for: .image_uploading,
                         statusCode, data.count)

                // 4xx client errors are permanent failures - don't retry
                // (e.g., 400 Bad Request, 401 Unauthorized, 413 Payload Too Large)
                if statusCode >= 400 && statusCode < 500 {
                    // Try to extract error message from response body
                    if case .failure(let error) = mediaUploader.getMediaURL(from: data) {
                        Log.error("Client error HTTP %{public}d: %{public}@", for: .image_uploading, statusCode, error.userMessage)
                        return .failed(.httpError(statusCode: statusCode, message: error.userMessage))
                    }
                    Log.error("Client error HTTP %{public}d", for: .image_uploading, statusCode)
                    return .failed(.httpError(statusCode: statusCode, message: "HTTP \(statusCode) error"))
                }

                // 5xx server errors - extract message but return retryable httpError
                if statusCode >= 500 {
                    if case .failure(let error) = mediaUploader.getMediaURL(from: data) {
                        Log.error("Server error HTTP %{public}d: %{public}@", for: .image_uploading, statusCode, error.userMessage)
                        return .failed(.httpError(statusCode: statusCode, message: error.userMessage))
                    }
                    Log.error("Server error HTTP %{public}d", for: .image_uploading, statusCode)
                    return .failed(.httpError(statusCode: statusCode, message: "HTTP \(statusCode) server error"))
                }
            }

            switch mediaUploader.getMediaURL(from: data) {
            case .success(let url):
                Log.info("Upload successful: %{public}@", for: .image_uploading, url)
                return .success(url)
            case .failure(let error):
                Log.error("Upload failed: %{public}@", for: .image_uploading, error.userMessage)
                return .failed(error)
            }

        } catch {
            Log.error("Network error during upload: %{public}@", for: .image_uploading, error.localizedDescription)
            return .failed(.networkError(underlying: error))
        }
    }
}

extension NSMutableData {
    func appendString(string: String) {
        guard let data = string.data(using: String.Encoding.utf8, allowLossyConversion: true) else {
            return
        }
        append(data)
    }
}

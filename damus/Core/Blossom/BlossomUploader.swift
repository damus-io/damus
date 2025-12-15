//
//  BlossomUploader.swift
//  damus
//
//  Created by Claude on 2025-01-15.
//
//  Implements Blossom blob upload protocol (BUD-02).
//
//  Key differences from NIP-96 uploaders (nostr.build, nostrcheck):
//  - Uses PUT method (not POST)
//  - Sends raw binary body (not multipart form-data)
//  - Requires SHA256 hash of data for authorization
//  - Uses kind 24242 auth (not NIP-98 kind 27235)
//  - Returns blob descriptor JSON (not NIP-94 event)
//

import Foundation
import CommonCrypto

// MARK: - Blossom Uploader

/// Handles uploading blobs to Blossom servers.
///
/// Usage:
/// ```swift
/// let uploader = BlossomUploader()
/// let result = await uploader.upload(
///     data: imageData,
///     mimeType: "image/jpeg",
///     to: serverURL,
///     keypair: keypair
/// )
/// switch result {
/// case .success(let descriptor):
///     print("Uploaded to: \(descriptor.url)")
/// case .failed(let error):
///     print("Upload failed: \(error)")
/// }
/// ```
struct BlossomUploader {

    // MARK: - Upload

    /// Uploads a blob to a Blossom server.
    ///
    /// This method:
    /// 1. Computes SHA256 hash of the data
    /// 2. Creates a kind 24242 authorization event
    /// 3. Sends PUT request with raw binary body
    /// 4. Parses the blob descriptor response
    ///
    /// - Parameters:
    ///   - data: The raw binary data to upload
    ///   - mimeType: MIME type of the data (e.g., "image/jpeg")
    ///   - serverURL: The Blossom server to upload to
    ///   - keypair: User's keypair for authorization
    /// - Returns: Upload result with blob descriptor or error
    func upload(
        data: Data,
        mimeType: String,
        to serverURL: BlossomServerURL,
        keypair: Keypair
    ) async -> BlossomUploadResult {
        // Step 1: Compute SHA256 hash of the data
        // This is required for the authorization event's "x" tag
        let sha256Hex = computeSHA256Hex(data)

        // Step 2: Create Blossom authorization event
        guard let authBase64 = create_blossom_upload_auth(keypair: keypair, sha256Hex: sha256Hex) else {
            return .failed(.authenticationFailed)
        }

        // Step 3: Build the upload request
        var request = URLRequest(url: serverURL.uploadURL)
        request.httpMethod = "PUT"
        request.httpBody = data

        // Set headers per BUD-02:
        // - Content-Type: MIME type of the blob
        // - Content-Length: set automatically by URLSession
        // - Authorization: Nostr <base64_auth_event>
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(blossom_authorization_header(authBase64), forHTTPHeaderField: "Authorization")

        // Step 4: Execute the request
        let responseData: Data
        let response: URLResponse

        do {
            (responseData, response) = try await URLSession.shared.data(for: request)
        } catch {
            return .failed(.uploadFailed(underlying: error))
        }

        // Step 5: Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            return .failed(.invalidResponse)
        }

        // Check for error status codes
        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            // Try to get reason from X-Reason header or response body
            let reason = extractErrorReason(from: httpResponse, body: responseData)
            return .failed(.serverRejected(reason: reason, statusCode: httpResponse.statusCode))
        }

        // Step 6: Parse blob descriptor response
        guard let descriptor = parseBlossomResponse(responseData) else {
            return .failed(.invalidResponse)
        }

        return .success(descriptor)
    }

    // MARK: - Helpers

    /// Computes SHA256 hash of data and returns hex-encoded string.
    private func computeSHA256Hex(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Parses the Blossom blob descriptor from JSON response.
    private func parseBlossomResponse(_ data: Data) -> BlossomBlobDescriptor? {
        let decoder = JSONDecoder()
        return try? decoder.decode(BlossomBlobDescriptor.self, from: data)
    }

    /// Extracts error reason from response headers or body.
    ///
    /// Per BUD-01, servers should include X-Reason header on error responses.
    /// Falls back to parsing JSON error message or raw body text.
    private func extractErrorReason(from response: HTTPURLResponse, body: Data) -> String {
        // First try X-Reason header (per BUD-01)
        if let reason = response.value(forHTTPHeaderField: "X-Reason") {
            return reason
        }

        // Try to parse JSON error response
        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let message = json["message"] as? String {
            return message
        }

        // Fall back to raw body text
        if let text = String(data: body, encoding: .utf8), !text.isEmpty {
            return text
        }

        return "Unknown error"
    }
}

// MARK: - Convenience Extension

extension BlossomUploader {

    /// Uploads media from a URL (reads file data first).
    ///
    /// - Parameters:
    ///   - fileURL: Local file URL to upload
    ///   - mimeType: MIME type of the file
    ///   - serverURL: The Blossom server to upload to
    ///   - keypair: User's keypair for authorization
    /// - Returns: Upload result with blob descriptor or error
    func upload(
        fileURL: URL,
        mimeType: String,
        to serverURL: BlossomServerURL,
        keypair: Keypair
    ) async -> BlossomUploadResult {
        guard let data = try? Data(contentsOf: fileURL) else {
            return .failed(.fileReadError)
        }

        return await upload(data: data, mimeType: mimeType, to: serverURL, keypair: keypair)
    }
}

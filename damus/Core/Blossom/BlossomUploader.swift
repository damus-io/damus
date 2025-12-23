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
//  Large file support:
//  - Uses streaming SHA256 to avoid loading entire file into memory
//  - Uses URLSession.uploadTask(fromFile:) for memory-efficient uploads
//

import Foundation
import CommonCrypto

// MARK: - Streaming SHA256

/// Computes SHA256 hash of a file using streaming to avoid loading entire file into memory.
/// Reads the file in chunks (default 64KB) and updates the hash incrementally.
///
/// - Parameters:
///   - fileURL: URL of the file to hash
///   - chunkSize: Size of chunks to read (default 64KB)
/// - Returns: Hex-encoded SHA256 hash, or nil if file cannot be read
func computeStreamingSHA256(fileURL: URL, chunkSize: Int = 64 * 1024) -> String? {
    // Check file exists first - InputStream doesn't fail for non-existent files
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        return nil
    }

    guard let inputStream = InputStream(url: fileURL) else {
        return nil
    }

    inputStream.open()
    defer { inputStream.close() }

    // Check for open errors
    if inputStream.streamStatus == .error {
        return nil
    }

    var context = CC_SHA256_CTX()
    CC_SHA256_Init(&context)

    var buffer = [UInt8](repeating: 0, count: chunkSize)

    while inputStream.hasBytesAvailable {
        let bytesRead = inputStream.read(&buffer, maxLength: chunkSize)
        if bytesRead < 0 {
            // Read error
            return nil
        }
        if bytesRead == 0 {
            break
        }
        CC_SHA256_Update(&context, buffer, CC_LONG(bytesRead))
    }

    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    CC_SHA256_Final(&hash, &context)

    return hash.map { String(format: "%02x", $0) }.joined()
}

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
    ///   - progressDelegate: Optional delegate for upload progress tracking
    /// - Returns: Upload result with blob descriptor or error
    func upload(
        data: Data,
        mimeType: String,
        to serverURL: BlossomServerURL,
        keypair: Keypair,
        progressDelegate: URLSessionTaskDelegate? = nil
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
            (responseData, response) = try await URLSession.shared.data(for: request, delegate: progressDelegate)
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

// MARK: - Streaming File Upload

extension BlossomUploader {

    /// Uploads a file to a Blossom server using streaming.
    ///
    /// This method is optimized for large files (videos, etc.):
    /// - Uses streaming SHA256 to hash without loading entire file into memory
    /// - Uses URLSession.uploadTask(fromFile:) for memory-efficient upload
    ///
    /// - Parameters:
    ///   - fileURL: Local file URL to upload
    ///   - mimeType: MIME type of the file
    ///   - serverURL: The Blossom server to upload to
    ///   - keypair: User's keypair for authorization
    ///   - progressDelegate: Optional delegate for upload progress tracking
    /// - Returns: Upload result with blob descriptor or error
    func uploadFile(
        fileURL: URL,
        mimeType: String,
        to serverURL: BlossomServerURL,
        keypair: Keypair,
        progressDelegate: URLSessionTaskDelegate? = nil
    ) async -> BlossomUploadResult {
        // Step 1: Compute SHA256 hash using streaming (memory-efficient)
        guard let sha256Hex = computeStreamingSHA256(fileURL: fileURL) else {
            return .failed(.fileReadError)
        }

        // Step 2: Create Blossom authorization event
        guard let authBase64 = create_blossom_upload_auth(keypair: keypair, sha256Hex: sha256Hex) else {
            return .failed(.authenticationFailed)
        }

        // Step 3: Build the upload request
        var request = URLRequest(url: serverURL.uploadURL)
        request.httpMethod = "PUT"

        // Set headers per BUD-02
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(blossom_authorization_header(authBase64), forHTTPHeaderField: "Authorization")

        // Step 4: Execute the upload using file-based upload task (streams from disk)
        let responseData: Data
        let response: URLResponse

        do {
            let session = URLSession.shared
            (responseData, response) = try await session.upload(for: request, fromFile: fileURL, delegate: progressDelegate)
        } catch {
            return .failed(.uploadFailed(underlying: error))
        }

        // Step 5: Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            return .failed(.invalidResponse)
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            let reason = extractErrorReason(from: httpResponse, body: responseData)
            return .failed(.serverRejected(reason: reason, statusCode: httpResponse.statusCode))
        }

        // Step 6: Parse blob descriptor response
        guard let descriptor = parseBlossomResponse(responseData) else {
            return .failed(.invalidResponse)
        }

        return .success(descriptor)
    }

    /// Uploads media from a URL.
    ///
    /// For small files (<1MB), loads data into memory for simpler handling.
    /// For larger files, uses streaming upload for memory efficiency.
    ///
    /// - Parameters:
    ///   - fileURL: Local file URL to upload
    ///   - mimeType: MIME type of the file
    ///   - serverURL: The Blossom server to upload to
    ///   - keypair: User's keypair for authorization
    ///   - progressDelegate: Optional delegate for upload progress tracking
    /// - Returns: Upload result with blob descriptor or error
    func upload(
        fileURL: URL,
        mimeType: String,
        to serverURL: BlossomServerURL,
        keypair: Keypair,
        progressDelegate: URLSessionTaskDelegate? = nil
    ) async -> BlossomUploadResult {
        // Check file size to decide upload strategy
        let fileSize: Int64
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            fileSize = attributes[.size] as? Int64 ?? 0
        } catch {
            return .failed(.fileReadError)
        }

        // For files larger than 1MB, use streaming upload
        let oneMB: Int64 = 1024 * 1024
        if fileSize > oneMB {
            return await uploadFile(fileURL: fileURL, mimeType: mimeType, to: serverURL, keypair: keypair, progressDelegate: progressDelegate)
        }

        // For small files, load into memory (simpler, still efficient for small data)
        guard let data = try? Data(contentsOf: fileURL) else {
            return .failed(.fileReadError)
        }

        return await upload(data: data, mimeType: mimeType, to: serverURL, keypair: keypair, progressDelegate: progressDelegate)
    }
}

// MARK: - Mirroring (BUD-04)

extension BlossomUploader {

    /// Mirrors a blob from a remote URL to a Blossom server.
    ///
    /// This implements BUD-04: the server downloads the blob from the source URL
    /// and stores it locally. This is more efficient than re-uploading the data.
    ///
    /// - Parameters:
    ///   - sourceURL: The URL where the blob is currently hosted
    ///   - targetServer: The Blossom server to mirror to
    ///   - sha256Hex: SHA256 hash of the blob (for authorization)
    ///   - keypair: User's keypair for authorization
    /// - Returns: Mirror result with blob descriptor or error
    func mirror(
        sourceURL: String,
        to targetServer: BlossomServerURL,
        sha256Hex: String,
        keypair: Keypair
    ) async -> BlossomUploadResult {
        // Create Blossom authorization event for the mirror
        guard let authBase64 = create_blossom_upload_auth(keypair: keypair, sha256Hex: sha256Hex) else {
            return .failed(.authenticationFailed)
        }

        // Build the mirror request per BUD-04
        let mirrorURL = targetServer.url.appendingPathComponent("mirror")
        var request = URLRequest(url: mirrorURL)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(blossom_authorization_header(authBase64), forHTTPHeaderField: "Authorization")

        // Request body is JSON with the source URL
        let body: [String: String] = ["url": sourceURL]
        guard let bodyData = try? JSONEncoder().encode(body) else {
            return .failed(.invalidResponse)
        }
        request.httpBody = bodyData

        // Execute the request
        let responseData: Data
        let response: URLResponse

        do {
            (responseData, response) = try await URLSession.shared.data(for: request)
        } catch {
            return .failed(.uploadFailed(underlying: error))
        }

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            return .failed(.invalidResponse)
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            let reason = extractErrorReason(from: httpResponse, body: responseData)
            return .failed(.serverRejected(reason: reason, statusCode: httpResponse.statusCode))
        }

        // Parse blob descriptor response
        guard let descriptor = parseBlossomResponse(responseData) else {
            return .failed(.invalidResponse)
        }

        return .success(descriptor)
    }

    /// Mirrors a blob to multiple servers in the background.
    ///
    /// This is fire-and-forget - errors are logged but don't affect the caller.
    /// Used after a successful primary upload to ensure redundancy.
    ///
    /// - Parameters:
    ///   - sourceURL: The URL where the blob was uploaded (from primary server)
    ///   - sha256Hex: SHA256 hash of the blob
    ///   - targetServers: List of server URLs to mirror to
    ///   - keypair: User's keypair for authorization
    static func mirrorToServersInBackground(
        sourceURL: String,
        sha256Hex: String,
        targetServers: [BlossomServerURL],
        keypair: Keypair
    ) {
        guard !targetServers.isEmpty else { return }

        Task.detached(priority: .background) {
            let uploader = BlossomUploader()

            for server in targetServers {
                let result = await uploader.mirror(
                    sourceURL: sourceURL,
                    to: server,
                    sha256Hex: sha256Hex,
                    keypair: keypair
                )

                switch result {
                case .success(let descriptor):
                    print("[BlossomMirror] Successfully mirrored to \(server.absoluteString): \(descriptor.url)")
                case .failed(let error):
                    print("[BlossomMirror] Failed to mirror to \(server.absoluteString): \(error)")
                }
            }
        }
    }
}

//
//  BlossomUploader.swift
//  damus
//
//  Created by Claude on 2026-03-18.
//

import Foundation
import CommonCrypto

/// Uploads media to a Blossom server using BUD-02 (PUT /upload).
///
/// Unlike NIP-96 which uses POST multipart/form-data, Blossom uses
/// PUT with a raw binary body. The server returns a blob descriptor
/// with the SHA-256 hash as the content identifier.
struct BlossomUploader {

    /// Uploads a file to a Blossom server.
    ///
    /// - Parameters:
    ///   - media: The media file to upload
    ///   - server: The Blossom server URL
    ///   - keypair: The user's keypair for auth
    ///   - delegate: URLSession delegate for progress tracking
    /// - Returns: The blob descriptor from the server
    static func upload(
        media: MediaUpload,
        server: BlossomServerURL,
        keypair: Keypair,
        delegate: URLSessionTaskDelegate? = nil
    ) async throws -> BlossomBlobDescriptor {
        let fileData: Data
        do {
            fileData = try Data(contentsOf: media.localURL)
        } catch {
            throw BlossomError.fileReadError(error)
        }

        let hashHex = sha256_hex(fileData)

        guard let auth = create_blossom_auth(
            keypair: keypair,
            action: "upload",
            sha256hex: hashHex,
            fileSize: Int64(fileData.count),
            serverURL: server
        ) else {
            throw BlossomError.authError("Failed to create auth event")
        }

        var request = URLRequest(url: server.uploadURL)
        request.httpMethod = "PUT"
        request.httpBody = fileData
        request.setValue(auth, forHTTPHeaderField: "Authorization")
        request.setValue(media.mime_type, forHTTPHeaderField: "Content-Type")
        request.setValue(String(fileData.count), forHTTPHeaderField: "Content-Length")

        let (data, response) = try await URLSession.shared.data(for: request, delegate: delegate)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlossomError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw BlossomError.uploadFailed(statusCode: httpResponse.statusCode)
        }

        let descriptor = try JSONDecoder().decode(BlossomBlobDescriptor.self, from: data)

        guard descriptor.sha256 == hashHex else {
            throw BlossomError.hashMismatch(expected: hashHex, got: descriptor.sha256)
        }

        return descriptor
    }
}

/// Computes SHA-256 hash of data and returns hex-encoded string.
///
/// Uses streaming chunked reads via CommonCrypto's update API
/// to avoid doubling memory usage for large files.
func sha256_hex(_ data: Data) -> String {
    var context = CC_SHA256_CTX()
    CC_SHA256_Init(&context)

    let chunkSize = 64 * 1024 // 64 KB chunks
    data.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
            let remaining = buffer.count - offset
            let length = min(chunkSize, remaining)
            let chunk = buffer.baseAddress!.advanced(by: offset)
            CC_SHA256_Update(&context, chunk, CC_LONG(length))
            offset += length
        }
    }

    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    CC_SHA256_Final(&hash, &context)

    return hex_encode(Data(hash))
}

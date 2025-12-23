//
//  BlossomAuth.swift
//  damus
//
//  Created by Claude on 2025-01-15.
//
//  Creates kind 24242 authorization events for Blossom servers (BUD-01).
//
//  Unlike NIP-98 (kind 27235) which uses URL and method tags,
//  Blossom auth uses:
//    - ["t", action]       (e.g., "upload", "delete", "list")
//    - ["x", sha256_hex]   (hash of the blob being uploaded/referenced)
//    - ["expiration", ts]  (unix timestamp when auth expires)
//
//  The event is base64-encoded and sent in the Authorization header:
//    Authorization: Nostr <base64_encoded_event_json>
//

import Foundation

// MARK: - Blossom Authorization

/// Creates a Blossom upload authorization event (kind 24242).
///
/// The authorization event authenticates the user to the Blossom server
/// and proves they intend to upload a specific blob (identified by SHA256 hash).
///
/// - Parameters:
///   - keypair: The user's nostr keypair for signing
///   - sha256Hex: The SHA256 hash of the blob being uploaded (hex-encoded)
///   - expirationSeconds: How long until the auth expires (default 5 minutes)
/// - Returns: Base64-encoded authorization string for the HTTP header, or nil on failure
///
/// Example usage:
/// ```swift
/// guard let auth = create_blossom_upload_auth(keypair: keypair, sha256Hex: hash) else {
///     return // auth creation failed
/// }
/// request.setValue("Nostr " + auth, forHTTPHeaderField: "Authorization")
/// ```
func create_blossom_upload_auth(keypair: Keypair, sha256Hex: String, expirationSeconds: TimeInterval = 300) -> String? {
    return create_blossom_auth(
        keypair: keypair,
        action: "upload",
        sha256Hex: sha256Hex,
        expirationSeconds: expirationSeconds,
        content: "Upload blob"
    )
}

/// Creates a Blossom delete authorization event (kind 24242).
///
/// - Parameters:
///   - keypair: The user's nostr keypair for signing
///   - sha256Hex: The SHA256 hash of the blob to delete (hex-encoded)
///   - expirationSeconds: How long until the auth expires (default 5 minutes)
/// - Returns: Base64-encoded authorization string for the HTTP header, or nil on failure
func create_blossom_delete_auth(keypair: Keypair, sha256Hex: String, expirationSeconds: TimeInterval = 300) -> String? {
    return create_blossom_auth(
        keypair: keypair,
        action: "delete",
        sha256Hex: sha256Hex,
        expirationSeconds: expirationSeconds,
        content: "Delete blob"
    )
}

// MARK: - Private Implementation

/// Creates a Blossom authorization event (kind 24242) for any action.
///
/// Per BUD-01, the event must have:
/// - kind: 24242
/// - created_at: in the past (at event creation time)
/// - expiration tag: unix timestamp in the future
/// - t tag: the action verb ("upload", "delete", "list", "get")
/// - x tag(s): sha256 hash(es) of the blob(s) being referenced
/// - content: human-readable description of the action
///
/// - Parameters:
///   - keypair: The user's nostr keypair for signing
///   - action: The action verb ("upload", "delete", "list", "get")
///   - sha256Hex: The SHA256 hash of the blob (hex-encoded), nil for actions that don't need it
///   - expirationSeconds: How long until the auth expires
///   - content: Human-readable description of the action
/// - Returns: Base64-encoded authorization string, or nil on failure
private func create_blossom_auth(
    keypair: Keypair,
    action: String,
    sha256Hex: String?,
    expirationSeconds: TimeInterval,
    content: String
) -> String? {
    let now = UInt32(Date().timeIntervalSince1970)
    let expiration = UInt32(Date().timeIntervalSince1970 + expirationSeconds)

    // Build tags array
    // Required: ["t", action] and ["expiration", timestamp]
    // Optional: ["x", sha256] for upload/delete actions
    var tags: [[String]] = [
        ["t", action],
        ["expiration", String(expiration)]
    ]

    // Add the blob hash if provided (required for upload/delete)
    if let hash = sha256Hex {
        tags.append(["x", hash])
    }

    // Create the kind 24242 event
    // NdbNote handles signing automatically when given a full keypair
    guard let authNote = NdbNote(
        content: content,
        keypair: keypair,
        kind: 24242,
        tags: tags,
        createdAt: now
    ) else {
        return nil
    }

    // Encode to JSON and then base64
    // This follows the same pattern as NIP-98 auth
    guard let jsonData = try? encode_json_data(authNote) else {
        return nil
    }

    return base64_encode(jsonData.bytes)
}

// MARK: - Authorization Header Builder

/// Builds the full Authorization header value for Blossom requests.
///
/// - Parameter base64Auth: The base64-encoded authorization event
/// - Returns: The full header value in format "Nostr <base64>"
func blossom_authorization_header(_ base64Auth: String) -> String {
    return "Nostr " + base64Auth
}

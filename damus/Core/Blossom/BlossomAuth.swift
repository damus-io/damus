//
//  BlossomAuth.swift
//  damus
//
//  Created by Claude on 2026-03-18.
//

import Foundation

/// Creates a Blossom authorization header value (BUD-11).
///
/// Blossom uses kind 24242 events with action tags for auth,
/// unlike NIP-98 which uses kind 27235 with URL/method tags.
///
/// - Parameters:
///   - keypair: The user's Nostr keypair for signing
///   - action: The action being authorized ("upload", "delete", "list", "media")
///   - sha256hex: Hex-encoded SHA-256 hash of the blob (required for upload)
///   - fileSize: Size of the blob in bytes (optional, for upload)
///   - serverURL: The server URL to scope auth to (optional)
///   - expiresIn: Seconds until expiration (default: 5 minutes)
/// - Returns: The base64-encoded auth header value prefixed with "Nostr ", or nil on failure
func create_blossom_auth(
    keypair: Keypair,
    action: String,
    sha256hex: String? = nil,
    fileSize: Int64? = nil,
    serverURL: BlossomServerURL? = nil,
    expiresIn: TimeInterval = 300
) -> String? {
    let expiration = UInt64(Date().timeIntervalSince1970 + expiresIn)

    var tags: [[String]] = [
        ["t", action],
        ["expiration", String(expiration)]
    ]

    if let sha256hex {
        tags.append(["x", sha256hex])
    }

    if let fileSize {
        tags.append(["size", String(fileSize)])
    }

    if let serverURL {
        tags.append(["server", serverURL.url.absoluteString])
    }

    guard let ev = NostrEvent(
        content: "Authorize \(action)",
        keypair: keypair,
        kind: NostrKind.blossom_auth.rawValue,
        tags: tags
    ) else {
        return nil
    }

    let json = event_to_json(ev: ev)
    let base64Header = base64_encode(Array(json.utf8))
    return "Nostr " + base64Header
}

//
//  DMTypingIndicator.swift
//  damus
//
//  Created by Clawdbot on 2026-01-25.
//

import Foundation

/// Community convention: kind 20001 (ephemeral) typing indicators.
///
/// This is intentionally best-effort:
/// - Relays may drop ephemeral events
/// - Clients may ignore expiration tags
/// - Missing stop events are handled by local auto-clear timers
/// Typing indicator action payload, typically sent as a small plaintext string inside an ephemeral event.
enum DMTypingAction: String {
    case start
    case stop
}

/// Helper for creating Damus typing indicator events (kind 20001).
struct DMTypingIndicator {
    /// Nostr kind used for typing indicator events.
    static let kind: UInt32 = NostrKind.typing.rawValue

    /// Namespace tag value used to distinguish Damus typing indicator events from other clients.
    static let namespaceTagValue = "damus-typing"

    /// Creates an ephemeral typing indicator event addressed to a specific recipient.
    ///
    /// - Parameters:
    ///   - action: Whether the user started or stopped typing.
    ///   - recipient: The pubkey of the DM recipient.
    ///   - keypair: Sender keypair.
    ///   - ttlSeconds: Best-effort expiration in seconds, encoded in an `expiration` tag.
    static func makeEvent(
        action: DMTypingAction,
        to recipient: Pubkey,
        keypair: Keypair,
        ttlSeconds: UInt32 = 30
    ) -> NostrEvent? {
        let created = UInt32(Date().timeIntervalSince1970)
        let expiration: UInt32 = {
            let (sum, overflow) = created.addingReportingOverflow(ttlSeconds)
            return overflow ? UInt32.max : sum
        }()

        guard let full = keypair.to_full() else {
            return nil
        }

        let tags: [[String]] = [
            ["p", recipient.hex()],
            ["t", namespaceTagValue],
            ["expiration", String(expiration)]
        ]

        // Encrypting keeps parity with DM privacy expectations.
        return NIP04.create_encrypted_event(
            action.rawValue,
            to_pk: recipient,
            tags: tags,
            keypair: full,
            created_at: created,
            kind: kind
        )
    }
}

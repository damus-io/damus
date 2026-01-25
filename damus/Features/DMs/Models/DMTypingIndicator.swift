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
enum DMTypingAction: String {
    case start
    case stop
}

struct DMTypingIndicator {
    static let kind: UInt32 = NostrKind.typing.rawValue
    static let namespaceTagValue = "damus-typing"

    static func makeEvent(
        action: DMTypingAction,
        to recipient: Pubkey,
        keypair: Keypair,
        ttlSeconds: UInt32 = 30
    ) -> NostrEvent? {
        let created = UInt32(Date().timeIntervalSince1970)
        let expiration = created + ttlSeconds

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

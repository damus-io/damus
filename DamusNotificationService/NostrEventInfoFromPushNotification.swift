//
//  NostrEventInfoFromPushNotification.swift
//  DamusNotificationService
//
//  Created by Daniel D’Aquino on 2023-11-13.
//

import Foundation

/// The representation of a JSON-encoded Nostr Event used by the push notification server
/// Needs to match with https://gitlab.com/soapbox-pub/strfry-policies/-/raw/433459d8084d1f2d6500fdf916f22caa3b4d7be5/src/types.ts
struct NostrEventInfoFromPushNotification: Codable {
    let id: String          // Hex-encoded
    let sig: String         // Hex-encoded
    let kind: NostrKind
    let tags: [[String]]
    let pubkey: String      // Hex-encoded
    let content: String
    let created_at: Int
    
    static func from(dictionary: [AnyHashable: Any]) -> NostrEventInfoFromPushNotification? {
        guard let id = dictionary["id"] as? String,
              let sig = dictionary["sig"] as? String,
              let kind_int = dictionary["kind"] as? UInt32,
              let kind = NostrKind(rawValue: kind_int),
              let tags = dictionary["tags"] as? [[String]],
              let pubkey = dictionary["pubkey"] as? String,
              let content = dictionary["content"] as? String,
              let created_at = dictionary["created_at"] as? Int else {
            return nil
        }
        return NostrEventInfoFromPushNotification(id: id, sig: sig, kind: kind, tags: tags, pubkey: pubkey, content: content, created_at: created_at)
    }
    
    func reactionEmoji() -> String? {
        guard self.kind == NostrKind.like else {
            return nil
        }

        switch self.content {
        case "", "+":
            return "❤️"
        case "-":
            return "👎"
        default:
            return self.content
        }
    }
}

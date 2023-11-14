//
//  LocalNotification.swift
//  damus
//
//  Created by William Casarin on 2023-04-15.
//

import Foundation

struct LossyLocalNotification {
    let type: LocalNotificationType
    let mention: MentionRef

    func to_user_info() -> [AnyHashable: Any] {
        return [
            "type": self.type.rawValue,
            "id": self.mention.bech32
        ]
    }
    
    static func from_user_info(user_info: [AnyHashable: Any]) -> LossyLocalNotification? {
        if let encoded_nostr_event_push_data = user_info["nostr_event_info"] as? String {
            return self.from(encoded_nostr_event_push_data: encoded_nostr_event_push_data)
        }
        guard let id = user_info["id"] as? String,
              let target_id = MentionRef.from_bech32(str: id) else {
            return nil
        }
        let typestr = user_info["type"] as! String
        let type = LocalNotificationType(rawValue: typestr)!
        
        return LossyLocalNotification(type: type, mention: target_id)
    }
    
    static func from(encoded_nostr_event_push_data: String) -> LossyLocalNotification? {
        guard let json_data = encoded_nostr_event_push_data.data(using: .utf8),
              let nostr_event_push_data = try? JSONDecoder().decode(NostrEventInfoFromPushNotification.self, from: json_data) else {
            return nil
        }
        return self.from(nostr_event_push_data: nostr_event_push_data)
    }
    
    static func from(nostr_event_push_data: NostrEventInfoFromPushNotification) -> LossyLocalNotification? {
        guard let type = LocalNotificationType.from(nostr_kind: nostr_event_push_data.kind) else { return nil }
        guard let note_id: NoteId = NoteId.init(hex: nostr_event_push_data.id) else { return nil }
        let target: MentionRef = .note(note_id)
        return LossyLocalNotification(type: type, mention: target)
    }
}

struct LocalNotification {
    let type: LocalNotificationType
    let event: NostrEvent
    let target: NostrEvent
    let content: String
    
    func to_lossy() -> LossyLocalNotification {
        return LossyLocalNotification(type: self.type, mention: .note(self.target.id))
    }
}

enum LocalNotificationType: String {
    case dm
    case like
    case mention
    case repost
    case zap
    case profile_zap
    
    static func from(nostr_kind: NostrKind) -> Self? {
        switch nostr_kind {
            case .text:
                return .mention
            case .dm:
                return .dm
            case .like:
                return .like
            case .longform:
                return .mention
            case .zap:
                return .zap
            default:
                return nil
        }
    }
}

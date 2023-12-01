//
//  LocalNotification.swift
//  damus
//
//  Created by William Casarin on 2023-04-15.
//

import Foundation

let NDB_NOTE_JSON_USER_INFO_KEY = "ndb_note_json"

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
        if let encoded_ndb_note = user_info[NDB_NOTE_JSON_USER_INFO_KEY] as? String {
            return self.from(json_encoded_ndb_note: encoded_ndb_note)
        }
        guard let id = user_info["id"] as? String,
              let target_id = MentionRef.from_bech32(str: id) else {
            return nil
        }
        let typestr = user_info["type"] as! String
        let type = LocalNotificationType(rawValue: typestr)!
        
        return LossyLocalNotification(type: type, mention: target_id)
    }
    
    static func from(json_encoded_ndb_note: String) -> LossyLocalNotification? {
        guard let ndb_note = NdbNote.owned_from_json(json: json_encoded_ndb_note) else {
            return nil
        }
        return self.from(ndb_note: ndb_note)
    }
    
    static func from(ndb_note: NdbNote) -> LossyLocalNotification? {
        guard let known_kind = ndb_note.known_kind, let type = LocalNotificationType.from(nostr_kind: known_kind) else { return nil }
        let target: MentionRef = .note(ndb_note.id)
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

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
              let target_id = MentionRef(bech32_str: id) else {
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
        guard let type = LocalNotificationType.from(note: ndb_note) else {
            return nil
        }
        let target: MentionRef = .init(nip19: .note(ndb_note.id))
        return LossyLocalNotification(type: type, mention: target)
    }
}

enum NotificationTarget {
    case note(NostrEvent)
    case note_id(NoteId)

    var id: NoteId {
        switch self {
        case .note(let note):
            return note.id
        case .note_id(let id):
            return id
        }
    }
}

struct LocalNotification {
    let type: LocalNotificationType
    let event: NostrEvent
    let target: NotificationTarget
    let content: String
    
    func to_lossy() -> LossyLocalNotification {
        return LossyLocalNotification(type: self.type, mention: .init(nip19: .note(self.target.id)))
    }
}

enum LocalNotificationType: String {
    case dm
    case like
    case mention
    case reply
    case tagged
    case repost
    case zap
    case profile_zap
    /// A reply that reached us inside a gift wrap — see ``NdbNote/is_private_reply``.
    ///
    /// Distinct from ``reply`` because the two are the same *kind* and must not read the same on a
    /// lock screen: one is a public note anyone can already see, the other is a secret of the same
    /// class as a DM. Distinct from ``dm`` because it belongs to a thread rather than to a
    /// conversation, so it opens in the notifications tab and not the DM list.
    case private_reply

    /// The notification a note warrants, given what the note *is* rather than only what kind it is.
    ///
    /// Prefer this to ``from(nostr_kind:)``: kind 1 is two different things depending on
    /// ``NdbNote/is_rumor``, and the kind alone cannot tell a private reply from a public mention.
    static func from(note: NdbNote) -> Self? {
        if note.is_private_reply { return .private_reply }
        guard let known_kind = note.known_kind else { return nil }
        return from(nostr_kind: known_kind)
    }

    static func from(nostr_kind: NostrKind) -> Self? {
        switch nostr_kind {
            case .text:
                return .mention
            case .dm, .private_dm:
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

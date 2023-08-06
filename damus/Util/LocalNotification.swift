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
        guard let id = user_info["id"] as? String,
              let target_id = MentionRef.from_bech32(str: id) else {
            return nil
        }
        let typestr = user_info["type"] as! String
        let type = LocalNotificationType(rawValue: typestr)!
        
        return LossyLocalNotification(type: type, mention: target_id)
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
}

//
//  LocalNotification.swift
//  damus
//
//  Created by William Casarin on 2023-04-15.
//

import Foundation

struct LossyLocalNotification {
    let type: LocalNotificationType
    let event_id: String
    
    func to_user_info() -> [AnyHashable: Any] {
        return [
            "type": self.type.rawValue,
            "evid": self.event_id
        ]
    }
    
    static func from_user_info(user_info: [AnyHashable: Any]) -> LossyLocalNotification {
        let target_id = user_info["evid"] as! String
        let typestr = user_info["type"] as! String
        let type = LocalNotificationType(rawValue: typestr)!
        
        return LossyLocalNotification(type: type, event_id: target_id)
    }
}

struct LocalNotification {
    let type: LocalNotificationType
    let event: NostrEvent
    let target: NostrEvent
    let content: String
    
    func to_lossy() -> LossyLocalNotification {
        return LossyLocalNotification(type: self.type, event_id: self.target.id)
    }
}

enum LocalNotificationType: String {
    case dm
    case like
    case mention
    case repost
    case zap
}

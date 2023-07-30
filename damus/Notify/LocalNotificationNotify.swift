//
//  LocalNotificationNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct LocalNotificationNotify: Notify {
    typealias Payload = LossyLocalNotification
    var payload: Payload
}

extension NotifyHandler {
    static var local_notification: NotifyHandler<LocalNotificationNotify> {
        .init()
    }
}

extension Notifications {
    static func local_notification(_ payload: LossyLocalNotification) -> Notifications<LocalNotificationNotify> {
        .init(.init(payload: payload))
    }
}

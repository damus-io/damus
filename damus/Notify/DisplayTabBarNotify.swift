//
//  DisplayTabBarNotify.swift
//  damus
//
//  Created by William Casarin on 2023-12-01.
//

import Foundation

struct DisplayTabBarNotify: Notify {
    typealias Payload = Bool
    var payload: Payload
}

extension NotifyHandler {
    static var display_tabbar: NotifyHandler<DisplayTabBarNotify> {
        .init()
    }
}

extension Notifications {
    static func display_tabbar(_ payload: Bool) -> Notifications<DisplayTabBarNotify> {
        .init(.init(payload: payload))
    }
}

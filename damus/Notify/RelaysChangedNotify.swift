//
//  RelaysChangedNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct RelaysChangedNotify: Notify {
    typealias Payload = ()
    var payload: Payload
}

extension NotifyHandler {
    static var relays_changed: NotifyHandler<RelaysChangedNotify> {
        .init()
    }
}

extension Notifications {
    static var relays_changed: Notifications<RelaysChangedNotify> {
        .init(.init(payload: ()))
    }
}


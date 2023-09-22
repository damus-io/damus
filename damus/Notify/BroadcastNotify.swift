//
//  BroadcastEventNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct BroadcastNotify: Notify {
    typealias Payload = NostrEvent
    var payload: Payload
}

extension NotifyHandler {
    static var broadcast: NotifyHandler<BroadcastNotify> {
        .init()
    }
}

extension Notifications {
    static func broadcast(_ event: NostrEvent) -> Notifications<BroadcastNotify> {
        .init(.init(payload: event))
    }
}

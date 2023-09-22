//
//  ZappingNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct ZappingNotify: Notify {
    typealias Payload = ZappingEvent
    var payload: Payload
}

extension NotifyHandler {
    static var zapping: NotifyHandler<ZappingNotify> {
        NotifyHandler<ZappingNotify>()
    }
}

extension Notifications {
    static func zapping(_ event: ZappingEvent) -> Notifications<ZappingNotify> {
        .init(.init(payload: event))
    }
}


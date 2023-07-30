//
//  UnmuteThreadNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct UnmuteThreadNotify: Notify {
    typealias Payload = NostrEvent
    var payload: Payload
}

extension NotifyHandler {
    static var unmute_thread: NotifyHandler<UnmuteThreadNotify> {
        .init()
    }
}

extension Notifications {
    static func unmute_thread(_ note: NostrEvent) -> Notifications<UnmuteThreadNotify> {
        .init(.init(payload: note))
    }
}


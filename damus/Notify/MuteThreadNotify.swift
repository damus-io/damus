//
//  MuteThreadNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct MuteThreadNotify: Notify {
    typealias Payload = NostrEvent
    var payload: Payload
}

extension NotifyHandler {
    static var mute_thread: NotifyHandler<MuteThreadNotify> {
        .init()
    }
}

extension Notifications {
    static func mute_thread(_ note: NostrEvent) -> Notifications<MuteThreadNotify> {
        .init(.init(payload: note))
    }
}


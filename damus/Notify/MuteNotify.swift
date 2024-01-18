//
//  MuteNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct MuteNotify: Notify {
    typealias Payload = MuteItem
    var payload: MuteItem
}

extension NotifyHandler {
    static var mute: NotifyHandler<MuteNotify> {
        NotifyHandler<MuteNotify>()
    }
}

extension Notifications {
    static func mute(_ target: MuteItem) -> Notifications<MuteNotify> {
        .init(.init(payload: target))
    }
}


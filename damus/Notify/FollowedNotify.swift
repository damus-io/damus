//
//  FollowedNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct FollowedNotify: Notify {
    typealias Payload = FollowRef
    var payload: FollowRef
}

extension NotifyHandler {
    static var followed: NotifyHandler<FollowedNotify> {
        .init()
    }
}

extension Notifications {
    static func followed(_ ref: FollowRef) -> Notifications<FollowedNotify> {
        .init(.init(payload: ref))
    }
}

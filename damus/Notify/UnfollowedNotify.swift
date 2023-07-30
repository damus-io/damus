//
//  UnfollowedNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct UnfollowedNotify: Notify {
    typealias Payload = FollowRef
    var payload: Payload
}

extension NotifyHandler {
    static var unfollowed: NotifyHandler<UnfollowedNotify> {
        .init()
    }
}

extension Notifications {
    static func unfollowed(_ payload: FollowRef) -> Notifications<UnfollowedNotify> {
        .init(.init(payload: payload))
    }
}

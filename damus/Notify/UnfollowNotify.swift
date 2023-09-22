//
//  UnfollowNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

/// Notification sent when an unfollow action is initiatied. Not to be confused with unfollowed
struct UnfollowNotify: Notify {
    typealias Payload = FollowTarget
    var payload: Payload
}

extension NotifyHandler {
    static var unfollow: NotifyHandler<UnfollowNotify> {
        .init()
    }
}

extension Notifications {
    static func unfollow(_ target: FollowTarget) -> Notifications<UnfollowNotify> {
        .init(.init(payload: target))
    }
}

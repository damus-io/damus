//
//  FollowNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct FollowNotify: Notify {
    typealias Payload = FollowTarget
    var payload: Payload
}

extension NotifyHandler {
    static var follow: NotifyHandler<FollowNotify> {
        NotifyHandler<FollowNotify>()
    }
}

extension Notifications {
    static func follow(_ target: FollowTarget) -> Notifications<FollowNotify> {
        .init(.init(payload: target))
    }
}


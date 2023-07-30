//
//  LikedNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct LikedNotify: Notify {
    typealias Payload = Counted
    var payload: Counted
}

extension NotifyHandler {
    static var liked: NotifyHandler<LikedNotify> {
        .init()
    }
}

extension Notifications {
    static func liked(_ counted: Counted) -> Notifications<LikedNotify> {
        .init(.init(payload: counted))
    }
}



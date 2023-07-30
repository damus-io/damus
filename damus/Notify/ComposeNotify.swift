//
//  ComposeNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct ComposeNotify: Notify {
    typealias Payload = PostAction
    var payload: Payload
}

extension NotifyHandler {
    static var compose: NotifyHandler<ComposeNotify> {
        .init()
    }
}

extension Notifications {
    static func compose(_ payload: PostAction) -> Notifications<ComposeNotify> {
        .init(.init(payload: payload))
    }
}

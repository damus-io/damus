//
//  PostNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct PostNotify: Notify {
    typealias Payload = NostrPostResult
    var payload: NostrPostResult
}

extension NotifyHandler {
    static var post: NotifyHandler<PostNotify> {
        .init()
    }
}

extension Notifications {
    static func post(_ result: NostrPostResult) -> Notifications<PostNotify> {
        .init(.init(payload: result))
    }
}

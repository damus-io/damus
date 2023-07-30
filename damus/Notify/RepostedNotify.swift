//
//  BoostedNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct RepostedNotify: Notify {
    typealias Payload = Counted
    var payload: Payload
}

extension NotifyHandler {
    static var reposted: NotifyHandler<RepostedNotify> {
        .init()
    }
}

extension Notifications {
    static func reposted(_ counts: Counted) -> Notifications<RepostedNotify> {
        .init(.init(payload: counts))
    }
}

